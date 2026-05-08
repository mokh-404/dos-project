# 🛡️ DoS Attack Simulation & Analysis Lab

> **Educational Cybersecurity Training Environment**  
> ⚠️ FOR ISOLATED LAB USE ONLY — DO NOT target external systems or public infrastructure.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Services & Ports](#services--ports)
- [How to Use the Lab](#how-to-use-the-lab)
  - [Launching Attacks](#launching-attacks)
  - [Using Grafana (Monitoring Dashboard)](#using-grafana-monitoring-dashboard)
  - [Using Prometheus (Metrics Engine)](#using-prometheus-metrics-engine)
  - [Viewing Logs & Reports](#viewing-logs--reports)
- [Understanding What Happens During an Attack](#understanding-what-happens-during-an-attack)
- [Mitigation Thresholds](#mitigation-thresholds)
- [Configuration Reference](#configuration-reference)
- [Troubleshooting](#troubleshooting)

---

## Overview

This lab creates an **isolated Docker network** where you can safely simulate and analyze DoS (Denial of Service) attacks. It consists of 7 containers:

| Container | Role | What it does |
|---|---|---|
| **victim** | Target server | Apache2 web server with **deliberately limited resources** (0.15 CPU, 48MB RAM, 10 workers) |
| **attacker** | Attack tools | Contains `ab`, `siege`, `hping3`, `python3` for generating traffic |
| **mitigation** | Defense layer | Nginx reverse proxy with rate limiting + Fail2Ban for IP blocking |
| **packet_capture** | Forensics | Captures network traffic (PCAP files) for analysis |
| **prometheus** | Metrics collection | Scrapes Apache performance metrics every 5 seconds |
| **apache_exporter** | Metrics translator | Converts Apache's `mod_status` output into Prometheus-compatible format |
| **grafana** | Visualization | Real-time dashboards showing request rate, worker saturation, response times |

### Why is the victim "weak"?

The victim container is **intentionally crippled** to simulate a vulnerable, under-provisioned server:

- **CPU**: 0.15 cores (15% of one core)
- **Memory**: 48MB (no swap)
- **Workers**: Only 10 Apache worker processes

This means when 200 concurrent connections hit it, the server **gets destroyed** — response times spike from ~5ms to **3,000ms+**, workers max out at 10/10, and only ~65 req/s get through instead of the 1,500+ it could handle with unlimited resources.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    Docker Network: lab_net                       │
│                                                                  │
│  ┌──────────┐    HTTP flood    ┌──────────────┐                 │
│  │ ATTACKER │ ───────────────> │    VICTIM     │                │
│  │ ab/siege │                  │ Apache2 (10w) │                │
│  │ hping3   │                  │ 0.25CPU/64MB  │                │
│  └──────────┘                  └───────┬───────┘                │
│                                        │ mod_status             │
│  ┌──────────────┐              ┌───────┴───────┐                │
│  │  MITIGATION  │              │APACHE EXPORTER│                │
│  │  Nginx + F2B │              │  :9117/metrics│                │
│  │   :8443      │              └───────┬───────┘                │
│  └──────────────┘                      │                        │
│                                ┌───────┴───────┐                │
│  ┌──────────────┐              │  PROMETHEUS   │                │
│  │PACKET CAPTURE│              │  :9090        │                │
│  │   tshark     │              └───────┬───────┘                │
│  └──────────────┘                      │                        │
│                                ┌───────┴───────┐                │
│                                │   GRAFANA     │                │
│                                │   :3000       │                │
│                                └───────────────┘                │
└──────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

- **Docker Desktop** (Windows/Mac) or **Docker Engine** (Linux)
- **Docker Compose v2** (included with Docker Desktop)
- At least **4GB free RAM** and **2 CPU cores**

---

## Quick Start

### Option 1: PowerShell Script (Windows)

```powershell
cd "dos-project"
.\run_auto.ps1
```

### Option 2: Manual

```bash
cd dos-project
docker compose up -d --build
```

Wait ~60 seconds for all containers to become healthy, then:

- **Victim website**: http://localhost:8080
- **Grafana dashboard**: http://localhost:3000
- **Prometheus**: http://localhost:9090
- **Mitigation proxy**: http://localhost:8443

---

## Services & Ports

| Service | Container Name | Port | URL |
|---|---|---|---|
| Victim (Apache) | `dos_victim` | 8080 | http://localhost:8080 |
| Mitigation (Nginx) | `dos_mitigation` | 8443 | http://localhost:8443 |
| Prometheus | `dos_prometheus` | 9090 | http://localhost:9090 |
| Grafana | `dos_grafana` | 3000 | http://localhost:3000 |
| Apache Exporter | `dos_apache_exporter` | 9117 (internal) | — |
| Attacker | `dos_attacker` | — | — |
| Packet Capture | `dos_packet_capture` | — | — |

---

## How to Use the Lab

### Launching Attacks

All attacks are run from the `dos_attacker` container. Use `docker exec` to trigger them:

#### Individual Attack Scenarios

```bash
# Apache Benchmark — HTTP flood (4 parallel streams x 200 concurrent, 60 seconds)
docker exec -e SCENARIO=ab dos_attacker bash /scripts/simulate_load.sh

# Siege — Multi-URL concurrent load
docker exec -e SCENARIO=siege dos_attacker bash /scripts/simulate_load.sh

# hping3 — Low-rate packet inspection demo (ICMP + TCP SYN)
docker exec -e SCENARIO=hping3 dos_attacker bash /scripts/simulate_load.sh

# Connection exhaustion — Slow curl requests
docker exec -e SCENARIO=conn dos_attacker bash /scripts/simulate_load.sh

# ALL scenarios sequentially
docker exec -e SCENARIO=all dos_attacker bash /scripts/simulate_load.sh
```

#### Custom Attack Parameters

Override defaults via environment variables:

```bash
# Even heavier attack: 1000 req/s rate, 500 concurrent, 60 seconds
docker exec -e SCENARIO=ab \
  -e ATTACK_RATE=1000 \
  -e ATTACK_CONCURRENCY=500 \
  -e ATTACK_DURATION=60 \
  dos_attacker bash /scripts/simulate_load.sh
```

#### What each attack tool does:

| Tool | What it does | Impact on victim |
|---|---|---|
| **ab** (Apache Benchmark) | Sends N concurrent HTTP GET requests | Saturates worker pool, spikes response time |
| **siege** | Hits multiple URLs simultaneously | Simulates distributed user load |
| **hping3** | Sends raw ICMP/TCP packets | Demonstrates packet-level traffic (low rate, educational) |
| **curl slow-read** | Opens connections and reads very slowly | Holds workers busy, simulates Slowloris-style attack |

---

### Using Grafana (Monitoring Dashboard)

**URL**: http://localhost:3000 (no login required — anonymous admin access enabled)

The dashboard auto-loads at "DoS Lab — Overview Dashboard" and shows:

#### Top Row — Live Stats

| Panel | What it shows | Normal value | Under attack |
|---|---|---|---|
| **⚡ Request Rate** | Requests per second hitting Apache | ~0.3 req/s | 100+ req/s (RED) |
| **👷 Busy Workers (max 10)** | How many of 10 Apache workers are busy | 1 | **10/10** (RED = saturated) |
| **⏱️ Avg Response Time** | How long each request takes | ~5ms | **400-900ms** (RED = server choking) |
| **🔌 Active Connections** | Current TCP connections to Apache | 0-1 | 18+ (RED) |

#### Time Series Graphs

| Graph | What to look for |
|---|---|
| **Request Rate Over Time** | Sharp spike during attacks, flat baseline otherwise |
| **Workers (Busy vs Idle)** | Red (busy) fills up to 10, green (idle) drops to 0 = worker pool exhausted |
| **Response Time** | Spikes to 80-400ms during attack = server struggling under CPU pressure |
| **Apache Throughput** | KB/sec served — peaks during flood, then drops when server chokes |
| **Apache Connections** | Total active connections — shows flood pattern |

#### What the workers panel means:

Apache handles requests using **worker processes**. This lab limits Apache to only **10 workers**. Think of them as cashiers at a store:

- **Idle workers** = cashiers waiting for customers (green line)
- **Busy workers** = cashiers serving customers (red line)
- When all 10 are busy, **new requests must WAIT in a queue** → response time spikes
- If the queue overflows, requests start **failing**

During an attack, you'll see the red line hit 10 and stay there while the green drops to 0. This is **worker pool exhaustion** — the primary effect of an HTTP flood DoS.

---

### Using Prometheus (Metrics Engine)

**URL**: http://localhost:9090

Prometheus is the metrics collection engine that powers Grafana. Here's what you can do:

#### Check Target Health

Go to **Status → Targets** (http://localhost:9090/targets) to see:

| Target | What it monitors | Should be |
|---|---|---|
| `apache` | Apache via apache_exporter:9117 | **UP** ✅ |
| `grafana` | Grafana internal metrics | **UP** ✅ |
| `prometheus` | Self-monitoring | **UP** ✅ |

If any target shows **DOWN**, that service has a problem.

#### Run Metric Queries

Go to **Graph** (http://localhost:9090/graph) and type PromQL queries:

```promql
# Current request rate
rate(apache_accesses_total[30s])

# Number of busy workers right now
apache_workers{state="busy"}

# Average response time in milliseconds
rate(apache_duration_ms_total[30s]) / rate(apache_accesses_total[30s])

# Total bytes served
apache_sent_kilobytes_total

# Total requests ever served since container start
apache_accesses_total

# Connection states
apache_connections
```

Click **Execute** → switch to the **Graph** tab to see values over time.

#### Check Alerting Rules

Go to **Status → Rules** (http://localhost:9090/rules) to see alert thresholds:

| Alert | Fires when | Severity |
|---|---|---|
| `HighApacheRequestRate` | > 50 req/s for 30s | ⚠️ Warning |
| `CriticalApacheRequestRate` | > 200 req/s for 15s | 🔴 Critical |
| `ApacheWorkersExhausted` | > 40 busy workers | ⚠️ Warning |
| `HighApacheThroughput` | > 5000 KB/s | ⚠️ Warning |

---

### Viewing Logs & Reports

All data is stored on your host machine in the `./data/` directory:

```
data/
├── logs/                    # Apache access & error logs
│   ├── access.log           # Every HTTP request to the victim
│   ├── dos_analysis.log     # Structured DoS analysis log
│   └── error.log            # Apache errors
├── reports/                 # Attack tool output
│   ├── ab_report_*.txt      # Apache Benchmark raw results
│   ├── siege_report_*.txt   # Siege raw results  
│   └── summary_*.md         # Per-attack summary with status
├── captures/                # PCAP network captures
│   ├── capture_*.pcap       # Rotating packet captures (60s each)
│   └── capture.log          # Tshark capture log
├── prometheus/              # Prometheus time-series database
└── grafana/                 # Grafana state & config
```

#### Reading the Summary Report

After each attack, a summary report is generated in `./data/reports/summary_*.md`:

```markdown
# DoS Lab — Load Simulation Report

**Started**: 20260508_211124
**Completed**: 2026-05-08 21:11:54 UTC
**Target**: http://victim:80
**Rate**: 200 req/s | **Duration**: 30s | **Concurrency**: 50

## Scenarios Executed
| Tool | Status |
|---|---|
| Apache Benchmark (ab) | ✅ Completed |

## Files Generated
- /reports/ab_report_20260508_211124.txt
- /reports/summary_20260508_211124.md
```

> **Note**: Only scenarios that were actually executed appear in the report. Skipped or failed scenarios are marked with ⏭️ or ❌.

---

## Understanding What Happens During an Attack

### Before Attack (Baseline)
- Request rate: ~0.3 req/s (just health checks)
- Busy workers: 1/10
- Response time: ~5ms
- The victim website at http://localhost:8080 loads instantly

### During Attack (4 streams x 200 connections = 800 total)
- Request rate: **65-80 req/s** (CPU-bottlenecked — server can't go faster)
- Busy workers: **10/10** (maxed out — all workers occupied)
- Response time: **3,000-27,000ms** (up to 27 SECONDS per request!)
- The victim website takes **6-10 seconds to load** or times out completely
- Only ~4,400 of the potential 30,000+ requests complete in 60 seconds

### After Attack
- Workers drain back to idle within seconds
- Response time returns to normal
- Request rate drops to baseline

### Why It Works

The victim is limited to:
- **0.15 CPU cores** → can only process ~65 req/s even at 100% CPU
- **48MB RAM** → leaves very little memory for buffering
- **10 Apache workers** → only 10 simultaneous requests can be handled, rest queue up
- **KeepAlive disabled** → each request opens a new connection (more overhead)

So when 800 simultaneous connections (4 streams x 200) flood the server for 60 seconds, it:
1. **Exhausts all 10 workers** instantly
2. **Queues remaining 790 connections** → massive queue backlog
3. **CPU maxes out at 0.15 cores** → each request takes 9-27 seconds
4. **Response time spirals** → 5ms → 400ms+ as the queue backs up

---

## Mitigation Thresholds

The mitigation container (Nginx + Fail2Ban) sits at http://localhost:8443 and enforces these limits:

### Nginx Rate Limiting

| Rule | Limit | Burst | Effect |
|---|---|---|---|
| General rate limit | 30 requests/minute per IP | 10 extra (burst) | Returns `503` when exceeded |
| Strict rate limit | 5 requests/minute per IP | — | For sensitive endpoints |
| Connection limit | 20 concurrent connections per IP | — | Returns `503` when exceeded |

### Fail2Ban (Automatic IP Blocking)

| Jail | Trigger | Ban Duration | What it watches |
|---|---|---|---|
| `nginx-limit-req` | 5 rate-limit violations in 60s | 5 minutes | Nginx error logs |
| `nginx-req-limit` | 200 requests in 60s | 10 minutes | Nginx access logs |
| `apache-dos` | 300 requests in 60s | 10 minutes | Apache access logs |
| `apache-overflows` | 2 buffer overflow errors in 10min | 5 minutes | Apache error logs |
| `apache-noscript` | 5 script scan attempts in 10min | 5 minutes | Apache access logs |
| `slowloris` | 2 slow connection errors in 10min | 30 minutes | Nginx error logs |

### Testing Mitigation

To see mitigation in action, attack through the Nginx proxy instead of directly:

```bash
# Attack through the mitigation layer (port 8443)
docker exec -e TARGET_HOST=mitigation -e TARGET_PORT=80 \
  -e SCENARIO=ab dos_attacker bash /scripts/simulate_load.sh
```

You'll see many `503` errors as Nginx rate-limits and Fail2Ban blocks the attacker's IP.

---

## Configuration Reference

### Environment Variables (.env)

| Variable | Default | Description |
|---|---|---|
| `VICTIM_PORT` | 8080 | Host port for victim website |
| `MITIGATION_PORT` | 8443 | Host port for mitigation proxy |
| `PROMETHEUS_PORT` | 9090 | Host port for Prometheus |
| `GRAFANA_PORT` | 3000 | Host port for Grafana |
| `ATTACK_RATE` | 500 | Requests/sec for load tools |
| `ATTACK_DURATION` | 60 | Attack duration in seconds |
| `ATTACK_CONCURRENCY` | 200 | Concurrent connections |
| `GRAFANA_USER` | admin | Grafana admin username |
| `GRAFANA_PASSWORD` | doslab2024 | Grafana admin password |

### Victim Resource Limits (docker-compose.yml)

| Resource | Value | Why |
|---|---|---|
| `cpus` | 0.15 | 15% of one CPU core — starves the server |
| `mem_limit` | 48m | 48MB RAM — minimal memory |
| `memswap_limit` | 48m | No swap — prevents memory overflow |
| `MaxRequestWorkers` | 10 | Only 10 simultaneous requests handled |

To make the victim stronger or weaker, edit these values in `docker-compose.yml` and `victim/apache/apache2.conf`, then rebuild:

```bash
docker compose down
docker compose up -d --build
```

---

## Troubleshooting

### Grafana shows "No data"

1. Check Prometheus targets: http://localhost:9090/targets
2. All 3 targets (apache, grafana, prometheus) should show **UP**
3. If `apache` is DOWN, restart the apache_exporter: `docker compose restart apache_exporter`

### Victim container keeps restarting

The 48MB memory limit may be too tight for your system. Increase `mem_limit` in `docker-compose.yml` to `128m`.

### Attacks don't seem to affect the victim

- Make sure you're attacking `victim:80` (direct) not `mitigation:80`
- Check that resource limits are applied: `docker inspect dos_victim --format '{{.HostConfig.NanoCpus}} {{.HostConfig.Memory}}'`
- Should show `150000000` (0.15 CPU) and `50331648` (48MB)

### Port already in use

Change ports in `.env` file (e.g., `VICTIM_PORT=9080`).

### How to stop everything

```bash
docker compose down        # Stop and remove containers
docker compose down -v     # Also remove volumes
```

---

## Project Structure

```
dos-project/
├── docker-compose.yml          # Service definitions
├── .env                        # Configuration variables
├── run_auto.ps1                # PowerShell launcher script
├── README.md                   # This file
├── victim/
│   ├── Dockerfile              # Apache2 container build
│   ├── apache/
│   │   ├── apache2.conf        # Apache config (10 workers, no keepalive)
│   │   └── 000-default.conf    # Virtual host + mod_status
│   └── website/                # Static HTML site served by victim
├── attacker/
│   ├── Dockerfile              # Ubuntu + attack tools
│   └── scripts/
│       └── simulate_load.sh    # Attack orchestration script
├── mitigation/
│   ├── Dockerfile              # Nginx + Fail2Ban
│   ├── nginx/
│   │   └── nginx.conf          # Rate limiting configuration
│   └── fail2ban/
│       └── jail.local          # Ban rules and thresholds
├── packet_capture/
│   ├── Dockerfile              # Tshark/tcpdump
│   └── entrypoint.sh           # Capture rotation script
├── monitoring/
│   ├── prometheus/
│   │   ├── prometheus.yml      # Scrape targets (5s interval)
│   │   └── rules/
│   │       └── dos_alerts.yml  # Alert rules
│   └── grafana/
│       ├── provisioning/       # Datasource auto-config
│       └── dashboards/
│           └── dos_lab_overview.json  # Main dashboard
└── data/                       # Persistent data (bind-mounted)
    ├── logs/
    ├── reports/
    ├── captures/
    ├── prometheus/
    └── grafana/
```

---

*DoS Lab — Educational Cybersecurity Training Environment*  
*Built for learning about network security, attack patterns, and defense mechanisms.*
