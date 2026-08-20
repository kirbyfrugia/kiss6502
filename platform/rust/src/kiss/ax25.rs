use super::aprs::AprsData;

pub const MAX_DIGIPEATERS: usize = 8;

pub fn parse_digipeater_path(path: &[String]) -> Result<Vec<Ax25Addr>, String> {
    let digis = path
        .iter()
        .map(|d| Ax25Addr::parse(d))
        .collect::<Result<Vec<_>, _>>()?;

    if digis.len() > MAX_DIGIPEATERS {
        return Err(format!("at most {MAX_DIGIPEATERS} digipeaters are allowed"));
    }

    Ok(digis)
}

#[derive(Debug,Clone)]
pub struct Ax25Addr {
    addr: String,
    ssid: u8,
    repeated: bool,
}

impl Ax25Addr {
    pub const AX25DEST: &str = "APKTY1";

    const COMMAND: u8 = 0b1000_0000;

    pub fn parse(s: &str) -> Result<Self, String> {
        let s = s.trim();
        let (addr, ssid) = match s.split_once('-') {
            Some((addr, ssid)) => {
                let ssid = ssid
                    .parse::<u8>()
                    .ok()
                    .filter(|&n| n <= 15)
                    .ok_or_else(|| format!("'{s}' has an invalid SSID (must be 0-15)"))?;
                (addr, ssid)
            }
            None => (s, 0),
        };

        if addr.is_empty() || addr.len() > 6 || !addr.chars().all(|c| c.is_ascii_alphanumeric()) {
            return Err(format!("'{addr}' is not a valid station"));
        }

        Ok(Self::new(addr.to_string(), ssid))
    }

    pub fn new(addr: String, ssid: u8) -> Self {
        let mut addr = addr.to_uppercase();

        if addr.len() > 6 {
            addr.truncate(6);
        }

        Self {
            addr,
            ssid,
            repeated: false,
        }
    }

    pub fn encode(&self, last_addr: bool) -> [u8; 7] {
        let mut bytes: [u8; 7] = [0; 7];

        let formatted = format!("{:<6}", &self.addr);
        let str_bytes: &[u8] = formatted.as_bytes();
        let mut i = 0;
        for unshifted in str_bytes.iter() {
            let shifted = unshifted << 1;
            bytes[i] = shifted;
            i += 1;
        }

        let ssid_byte: u8 = (self.ssid << 1) | 0b01100000;
        if last_addr {
            bytes[6] = ssid_byte | 0b00000001;
        } else {
            bytes[6] = ssid_byte & 0b11111110;
        };

        return bytes;
    }

    pub fn encode_dest(&self) -> [u8; 7] {
        let mut bytes = self.encode(false);
        bytes[6] |= Self::COMMAND;
        bytes
    }

    fn process_addr(buf: &[u8; 7]) -> String {
        let mut addr = String::new();
        for &byte in &buf[0..6] {
            let shifted = byte >> 1;
            let byte_char = shifted as char;
            addr.push(byte_char);
        }

        return String::from(addr.trim_end());
    }

    pub fn decode(buf: &[u8; 7]) -> (Self, bool) {
        let addr = Self::process_addr(buf);
        let ssid = (buf[6] >> 1) & 0b0000_1111;

        let repeated = buf[6] & 0b1000_0000 != 0;

        // this is the last address in the header if
        // the lsb on byte 6 is 0.
        let last_byte = buf[6];
        let last_addr = last_byte & 0b0000_0001 != 0;

        (Self { addr, ssid, repeated }, last_addr)
    }

    pub fn repeated(&self) -> bool {
        self.repeated
    }
}

impl std::fmt::Display for Ax25Addr {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        if self.ssid != 0 {
            write!(f, "{}-{}", self.addr, self.ssid)
        } else {
            write!(f, "{}", self.addr)
        }
    }
}

#[derive(Debug,Clone)]
pub struct Ax25Frame {
    dest: Ax25Addr,
    source: Ax25Addr,
    digipeaters: Vec<Ax25Addr>,
    #[allow(dead_code)]
    control: u8,
    #[allow(dead_code)]
    pid: u8,
    data: AprsData,
}

impl Ax25Frame {
    pub fn new(dest: Ax25Addr, source: Ax25Addr, digipeaters: Vec<Ax25Addr>, data: AprsData) -> Self {
        Self {
            dest,
            source,
            digipeaters,
            data,
            control: 0x03,
            pid: 0xf0,
        }
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut bytes: Vec<u8> = Vec::new();

        let num_digis = self.digipeaters.len();

        bytes.extend(self.dest.encode_dest());
        bytes.extend(self.source.encode(num_digis == 0));

        for (i, digi) in self.digipeaters.iter().enumerate() {
            bytes.extend(digi.encode(i + 1 == num_digis));
        }

        bytes.push(self.control);
        bytes.push(self.pid);
        bytes.extend(self.data.encode());

        bytes
    }

    pub fn decode(bytes: &[u8]) -> Option<Self> {
        const MIN_AX25_FRAME_SIZE: usize = 17; // dest + source + ctrl + pid + 1 info byte
        if bytes.len() < MIN_AX25_FRAME_SIZE {
            tracing::warn!(len = bytes.len(), "discarding invalid ax25 frame - too small");
            return None
        }

        const MAX_AX25_ADDRS: usize = 10;
        let mut addrs: Vec<Ax25Addr> = Vec::new();
        let mut offset = 0;
        while addrs.len() < MAX_AX25_ADDRS && offset + 7 <= bytes.len() {
            let (addr, last_addr) = Ax25Addr::decode(bytes[offset..offset + 7].try_into().unwrap());
            addrs.push(addr);
            if last_addr { break }
            offset += 7;
        }

        let mut addrs = addrs.into_iter();
        let control_field_start = addrs.len() * 7;

        let Some(dest) = addrs.next() else {
            tracing::warn!("ax25 frame missing dest field");
            return None
        };

        let Some(source) = addrs.next() else {
            tracing::warn!("ax25 frame missing source field");
            return None
        };

        let digipeaters = addrs.collect();

        let Some(&control) = bytes.get(control_field_start) else {
            tracing::warn!("ax25 frame missing control byte");
            return None
        };
        let Some(&pid) = bytes.get(control_field_start + 1) else {
            tracing::warn!("ax25 frame missing pid byte");
            return None
        };

        let info_field_start = control_field_start + 2;
        let info = bytes.get(info_field_start..).unwrap_or(&[]);
        let data = AprsData::decode(info)?;

        Some(Ax25Frame { dest, source, digipeaters, control, pid, data })
    }

    pub fn digipeaters(&self) -> &[Ax25Addr] {
        &self.digipeaters
    }

    pub fn source(&self) -> &Ax25Addr {
        &self.source
    }

    pub fn dest(&self) -> &Ax25Addr {
        &self.dest
    }

    pub fn data(&self) -> &AprsData {
        &self.data
    }
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dest_encodes_with_the_command_bit_set() {
        let dest = Ax25Addr::new(Ax25Addr::AX25DEST.to_string(), 0);

        assert_eq!(
            dest.encode_dest(),
            [0x82, 0xA0, 0x96, 0xA8, 0xB2, 0x62, 0xE0],
            "must match pk_dest_addr in platform/atari/protocol_kiss.s",
        );
    }

    #[test]
    fn source_encodes_without_the_command_bit_and_marked_last() {
        let source = Ax25Addr::new("NOCALL".to_string(), 0);

        assert_eq!(
            source.encode(true), [0x9C, 0x9E, 0x86, 0x82, 0x98, 0x98, 0x61],
        );
    }

    #[test]
    fn ssid_lands_in_bits_four_through_one() {
        let source = Ax25Addr::new("NOCA".to_string(), 9);

        assert_eq!(source.encode(true), [0x9C, 0x9E, 0x86, 0x82, 0x40, 0x40, 0x73]);
    }

}
