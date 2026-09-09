#!/usr/bin/env bash
# Manually push locally-built images (releases are automated by CI; this is a local fallback only).
# Prerequisite: log in to ghcr first ->
#   echo $GH_PAT | docker login ghcr.io -u axelburks --password-stdin   (PAT needs write:packages)
#   dockerhub is already logged in locally.
# Usage: ./dev/push.sh <addon_dir> <image_tag> [ghcr|dockerhub|both]
set -euo pipefail

ADDON="${1:?usage: push.sh <addon_dir> <image_tag> [ghcr|dockerhub|both]}"
IMG_TAG="${2:?usage: push.sh <addon_dir> <image_tag> [ghcr|dockerhub|both]}"
TARGET="${3:-both}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CTX="${REPO_ROOT}/${ADDON}"

IMG_TMPL="$(grep -E '^image:' "${CTX}/config.yaml" | head -1 | sed -E 's/^image:[[:space:]]*"?([^"]+)"?.*/\1/')"
[ -n "${IMG_TMPL}" ] || { echo "${ADDON}/config.yaml has no image field"; exit 1; }
BASENAME="${IMG_TMPL##*/}"

push_one() { echo ">>> docker push $1"; docker push "$1"; }

for ARCH in amd64 aarch64; do
  IMG="${BASENAME/\{arch\}/$ARCH}"
  case "$TARGET" in
    ghcr|both)      push_one "ghcr.io/axelburks/${IMG}:${IMG_TAG}" ;;
  esac
  case "$TARGET" in
    dockerhub|both) push_one "axelburks/${IMG}:${IMG_TAG}" ;;
  esac
done
echo "done."
