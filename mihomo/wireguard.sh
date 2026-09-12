#!/usr/bin/env bash

WG_DIR="/data/wireguard"
WG_INTERFACE="mihomo-wg"
WG_TUN_INTERFACE="Meta"
WG_DNS_PORT=""

ensure_wg_key() {
  if [ ! -s "$1" ]; then
    rm -f "$1.tmp"
    wg genkey > "$1.tmp"
    mv -f "$1.tmp" "$1"
  fi
}

remove_iptables_rule() {
  local table=$1 chain=$2
  shift 2
  while iptables -w -t "${table}" -C "${chain}" "$@" 2>/dev/null; do
    iptables -w -t "${table}" -D "${chain}" "$@"
  done
}

wireguard_remove_rules() {
  remove_iptables_rule filter FORWARD \
    -i "${WG_INTERFACE}" -o "${WG_TUN_INTERFACE}" -j ACCEPT
  remove_iptables_rule filter FORWARD \
    -i "${WG_TUN_INTERFACE}" -o "${WG_INTERFACE}" \
    -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  if [ -n "${WG_DNS_PORT}" ]; then
    remove_iptables_rule nat PREROUTING \
      -i "${WG_INTERFACE}" -p udp --dport 53 -j REDIRECT --to-ports "${WG_DNS_PORT}"
    remove_iptables_rule nat PREROUTING \
      -i "${WG_INTERFACE}" -p tcp --dport 53 -j REDIRECT --to-ports "${WG_DNS_PORT}"
  fi
}

wireguard_add_rules() {
  iptables -w -I FORWARD 1 \
    -i "${WG_INTERFACE}" -o "${WG_TUN_INTERFACE}" -j ACCEPT
  iptables -w -I FORWARD 1 \
    -i "${WG_TUN_INTERFACE}" -o "${WG_INTERFACE}" \
    -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  iptables -w -t nat -I PREROUTING 1 \
    -i "${WG_INTERFACE}" -p udp --dport 53 -j REDIRECT --to-ports "${WG_DNS_PORT}"
  iptables -w -t nat -I PREROUTING 1 \
    -i "${WG_INTERFACE}" -p tcp --dport 53 -j REDIRECT --to-ports "${WG_DNS_PORT}"
}

wireguard_stop() {
  wireguard_remove_rules
  if ip link show dev "${WG_INTERFACE}" >/dev/null 2>&1; then
    echo "[wg] removing ${WG_INTERFACE}"
    ip link delete dev "${WG_INTERFACE}"
  fi
}

wireguard_start() {
  local config_file=$1 enabled peers subnet allowed port dns url base
  local dns_listen
  local server_private server_public names name peer_dir peer_private peer_public
  local index

  enabled="$(jq -r '.wireguard_enabled // false' /data/options.json)"
  peers="$(jq -r '.wireguard_peers // ""' /data/options.json)"
  if [ "${enabled}" != "true" ]; then
    wireguard_stop
    echo "[wg] disabled (default)"
    return
  fi
  if [ -z "${peers}" ]; then
    wireguard_stop
    echo "[wg] enabled but 'peers' is empty; not starting"
    return
  fi

  dns_listen="$(yq -r '.dns.listen // ""' "${config_file}")"
  WG_DNS_PORT="${dns_listen##*:}"

  wireguard_stop

  subnet="$(jq -r '.wireguard_internal_subnet // "10.13.13.0"' /data/options.json)"
  allowed="$(jq -r '.wireguard_allowed_ips // "0.0.0.0/0"' /data/options.json)"
  port="$(jq -r '.wireguard_listen_port // 51820' /data/options.json)"
  dns="$(jq -r '.wireguard_peer_dns // ""' /data/options.json)"
  url="$(jq -r '.wireguard_server_url // ""' /data/options.json)"
  if [ -z "${url}" ]; then
    url="$(ip route get 1.1.1.1 2>/dev/null |
      awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' |
      head -1 || true)"
  fi
  base="${subnet%.*}"

  if printf '%s' "${peers}" | grep -qE '^[0-9]+$'; then
    names=""
    index=1
    while [ "${index}" -le "${peers}" ]; do
      names="${names} peer${index}"
      index=$((index + 1))
    done
  else
    names="$(printf '%s' "${peers}" | tr ',' ' ')"
  fi

  umask 077
  mkdir -p "${WG_DIR}"
  ensure_wg_key "${WG_DIR}/server.key"
  server_private="${WG_DIR}/server.key"
  server_public="$(wg pubkey < "${server_private}")"

  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  ip link add dev "${WG_INTERFACE}" type wireguard
  ip address add "${base}.1/24" dev "${WG_INTERFACE}"
  wg set "${WG_INTERFACE}" private-key "${server_private}" listen-port "${port}"

  index=2
  for name in ${names}; do
    peer_dir="${WG_DIR}/peer_${name}"
    mkdir -p "${peer_dir}"
    ensure_wg_key "${peer_dir}/priv"
    peer_private="$(cat "${peer_dir}/priv")"
    peer_public="$(printf '%s' "${peer_private}" | wg pubkey)"
    wg set "${WG_INTERFACE}" peer "${peer_public}" allowed-ips "${base}.${index}/32"

    echo "[wg] ============ PEER: ${name} ============"
    echo "[Interface]"
    echo "Address = ${base}.${index}/32"
    echo "PrivateKey = ${peer_private}"
    [ -n "${dns}" ] && echo "DNS = ${dns}"
    echo ""
    echo "[Peer]"
    echo "PublicKey = ${server_public}"
    echo "Endpoint = ${url}:${port}"
    echo "AllowedIPs = ${allowed}"
    echo "PersistentKeepalive = 25"
    echo "[wg] ======================================="
    index=$((index + 1))
  done

  ip link set dev "${WG_INTERFACE}" mtu 1420 up
  wireguard_add_rules
  echo "[wg] ${WG_INTERFACE} up on port ${port}; server public key = ${server_public}"
}
