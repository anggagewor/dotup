#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-about}"
shift || true

# Path resolver
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG_PATH="$HOME/.config/dotup/config.json"

# Default config generator
generate_default_config() {
  mkdir -p "$(dirname "$CONFIG_PATH")"
  cat > "$CONFIG_PATH" <<EOF
{
  "actions_paths": [
    "$HOME/.dotup/actions",
    "$ROOT_DIR/actions"
  ],
  "default_configs_path": "$ROOT_DIR/configs",
  "runtimes": {
    "bash": "bash {entry} {args}",
    "python": "python3 {entry} {args}",
    "exec": "{entry} {args}"
  }
}
EOF
  echo "⚙️  Generated default config at $CONFIG_PATH"
}

# Generate config if missing
[[ -f "$CONFIG_PATH" ]] || generate_default_config

# Load config
ACTIONS_PATHS=$(jq -r '.actions_paths[]' "$CONFIG_PATH")
DEFAULT_ACTIONS_PATH=$(jq -r '.actions_paths[-1]' "$CONFIG_PATH")
RUNTIMES=$(jq -r '.runtimes' "$CONFIG_PATH")

# Reserved actions that cannot be overridden
RESERVED=("about")

# Find action
FOUND_ACTION=""
for path in $ACTIONS_PATHS; do
  path=$(eval echo "$path")  # expand ~
  CANDIDATE="$path/$ACTION"
  META="$CANDIDATE/action.json"

  if [[ -f "$META" ]]; then
    if [[ " ${RESERVED[*]} " =~ " $ACTION " && "$path" != "$DEFAULT_ACTIONS_PATH" ]]; then
      continue
    fi
    FOUND_ACTION="$CANDIDATE"
    break
  fi
done

if [[ -z "$FOUND_ACTION" ]]; then
  echo "❌ Action '$ACTION' not found in any path"
  exit 1
fi

# Load metadata
RUNTIME=$(jq -r '.runtime' "$FOUND_ACTION/action.json")
ENTRY=$(jq -r '.entry' "$FOUND_ACTION/action.json")
ENTRY_PATH="$FOUND_ACTION/$ENTRY"

# Make sure executable
[[ -x "$ENTRY_PATH" ]] || chmod +x "$ENTRY_PATH"

# Eksekusi runtime dari config
RUNTIME_CMD=$(echo "$RUNTIMES" | jq -r --arg key "$RUNTIME" '.[$key] // empty')

if [[ -z "$RUNTIME_CMD" ]]; then
  echo "❌ Unsupported runtime: $RUNTIME"
  exit 2
fi

# Expand vars
RUNTIME_CMD="${RUNTIME_CMD//\{entry\}/\"$ENTRY_PATH\"}"

# Build escaped args
ARGS_ESCAPED=$(printf '"%s" ' "$@")
RUNTIME_CMD="${RUNTIME_CMD//\{args\}/$ARGS_ESCAPED}"

# Eksekusi
eval exec $RUNTIME_CMD
