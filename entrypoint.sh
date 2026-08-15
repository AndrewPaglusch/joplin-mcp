#!/usr/bin/env bash
set -euo pipefail

PROFILE="${JOPLIN_PROFILE:-/profile}"
SYNC_INTERVAL="${JOPLIN_SYNC_INTERVAL:-300}"
SERVER_URL="${JOPLIN_SERVER_URL:-http://joplin:22300}"
API_PORT=41184

AI_TOOLS="semantic_search_notes read_image"
TOOL_METADATA=/joplin/packages/lib/models/settings/builtInMetadata.js

JOPLIN_BIN="/joplin/packages/app-cli/build/main.js"
joplin() { node "$JOPLIN_BIN" --profile "$PROFILE" "$@"; }

mkdir -p "$PROFILE"

joplin config keychain.supported 0 || true
joplin config sync.target 9
joplin config sync.9.path "$SERVER_URL"
joplin config sync.9.username "${JOPLIN_SERVER_EMAIL:?JOPLIN_SERVER_EMAIL is required}"
joplin config sync.9.password "${JOPLIN_SERVER_PASSWORD:?JOPLIN_SERVER_PASSWORD is required}"
joplin config api.port "$API_PORT"
joplin config mcp.enabled true

# Enable all tools except the AI-dependent ones
for key in $(grep -oE 'ai\.tool\.[a-z_]+\.enabled' "$TOOL_METADATA" | sort -u); do
    tool="${key#ai.tool.}"; tool="${tool%.enabled}"
    case " $AI_TOOLS " in *" $tool "*) continue ;; esac
    joplin config "$key" true
done

# When set, the master password lets the CLI decrypt synced notes for MCP
if [ -n "${JOPLIN_E2EE_PASSWORD:-}" ]; then
    joplin config encryption.masterPassword "$JOPLIN_E2EE_PASSWORD"
fi

joplin sync || echo "[entrypoint] initial sync failed; will retry in background"

# Decrypt before the server/sync-worker start, while nothing else holds the DB.
if [ -n "${JOPLIN_E2EE_PASSWORD:-}" ]; then
    joplin e2ee decrypt --password "$JOPLIN_E2EE_PASSWORD" --retry-failed-items \
        || echo "[entrypoint] decrypt pass failed"
fi

echo "Starting sync worker. Sync interval: ${SYNC_INTERVAL}..."
(
    while true; do
        sleep "$SYNC_INTERVAL"
        joplin sync || echo "[sync] failed; retrying next interval"
    done
) &
SYNC_LOOP_PID=$!

echo "Starting Joplin server..."
joplin server start &
SERVER_PID=$!

echo "Waiting for Joplin server to become healthy..."
for _ in $(seq 1 60); do
    curl -fsS "http://127.0.0.1:${API_PORT}/ping" >/dev/null 2>&1 && break
    sleep 1
done

echo "Reading REST API token..."
TOKEN="$(jq -r '."api.token" // empty' "$PROFILE/settings.json" 2>/dev/null || true)"
UPSTREAM_QUERY=""
[ -n "$TOKEN" ] && UPSTREAM_QUERY="?token=${TOKEN}"

export UPSTREAM_QUERY
envsubst '${UPSTREAM_QUERY}' \
    < /etc/nginx/templates/joplin-mcp.conf.template \
    > /etc/nginx/conf.d/joplin-mcp.conf

echo "Starting nginx..."
nginx -g 'daemon off;' &
NGINX_PID=$!

wait -n "$SERVER_PID" "$NGINX_PID"
EXIT_CODE=$?
kill "$SYNC_LOOP_PID" "$SERVER_PID" "$NGINX_PID" 2>/dev/null || true
exit "$EXIT_CODE"
