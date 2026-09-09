ARG BUILD_FROM
FROM ${BUILD_FROM}

ARG MIHOMO_VERSION=v1.19.30
ARG BUILD_ARCH

# Dependencies: iptables/iproute2 (TUN routing), curl, jq (read config), tzdata, ca-certificates
RUN apk add --no-cache iptables iproute2 curl ca-certificates tzdata jq

# Pick the mihomo binary asset per architecture:
#   amd64   -> mihomo-linux-amd64-compatible-<ver>.gz (best compatibility, no CPU-feature requirement)
#   aarch64 -> mihomo-linux-arm64-<ver>.gz
RUN case "${BUILD_ARCH}" in \
      amd64)   ASSET="mihomo-linux-amd64-compatible-${MIHOMO_VERSION}.gz" ;; \
      aarch64) ASSET="mihomo-linux-arm64-${MIHOMO_VERSION}.gz" ;; \
      *) echo "Unsupported arch: ${BUILD_ARCH}" && exit 1 ;; \
    esac \
    && curl -fsSL "https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VERSION}/${ASSET}" -o /tmp/mihomo.gz \
    && gunzip /tmp/mihomo.gz \
    && mv /tmp/mihomo /usr/bin/mihomo \
    && chmod +x /usr/bin/mihomo \
    && /usr/bin/mihomo -v

COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
