//! Spotify Dynamic Zero-Key Public Chart & Playlist Extractor.

use regex::Regex;
use reqwest::Client;
use serde_json::{json, Value};
use tracing::warn;

pub const SPOTIFY_CHARTS: [(&str, &str, &str); 7] = [
    ("top_hits", "37i9dQZF1DXcBWIGoYBM5M", "Today's Top Hits"),
    ("global_50", "37i9dQZEVXbMDoHDwVN2tF", "Top 50 - Global"),
    ("viral_50", "37i9dQZF1DX2L0iB23Enbq", "Viral Hits Global"),
    ("pop_rising", "37i9dQZF1DWUa8ZRTfalHk", "Pop Rising"),
    ("rap_caviar", "37i9dQZF1DX0XUsuxWHRQd", "RapCaviar"),
    ("bollywood", "37i9dQZF1DX0XUfTFmZeM0", "Bollywood Butter"),
    ("chill_hits", "37i9dQZF1DX4WYpdgoIcn6", "Chill Hits"),
];

pub async fn fetch_spotify_playlist(
    client: &Client,
    playlist_id: &str,
    limit: usize,
) -> Vec<Value> {
    let url = format!("https://open.spotify.com/embed/playlist/{}", playlist_id);
    let res = match client
        .get(&url)
        .header(
            "User-Agent",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        )
        .send()
        .await
    {
        Ok(r) => r,
        Err(e) => {
            warn!("Spotify embed request error: {}", e);
            return Vec::new();
        }
    };

    if !res.status().is_success() {
        return Vec::new();
    }

    let text = match res.text().await {
        Ok(t) => t,
        Err(_) => return Vec::new(),
    };

    let re = match Regex::new(r#"<script id="__NEXT_DATA__" type="application/json">(.*?)</script>"#) {
        Ok(r) => r,
        Err(_) => return Vec::new(),
    };

    let json_str = match re.captures(&text).and_then(|c| c.get(1)) {
        Some(m) => m.as_str(),
        None => return Vec::new(),
    };

    let data: Value = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(_) => return Vec::new(),
    };

    let entity = match data
        .pointer("/props/pageProps/state/data/entity")
        .or_else(|| data.pointer("/props/pageProps/data/entity"))
    {
        Some(e) => e,
        None => return Vec::new(),
    };

    let track_list = match entity.get("trackList").and_then(|t| t.as_array()) {
        Some(list) => list,
        None => return Vec::new(),
    };

    let cover_sources = entity
        .pointer("/coverArt/sources")
        .and_then(|s| s.as_array());
    let default_art = cover_sources
        .and_then(|arr| arr.first())
        .and_then(|obj| obj.get("url"))
        .and_then(|u| u.as_str())
        .unwrap_or("");

    let album_title = entity
        .get("title")
        .or_else(|| entity.get("name"))
        .and_then(|n| n.as_str())
        .unwrap_or("Spotify Chart");

    let mut results = Vec::new();
    for t in track_list.iter().take(limit) {
        let title = t.get("title").and_then(|s| s.as_str()).unwrap_or("").trim();
        let artist = t.get("subtitle").and_then(|s| s.as_str()).unwrap_or("").trim();
        if title.is_empty() {
            continue;
        }

        let uri = t.get("uri").and_then(|u| u.as_str()).unwrap_or("");
        let track_id = if uri.contains(':') {
            uri.split(':').last().unwrap_or("")
        } else {
            t.get("uid").and_then(|u| u.as_str()).unwrap_or("")
        };

        let dur_sec = t
            .get("duration")
            .and_then(|d| d.as_i64())
            .map(|ms| ms / 1000)
            .unwrap_or(180);

        results.push(json!({
            "id": format!("spot_{}", track_id),
            "title": title,
            "artist": artist,
            "album": album_title,
            "artworkUrl": default_art,
            "thumbnail": default_art,
            "streamUrl": Value::Null,
            "source": "spotify_chart",
            "quality": "Dynamic 320k Master",
            "duration": dur_sec,
            "spotifyUri": uri
        }));
    }

    results
}

pub async fn get_dynamic_spotify_charts(
    client: &Client,
    chart_key: &str,
    limit: usize,
) -> Vec<Value> {
    let playlist_id = SPOTIFY_CHARTS
        .iter()
        .find(|(k, _, _)| *k == chart_key)
        .map(|(_, id, _)| *id)
        .unwrap_or("37i9dQZF1DXcBWIGoYBM5M");

    fetch_spotify_playlist(client, playlist_id, limit).await
}
