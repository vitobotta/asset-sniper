FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PATH="/root/.local/bin:$PATH"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common \
    build-essential \
    ca-certificates \
    gnupg \
    lsb-release \
    curl \
    wget \
    git && \
    rm -rf /var/lib/apt/lists/*

RUN add-apt-repository ppa:longsleep/golang-backports && \
  apt-get update && \
  apt-get install -y golang-go && \
  rm -rf /var/lib/apt/lists/*

RUN add-apt-repository ppa:deadsnakes/ppa && \
  apt-get update && \
  apt-get install -y python3.11 python3.11-venv python3-pip && \
  rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

ENV PATH=/root/.cargo/bin:$PATH
ENV PYTHONUNBUFFERED=1

RUN go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest

CMD ["bash"]
