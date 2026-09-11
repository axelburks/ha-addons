#!/usr/bin/env bash
set -e

CONF_DIR="/data/mihomo"
CONF_FILE="${CONF_DIR}/config.yaml"

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

# Web UI: nginx serves the metacubexd panel on the ingress port and reverse-proxies
# the external-controller API (127.0.0.1:9090) so it stays same-origin behind HA
# ingress. nginx needs its runtime dir before starting.
mkdir -p /run/nginx

# If either process dies, tear the whole add-on down so HA can restart it cleanly.
pids=()
term() {
  trap - TERM INT
  kill "${pids[@]}" 2>/dev/null || true
}
trap term TERM INT

echo "[mihomo] starting nginx (ingress web UI on :8099)"
nginx -g 'daemon off;' &
pids+=("$!")

echo "[mihomo] starting with config dir ${CONF_DIR}"
echo "[mihomo] ---- effective config (head) ----"
head -20 "${CONF_FILE}"
echo "[mihomo] ------------------------------------"
/usr/bin/mihomo -d "${CONF_DIR}" &
pids+=("$!")

# Exit as soon as any child exits; term() stops the survivor.
wait -n
term
wait
