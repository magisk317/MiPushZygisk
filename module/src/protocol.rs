use std::io::{self, Read, Write};
use std::os::unix::net::UnixStream;
use std::time::Duration;

pub const MAGIC: [u8; 4] = *b"MPZK";
pub const VERSION: u16 = 1;
pub const MAX_FRAME: u32 = 16 * 1024;
pub const QUERY: u16 = 1;
pub const RESPONSE: u16 = 2;
pub const STATUS_OK: u8 = 0;
pub const STATUS_REJECTED: u8 = 1;

#[derive(Debug, Eq, PartialEq)]
pub struct RuntimeConfig {
    pub should_hook: bool,
    pub profile: u8,
    pub observe: bool,
    pub device_config: Vec<u8>,
}

impl RuntimeConfig {
    pub fn disabled() -> Self {
        Self {
            should_hook: false,
            profile: 0,
            observe: false,
            device_config: Vec::new(),
        }
    }
}

pub fn configure(stream: &UnixStream) -> io::Result<()> {
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    stream.set_write_timeout(Some(Duration::from_secs(2)))?;
    Ok(())
}

pub fn write_frame(stream: &mut UnixStream, kind: u16, payload: &[u8]) -> io::Result<()> {
    if payload.len() > MAX_FRAME as usize {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "frame too large",
        ));
    }
    let mut header = [0u8; 16];
    header[0..4].copy_from_slice(&MAGIC);
    header[4..6].copy_from_slice(&VERSION.to_be_bytes());
    header[6..8].copy_from_slice(&kind.to_be_bytes());
    header[8..12].copy_from_slice(&(payload.len() as u32).to_be_bytes());
    stream.write_all(&header)?;
    stream.write_all(payload)?;
    stream.flush()
}

pub fn read_frame(stream: &mut UnixStream) -> io::Result<(u16, Vec<u8>)> {
    let mut header = [0u8; 16];
    stream.read_exact(&mut header)?;
    if header[0..4] != MAGIC {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "bad magic"));
    }
    if u16::from_be_bytes([header[4], header[5]]) != VERSION {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "unsupported version",
        ));
    }
    let length = u32::from_be_bytes([header[8], header[9], header[10], header[11]]);
    if length > MAX_FRAME {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "frame too large",
        ));
    }
    let mut payload = vec![0u8; length as usize];
    stream.read_exact(&mut payload)?;
    Ok((u16::from_be_bytes([header[6], header[7]]), payload))
}

pub fn encode_query(package: &str, process: &str) -> Vec<u8> {
    format!("{package}\n{process}").into_bytes()
}

pub fn decode_query(payload: &[u8]) -> io::Result<(&str, &str)> {
    let text = std::str::from_utf8(payload)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "query is not utf8"))?;
    let mut lines = text.splitn(2, '\n');
    let package = lines.next().unwrap_or("").trim();
    let process = lines.next().unwrap_or("").trim();
    if package.is_empty() || process.is_empty() {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "missing identity",
        ));
    }
    Ok((package, process))
}

pub fn encode_response(config: &RuntimeConfig) -> Vec<u8> {
    let mut payload = Vec::with_capacity(7 + config.device_config.len());
    payload.push(if config.should_hook {
        STATUS_OK
    } else {
        STATUS_REJECTED
    });
    payload.push(config.profile);
    payload.push(config.observe as u8);
    payload.extend_from_slice(&(config.device_config.len() as u32).to_be_bytes());
    payload.extend_from_slice(&config.device_config);
    payload
}

pub fn decode_response(payload: &[u8]) -> io::Result<RuntimeConfig> {
    if payload.len() < 7 {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "short response"));
    }
    let should_hook = match payload[0] {
        STATUS_OK => true,
        STATUS_REJECTED => false,
        _ => {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "bad response status",
            ))
        }
    };
    if payload[2] > 1 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "bad observe flag",
        ));
    }
    let length = u32::from_be_bytes([payload[3], payload[4], payload[5], payload[6]]) as usize;
    if length > MAX_FRAME as usize - 7 || payload.len() != 7 + length {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "bad config length",
        ));
    }
    Ok(RuntimeConfig {
        should_hook,
        profile: payload[1],
        observe: payload[2] != 0,
        device_config: payload[7..].to_vec(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn query_round_trip() {
        let encoded = encode_query("com.example.app", "com.example.app:push");
        assert_eq!(
            decode_query(&encoded).unwrap(),
            ("com.example.app", "com.example.app:push")
        );
    }

    #[test]
    fn response_round_trip() {
        let config = RuntimeConfig {
            should_hook: true,
            profile: 1,
            observe: true,
            device_config: b"[system]\nMODEL=Test\n".to_vec(),
        };
        assert_eq!(decode_response(&encode_response(&config)).unwrap(), config);
    }

    #[test]
    fn rejects_oversized_payload() {
        let (left, _right) = UnixStream::pair().unwrap();
        let mut left = left;
        assert!(write_frame(&mut left, QUERY, &vec![0; MAX_FRAME as usize + 1]).is_err());
    }
}
