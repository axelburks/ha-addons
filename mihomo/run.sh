#!/usr/bin/env bash
set -e

CONF_DIR="/data/mihomo"
CONF_FILE="${CONF_DIR}/config.yaml"

source /wireguard.sh

pids=()
cleanup() {
  local status=$?
  trap - EXIT
  trap '' TERM INT

  if [ "${#pids[@]}" -gt 0 ]; then
    kill "${pids[@]}" 2>/dev/null || true
  fi

  if ! wireguard_stop; then
    echo "[wg] ERROR: failed to stop WireGuard" >&2
    [ "${status}" -ne 0 ] || status=1
  fi

  if [ "${#pids[@]}" -gt 0 ]; then
    wait "${pids[@]}" 2>/dev/null || true
  fi
  exit "${status}"
}

trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

mkdir -p "${CONF_DIR}"

# Read the full mihomo config from the add-on option (editable on the Configuration page).
# Read it directly from options.json with jq (jq is bundled in the image; most robust).
jq -r '.config' /data/options.json > "${CONF_FILE}"

if [ ! -s "${CONF_FILE}" ]; then
  echo "[mihomo] FATAL: config is empty; check add-on Configuration" >&2
  exit 1
fi

# TUN device fallback (config.yaml already declares devices, so it usually exists)
if [ ! -c /dev/net/tun ]; then
  mkdir -p /dev/net
  mknod /dev/net/tun c 10 200 || true
fi

wireguard_start "${CONF_FILE}"

# Web UI: nginx serves the metacubexd panel on the ingress port and reverse-proxies
# the external-controller API (127.0.0.1:9090) so it stays same-origin behind HA
# ingress. nginx needs its runtime dir before starting.
mkdir -p /run/nginx

echo "[mihomo] starting nginx (ingress web UI on :8099)"
nginx -g 'daemon off;' &
pids+=("$!")

echo "[mihomo] starting with config dir ${CONF_DIR}"
echo "[mihomo] ---- effective config (head) ----"
head -20 "${CONF_FILE}"
echo "[mihomo] ------------------------------------"
/usr/bin/mihomo -d "${CONF_DIR}" &
pids+=("$!")

# EXIT cleanup handles both successful and failed child exits.
wait -n
