/// Trust Ping flow — sends a DIDComm trust-ping and captures the pong response.
///
/// Emits `PacketEvent`s for both the outbound ping and inbound pong so the
/// Packet Inspector can visualise the round-trip.
use std::sync::Arc;
use std::time::Duration;

use serde_json::json;
use tracing::{debug, error, info};
use uuid::Uuid;

use crate::mediator::AppState;
use crate::packet_logger::{PacketDirection, PacketEvent, PacketStep};

/// Send a trust-ping from `from_alias` to `to_alias` and wait for the pong.
pub async fn trust_ping(
    state: &Arc<AppState>,
    from_alias: &str,
    to_alias: &str,
) -> Result<Vec<PacketEvent>, String> {
    let correlation_id = Uuid::new_v4().to_string();
    let mut events: Vec<PacketEvent> = Vec::new();
    let atm = &*state.atm;

    // Resolve profiles
    let (sender_profile, sender_did, target_did) = match from_alias.to_lowercase().as_str() {
        "alice" => {
            let target = match to_alias.to_lowercase().as_str() {
                "bob" => state.bob_info.did.clone(),
                "mediator" => state.alice_mediator_did.clone(),
                _ => return Err(format!("Unknown ping target: {to_alias}")),
            };
            (state.alice_profile.clone(), state.alice_info.did.clone(), target)
        }
        "bob" => {
            let target = match to_alias.to_lowercase().as_str() {
                "alice" => state.alice_info.did.clone(),
                "mediator" => state.bob_mediator_did.clone(),
                _ => return Err(format!("Unknown ping target: {to_alias}")),
            };
            (state.bob_profile.clone(), state.bob_info.did.clone(), target)
        }
        _ => return Err(format!("Unknown sender: {from_alias}")),
    };
    let sender_profile = &sender_profile;

    // ── Step 1: Send Ping ──────────────────────────────────────────────
    let ping_evt = PacketEvent::new(
        PacketDirection::Outbound,
        &sender_did,
        &target_did,
        PacketStep::TrustPing,
        json!({
            "type": "https://didcomm.org/trust-ping/2.0/ping",
            "from": &sender_did,
            "to": &target_did,
            "body": { "response_requested": true }
        }),
        Some(correlation_id.clone()),
    );
    let _ = state.packet_tx.send(ping_evt.clone());
    events.push(ping_evt);

    let response = atm
        .trust_ping()
        .send_ping(sender_profile, &target_did, true, true, false)
        .await
        .map_err(|e| format!("send_ping failed: {e}"))?;

    info!(
        "{from_alias} → {to_alias} PING sent (hash: {})",
        response.message_hash
    );

    let ack_evt = PacketEvent::new(
        PacketDirection::Inbound,
        "mediator",
        &sender_did,
        PacketStep::MediatorAck,
        json!({
            "message_hash": &response.message_hash,
            "message_id": &response.message_id,
        }),
        Some(correlation_id.clone()),
    );
    let _ = state.packet_tx.send(ack_evt.clone());
    events.push(ack_evt);

    // ── Step 2: Receive Pong via live stream ────────────────────────────
    match atm
        .message_pickup()
        .live_stream_get(sender_profile, &response.message_id, Duration::from_secs(10), false)
        .await
    {
        Ok(Some((msg, _metadata))) => {
            let pong_json =
                serde_json::to_value(&msg).unwrap_or_else(|_| json!({"id": msg.id}));
            let pong_evt = PacketEvent::new(
                PacketDirection::Inbound,
                &target_did,
                &sender_did,
                PacketStep::TrustPong,
                pong_json,
                Some(correlation_id.clone()),
            );
            info!("{from_alias} ← {to_alias} PONG received");
            let _ = state.packet_tx.send(pong_evt.clone());
            events.push(pong_evt);
        }
        Ok(None) => {
            debug!("No pong received within timeout");
            let timeout_evt = PacketEvent::new(
                PacketDirection::Inbound,
                &target_did,
                &sender_did,
                PacketStep::TrustPong,
                json!({ "status": "timeout" }),
                Some(correlation_id.clone()),
            );
            let _ = state.packet_tx.send(timeout_evt.clone());
            events.push(timeout_evt);
        }
        Err(e) => {
            error!("Pong pickup failed: {e}");
            let err_evt = PacketEvent::new(
                PacketDirection::Inbound,
                &target_did,
                &sender_did,
                PacketStep::TrustPong,
                json!({ "error": format!("{e}") }),
                Some(correlation_id.clone()),
            );
            let _ = state.packet_tx.send(err_evt.clone());
            events.push(err_evt);
        }
    }

    Ok(events)
}
