FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    openssh-client \
    procps \
    python3 \
    tmux \
    && rm -rf /var/lib/apt/lists/*

# Install ttyd (x86_64 static binary)
RUN curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64" -o /usr/local/bin/ttyd \
    && chmod +x /usr/local/bin/ttyd

# Install cloudflared (x86_64 Linux binary)
RUN curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared

# Install Claude Code CLI, Supergateway, Filesystem MCP, and Tmux MCP globally
RUN npm install -g \
    @anthropic-ai/claude-code \
    supergateway \
    @modelcontextprotocol/server-filesystem \
    tmux-mcp

# Pre-cache corhub workspace skeleton for fast, reliable first-boot volume seeding
ARG CORHUB_REPO_URL="https://github.com/2ndcortex-labs/corhub.git"
RUN git clone --depth 1 "${CORHUB_REPO_URL}" /opt/corhub-seed || mkdir -p /opt/corhub-seed

WORKDIR /app
COPY gateway.mjs /app/gateway.mjs
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

RUN mkdir -p /workspace
WORKDIR /workspace

ENTRYPOINT ["/app/entrypoint.sh"]
