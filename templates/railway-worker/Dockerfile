FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    openssh-client \
    procps \
    python3 \
    ripgrep \
    tmux \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g \
    @anthropic-ai/claude-code \
    supergateway \
    tmux-mcp \
    @modelcontextprotocol/server-filesystem

WORKDIR /opt/worker

COPY gateway.mjs /opt/worker/gateway.mjs

COPY entrypoint.sh /opt/worker/entrypoint.sh

RUN chmod +x /opt/worker/entrypoint.sh

ENV PORT=8080

ENV WORKSPACE_DIR=/workspace

ENTRYPOINT ["/opt/worker/entrypoint.sh"]
