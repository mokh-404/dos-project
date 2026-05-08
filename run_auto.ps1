$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║     DoS Lab — Automated Execution Script        ║" -ForegroundColor Cyan
Write-Host "  ║     Educational Cybersecurity Training           ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── 1. Build & Start ─────────────────────────────────────────
Write-Host "[1/5] Building and starting all containers..." -ForegroundColor Yellow
docker compose up -d --build
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Docker build failed. Check the output above." -ForegroundColor Red
    exit 1
}
Write-Host "[+] Containers started." -ForegroundColor Green

# ── 2. Wait for Health ────────────────────────────────────────
Write-Host "[2/5] Waiting for services to become healthy..." -ForegroundColor Yellow
$retries = 0
$maxRetries = 20

while ($retries -lt $maxRetries) {
    $status = docker inspect --format='{{.State.Health.Status}}' dos_victim 2>$null
    if ($status -eq "healthy") {
        break
    }
    Write-Host "      Waiting for victim... (attempt $($retries+1)/$maxRetries)"
    Start-Sleep -Seconds 5
    $retries++
}

if ($retries -ge $maxRetries) {
    Write-Host "[ERROR] Victim server did not become healthy. Run 'docker compose ps' to check." -ForegroundColor Red
    exit 1
}
Write-Host "[+] All services healthy!" -ForegroundColor Green

# ── 3. Open Dashboards ───────────────────────────────────────
Write-Host "[3/5] Opening Grafana & Victim website in browser..." -ForegroundColor Yellow
Start-Process "http://localhost:3000"
Start-Process "http://localhost:8080"
Start-Sleep -Seconds 3

# ── 4. Run Attack Simulation ─────────────────────────────────
Write-Host "[4/5] Launching attack simulation..." -ForegroundColor Yellow
Write-Host "      Watch Grafana as the attack runs!" -ForegroundColor Cyan
docker exec dos_attacker bash /scripts/simulate_load.sh
Write-Host "[+] Attack simulation completed." -ForegroundColor Green

# ── 5. Stop Capture & Report ─────────────────────────────────
Write-Host "[5/5] Stopping packet capture..." -ForegroundColor Yellow
docker exec dos_packet_capture pkill -SIGINT tshark 2>$null
Start-Sleep -Seconds 3

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║          Lab Execution Complete!                 ║" -ForegroundColor Green
Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Reports  : ./data/reports/" -ForegroundColor White
Write-Host "  Captures : ./data/captures/" -ForegroundColor White
Write-Host "  Grafana  : http://localhost:3000" -ForegroundColor White
Write-Host "  Victim   : http://localhost:8080" -ForegroundColor White
Write-Host ""
Write-Host "  To shut down: docker compose down" -ForegroundColor DarkGray
Write-Host ""
