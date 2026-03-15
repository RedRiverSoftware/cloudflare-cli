FROM ubuntu:22.04

RUN apt-get update && apt-get install -y build-essential software-properties-common openssl \
    zip unzip --no-install-recommends \
    && apt-get install -y curl jq \
    && apt-get auto-remove && rm -rf /var/lib/apt/lists/*
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl"
RUN chmod +x ./kubectl
RUN mv ./kubectl /usr/local/bin/kubectl
RUN kubectl version --client

ADD k8s-tools.sh /k8s-tools.sh
RUN sed -i 's/\r$//' /k8s-tools.sh && chmod +x /k8s-tools.sh
