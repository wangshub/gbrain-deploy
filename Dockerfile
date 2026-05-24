FROM oven/bun:1 AS builder

ARG GBRAIN_REF=latest

RUN bun install -g "github:garrytan/gbrain#${GBRAIN_REF}"

FROM oven/bun:1

RUN apt-get update && apt-get install -y --no-install-recommends postgresql-client && rm -rf /var/lib/apt/lists/*

RUN addgroup --system gbrain && adduser --system --ingroup gbrain gbrain

COPY --from=builder /root/.bun/install/global /home/gbrain/.bun/install/global

ENV PATH="/home/gbrain/.bun/install/global/node_modules/.bin:${PATH}"
ENV HOME=/home/gbrain

COPY scripts/entrypoint.sh /entrypoint.sh

USER gbrain
WORKDIR /home/gbrain

EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["serve", "--http"]
