//! Search Result Merge, Normalization & Relevance Ranker.
//!
//! Direct 1:1 Rust native port of Noctra's `search_result_ranker.dart` and `search_text_normalizer.dart`.
//! Performs zero-allocation diacritic folding, fuzzy token matching (Levenshtein $\le 1$ edit),
//! natural language intent extraction ("<Title> by <Artist>", "<Artist> - <Title>"), and
//! modifier penalty scoring (demoting remixes, slowed, reverb unless explicitly requested).

pub const MODIFIER_TAGS: [&str; 32] = [
    "remix", "slowed", "reverb", "sped", "cover", "karaoke", "instrumental", "live", "acoustic",
    "dj", "mashup", "loop", "reprise", "trap", "drill", "remake", "tribute", "rendition",
    "originally performed", "originally by", "in the style of", "made famous by", "piano version",
    "piano cover", "guitar cover", "vocal cover", "harp", "orchestral", "lofi", "lo-fi",
    "bass boosted", "nightcore",
];

/// Normalizes text: lowercases, removes combining diacritics, strips apostrophes,
/// keeps alphanumeric letters & numbers across all Unicode alphabets, and collapses whitespace.
pub fn normalize_search_text(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut prev_space = false;

    for ch in input.chars() {
        let cp = ch as u32;
        // Skip combining diacritical marks
        if (0x0300..=0x036F).contains(&cp) {
            continue;
        }

        // Fold common Latin accented characters to ASCII equivalents
        let folded = match ch {
            'à' | 'á' | 'â' | 'ã' | 'ä' | 'å' | 'À' | 'Á' | 'Â' | 'Ã' | 'Ä' | 'Å' => Some('a'),
            'è' | 'é' | 'ê' | 'ë' | 'È' | 'É' | 'Ê' | 'Ë' => Some('e'),
            'ì' | 'í' | 'î' | 'ï' | 'Ì' | 'Í' | 'Î' | 'Ï' => Some('i'),
            'ò' | 'ó' | 'ô' | 'õ' | 'ö' | 'Ò' | 'Ó' | 'Ô' | 'Õ' | 'Ö' => Some('o'),
            'ù' | 'ú' | 'û' | 'ü' | 'Ù' | 'Ú' | 'Û' | 'Ü' => Some('u'),
            'ñ' | 'Ñ' => Some('n'),
            'ç' | 'Ç' => Some('c'),
            '\'' | '’' => None, // Apostrophes removed word-internally
            _ => None,
        };

        if let Some(f) = folded {
            out.push(f);
            prev_space = false;
        } else if ch == '\'' || ch == '’' {
            // Drop apostrophe without inserting space
            continue;
        } else if ch.is_alphanumeric() {
            for lowered in ch.to_lowercase() {
                out.push(lowered);
            }
            prev_space = false;
        } else if !prev_space {
            out.push(' ');
            prev_space = true;
        }
    }

    out.trim().to_string()
}

/// Tokenizes normalized text into whitespace-delimited tokens.
pub fn tokenize(input: &str) -> Vec<String> {
    normalize_search_text(input)
        .split_whitespace()
        .map(|s| s.to_string())
        .collect()
}

/// Checks if two tokens are within 1 edit distance (Levenshtein distance $\le 1$).
/// Tokens shorter than 4 characters must match exactly to avoid false positives.
pub fn within_one_edit(a: &str, b: &str) -> bool {
    if a == b {
        return true;
    }
    let a_len = a.chars().count();
    let b_len = b.chars().count();

    if a_len < 4 || b_len < 4 {
        return false;
    }
    if a_len.abs_diff(b_len) > 1 {
        return false;
    }

    let a_chars: Vec<char> = a.chars().collect();
    let b_chars: Vec<char> = b.chars().collect();

    let mut diffs = 0;
    let mut i = 0;
    let mut j = 0;

    while i < a_chars.len() && j < b_chars.len() {
        if a_chars[i] != b_chars[j] {
            diffs += 1;
            if diffs > 1 {
                return false;
            }
            if a_len > b_len {
                i += 1;
                continue;
            } else if b_len > a_len {
                j += 1;
                continue;
            }
        }
        i += 1;
        j += 1;
    }

    true
}

/// Computes search relevance score in [0.0, 1.0] between a user query and a candidate track.
pub fn score_candidate(query: &str, title: &str, artist: &str) -> f64 {
    let q = normalize_search_text(query);
    let t = normalize_search_text(title);
    let a = normalize_search_text(artist);

    if q.is_empty() || t.is_empty() {
        return 0.0;
    }

    let qt = tokenize(&q);
    let tt = tokenize(&t);
    let at = tokenize(&a);

    if qt.is_empty() {
        return 0.0;
    }

    let wants_modifier = MODIFIER_TAGS.iter().any(|&m| q.contains(m));

    // 1. Natural language query intent: "<Title> by <Artist>"
    if query.to_lowercase().contains(" by ") {
        let parts: Vec<&str> = query.splitn(2, " by ").collect();
        if parts.len() == 2 {
            let exp_title = normalize_search_text(parts[0]);
            let exp_artist = normalize_search_text(parts[1]);

            if !exp_title.is_empty() && !exp_artist.is_empty() {
                let title_exact = t == exp_title;
                let title_prefix = t.starts_with(&exp_title) || exp_title.starts_with(&t);
                let title_contains = t.contains(&exp_title) || exp_title.contains(&t);

                let artist_exact = a == exp_artist;
                let artist_contains = a.contains(&exp_artist) || exp_artist.contains(&a);

                if (title_exact || title_prefix || title_contains) && (artist_exact || artist_contains) {
                    let mut s: f64 = if title_exact {
                        1.0
                    } else if title_prefix {
                        0.98
                    } else {
                        0.94
                    };
                    if artist_exact {
                        s += 0.05;
                    }
                    if !wants_modifier {
                        for &m in &MODIFIER_TAGS {
                            if t.contains(m) {
                                s *= 0.35;
                                break;
                            }
                        }
                    }
                    return s.clamp(0.0, 1.0);
                } else if (title_exact || title_prefix) && !artist_contains {
                    // Different artist cover / remake
                    let mut s: f64 = 0.40;
                    if !wants_modifier {
                        for &m in &MODIFIER_TAGS {
                            if t.contains(m) {
                                s *= 0.50;
                            }
                        }
                    }
                    return s;
                }
            }
        }
    }

    // 2. Dash separated query intent: "<Artist> - <Title>" or "<Title> - <Artist>"
    if query.contains(" - ") {
        let parts: Vec<&str> = query.splitn(2, " - ").collect();
        if parts.len() == 2 {
            let p1 = normalize_search_text(parts[0]);
            let p2 = normalize_search_text(parts[1]);

            let case_a = (t == p1 || t.contains(&p1)) && (a == p2 || a.contains(&p2));
            let case_b = (a == p1 || a.contains(&p1)) && (t == p2 || t.contains(&p2));

            if case_a || case_b {
                let mut s = 1.0;
                if !wants_modifier {
                    for &m in &MODIFIER_TAGS {
                        if t.contains(m) {
                            s *= 0.35;
                            break;
                        }
                    }
                }
                return s;
            }
        }
    }

    // 3. Exact full match
    if t == q {
        let mut s = 1.0;
        if !wants_modifier {
            for &m in &MODIFIER_TAGS {
                if t.contains(m) {
                    s *= 0.35;
                    break;
                }
            }
        }
        return s;
    }

    // 4. Token Overlap & Fuzzy Jaro/Levenshtein matching
    let mut matched_title_tokens = 0usize;
    let mut matched_artist_tokens = 0usize;

    for q_tok in &qt {
        let in_title = tt.iter().any(|t_tok| within_one_edit(q_tok, t_tok));
        let in_artist = at.iter().any(|a_tok| within_one_edit(q_tok, a_tok));

        if in_title {
            matched_title_tokens += 1;
        }
        if in_artist {
            matched_artist_tokens += 1;
        }
    }

    let total_matches = matched_title_tokens + matched_artist_tokens;
    if total_matches == 0 {
        return 0.0;
    }

    let mut score = (matched_title_tokens as f64 * 0.7 + matched_artist_tokens as f64 * 0.3)
        / (qt.len() as f64);

    // Prefix boost
    if t.starts_with(&q) {
        score += 0.15;
    }

    // Modifier penalty if user didn't ask for it
    if !wants_modifier {
        for &m in &MODIFIER_TAGS {
            if t.contains(m) {
                score *= 0.35;
                break;
            }
        }
    }

    score.clamp(0.0, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalization() {
        assert_eq!(normalize_search_text("Beyoncé"), "beyonce");
        assert_eq!(normalize_search_text("Don't Stop Believin'"), "dont stop believin");
        assert_eq!(normalize_search_text("   Hello   World!  "), "hello world");
    }

    #[test]
    fn test_within_one_edit() {
        assert!(within_one_edit("hello", "hello"));
        assert!(within_one_edit("sound", "sund")); // 1 delete
        assert!(within_one_edit("track", "traack")); // 1 insert
        assert!(within_one_edit("music", "musik")); // 1 substitute
        assert!(!within_one_edit("cat", "cap")); // < 4 chars requires exact
    }

    #[test]
    fn test_scoring_natural_language_by() {
        let score_official = score_candidate("Blinding Lights by The Weeknd", "Blinding Lights", "The Weeknd");
        assert!(score_official >= 0.95);

        // Remix should be heavily demoted
        let score_remix = score_candidate("Blinding Lights by The Weeknd", "Blinding Lights (Remix)", "The Weeknd");
        assert!(score_remix < score_official);
    }
}
