# =============================================================================
# Dockerfile.easypanel — Slim Hermes Gateway for Easypanel Free Tier
# =============================================================================
# Optimized for VPS with 512MB-1024MB RAM constraint.
# Strips: Playwright/Chromium, Node.js/TUI/Dashboard, s6-overlay, build tools.
# Keeps: Python gateway core + messaging adapters + API server.
#
# Build:  docker build -f Dockerfile.easypanel -t hermes-gateway:slim .
# Run:    docker run -e NVIDIA_API_KEY=... -p 8080:8080 hermes-gateway:slim
# =============================================================================

# ---------- Stage 1: uv installer ----------
FROM ghcr.io/astral-sh/uv:0.5.9-python3.13-bookworm-slim AS uv_source

# ---------- Stage 2: gosu installer ----------
FROM debian:13.4-slim AS gosu_source
ARG GOSU_VERSION=1.17
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && \
    curl -fsSL -o /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-$(dpkg --print-architecture)" && \
    chmod +x /usr/local/bin/gosu && \
    rm -rf /var/lib/apt/lists/*

# ---------- Stage 3: Runtime ----------
FROM python:3.13-slim-bookworm

# Disable Python buffering + bytecode writing (container best practices)
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Install only runtime system deps needed by the gateway:
# - ca-certificates: TLS for LLM API calls
# - curl: healthcheck + lazy-install fallbacks
# - git: agent git operations
# - ffmpeg: audio processing (TTS/STT media)
# - tini: lightweight PID 1 init (zombie reaping, signal forwarding)
# - procps: process monitoring (ps for memory_monitor)
# - gcc g++: C/C++ compilers required by cmake for python-olm (mautrix[encryption] static build)
# - make cmake: build tools for python-olm (mautrix[encryption] static build)
# - libolm-dev: Matrix encryption (mautrix[encryption] native dep)
# Total: ~80MB vs ~300MB in the full image
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates curl git ffmpeg tini procps gcc g++ make cmake libolm-dev && \
    rm -rf /var/lib/apt/lists/*

# Copy uv + gosu from builder stages
COPY --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/
COPY --from=gosu_source /usr/local/bin/gosu /usr/local/bin/gosu

# Create non-root user for runtime (UID 1000 for Easypanel compatibility)
RUN useradd -u 1000 -m -d /opt/data -s /bin/bash hermes

WORKDIR /opt/hermes

# ---------- Layer-cached Python dependency install ----------
# Copy only pyproject.toml + uv.lock first for cache hit on source-only changes.
# README.md is excluded by .dockerignore but referenced by pyproject.toml's readme field;
# touch an empty placeholder so uv's build frontend doesn't fail.
COPY pyproject.toml uv.lock ./
RUN touch ./README.md

# Install ONLY the extras needed for gateway operation on a constrained VPS:
# - [all]: core agent deps (OpenAI, FastAPI, uvicorn, croniter, etc.)
# - [messaging]: Telegram, Discord, Slack adapters
# - [web]: dashboard/API server
# - [anthropic]: Anthropic provider
# - [matrix]: Matrix/Element gateway
#
# NOT installed (stripped for resource savings):
# - [voice]: faster-whisper + numpy (~200MB, CPU-heavy)
# - [edge-tts]: TTS (not needed on headless VPS)
# - [modal/daytona]: cloud sandbox backends
# - [dev]: debugpy, pytest
# - [cli]: simple-term-menu (not needed without TUI)
# - [fal/exa/firecrawl]: search/image backends (lazy-installable)
RUN uv sync --frozen --no-install-project \
    --extra all --extra messaging --extra web --extra anthropic --extra matrix

# ---------- Source code ----------
COPY . .

# Ensure entrypoint script is executable (COPY strips host permissions)
RUN chmod +x /opt/hermes/docker/easypanel-entrypoint.sh

# Install hermes-agent as editable link (fast — deps already resolved above)
RUN uv pip install --no-cache-dir --no-deps -e "." && \
    printf 'docker-easypanel\n' > /opt/hermes/.install_method

# ---------- Config overlay (seeds first-boot data) ----------
COPY docker/SOUL.md.seed /opt/data-seed/SOUL.md
COPY docker/easypanel-config.yaml /opt/data-seed/config.yaml

RUN mkdir -p /opt/data-seed && chown hermes:hermes /opt/data-seed

# ---------- Runtime config ----------
ENV HERMES_HOME=/opt/data
ENV HERMES_WRITE_SAFE_ROOT=/opt/data
ENV HERMES_DISABLE_LAZY_INSTALLS=1
ENV HERMES_LAZY_INSTALL_TARGET=/opt/data/lazy-packages
ENV PATH="/opt/hermes/.venv/bin:${PATH}"

# Create data volume directory
RUN mkdir -p /opt/data && chown hermes:hermes /opt/data

VOLUME [ "/opt/data" ]

# Expose gateway API port (default 8642, configurable via API_SERVER_PORT)
EXPOSE 8642

# Healthcheck: verify gateway API server responds
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:${API_SERVER_PORT:-8642}/health || exit 1

# tini as PID 1 → entrypoint → gateway run
ENTRYPOINT [ "tini", "--", "/opt/hermes/docker/easypanel-entrypoint.sh" ]
CMD [ "hermes", "gateway", "run" ]
