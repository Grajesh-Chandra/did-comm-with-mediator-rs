/// Full annotated send-message flow: Alice → Mediator → Bob (or vice versa).
///
/// Each step emits a `PacketEvent` to the broadcast channel so the frontend's
/// Packet Inspector can show the exact bytes on the wire.
use std::sync::Arc;
use std::time::{Duration, SystemTime};

use serde_json::{json, Value};
use tracing::{debug, error, info};
use uuid::Uuid;

use affinidi_messaging_didcomm::Message;
use affinidi_messaging_sdk::profiles::ATMProfile;

use crate::mediator::AppState;
use crate::packet_logger::{PacketDirection, PacketEvent, PacketStep};

/// Execute the full send flow and return the events that were emitted.
pub async fn send_message(
    state: &Arc<AppState>,
    from_alias: &str,
    to_alias: &str,
    body_text: &str,
) -> Result<Vec<PacketEvent>, String> {
    let correlation_id = Uuid::new_v4().to_string();
    let mut events: Vec<PacketEvent> = Vec::new();

    // Resolve sender / recipient profiles
    let (sender_profile, recipient_profile, sender_did, recipient_did, recipient_mediator_did) =
        resolve_profiles(state, from_alias, to_alias)?;

    let sender_profile = &sender_profile;
    let recipient_profile = &recipient_profile;

    let atm = &*state.atm;

    // ── Step 1: Build plaintext message ─────────────────────────────────
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap()
        .as_secs();

    let msg = Message::build(
        Uuid::new_v4().into(),
        "https://didcomm.org/basicmessage/2.0/message".into(),
        json!({ "content": body_text }),
    )
    .to(recipient_did.clone())
    .from(sender_did.clone())
    .created_time(now)
    .expires_time(now + 300) // 5 min expiry
    .finalize();

    let msg_id = msg.id.clone();
    let plaintext_json: Value =
        serde_json::to_value(&msg).unwrap_or_else(|_| json!({"error": "serialisation failed"}));

    let evt = PacketEvent::new(
        PacketDirection::Outbound,
        &sender_did,
        &recipient_did,
        PacketStep::PlaintextMessage,
        plaintext_json.clone(),
        Some(correlation_id.clone()),
    );
    debug!("{} → {} plaintext: {}", from_alias, to_alias, plaintext_json);
    let _ = state.packet_tx.send(evt.clone());
    events.push(evt);

    // ── Step 2: Pack encrypted + signed ─────────────────────────────────
    let packed_msg = atm
        .pack_encrypted(
            &msg,
            &recipient_did,
            Some(&sender_did),
            Some(&sender_did),
            None,
        )
        .await
        .map_err(|e| format!("pack_encrypted failed: {e}"))?;

    let encrypted_json: Value = serde_json::from_str(&packed_msg.0)
        .unwrap_or_else(|_| json!({"raw": packed_msg.0}));

    let evt = PacketEvent::new(
        PacketDirection::Outbound,
        &sender_did,
        &recipient_did,
        PacketStep::EncryptedPayload,
        encrypted_json.clone(),
        Some(correlation_id.clone()),
    );
    debug!("Encrypted payload for {to_alias}: {} bytes", packed_msg.0.len());
    let _ = state.packet_tx.send(evt.clone());
    events.push(evt);

    // ── Step 3: Wrap in forward envelope for the mediator ───────────────
    let (_forward_id, forward_msg) = atm
        .routing()
        .forward_message(
            sender_profile,
            false,
            &packed_msg.0,
            &recipient_mediator_did,
            &recipient_did,
            None,
            None,
        )
        .await
        .map_err(|e| format!("forward_message failed: {e}"))?;

    let forward_json: Value = serde_json::from_str(&forward_msg)
        .unwrap_or_else(|_| json!({"raw": forward_msg}));

    let evt = PacketEvent::new(
        PacketDirection::Outbound,
        &sender_did,
        &recipient_mediator_did,
        PacketStep::EncryptedForward,
        forward_json.clone(),
        Some(correlation_id.clone()),
    );
    debug!("Forward envelope → mediator: {} bytes", forward_msg.len());
    let _ = state.packet_tx.send(evt.clone());
    events.push(evt);

    // ── Step 4: Send to mediator ────────────────────────────────────────
    let evt = PacketEvent::new(
        PacketDirection::Outbound,
        &sender_did,
        "mediator",
        PacketStep::MediatorSend,
        json!({ "msg_id": &msg_id, "size_bytes": forward_msg.len() }),
        Some(correlation_id.clone()),
    );
    let _ = state.packet_tx.send(evt.clone());
    events.push(evt);

    match atm
        .send_message(sender_profile, &forward_msg, &msg_id, false, false)
        .await
    {
        Ok(response) => {
            let ack_json =
                serde_json::to_value(&format!("{:?}", response)).unwrap_or(json!("ok"));
            let evt = PacketEvent::new(
                PacketDirection::Inbound,
                "mediator",
                &sender_did,
                PacketStep::MediatorAck,
                json!({ "status": "stored", "response": ack_json }),
                Some(correlation_id.clone()),
            );
            info!("{from_alias} sent message {msg_id} to mediator");
            let _ = state.packet_tx.send(evt.clone());
            events.push(evt);
        }
        Err(e) => {
            error!("send_message failed: {e}");
            return Err(format!("send_message failed: {e}"));
        }
    }

    // ── Step 5: Bob picks up via WebSocket live stream ──────────────────
    let evt = PacketEvent::new(
        PacketDirection::Inbound,
        "mediator",
        &recipient_did,
        PacketStep::MessagePickup,
        json!({ "msg_id": &msg_id, "waiting": true }),
        Some(correlation_id.clone()),
    );
    let _ = state.packet_tx.send(evt.clone());
    events.push(evt);

    match atm
        .message_pickup()
        .live_stream_get(recipient_profile, &msg_id, Duration::from_secs(10), true)
        .await
    {
        Ok(Some((decrypted_msg, _metadata))) => {
            let delivery_json = serde_json::to_value(&decrypted_msg)
                .unwrap_or_else(|_| json!({"id": decrypted_msg.id}));

            let evt = PacketEvent::new(
                PacketDirection::Inbound,
                &sender_did,
                &recipient_did,
                PacketStep::MessageDelivery,
                delivery_json,
                Some(correlation_id.clone()),
            );
            info!("{to_alias} received message {msg_id}");
            let _ = state.packet_tx.send(evt.clone());
            events.push(evt);
        }
        Ok(None) => {
            info!("No message received within timeout for {msg_id}");
            let evt = PacketEvent::new(
                PacketDirection::Inbound,
                "mediator",
                &recipient_did,
                PacketStep::MessageDelivery,
                json!({ "status": "timeout", "msg_id": &msg_id }),
                Some(correlation_id.clone()),
            );
            let _ = state.packet_tx.send(evt.clone());
            events.push(evt);
        }
        Err(e) => {
            error!("live_stream_get failed: {e}");
            let evt = PacketEvent::new(
                PacketDirection::Inbound,
                "mediator",
                &recipient_did,
                PacketStep::MessageDelivery,
                json!({ "error": format!("{e}") }),
                Some(correlation_id.clone()),
            );
            let _ = state.packet_tx.send(evt.clone());
            events.push(evt);
        }
    }

    Ok(events)
}

/// Resolve aliases ("alice"/"bob") to (sender_profile, recipient_profile, sender_did, recipient_did, recipient_mediator_did).
fn resolve_profiles(
    state: &Arc<AppState>,
    from: &str,
    to: &str,
) -> Result<(Arc<ATMProfile>, Arc<ATMProfile>, String, String, String), String> {
    let from_lower = from.to_lowercase();
    let to_lower = to.to_lowercase();

    let (sender_profile, sender_did) = match from_lower.as_str() {
        "alice" => (state.alice_profile.clone(), state.alice_info.did.clone()),
        "bob" => (state.bob_profile.clone(), state.bob_info.did.clone()),
        _ => return Err(format!("Unknown sender: {from}")),
    };

    let (recipient_profile, recipient_did, recipient_mediator_did) = match to_lower.as_str() {
        "alice" => (
            state.alice_profile.clone(),
            state.alice_info.did.clone(),
            state.alice_mediator_did.clone(),
        ),
        "bob" => (
            state.bob_profile.clone(),
            state.bob_info.did.clone(),
            state.bob_mediator_did.clone(),
        ),
        _ => return Err(format!("Unknown recipient: {to}")),
    };

    Ok((sender_profile, recipient_profile, sender_did, recipient_did, recipient_mediator_did))
}
