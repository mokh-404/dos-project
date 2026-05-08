# ============================================================
# Mitigation Container — Nginx Reverse Proxy + Fail2Ban
# DoS Lab — Educational Use Only
# ============================================================
FROM ubuntu:22.04

LABEL description="Nginx reverse proxy with rate limiting and Fail2Ban protection"
LABEL version="1.0"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false update \
    && apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false install -y --no-install-recommends \
    nginx \
    fail2ban \
    curl \
    wget \
    iptables \
    net-tools \
    iproute2 \
    procps \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Copy configs
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY fail2ban/jail.local /etc/fail2ban/jail.local
COPY fail2ban/filter.d/ /etc/fail2ban/filter.d/

# Create nginx log directory
RUN mkdir -p /var/log/nginx /var/log/fail2ban

# Copy entrypoint
COPY mitigation_entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80

HEALTHCHECK --interval=15s --timeout=5s --retries=3 \
    CMD nginx -t && echo OK || exit 1

CMD ["/entrypoint.sh"]
