//! Pure Rust, zero-dependency bit-accurate DES (Data Encryption Standard)
//! Electronic Codebook (ECB) implementation with PKCS5/PKCS7 padding.
//!
//! Specifically used for JioSaavn 320kbps encrypted media URL resolution.

use base64::Engine;

const IP: [usize; 64] = [
    58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36, 28, 20, 12, 4,
    62, 54, 46, 38, 30, 22, 14, 6, 64, 56, 48, 40, 32, 24, 16, 8,
    57, 49, 41, 33, 25, 17, 9, 1, 59, 51, 43, 35, 27, 19, 11, 3,
    61, 53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7,
];

const FP: [usize; 64] = [
    40, 8, 48, 16, 56, 24, 64, 32, 39, 7, 47, 15, 55, 23, 63, 31,
    38, 6, 46, 14, 54, 22, 62, 30, 37, 5, 45, 13, 53, 21, 61, 29,
    36, 4, 44, 12, 52, 20, 60, 28, 35, 3, 43, 11, 51, 19, 59, 27,
    34, 2, 42, 10, 50, 18, 58, 26, 33, 1, 41, 9, 49, 17, 57, 25,
];

const PC1: [usize; 56] = [
    57, 49, 41, 33, 25, 17, 9, 1, 58, 50, 42, 34, 26, 18,
    10, 2, 59, 51, 43, 35, 27, 19, 11, 3, 60, 52, 44, 36,
    63, 55, 47, 39, 31, 23, 15, 7, 62, 54, 46, 38, 30, 22,
    14, 6, 61, 53, 45, 37, 29, 21, 13, 5, 28, 20, 12, 4,
];

const PC2: [usize; 48] = [
    14, 17, 11, 24, 1, 5, 3, 28, 15, 6, 21, 10,
    23, 19, 12, 4, 26, 8, 16, 7, 27, 20, 13, 2,
    41, 52, 31, 37, 47, 55, 30, 40, 51, 45, 33, 48,
    44, 49, 39, 56, 34, 53, 46, 42, 50, 36, 29, 32,
];

const SHIFTS: [usize; 16] = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1];

const E: [usize; 48] = [
    32, 1, 2, 3, 4, 5, 4, 5, 6, 7, 8, 9,
    8, 9, 10, 11, 12, 13, 12, 13, 14, 15, 16, 17,
    16, 17, 18, 19, 20, 21, 20, 21, 22, 23, 24, 25,
    24, 25, 26, 27, 28, 29, 28, 29, 30, 31, 32, 1,
];

const P: [usize; 32] = [
    16, 7, 20, 21, 29, 12, 28, 17, 1, 15, 23, 26, 5, 18, 31, 10,
    2, 8, 24, 14, 32, 27, 3, 9, 19, 13, 30, 6, 22, 11, 4, 25,
];

const SBOXES: [[[u8; 16]; 4]; 8] = [
    // S1
    [
        [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7],
        [0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8],
        [4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0],
        [15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13],
    ],
    // S2
    [
        [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10],
        [3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5],
        [0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15],
        [13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9],
    ],
    // S3
    [
        [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8],
        [13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1],
        [13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7],
        [1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12],
    ],
    // S4
    [
        [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15],
        [13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9],
        [10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4],
        [3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14],
    ],
    // S5
    [
        [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9],
        [14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6],
        [4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14],
        [11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3],
    ],
    // S6
    [
        [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11],
        [10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8],
        [9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6],
        [4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13],
    ],
    // S7
    [
        [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1],
        [13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6],
        [1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2],
        [6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12],
    ],
    // S8
    [
        [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7],
        [1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2],
        [7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8],
        [2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11],
    ],
];

fn bytes_to_bits(bytes: &[u8]) -> Vec<u8> {
    let mut bits = Vec::with_capacity(bytes.len() * 8);
    for &b in bytes {
        for i in (0..8).rev() {
            bits.push((b >> i) & 1);
        }
    }
    bits
}

fn bits_to_bytes(bits: &[u8]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(bits.len() / 8);
    for chunk in bits.chunks(8) {
        let mut b = 0u8;
        for (i, &bit) in chunk.iter().enumerate() {
            b |= bit << (7 - i);
        }
        bytes.push(b);
    }
    bytes
}

fn generate_subkeys(key: &[u8]) -> Vec<Vec<u8>> {
    let key_bits = bytes_to_bits(key);
    let mut c: Vec<u8> = (0..28).map(|i| key_bits[PC1[i] - 1]).collect();
    let mut d: Vec<u8> = (0..28).map(|i| key_bits[PC1[i + 28] - 1]).collect();
    let mut subkeys = Vec::with_capacity(16);

    for &s in SHIFTS.iter() {
        c.rotate_left(s);
        d.rotate_left(s);
        let mut cd = c.clone();
        cd.extend_from_slice(&d);
        let subkey: Vec<u8> = (0..48).map(|i| cd[PC2[i] - 1]).collect();
        subkeys.push(subkey);
    }
    subkeys
}

fn feistel(block: &[u8], subkeys: &[Vec<u8>]) -> Vec<u8> {
    let bits = bytes_to_bits(block);
    let ip_bits: Vec<u8> = (0..64).map(|i| bits[IP[i] - 1]).collect();
    let mut l = ip_bits[0..32].to_vec();
    let mut r = ip_bits[32..64].to_vec();

    for k in subkeys {
        let e_r: Vec<u8> = (0..48).map(|i| r[E[i] - 1]).collect();
        let xor_k: Vec<u8> = (0..48).map(|i| e_r[i] ^ k[i]).collect();
        let mut s_out = Vec::with_capacity(32);

        for b in 0..8 {
            let chunk = &xor_k[b * 6..(b + 1) * 6];
            let row = ((chunk[0] as usize) << 1) | (chunk[5] as usize);
            let col = ((chunk[1] as usize) << 3)
                | ((chunk[2] as usize) << 2)
                | ((chunk[3] as usize) << 1)
                | (chunk[4] as usize);
            let val = SBOXES[b][row][col];
            for bit in (0..4).rev() {
                s_out.push((val >> bit) & 1);
            }
        }

        let p_out: Vec<u8> = (0..32).map(|i| s_out[P[i] - 1]).collect();
        let next_l = r;
        r = (0..32).map(|i| l[i] ^ p_out[i]).collect();
        l = next_l;
    }

    let mut pre_output = r;
    pre_output.extend_from_slice(&l);
    let fp_bits: Vec<u8> = (0..64).map(|i| pre_output[FP[i] - 1]).collect();
    bits_to_bytes(&fp_bits)
}

pub fn decrypt_des_ecb(cipher: &[u8], key: &[u8]) -> Result<Vec<u8>, String> {
    if cipher.len() % 8 != 0 || cipher.is_empty() {
        return Err("Ciphertext must be a multiple of 8 bytes".into());
    }
    if key.len() < 8 {
        return Err("Key must be at least 8 bytes".into());
    }

    let mut subkeys = generate_subkeys(&key[0..8]);
    subkeys.reverse(); // Decryption uses reverse subkey order

    let mut decrypted = Vec::with_capacity(cipher.len());
    for chunk in cipher.chunks(8) {
        decrypted.extend_from_slice(&feistel(chunk, &subkeys));
    }

    // PKCS7 padding removal
    if let Some(&pad) = decrypted.last() {
        let pad_len = pad as usize;
        if pad_len > 0 && pad_len <= 8 && decrypted.len() >= pad_len {
            let start = decrypted.len() - pad_len;
            if decrypted[start..].iter().all(|&b| b == pad) {
                decrypted.truncate(start);
            }
        }
    }

    Ok(decrypted)
}

/// Decrypts a JioSaavn encrypted media url token into a 320kbps MP4/M4A direct URL.
pub fn decrypt_jiosaavn_media_url(encrypted: &str) -> Option<String> {
    let clean = encrypted.trim();
    if clean.is_empty() {
        return None;
    }
    let engine = base64::engine::general_purpose::STANDARD;
    let decoded = engine.decode(clean).ok()?;
    let key = b"38346591";
    let decrypted = decrypt_des_ecb(&decoded, key).ok()?;
    let raw = String::from_utf8_lossy(&decrypted).to_string();
    if raw.is_empty() {
        return None;
    }

    let high_quality = raw
        .replace("_96.mp4", "_320.mp4")
        .replace("_96.m4a", "_320.m4a")
        .replace("_160.mp4", "_320.mp4");
    Some(high_quality)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_known_des_vector() {
        let key = [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF];
        let ciphertext = [0x3F, 0xA4, 0x0E, 0x8A, 0x98, 0x4D, 0x48, 0x15];
        let mut subkeys = generate_subkeys(&key);
        subkeys.reverse();
        let plain = feistel(&ciphertext, &subkeys);
        assert_eq!(&plain, b"Now is t");
    }
}
