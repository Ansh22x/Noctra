//! Zero-key MusicBrainz recording metadata enrichment.

use reqwest::Client;
use serde_json::{json, Value};
use tracing::warn;

pub async fn enrich_metadata(
    client: &Client,
    title: &str,
    artist: &str,
) -> Value {
    if title.trim().is_empty() {
        return json!({"error": "Missing title", "found": false});
    }

    let query = if !artist.trim().is_empty() {
        format!("{} {}", title.trim(), artist.trim())
    } else {
        title.trim().to_string()
    };

    let res = match client
        .get("https://musicbrainz.org/ws/2/recording/")
        .query(&[("query", &query), ("fmt", &"json".to_string()), ("limit", &"1".to_string())])
        .header("User-Agent", "NoctraApp/1.0.0 (contact@noctra.local)")
        .send()
        .await
    {
        Ok(r) => r,
        Err(e) => {
            warn!("MusicBrainz enrichment error: {}", e);
            return json!({"found": false, "error": e.to_string()});
        }
    };

    if !res.status().is_success() {
        return json!({"found": false});
    }

    let data: Value = match res.json().await {
        Ok(v) => v,
        Err(_) => return json!({"found": false}),
    };

    if let Some(recordings) = data.get("recordings").and_then(|r| r.as_array()) {
        if let Some(rec) = recordings.first() {
            let releases = rec.get("releases").and_then(|rel| rel.as_array());
            let first_release = releases.and_then(|arr| arr.first());
            let album = first_release.and_then(|r| r.get("title")).and_then(|t| t.as_str());
            let release_mbid = first_release.and_then(|r| r.get("id")).and_then(|i| i.as_str());

            let tags: Vec<String> = rec
                .get("tags")
                .and_then(|t| t.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|tag| tag.get("name").and_then(|n| n.as_str()).map(|s| s.to_string()))
                        .collect()
                })
                .unwrap_or_default();

            return json!({
                "found": true,
                "mbid": rec.get("id").and_then(|i| i.as_str()),
                "title": rec.get("title").and_then(|t| t.as_str()),
                "album": album,
                "releaseMbid": release_mbid,
                "tags": tags
            });
        }
    }

    json!({"found": false})
}
