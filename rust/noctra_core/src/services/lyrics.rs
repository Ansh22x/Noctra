//! Multi-Source Synchronized & Plain Lyrics Resolution Service.

use regex::Regex;
use reqwest::Client;
use serde_json::{json, Value};
use tracing::warn;

fn pick_best_match<'a>(
    candidates: &'a [Value],
    artists: &[String],
    song_duration: i64,
) -> Option<&'a Value> {
    if candidates.is_empty() {
        return None;
    }

    let mut scored: Vec<(i64, &Value)> = candidates
        .iter()
        .map(|c| {
            let mut score = 0i64;
            let artist_name = c
                .get("artistName")
                .and_then(|a| a.as_str())
                .unwrap_or("")
                .to_lowercase();

            for artist in artists {
                if !artist.is_empty() && artist_name.contains(artist) {
                    score += 50;
                    break;
                }
            }

            if song_duration > 0 {
                let cand_dur = c
                    .get("duration")
                    .and_then(|d| d.as_f64())
                    .map(|d| d.round() as i64)
                    .unwrap_or(0);
                let diff = (cand_dur - song_duration).abs();
                if diff <= 3 {
                    score += 50;
                } else if diff <= 8 {
                    score += 30;
                } else if diff <= 15 {
                    score += 15;
                }
            }

            (score, c)
        })
        .collect();

    scored.sort_by(|a, b| b.0.cmp(&a.0));
    scored.first().map(|s| s.1)
}

pub async fn fetch_lyrics(
    client: &Client,
    title: &str,
    artist_str: &str,
    duration: i64,
) -> Value {
    if title.trim().is_empty() {
        return json!({"error": "Missing title"});
    }

    let re_brackets = Regex::new(r"\(.*?\)|\{.*?\}|\[.*?\]").unwrap();
    let clean_title = re_brackets.replace_all(title, "").trim().to_string();

    let re_sep = Regex::new(r"[,/&|]").unwrap();
    let artists: Vec<String> = re_sep
        .split(artist_str)
        .map(|s| s.trim().to_lowercase())
        .filter(|s| !s.is_empty())
        .collect();

    // 1. LRCLIB exact get
    let queries = [
        if !artists.is_empty() { artists[0].clone() } else { String::new() },
        artist_str.to_string(),
    ];

    for artist_q in queries {
        if artist_q.is_empty() {
            continue;
        }

        let mut req = client
            .get("https://lrclib.net/api/get")
            .query(&[("track_name", &clean_title), ("artist_name", &artist_q)])
            .header("User-Agent", "Noctra/1.0");

        if duration > 0 {
            req = req.query(&[("duration", &duration.to_string())]);
        }

        if let Ok(res) = req.send().await {
            if res.status().is_success() {
                if let Ok(item) = res.json::<Value>().await {
                    let synced = item.get("syncedLyrics").and_then(|s| s.as_str());
                    let plain = item.get("plainLyrics").and_then(|s| s.as_str());
                    if synced.is_some() || plain.is_some() {
                        return json!({
                            "found": true,
                            "synced": synced.is_some(),
                            "synced_lyrics": synced.unwrap_or(""),
                            "plain_lyrics": plain.unwrap_or(""),
                            "track_name": item.get("trackName").and_then(|t| t.as_str()).unwrap_or(&clean_title),
                            "artist_name": item.get("artistName").and_then(|a| a.as_str()).unwrap_or(artist_str)
                        });
                    }
                }
            }
        }
    }

    // 2. LRCLIB search with duration-aware filtering
    let search_queries = [
        if !artists.is_empty() {
            format!("{} {}", clean_title, artists[0])
        } else {
            clean_title.clone()
        },
        clean_title.clone(),
        title.to_string(),
    ];

    for q in search_queries {
        let res = match client
            .get("https://lrclib.net/api/search")
            .query(&[("q", &q)])
            .header("User-Agent", "Noctra/1.0")
            .send()
            .await
        {
            Ok(r) => r,
            Err(e) => {
                warn!("LRCLIB search error: {}", e);
                continue;
            }
        };

        if !res.status().is_success() {
            continue;
        }

        let items: Vec<Value> = match res.json().await {
            Ok(v) => v,
            Err(_) => continue,
        };

        let synced_candidates: Vec<Value> = items
            .iter()
            .filter(|i| i.get("syncedLyrics").and_then(|s| s.as_str()).is_some())
            .cloned()
            .collect();

        if let Some(best) = pick_best_match(&synced_candidates, &artists, duration) {
            return json!({
                "found": true,
                "synced": true,
                "synced_lyrics": best.get("syncedLyrics").and_then(|s| s.as_str()).unwrap_or(""),
                "plain_lyrics": best.get("plainLyrics").and_then(|s| s.as_str()).unwrap_or(""),
                "track_name": best.get("trackName").and_then(|t| t.as_str()).unwrap_or(&clean_title),
                "artist_name": best.get("artistName").and_then(|a| a.as_str()).unwrap_or(artist_str)
            });
        }

        let plain_candidates: Vec<Value> = items
            .iter()
            .filter(|i| i.get("plainLyrics").and_then(|s| s.as_str()).is_some())
            .cloned()
            .collect();

        if let Some(best) = pick_best_match(&plain_candidates, &artists, duration) {
            return json!({
                "found": true,
                "synced": false,
                "synced_lyrics": "",
                "plain_lyrics": best.get("plainLyrics").and_then(|s| s.as_str()).unwrap_or(""),
                "track_name": best.get("trackName").and_then(|t| t.as_str()).unwrap_or(&clean_title),
                "artist_name": best.get("artistName").and_then(|a| a.as_str()).unwrap_or(artist_str)
            });
        }
    }

    json!({
        "found": false,
        "error": "No lyrics found across LRCLIB or JioSaavn catalog."
    })
}
