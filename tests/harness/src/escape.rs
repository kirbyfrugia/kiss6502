//! Byte escapes, so scenarios and packet tests can write exact bytes.

use crate::HarnessError;

/// Turns the backslash escapes a scenario writes into bytes for the wire.
/// Supports `\r \n \t \0 \\` and `\xNN`.
///
/// Non-ASCII input is an error: it means TOML already ate the escape (a
/// double quoted `"\x9b"` arrives as U+009B, not the one byte written), so
/// scenarios must use single quoted TOML literal strings.
pub fn unescape(text: &str) -> Result<Vec<u8>, HarnessError> {
    let mut out = Vec::new();
    let mut chars = text.chars();
    while let Some(c) = chars.next() {
        if c != '\\' {
            if !c.is_ascii() {
                return Err(format!(
                    "non-ascii {c:?}. write the byte as \\xNN, and use a TOML literal \
                     string (single quotes) so TOML does not eat the escape first"
                ));
            }
            out.push(c as u8);
            continue;
        }
        match chars.next() {
            Some('r') => out.push(0x0d),
            Some('n') => out.push(0x0a),
            Some('t') => out.push(0x09),
            Some('0') => out.push(0x00),
            Some('\\') => out.push(0x5c),
            Some('x') => {
                let hi = chars.next().ok_or("\\x needs two hex digits")?;
                let lo = chars.next().ok_or("\\x needs two hex digits")?;
                let byte = u8::from_str_radix(&format!("{hi}{lo}"), 16)
                    .map_err(|_| format!("bad hex escape \\x{hi}{lo}"))?;
                out.push(byte);
            }
            Some(other) => return Err(format!("unknown escape \\{other}")),
            None => return Err("trailing backslash".to_string()),
        }
    }
    Ok(out)
}

/// Renders bytes the way a scenario would write them, for failure output.
/// Not a strict inverse of [`unescape`]: a literal backslash stays one
/// character, so it round-trips through `escape` but not back through it.
pub fn escape(data: &[u8]) -> String {
    let mut out = String::new();
    for &b in data {
        match b {
            0x0d => out.push_str("\\r"),
            0x0a => out.push_str("\\n"),
            0x09 => out.push_str("\\t"),
            0x20..=0x7e => out.push(b as char),
            _ => out.push_str(&format!("\\x{b:02x}")),
        }
    }
    out
}

/// Substring test where an empty needle never matches (unlike a naive
/// `contains`), so a typo'd empty expectation can't pass for free.
pub fn contains(haystack: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty() && haystack.windows(needle.len()).any(|w| w == needle)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escape_and_unescape_round_trip() {
        assert_eq!(unescape(r"AB\r\n\t\0\\").unwrap(), b"AB\r\n\t\0\\");
        assert_eq!(unescape(r"\x9b").unwrap(), vec![0x9b]);
        assert_eq!(escape(b"AB\r\n\t"), r"AB\r\n\t");
        assert_eq!(escape(&[0x9b]), r"\x9b");
        for data in [
            b"AB\r\n".to_vec(),
            vec![0x9b, 0x00, 0x1b],
            (0u8..32).collect(),
        ] {
            assert_eq!(unescape(&escape(&data)).unwrap(), data);
        }
    }

    #[test]
    fn unescape_rejects_bad_input() {
        // "\u{9b}" and "café" are the toml-already-ate-it case.
        for bad in [r"\q", r"\x", r"\xzz", "\\", "\u{9b}", "café"] {
            assert!(unescape(bad).is_err(), "{bad:?} should be rejected");
        }
    }

    #[test]
    fn empty_needle_never_matches() {
        assert!(!contains(b"anything", b""));
        assert!(contains(b"anything", b"thin"));
    }
}
