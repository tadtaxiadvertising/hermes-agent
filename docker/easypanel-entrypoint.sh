#!/bin/bash
# easypanel-entrypoint.sh — Lightweight entrypoint for Easypanel deployment
# Seeds data dir, then exec's the gateway via gosu privilege drop.
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"
INSTALL_DIR="/opt/hermes"
DATA_SEED="/opt/data-seed"

# --- Bootstrap as root, then drop to hermes ---
if [ "$(id -u)" = 0 ]; then
    # Fix ownership of data volume
    chown hermes:hermes "$HERMES_HOME" 2>/dev/null || true

    # Seed config on first boot (preserve existing files from volume mounts)
    if [ ! -f "$HERMES_HOME/.env" ] && [ -f "$INSTALL_DIR/.env.example" ]; then
        cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
        chown hermes:hermes "$HERMES_HOME/.env"
        chmod 600 "$HERMES_HOME/.env"
    fi
    if [ ! -f "$HERMES_HOME/config.yaml" ]; then
        # Seed from overlay first, then fallback to Easypanel-optimized config
        if [ -f "$DATA_SEED/config.yaml" ]; then
            cp "$DATA_SEED/config.yaml" "$HERMES_HOME/config.yaml"
        elif [ -f "$INSTALL_DIR/docker/easypanel-config.yaml" ]; then
            cp "$INSTALL_DIR/docker/easypanel-config.yaml" "$HERMES_HOME/config.yaml"
        elif [ -f "$INSTALL_DIR/cli-config.yaml.example" ]; then
            cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
        fi
        chown hermes:hermes "$HERMES_HOME/config.yaml" 2>/dev/null || true
        chmod 640 "$HERMES_HOME/config.yaml" 2>/dev/null || true
    fi
    if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
        # Seed from overlay first, then fallback to inline default
        if [ -f "$DATA_SEED/SOUL.md" ]; then
            cp "$DATA_SEED/SOUL.md" "$HERMES_HOME/SOUL.md"
        else
            printf 'You are Hermes Agent, an intelligent AI assistant. You are helpful, knowledgeable, and direct.\n' > "$HERMES_HOME/SOUL.md"
        fi
        chown hermes:hermes "$HERMES_HOME/SOUL.md"
    fi

    # Create runtime subdirectories owned by hermes
    mkdir -p \
        "$HERMES_HOME/cron" \
        "$HERMES_HOME/sessions" \
        "$HERMES_HOME/logs" \
        "$HERMES_HOME/hooks" \
        "$HERMES_HOME/memories" \
        "$HERMES_HOME/skills" \
        "$HERMES_HOME/lazy-packages" \
        "$HERMES_HOME/platforms/pairing"
    chown -R hermes:hermes \
        "$HERMES_HOME/cron" \
        "$HERMES_HOME/sessions" \
        "$HERMES_HOME/logs" \
        "$HERMES_HOME/hooks" \
        "$HERMES_HOME/memories" \
        "$HERMES_HOME/skills" \
        "$HERMES_HOME/lazy-packages" \
        "$HERMES_HOME/platforms/pairing" 2>/dev/null || true

    # Drop to hermes user via gosu (lightweight su-exec alternative)
    exec gosu hermes "$@"
else
    exec "$@"
fi
