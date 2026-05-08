FROM ubuntu/apache2:2.4-22.04_beta
RUN apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false update \
    && apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false install -y curl \
    && rm -rf /var/lib/apt/lists/*
EXPOSE 80
