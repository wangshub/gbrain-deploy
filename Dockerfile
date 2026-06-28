# Base image is parameterized so China deploys can pull via a mirror.
# Default = upstream Docker Hub. See the "China mirror" section in .env.example.
ARG BUN_IMAGE=oven/bun:1
FROM ${BUN_IMAGE}

ARG GBRAIN_REF=master
# Optional China mirrors (empty = upstream defaults):
#   APT_MIRROR   e.g. mirrors.aliyun.com           (Debian apt)
#   NPM_REGISTRY e.g. https://registry.npmmirror.com (bun/npm deps)
ARG APT_MIRROR=
ARG NPM_REGISTRY=

# Optional: swap Debian apt sources to a faster mirror.
RUN if [ -n "${APT_MIRROR}" ]; then \
      sed -i "s|deb.debian.org|${APT_MIRROR}|g; s|security.debian.org|${APT_MIRROR}|g" /etc/apt/sources.list.d/debian.sources 2>/dev/null \
      || sed -i "s|deb.debian.org|${APT_MIRROR}|g; s|security.debian.org|${APT_MIRROR}|g" /etc/apt/sources.list 2>/dev/null || true; \
    fi

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates postgresql-client curl \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${GBRAIN_REF}" https://github.com/garrytan/gbrain.git /opt/gbrain-src \
    && cd /opt/gbrain-src \
    && if [ -n "${NPM_REGISTRY}" ]; then export npm_config_registry="${NPM_REGISTRY}"; fi \
    && bun install \
    && bun install -g file:/opt/gbrain-src \
    && mkdir -p /root/admin && cp -r /opt/gbrain-src/admin/dist /root/admin/

ENV HOME=/root

COPY scripts/entrypoint.sh /entrypoint.sh

WORKDIR /root

EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["serve", "--http", "--port", "3000", "--bind", "0.0.0.0"]
