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

# ---------------------------------------------------------------------------
# Optional WireGuard server (default OFF). wg0 uses "Table = off" so it never
# touches the default route, leaving mihomo's auto-route in sole charge. 
# ---------------------------------------------------------------------------
WG_ENABLED="$(jq -r '.wireguard.enabled // false' /data/options.json)"
WG_PEERS="$(jq -r '.wireguard.peers // ""' /data/options.json)"
if [ "${WG_ENABLED}" = "true" ] && [ -n "${WG_PEERS}" ]; then
  WG_SUBNET="$(jq -r '.wireguard.internal_subnet // "10.13.13.0"' /data/options.json)"
  WG_ALLOWED="$(jq -r '.wireguard.allowed_ips // "0.0.0.0/0"' /data/options.json)"
  WG_PORT="$(jq -r '.wireguard.listen_port // 51820' /data/options.json)"
  WG_DNS="$(jq -r '.wireguard.peer_dns // ""' /data/options.json)"
  WG_URL="$(jq -r '.wireguard.server_url // ""' /data/options.json)"
  # Empty server_url -> auto-detect the LAN IP on the default-route interface.
  if [ -z "${WG_URL}" ]; then
    WG_URL="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1 || true)"
  fi
  WG_BASE="${WG_SUBNET%.*}"

  # Expand peers: a bare integer N -> peer1..peerN; otherwise a CSV of names.
  if printf '%s' "${WG_PEERS}" | grep -qE '^[0-9]+$'; then
    WG_NAMES=""; n=1
    while [ "${n}" -le "${WG_PEERS}" ]; do WG_NAMES="${WG_NAMES} peer${n}"; n=$((n+1)); done
  else
    WG_NAMES="$(printf '%s' "${WG_PEERS}" | tr ',' ' ')"
  fi

  WG_DIR=/data/wireguard
  mkdir -p "${WG_DIR}" /etc/wireguard
  umask 077
  [ -f "${WG_DIR}/server.key" ] || wg genkey > "${WG_DIR}/server.key"
  SRV_PRIV="$(cat "${WG_DIR}/server.key")"
  SRV_PUB="$(printf '%s' "${SRV_PRIV}" | wg pubkey)"

  {
    echo "[Interface]"
    echo "Address = ${WG_BASE}.1/24"
    echo "PrivateKey = ${SRV_PRIV}"
    echo "ListenPort = ${WG_PORT}"
    echo "Table = off"
  } > /etc/wireguard/wg0.conf

  i=2
  for name in ${WG_NAMES}; do
    pdir="${WG_DIR}/peer_${name}"
    mkdir -p "${pdir}"
    [ -f "${pdir}/priv" ] || wg genkey > "${pdir}/priv"
    ppriv="$(cat "${pdir}/priv")"
    ppub="$(printf '%s' "${ppriv}" | wg pubkey)"
    # Server side: this peer's tunnel /32 only (crypto-routing / return path).
    {
      echo ""
      echo "[Peer]"
      echo "PublicKey = ${ppub}"
      echo "AllowedIPs = ${WG_BASE}.${i}/32"
    } >> /etc/wireguard/wg0.conf
    # Client side: printed to the log for import on the peer (e.g. UDM).
    echo "[wg] ============ PEER: ${name} ============"
    echo "[Interface]"
    echo "Address = ${WG_BASE}.${i}/32"
    echo "PrivateKey = ${ppriv}"
    [ -n "${WG_DNS}" ] && echo "DNS = ${WG_DNS}"
    echo ""
    echo "[Peer]"
    echo "PublicKey = ${SRV_PUB}"
    echo "Endpoint = ${WG_URL}:${WG_PORT}"
    echo "AllowedIPs = ${WG_ALLOWED}"
    echo "PersistentKeepalive = 25"
    echo "[wg] ======================================="
    i=$((i+1))
  done

  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
  wg-quick up wg0 || { echo "[wg] FATAL: wg-quick up failed" >&2; exit 1; }
  echo "[wg] wg0 up on port ${WG_PORT}; server public key = ${SRV_PUB}"
elif [ "${WG_ENABLED}" = "true" ]; then
  echo "[wg] enabled but 'peers' is empty; not starting wg0"
else
  echo "[wg] disabled (default)"
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
