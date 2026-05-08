#!/bin/bash
# ============================================================
# DoS Lab — Load Simulation Launcher
# ============================================================
# Launches controlled HTTP load simulation against victim.
#
# Usage: ./scripts/attack.sh [SCENARIO] [OPTIONS]
#   SCENARIO: ab | vegeta | siege | http_load | hping3 | all
#
# ⚠ EDUCATIONAL USE ONLY — ISOLATED DOCKER LAB
# ⚠ DO NOT target external systems
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'

SCENARIO="${1:-ab}"
ATTACKER_CONTAINER="dos_attacker"

# Check attacker is running
if ! docker ps --format '{{.Names}}' | grep -q "${ATTACKER_CONTAINER}"; then
    echo -e "${RED}[ERROR] Attacker container not running.${RESET}"
    echo -e "  Start with: ${CYAN}./scripts/start_lab.sh --with-attacker${RESET}"
    exit 1
fi

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║      DoS Lab — Load Simulation Launcher                  ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  ⚠ EDUCATIONAL USE ONLY — ISOLATED LAB ONLY ⚠           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "Scenario : ${BOLD}${SCENARIO}${RESET}"
echo -e "Container: ${ATTACKER_CONTAINER}"
echo ""

case "${SCENARIO}" in
    ab)
        echo -e "${CYAN}[*] Running Apache Benchmark (ab) HTTP load test...${RESET}"
        docker exec "${ATTACKER_CONTAINER}" bash /scripts/simulate_load.sh
        ;;
    vegeta)
        echo -e "${CYAN}[*] Running Vegeta HTTP rate load test...${RESET}"
        docker exec -e SCENARIO=vegeta "${ATTACKER_CONTAINER}" bash /scripts/simulate_load.sh
        ;;
    siege)
        echo -e "${CYAN}[*] Running Siege multi-URL load test...${RESET}"
        docker exec -e SCENARIO=siege "${ATTACKER_CONTAINER}" bash /scripts/simulate_load.sh
        ;;
    http_load)
        echo -e "${CYAN}[*] Running Python async HTTP load simulator...${RESET}"
        docker exec "${ATTACKER_CONTAINER}" python3 /scripts/http_load.py
        ;;
    hping3)
        echo -e "${YELLOW}[*] Running hping3 educational packet demonstration...${RESET}"
        echo -e "${YELLOW}    (Low-rate demo — 10-15 packets only)${RESET}"
        docker exec -e SCENARIO=hping3 "${ATTACKER_CONTAINER}" bash /scripts/simulate_load.sh
        ;;
    all)
        echo -e "${CYAN}[*] Running all simulation scenarios sequentially...${RESET}"
        docker exec -e SCENARIO=all "${ATTACKER_CONTAINER}" bash /scripts/simulate_load.sh
        ;;
    interactive)
        echo -e "${CYAN}[*] Launching interactive shell in attacker container...${RESET}"
        docker exec -it "${ATTACKER_CONTAINER}" bash
        ;;
    *)
        echo -e "${RED}Unknown scenario: ${SCENARIO}${RESET}"
        echo ""
        echo "Available scenarios:"
        echo "  ab          Apache Benchmark HTTP flood simulation"
        echo "  vegeta      Vegeta constant-rate HTTP load"
        echo "  siege       Siege concurrent multi-URL load"
        echo "  http_load   Python async HTTP load simulator"
        echo "  hping3      Educational packet demo (low rate)"
        echo "  all         Run all scenarios"
        echo "  interactive Open attacker container shell"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}[+] Simulation complete.${RESET}"
echo -e "  Reports: ${PROJECT_ROOT}/reports/"
echo -e "  Analyze: ./scripts/capture.sh --analyze"
