//! Random packets for `random` scenario steps and soak runs.

use crate::Xorshift64;

/// Message bodies for `random` steps, short enough through long enough to wrap.
const LOREM: &[&str] = &[
    "OK",
    "Roger that.",
    "Back in 5.",
    "QSL, 73 and good DX.",
    "Heading home now, traffic is light.",
    "The quick brown fox jumps over the lazy dog.",
    "She sells seashells by the seashore at dawn.",
    "All work and no play makes Jack a dull boy today.",
    "Pack my box with five dozen liquor jugs before noon.",
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
    "The morning sun rises slowly above the quiet green hills.",
    "How vexingly quick daft zebras jump under the pale moonlight.",
    "Sphinx of black quartz, judge my vow on this calm clear night.",
    "The river winds gently through the valley toward the harbor light.",
    "A gentle breeze drifts across the wide open meadow on a summer day.",
];

/// Seed it explicitly to get checkable, repeatable output.
pub struct LoremSource {
    rng: Xorshift64,
}

impl LoremSource {
    /// `None` seeds from the clock, for real runs. Tests pass an explicit
    /// seed so the invariants below are checkable.
    pub fn new(seed: Option<u64>) -> Self {
        Self {
            rng: Xorshift64::new(seed),
        }
    }

    /// A message from the corpus, from a random SSID station.
    ///
    /// The ssid is 1 to 15 and never 0: a frame from bare NOCALL is the
    /// station under test talking to itself, and kisstty drops those.
    /// Varying the sender also keeps the small corpus from tripping dedup
    /// on every other packet.
    pub fn packet(&mut self) -> String {
        let s = self.rng.next_u64();
        let body = LOREM[(s % LOREM.len() as u64) as usize];
        let ssid = 1 + (s >> 8) % 15;
        format!("NOCALL-{ssid}>APKTY1,WIDE1-1,WIDE2-1::NOCALL   :{body}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packets_stay_within_their_invariants() {
        let mut rng = LoremSource::new(Some(0x2545_f491_4f6c_dd1d));
        let mut ssids = std::collections::HashSet::new();
        for _ in 0..1000 {
            let packet = rng.packet();
            assert!(packet.contains("::NOCALL   :"));
            let src = packet.split('>').next().unwrap();
            assert_ne!(src, "NOCALL", "{packet}");
            let ssid: u32 = src.split('-').nth(1).unwrap().parse().unwrap();
            assert!((1..=15).contains(&ssid));
            ssids.insert(ssid);
        }
        assert_eq!(
            ssids,
            (1..=15).collect(),
            "the corpus should reach every ssid"
        );
    }
}
