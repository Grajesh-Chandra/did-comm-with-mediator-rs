#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# setup.sh — One-command setup for the DIDComm v2.1 P2P Demo
#
# Prerequisites: Docker, Rust ≥1.85, Node.js ≥20, git
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TDK_DIR="${SCRIPT_DIR}/affinidi-tdk-rs"
FRONTEND_DIR="${SCRIPT_DIR}/frontend"
ENV_FILE="${SCRIPT_DIR}/.env"

# ── Colours ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

header() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   DIDComm v2.1 P2P Demo — Setup Script                 ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ── Check prerequisites ─────────────────────────────────────────────────
check_prereqs() {
    info "Checking prerequisites..."

    command -v docker   >/dev/null 2>&1 || error "Docker is required but not installed."
    command -v cargo    >/dev/null 2>&1 || error "Rust/Cargo is required but not installed."
    command -v node     >/dev/null 2>&1 || error "Node.js is required but not installed."
    command -v npm      >/dev/null 2>&1 || error "npm is required but not installed."
    command -v git      >/dev/null 2>&1 || error "git is required but not installed."

    # Check Rust version
    local rust_version
    rust_version=$(rustc --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    info "Rust version: ${rust_version}"

    # Check Node version
    local node_version
    node_version=$(node --version | tr -d 'v')
    info "Node version: ${node_version}"

    ok "All prerequisites found"
}

# ── Step 1: Start Redis ─────────────────────────────────────────────────
start_redis() {
    info "Step 1/6: Starting Redis..."

    if docker ps --format '{{.Names}}' | grep -q '^redis-local$'; then
        ok "Redis already running"
        return
    fi

    if docker ps -a --format '{{.Names}}' | grep -q '^redis-local$'; then
        info "Starting existing Redis container..."
        docker start redis-local >/dev/null
    else
        info "Creating new Redis container..."
        docker run \
            --name=redis-local \
            --publish=6379:6379 \
            --hostname=redis \
            --restart=on-failure \
            --detach \
            redis:8.0 >/dev/null
    fi

    # Wait for Redis to be ready
    local retries=10
    while [ $retries -gt 0 ]; do
        if docker exec redis-local redis-cli ping 2>/dev/null | grep -q PONG; then
            ok "Redis is running on port 6379"
            return
        fi
        retries=$((retries - 1))
        sleep 1
    done
    error "Redis failed to start"
}

# ── Step 2: Clone / update TDK ──────────────────────────────────────────
setup_tdk() {
    info "Step 2/6: Setting up Affinidi TDK..."

    if [ -d "${TDK_DIR}" ]; then
        info "TDK repo already exists. Pulling latest..."
        (cd "${TDK_DIR}" && git pull --quiet) || warn "git pull failed — using existing version"
    else
        info "Cloning affinidi-tdk-rs (this may take a minute)..."
        git clone --depth 1 https://github.com/affinidi/affinidi-tdk-rs.git "${TDK_DIR}"
    fi

    ok "TDK repository ready at ${TDK_DIR}"
}

# ── Step 3: Run setup_environment ────────────────────────────────────────
setup_environment() {
    info "Step 3/6: Running setup_environment to configure mediator + identities..."

    local MESSAGING_DIR="${TDK_DIR}/crates/affinidi-messaging"

    if [ -f "${MESSAGING_DIR}/environments.json" ] || [ -f "${TDK_DIR}/environments.json" ]; then
        warn "environments.json already exists. Skipping setup_environment."
        warn "Delete it from ${MESSAGING_DIR}/ to regenerate."
    else
        info "Building and running setup_environment (interactive)..."
        info "When prompted:"
        info "  - Choose 'Local' mediator"
        info "  - Create new JWT authorization secrets → Yes"
        info "  - Save mediator configuration → Yes"
        info "  - Create SSL certificates → Yes"
        info "  - Create friends (Alice, Bob, etc.) → Yes"
        info "  - Save friends → Yes"
        echo ""

        # Clear existing mediator_did.json so the wizard creates a NEW DID
        # (reusing an existing DID skips secrets.json generation)
        local mediator_did_json="${MESSAGING_DIR}/affinidi-messaging-mediator/conf/mediator_did.json"
        if [ -f "${mediator_did_json}" ]; then
            rm -f "${mediator_did_json}"
            info "Removed old mediator_did.json to force fresh DID creation"
        fi

        # Blank the mediator_did line in mediator.toml so the wizard doesn't
        # detect an existing DID and offer to reuse it (which skips secrets.json)
        local mediator_toml="${MESSAGING_DIR}/affinidi-messaging-mediator/conf/mediator.toml"
        if [ -f "${mediator_toml}" ]; then
            sed -i.bak 's/^mediator_did = .*/mediator_did = ""/' "${mediator_toml}"
            rm -f "${mediator_toml}.bak"
            info "Cleared mediator_did in mediator.toml for fresh setup"
        fi

        # setup_environment requires CWD inside crates/affinidi-messaging
        (cd "${MESSAGING_DIR}" && cargo run --bin setup_environment)
    fi

    # environments.json is generated inside crates/affinidi-messaging/
    local env_json="${MESSAGING_DIR}/environments.json"
    # Also check repo root as a fallback
    if [ ! -f "${env_json}" ] && [ -f "${TDK_DIR}/environments.json" ]; then
        env_json="${TDK_DIR}/environments.json"
    fi

    if [ -f "${env_json}" ]; then
        cp "${env_json}" "${SCRIPT_DIR}/environments.json"
        ok "environments.json copied to project root"
    else
        error "environments.json not found. Run setup_environment manually from ${MESSAGING_DIR}"
    fi

    # Verify secrets.json was generated (critical for mediator startup)
    local secrets_file="${MESSAGING_DIR}/affinidi-messaging-mediator/conf/secrets.json"
    if [ ! -f "${secrets_file}" ]; then
        echo ""
        warn "secrets.json was NOT generated at:"
        warn "  ${secrets_file}"
        warn ""
        warn "This means the 'Save mediator configuration?' prompt was likely"
        warn "not confirmed during setup_environment."
        warn ""
        warn "Please re-run setup_environment manually:"
        warn "  cd ${MESSAGING_DIR}"
        warn "  cargo run --bin setup_environment"
        warn ""
        warn "Make sure to confirm 'Yes' when asked to save the mediator config."
        error "secrets.json is required for the mediator to start."
    fi
    ok "secrets.json verified"

    # Copy SSL certs and config files (including secrets.json)
    local certs_dir="${TDK_DIR}/crates/affinidi-messaging/affinidi-messaging-mediator/conf"
    if [ -d "${certs_dir}" ]; then
        mkdir -p "${SCRIPT_DIR}/conf"
        cp -r "${certs_dir}"/* "${SCRIPT_DIR}/conf/" 2>/dev/null || true
        ok "SSL certificates and secrets copied"
    fi
}

# ── Step 4: Start the mediator ───────────────────────────────────────────
start_mediator() {
    info "Step 4/6: Starting Affinidi Mediator..."

    local mediator_dir="${TDK_DIR}/crates/affinidi-messaging/affinidi-messaging-mediator"

    if ! [ -d "${mediator_dir}" ]; then
        error "Mediator directory not found at ${mediator_dir}"
    fi

    # Check if mediator is already running
    if lsof -i :7037 >/dev/null 2>&1; then
        ok "Mediator appears to be running on port 7037"
        return
    fi

    info "Building and starting mediator (background)..."
    info "Mediator logs: ${SCRIPT_DIR}/mediator.log"

    export REDIS_URL="redis://@localhost:6379"
    export RUST_LOG="info,affinidi_messaging_mediator=debug"

    (cd "${mediator_dir}" && cargo run 2>&1) > "${SCRIPT_DIR}/mediator.log" &
    local mediator_pid=$!
    echo "${mediator_pid}" > "${SCRIPT_DIR}/.mediator.pid"

    # Wait for mediator to start
    info "Waiting for mediator to start (max 120s)..."
    local retries=120
    while [ $retries -gt 0 ]; do
        if lsof -i :7037 >/dev/null 2>&1; then
            ok "Mediator running on port 7037 (PID: ${mediator_pid})"
            return
        fi
        retries=$((retries - 1))
        sleep 1
    done

    warn "Mediator may still be compiling. Check mediator.log"
    warn "PID saved to .mediator.pid — monitor with: tail -f mediator.log"
}

# ── Step 5: Set up .env ─────────────────────────────────────────────────
setup_env_file() {
    info "Step 5/6: Configuring .env file..."

    if [ ! -f "${ENV_FILE}" ]; then
        cat > "${ENV_FILE}" << 'EOF'
TDK_ENVIRONMENT=default
PORT=3000
RUST_LOG=info,didcomm_demo=debug,affinidi_messaging_sdk=debug
EOF
        ok ".env file created"
    else
        ok ".env file already exists"
    fi
}

# ── Step 6: Install frontend dependencies ────────────────────────────────
setup_frontend() {
    info "Step 6/6: Installing frontend dependencies..."

    (cd "${FRONTEND_DIR}" && npm install --silent)

    ok "Frontend dependencies installed"

    info "Building frontend for production..."
    (cd "${FRONTEND_DIR}" && npm run build --silent) || warn "Frontend build failed — use dev mode instead"

    ok "Frontend build complete"
}

# ── Summary ──────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   Setup Complete!                                       ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BLUE}Start the demo backend:${NC}"
    echo -e "    cargo run"
    echo ""
    echo -e "  ${BLUE}Start the frontend (dev mode):${NC}"
    echo -e "    cd frontend && npm run dev"
    echo ""
    echo -e "  ${BLUE}Open in browser:${NC}"
    echo -e "    http://localhost:5173  (dev mode)"
    echo -e "    http://localhost:3000  (production build served by Axum)"
    echo ""
    echo -e "  ${BLUE}Monitor mediator:${NC}"
    echo -e "    tail -f mediator.log"
    echo ""
    echo -e "  ${BLUE}Cleanup:${NC}"
    echo -e "    ./cleanup.sh"
    echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────
main() {
    header
    check_prereqs
    start_redis
    setup_tdk
    setup_environment
    start_mediator
    setup_env_file
    setup_frontend
    print_summary
}

main "$@"
