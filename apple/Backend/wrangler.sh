#!/bin/zsh
set -euo pipefail
BACKEND_DIR="${0:A:h}"
PROJECT_DIR="${BACKEND_DIR:h:h}"
NODE_BIN="$(command -v node || true)"
if [[ -z "$NODE_BIN" ]]; then
  NODE_BIN="$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node"
fi
if [[ ! -x "$NODE_BIN" ]]; then
  print -u2 'Install Node.js 22 or newer, then rerun this command.'
  exit 1
fi
export PATH="${NODE_BIN:h}:$PATH"
exec "$NODE_BIN" "$PROJECT_DIR/node_modules/wrangler/bin/wrangler.js" "$@" --config "$PROJECT_DIR/wrangler.jsonc"
