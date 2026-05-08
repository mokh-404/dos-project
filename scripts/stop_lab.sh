#!/bin/bash
# ============================================================
# DoS Lab — Stop Script
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

echo -e "${CYAN}[*] Stopping DoS Lab environment...${RESET}"

cd "${PROJECT_ROOT}"
docker compose down --remove-orphans

echo -e "${GREEN}[+] All containers stopped${RESET}"
echo ""
echo -e "  Reports and PCAP files are preserved in:"
echo -e "    ${PROJECT_ROOT}/reports/"
echo -e "    ${PROJECT_ROOT}/packet_capture/captures/"
echo -e "    ${PROJECT_ROOT}/logs/"
echo ""
echo -e "  To fully remove volumes: docker compose down -v"
echo -e "  To clean everything:     ./scripts/cleanup.sh"
