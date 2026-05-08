#!/bin/bash
# ============================================================
# PCAP Analysis Script — DFIR Workflow
# DoS Lab — Educational Use Only
# ============================================================
# Performs tshark-based analysis on captured PCAP files
# to identify DoS indicators and attack signatures.
# ============================================================

set -euo pipefail

CAPTURE_DIR="${1:-/captures}"
ANALYSIS_DIR="${2:-/analysis}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT="${ANALYSIS_DIR}/pcap_analysis_${TIMESTAMP}.md"

mkdir -p "${ANALYSIS_DIR}"

# Color codes
CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'

# Find most recent PCAP
PCAP=$(ls -t "${CAPTURE_DIR}"/*.pcap 2>/dev/null | head -1 || true)

if [[ -z "${PCAP}" ]]; then
    echo -e "${RED}[ERROR] No PCAP files found in ${CAPTURE_DIR}${RESET}"
    exit 1
fi

echo -e "${BOLD}${CYAN}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║      DoS Lab — DFIR Packet Analysis Workflow          ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "${CYAN}[*] Analyzing: ${PCAP}${RESET}"
echo ""

# ── Begin report ──────────────────────────────────────────────
cat > "${REPORT}" << EOF
# DFIR Packet Analysis Report
**Generated**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Analyst**: DoS Lab Automated Analysis Engine
**PCAP File**: $(basename "${PCAP}")
**File Size**: $(du -sh "${PCAP}" | awk '{print $1}')

---

## 1. Capture Statistics

EOF

# ── Section 1: Capture statistics ────────────────────────────
echo -e "${BOLD}[1/7] Capture Statistics${RESET}"
tshark -r "${PCAP}" -q -z io,stat,0 2>/dev/null >> "${REPORT}" || true
echo "" >> "${REPORT}"

# ── Section 2: Protocol hierarchy ────────────────────────────
echo -e "${BOLD}[2/7] Protocol Hierarchy${RESET}"
cat >> "${REPORT}" << 'EOF'

## 2. Protocol Hierarchy
```
EOF
tshark -r "${PCAP}" -q -z io,phs 2>/dev/null >> "${REPORT}" || echo "(tshark analysis unavailable)" >> "${REPORT}"
echo '```' >> "${REPORT}"

# ── Section 3: Top source IPs ─────────────────────────────────
echo -e "${BOLD}[3/7] Top Source IP Analysis${RESET}"
cat >> "${REPORT}" << 'EOF'

## 3. Top Source IP Addresses
```
EOF
tshark -r "${PCAP}" -T fields -e ip.src 2>/dev/null \
    | sort | uniq -c | sort -rn | head -20 \
    >> "${REPORT}" || echo "(no IP data)" >> "${REPORT}"
echo '```' >> "${REPORT}"

# ── Section 4: TCP flag analysis ──────────────────────────────
echo -e "${BOLD}[4/7] TCP Flag Analysis (SYN flood indicators)${RESET}"
cat >> "${REPORT}" << 'EOF'

## 4. TCP Flag Analysis
### SYN Packets (potential SYN flood indicator)
```
EOF

SYN_COUNT=$(tshark -r "${PCAP}" -Y "tcp.flags.syn==1 && tcp.flags.ack==0" -T fields -e frame.number 2>/dev/null | wc -l || echo 0)
RST_COUNT=$(tshark -r "${PCAP}" -Y "tcp.flags.reset==1" -T fields -e frame.number 2>/dev/null | wc -l || echo 0)
SYN_ACK_COUNT=$(tshark -r "${PCAP}" -Y "tcp.flags.syn==1 && tcp.flags.ack==1" -T fields -e frame.number 2>/dev/null | wc -l || echo 0)

echo "SYN packets  : ${SYN_COUNT}" >> "${REPORT}"
echo "SYN-ACK pkts : ${SYN_ACK_COUNT}" >> "${REPORT}"
echo "RST packets  : ${RST_COUNT}" >> "${REPORT}"
if [[ "${SYN_COUNT}" -gt 0 && "${SYN_ACK_COUNT}" -gt 0 ]]; then
    RATIO=$(echo "scale=2; ${SYN_COUNT} / ${SYN_ACK_COUNT}" | bc 2>/dev/null || echo "N/A")
    echo "SYN/SYN-ACK ratio: ${RATIO} (>5 may indicate SYN flood)" >> "${REPORT}"
fi
echo '```' >> "${REPORT}"

# ── Section 5: HTTP analysis ──────────────────────────────────
echo -e "${BOLD}[5/7] HTTP Request Analysis${RESET}"
cat >> "${REPORT}" << 'EOF'

## 5. HTTP Request Analysis
### Top Requested URIs
```
EOF
tshark -r "${PCAP}" -Y "http.request" -T fields -e http.request.uri 2>/dev/null \
    | sort | uniq -c | sort -rn | head -20 \
    >> "${REPORT}" || echo "(no HTTP data)" >> "${REPORT}"
echo '```' >> "${REPORT}"

cat >> "${REPORT}" << 'EOF'

### HTTP Method Distribution
```
EOF
tshark -r "${PCAP}" -Y "http.request" -T fields -e http.request.method 2>/dev/null \
    | sort | uniq -c | sort -rn \
    >> "${REPORT}" || echo "(no HTTP methods)" >> "${REPORT}"
echo '```' >> "${REPORT}"

cat >> "${REPORT}" << 'EOF'

### HTTP Response Codes
```
EOF
tshark -r "${PCAP}" -Y "http.response" -T fields -e http.response.code 2>/dev/null \
    | sort | uniq -c | sort -rn | head -10 \
    >> "${REPORT}" || echo "(no HTTP responses)" >> "${REPORT}"
echo '```' >> "${REPORT}"

# ── Section 6: Connection analysis ───────────────────────────
echo -e "${BOLD}[6/7] TCP Connection Analysis${RESET}"
cat >> "${REPORT}" << 'EOF'

## 6. TCP Connection Behavior
```
EOF
tshark -r "${PCAP}" -q -z conv,tcp 2>/dev/null | head -30 >> "${REPORT}" || echo "(no TCP conv data)" >> "${REPORT}"
echo '```' >> "${REPORT}"

# ── Section 7: IOC Summary ────────────────────────────────────
echo -e "${BOLD}[7/7] IOC Summary${RESET}"
cat >> "${REPORT}" << EOF

## 7. Indicators of Compromise (IOC) Summary

| Indicator | Value | Severity |
|---|---|---|
| Total SYN packets | ${SYN_COUNT} | $([ "${SYN_COUNT}" -gt 500 ] && echo "⚠ HIGH" || echo "LOW") |
| Total RST packets | ${RST_COUNT} | $([ "${RST_COUNT}" -gt 200 ] && echo "⚠ HIGH" || echo "LOW") |
| SYN/SYN-ACK Ratio | ${RATIO:-N/A} | $([ "${SYN_COUNT}" -gt "${SYN_ACK_COUNT}" ] && echo "⚠ ELEVATED" || echo "NORMAL") |

## 8. DFIR Recommendations

1. **If SYN/SYN-ACK ratio > 5**: Enable SYN cookies on the victim server
2. **If single source IP dominates**: Implement IP-based rate limiting
3. **If HTTP 503 errors spike**: Review Apache MaxRequestWorkers setting
4. **If RST count is high**: Investigate connection exhaustion
5. **Cross-reference**: Check Apache access logs for corresponding timestamps

---
*Report generated by DoS Lab Automated Analysis Engine*
*PCAP file analyzed: $(basename "${PCAP}")*
EOF

echo ""
echo -e "${GREEN}[+] Analysis complete${RESET}"
echo -e "${GREEN}[+] Report saved: ${REPORT}${RESET}"
echo ""
cat "${REPORT}"
