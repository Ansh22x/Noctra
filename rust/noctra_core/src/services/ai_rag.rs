//! 16-Axis Keyword Scoring, Knowledge Graph, and Hybrid Dense RAG Re-Ranker.
//!
//! Bit-accurate Rust port of Noctra's AI RAG heuristic engine.

use md5::{Digest, Md5};
use serde_json::Value;
use std::collections::HashMap;

pub const AXIS_KEYS: [&str; 16] = [
    "dark_tone", "ambient_depth", "energy", "chill_factor",
    "melancholy", "acoustic_warmth", "electronic", "vocal_presence",
    "harmonic_density", "analog_synth", "night_drive", "cognitive_focus",
    "uplift", "sub_bass_weight", "rhythm_tempo", "instrumental",
];

pub fn generate_16axis_vector(text: &str) -> [f64; 16] {
    let lower = text.to_lowercase();
    let mut vec = [0.5f64; 16];

    let weights: [(&str, usize, f64); 34] = [
        ("dark", 0, 0.4), ("noir", 0, 0.45), ("night", 10, 0.4), ("midnight", 10, 0.45),
        ("ambient", 1, 0.4), ("drone", 1, 0.45), ("space", 1, 0.35),
        ("energy", 2, 0.4), ("hype", 2, 0.45), ("fast", 14, 0.4), ("dance", 2, 0.35),
        ("chill", 3, 0.4), ("lofi", 3, 0.45), ("relax", 3, 0.4), ("calm", 3, 0.35),
        ("sad", 4, 0.4), ("melancholy", 4, 0.45), ("heartbreak", 4, 0.4),
        ("acoustic", 5, 0.45), ("piano", 5, 0.35), ("guitar", 5, 0.35), ("unplugged", 5, 0.4),
        ("electronic", 6, 0.45), ("synth", 9, 0.45), ("synthwave", 9, 0.45), ("edm", 6, 0.4),
        ("vocal", 7, 0.4), ("sing", 7, 0.35), ("choir", 7, 0.4),
        ("harmonic", 8, 0.4), ("complex", 8, 0.35), ("orchestra", 8, 0.4),
        ("drive", 10, 0.45), ("cruising", 10, 0.4),
    ];

    for (word, axis_idx, boost) in weights {
        if lower.contains(word) {
            vec[axis_idx] = (vec[axis_idx] + boost).min(1.0);
        }
    }

    // Deterministic hash perturbation
    let mut hasher = Md5::new();
    hasher.update(text.as_bytes());
    let h_bytes = hasher.finalize();

    for i in 0..16 {
        let byte_val = h_bytes[i % h_bytes.len()];
        let perturbation = (((byte_val % 4) as f64) - 1.5) * 0.04;
        vec[i] = (vec[i] + perturbation).clamp(0.05, 0.95);
    }

    vec
}

pub fn cosine_similarity(v1: &[f64], v2: &[f64]) -> f64 {
    if v1.len() < 16 || v2.len() < 16 {
        return 0.5;
    }
    let mut dot = 0.0;
    let mut norm_a = 0.0;
    let mut norm_b = 0.0;

    for i in 0..16 {
        dot += v1[i] * v2[i];
        norm_a += v1[i] * v1[i];
        norm_b += v2[i] * v2[i];
    }

    let norm_product = norm_a.sqrt() * norm_b.sqrt();
    if norm_product == 0.0 {
        return 0.5;
    }

    (dot / norm_product).clamp(0.0, 1.0)
}

pub fn query_knowledge_graph_context(seed_text: &str) -> HashMap<String, Value> {
    let lower = seed_text.to_lowercase();
    let mut expanded: Vec<String> = Vec::new();
    let mut mood = "universal".to_string();

    let kg: [(&str, &[&str], &str); 8] = [
        ("synthwave", &["retrowave", "outrun", "cyberpunk", "dark electro"], "night_drive"),
        ("lofi", &["chillhop", "ambient jazz", "bedroom pop"], "chill_factor"),
        ("bollywood", &["filmi", "sufi", "romantic ballad", "desi pop"], "acoustic_warmth"),
        ("pop", &["dance pop", "synth pop", "indie pop"], "uplift"),
        ("classical", &["neo-classical", "orchestral", "piano solo"], "cognitive_focus"),
        ("electronic", &["techno", "house", "trance", "dnb"], "electronic"),
        ("rock", &["alternative", "indie rock", "post-rock", "grunge"], "energy"),
        ("hiphop", &["trap", "boom bap", "conscious hip hop"], "sub_bass_weight"),
    ];

    for (genre, related, genre_mood) in kg {
        if lower.contains(genre) || related.iter().any(|r| lower.contains(r)) {
            for &r in related {
                expanded.push(r.to_string());
            }
            mood = genre_mood.to_string();
        }
    }

    let mut map = HashMap::new();
    map.insert("seed".to_string(), Value::String(seed_text.to_string()));
    map.insert("expanded_clusters".to_string(), serde_json::to_value(expanded).unwrap());
    map.insert("dominant_mood".to_string(), Value::String(mood));
    map
}

pub fn hybrid_dense_rag_rerank(
    query: &str,
    mut candidates: Vec<Value>,
    user_taste_vector: Option<&[f64]>,
) -> Vec<Value> {
    let query_vector = generate_16axis_vector(query);

    let mut scored: Vec<(f64, Value)> = candidates
        .drain(..)
        .map(|c| {
            let title = c.get("title").and_then(|t| t.as_str()).unwrap_or("");
            let artist = c.get("artist").and_then(|a| a.as_str()).unwrap_or("");
            let genre = c.get("genre").and_then(|g| g.as_str()).unwrap_or("");
            let item_text = format!("{} {} {}", title, artist, genre);
            let item_vec = generate_16axis_vector(&item_text);

            let query_sim = cosine_similarity(&query_vector, &item_vec);
            let final_score = if let Some(taste) = user_taste_vector {
                let taste_sim = cosine_similarity(taste, &item_vec);
                0.6 * query_sim + 0.4 * taste_sim
            } else {
                query_sim
            };

            (final_score, c)
        })
        .collect();

    // Sort descending by score
    scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
    scored.into_iter().map(|(_, item)| item).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_16axis_vector_generation() {
        let v = generate_16axis_vector("Late Night Synthwave Drive with deep bass");
        assert_eq!(v.len(), 16);
        for &val in &v {
            assert!(val >= 0.0 && val <= 1.0);
        }
        // Night Drive (axis 10) and Analog Synth (axis 9) should be boosted
        assert!(v[10] > 0.6);
        assert!(v[9] > 0.6);
    }

    #[test]
    fn test_cosine_similarity() {
        let v1 = [1.0f64; 16];
        let v2 = [1.0f64; 16];
        let sim = cosine_similarity(&v1, &v2);
        assert!((sim - 1.0).abs() < 1e-4);

        let mut v3 = [0.0f64; 16];
        v3[0] = 1.0;
        let mut v4 = [0.0f64; 16];
        v4[1] = 1.0;
        let sim_ortho = cosine_similarity(&v3, &v4);
        assert!((sim_ortho - 0.0).abs() < 1e-4);
    }

    #[test]
    fn test_knowledge_graph_expansion() {
        let kg = query_knowledge_graph_context("synthwave");
        let clusters = kg.get("expanded_clusters").unwrap().as_array().unwrap();
        let clusters_str: Vec<&str> = clusters.iter().map(|v| v.as_str().unwrap()).collect();
        assert!(clusters_str.contains(&"retrowave"));
        assert!(clusters_str.contains(&"outrun"));
        assert_eq!(kg.get("dominant_mood").unwrap().as_str().unwrap(), "night_drive");
    }
}
