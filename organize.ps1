$ErrorActionPreference = "Stop"

$root = "c:\Users\ziad khaled\Desktop\dos-project"
Set-Location $root

# Create directories
$dirs = @(
    "victim/website",
    "victim/apache",
    "attacker/scripts",
    "packet_capture",
    "mitigation/nginx",
    "mitigation/fail2ban/filter.d",
    "monitoring/prometheus/rules",
    "monitoring/grafana/provisioning/dashboards",
    "monitoring/grafana/provisioning/datasources",
    "monitoring/grafana/dashboards",
    "scripts"
)

foreach ($d in $dirs) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

# Move files
$moves = @{
    "000-default.conf" = "victim/apache/000-default.conf"
    "apache2.conf" = "victim/apache/apache2.conf"
    "index.html" = "victim/website/index.html"
    "about.html" = "victim/website/about.html"
    "api.html" = "victim/website/api.html"
    "contact.html" = "victim/website/contact.html"
    
    "attack.sh" = "attacker/scripts/attack.sh"
    "simulate_load.sh" = "attacker/scripts/simulate_load.sh"
    "http_load.py" = "attacker/scripts/http_load.py"
    
    "capture_entrypoint.sh" = "packet_capture/capture_entrypoint.sh"
    
    "Dockerfile" = "mitigation/Dockerfile"
    "mitigation_entrypoint.sh" = "mitigation/mitigation_entrypoint.sh"
    "nginx.conf" = "mitigation/nginx/nginx.conf"
    "jail.download" = "mitigation/fail2ban/jail.local"
    
    "prometheus.yml" = "monitoring/prometheus/prometheus.yml"
    "dos_alerts.yml" = "monitoring/prometheus/rules/dos_alerts.yml"
    "loki-config.yml" = "monitoring/prometheus/loki-config.yml"
    "promtail-config.yml" = "monitoring/prometheus/promtail-config.yml"
    
    "dos_lab_overview.json" = "monitoring/grafana/dashboards/dos_lab_overview.json"
    "dashboards.yml" = "monitoring/grafana/provisioning/dashboards/dashboards.yml"
    "datasources.yml" = "monitoring/grafana/provisioning/datasources/datasources.yml"
    
    "start_lab.sh" = "scripts/start_lab.sh"
    "stop_lab.sh" = "scripts/stop_lab.sh"
    "capture.sh" = "scripts/capture.sh"
    "analyze_pcap.sh" = "scripts/analyze_pcap.sh"
    "export_reports.sh" = "scripts/export_reports.sh"
    "cleanup.sh" = "scripts/cleanup.sh"
    
    "env" = ".env"
}

foreach ($k in $moves.Keys) {
    if (Test-Path $k) {
        Move-Item -Force $k $moves[$k]
    }
}

# Create missing Dockerfiles

# 1. Victim Dockerfile
$victimDockerfile = @"
FROM ubuntu/apache2:2.4-22.04_beta
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
EXPOSE 80
"@
Set-Content -Path "victim/Dockerfile" -Value $victimDockerfile

# 2. Attacker Dockerfile
$attackerDockerfile = @"
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    apache2-utils \
    siege \
    hping3 \
    python3 \
    python3-pip \
    curl \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*
RUN pip3 install aiohttp
CMD ["tail", "-f", "/dev/null"]
"@
Set-Content -Path "attacker/Dockerfile" -Value $attackerDockerfile

# 3. Packet Capture Dockerfile
$captureDockerfile = @"
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    tshark \
    tcpdump \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*
COPY capture_entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
"@
Set-Content -Path "packet_capture/Dockerfile" -Value $captureDockerfile

Write-Host "Project organized successfully!"
