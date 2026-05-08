#!/bin/bash
# ============================================================
# DoS Lab — Cleanup Script
# ============================================================
# Removes all containers, volumes, networks, and generated
# files from the lab. Use with caution — DESTROYS DATA.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BOLD='\033[1m'; RESET='\033[0m'

echo -e "${BOLD}${RED}"
echo "╔══════════════════════════════════════════════╗"
echo "║         DoS Lab — Full Cleanup               ║"
echo "║  ⚠ This will DELETE all containers and data  ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "${YELLOW}This will remove:${RESET}"
echo "  - All DoS lab containers"
echo "  - All DoS lab Docker volumes (prometheus data, grafana data, etc.)"
echo "  - All Docker networks created by this lab"
echo "  - PCAP files in packet_capture/captures/"
echo "  - Log files in logs/"
echo ""
echo -e "${YELLOW}Reports in reports/ and exports/ will be PRESERVED.${RESET}"
echo ""

read -p "Are you sure? Type 'yes' to confirm: " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

cd "${PROJECT_ROOT}"

echo ""
echo -e "${BOLD}[1/4] Stopping and removing containers...${RESET}"
docker compose down -v --remove-orphans 2>/dev/null || true
echo -e "${GREEN}[+] Containers and volumes removed${RESET}"

echo -e "\n${BOLD}[2/4] Removing PCAP captures...${RESET}"
rm -f "${PROJECT_ROOT}/packet_capture/captures/"*.pcap 2>/dev/null || true
echo -e "${GREEN}[+] PCAP files cleared${RESET}"

echo -e "\n${BOLD}[3/4] Clearing log files...${RESET}"
rm -f "${PROJECT_ROOT}/logs/"* 2>/dev/null || true
rm -f "${PROJECT_ROOT}/victim/logs/"* 2>/dev/null || true
echo -e "${GREEN}[+] Logs cleared${RESET}"

echo -e "\n${BOLD}[4/4] Removing unused Docker images (optional)...${RESET}"
read -p "Remove unused Docker images? [y/N]: " REMOVE_IMAGES
if [[ "${REMOVE_IMAGES}" == "y" || "${REMOVE_IMAGES}" == "Y" ]]; then
    docker image prune -f --filter "label=lab.role" 2>/dev/null || true
    echo -e "${GREEN}[+] Unused images pruned${RESET}"
else
    echo "  Skipped"
fi

echo ""
echo -e "${GREEN}${BOLD}[+] Cleanup complete.${RESET}"
echo -e "  Reports preserved in: ${PROJECT_ROOT}/reports/"
echo ""
echo -e "  To restart the lab: ${RESET}./scripts/start_lab.sh"
