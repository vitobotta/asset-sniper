#!/bin/bash

set -e

IMAGE=vitobotta/assetsniper

VERSION=v${VERSION:-`git rev-parse --short HEAD`}

docker buildx create --name=buildkit-assetsniper --use --driver=docker-container > /dev/null 2>&1 || true

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ${IMAGE}:latest \
  -t ${IMAGE}:${VERSION} \
  --progress=plain \
  --push \
  --cache-to type=registry,compression=zstd,mode=max,ref=${IMAGE}:buildcache \
  --cache-from type=registry,ref=${IMAGE}:buildcache .

docker buildx rm buildkit-assetsniper > /dev/null 2>&1 || true

echo

echo Image: ${IMAGE}:${VERSION}

