//! JioSaavn High-Fidelity Music Extraction & Decryption Engine.

use reqwest::Client;
use serde_json::{json, Value};
use tracing::warn;

use crate::crypto::des::decrypt_jiosaavn_media_url;

fn parse_song_item(item: &Value) -> Option<Value> {
    let song_name = item
        .get("song")
        .or_else(|| item.get("title"))
        .and_then(|v| v.as_str())?;

    let enc_url = item
        .get("encrypted_media_url")
        .and_then(|v| v.as_str())
        .unwrap_or("");
    let stream_url = decrypt_jiosaavn_media_url(enc_url)?;

    let raw_img = item.get("image").and_then(|v| v.as_str()).unwrap_or("");
    let high_res_img = raw_img.replace("150x150", "500x500").replace("50x50", "500x500");

    let primary_artists = item
        .get("primary_artists")
        .or_else(|| item.get("singers"))
        .or_else(|| item.get("music"))
        .and_then(|v| v.as_str())
        .unwrap_or("Unknown Artist");

    let clean_title = song_name
        .replace("&quot;", "\"")
        .replace("&amp;", "&")
        .replace("&#039;", "'");
    let clean_artists = primary_artists
        .replace("&quot;", "\"")
        .replace("&amp;", "&")
        .replace("&#039;", "'");

    let duration_sec = item
        .get("duration")
        .and_then(|d| d.as_str())
        .and_then(|s| s.parse::<i64>().ok())
        .or_else(|| item.get("duration").and_then(|d| d.as_i64()))
        .unwrap_or(0);

    let id = item.get("id").and_then(|i| i.as_str()).unwrap_or("");

    Some(json!({
        "id": format!("saavn_{}", id),
        "title": clean_title,
        "artist": clean_artists,
        "album": item.get("album").and_then(|a| a.as_str()).unwrap_or(""),
        "artworkUrl": high_res_img,
        "thumbnail": high_res_img,
        "streamUrl": stream_url,
        "stream_url": stream_url,
        "source": "jiosaavn_320k",
        "quality": "320kbps High Quality",
        "duration": duration_sec,
        "year": item.get("year").and_then(|y| y.as_str()).unwrap_or(""),
        "genre": item.get("language").and_then(|l| l.as_str()).unwrap_or("Universal"),
        "has_lyrics": item.get("has_lyrics").and_then(|h| h.as_str()).map(|s| s == "true").unwrap_or(false)
    }))
}

pub async fn search_jiosaavn_music(
    client: &Client,
    query: &str,
    limit: usize,
) -> Vec<Value> {
    let params = [
        ("__call", "search.getResults"),
        ("_format", "json"),
        ("_marker", "0"),
        ("cc", "in"),
        ("includeMetaTags", "1"),
        ("q", query),
        ("p", "1"),
        ("n", &limit.to_string()),
    ];

    let resp = match client
        .get("https://www.jiosaavn.com/api.php")
        .query(&params)
        .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        .send()
        .await
    {
        Ok(r) => r,
        Err(e) => {
            warn!("JioSaavn search network error: {}", e);
            return Vec::new();
        }
    };

    let data: Value = match resp.json().await {
        Ok(v) => v,
        Err(_) => return Vec::new(),
    };

    let mut results = Vec::new();
    if let Some(results_array) = data.get("results").and_then(|r| r.as_array()) {
        for item in results_array {
            if let Some(parsed) = parse_song_item(item) {
                results.push(parsed);
            }
        }
    }

    results
}

pub async fn get_jiosaavn_trending(client: &Client, limit: usize) -> Vec<Value> {
    let params = [
        ("__call", "content.getTrending"),
        ("_format", "json"),
        ("_marker", "0"),
        ("cc", "in"),
    ];

    let resp = match client
        .get("https://www.jiosaavn.com/api.php")
        .query(&params)
        .header("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
        .send()
        .await
    {
        Ok(r) => r,
        Err(e) => {
            warn!("JioSaavn trending error: {}", e);
            return Vec::new();
        }
    };

    let data: Value = match resp.json().await {
        Ok(v) => v,
        Err(_) => return Vec::new(),
    };

    let mut results = Vec::new();
    if let Some(items) = data.as_array() {
        for item in items {
            if item.get("type").and_then(|t| t.as_str()) == Some("song") {
                if let Some(parsed) = parse_song_item(item) {
                    results.push(parsed);
                    if results.len() >= limit {
                        break;
                    }
                }
            }
        }
    }

    results
}
