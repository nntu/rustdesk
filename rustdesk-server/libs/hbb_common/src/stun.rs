use bytes::{BufMut, BytesMut};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};

pub const STUN_MAGIC_COOKIE: u32 = 0x2112_A442;
pub const STUN_BINDING_REQUEST: u16 = 0x0001;
pub const STUN_BINDING_RESPONSE: u16 = 0x0101;

pub const ATTR_MAPPED_ADDRESS: u16 = 0x0001;
pub const ATTR_XOR_MAPPED_ADDRESS: u16 = 0x0020;
pub const ATTR_SOFTWARE: u16 = 0x8022;

const SERVER_SOFTWARE: &[u8] = b"RustDesk-HBBS";

/// Checks whether the raw incoming UDP packet is a STUN packet.
/// STUN header is at least 20 bytes long, starts with 0b00 (first 2 bits zero),
/// and Binding Request type is 0x0001.
#[inline]
pub fn is_stun_packet(bytes: &[u8]) -> bool {
    if bytes.len() < 20 {
        return false;
    }
    // STUN message type starts with 0b00 (bits 0 and 1 must be 0)
    if (bytes[0] & 0xC0) != 0 {
        return false;
    }
    let msg_type = u16::from_be_bytes([bytes[0], bytes[1]]);
    if msg_type != STUN_BINDING_REQUEST {
        return false;
    }
    // RFC 5389 magic cookie check or RFC 3489 legacy check
    let magic = u32::from_be_bytes([bytes[4], bytes[5], bytes[6], bytes[7]]);
    magic == STUN_MAGIC_COOKIE || bytes.len() == 20 + u16::from_be_bytes([bytes[2], bytes[3]]) as usize
}

/// Handles a STUN Binding Request and produces an RFC 5389 / RFC 3489 compliant Binding Response
/// containing both XOR-MAPPED-ADDRESS and MAPPED-ADDRESS attributes.
pub fn handle_stun_request(req: &[u8], src_addr: SocketAddr) -> Option<Vec<u8>> {
    if !is_stun_packet(req) {
        return None;
    }

    let magic_bytes = &req[4..8];
    let tx_id = &req[8..20];

    let mut attr_buf = BytesMut::with_capacity(64);

    // 1. XOR-MAPPED-ADDRESS (RFC 5389)
    attr_buf.put_u16(ATTR_XOR_MAPPED_ADDRESS);
    match src_addr {
        SocketAddr::V4(addr_v4) => {
            attr_buf.put_u16(8); // attr len
            attr_buf.put_u8(0x00); // reserved
            attr_buf.put_u8(0x01); // IPv4 family
            let x_port = addr_v4.port() ^ (STUN_MAGIC_COOKIE >> 16) as u16;
            attr_buf.put_u16(x_port);
            let ip_octets = addr_v4.ip().octets();
            let magic_octets = STUN_MAGIC_COOKIE.to_be_bytes();
            let x_ip = [
                ip_octets[0] ^ magic_octets[0],
                ip_octets[1] ^ magic_octets[1],
                ip_octets[2] ^ magic_octets[2],
                ip_octets[3] ^ magic_octets[3],
            ];
            attr_buf.put_slice(&x_ip);
        }
        SocketAddr::V6(addr_v6) => {
            attr_buf.put_u16(20); // attr len
            attr_buf.put_u8(0x00); // reserved
            attr_buf.put_u8(0x02); // IPv6 family
            let x_port = addr_v6.port() ^ (STUN_MAGIC_COOKIE >> 16) as u16;
            attr_buf.put_u16(x_port);
            let ip_octets = addr_v6.ip().octets();
            let mut xor_key = [0u8; 16];
            xor_key[..4].copy_from_slice(magic_bytes);
            xor_key[4..16].copy_from_slice(tx_id);
            let mut x_ip = [0u8; 16];
            for i in 0..16 {
                x_ip[i] = ip_octets[i] ^ xor_key[i];
            }
            attr_buf.put_slice(&x_ip);
        }
    }

    // 2. MAPPED-ADDRESS (RFC 3489 compatibility)
    attr_buf.put_u16(ATTR_MAPPED_ADDRESS);
    match src_addr {
        SocketAddr::V4(addr_v4) => {
            attr_buf.put_u16(8); // attr len
            attr_buf.put_u8(0x00); // reserved
            attr_buf.put_u8(0x01); // IPv4
            attr_buf.put_u16(addr_v4.port());
            attr_buf.put_slice(&addr_v4.ip().octets());
        }
        SocketAddr::V6(addr_v6) => {
            attr_buf.put_u16(20); // attr len
            attr_buf.put_u8(0x00); // reserved
            attr_buf.put_u8(0x02); // IPv6
            attr_buf.put_u16(addr_v6.port());
            attr_buf.put_slice(&addr_v6.ip().octets());
        }
    }

    // 3. SOFTWARE attribute
    attr_buf.put_u16(ATTR_SOFTWARE);
    let sw_len = SERVER_SOFTWARE.len() as u16;
    attr_buf.put_u16(sw_len);
    attr_buf.put_slice(SERVER_SOFTWARE);
    // Attributes must be padded to a multiple of 4 bytes
    let pad_len = (4 - (SERVER_SOFTWARE.len() % 4)) % 4;
    for _ in 0..pad_len {
        attr_buf.put_u8(0x00);
    }

    let body_len = attr_buf.len() as u16;
    let mut resp = BytesMut::with_capacity(20 + attr_buf.len());
    // STUN Header (20 bytes)
    resp.put_u16(STUN_BINDING_RESPONSE);
    resp.put_u16(body_len);
    resp.put_slice(magic_bytes);
    resp.put_slice(tx_id);
    resp.put_slice(&attr_buf);

    Some(resp.to_vec())
}

/// Helper function to create a standard STUN Binding Request packet (for testing/client use)
pub fn create_binding_request(tx_id: [u8; 12]) -> Vec<u8> {
    let mut req = BytesMut::with_capacity(20);
    req.put_u16(STUN_BINDING_REQUEST);
    req.put_u16(0); // body length 0
    req.put_u32(STUN_MAGIC_COOKIE);
    req.put_slice(&tx_id);
    req.to_vec()
}

/// Parses XOR-MAPPED-ADDRESS from a STUN Binding Response
pub fn parse_xor_mapped_address(resp: &[u8]) -> Option<SocketAddr> {
    if resp.len() < 20 {
        return None;
    }
    let msg_type = u16::from_be_bytes([resp[0], resp[1]]);
    if msg_type != STUN_BINDING_RESPONSE {
        return None;
    }
    let magic_bytes = &resp[4..8];
    let tx_id = &resp[8..20];
    let body_len = u16::from_be_bytes([resp[2], resp[3]]) as usize;
    if resp.len() < 20 + body_len {
        return None;
    }

    let mut offset = 20;
    while offset + 4 <= resp.len() {
        let attr_type = u16::from_be_bytes([resp[offset], resp[offset + 1]]);
        let attr_len = u16::from_be_bytes([resp[offset + 2], resp[offset + 3]]) as usize;
        offset += 4;
        if offset + attr_len > resp.len() {
            break;
        }

        if attr_type == ATTR_XOR_MAPPED_ADDRESS {
            if attr_len >= 8 {
                let family = resp[offset + 1];
                let raw_xport = u16::from_be_bytes([resp[offset + 2], resp[offset + 3]]);
                let port = raw_xport ^ (STUN_MAGIC_COOKIE >> 16) as u16;
                if family == 0x01 && attr_len == 8 {
                    let magic_octets = STUN_MAGIC_COOKIE.to_be_bytes();
                    let ip = Ipv4Addr::new(
                        resp[offset + 4] ^ magic_octets[0],
                        resp[offset + 5] ^ magic_octets[1],
                        resp[offset + 6] ^ magic_octets[2],
                        resp[offset + 7] ^ magic_octets[3],
                    );
                    return Some(SocketAddr::new(IpAddr::V4(ip), port));
                } else if family == 0x02 && attr_len == 20 {
                    let mut xor_key = [0u8; 16];
                    xor_key[..4].copy_from_slice(magic_bytes);
                    xor_key[4..16].copy_from_slice(tx_id);
                    let mut ip_octets = [0u8; 16];
                    for i in 0..16 {
                        ip_octets[i] = resp[offset + 4 + i] ^ xor_key[i];
                    }
                    let ip = Ipv6Addr::from(ip_octets);
                    return Some(SocketAddr::new(IpAddr::V6(ip), port));
                }
            }
        }

        // Advance with 4-byte padding
        let pad = (4 - (attr_len % 4)) % 4;
        offset += attr_len + pad;
    }
    None
}
