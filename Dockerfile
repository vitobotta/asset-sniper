FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common \
    curl \
    wget \
    build-essential \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

ENV GO_VERSION=1.20.1
RUN wget https://go.dev/dl/go$GO_VERSION.linux-amd64.tar.gz && \
    tar -xvf go$GO_VERSION.linux-amd64.tar.gz && \
    mv go /usr/local && \
    rm go$GO_VERSION.linux-amd64.tar.gz

ENV GOROOT=/usr/local/go
ENV GOPATH=$HOME/go
ENV PATH=$GOPATH/bin:$GOROOT/bin:$PATH

RUN apt-get update && \
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get install -y python3.11 python3.11-venv python3-pip && \
    rm -rf /var/lib/apt/lists/*


RUN go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest

ENV PYTHONUNBUFFERED=1

CMD ["bash"]
