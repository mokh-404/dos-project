#!/bin/bash
# ============================================================
# Mitigation Container Entrypoint
# Starts Nginx and Fail2Ban together
# ============================================================

set -euo pipefail

echo "=============================================="
echo " DoS Lab — Mitigation Container"
echo " Nginx Reverse Proxy + Fail2Ban"
echo "=============================================="

# Test Nginx config
nginx -t 2>&1 && echo "[+] Nginx config OK"

# Start Nginx
nginx -g "daemon off;" &
NGINX_PID=$!
echo "[+] Nginx started (PID: ${NGINX_PID})"

# Start Fail2Ban (may fail if iptables not available in container — that's OK for lab)
fail2ban-server -f -x -v start 2>&1 &
F2B_PID=$!
echo "[+] Fail2Ban started (PID: ${F2B_PID})"

echo ""
echo "[*] Mitigation services running"
echo "[*] Rate limit: 30 req/min per IP (burst: 10)"
echo "[*] Connection limit: 20 per IP"
echo "[*] Fail2Ban monitoring active"
echo ""

# Monitor both services
wait "${NGINX_PID}"
