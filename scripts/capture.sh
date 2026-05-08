#!/bin/bash
# ============================================================
# DoS Lab — Packet Capture & Analysis Script
# ============================================================
# Manages PCAP capture and runs DFIR analysis workflows.
#
# Usage: ./scripts/capture.sh [--analyze] [--list] [--export]
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
CAPTURE_CONTAINER="dos_packet_capture"
CAPTURE_DIR="${PROJECT_ROOT}/packet_capture/captures"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BOLD='\033[1m'; RESET='\033[0m'

ACTION="${1:---status}"

echo -e "${BOLD}${CYAN}[*] DoS Lab — Packet Capture Manager${RESET}"
echo ""

case "${ACTION}" in
    --analyze|-a)
        echo -e "${CYAN}[*] Running DFIR packet analysis...${RESET}"
        if ! docker ps --format '{{.Names}}' | grep -q "${CAPTURE_CONTAINER}"; then
            echo -e "Running analysis on local PCAP files..."
            LATEST=$(ls -t "${CAPTURE_DIR}"/*.pcap 2>/dev/null | head -1 || true)
            if [[ -z "${LATEST}" ]]; then
                echo "No PCAP files found in ${CAPTURE_DIR}"
                exit 1
            fi
            echo "Analyzing: ${LATEST}"
        else
            docker exec "${CAPTURE_CONTAINER}" \
                bash /analysis/analyze_pcap.sh /captures /analysis
        fi
        ;;

    --list|-l)
        echo -e "${CYAN}[*] Available PCAP files:${RESET}"
        ls -lh "${CAPTURE_DIR}"/*.pcap 2>/dev/null \
            | awk '{print "  " $NF "\t" $5 "\t" $6 " " $7 " " $8}' \
            || echo "  No PCAP files found yet"
        ;;

    --export|-e)
        echo -e "${CYAN}[*] Exporting PCAP files to reports...${RESET}"
        EXPORT_DIR="${PROJECT_ROOT}/reports/pcap_export_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "${EXPORT_DIR}"
        cp "${CAPTURE_DIR}"/*.pcap "${EXPORT_DIR}/" 2>/dev/null && \
            echo -e "${GREEN}[+] Exported to: ${EXPORT_DIR}${RESET}" || \
            echo "No PCAP files to export"
        ;;

    --tshark)
        echo -e "${CYAN}[*] Opening tshark interactive session in capture container...${RESET}"
        docker exec -it "${CAPTURE_CONTAINER}" tshark -i any
        ;;

    --status)
        echo -e "${CYAN}[*] Capture container status:${RESET}"
        docker ps --filter "name=${CAPTURE_CONTAINER}" \
            --format "  Name: {{.Names}}\n  Status: {{.Status}}\n  Ports: {{.Ports}}"
        echo ""
        echo -e "  PCAP directory: ${CAPTURE_DIR}"
        FILE_COUNT=$(ls "${CAPTURE_DIR}"/*.pcap 2>/dev/null | wc -l || echo 0)
        echo -e "  PCAP files    : ${FILE_COUNT}"
        if [[ "${FILE_COUNT}" -gt 0 ]]; then
            TOTAL_SIZE=$(du -sh "${CAPTURE_DIR}"/*.pcap 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
            echo -e "  Total size    : ${TOTAL_SIZE}"
            LATEST=$(ls -t "${CAPTURE_DIR}"/*.pcap 2>/dev/null | head -1 || true)
            echo -e "  Latest file   : $(basename "${LATEST}")"
        fi
        ;;

    --quick-stats)
        echo -e "${CYAN}[*] Quick PCAP statistics (latest file):${RESET}"
        LATEST=$(ls -t "${CAPTURE_DIR}"/*.pcap 2>/dev/null | head -1 || true)
        if [[ -z "${LATEST}" ]]; then
            echo "No PCAP files found"
            exit 0
        fi
        echo "File: $(basename "${LATEST}")"
        docker exec "${CAPTURE_CONTAINER}" \
            tshark -r /captures/$(basename "${LATEST}") -q -z io,stat,0 2>/dev/null || \
            echo "(tshark unavailable for this file)"
        ;;

    --help|-h)
        echo "Usage: $0 [ACTION]"
        echo ""
        echo "Actions:"
        echo "  --status        Show capture container status (default)"
        echo "  --analyze, -a   Run DFIR analysis on latest PCAP"
        echo "  --list, -l      List available PCAP files"
        echo "  --export, -e    Export PCAP files to reports/"
        echo "  --quick-stats   Show quick statistics from latest PCAP"
        echo "  --tshark        Interactive tshark session"
        ;;

    *)
        echo "Unknown action: ${ACTION}. Use --help for options."
        exit 1
        ;;
esac
