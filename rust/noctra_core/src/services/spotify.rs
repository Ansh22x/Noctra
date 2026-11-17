//! Spotify Dynamic Recommendation Engine & Chart Extractor.
//!
//! Provides zero-key Spotify recommendation generation using Spotify's official
//! recommendation algorithms, dynamic web-client transport access, and curated genre/vibe radio.

use regex::Regex;
use reqwest::Client;
use serde_json::{json, Value};
use tracing::warn;

pub const SPOTIFY_CHARTS: [(&str, &str, &str); 12] = [
    ("top_hits", "37i9dQZF1DXcBWIGoYBM5M", "Today's Top Hits"),
    ("global_50", "37i9dQZEVXbMDoHDwVN2tF", "Top 50 - Global"),
    ("viral_50", "37i9dQZF1DX2L0iB23Enbq", "Viral Hits Global"),
    ("pop_rising", "37i9dQZF1DWUa8ZRTfalHk", "Pop Rising"),
    ("rap_caviar", "37i9dQZF1DX0XUsuxWHRQd", "RapCaviar"),
    ("bollywood", "37i9dQZF1DX0XUfTFmZeM0", "Bollywood Butter"),
    ("chill_hits", "37i9dQZF1DX4WYpdgoIcn6", "Chill Hits"),
    ("rock_classics", "37i9dQZF1DXcF6B6QricJ5", "Rock Classics"),
    ("dance_pop", "37i9dQZF1DX4dyzvuaRJ0n", "Dance Pop"),
    ("indie_chill", "37i9dQZF1DX2Nc3B70tvx0", "Ultimate Indie"),
    ("lofi_beats", "37i9dQZF1DXdLEN7aqioXM", "Lofi Beats"),
    ("rnb_vibes", "37i9dQZF1DX4SBhb3fqAp5", "Are & Be"),
];

/// Retrieves an anonymous Spotify web player bearer token.
pub async fn get_spotify_web_token(client: &Client) -> Option<String> {
    let url = "https://open.spotify.com/get_access_token?reason=transport&productType=web_player";
    let res = client
        .get(url)
        .header(
            "User-Agent",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        )
        .send()
        .await
        .ok()?;

    if !res.status().is_success() {
        return None;
    }

    let body: Value = res.json().await.ok()?;
    body.get("accessToken")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
}

/// Fetches tracks from a Spotify public embed playlist.
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
        .unwrap_or("Spotify Playlist");

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
            "source": "spotify_recommendations",
            "quality": "Dynamic 320k Master",
            "duration": dur_sec,
            "spotifyUri": uri
        }));
    }

    results
}

/// Generates recommendations via Spotify's Recommendation API endpoint or fallback genre radio.
pub async fn get_spotify_recommendations(
    client: &Client,
    seed_artists: Option<&str>,
    seed_tracks: Option<&str>,
    seed_genres: Option<&str>,
    limit: usize,
) -> Vec<Value> {
    let limit_clamped = limit.clamp(1, 50);

    // Try Spotify Web API recommendation endpoint if token is obtainable
    if let Some(token) = get_spotify_web_token(client).await {
        let mut query_params = vec![format!("limit={}", limit_clamped)];
        if let Some(artists) = seed_artists {
            if !artists.trim().is_empty() {
                query_params.push(format!("seed_artists={}", urlencoding::encode(artists)));
            }
        }
        if let Some(tracks) = seed_tracks {
            if !tracks.trim().is_empty() {
                query_params.push(format!("seed_tracks={}", urlencoding::encode(tracks)));
            }
        }
        let genres = seed_genres.unwrap_or("pop,dance,hip-hop");
        query_params.push(format!("seed_genres={}", urlencoding::encode(genres)));

        let rec_url = format!(
            "https://api.spotify.com/v1/recommendations?{}",
            query_params.join("&")
        );

        if let Ok(res) = client
            .get(&rec_url)
            .header("Authorization", format!("Bearer {}", token))
            .send()
            .await
        {
            if res.status().is_success() {
                if let Ok(data) = res.json::<Value>().await {
                    if let Some(tracks) = data.get("tracks").and_then(|t| t.as_array()) {
                        let mut out = Vec::new();
                        for t in tracks {
                            let id = t.get("id").and_then(|s| s.as_str()).unwrap_or("");
                            let title = t.get("name").and_then(|s| s.as_str()).unwrap_or("");
                            let artist = t
                                .get("artists")
                                .and_then(|a| a.as_array())
                                .and_then(|arr| arr.first())
                                .and_then(|obj| obj.get("name"))
                                .and_then(|s| s.as_str())
                                .unwrap_or("Unknown Artist");
                            let album = t
                                .pointer("/album/name")
                                .and_then(|s| s.as_str())
                                .unwrap_or("Spotify Album");
                            let art = t
                                .pointer("/album/images/0/url")
                                .and_then(|s| s.as_str())
                                .unwrap_or("");
                            let dur_ms = t.get("duration_ms").and_then(|d| d.as_i64()).unwrap_or(180000);

                            if !title.is_empty() {
                                out.push(json!({
                                    "id": format!("spot_{}", id),
                                    "title": title,
                                    "artist": artist,
                                    "album": album,
                                    "artworkUrl": art,
                                    "thumbnail": art,
                                    "streamUrl": Value::Null,
                                    "source": "spotify_recommendations",
                                    "quality": "Dynamic 320k Master",
                                    "duration": dur_ms / 1000,
                                    "spotifyUri": format!("spotify:track:{}", id)
                                }));
                            }
                        }
                        if !out.is_empty() {
                            return out;
                        }
                    }
                }
            }
        }
    }

    // Graceful fallback to Spotify's curated genre charts
    let chart_id = match seed_genres.unwrap_or("") {
        g if g.contains("bollywood") || g.contains("hindi") => "37i9dQZF1DX0XUfTFmZeM0",
        g if g.contains("rap") || g.contains("hiphop") => "37i9dQZF1DX0XUsuxWHRQd",
        g if g.contains("chill") || g.contains("lofi") => "37i9dQZF1DX4WYpdgoIcn6",
        g if g.contains("rock") => "37i9dQZF1DXcF6B6QricJ5",
        g if g.contains("dance") || g.contains("edm") => "37i9dQZF1DX4dyzvuaRJ0n",
        g if g.contains("indie") => "37i9dQZF1DX2Nc3B70tvx0",
        _ => "37i9dQZF1DXcBWIGoYBM5M", // Today's Top Hits
    };

    fetch_spotify_playlist(client, chart_id, limit_clamped).await
}

/// Retrieves Spotify chart tracks for the specified key.
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
