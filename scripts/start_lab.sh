#!/bin/bash
# ============================================================
# DoS Lab — Start Script
# ============================================================
# Starts the full lab environment.
# Usage: ./scripts/start_lab.sh [--with-mitigation] [--with-attacker]
#
# ⚠ EDUCATIONAL USE ONLY — ISOLATED DOCKER LAB
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"
ENV_FILE="${PROJECT_ROOT}/.env"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════╗
║          DoS Attack Simulation & Analysis Lab                   ║
║          Enterprise Cybersecurity Training Environment           ║
╠══════════════════════════════════════════════════════════════════╣
║  ⚠  FOR EDUCATIONAL USE ONLY — ISOLATED DOCKER LAB  ⚠          ║
║  Do NOT attack external systems or public infrastructure         ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${RESET}"
}

# Parse arguments
WITH_MITIGATION=false
WITH_ATTACKER=false

for arg in "$@"; do
    case $arg in
        --with-mitigation) WITH_MITIGATION=true ;;
        --with-attacker)   WITH_ATTACKER=true ;;
        --help|-h)
            echo "Usage: $0 [--with-mitigation] [--with-attacker]"
            echo ""
            echo "  --with-mitigation  Also start the Nginx mitigation proxy"
            echo "  --with-attacker    Also start the attacker/simulation container"
            exit 0
            ;;
    esac
done

print_banner

cd "${PROJECT_ROOT}"

# Check prerequisites
echo -e "${BOLD}[1/5] Checking prerequisites...${RESET}"
if ! command -v docker &>/dev/null; then
    echo -e "${RED}[ERROR] Docker is not installed or not in PATH${RESET}"
    exit 1
fi

if ! docker compose version &>/dev/null && ! docker-compose version &>/dev/null; then
    echo -e "${RED}[ERROR] Docker Compose is not available${RESET}"
    exit 1
fi

# Check Docker daemon is running
if ! docker info &>/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Docker daemon is not running${RESET}"
    exit 1
fi
echo -e "${GREEN}[+] Docker and Docker Compose are available${RESET}"

# Create required directories
echo -e "\n${BOLD}[2/5] Preparing directories...${RESET}"
mkdir -p "${PROJECT_ROOT}/logs"
mkdir -p "${PROJECT_ROOT}/reports"
mkdir -p "${PROJECT_ROOT}/analysis"
mkdir -p "${PROJECT_ROOT}/packet_capture/captures"
mkdir -p "${PROJECT_ROOT}/victim/logs"
echo -e "${GREEN}[+] Directories ready${RESET}"

# Copy .env if missing
if [[ ! -f "${ENV_FILE}" ]]; then
    cp "${PROJECT_ROOT}/.env.example" "${ENV_FILE}" 2>/dev/null || true
    echo -e "${YELLOW}[!] Created .env from defaults${RESET}"
fi

# Build containers
echo -e "\n${BOLD}[3/5] Building containers...${RESET}"
COMPOSE_PROFILES=""

if [[ "${WITH_MITIGATION}" == "true" ]]; then
    COMPOSE_PROFILES="${COMPOSE_PROFILES} --profile mitigation"
fi

if [[ "${WITH_ATTACKER}" == "true" ]]; then
    COMPOSE_PROFILES="${COMPOSE_PROFILES} --profile attack"
fi

docker compose -f "${COMPOSE_FILE}" ${COMPOSE_PROFILES} build --quiet
echo -e "${GREEN}[+] Containers built${RESET}"

# Start core services
echo -e "\n${BOLD}[4/5] Starting services...${RESET}"
docker compose -f "${COMPOSE_FILE}" ${COMPOSE_PROFILES} up -d

# Wait for health checks
echo -e "\n${BOLD}[5/5] Waiting for services to become healthy...${RESET}"
sleep 5

max_wait=60
elapsed=0

services=("dos_victim" "dos_prometheus" "dos_grafana")
all_healthy=false

while [[ ${elapsed} -lt ${max_wait} ]]; do
    all_healthy=true
    for svc in "${services[@]}"; do
        status=$(docker inspect --format='{{.State.Health.Status}}' "${svc}" 2>/dev/null || echo "missing")
        if [[ "${status}" != "healthy" ]]; then
            all_healthy=false
        fi
    done
    if [[ "${all_healthy}" == "true" ]]; then break; fi
    sleep 3
    elapsed=$((elapsed + 3))
    echo -n "."
done
echo ""

# Print status
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Lab Status${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
docker compose -f "${COMPOSE_FILE}" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# Source .env for port values
source "${ENV_FILE}" 2>/dev/null || true
VICTIM_PORT="${VICTIM_HTTP_PORT:-8080}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
CADVISOR_PORT="${CADVISOR_PORT:-8081}"

echo ""
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  🎉 Lab is running!${RESET}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  🌐 Victim Web Server  : ${CYAN}http://localhost:${VICTIM_PORT}${RESET}"
echo -e "  📊 Grafana Dashboard  : ${CYAN}http://localhost:${GRAFANA_PORT}${RESET}  (admin / doslab2024)"
echo -e "  🔬 Prometheus         : ${CYAN}http://localhost:${PROMETHEUS_PORT}${RESET}"
echo -e "  📦 cAdvisor           : ${CYAN}http://localhost:${CADVISOR_PORT}${RESET}"

if [[ "${WITH_MITIGATION}" == "true" ]]; then
    MITIGATION_PORT="${MITIGATION_PORT:-8443}"
    echo -e "  🛡  Mitigation Proxy  : ${CYAN}http://localhost:${MITIGATION_PORT}${RESET}"
fi

echo ""
echo -e "  📁 PCAP Captures      : ${PROJECT_ROOT}/packet_capture/captures/"
echo -e "  📋 Reports            : ${PROJECT_ROOT}/reports/"
echo -e "  📝 Logs               : ${PROJECT_ROOT}/logs/"
echo ""
echo -e "${YELLOW}  ⚠ Reminder: This lab is for educational use only.${RESET}"
echo -e "${YELLOW}    All traffic is isolated within Docker networks.${RESET}"
echo ""
echo -e "  Run simulation : ${CYAN}./scripts/attack.sh${RESET}"
echo -e "  Capture packets: ${CYAN}./scripts/capture.sh${RESET}"
echo -e "  Stop lab       : ${CYAN}./scripts/stop_lab.sh${RESET}"
echo ""
