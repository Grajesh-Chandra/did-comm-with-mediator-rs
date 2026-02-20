/// REST + SSE endpoints served by Axum.
///
/// All handlers receive `Arc<AppState>` via Axum's state extraction.
use std::convert::Infallible;
use std::sync::Arc;
use std::time::Duration;

use axum::{
    Json,
    extract::State,
    http::StatusCode,
    response::{
        sse::{Event, Sse},
        IntoResponse, Response,
    },
};
use futures::stream::Stream;
use serde::{Deserialize, Serialize};
use serde_json::json;
use tokio_stream::wrappers::BroadcastStream;
use tokio_stream::StreamExt;
use tracing::error;

use crate::identity::IdentityInfo;
use crate::mediator::AppState;
use crate::flows;

// ─── Request / Response types ───────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct SendMessageRequest {
    pub from: String,
    pub to: String,
    pub body: String,
}

#[derive(Debug, Deserialize)]
pub struct PingRequest {
    pub from: String,
    pub to: String,
}

#[derive(Debug, Serialize)]
pub struct IdentitiesResponse {
    pub alice: IdentityInfo,
    pub bob: IdentityInfo,
}

#[derive(Debug, Serialize)]
pub struct ApiError {
    pub error: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub step: Option<String>,
}

fn api_error(status: StatusCode, msg: impl Into<String>, step: Option<&str>) -> Response {
    let body = ApiError {
        error: msg.into(),
        step: step.map(|s| s.to_string()),
    };
    (status, Json(body)).into_response()
}

// ─── GET /api/identities ────────────────────────────────────────────────────

pub async fn get_identities(
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    Json(IdentitiesResponse {
        alice: state.alice_info.clone(),
        bob: state.bob_info.clone(),
    })
}

// ─── POST /api/messages/send ────────────────────────────────────────────────

pub async fn send_message(
    State(state): State<Arc<AppState>>,
    Json(req): Json<SendMessageRequest>,
) -> Response {
    if req.body.trim().is_empty() {
        return api_error(StatusCode::BAD_REQUEST, "body cannot be empty", None);
    }

    match flows::send_message::send_message(&state, &req.from, &req.to, &req.body).await {
        Ok(events) => (
            StatusCode::OK,
            Json(json!({
                "status": "delivered",
                "events_count": events.len(),
                "correlation_id": events.first().and_then(|e| e.correlation_id.clone()),
            })),
        )
            .into_response(),
        Err(e) => {
            error!("send_message error: {e}");
            api_error(StatusCode::INTERNAL_SERVER_ERROR, e, Some("send_message"))
        }
    }
}

// ─── POST /api/ping ─────────────────────────────────────────────────────────

pub async fn send_ping(
    State(state): State<Arc<AppState>>,
    Json(req): Json<PingRequest>,
) -> Response {
    match flows::trust_ping::trust_ping(&state, &req.from, &req.to).await {
        Ok(events) => (
            StatusCode::OK,
            Json(json!({
                "status": "pong_received",
                "events_count": events.len(),
                "correlation_id": events.first().and_then(|e| e.correlation_id.clone()),
            })),
        )
            .into_response(),
        Err(e) => {
            error!("trust_ping error: {e}");
            api_error(StatusCode::INTERNAL_SERVER_ERROR, e, Some("trust_ping"))
        }
    }
}

// ─── GET /api/messages/{did} ────────────────────────────────────────────────

pub async fn fetch_messages(
    State(state): State<Arc<AppState>>,
    axum::extract::Path(alias): axum::extract::Path<String>,
) -> Response {
    use affinidi_messaging_sdk::messages::{FetchDeletePolicy, fetch::FetchOptions};

    let profile = match alias.to_lowercase().as_str() {
        "alice" => &state.alice_profile,
        "bob" => &state.bob_profile,
        _ => return api_error(StatusCode::BAD_REQUEST, format!("Unknown alias: {alias}"), None),
    };

    let fetch_opts = FetchOptions {
        limit: 50,
        delete_policy: FetchDeletePolicy::DoNotDelete,
        start_id: None,
    };

    match state.atm.fetch_messages(profile, &fetch_opts).await {
        Ok(response) => {
            let messages: Vec<serde_json::Value> = response
                .success
                .iter()
                .map(|m| {
                    json!({
                        "msg_id": m.msg_id,
                        "msg": m.msg,
                    })
                })
                .collect();
            (StatusCode::OK, Json(json!({ "messages": messages }))).into_response()
        }
        Err(e) => {
            error!("fetch_messages error: {e}");
            api_error(
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("{e}"),
                Some("fetch_messages"),
            )
        }
    }
}

// ─── GET /api/packets/stream (SSE) ─────────────────────────────────────────

pub async fn packet_stream(
    State(state): State<Arc<AppState>>,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let rx = state.packet_tx.subscribe();
    let stream = BroadcastStream::new(rx).filter_map(|result| match result {
        Ok(event) => {
            let data = serde_json::to_string(&event).unwrap_or_default();
            Some(Ok(Event::default().data(data).event("packet")))
        }
        Err(_) => None, // lagged receiver — skip
    });
    Sse::new(stream).keep_alive(
        axum::response::sse::KeepAlive::new()
            .interval(Duration::from_secs(15))
            .text("ping"),
    )
}

// ─── POST /api/reset ────────────────────────────────────────────────────────

pub async fn reset_demo(
    State(state): State<Arc<AppState>>,
) -> impl IntoResponse {
    // Emit a special "reset" event so the frontend clears its state
    use crate::packet_logger::{PacketDirection, PacketEvent, PacketStep};
    let evt = PacketEvent::new(
        PacketDirection::Outbound,
        "system",
        "all",
        PacketStep::PlaintextMessage,
        json!({ "action": "reset" }),
        None,
    );
    let _ = state.packet_tx.send(evt);
    Json(json!({ "status": "reset" }))
}
