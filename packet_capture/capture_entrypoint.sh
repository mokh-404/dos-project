#!/bin/bash
# ============================================================
# Packet Capture Entrypoint
# Runs continuous rotating PCAP capture on victim network
# ============================================================

set -euo pipefail

INTERFACE="${CAPTURE_INTERFACE:-eth0}"
FILTER="${CAPTURE_FILTER:-tcp port 80}"
ROTATE_SECS="${CAPTURE_ROTATE_SECONDS:-60}"
CAPTURE_DIR="/captures"
LOG_FILE="/captures/capture.log"

mkdir -p "${CAPTURE_DIR}"

echo "=============================================="
echo " DoS Lab — Packet Capture Container"
echo " Interface : ${INTERFACE}"
echo " Filter    : ${FILTER}"
echo " Rotation  : every ${ROTATE_SECS}s"
echo " Output    : ${CAPTURE_DIR}"
echo "=============================================="
echo ""

# Wait for network to stabilize
sleep 3

# Try interface detection
IFACE="${INTERFACE}"
if ! ip link show "${IFACE}" &>/dev/null; then
    # Fall back to first available non-loopback interface
    IFACE=$(ip link | awk -F: '/^[0-9]+: (eth|ens|enp)[0-9]/{print $2; exit}' | tr -d ' ' || echo "eth0")
    echo "[!] Interface ${INTERFACE} not found, using: ${IFACE}"
fi

echo "[*] Starting capture on ${IFACE} (filter: ${FILTER})"
echo "[*] PCAP files rotate every ${ROTATE_SECS} seconds"
echo ""

# Rotating capture with tshark
tshark \
    -i "${IFACE}" \
    -b duration:"${ROTATE_SECS}" \
    -b filesize:102400 \
    -w "${CAPTURE_DIR}/capture_%Y%m%d_%H%M%S.pcap" \
    -F pcap \
    -f "${FILTER}" \
    -q \
    2>&1 | tee -a "${LOG_FILE}" &

CAPTURE_PID=$!
echo "[+] Capture PID: ${CAPTURE_PID}" | tee -a "${LOG_FILE}"

# Keep container alive and monitor capture
while true; do
    sleep 30
    FILE_COUNT=$(ls "${CAPTURE_DIR}"/*.pcap 2>/dev/null | wc -l || echo 0)
    TOTAL_SIZE=$(du -sh "${CAPTURE_DIR}"/*.pcap 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
    echo "[$(date -u '+%H:%M:%S')] PCAP files: ${FILE_COUNT} | Latest size check: OK" | tee -a "${LOG_FILE}"
done
