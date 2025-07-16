#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
shift || true

# Path resolver
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_PATH="$HOME/.config/dotup/config.json"

# Function to detect OS information
detect_os_info() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "${ID}-${VERSION_ID}"
    else
        echo "unknown-unknown"
    fi
}

# Get current OS ID and define manifest path
OS_KEY=$(detect_os_info)
MANIFEST_DIR="$ROOT_DIR/configs"
MANIFEST_FILE="$MANIFEST_DIR/$OS_KEY.json"

# --- NEW: Logging setup ---
DOTUP_LOG_DIR="$HOME/.config/dotup/log"
CURRENT_DATE=$(date +%Y%m%d)
DOTUP_CURRENT_LOG_FILE="$DOTUP_LOG_DIR/$CURRENT_DATE.jsonl"

# Export log file path for actions to use
export DOTUP_CURRENT_LOG_FILE

# Function to log events to the daily log file
# Usage: log_event <level> <status> <message> [details_json_string]
log_event() {
    local level="$1"
    local status="$2"
    local message="$3"
    local details_json_input="${4:-{}}" # Input details. Can be empty string or JSON string.

    mkdir -p "$DOTUP_LOG_DIR"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z") # UTC timestamp with milliseconds

    # Construct the base log entry
    local log_entry_base=$(jq -n \
        --arg ts "$timestamp" \
        --arg lvl "$level" \
        --arg act "$ACTION" \
        --arg stat "$status" \
        --arg oskey "$OS_KEY" \
        --arg msg "$message" \
        '{timestamp: $ts, level: $lvl, action: $act, status: $stat, os_key: $oskey, message: $msg}')

    # --- MODIFIED: Handle details_json_input properly ---
    local log_entry
    if [[ -n "$details_json_input" && "$details_json_input" != "{}" ]]; then
        # Try to parse as JSON. If it fails, treat as a string.
        if echo "$details_json_input" | jq -e . &>/dev/null; then
            # It's valid JSON, merge it directly
            log_entry=$(echo "$log_entry_base" | jq --argjson det "$details_json_input" '. + {details: $det}')
        else
            # It's not valid JSON, treat it as a plain string value for details field
            log_entry=$(echo "$log_entry_base" | jq --arg det_str "$details_json_input" '. + {details: $det_str}')
        fi
    else
        log_entry="$log_entry_base"
    fi
    # --- END MODIFIED ---

    echo "$log_entry" >> "$DOTUP_CURRENT_LOG_FILE"
}

# Function to generate default OS manifest
generate_default_manifest() {
    mkdir -p "$MANIFEST_DIR"
    cat > "$MANIFEST_FILE" <<EOF
{
  "id": "$(echo "$OS_KEY" | cut -d'-' -f1)",
  "version": "$(echo "$OS_KEY" | cut -d'-' -f2)",
  "created_at": "$(date -Iseconds)",
  "actions_log": [],
  "packages": [],
  "config_items": [],
  "themes": [],
  "icons": [],
  "fonts": []
}
EOF
    echo "⚙️  Generated default OS manifest at $MANIFEST_FILE"
    # Pass a valid JSON string for details
    log_event "INFO" "success" "Default OS manifest generated." "{\"path\": \"$MANIFEST_FILE\"}"
}

# Default global config generator
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
    echo "⚙️  Generated default global config at $CONFIG_PATH"
    # Pass a valid JSON string for details
    log_event "INFO" "success" "Default global config generated." "{\"path\": \"$CONFIG_PATH\"}"
}

# Generate global config if missing
[[ -f "$CONFIG_PATH" ]] || generate_default_config

# Load global config
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
    log_event "INFO" "success" "About/List actions displayed."
    exit 0
fi

# Ensure OS manifest exists and is valid
if [[ ! -f "$MANIFEST_FILE" ]]; then
    generate_default_manifest
elif ! jq -e . "$MANIFEST_FILE" &>/dev/null; then
    echo "❌ Error: OS manifest file '$MANIFEST_FILE' is corrupted or invalid JSON."
    echo "Please check the file manually or re-run an action like 'scan' to regenerate (be cautious with data)."
    # Pass a valid JSON string for details
    log_event "ERROR" "failure" "OS manifest file corrupted." "{\"path\": \"$MANIFEST_FILE\"}"
    exit 1
fi
echo "✅ OS manifest loaded: $MANIFEST_FILE"
# Pass a valid JSON string for details
log_event "INFO" "success" "OS manifest loaded." "{\"path\": \"$MANIFEST_FILE\"}"


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
    # Pass a valid JSON string for details
    log_event "ERROR" "failure" "Action not found." "{\"action_name\": \"$ACTION\", \"searched_paths\": \"$(echo "$ACTIONS_PATHS" | tr '\n' ',' | sed 's/,*$//')\"}"
    exit 1
fi

# Display the path of the found action
echo "▶️ Running action: '$ACTION' from '$FOUND_ACTION'"
# Pass a valid JSON string for details
log_event "INFO" "success" "Action found and ready to run." "{\"action_name\": \"$ACTION\", \"action_path\": \"$FOUND_ACTION\"}"

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
    # Pass a valid JSON string for details
    log_event "ERROR" "failure" "Unsupported runtime for action." "{\"action_name\": \"$ACTION\", \"runtime\": \"$RUNTIME\"}"
    exit 2
}

# Export MANIFEST_FILE to environment for actions to use
export DOTUP_OS_MANIFEST="$MANIFEST_FILE"
echo "ℹ️  DOTUP_OS_MANIFEST set to: $DOTUP_OS_MANIFEST"

RUNTIME_CMD="${RUNTIME_CMD//\{entry\}/\"$ENTRY_PATH\"}"
ARGS_ESCAPED=$(printf '"%s" ' "$@")
RUNTIME_CMD="${RUNTIME_CMD//\{args\}/$ARGS_ESCAPED}"

# Log before executing the action. The action itself should log its completion/status.
# Pass a valid JSON string for details
log_event "INFO" "success" "Executing action." "{\"action_name\": \"$ACTION\", \"entry_path\": \"$ENTRY_PATH\", \"runtime_command_template\": \"$RUNTIME_CMD\"}"

eval exec $RUNTIME_CMD
