FROM node:22-bookworm-slim

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl git gosu socat procps \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g openclaw@latest

RUN useradd -m -s /bin/bash openclaw \
  && mkdir -p /data && chown openclaw:openclaw /data

COPY --chmod=755 entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
