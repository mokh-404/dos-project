FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false update \
    && apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false install -y \
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
