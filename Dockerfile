FROM oven/bun:1 AS builder

ARG GBRAIN_REF=latest

RUN bun install -g "github:garrytan/gbrain#${GBRAIN_REF}"

FROM oven/bun:1

RUN addgroup --system gbrain && adduser --system --ingroup gbrain gbrain

COPY --from=builder /root/.bun/install/global /home/gbrain/.bun/install/global

ENV PATH="/home/gbrain/.bun/install/global/node_modules/.bin:${PATH}"
ENV HOME=/home/gbrain

USER gbrain
WORKDIR /home/gbrain

COPY scripts/entrypoint.sh /entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["serve", "--http"]
