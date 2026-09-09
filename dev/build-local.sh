#!/usr/bin/env bash
# Build an addon image locally (no push; --load into local docker only).
# Usage: ./dev/build-local.sh <addon_dir> <arch> [image_tag]
#   addon_dir : addon directory name under the repo root, e.g. mihomo
#   arch      : amd64 | aarch64
#   image_tag : image tag, default "dev" (local checks only; release tags come from CI via config.yaml version)
# Image-name single source of truth: <addon_dir>/config.yaml image field (contains the {arch} placeholder).
# mihomo-version single source of truth: <addon_dir>/Dockerfile ARG MIHOMO_VERSION default.
set -euo pipefail

ADDON="${1:?usage: build-local.sh <addon_dir> <arch> [image_tag]}"
ARCH="${2:?usage: build-local.sh <addon_dir> <arch> [image_tag]}"
IMG_TAG="${3:-dev}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CTX="${REPO_ROOT}/${ADDON}"

[ -f "${CTX}/config.yaml" ] || { echo "no such addon: ${ADDON}/config.yaml not found"; exit 1; }

# Read the image base name (with {arch}) from the config.yaml image field, e.g. ghcr.io/axelburks/{arch}-mihomo-proxy
IMG_TMPL="$(grep -E '^image:' "${CTX}/config.yaml" | head -1 | sed -E 's/^image:[[:space:]]*"?([^"]+)"?.*/\1/')"
[ -n "${IMG_TMPL}" ] || { echo "${ADDON}/config.yaml has no image field"; exit 1; }
BASENAME="${IMG_TMPL##*/}"                       # {arch}-mihomo-proxy

case "$ARCH" in
  amd64)   PLATFORM=linux/amd64; BASE=ghcr.io/home-assistant/amd64-base:latest ;;
  aarch64) PLATFORM=linux/arm64; BASE=ghcr.io/home-assistant/aarch64-base:latest ;;
  *) echo "bad arch: $ARCH (use amd64|aarch64)"; exit 1 ;;
esac
IMG="${BASENAME/\{arch\}/$ARCH}"                 # amd64-mihomo-proxy

set -x
docker buildx build \
  --builder multi \
  --platform "$PLATFORM" \
  --build-arg BUILD_FROM="$BASE" \
  --build-arg BUILD_ARCH="$ARCH" \
  -t "ghcr.io/axelburks/${IMG}:${IMG_TAG}" \
  -t "axelburks/${IMG}:${IMG_TAG}" \
  --load \
  "$CTX"
