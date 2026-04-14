#!/usr/bin/env bash
# bootstrap.sh — one-shot deployment script for the monitoring stack
# Usage: ./bootstrap.sh
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo ""
echo "  ┌─────────────────────────────────────────┐"
echo "  │   Monitoring Stack — Bootstrap Script   │"
echo "  └─────────────────────────────────────────┘"
echo ""

# ─── 1. Check prerequisites ───────────────────────────────────────────────────
info "Checking prerequisites..."

command -v docker >/dev/null 2>&1 || error "Docker is not installed. Visit https://docs.docker.com/get-docker/"

# Support both 'docker compose' (v2 plugin) and 'docker-compose' (v1 standalone)
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  error "Docker Compose not found. Install Docker Desktop or the Compose plugin."
fi

docker info >/dev/null 2>&1 || error "Docker daemon is not running. Start Docker and try again."

success "Docker $(docker --version | awk '{print $3}' | tr -d ',')"
success "Compose: $($COMPOSE_CMD version --short)"

# ─── 2. Set up environment file ───────────────────────────────────────────────
info "Checking environment configuration..."

if [ ! -f .env ]; then
  cp .env.example .env
  warn ".env file created from .env.example"
  warn "Default Grafana password is 'changeme' — edit .env before exposing this to a network."
else
  success ".env file already exists, leaving it untouched."
fi

# Warn if default password is still set
if grep -q "GF_ADMIN_PASSWORD=changeme" .env 2>/dev/null; then
  warn "You are using the default Grafana password. Change GF_ADMIN_PASSWORD in .env."
fi

# ─── 3. Pull all Docker images ────────────────────────────────────────────────
info "Pulling Docker images (this may take a few minutes on first run)..."
$COMPOSE_CMD pull
success "All images pulled."

# ─── 4. Start the stack ──────────────────────────────────────────────────────
info "Starting monitoring stack..."
$COMPOSE_CMD up -d
success "Stack started."

# ─── 5. Health check ─────────────────────────────────────────────────────────
info "Waiting for services to become healthy (30s)..."
sleep 30

check_service() {
  local name=$1
  local url=$2
  if curl -sf "$url" >/dev/null 2>&1; then
    success "$name is up at $url"
  else
    warn "$name did not respond at $url — it may still be starting."
  fi
}

check_service "Grafana"       "http://localhost:3000/api/health"
check_service "Prometheus"    "http://localhost:9090/-/healthy"
check_service "Loki"          "http://localhost:3100/ready"
check_service "Alertmanager"  "http://localhost:9093/-/healthy"
check_service "Alloy"         "http://localhost:12345/-/healthy"

# ─── 6. Summary ──────────────────────────────────────────────────────────────
echo ""
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │   Stack is running. Access points:                      │"
echo "  │                                                         │"
echo "  │   Grafana        →  http://localhost:3000               │"
echo "  │   Prometheus     →  http://localhost:9090               │"
echo "  │   Alertmanager   →  http://localhost:9093               │"
echo "  │   Alloy UI       →  http://localhost:12345              │"
echo "  │   Loki           →  http://localhost:3100               │"
echo "  │                                                         │"
echo "  │   Grafana login: see GF_ADMIN_USER / PASSWORD in .env   │"
echo "  └─────────────────────────────────────────────────────────┘"
echo ""
info "To stop the stack:  $COMPOSE_CMD down"
info "To view logs:       $COMPOSE_CMD logs -f"
info "To remove all data: $COMPOSE_CMD down -v"
