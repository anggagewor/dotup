#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
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
RESERVED=("about")

# =======================
# 🎨 ABOUT + DEFAULT BEHAVIOR
# =======================
show_about() {
  CONFIG_PATH_VIEW="${DOTUP_HOME:-$HOME/.dotup}"

  echo "╭────────────────────────────────────────────────────────────────────────────────╮"
  echo "│ # Dotup — Modular System Setup Framework                                       │"
  echo "├────────────────────────────────────────────────────────────────────────────────┤"
  echo "│ 📂 Config path : $CONFIG_PATH_VIEW"
  echo "│ 📦 Version     : 0.1.0"
  echo "│ 🐚 Runtime     : Bash, JSON, and pure madness 😎"
  echo "╰────────────────────────────────────────────────────────────────────────────────╯"
}

list_actions() {
  echo
  echo "📂 Available actions:"
  for path in $ACTIONS_PATHS; do
    path=$(eval echo "$path")
    [[ -d "$path" ]] || continue

    while IFS= read -r dir; do
      action_name="$(basename "$dir")"
      meta_file="$dir/action.json"
      [[ -f "$meta_file" ]] || continue

      if [[ " ${RESERVED[*]} " =~ " $action_name " && "$path" != "$DEFAULT_ACTIONS_PATH" ]]; then
        continue
      fi

      echo " - $action_name (from ${path/#$HOME/~})"
    done < <(find "$path" -maxdepth 1 -mindepth 1 -type d)
  done

  echo
  echo "💡 Usage: ./dotup.sh <action> [args...]"
  echo "   Example: ./dotup.sh backup-style --all"
  echo
}

if [[ -z "$ACTION" || "$ACTION" == "about" ]]; then
  show_about
  list_actions
  exit 0
fi

# =======================
# 🔍 Find matching action
# =======================
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

# =======================
# 🚀 Run the action
# =======================
RUNTIME=$(jq -r '.runtime' "$FOUND_ACTION/action.json")
ENTRY=$(jq -r '.entry' "$FOUND_ACTION/action.json")
ENTRY_PATH="$FOUND_ACTION/$ENTRY"

[[ -x "$ENTRY_PATH" ]] || chmod +x "$ENTRY_PATH"

RUNTIME_CMD=$(echo "$RUNTIMES" | jq -r --arg key "$RUNTIME" '.[$key] // empty')
[[ -z "$RUNTIME_CMD" ]] && {
  echo "❌ Unsupported runtime: $RUNTIME"
  exit 2
}

RUNTIME_CMD="${RUNTIME_CMD//\{entry\}/\"$ENTRY_PATH\"}"
ARGS_ESCAPED=$(printf '"%s" ' "$@")
RUNTIME_CMD="${RUNTIME_CMD//\{args\}/$ARGS_ESCAPED}"

eval exec $RUNTIME_CMD
