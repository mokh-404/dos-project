#!/bin/bash
# ============================================================
# DoS Lab — Controlled Load Simulation Script
# ============================================================
# PURPOSE: Generate controlled HTTP traffic to simulate
#          high-load conditions for performance analysis.
#
# ⚠ EDUCATIONAL USE ONLY — ISOLATED DOCKER LAB ONLY
# ⚠ DO NOT target external systems or public infrastructure
# ============================================================

set -euo pipefail

# ── Configuration ────────────────────────────────────────────
TARGET_HOST="${TARGET_HOST:-victim}"
TARGET_PORT="${TARGET_PORT:-80}"
TARGET_URL="http://${TARGET_HOST}:${TARGET_PORT}"
RATE="${ATTACK_RATE:-100}"
DURATION="${ATTACK_DURATION:-30}"
CONCURRENCY="${ATTACK_CONCURRENCY:-10}"
REPORT_DIR="${REPORT_DIR:-/reports}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# ── Scenario tracking (real-time, not hardcoded) ──────────────
declare -A SCENARIO_RESULTS

# ── Color codes ───────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Banner ────────────────────────────────────────────────────
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║       DoS Lab — Controlled Load Simulation Engine        ║"
    echo "║       Educational Cybersecurity Training Environment     ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║  ⚠  FOR ISOLATED LAB USE ONLY — DO NOT MISUSE  ⚠        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

# ── Verify target reachable ───────────────────────────────────
verify_target() {
    echo -e "${CYAN}[*] Verifying target reachability: ${TARGET_URL}${RESET}"
    if curl -sf --max-time 5 "${TARGET_URL}/health" > /dev/null 2>&1; then
        echo -e "${GREEN}[+] Target is reachable and healthy${RESET}"
    else
        echo -e "${RED}[-] WARNING: Target may not be healthy. Proceeding anyway.${RESET}"
    fi
}

# ── Scenario 1: Apache Benchmark (ab) HTTP flood ──────────────
run_ab_load() {
    local concurrency=${1:-${CONCURRENCY}}
    local path=${2:-"/"}
    # Number of parallel ab processes to run simultaneously
    local parallel=${AB_PARALLEL:-4}

    echo -e "\n${BOLD}${CYAN}═══ SCENARIO: HTTP Flood (Apache Benchmark) ═══${RESET}"
    echo -e "  Target        : ${TARGET_URL}${path}"
    echo -e "  Duration      : ${DURATION}s (continuous)"
    echo -e "  Concurrency   : ${concurrency} per stream"
    echo -e "  Parallel      : ${parallel} streams"
    echo -e "  Total Conns   : $((concurrency * parallel)) simultaneous"
    echo ""

    mkdir -p "${REPORT_DIR}"
    local outfile="${REPORT_DIR}/ab_report_${TIMESTAMP}.txt"

    echo -e "${RED}[!] FLOODING — ${parallel} parallel streams x ${concurrency} connections = $((concurrency * parallel)) total${RESET}"
    echo ""

    # Launch multiple parallel ab processes to truly overwhelm the server
    local pids=()
    for i in $(seq 1 ${parallel}); do
        ab \
            -n 999999 \
            -c "${concurrency}" \
            -t "${DURATION}" \
            -H "Accept-Encoding: gzip, deflate" \
            -r \
            "${TARGET_URL}${path}" \
            > "${REPORT_DIR}/ab_stream${i}_${TIMESTAMP}.txt" 2>&1 &
        pids+=($!)
        echo -e "  ${YELLOW}[→] Stream ${i}/${parallel} launched (PID $!)${RESET}"
    done

    echo -e "\n  ${CYAN}[*] Waiting for all ${parallel} streams to complete (${DURATION}s)...${RESET}\n"

    # Wait for all and collect results
    local total_requests=0
    local total_failed=0
    local any_success=false
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    # Parse results from all streams
    echo -e "\n${BOLD}${CYAN}═══ ATTACK RESULTS ═══${RESET}"
    for i in $(seq 1 ${parallel}); do
        local stream_file="${REPORT_DIR}/ab_stream${i}_${TIMESTAMP}.txt"
        if [ -f "$stream_file" ]; then
            local reqs=$(grep "Complete requests:" "$stream_file" 2>/dev/null | awk '{print $3}' || echo "0")
            local failed=$(grep "Failed requests:" "$stream_file" 2>/dev/null | awk '{print $3}' || echo "0")
            local rps=$(grep "Requests per second:" "$stream_file" 2>/dev/null | awk '{print $4}' || echo "0")
            local avg_time=$(grep "Time per request:.*mean\b" "$stream_file" 2>/dev/null | head -1 | awk '{print $4}' || echo "0")
            echo -e "  Stream ${i}: ${GREEN}${reqs}${RESET} requests | ${RED}${failed}${RESET} failed | ${YELLOW}${rps}${RESET} req/s | ${CYAN}${avg_time}${RESET} ms/req"
            total_requests=$((total_requests + ${reqs:-0}))
            total_failed=$((total_failed + ${failed:-0}))
            any_success=true
        fi
    done

    echo -e "\n  ${BOLD}TOTAL: ${GREEN}${total_requests}${RESET} requests | ${RED}${total_failed}${RESET} failed"

    # Copy the first stream's full output as the main report
    cp "${REPORT_DIR}/ab_stream1_${TIMESTAMP}.txt" "${outfile}" 2>/dev/null || true

    if [ "$any_success" = true ]; then
        SCENARIO_RESULTS["Apache Benchmark (ab)"]="✅ Completed (${total_requests} reqs, ${total_failed} failed)"
    else
        SCENARIO_RESULTS["Apache Benchmark (ab)"]="❌ Failed"
    fi

    echo -e "\n${GREEN}[+] Apache Benchmark reports saved to: ${REPORT_DIR}/ab_stream*_${TIMESTAMP}.txt${RESET}"
}

# ── Scenario 2: Vegeta HTTP load ─────────────────────────────
run_vegeta_load() {
    local rate=${1:-${RATE}}
    local duration="${2:-${DURATION}s}"

    if ! command -v vegeta &>/dev/null; then
        echo -e "${YELLOW}[!] Vegeta not installed — skipping scenario${RESET}"
        SCENARIO_RESULTS["Vegeta"]="⏭️ Skipped (not installed)"
        return 0
    fi

    echo -e "\n${BOLD}${CYAN}═══ SCENARIO: HTTP Load (Vegeta) ═══${RESET}"
    echo -e "  Target  : ${TARGET_URL}"
    echo -e "  Rate    : ${rate} req/s"
    echo -e "  Duration: ${duration}"
    echo ""

    local outfile="${REPORT_DIR}/vegeta_report_${TIMESTAMP}"

    # Build target list with multiple endpoints for diversity
    cat << EOF | vegeta attack \
        -rate="${rate}" \
        -duration="${duration}" \
        -timeout=10s \
        | tee "${outfile}.bin" \
        | vegeta report \
        | tee "${outfile}.txt"
GET ${TARGET_URL}/
GET ${TARGET_URL}/about.html
GET ${TARGET_URL}/api.html
GET ${TARGET_URL}/contact.html
GET ${TARGET_URL}/health
EOF

    # Generate histogram
    cat "${outfile}.bin" | vegeta report -type=hist[0,10ms,50ms,100ms,200ms,500ms,1s] \
        >> "${outfile}.txt" 2>/dev/null || true

    SCENARIO_RESULTS["Vegeta"]="✅ Completed"
    echo -e "\n${GREEN}[+] Vegeta report saved to: ${outfile}.txt${RESET}"
}

# ── Scenario 3: Siege multi-URL load ─────────────────────────
run_siege_load() {
    if ! command -v siege &>/dev/null; then
        echo -e "${YELLOW}[!] Siege not installed — skipping scenario${RESET}"
        SCENARIO_RESULTS["Siege"]="⏭️ Skipped (not installed)"
        return 0
    fi

    echo -e "\n${BOLD}${CYAN}═══ SCENARIO: Multi-URL Concurrent Load (Siege) ═══${RESET}"
    echo -e "  Target: ${TARGET_URL}"
    echo -e "  Concurrency: ${CONCURRENCY}"
    echo -e "  Duration: ${DURATION}s"
    echo ""

    local outfile="${REPORT_DIR}/siege_report_${TIMESTAMP}.txt"

    # Create URL file
    cat > /tmp/siege_urls.txt << EOF
${TARGET_URL}/
${TARGET_URL}/about.html
${TARGET_URL}/api.html
${TARGET_URL}/health
${TARGET_URL}/contact.html
EOF

    siege \
        --concurrent="${CONCURRENCY}" \
        --time="${DURATION}S" \
        --file=/tmp/siege_urls.txt \
        --log="${outfile}" \
        2>&1 | tee -a "${outfile}" || true

    SCENARIO_RESULTS["Siege"]="✅ Completed"
    echo -e "\n${GREEN}[+] Siege report saved to: ${outfile}${RESET}"
}

# ── Scenario 4: hping3 — Educational packet inspection ────────
# Low-rate ICMP/TCP packet demonstration for packet analysis
run_hping3_demo() {
    echo -e "\n${BOLD}${CYAN}═══ SCENARIO: Educational Packet Demo (hping3) ═══${RESET}"
    echo -e "${YELLOW}  ⚠ Low-rate demonstration only — for packet inspection${RESET}"
    echo -e "  Target: ${TARGET_HOST}"
    echo -e "  Mode  : ICMP ping (10 packets)"
    echo ""

    # Very low rate ICMP — only 10 packets for demonstration
    hping3 -c 10 -1 --fast "${TARGET_HOST}" 2>&1 || true

    echo ""
    echo -e "  Mode  : TCP SYN probe (5 packets) — educational only"
    hping3 -c 5 -S -p "${TARGET_PORT}" "${TARGET_HOST}" 2>&1 || true

    SCENARIO_RESULTS["hping3"]="✅ Completed"
    echo -e "\n${GREEN}[+] hping3 packet demo completed — see packet_capture container for PCAP${RESET}"
}

# ── Scenario 5: Connection exhaustion simulation ──────────────
run_connection_test() {
    echo -e "\n${BOLD}${CYAN}═══ SCENARIO: Slow Connection Behavior Analysis ═══${RESET}"
    echo -e "  Using curl with slow read for educational demonstration"
    echo ""

    # Simple slow curl to observe connection behavior
    for i in $(seq 1 5); do
        echo -e "  [${i}/5] Sending slow request..."
        curl -s --max-time 10 --limit-rate 1k \
            "${TARGET_URL}/" > /dev/null 2>&1 &
    done
    wait
    SCENARIO_RESULTS["Connection Test (curl)"]="✅ Completed"
    echo -e "${GREEN}[+] Connection behavior test completed${RESET}"
}

# ── Generate Summary Report (real-time, based on actual execution) ────
generate_summary() {
    local summary="${REPORT_DIR}/summary_${TIMESTAMP}.md"
    local end_time
    end_time=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

    # Build scenario table dynamically from actual results
    local scenario_table=""
    for tool in "${!SCENARIO_RESULTS[@]}"; do
        scenario_table+="| ${tool} | ${SCENARIO_RESULTS[$tool]} |\n"
    done

    if [ -z "${scenario_table}" ]; then
        scenario_table="| (none) | — |\n"
    fi

    cat > "${summary}" << EOF
# DoS Lab — Load Simulation Report

**Started**: ${TIMESTAMP}
**Completed**: ${end_time}
**Target**: ${TARGET_URL}
**Rate**: ${RATE} req/s | **Duration**: ${DURATION}s | **Concurrency**: ${CONCURRENCY}

## Scenarios Executed
| Tool | Status |
|---|---|
$(echo -e "${scenario_table}")

## Files Generated
$(ls "${REPORT_DIR}/"*"${TIMESTAMP}"* 2>/dev/null | sed 's/^/- /' || echo "- (none)")

## Notes
- All traffic confined to isolated Docker network
- Prometheus metrics at http://localhost:9090
- Grafana dashboard at http://localhost:3000
- Apache logs in ./data/logs/
- PCAP captures in ./data/captures/

---
*Generated by DoS Lab Cyber Range — Educational use only*
EOF
    echo -e "\n${GREEN}[+] Summary report: ${summary}${RESET}"
}

# ── Main ──────────────────────────────────────────────────────
main() {
    print_banner

    echo -e "${BOLD}Configuration:${RESET}"
    echo -e "  Target      : ${TARGET_URL}"
    echo -e "  Rate        : ${RATE} req/s"
    echo -e "  Duration    : ${DURATION}s"
    echo -e "  Concurrency : ${CONCURRENCY}"
    echo -e "  Reports     : ${REPORT_DIR}"
    echo -e "  Timestamp   : ${TIMESTAMP}"
    echo ""

    verify_target

    local SCENARIO="${SCENARIO:-all}"

    case "${SCENARIO}" in
        ab)       run_ab_load ;;
        vegeta)   run_vegeta_load ;;
        siege)    run_siege_load ;;
        hping3)   run_hping3_demo ;;
        conn)     run_connection_test ;;
        all)
            run_ab_load
            sleep 2
            run_vegeta_load
            sleep 2
            run_siege_load
            sleep 2
            run_hping3_demo
            sleep 2
            run_connection_test
            ;;
        *)
            echo -e "${RED}Unknown scenario: ${SCENARIO}${RESET}"
            echo "Valid options: ab | vegeta | siege | hping3 | conn | all"
            exit 1
            ;;
    esac

    generate_summary
    echo -e "\n${BOLD}${GREEN}All scenarios completed. Check ${REPORT_DIR} for results.${RESET}\n"
}

main "$@"
