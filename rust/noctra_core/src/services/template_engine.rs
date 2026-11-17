//! Declarative, self-healing HTTP API template engine inspired by `api-anything`.
//!
//! Replaces hardcoded, brittle API scrapers with declarative request templates,
//! parameter interpolation, JSONPath response extraction, and automated fallback cascading.

use reqwest::{header::{HeaderMap, HeaderName, HeaderValue}, Client};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::time::Duration;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EndpointTemplate {
    pub url: String,
    #[serde(default = "default_method")]
    pub method: String,
    #[serde(default)]
    pub headers: HashMap<String, String>,
    #[serde(default)]
    pub params: HashMap<String, String>,
    #[serde(default)]
    pub body: Option<Value>,
    #[serde(default)]
    pub timeout_ms: Option<u64>,
    #[serde(default)]
    pub fallbacks: Vec<String>,
}

fn default_method() -> String {
    "GET".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemplateRegistry {
    #[serde(default)]
    pub version: Option<String>,
    pub operations: HashMap<String, EndpointTemplate>,
}

pub struct TemplateEngine {
    client: Client,
    registry: Arc<RwLock<HashMap<String, EndpointTemplate>>>,
}

impl Default for TemplateEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl TemplateEngine {
    pub fn new() -> Self {
        let client = Client::builder()
            .timeout(Duration::from_secs(12))
            .pool_max_idle_per_host(10)
            .build()
            .unwrap_or_else(|_| Client::new());

        Self {
            client,
            registry: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Load or update the template registry from a JSON string.
    pub fn load_registry_json(&self, json_str: &str) -> Result<usize, String> {
        let parsed: Result<TemplateRegistry, _> = serde_json::from_str(json_str);
        match parsed {
            Ok(reg) => {
                let mut map = self.registry.write().map_err(|e| e.to_string())?;
                let count = reg.operations.len();
                for (k, v) in reg.operations {
                    map.insert(k, v);
                }
                Ok(count)
            }
            Err(_) => {
                // Also accept direct HashMap<String, EndpointTemplate>
                let direct: HashMap<String, EndpointTemplate> = serde_json::from_str(json_str)
                    .map_err(|e| format!("Failed to parse endpoint templates: {}", e))?;
                let mut map = self.registry.write().map_err(|e| e.to_string())?;
                let count = direct.len();
                for (k, v) in direct {
                    map.insert(k, v);
                }
                Ok(count)
            }
        }
    }

    /// Check if an operation exists in the registry.
    pub fn has_operation(&self, operation_id: &str) -> bool {
        if let Ok(map) = self.registry.read() {
            map.contains_key(operation_id)
        } else {
            false
        }
    }

    /// Interpolate `{{param}}` and `{{param|default:val}}` tokens with provided variables.
    pub fn interpolate(pattern: &str, vars: &HashMap<String, Value>) -> String {
        let mut result = pattern.to_string();
        let re_open = "{{";
        let re_close = "}}";

        while let Some(start_idx) = result.find(re_open) {
            if let Some(end_idx) = result[start_idx..].find(re_close) {
                let actual_end = start_idx + end_idx;
                let token = &result[start_idx + 2..actual_end].trim();

                let (var_name, default_val) = if let Some(pipe_idx) = token.find("|default:") {
                    let name = token[..pipe_idx].trim();
                    let def = token[pipe_idx + 9..].trim();
                    (name, Some(def))
                } else {
                    (*token, None)
                };

                let replacement = match vars.get(var_name) {
                    Some(Value::String(s)) => s.clone(),
                    Some(Value::Number(n)) => n.to_string(),
                    Some(Value::Bool(b)) => b.to_string(),
                    Some(other) => other.to_string(),
                    None => default_val.unwrap_or("").to_string(),
                };

                result.replace_range(start_idx..actual_end + 2, &replacement);
            } else {
                break;
            }
        }

        result
    }

    /// Execute an operation template with fallback support.
    pub async fn execute(
        &self,
        operation_id: &str,
        params: &HashMap<String, Value>,
    ) -> Result<Value, String> {
        let template = {
            let map = self.registry.read().map_err(|e| e.to_string())?;
            map.get(operation_id)
                .cloned()
                .ok_or_else(|| format!("Operation '{}' not found in registry", operation_id))?
        };

        match self.execute_single(&template, params).await {
            Ok(val) => Ok(val),
            Err(primary_err) => {
                // Try fallback cascade if defined
                for fallback_id in &template.fallbacks {
                    if let Ok(fallback_val) = Box::pin(self.execute(fallback_id, params)).await {
                        return Ok(json!({
                            "status": "fallback_success",
                            "fallback_operation": fallback_id,
                            "data": fallback_val
                        }));
                    }
                }
                Err(format!("Operation '{}' failed: {}", operation_id, primary_err))
            }
        }
    }

    async fn execute_single(
        &self,
        template: &EndpointTemplate,
        vars: &HashMap<String, Value>,
    ) -> Result<Value, String> {
        let url = Self::interpolate(&template.url, vars);
        let method = template.method.to_uppercase();

        let mut req_builder = match method.as_str() {
            "POST" => self.client.post(&url),
            "PUT" => self.client.put(&url),
            "DELETE" => self.client.delete(&url),
            "HEAD" => self.client.head(&url),
            _ => self.client.get(&url),
        };

        // Headers
        let mut header_map = HeaderMap::new();
        for (k, v) in &template.headers {
            let val = Self::interpolate(v, vars);
            if let (Ok(name), Ok(val)) = (HeaderName::from_bytes(k.as_bytes()), HeaderValue::from_str(&val)) {
                header_map.insert(name, val);
            }
        }
        req_builder = req_builder.headers(header_map);

        // Query params
        let mut query_params = Vec::new();
        for (k, v) in &template.params {
            let val = Self::interpolate(v, vars);
            if !val.is_empty() {
                query_params.push((k.clone(), val));
            }
        }
        if !query_params.is_empty() {
            req_builder = req_builder.query(&query_params);
        }

        // Timeout override
        if let Some(ms) = template.timeout_ms {
            req_builder = req_builder.timeout(Duration::from_millis(ms));
        }

        // Body if present
        if let Some(body_val) = &template.body {
            req_builder = req_builder.json(body_val);
        }

        let resp = req_builder.send().await.map_err(|e| e.to_string())?;
        if !resp.status().is_success() {
            return Err(format!("HTTP error status: {}", resp.status()));
        }

        let json_body: Value = resp.json().await.map_err(|e| format!("Failed to parse response JSON: {}", e))?;
        Ok(json_body)
    }
}

// Global thread-safe singleton
static GLOBAL_TEMPLATE_ENGINE: std::sync::OnceLock<TemplateEngine> = std::sync::OnceLock::new();

pub fn get_global_template_engine() -> &'static TemplateEngine {
    GLOBAL_TEMPLATE_ENGINE.get_or_init(TemplateEngine::new)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_interpolation() {
        let mut vars = HashMap::new();
        vars.insert("artist".to_string(), json!("Arijit Singh"));
        vars.insert("limit".to_string(), json!(10));

        let pattern = "https://api.music.com/search?q={{artist}}&limit={{limit|default:20}}&type={{type|default:song}}";
        let interpolated = TemplateEngine::interpolate(pattern, &vars);
        assert_eq!(interpolated, "https://api.music.com/search?q=Arijit Singh&limit=10&type=song");
    }

    #[test]
    fn test_registry_loading() {
        let engine = TemplateEngine::new();
        let spec = r#"{
            "operations": {
                "test_op": {
                    "url": "https://api.test.com/v1/tracks",
                    "method": "GET",
                    "headers": { "Accept": "application/json" },
                    "params": { "seed": "{{seed}}" },
                    "fallbacks": ["fallback_op"]
                },
                "fallback_op": {
                    "url": "https://backup.test.com/v1/tracks",
                    "method": "GET"
                }
            }
        }"#;

        let count = engine.load_registry_json(spec).expect("Should load registry");
        assert_eq!(count, 2);
        assert!(engine.has_operation("test_op"));
        assert!(engine.has_operation("fallback_op"));
        assert!(!engine.has_operation("non_existent"));
    }
}
