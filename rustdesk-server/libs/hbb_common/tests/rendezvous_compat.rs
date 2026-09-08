use hbb_common::{
    protobuf::Message,
    rendezvous_proto::{
        register_pk_response, rendezvous_message, ConnType, PunchHoleRequest, RegisterPk,
        RegisterPkResponse, RendezvousMessage,
    },
};

#[test]
fn client_1_4_7_registration_fields_round_trip() {
    let mut message = RendezvousMessage::new();
    message.set_register_pk(RegisterPk {
        id: "123456789".to_owned(),
        uuid: vec![1, 2, 3].into(),
        pk: vec![4, 5, 6].into(),
        no_register_device: true,
        ..Default::default()
    });

    let decoded = RendezvousMessage::parse_from_bytes(&message.write_to_bytes().unwrap()).unwrap();
    let Some(rendezvous_message::Union::RegisterPk(register_pk)) = decoded.union else {
        panic!("expected register_pk");
    };
    assert!(register_pk.no_register_device);

    let response = RegisterPkResponse {
        result: register_pk_response::Result::NOT_DEPLOYED.into(),
        ..Default::default()
    };
    assert_eq!(
        response.result.enum_value().unwrap(),
        register_pk_response::Result::NOT_DEPLOYED
    );
}

#[test]
fn client_1_4_7_punch_fields_round_trip() {
    let mut message = RendezvousMessage::new();
    message.set_punch_hole_request(PunchHoleRequest {
        id: "987654321".to_owned(),
        conn_type: ConnType::TERMINAL.into(),
        udp_port: 32116,
        force_relay: true,
        upnp_port: 32117,
        socket_addr_v6: vec![7, 8, 9].into(),
        ..Default::default()
    });

    let decoded = RendezvousMessage::parse_from_bytes(&message.write_to_bytes().unwrap()).unwrap();
    let Some(rendezvous_message::Union::PunchHoleRequest(request)) = decoded.union else {
        panic!("expected punch_hole_request");
    };
    assert_eq!(request.conn_type.enum_value().unwrap(), ConnType::TERMINAL);
    assert_eq!(request.udp_port, 32116);
    assert!(request.force_relay);
    assert_eq!(request.upnp_port, 32117);
    assert_eq!(request.socket_addr_v6.as_ref(), &[7, 8, 9]);
}

#[test]
fn client_1_5_0_webrtc_ice_fields_round_trip() {
    use hbb_common::rendezvous_proto::{IceCandidate, PunchHole, PunchHoleResponse};

    // Test PunchHoleRequest WebRTC offer
    let mut ph_req = RendezvousMessage::new();
    ph_req.set_punch_hole_request(PunchHoleRequest {
        id: "target_peer_123".to_owned(),
        webrtc_sdp_offer: "v=0\r\no=- 12345 2 IN IP4 127.0.0.1...".to_owned(),
        ..Default::default()
    });
    let decoded = RendezvousMessage::parse_from_bytes(&ph_req.write_to_bytes().unwrap()).unwrap();
    let Some(rendezvous_message::Union::PunchHoleRequest(req)) = decoded.union else {
        panic!("expected PunchHoleRequest");
    };
    assert_eq!(req.webrtc_sdp_offer, "v=0\r\no=- 12345 2 IN IP4 127.0.0.1...");

    // Test PunchHole WebRTC offer forward
    let mut ph = RendezvousMessage::new();
    ph.set_punch_hole(PunchHole {
        webrtc_sdp_offer: "v=0\r\no=- 12345 2 IN IP4 127.0.0.1...".to_owned(),
        ..Default::default()
    });
    let decoded = RendezvousMessage::parse_from_bytes(&ph.write_to_bytes().unwrap()).unwrap();
    let Some(rendezvous_message::Union::PunchHole(punch)) = decoded.union else {
        panic!("expected PunchHole");
    };
    assert_eq!(punch.webrtc_sdp_offer, "v=0\r\no=- 12345 2 IN IP4 127.0.0.1...");

    // Test PunchHoleResponse WebRTC answer
    let mut ph_resp = RendezvousMessage::new();
    ph_resp.set_punch_hole_response(PunchHoleResponse {
        webrtc_sdp_answer: "v=0\r\no=- 67890 2 IN IP4 127.0.0.1...".to_owned(),
        ..Default::default()
    });
    let decoded = RendezvousMessage::parse_from_bytes(&ph_resp.write_to_bytes().unwrap()).unwrap();
    let Some(rendezvous_message::Union::PunchHoleResponse(resp)) = decoded.union else {
        panic!("expected PunchHoleResponse");
    };
    assert_eq!(resp.webrtc_sdp_answer, "v=0\r\no=- 67890 2 IN IP4 127.0.0.1...");

    // Test IceCandidate Trickling message
    let mut ice_msg = RendezvousMessage::new();
    ice_msg.set_ice_candidate(IceCandidate {
        id: "peer_b".to_owned(),
        session_key: "session_key_abc".to_owned(),
        candidate: "candidate:1 1 UDP 2130706431 192.168.1.100 50000 typ host".to_owned(),
        ..Default::default()
    });
    let decoded = RendezvousMessage::parse_from_bytes(&ice_msg.write_to_bytes().unwrap()).unwrap();
    let Some(rendezvous_message::Union::IceCandidate(ice)) = decoded.union else {
        panic!("expected IceCandidate");
    };
    assert_eq!(ice.id, "peer_b");
    assert_eq!(ice.session_key, "session_key_abc");
    assert_eq!(ice.candidate, "candidate:1 1 UDP 2130706431 192.168.1.100 50000 typ host");
}

