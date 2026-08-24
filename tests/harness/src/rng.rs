//! A tiny non-cryptographic RNG, so soak runs and random picks don't need
//! the `rand` crate.

use std::time::{SystemTime, UNIX_EPOCH};

/// xorshift64.
pub struct Xorshift64 {
    state: u64,
}

impl Xorshift64 {
    /// `None` seeds from the clock, for real runs. Tests pass an explicit
    /// seed so output is repeatable.
    pub fn new(seed: Option<u64>) -> Self {
        let seed = seed.unwrap_or_else(|| {
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.subsec_nanos() as u64)
                .unwrap_or(0);
            (nanos % 1_000_000_000) | 1
        });
        Self {
            state: if seed == 0 {
                0x2545_f491_4f6c_dd1d
            } else {
                seed
            },
        }
    }

    pub fn next_u64(&mut self) -> u64 {
        let mut s = self.state;
        s ^= s << 13;
        s ^= s >> 7;
        s ^= s << 17;
        self.state = s;
        s
    }
}
