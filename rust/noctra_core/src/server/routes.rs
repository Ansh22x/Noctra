//! Axum REST API Routes for Noctra Native Sidecar.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use axum::{
    body::Body,
    extract::{Path, Query, State},
    http::{header, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use futures_util::StreamExt;
use reqwest::Client;
use serde_json::{json, Value};
use tower_http::cors::{Any, CorsLayer};
use tracing::error;

use crate::services::{
    ai_rag::{generate_16axis_vector, hybrid_dense_rag_rerank},
    jiosaavn::{get_jiosaavn_trending, search_jiosaavn_music},
    lyrics::fetch_lyrics,
    musicbrainz::enrich_metadata,
    spotify::{get_dynamic_spotify_charts, SPOTIFY_CHARTS},
};

pub struct AppState {
    pub client: Client,
}

const TRUSTED_STREAM_HOSTS: [&str; 6] = [
    "saavncdn.com",
    "jiosaavn.com",
    "googlevideo.com",
    "youtube.com",
    "ytimg.com",
    "jamendo.com",
];

fn is_trusted_stream_url(stream_url: &str) -> bool {
    let Ok(parsed) = url::Url::parse(stream_url) else {
        return false;
    };
    if parsed.scheme() != "https" {
        return false;
    }
    let Some(host) = parsed.host_str() else {
        return false;
    };
    let host_lower = host.to_lowercase();
    TRUSTED_STREAM_HOSTS
        .iter()
        .any(|&domain| host_lower == domain || host_lower.ends_with(&format!(".{}", domain)))
}

fn bounded_limit(query: &HashMap<String, String>, default: usize) -> usize {
    query
        .get("limit")
        .and_then(|l| l.parse::<usize>().ok())
        .unwrap_or(default)
        .clamp(1, 50)
}

pub fn create_router() -> Router {
    let client = Client::builder()
        .timeout(std::time::Duration::from_secs(15))
        .build()
        .expect("Failed to build HTTP client");

    let state = Arc::new(AppState { client });

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    Router::new()
        .route("/", get(health_handler))
        .route("/health", get(health_handler))
        .route("/api/search", get(search_handler))
        .route("/api/trending", get(trending_handler))
        .route("/api/vibe_feed", get(vibe_feed_handler))
        .route("/api/ai_radio", get(ai_radio_handler))
        .route("/api/vibe_curate", post(vibe_curate_handler))
        .route("/api/spotify/charts", get(spotify_charts_handler))
        .route("/api/spotify/oembed", get(spotify_oembed_handler))
        .route("/api/metadata/enrich", get(metadata_enrich_handler))
        .route("/api/lyrics", get(lyrics_handler))
        .route("/api/ml/vectorize", post(vectorize_handler))
        .route("/api/stream/{video_id}", get(stream_handler))
        .route("/api/proxy_stream", get(proxy_stream_handler))
        .route("/api/download", post(download_handler))
        .layer(cors)
        .with_state(state)
}

async fn health_handler() -> impl IntoResponse {
    Json(json!({
        "status": "online",
        "service": "Noctra High-Performance Native Rust Core",
        "version": "1.0.0",
        "ai_rag": "active",
        "engine": "Rust / Axum",
        "endpoints": [
            "/api/search",
            "/api/trending",
            "/api/vibe_feed",
            "/api/ai_radio",
            "/api/vibe_curate",
            "/api/spotify/charts",
            "/api/spotify/oembed",
            "/api/metadata/enrich",
            "/api/lyrics",
            "/api/stream/<id>",
            "/api/proxy_stream",
            "/api/download",
            "/api/ml/vectorize"
        ]
    }))
}

async fn search_handler(
    State(state): State<Arc<AppState>>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let query = params.get("q").map(|s| s.trim()).unwrap_or("");
    let limit = bounded_limit(&params, 15);
    if query.is_empty() {
        return Json(json!({"results": [], "query": "", "source": "all"}));
    }

    let results = search_jiosaavn_music(&state.client, query, limit).await;
    let ranked = hybrid_dense_rag_rerank(query, results, None);
    let final_res: Vec<Value> = ranked.into_iter().take(limit).collect();

    Json(json!({
        "results": final_res,
        "query": query,
        "source": "all"
    }))
}

async fn trending_handler(
    State(state): State<Arc<AppState>>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let limit = bounded_limit(&params, 20);
    let results = get_jiosaavn_trending(&state.client, limit).await;
    Json(json!({
        "trending": results.clone(),
        "results": results
    }))
}

async fn vibe_feed_handler(
    State(state): State<Arc<AppState>>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let vibe = params
        .get("vibe")
        .map(|v| v.as_str())
        .unwrap_or("late_night")
        .trim();
    let limit = bounded_limit(&params, 15);

    let vibe_map = [
        ("late_night", "Arijit Singh midnight songs"),
        ("chill_lofi", "lofi chill beats relaxing"),
        ("high_energy", "Badshah party songs dance"),
        ("dark_synth", "dark electronic ambient"),
        ("acoustic_warm", "acoustic unplugged ballad"),
        ("bollywood", "Bollywood latest romantic hits"),
        ("punjabi", "Diljit Dosanjh AP Dhillon Punjabi"),
        ("rnb_soul", "R&B soul smooth vibes"),
        ("classical", "Indian classical instrumental"),
        ("kpop", "K-Pop BTS trending"),
        ("sufi", "Sufi Nusrat Fateh Ali Khan"),
        ("workout", "workout motivation songs"),
    ];

    let query = vibe_map
        .iter()
        .find(|(k, _)| *k == vibe)
        .map(|(_, q)| *q)
        .unwrap_or(vibe);

    let candidates = search_jiosaavn_music(&state.client, query, limit * 2).await;
    let ranked = hybrid_dense_rag_rerank(vibe, candidates, None);
    let final_res: Vec<Value> = ranked.into_iter().take(limit).collect();

    Json(json!({
        "results": final_res,
        "vibe": vibe
    }))
}

async fn ai_radio_handler(
    State(state): State<Arc<AppState>>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let title = params.get("title").map(|s| s.trim()).unwrap_or("");
    let artist = params.get("artist").map(|s| s.trim()).unwrap_or("");
    let limit = bounded_limit(&params, 15);

    if title.is_empty() && artist.is_empty() {
        return Json(json!({"results": []}));
    }

    let re_noise = regex::Regex::new(r"[\(\[\{].*?[\)\]\}]").unwrap();
    let re_keywords = regex::Regex::new(r"\b(official|video|audio|lyric|lyrics|remix|lofi|slowed|reverb|hd|4k)\b").unwrap();

    let norm_title = |t: &str| -> String {
        let lower = t.to_lowercase();
        let clean = re_noise.replace_all(&lower, "");
        let clean = re_keywords.replace_all(&clean, "");
        clean.split_whitespace().collect::<Vec<_>>().join(" ")
    };

    let seed_norm = norm_title(title);
    let mut queries = Vec::new();
    if !artist.is_empty() {
        queries.push(format!("{} top songs", artist));
        queries.push(format!("{} radio", artist));
    } else {
        queries.push(format!("{} similar songs", title));
    }

    let mut all_results = Vec::new();
    let mut seen_ids = HashSet::new();
    let mut seen_norms = HashSet::new();
    if !seed_norm.is_empty() {
        seen_norms.insert(seed_norm.clone());
    }

    for q in queries {
        let fetched = search_jiosaavn_music(&state.client, &q, 12).await;
        for t in fetched {
            let tid = t.get("id").and_then(|id| id.as_str()).unwrap_or("");
            let ttitle = t.get("title").and_then(|tt| tt.as_str()).unwrap_or("");
            if tid.is_empty() || seen_ids.contains(tid) {
                continue;
            }
            let cn = norm_title(ttitle);
            if !cn.is_empty() && seen_norms.contains(&cn) {
                continue;
            }
            if !cn.is_empty() {
                seen_norms.insert(cn);
            }
            seen_ids.insert(tid.to_string());
            all_results.push(t);
        }
        if all_results.len() >= limit * 2 {
            break;
        }
    }

    let rerank_query = if !artist.is_empty() {
        format!("{} style", artist)
    } else {
        title.to_string()
    };
    let ranked = hybrid_dense_rag_rerank(&rerank_query, all_results, None);
    let final_res: Vec<Value> = ranked.into_iter().take(limit).collect();

    Json(json!({"results": final_res}))
}

async fn vibe_curate_handler(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<Value>,
) -> impl IntoResponse {
    let vibe = payload
        .get("vibe")
        .and_then(|v| v.as_str())
        .unwrap_or("Late Night Drive");
    let limit = payload
        .get("limit")
        .and_then(|l| l.as_u64())
        .map(|l| l as usize)
        .unwrap_or(12)
        .clamp(1, 50);

    let taste_vec = payload.get("userTasteVector").and_then(|v| {
        v.as_array().map(|arr| {
            arr.iter()
                .filter_map(|val| val.as_f64())
                .collect::<Vec<f64>>()
        })
    });

    let candidates = search_jiosaavn_music(&state.client, vibe, limit * 2).await;
    let ranked = hybrid_dense_rag_rerank(vibe, candidates, taste_vec.as_deref());
    let final_res: Vec<Value> = ranked.into_iter().take(limit).collect();

    Json(json!({"results": final_res, "vibe": vibe}))
}

async fn spotify_charts_handler(
    State(state): State<Arc<AppState>>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let chart_key = params
        .get("chart")
        .map(|s| s.as_str())
        .unwrap_or("top_hits");
    let limit = bounded_limit(&params, 20);

    let tracks = get_dynamic_spotify_charts(&state.client, chart_key, limit).await;
    let available: Vec<&str> = SPOTIFY_CHARTS.iter().map(|(k, _, _)| *k).collect();

    Json(json!({
        "chart": chart_key,
        "charts_available": available,
        "results": tracks.clone(),
        "trending": tracks
    }))
}

async fn spotify_oembed_handler(
    State(state): State<Arc<AppState>>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let url = params.get("url").map(|u| u.trim()).unwrap_or("");
    if !url.starts_with("https://open.spotify.com/") && !url.starts_with("https://spotify.link/") {
        return (StatusCode::BAD_REQUEST, Json(json!({"error": "Invalid Spotify URL"}))).into_response();
    }

    let oembed_url = format!(
        "https://open.spotify.com/oembed?url={}",
        urlencoding::encode(url)
    );
    match state.client.get(&oembed_url).send().await {
        Ok(res) if res.status().is_success() => {
            let data: Value = res.json().await.unwrap_or_else(|_| json!({}));
            Json(data).into_response()
        }
        _ => (
            StatusCode::BAD_GATEWAY,
            Json(json!({"error": "Spotify oEmbed lookup failed"})),
        )
            .into_response(),
    }
}

async fn metadata_enrich_handler(
    State(state): State<Arc<AppState>>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let title = params.get("title").map(|s| s.trim()).unwrap_or("");
    let artist = params.get("artist").map(|s| s.trim()).unwrap_or("");
    let res = enrich_metadata(&state.client, title, artist).await;
    Json(res)
}

async fn lyrics_handler(
    State(state): State<Arc<AppState>>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let title = params.get("title").map(|s| s.trim()).unwrap_or("");
    let artist = params.get("artist").map(|s| s.trim()).unwrap_or("");
    let duration = params
        .get("duration")
        .and_then(|d| d.parse::<i64>().ok())
        .unwrap_or(0);

    let res = fetch_lyrics(&state.client, title, artist, duration).await;
    Json(res)
}

async fn vectorize_handler(Json(payload): Json<Value>) -> impl IntoResponse {
    let text = payload.get("text").and_then(|t| t.as_str()).unwrap_or("");
    let vec = generate_16axis_vector(text);
    Json(json!({
        "vector": vec,
        "dimensions": 16
    }))
}

async fn stream_proxy_core(
    state: &AppState,
    stream_url: &str,
    client_headers: HeaderMap,
) -> Result<Response, (StatusCode, Json<Value>)> {
    if !is_trusted_stream_url(stream_url) {
        return Err((
            StatusCode::BAD_GATEWAY,
            Json(json!({"error": "Untrusted stream URL"})),
        ));
    }

    let mut req = state.client.get(stream_url);
    if let Some(range) = client_headers.get(header::RANGE) {
        req = req.header(header::RANGE, range);
    }
    req = req.header("User-Agent", "Mozilla/5.0");

    let upstream = match req.send().await {
        Ok(res) => res,
        Err(e) => {
            error!("Upstream stream error: {}", e);
            return Err((
                StatusCode::BAD_GATEWAY,
                Json(json!({"error": "Failed to connect to upstream stream"})),
            ));
        }
    };

    let status = upstream.status();
    let content_type = upstream
        .headers()
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("audio/mp4")
        .to_string();

    let content_length = upstream
        .headers()
        .get(header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.parse::<u64>().ok());

    let content_range = upstream
        .headers()
        .get(header::CONTENT_RANGE)
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());

    let body_stream = upstream.bytes_stream().map(|item| item.map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e)));
    let body = Body::from_stream(body_stream);

    let mut response = Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, content_type)
        .header(header::ACCEPT_RANGES, "bytes")
        .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*");

    if let Some(len) = content_length {
        if len <= 500 * 1024 * 1024 {
            response = response.header(header::CONTENT_LENGTH, len);
        }
    }
    if let Some(cr) = content_range {
        response = response.header(header::CONTENT_RANGE, cr);
    }

    Ok(response.body(body).unwrap())
}

async fn stream_handler(
    State(state): State<Arc<AppState>>,
    Path(video_id): Path<String>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let clean_id = video_id.trim();
    if clean_id.starts_with("saavn_") {
        // Look up JioSaavn track
        let matches = search_jiosaavn_music(&state.client, clean_id, 1).await;
        if let Some(first) = matches.first() {
            if let Some(stream_url) = first.get("streamUrl").and_then(|s| s.as_str()) {
                if let Ok(resp) = stream_proxy_core(&state, stream_url, headers).await {
                    return resp;
                }
            }
        }
    }

    (
        StatusCode::BAD_GATEWAY,
        Json(json!({"error": "Failed to resolve stream"})),
    )
        .into_response()
}

async fn proxy_stream_handler(
    State(state): State<Arc<AppState>>,
    Query(params): Query<HashMap<String, String>>,
    headers: HeaderMap,
) -> impl IntoResponse {
    let query = params.get("q").map(|s| s.trim()).unwrap_or("");
    let title = params.get("title").map(|s| s.trim()).unwrap_or("");
    let artist = params.get("artist").map(|s| s.trim()).unwrap_or("");
    let search_q = if !query.is_empty() {
        query.to_string()
    } else {
        format!("{} {}", title, artist).trim().to_string()
    };

    if !search_q.is_empty() {
        let matches = search_jiosaavn_music(&state.client, &search_q, 2).await;
        if let Some(first) = matches.first() {
            if let Some(stream_url) = first.get("streamUrl").and_then(|s| s.as_str()) {
                if let Ok(resp) = stream_proxy_core(&state, stream_url, headers).await {
                    return resp;
                }
            }
        }
    }

    (
        StatusCode::BAD_GATEWAY,
        Json(json!({"error": "Unable to resolve stream"})),
    )
        .into_response()
}

async fn download_handler(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<Value>,
) -> impl IntoResponse {
    let title = payload.get("title").and_then(|t| t.as_str()).unwrap_or("track");
    let artist = payload.get("artist").and_then(|a| a.as_str()).unwrap_or("Unknown");
    let query = format!("{} {}", title, artist);

    let matches = search_jiosaavn_music(&state.client, &query, 1).await;
    let Some(first) = matches.first() else {
        return (StatusCode::NOT_FOUND, Json(json!({"error": "Track not found for download"}))).into_response();
    };

    let Some(stream_url) = first.get("streamUrl").and_then(|s| s.as_str()) else {
        return (StatusCode::BAD_GATEWAY, Json(json!({"error": "No valid stream URL resolved"}))).into_response();
    };

    if !is_trusted_stream_url(stream_url) {
        return (StatusCode::BAD_REQUEST, Json(json!({"error": "Untrusted stream URL"}))).into_response();
    }

    let download_dir = std::env::var("USERPROFILE")
        .or_else(|_| std::env::var("HOME"))
        .map(|h| std::path::PathBuf::from(h).join("Music").join("Noctra"))
        .unwrap_or_else(|_| std::path::PathBuf::from("downloads"));

    let _ = std::fs::create_dir_all(&download_dir);

    let clean_title: String = title.chars().filter(|c| c.is_alphanumeric() || *c == ' ' || *c == '-').collect();
    let filename = format!("{} - {}.m4a", artist, clean_title);
    let target_path = download_dir.join(&filename);

    if target_path.exists() {
        return Json(json!({
            "status": "success",
            "message": "File already exists in vault",
            "filename": filename
        })).into_response();
    }

    let mut res = match state.client.get(stream_url).send().await {
        Ok(r) => r,
        Err(e) => return (StatusCode::BAD_GATEWAY, Json(json!({"error": e.to_string()}))).into_response(),
    };

    let temp_path = download_dir.join(format!("{}.part", &filename));
    let mut file = match std::fs::File::create(&temp_path) {
        Ok(f) => f,
        Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({"error": e.to_string()}))).into_response(),
    };

    use std::io::Write;
    let mut total_bytes = 0usize;
    let max_bytes = 200 * 1024 * 1024; // 200 MB cap

    while let Some(chunk) = res.chunk().await.unwrap_or(None) {
        total_bytes += chunk.len();
        if total_bytes > max_bytes {
            let _ = std::fs::remove_file(&temp_path);
            return (StatusCode::PAYLOAD_TOO_LARGE, Json(json!({"error": "Download exceeded 200MB cap"}))).into_response();
        }
        if let Err(e) = file.write_all(&chunk) {
            let _ = std::fs::remove_file(&temp_path);
            return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({"error": e.to_string()}))).into_response();
        }
    }

    if let Err(e) = std::fs::rename(&temp_path, &target_path) {
        return (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({"error": e.to_string()}))).into_response();
    }

    Json(json!({
        "status": "success",
        "message": "Downloaded lossless track",
        "filename": filename
    })).into_response()
}
