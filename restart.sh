#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# restart.sh — Stop all services, optionally flush Redis (ACLs), restart
#
# Usage:
#   ./restart.sh              # Restart all services (keep data)
#   ./restart.sh --flush      # Flush Redis + restart (resets ACLs)
#   ./restart.sh --flush-acl  # Same as --flush
#   ./restart.sh --backend    # Restart backend only
#   ./restart.sh --mediator   # Restart mediator only
#   ./restart.sh --frontend   # Restart frontend only
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TDK_DIR="${SCRIPT_DIR}/affinidi-tdk-rs"
FRONTEND_DIR="${SCRIPT_DIR}/frontend"
MEDIATOR_DIR="${TDK_DIR}/crates/affinidi-messaging/affinidi-messaging-mediator"

# ── Colours ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── Parse arguments ─────────────────────────────────────────────────────
FLUSH_REDIS=false
ONLY_BACKEND=false
ONLY_MEDIATOR=false
ONLY_FRONTEND=false

for arg in "$@"; do
    case "$arg" in
        --flush|--flush-acl)
            FLUSH_REDIS=true
            ;;
        --backend)
            ONLY_BACKEND=true
            ;;
        --mediator)
            ONLY_MEDIATOR=true
            ;;
        --frontend)
            ONLY_FRONTEND=true
            ;;
        --help|-h)
            echo "Usage: ./restart.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --flush, --flush-acl   Flush Redis (clears all stored ACLs and messages)"
            echo "  --backend              Restart backend only"
            echo "  --mediator             Restart mediator only"
            echo "  --frontend             Restart frontend only"
            echo "  --help, -h             Show this help"
            echo ""
            echo "With no options, restarts all services (mediator, backend, frontend)."
            echo "Use --flush when ACL changes aren't taking effect."
            exit 0
            ;;
        *)
            warn "Unknown option: $arg (ignored)"
            ;;
    esac
done

# ─────────────────────────────────────────────────────────────────────────
# Stop helpers
# ─────────────────────────────────────────────────────────────────────────

stop_frontend() {
    info "Stopping frontend dev server..."
    local pid
    pid=$(lsof -ti :5173 2>/dev/null || true)
    if [ -n "${pid}" ]; then
        kill "${pid}" 2>/dev/null || true
        sleep 1
        kill -9 "${pid}" 2>/dev/null || true
        ok "Frontend stopped (PID: ${pid})"
    else
        ok "No frontend running"
    fi
}

stop_backend() {
    info "Stopping backend..."
    local pid
    pid=$(lsof -ti :3000 2>/dev/null || true)
    if [ -n "${pid}" ]; then
        kill "${pid}" 2>/dev/null || true
        sleep 1
        kill -9 "${pid}" 2>/dev/null || true
        ok "Backend stopped (PID: ${pid})"
    else
        ok "No backend running"
    fi
}

stop_mediator() {
    info "Stopping mediator..."

    # Try PID file first
    if [ -f "${SCRIPT_DIR}/.mediator.pid" ]; then
        local pid
        pid=$(cat "${SCRIPT_DIR}/.mediator.pid")
        if kill -0 "${pid}" 2>/dev/null; then
            kill "${pid}" 2>/dev/null || true
            sleep 2
            kill -9 "${pid}" 2>/dev/null || true
            ok "Mediator stopped (PID: ${pid})"
        else
            ok "Mediator PID ${pid} already stopped"
        fi
        rm -f "${SCRIPT_DIR}/.mediator.pid"
    fi

    # Also kill by port in case PID file is stale
    local pid
    pid=$(lsof -ti :7037 2>/dev/null || true)
    if [ -n "${pid}" ]; then
        kill "${pid}" 2>/dev/null || true
        sleep 2
        kill -9 "${pid}" 2>/dev/null || true
        ok "Mediator stopped (port 7037, PID: ${pid})"
    fi
}

# ─────────────────────────────────────────────────────────────────────────
# Flush Redis (clears ACLs, messages, sessions)
# ─────────────────────────────────────────────────────────────────────────

flush_redis() {
    info "Flushing Redis (clearing ACLs, messages, sessions)..."

    if command -v redis-cli >/dev/null 2>&1; then
        local result
        result=$(redis-cli FLUSHALL 2>&1)
        if [ "${result}" = "OK" ]; then
            ok "Redis flushed via redis-cli"
            return
        fi
    fi

    # Fallback: try via Docker
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^redis-local$'; then
        docker exec redis-local redis-cli FLUSHALL >/dev/null 2>&1
        ok "Redis flushed via Docker"
        return
    fi

    warn "Could not flush Redis — neither redis-cli nor Docker container available"
    warn "You may need to manually run: redis-cli FLUSHALL"
}

# ─────────────────────────────────────────────────────────────────────────
# Start helpers
# ─────────────────────────────────────────────────────────────────────────

ensure_redis() {
    info "Checking Redis..."
    if command -v redis-cli >/dev/null 2>&1 && redis-cli ping 2>/dev/null | grep -q PONG; then
        ok "Redis is running"
        return
    fi

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^redis-local$'; then
        ok "Redis container running"
        return
    fi

    # Try to start existing container
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^redis-local$'; then
        info "Starting stopped Redis container..."
        docker start redis-local >/dev/null
        sleep 2
        ok "Redis started"
        return
    fi

    # Create new Redis container
    info "Creating Redis container..."
    docker run \
        --name=redis-local \
        --publish=6379:6379 \
        --hostname=redis \
        --restart=on-failure \
        --detach \
        redis:8.0 >/dev/null
    sleep 2
    ok "Redis created and started"
}

start_mediator() {
    info "Starting mediator..."

    if lsof -i :7037 >/dev/null 2>&1; then
        ok "Mediator already running on port 7037"
        return
    fi

    if [ ! -d "${MEDIATOR_DIR}" ]; then
        error "Mediator directory not found: ${MEDIATOR_DIR}"
    fi

    # Export ACL config — SELF_MANAGE_LIST is required for Alice ↔ Bob
    # access_list_add to work without admin privileges
    export GLOBAL_DEFAULT_ACL="DENY_ALL,LOCAL,SEND_MESSAGES,RECEIVE_MESSAGES,SELF_MANAGE_LIST"
    export RUST_LOG="info,affinidi_messaging_mediator=debug"
    export REDIS_URL="redis://@localhost:6379"

    # Ensure did_web_self_hosted is disabled for did:peer mode
    local mediator_toml="${MEDIATOR_DIR}/conf/mediator.toml"
    local mediator_did_json="${MEDIATOR_DIR}/conf/mediator_did.json"
    if [ ! -f "${mediator_did_json}" ] && [ -f "${mediator_toml}" ]; then
        if grep -q '^did_web_self_hosted' "${mediator_toml}"; then
            sed -i.bak 's|^did_web_self_hosted = .*|# did_web_self_hosted disabled for did:peer|' "${mediator_toml}"
            rm -f "${mediator_toml}.bak"
            info "Disabled did_web_self_hosted (did:peer mode)"
        fi
    fi

    (cd "${MEDIATOR_DIR}" && cargo run 2>&1) > "${SCRIPT_DIR}/mediator.log" &
    local mediator_pid=$!
    echo "${mediator_pid}" > "${SCRIPT_DIR}/.mediator.pid"

    info "Waiting for mediator (PID: ${mediator_pid})..."
    local retries=120
    while [ $retries -gt 0 ]; do
        if lsof -i :7037 >/dev/null 2>&1; then
            ok "Mediator running on port 7037 (PID: ${mediator_pid})"

            # Verify ACL config
            if grep -q "self_manage_list: true" "${SCRIPT_DIR}/mediator.log" 2>/dev/null; then
                ok "ACL verified: SELF_MANAGE_LIST is active"
            else
                warn "Could not verify SELF_MANAGE_LIST in mediator log"
            fi
            return
        fi

        # Check if process died
        if ! kill -0 "${mediator_pid}" 2>/dev/null; then
            echo ""
            error "Mediator crashed during startup. Check: tail -50 mediator.log"
        fi

        retries=$((retries - 1))
        sleep 1
    done

    warn "Mediator may still be compiling. Monitor: tail -f mediator.log"
}

start_backend() {
    info "Starting backend..."

    if lsof -i :3000 >/dev/null 2>&1; then
        ok "Backend already running on port 3000"
        return
    fi

    export TDK_ENVIRONMENT="local"
    export RUST_LOG="info,didcomm_demo=debug,affinidi_messaging_sdk=info"

    (cd "${SCRIPT_DIR}" && cargo run 2>&1) > "${SCRIPT_DIR}/backend.log" &
    local backend_pid=$!
    echo "${backend_pid}" > "${SCRIPT_DIR}/.backend.pid"

    info "Waiting for backend (PID: ${backend_pid})..."
    local retries=120
    while [ $retries -gt 0 ]; do
        if lsof -i :3000 >/dev/null 2>&1; then
            ok "Backend running on port 3000 (PID: ${backend_pid})"
            return
        fi

        # Check if process died
        if ! kill -0 "${backend_pid}" 2>/dev/null; then
            echo ""
            error "Backend crashed during startup. Check: tail -50 backend.log"
        fi

        retries=$((retries - 1))
        sleep 1
    done

    warn "Backend may still be compiling. Monitor: tail -f backend.log"
}

start_frontend() {
    info "Starting frontend dev server..."

    if lsof -i :5173 >/dev/null 2>&1; then
        ok "Frontend already running on port 5173"
        return
    fi

    if [ ! -d "${FRONTEND_DIR}/node_modules" ]; then
        info "Installing frontend dependencies..."
        (cd "${FRONTEND_DIR}" && npm install --silent)
    fi

    (cd "${FRONTEND_DIR}" && npm run dev 2>&1) > "${SCRIPT_DIR}/frontend.log" &
    local frontend_pid=$!

    info "Waiting for frontend (PID: ${frontend_pid})..."
    local retries=30
    while [ $retries -gt 0 ]; do
        if lsof -i :5173 >/dev/null 2>&1; then
            ok "Frontend running on port 5173 (PID: ${frontend_pid})"
            return
        fi

        if ! kill -0 "${frontend_pid}" 2>/dev/null; then
            echo ""
            warn "Frontend failed to start. Check: tail -20 frontend.log"
            return
        fi

        retries=$((retries - 1))
        sleep 1
    done

    warn "Frontend may still be starting. Monitor: tail -f frontend.log"
}

# ─────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────

print_summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   All services restarted!                               ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}Frontend:${NC}  http://localhost:5173  (dev)"
    echo -e "  ${CYAN}Backend:${NC}   http://localhost:3000"
    echo -e "  ${CYAN}Mediator:${NC}  http://localhost:7037"
    echo ""
    echo -e "  ${BLUE}Logs:${NC}"
    echo -e "    tail -f mediator.log     # mediator"
    echo -e "    tail -f backend.log      # backend"
    echo -e "    tail -f frontend.log     # frontend"
    echo ""
    if $FLUSH_REDIS; then
        echo -e "  ${YELLOW}Redis was flushed — all ACLs, messages, sessions cleared.${NC}"
        echo -e "  ${YELLOW}ACL: DENY_ALL,LOCAL,SEND_MESSAGES,RECEIVE_MESSAGES,SELF_MANAGE_LIST${NC}"
        echo ""
    fi
}

# ─────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   DIDComm v2.1 P2P Demo — Restart Script               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # ── Single-service restart ───────────────────────────────────────────
    if $ONLY_BACKEND; then
        stop_backend
        sleep 1
        start_backend
        ok "Backend restarted"
        return
    fi

    if $ONLY_MEDIATOR; then
        stop_mediator
        sleep 1
        if $FLUSH_REDIS; then
            flush_redis
        fi
        ensure_redis
        start_mediator
        ok "Mediator restarted"
        return
    fi

    if $ONLY_FRONTEND; then
        stop_frontend
        sleep 1
        start_frontend
        ok "Frontend restarted"
        return
    fi

    # ── Full restart ─────────────────────────────────────────────────────
    info "Stopping all services..."
    stop_frontend
    stop_backend
    stop_mediator

    # Wait for ports to free
    sleep 2

    # Flush Redis if requested
    if $FLUSH_REDIS; then
        flush_redis
    fi

    info "Starting all services..."
    ensure_redis
    start_mediator
    start_backend
    start_frontend

    print_summary
}

main "$@"
