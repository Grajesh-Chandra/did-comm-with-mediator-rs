# DIDComm v2.1 P2P Demo — Affinidi Messaging SDK

A full-stack demo application that showcases peer-to-peer communication using
Affinidi's DIDComm v2.1 mediator. The app visually exposes every request/response
packet in real time so customers can understand the protocol internals.

## Architecture

```
┌─────────────┐     REST/SSE     ┌──────────────────┐     DIDComm      ┌────────────────┐
│  React UI   │◄────────────────►│  Axum Demo Server │◄────────────────►│ Affinidi       │
│ (Alice/Bob  │                  │  (Rust backend)   │                  │ Mediator       │
│  chat panes)│                  │                   │                  │ (local Docker) │
└─────────────┘                  └──────────────────┘                  └────────────────┘
```

The backend maintains two in-memory DID identities (Alice and Bob), each configured
with `did:peer` method. Both connect to a locally running Affinidi mediator.

## Prerequisites

| Tool       | Version  | Purpose                              |
|------------|----------|--------------------------------------|
| Rust       | ≥ 1.85   | Backend (2024 edition)               |
| Node.js    | ≥ 20     | Frontend build                       |
| Docker     | Latest   | Redis + Mediator                     |
| Git        | Latest   | Clone the affinidi-tdk-rs repository |

## Quick Start

### 1. Clone and set up the mediator

```bash
# Clone the Affinidi TDK repository (needed for mediator + setup tools)
git clone https://github.com/affinidi/affinidi-tdk-rs.git
cd affinidi-tdk-rs/crates/affinidi-messaging
```

### 2. Start Redis

```bash
docker run --name=redis-local --publish=6379:6379 \
  --hostname=redis --restart=on-failure --detach redis:8.0
```

### 3. Set up the mediator environment

```bash
# From the affinidi-tdk-rs root:
cargo run --bin setup_environment
```

This interactive wizard generates:
- Mediator DID and secrets
- SSL certificates for local development
- Alice and Bob profiles (with `did:peer` identities)
- An `environments.json` configuration file

### 4. Start the mediator

```bash
cd crates/affinidi-messaging/affinidi-messaging-mediator
export REDIS_URL=redis://@localhost:6379
cargo run
```

Note the mediator DID printed in the startup logs.

### 5. Configure the demo app

```bash
# Back in this project directory:
cp .env.example .env

# Copy the environments.json from the TDK setup into this directory:
cp /path/to/affinidi-tdk-rs/environments.json .

# Set the TDK environment name (default: "default")
export TDK_ENVIRONMENT=default
```

### 6. Start the backend

```bash
cargo run
```

The Axum server starts on `http://localhost:3000`.

### 7. Start the frontend (development mode)

```bash
cd frontend
npm install
npm run dev
```

Open `http://localhost:5173` in your browser.

### 7b. Production build (served by Axum)

```bash
cd frontend
npm install
npm run build
# The built files go to frontend/dist/
# Axum serves them automatically at http://localhost:3000
```

## Docker Compose (alternative)

If you prefer a fully containerised setup:

```bash
docker compose up -d    # Starts Redis + Mediator
cargo run               # Demo backend
```

## API Endpoints

| Method | Path                    | Description                              |
|--------|-------------------------|------------------------------------------|
| GET    | `/api/identities`       | Returns Alice & Bob public DID info      |
| POST   | `/api/messages/send`    | Send a DIDComm message (Alice↔Bob)       |
| POST   | `/api/ping`             | Send a trust ping between identities     |
| GET    | `/api/messages/{alias}` | Fetch queued messages for alice or bob    |
| GET    | `/api/packets/stream`   | SSE stream of real-time packet events    |
| POST   | `/api/reset`            | Clear demo state and packet log          |

### Send Message

```bash
curl -X POST http://localhost:3000/api/messages/send \
  -H 'Content-Type: application/json' \
  -d '{"from": "alice", "to": "bob", "body": "Hello Bob!"}'
```

### Trust Ping

```bash
curl -X POST http://localhost:3000/api/ping \
  -H 'Content-Type: application/json' \
  -d '{"from": "alice", "to": "bob"}'
```

## Project Structure

```
├── Cargo.toml              # Rust dependencies
├── src/
│   ├── main.rs             # Axum server entry point
│   ├── api.rs              # REST + SSE endpoints
│   ├── identity.rs         # DID identity info types
│   ├── mediator.rs         # TDK/ATM initialisation & AppState
│   ├── packet_logger.rs    # PacketEvent types & broadcast channel
│   └── flows/
│       ├── mod.rs
│       ├── send_message.rs # Full annotated send flow (6 steps)
│       └── trust_ping.rs   # Trust ping/pong flow
├── frontend/
│   ├── package.json
│   ├── vite.config.js
│   ├── src/
│   │   ├── App.jsx         # Main layout (3-column)
│   │   ├── main.jsx        # React entry
│   │   ├── index.css       # Tailwind + animations
│   │   └── components/
│   │       ├── IdentityCard.jsx     # DID identity display
│   │       ├── ChatPane.jsx         # Message thread & input
│   │       ├── PacketInspector.jsx  # Live packet stream
│   │       ├── FlowDiagram.jsx      # SVG sequence diagram
│   │       └── ControlPanel.jsx     # Demo action buttons
├── .env.example
├── docker-compose.yml
├── Dockerfile.mediator
├── DEMO_SCRIPT.md
└── README.md
```

## Key Dependencies

| Crate                        | Version | Purpose                           |
|------------------------------|---------|-----------------------------------|
| `affinidi-tdk`               | 0.4     | Trust Development Kit             |
| `affinidi-messaging-sdk`     | 0.14    | ATM SDK (profiles, messaging)     |
| `affinidi-messaging-didcomm` | 0.11    | DIDComm protocol implementation   |
| `axum`                       | 0.8     | HTTP/WS server                    |
| `tokio`                      | 1       | Async runtime                     |
| `tower-http`                 | 0.6     | CORS + static file serving        |

## Troubleshooting

### "Alice/Bob not found in environment"
Run `setup_environment` from the affinidi-tdk-rs repo and ensure it creates
Alice and Bob profiles. Copy the resulting `environments.json` to this project
root.

### SSL/TLS certificate errors
The mediator uses self-signed certificates for local development. Make sure the
SSL certificate paths in `environments.json` are correct and accessible.

### Redis connection refused
Ensure Redis is running: `docker ps | grep redis`. Start it with:
```bash
docker run --name=redis-local --publish=6379:6379 --detach redis:8.0
```

### WebSocket connection issues
The SDK opens WebSocket connections after profile activation. Check the mediator
logs for connection errors and ensure port 7037 is accessible.

## License

Apache-2.0 — See the Affinidi TDK for licensing details.
