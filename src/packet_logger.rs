/// Packet logger — captures every DIDComm pack/unpack event and fans it out
/// to connected frontend clients via SSE.
use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::broadcast;

/// The step within the DIDComm send/receive pipeline.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PacketStep {
    PlaintextMessage,
    SignedEnvelope,
    EncryptedPayload,
    EncryptedForward,
    MediatorSend,
    MediatorAck,
    TrustPing,
    TrustPong,
    MessagePickup,
    MessageDelivery,
}

impl PacketStep {
    /// Human-readable label for the frontend badge.
    pub fn label(&self) -> &'static str {
        match self {
            Self::PlaintextMessage => "① Plaintext Message",
            Self::SignedEnvelope => "② Signed Envelope",
            Self::EncryptedPayload => "③ Encrypted Payload",
            Self::EncryptedForward => "④ Forward Envelope",
            Self::MediatorSend => "⑤ Mediator Send",
            Self::MediatorAck => "⑤ Mediator ACK",
            Self::TrustPing => "① Trust Ping",
            Self::TrustPong => "② Trust Pong",
            Self::MessagePickup => "⑥ Message Pickup",
            Self::MessageDelivery => "⑥ Message Delivery",
        }
    }

    /// CSS colour class hint.
    pub fn color(&self) -> &'static str {
        match self {
            Self::PlaintextMessage => "blue",
            Self::SignedEnvelope => "yellow",
            Self::EncryptedPayload | Self::EncryptedForward => "red",
            Self::MediatorSend => "orange",
            Self::MediatorAck => "green",
            Self::TrustPing | Self::TrustPong => "purple",
            Self::MessagePickup | Self::MessageDelivery => "green",
        }
    }
}

/// Direction of the packet relative to this demo server.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PacketDirection {
    Outbound,
    Inbound,
}

/// A single packet event emitted to the frontend.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PacketEvent {
    pub id: String,
    pub timestamp: String,
    pub direction: PacketDirection,
    pub from: String,
    pub to: String,
    /// Human-readable alias ("alice", "bob", "mediator") for the `from` DID.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from_alias: Option<String>,
    /// Human-readable alias for the `to` DID.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub to_alias: Option<String>,
    pub step: PacketStep,
    pub label: String,
    pub color: String,
    pub raw_json: Value,
    /// Optional correlation ID linking related events together.
    pub correlation_id: Option<String>,
}

impl PacketEvent {
    pub fn new(
        direction: PacketDirection,
        from: impl Into<String>,
        to: impl Into<String>,
        step: PacketStep,
        raw_json: Value,
        correlation_id: Option<String>,
    ) -> Self {
        let label = step.label().to_string();
        let color = step.color().to_string();
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            timestamp: Utc::now().to_rfc3339(),
            direction,
            from: from.into(),
            to: to.into(),
            from_alias: None,
            to_alias: None,
            step,
            label,
            color,
            raw_json,
            correlation_id,
        }
    }

    /// Set human-readable aliases for from/to.
    pub fn with_aliases(mut self, from_alias: &str, to_alias: &str) -> Self {
        self.from_alias = Some(from_alias.to_string());
        self.to_alias = Some(to_alias.to_string());
        self
    }
}

/// Create a broadcast channel for packet events.
/// Returns (sender, _receiver). The receiver is dropped — subscribers use `sender.subscribe()`.
pub fn create_packet_channel() -> broadcast::Sender<PacketEvent> {
    let (tx, _rx) = broadcast::channel::<PacketEvent>(256);
    tx
}
