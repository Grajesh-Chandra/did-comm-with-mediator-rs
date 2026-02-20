#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# cleanup.sh — Tear down all demo resources
#
# Usage:
#   ./cleanup.sh          # Stop services, keep data
#   ./cleanup.sh --all    # Stop services AND remove cloned repos, certs, etc.
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TDK_DIR="${SCRIPT_DIR}/affinidi-tdk-rs"

# ── Colours ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

FULL_CLEANUP=false
if [[ "${1:-}" == "--all" ]] || [[ "${1:-}" == "-a" ]]; then
    FULL_CLEANUP=true
fi

header() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║   DIDComm v2.1 P2P Demo — Cleanup Script               ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ── Stop mediator ────────────────────────────────────────────────────────
stop_mediator() {
    info "Stopping Affinidi Mediator..."

    if [ -f "${SCRIPT_DIR}/.mediator.pid" ]; then
        local pid
        pid=$(cat "${SCRIPT_DIR}/.mediator.pid")
        if kill -0 "${pid}" 2>/dev/null; then
            kill "${pid}" 2>/dev/null || true
            # Wait a moment for graceful shutdown
            sleep 2
            kill -9 "${pid}" 2>/dev/null || true
            ok "Mediator stopped (PID: ${pid})"
        else
            ok "Mediator process already stopped"
        fi
        rm -f "${SCRIPT_DIR}/.mediator.pid"
    else
        # Try to find by port
        local pid
        pid=$(lsof -ti :7037 2>/dev/null || true)
        if [ -n "${pid}" ]; then
            kill "${pid}" 2>/dev/null || true
            ok "Mediator stopped (PID: ${pid})"
        else
            ok "No mediator process found"
        fi
    fi
}

# ── Stop Redis ───────────────────────────────────────────────────────────
stop_redis() {
    info "Stopping Redis..."

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^redis-local$'; then
        docker stop redis-local >/dev/null 2>&1
        ok "Redis container stopped"
    else
        ok "Redis container not running"
    fi

    if $FULL_CLEANUP; then
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^redis-local$'; then
            docker rm redis-local >/dev/null 2>&1
            ok "Redis container removed"
        fi
    fi
}

# ── Docker full prune ────────────────────────────────────────────────────
docker_full_prune() {
    if $FULL_CLEANUP; then
        info "Removing all stopped containers..."
        docker container prune -f >/dev/null 2>&1 || true
        ok "Stopped containers removed"

        info "Removing all unused images..."
        docker image prune -a -f >/dev/null 2>&1 || true
        ok "Unused images removed"

        info "Removing all unused volumes..."
        docker volume prune -f >/dev/null 2>&1 || true
        ok "Unused volumes removed"

        info "Removing all unused networks..."
        docker network prune -f >/dev/null 2>&1 || true
        ok "Unused networks removed"

        info "Running full Docker system prune..."
        docker system prune -a -f --volumes >/dev/null 2>&1 || true
        ok "Docker system pruned (containers, images, volumes, networks)"
    fi
}

# ── Stop Docker Compose services ─────────────────────────────────────────
stop_compose() {
    if [ -f "${SCRIPT_DIR}/docker-compose.yml" ]; then
        info "Stopping Docker Compose services..."
        (cd "${SCRIPT_DIR}" && docker compose down 2>/dev/null) || true
        ok "Docker Compose services stopped"
    fi
}

# ── Kill any frontend dev server ─────────────────────────────────────────
stop_frontend() {
    info "Stopping frontend dev server..."

    local pid
    pid=$(lsof -ti :5173 2>/dev/null || true)
    if [ -n "${pid}" ]; then
        kill "${pid}" 2>/dev/null || true
        ok "Frontend dev server stopped (PID: ${pid})"
    else
        ok "No frontend dev server running"
    fi
}

# ── Kill backend server ─────────────────────────────────────────────────
stop_backend() {
    info "Stopping demo backend..."

    local pid
    pid=$(lsof -ti :3000 2>/dev/null || true)
    if [ -n "${pid}" ]; then
        kill "${pid}" 2>/dev/null || true
        ok "Backend stopped (PID: ${pid})"
    else
        ok "No backend running"
    fi
}

# ── Clean generated files ───────────────────────────────────────────────
clean_files() {
    info "Cleaning generated files..."

    rm -f "${SCRIPT_DIR}/mediator.log"
    rm -f "${SCRIPT_DIR}/.mediator.pid"
    ok "Log and PID files removed"

    if $FULL_CLEANUP; then
        info "Full cleanup: removing additional artifacts..."

        # Reset TDK mediator config to git defaults before removing
        if [ -d "${TDK_DIR}/.git" ]; then
            info "Resetting TDK mediator config to git defaults..."
            local messaging_dir="${TDK_DIR}/crates/affinidi-messaging"
            local mediator_conf="${messaging_dir}/affinidi-messaging-mediator/conf"

            # Reset mediator.toml to original template
            (cd "${TDK_DIR}" && git checkout -- \
                crates/affinidi-messaging/affinidi-messaging-mediator/conf/mediator.toml \
                crates/affinidi-messaging/affinidi-messaging-mediator/conf/mediator_did.json \
                2>/dev/null) || true
            ok "Reset mediator.toml and mediator_did.json to git defaults"

            # Remove generated secrets and keys
            rm -f "${mediator_conf}/secrets.json"
            ok "Removed mediator secrets.json"

            # Remove generated SSL keys (keep directory structure)
            rm -rf "${mediator_conf}/keys"
            ok "Removed mediator SSL keys"

            # Remove environments.json from TDK
            rm -f "${messaging_dir}/environments.json"
            ok "Removed TDK environments.json"
        fi

        # Remove cloned TDK repo
        if [ -d "${TDK_DIR}" ]; then
            rm -rf "${TDK_DIR}"
            ok "Removed affinidi-tdk-rs clone"
        fi

        # Remove generated config from demo project root
        rm -f "${SCRIPT_DIR}/environments.json"
        ok "Removed environments.json"

        # Remove SSL certs
        rm -rf "${SCRIPT_DIR}/conf"
        ok "Removed conf/ directory"

        # Remove .env (keep .env.example)
        rm -f "${SCRIPT_DIR}/.env"
        ok "Removed .env"

        # Remove frontend build artifacts
        rm -rf "${SCRIPT_DIR}/frontend/dist"
        rm -rf "${SCRIPT_DIR}/frontend/node_modules"
        ok "Removed frontend/dist and node_modules"

        # Remove Rust build artifacts
        rm -rf "${SCRIPT_DIR}/target"
        ok "Removed Rust target/ directory"
    fi
}

# ── Summary ──────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    if $FULL_CLEANUP; then
        echo -e "${GREEN}Full cleanup complete.${NC} All services stopped and artifacts removed."
        echo -e "Run ${BLUE}./setup.sh${NC} to set everything up again."
    else
        echo -e "${GREEN}Cleanup complete.${NC} All services stopped."
        echo -e "Run ${BLUE}./cleanup.sh --all${NC} to also remove cloned repos and build artifacts."
        echo -e "Run ${BLUE}./setup.sh${NC} to restart everything."
    fi
    echo ""
}

# ─── Main ────────────────────────────────────────────────────────────────
main() {
    header
    stop_frontend
    stop_backend
    stop_mediator
    stop_compose
    stop_redis
    docker_full_prune
    clean_files
    print_summary
}

main "$@"
