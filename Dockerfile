FROM oven/bun:1

ARG GBRAIN_REF=master

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${GBRAIN_REF}" https://github.com/garrytan/gbrain.git /opt/gbrain-src \
    && cd /opt/gbrain-src && bun install \
    && bun run build 2>/dev/null; true \
    && bun install -g file:/opt/gbrain-src \
    && mkdir -p /root/admin && cp -r /opt/gbrain-src/admin/dist /root/admin/

ENV HOME=/root

COPY scripts/entrypoint.sh /entrypoint.sh

WORKDIR /root

EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["serve", "--http", "--port", "3000", "--bind", "0.0.0.0"]
