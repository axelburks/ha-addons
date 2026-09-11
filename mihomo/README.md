# Mihomo Proxy

A TUN transparent proxy add-on based on Mihomo (Clash.Meta). Once started, TUN takes over the HA OS host's outbound traffic at the routing layer.

## Install

In the add-on store, open this add-on, then **Install** and **Start**. Before the first start, adjust settings on the **Configuration** page as needed.

## Web UI

Once started, a **metacubexd** control panel is available in the HA sidebar (and via *Open Web UI* on the add-on page) — switch nodes/groups, watch live traffic and connections, and inspect rules. It is served through HA ingress: access goes through HA's own authentication, the mihomo API stays bound to `127.0.0.1` and is never exposed on the LAN, and no extra host port is used. The panel auto-detects its backend, so no manual URL/secret is needed.

## Configuration

The entire mihomo config is exposed as a single `config` field (YAML text), editable on the **Configuration** page (open the top-right menu, then *Edit in YAML*). **Your changes persist and are not overwritten by add-on updates.**

No proxy node is bundled by default; the `PROXY` group falls back to the built-in `DIRECT` (i.e. everything goes direct). To use a proxy, add your own node under `proxies` and point the `PROXY` group to it, e.g.:

```yaml
proxies:
  - {name: my-proxy, type: socks5, server: 192.168.20.2, port: 6153, udp: true}
proxy-groups:
  - {name: PROXY, type: select, proxies: [my-proxy, DIRECT]}
```

## Notes

- `host_network` + `NET_ADMIN`/`NET_RAW` + `/dev/net/tun`: required for TUN transparent proxying.
- The Web UI needs `external-controller: 127.0.0.1:9090` in `config` (the default). Keep it on `127.0.0.1` — nginx reverse-proxies it through ingress; do not remove it or the panel stops working.
- DNS defaults to `223.5.5.5` (redir-host); direct domains resolve through it, proxied domains are resolved by the proxy side.
- Whitelist rules are in `rules` within `config`; only listed domains go through `PROXY`, everything else is `DIRECT`.
