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

RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "arm64" ]; then TTYD_ARCH="aarch64"; CF_ARCH="arm64"; else TTYD_ARCH="x86_64"; CF_ARCH="amd64"; fi && \
    curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${TTYD_ARCH}" -o /usr/local/bin/ttyd && \
    chmod +x /usr/local/bin/ttyd && \
    curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -o /usr/local/bin/cloudflared && \
    chmod +x /usr/local/bin/cloudflared

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
