#!/bin/bash
set -e

# Ensure /data is writable
chown -R openclaw:openclaw /data 2>/dev/null || true

export HOME=/home/openclaw
export OPENCLAW_HOME="${OPENCLAW_STATE_DIR:-/data/.openclaw}"

# Create state/workspace dirs
gosu openclaw mkdir -p "$OPENCLAW_HOME" "${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"

# Write gateway config (bind loopback — we proxy via socat)
INTERNAL_PORT=18789
gosu openclaw bash -c "cat > $OPENCLAW_HOME/openclaw.json" <<EOF
{
  "gateway": {
    "bind": "lan",
    "port": $INTERNAL_PORT,
    "http": {
      "endpoints": {
        "responses": { "enabled": true }
      }
    }
  }
}
EOF

# Start OpenClaw gateway in background
echo "[osmo-wrapper] Starting OpenClaw gateway on port $INTERNAL_PORT..."
gosu openclaw openclaw gateway start &

# Wait for gateway to be ready
for i in $(seq 1 30); do
  if gosu openclaw wget -qO- "http://127.0.0.1:$INTERNAL_PORT/" >/dev/null 2>&1; then
    echo "[osmo-wrapper] Gateway is ready"
    break
  fi
  sleep 1
done

# Forward external PORT to internal gateway port
EXTERNAL_PORT="${PORT:-8080}"
echo "[osmo-wrapper] Proxying 0.0.0.0:$EXTERNAL_PORT -> 127.0.0.1:$INTERNAL_PORT"
exec socat TCP-LISTEN:$EXTERNAL_PORT,fork,reuseaddr TCP:127.0.0.1:$INTERNAL_PORT
