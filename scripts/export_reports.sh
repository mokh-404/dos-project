#!/bin/bash
# ============================================================
# DoS Lab — Export Reports Script
# ============================================================
# Collects all generated reports, logs, and captures
# into a timestamped export bundle.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
EXPORT_DIR="${PROJECT_ROOT}/exports/lab_export_${TIMESTAMP}"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

echo -e "${BOLD}${CYAN}[*] DoS Lab — Exporting Reports${RESET}"
echo -e "  Export directory: ${EXPORT_DIR}"
echo ""

mkdir -p "${EXPORT_DIR}"/{reports,pcap,logs,analysis,apache_logs}

# Copy reports
cp -r "${PROJECT_ROOT}/reports/"* "${EXPORT_DIR}/reports/" 2>/dev/null || echo "  No reports to copy"

# Copy PCAP files
cp "${PROJECT_ROOT}/packet_capture/captures/"*.pcap \
   "${EXPORT_DIR}/pcap/" 2>/dev/null || echo "  No PCAP files to copy"

# Copy analysis outputs
cp -r "${PROJECT_ROOT}/analysis/"* "${EXPORT_DIR}/analysis/" 2>/dev/null || echo "  No analysis files"

# Copy application logs
cp -r "${PROJECT_ROOT}/logs/"* "${EXPORT_DIR}/logs/" 2>/dev/null || echo "  No host logs"

# Export Apache logs from container
echo -e "  Exporting Apache logs from container..."
docker exec dos_victim bash -c "cat /var/log/apache2/access.log" \
    > "${EXPORT_DIR}/apache_logs/access.log" 2>/dev/null || echo "  Victim not running"
docker exec dos_victim bash -c "cat /var/log/apache2/error.log" \
    > "${EXPORT_DIR}/apache_logs/error.log" 2>/dev/null || true
docker exec dos_victim bash -c "cat /var/log/apache2/dos_analysis.log" \
    > "${EXPORT_DIR}/apache_logs/dos_analysis.log" 2>/dev/null || true

# Generate manifest
cat > "${EXPORT_DIR}/MANIFEST.txt" << EOF
DoS Lab Export Manifest
========================
Timestamp : $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Host      : $(hostname)
Lab Dir   : ${PROJECT_ROOT}

Contents:
  reports/       - Load testing reports (ab, vegeta, siege, python)
  pcap/          - Network packet captures (.pcap)
  logs/          - Host-side log files
  apache_logs/   - Apache access and error logs from victim container
  analysis/      - DFIR analysis outputs

Container Status at Export:
$(docker compose -f "${PROJECT_ROOT}/docker-compose.yml" ps 2>/dev/null || echo "(docker compose unavailable)")
EOF

# Create tarball
TARBALL="${PROJECT_ROOT}/exports/lab_export_${TIMESTAMP}.tar.gz"
tar -czf "${TARBALL}" -C "${PROJECT_ROOT}/exports" "lab_export_${TIMESTAMP}" 2>/dev/null

echo ""
echo -e "${GREEN}[+] Export complete${RESET}"
echo -e "  Directory : ${EXPORT_DIR}"
echo -e "  Archive   : ${TARBALL}"
echo ""
ls -lh "${TARBALL}"
