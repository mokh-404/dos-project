# Cyber Range DoS Lab: Technical Operations & Command Reference Manual

## 1. Executive Summary

This document serves as the **Comprehensive Technical Operations and Command Reference Manual** for the Cyber Range DoS Lab project. It is designed to provide full transparency into every execution stage, script, terminal operation, and backend command utilized across the project's lifecycle. 

By detailing the precise parameters, internal mechanics, expected outputs, and troubleshooting procedures of each command, this manual empowers engineers, security analysts, and researchers to rebuild the environment from scratch, run every component correctly, and deeply understand the internal workflow of the entire federated system.

---

## 2. Project Organization & Initialization

Before any container is launched, the project directory must be systematically organized. This is handled by the initial setup script.

### 2.1 File Organization (`organize.ps1`)

**Command:**
```powershell
./organize.ps1
```
**Purpose:** Bootstraps the physical directory structure and stages all configuration files into their appropriate service-specific folders.

**Internal Operations:**
1. **Directory Creation (`New-Item -ItemType Directory -Force`)**: Systematically builds the workspace hierarchy (e.g., `victim/website`, `attacker/scripts`, `packet_capture`, `monitoring/grafana/dashboards`).
2. **File Migration (`Move-Item -Force`)**: Migrates root-level `.sh`, `.yml`, `.conf`, and `.html` files into their respective service directories.
3. **Dynamic Dockerfile Generation (`Set-Content`)**: Injects hardcoded Dockerfile configurations for the Victim (Apache), Attacker (hping3, siege, vegeta), and Packet Capture (tshark) containers directly into the file system.

**Expected Outcome:** A perfectly structured project directory ready for Docker Compose orchestration.

---

## 3. Infrastructure Deployment & Automation Workflow

The project utilizes Docker Compose to orchestrate a multi-network environment (Attacker, Victim, Monitoring, Logging). The deployment is managed via Bash/PowerShell wrappers.

### 3.1 Automated Execution Flow (`run_auto.ps1`)

**Command:**
```powershell
./run_auto.ps1
```
**Purpose:** Provides a "one-click" autonomous execution of the entire lab lifecycle, including deployment, simulation, visualization, and teardown.

**Internal Operations & Step-by-Step Commands:**
1. **Infrastructure Build:**
   ```powershell
   docker compose --profile attack --profile mitigation up -d --build
   ```
   *Explanation*: Deploys the infrastructure in detached mode (`-d`) and forces an image rebuild (`--build`). The `--profile` flags ensure optional services (like the attacker node and mitigation reverse proxy) are included in the deployment.

2. **Health Verification:**
   ```powershell
   docker inspect --format='{{.State.Health.Status}}' dos_victim
   ```
   *Explanation*: Loops and queries the Docker daemon for the health status of the victim container. Script execution halts until this returns `healthy`.

3. **Background Packet Capture:**
   ```powershell
   docker exec -d dos_packet_capture bash /entrypoint.sh
   ```
   *Explanation*: Executes the packet capture routine inside the isolated `dos_packet_capture` container in detached mode (`-d`). This ensures traffic is recorded without blocking the automated script's execution.

4. **Dashboard Launch:**
   ```powershell
   Start-Process "http://localhost:3000"
   ```
   *Explanation*: Automatically opens the default system web browser to the Grafana metrics dashboard.

5. **Attack Execution:**
   ```powershell
   docker exec dos_attacker bash /scripts/simulate_load.sh
   ```
   *Explanation*: Synchronously triggers the load simulation script on the attacker container. The terminal waits until the simulated DoS attack concludes.

6. **Graceful Packet Capture Termination:**
   ```powershell
   docker exec dos_packet_capture pkill -SIGINT tshark
   ```
   *Explanation*: Sends a `SIGINT` (Interrupt) signal to the `tshark` process inside the capture container. This ensures the PCAP file is safely flushed to disk and closed without corruption.

---

## 4. Attack Execution & Load Simulation

The attacker container (`dos_attacker`) houses a suite of network stress-testing tools. The orchestration is handled by `simulate_load.sh` and `attack.sh`.

### 4.1 Load Simulation Trigger (`scripts/attack.sh`)

**Command:**
```bash
./scripts/attack.sh [SCENARIO]
```
**Scenarios:** `ab`, `vegeta`, `siege`, `http_load`, `hping3`, `all`.
**Purpose:** Provides a centralized entry point to launch specific DoS methodologies from the host machine into the attacker container.

### 4.2 Traffic Generation Commands (`attacker/scripts/simulate_load.sh`)

#### 4.2.1 Apache Benchmark (HTTP Flood)
**Command:**
```bash
ab -n 1000 -c 10 -t 30 -k -H "Accept-Encoding: gzip, deflate" -r http://172.21.0.10/
```
**Explanation:**
* `-n 1000`: Maximum number of requests to perform.
* `-c 10`: Number of multiple requests to make concurrently.
* `-t 30`: Maximum number of seconds to spend for benchmarking.
* `-k`: Enables the HTTP KeepAlive feature.
* `-r`: Forces `ab` to not exit on socket receive errors.
**Behavior:** Generates a rapid burst of HTTP GET requests to exhaust Apache worker threads.

#### 4.2.2 Vegeta (Constant-Rate Load)
**Command:**
```bash
echo "GET http://172.21.0.10/" | vegeta attack -rate=100 -duration=30s | vegeta report
```
**Explanation:**
* `vegeta attack`: Reads target URLs from standard input.
* `-rate=100`: Enforces a strict continuous rate of 100 requests per second.
* `-duration=30s`: Sustains the attack for 30 seconds.
* `| vegeta report`: Pipes the binary output into a human-readable statistical report (latencies, success rates).
**Behavior:** Extremely precise rate-based HTTP loading, excellent for testing threshold-based rate limiting.

#### 4.2.3 Siege (Concurrent Multi-URL Load)
**Command:**
```bash
siege --concurrent=10 --time=30S --file=/tmp/siege_urls.txt
```
**Explanation:** Simulates multiple users accessing diverse endpoints simultaneously, mimicking complex user behavior rather than a simple single-endpoint flood.

#### 4.2.4 Hping3 (Network Layer Packet Injection)
**Command (ICMP Ping):**
```bash
hping3 -c 10 -1 --fast 172.21.0.10
```
**Command (TCP SYN Probe):**
```bash
hping3 -c 5 -S -p 80 172.21.0.10
```
**Explanation:**
* `-c 10`: Count (send exactly 10 packets).
* `-1`: ICMP mode.
* `-S`: Set the SYN tcp flag (simulating the start of a TCP handshake).
* `-p 80`: Target destination port 80.
**Behavior:** Used for educational demonstration of raw packet crafting at OSI Layers 3 and 4.

#### 4.2.5 Asynchronous Python HTTP Load (`http_load.py`)
**Command:**
```bash
python3 /scripts/http_load.py --target 172.21.0.10 --rate 50 --concurrency 10
```
**Explanation:** Utilizes Python's `asyncio` and `aiohttp` to generate highly concurrent, non-blocking asynchronous HTTP requests. Automatically calculates p95/p99 latencies and standard deviations.

---

## 5. Packet Capture & Digital Forensics (DFIR)

The `dos_packet_capture` container acts as an out-of-band network tap spanning the lab networks.

### 5.1 Tshark Packet Capture (`packet_capture/Dockerfile`)
**Command:**
```bash
tshark -i eth0 -f "tcp port 80" -b duration:60 -w /captures/traffic.pcap
```
**Explanation:**
* `-i eth0`: Listens on the primary interface.
* `-f "tcp port 80"`: BPF (Berkeley Packet Filter) capturing only HTTP traffic.
* `-b duration:60`: Ring-buffer rotation (creates a new file every 60 seconds).
* `-w`: Writes output to the specified binary file.

### 5.2 DFIR Analysis Script (`scripts/analyze_pcap.sh`)
This script executes automated forensic queries against the captured PCAP files.

#### General Capture Statistics
**Command:** `tshark -r traffic.pcap -q -z io,stat,0`
* **Purpose:** Generates a high-level summary of packet rates, byte counts, and duration.

#### Protocol Hierarchy Statistics
**Command:** `tshark -r traffic.pcap -q -z io,phs`
* **Purpose:** Displays a tree view of all protocols present in the capture (Ethernet -> IPv4 -> TCP -> HTTP).

#### Top Source IP Distribution
**Command:** `tshark -r traffic.pcap -T fields -e ip.src | sort | uniq -c | sort -rn | head -20`
* **Purpose:** Extracts just the source IP field (`-T fields -e ip.src`), counts occurrences, and sorts to identify the top bandwidth consumers (the attacker).

#### SYN Flood Identification
**Command:** `tshark -r traffic.pcap -Y "tcp.flags.syn==1 && tcp.flags.ack==0" -T fields -e frame.number | wc -l`
* **Purpose:** Filters (`-Y`) for packets containing only a SYN flag (initial connection request). High ratios of SYN vs. SYN-ACK indicate a potential TCP state exhaustion attack.

#### HTTP Method Distribution
**Command:** `tshark -r traffic.pcap -Y "http.request" -T fields -e http.request.method | sort | uniq -c`
* **Purpose:** Extracts HTTP methods (GET, POST) to verify the nature of the application-layer attack.

---

## 6. Environment Export & Cleanup

Proper lab hygiene is maintained through robust export and teardown scripts.

### 6.1 Exporting Reports (`scripts/export_reports.sh`)
**Command:**
```bash
./scripts/export_reports.sh
```
**Internal Operations:**
1. **Log Extraction:**
   ```bash
   docker exec dos_victim bash -c "cat /var/log/apache2/access.log" > apache_logs/access.log
   ```
   Pulls internal container logs into the host filesystem before destruction.
2. **Archiving:**
   ```bash
   tar -czf lab_export_TIMESTAMP.tar.gz -C ./exports lab_export_TIMESTAMP
   ```
   Bundles PCAPs, generated analysis markdown, and raw logs into a compressed, portable tarball.

### 6.2 Full Environment Teardown (`scripts/cleanup.sh`)
**Command:**
```bash
./scripts/cleanup.sh
```
**Internal Operations:**
1. **Container & Volume Destruction:**
   ```bash
   docker compose down -v --remove-orphans
   ```
   *Explanation*: Stops all compose-managed containers, removes all attached networks, and critically, deletes all anonymous and named volumes (`-v`). This resets Prometheus metrics, Grafana configurations, and Loki log states.
2. **File Deletion:**
   ```bash
   rm -f ./logs/*
   rm -f ./packet_capture/captures/*.pcap
   ```
   Wipes temporary runtime files while strictly preserving generated final reports.

---

## 7. Troubleshooting & Debugging

If the lab environment fails to initialize or exhibit expected behavior, consult the following CLI diagnostics:

**1. Containers failing to start / Port conflicts:**
* *Command:* `docker ps -a`
* *Fix:* Ensure ports 8080, 3000, 9090, 8081, 3100, and 8443 are free on the host. Run `./scripts/stop_lab.sh` to clear zombies.

**2. Attack scripts erroring out (Container Not Found):**
* *Command:* `docker compose ps`
* *Fix:* The attacker container must be booted using the specific compose profile: `docker compose --profile attack up -d`.

**3. No PCAP data generated:**
* *Command:* `docker logs dos_packet_capture`
* *Fix:* Ensure the target interface is correctly mapped and the container has `cap_add: [NET_ADMIN, NET_RAW]` privileges in `docker-compose.yml`.

**4. Grafana Dashboards show "No Data":**
* *Command:* `docker inspect dos_prometheus`
* *Fix:* Verify Prometheus is successfully scraping targets by navigating to `http://localhost:9090/targets`. Check network bridges if targets appear as "DOWN".

## 8. Operating System Compatibility Notes
* **Windows Host:** Must run scripts via PowerShell (`run_auto.ps1`, `organize.ps1`). Ensure Docker Desktop is configured for WSL2 backend. Line endings in all `.sh` scripts must be `LF` (not `CRLF`) to execute inside Linux containers.
* **Linux/macOS Host:** Native execution supported via `bash ./scripts/start_lab.sh`. Execute `chmod +x` on all scripts within `/scripts` and `/attacker/scripts` prior to runtime.
