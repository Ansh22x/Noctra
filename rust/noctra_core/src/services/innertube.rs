//! InnerTube Direct Stream Resolver & Radio Generator.
//!
//! Direct 1:1 Rust native port of `NoctraNativeStreamEngine.kt`.
//! Uses pre-authenticated client emulation (VISIONOS & ANDROID_VR) to extract
//! unthrottled 320k/Opus direct CDN audio streams without signature deciphering.

use reqwest::header::{HeaderMap, HeaderValue, ORIGIN, REFERER, USER_AGENT};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::time::Duration;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RadioTrack {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub duration: String,
    pub thumbnail: String,
}

struct InnerTubeClient {
    client_name: &'static str,
    client_version: &'static str,
    client_id: &'static str,
    user_agent: &'static str,
    os_name: Option<&'static str>,
    os_version: Option<&'static str>,
    device_make: Option<&'static str>,
    device_model: Option<&'static str>,
    android_sdk_version: Option<u32>,
}

pub struct InnerTubeService {
    http: reqwest::Client,
}

impl Default for InnerTubeService {
    fn default() -> Self {
        Self::new()
    }
}

impl InnerTubeService {
    pub fn new() -> Self {
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(6))
            .build()
            .unwrap_or_default();
        Self { http: client }
    }

    /// Extracts direct CDN audio stream URL for a YouTube Music video ID.
    ///
    /// Tries VISIONOS first (direct pre-signed Opus/AAC streams), then ANDROID_VR.
    pub async fn extract_stream(&self, video_id: &str) -> Option<String> {
        if video_id.len() != 11 {
            return None;
        }

        let clients = [
            InnerTubeClient {
                client_name: "VISIONOS",
                client_version: "0.1",
                client_id: "101",
                user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                os_name: Some("visionOS"),
                os_version: Some("1.3.21O771"),
                device_make: Some("Apple"),
                device_model: Some("RealityDevice14,1"),
                android_sdk_version: None,
            },
            InnerTubeClient {
                client_name: "ANDROID_VR",
                client_version: "1.65.10",
                client_id: "28",
                user_agent: "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
                os_name: Some("Android"),
                os_version: Some("12L"),
                device_make: Some("Oculus"),
                device_model: Some("Quest 3"),
                android_sdk_version: Some(32),
            },
        ];

        for client in &clients {
            let mut client_obj = json!({
                "clientName": client.client_name,
                "clientVersion": client.client_version,
            });

            if let Some(os) = client.os_name {
                client_obj["osName"] = json!(os);
            }
            if let Some(v) = client.os_version {
                client_obj["osVersion"] = json!(v);
            }
            if let Some(m) = client.device_make {
                client_obj["deviceMake"] = json!(m);
            }
            if let Some(m) = client.device_model {
                client_obj["deviceModel"] = json!(m);
            }
            if let Some(sdk) = client.android_sdk_version {
                client_obj["androidSdkVersion"] = json!(sdk);
            }

            let body = json!({
                "videoId": video_id,
                "context": {
                    "client": client_obj
                }
            });

            let mut headers = HeaderMap::new();
            headers.insert("X-Goog-Api-Format-Version", HeaderValue::from_static("1"));
            if let Ok(val) = HeaderValue::from_str(client.client_id) {
                headers.insert("X-YouTube-Client-Name", val);
            }
            if let Ok(val) = HeaderValue::from_str(client.client_version) {
                headers.insert("X-YouTube-Client-Version", val);
            }
            headers.insert(ORIGIN, HeaderValue::from_static("https://music.youtube.com"));
            headers.insert(REFERER, HeaderValue::from_static("https://music.youtube.com/"));
            if let Ok(ua) = HeaderValue::from_str(client.user_agent) {
                headers.insert(USER_AGENT, ua);
            }

            let resp = self
                .http
                .post("https://music.youtube.com/youtubei/v1/player")
                .headers(headers)
                .json(&body)
                .send()
                .await;

            let Ok(response) = resp else { continue };
            let Ok(root) = response.json::<Value>().await else { continue };

            // Check playability
            let status = root
                .pointer("/playabilityStatus/status")
                .and_then(|s| s.as_str())
                .unwrap_or("");

            if status != "OK" {
                let reason = root
                    .pointer("/playabilityStatus/reason")
                    .and_then(|r| r.as_str())
                    .unwrap_or("")
                    .to_lowercase();

                if reason.contains("sign in")
                    || reason.contains("age")
                    || reason.contains("unavailable")
                    || reason.contains("not available")
                {
                    return None;
                }
                continue;
            }

            // Extract adaptiveFormats
            let formats = root
                .pointer("/streamingData/adaptiveFormats")
                .and_then(|f| f.as_array());

            let Some(formats) = formats else { continue };

            let mut best_url: Option<String> = None;
            let mut max_score = -1i64;

            for f in formats {
                let mime = f.get("mimeType").and_then(|m| m.as_str()).unwrap_or("").to_lowercase();
                let url = f.get("url").and_then(|u| u.as_str()).unwrap_or("");
                let bitrate = f.get("bitrate").and_then(|b| b.as_i64()).unwrap_or(0);

                if mime.contains("audio") && url.starts_with("https://") {
                    let is_opus = mime.contains("opus") || mime.contains("webm");
                    let score = bitrate + if is_opus { 64000 } else { 0 };
                    if score > max_score {
                        max_score = score;
                        best_url = Some(url.to_string());
                    }
                }
            }

            if let Some(url) = best_url {
                return Some(url);
            }
        }

        None
    }

    /// Fetches algorithmic radio recommendations seeded from a video ID.
    pub async fn fetch_radio_tracks(&self, video_id: &str) -> Vec<RadioTrack> {
        let mut list = Vec::new();

        let body = json!({
            "videoId": video_id,
            "context": {
                "client": {
                    "clientName": "WEB_REMIX",
                    "clientVersion": "1.20260213.01.00",
                    "hl": "en",
                    "gl": "US"
                }
            }
        });

        let resp = self
            .http
            .post("https://music.youtube.com/youtubei/v1/next")
            .json(&body)
            .send()
            .await;

        let Ok(response) = resp else { return list };
        let Ok(root) = response.json::<Value>().await else { return list };

        let contents = root
            .pointer("/contents/singleColumnMusicWatchNextResultsRenderer/tabbedRenderer/watchNextTabbedResultsRenderer/tabs/0/tabRenderer/content/musicQueueRenderer/content/playlistPanelRenderer/contents")
            .and_then(|c| c.as_array());

        let Some(contents) = contents else { return list };

        for item in contents {
            let Some(video_renderer) = item.get("playlistPanelVideoRenderer") else { continue };

            let vid = video_renderer.get("videoId").and_then(|v| v.as_str()).unwrap_or("");
            let title = video_renderer
                .pointer("/title/runs/0/text")
                .and_then(|t| t.as_str())
                .unwrap_or("");
            let artist = video_renderer
                .pointer("/longBylineText/runs/0/text")
                .and_then(|a| a.as_str())
                .unwrap_or("YouTube Music");
            let duration = video_renderer
                .pointer("/lengthText/runs/0/text")
                .and_then(|d| d.as_str())
                .unwrap_or("3:30");

            if !vid.is_empty() && !title.is_empty() {
                list.push(RadioTrack {
                    id: vid.to_string(),
                    title: title.to_string(),
                    artist: artist.to_string(),
                    duration: duration.to_string(),
                    thumbnail: format!("https://i.ytimg.com/vi/{vid}/hqdefault.jpg"),
                });
            }
        }

        list
    }
}
