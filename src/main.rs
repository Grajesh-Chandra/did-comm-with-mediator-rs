mod api;
mod flows;
mod identity;
mod mediator;
mod packet_logger;

use std::env;
use std::net::SocketAddr;

use axum::{Router, routing::{get, post}};
use tower_http::cors::{Any, CorsLayer};
use tower_http::services::ServeDir;
use tracing::info;
use tracing_subscriber::{EnvFilter, fmt, prelude::*};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // ── Logging ─────────────────────────────────────────────────────────
    tracing_subscriber::registry()
        .with(fmt::layer())
        .with(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| {
                "info,didcomm_demo=debug,affinidi_messaging_sdk=debug".into()
            }),
        )
        .init();

    info!("╔══════════════════════════════════════════════════════╗");
    info!("║   DIDComm v2.1 P2P Demo — Affinidi Messaging SDK   ║");
    info!("╚══════════════════════════════════════════════════════╝");

    // ── Packet event channel ────────────────────────────────────────────
    let packet_tx = packet_logger::create_packet_channel();

    // ── Initialise TDK + ATM + profiles ─────────────────────────────────
    let environment_name =
        env::var("TDK_ENVIRONMENT").unwrap_or_else(|_| "default".to_string());

    let state = mediator::initialise(&environment_name, packet_tx).await?;

    // ── Axum router ─────────────────────────────────────────────────────
    let api_routes = Router::new()
        .route("/identities", get(api::get_identities))
        .route("/messages/send", post(api::send_message))
        .route("/ping", post(api::send_ping))
        .route("/messages/{alias}", get(api::fetch_messages))
        .route("/packets/stream", get(api::packet_stream))
        .route("/reset", post(api::reset_demo));

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let app = Router::new()
        .nest("/api", api_routes)
        // Serve the built React frontend from ./frontend/dist
        .fallback_service(ServeDir::new("frontend/dist").append_index_html_on_directories(true))
        .layer(cors)
        .with_state(state);

    // ── Start server ────────────────────────────────────────────────────
    let port: u16 = env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(3000);
    let addr = SocketAddr::from(([0, 0, 0, 0], port));

    info!("Server listening on http://{addr}");
    info!("Frontend: http://localhost:{port}");
    info!("SSE stream: http://localhost:{port}/api/packets/stream");

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
