#!/usr/bin/env bash
set -euo pipefail

FILTER=""
OUTPUT_BASE="" # This will now default to $ROOT_DIR/configs
TMPFILE=$(mktemp)

# --- NEW: Get OS_KEY from environment (set by dotup.sh) ---
# If not set, try to detect (fallback for direct execution, though not recommended)
OS_KEY="${OS_KEY:-}"
if [[ -z "$OS_KEY" ]]; then
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
        OS_KEY="${OS_ID}-${OS_VERSION}"
    else
        echo "❌ Error: OS information not available. Run via dotup.sh or set OS_KEY env."
        exit 1
    fi
fi

# --- NEW: Manifest and Log paths from environment (set by dotup.sh) ---
DOTUP_OS_MANIFEST="${DOTUP_OS_MANIFEST:-}" # Main manifest file
DOTUP_CURRENT_LOG_FILE="${DOTUP_CURRENT_LOG_FILE:-}" # Daily log file

# Fallback for direct script execution, though `dotup.sh` should set it.
if [[ -z "$DOTUP_OS_MANIFEST" ]]; then
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    MANIFEST_FILE_FALLBACK="$ROOT_DIR/configs/$OS_KEY.json"
    echo "⚠️ Warning: DOTUP_OS_MANIFEST not set. Falling back to: $MANIFEST_FILE_FALLBACK"
    DOTUP_OS_MANIFEST="$MANIFEST_FILE_FALLBACK"
fi

if [[ -z "$DOTUP_CURRENT_LOG_FILE" ]]; then
    DOTUP_LOG_DIR_FALLBACK="$HOME/.config/dotup/log"
    CURRENT_DATE=$(date +%Y%m%d)
    DOTUP_CURRENT_LOG_FILE_FALLBACK="$DOTUP_LOG_DIR_FALLBACK/$CURRENT_DATE.jsonl"
    echo "⚠️ Warning: DOTUP_CURRENT_LOG_FILE not set. Falling back to: $DOTUP_CURRENT_LOG_FILE_FALLBACK"
    mkdir -p "$DOTUP_LOG_DIR_FALLBACK"
    DOTUP_CURRENT_LOG_FILE="$DOTUP_CURRENT_LOG_FILE_FALLBACK"
fi

# --- NEW: Function to log events from action ---
# Usage: log_event_action <level> <status> <message> [details_json_string]
log_event_action() {
    local level="$1"
    local status="$2"
    local message="$3"
    local details_json_input="${4:-{}}" # Input details. Can be empty string or JSON string.

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    local log_entry_base=$(jq -n \
        --arg ts "$timestamp" \
        --arg lvl "$level" \
        --arg act "scan" \
        --arg stat "$status" \
        --arg oskey "$OS_KEY" \
        --arg msg "$message" \
        '{timestamp: $ts, level: $lvl, action: $act, status: $stat, os_key: $oskey, message: $msg}')

    local log_entry
    if [[ -n "$details_json_input" && "$details_json_input" != "{}" ]]; then
        if echo "$details_json_input" | jq -e . &>/dev/null; then
            log_entry=$(echo "$log_entry_base" | jq --argjson det "$details_json_input" '. + {details: $det}')
        else
            log_entry=$(echo "$log_entry_base" | jq --arg det_str "$details_json_input" '. + {details: $det_str}')
        fi
    else
        log_entry="$log_entry_base"
    fi

    echo "$log_entry" >> "$DOTUP_CURRENT_LOG_FILE"
}

# Initial log for action start
log_event_action "INFO" "start" "Scan action started." "{\"filter\": \"$FILTER\", \"output_base\": \"$OUTPUT_BASE\"}"


while [[ $# -gt 0 ]]; do
    case "$1" in
        --filter)
            FILTER="$2"
            shift 2
            ;;
        --output-path)
            OUTPUT_BASE="$2"
            shift 2
            ;;
        *)
            echo "❌ Unknown option: $1"
            log_event_action "ERROR" "failure" "Unknown option provided." "{\"option\": \"$1\"}"
            exit 1
            ;;
    esac
done

# Validate filter
if [[ -z "$FILTER" ]]; then
    echo "❌ Please provide --filter"
    log_event_action "ERROR" "failure" "Scan action failed: --filter not provided."
    exit 1
fi

# --- MODIFIED: Ensure CONFIG_DIR points to the OS-specific sub-directory ---
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" # Re-define ROOT_DIR in case of direct execution
CONFIG_DIR="$ROOT_DIR/configs/$OS_KEY" # This makes sure it's e.g., .../dotup/configs/ubuntu-24.04/
# END MODIFIED

GROUP_FILE="$CONFIG_DIR/$FILTER.json"

mkdir -p "$CONFIG_DIR"

# Package manager detection and package listing
PKG_MGR_CMD=""
PKG_MGR_NAME=""
if command -v dpkg-query &>/dev/null; then
    echo "📦 Detected dpkg/apt (Debian-based)"
    PKG_MGR_CMD="dpkg-query -W -f='\${Package}\t\${Version}\t\${Origin}\n'"
    PKG_MGR_NAME="dpkg"
elif command -v pacman &>/dev/null; then
    echo "📦 Detected pacman (Arch-based)"
    PKG_MGR_CMD="pacman -Q | awk '{print \$1 \"\\t\" \$2 \"\\trepo\"}'"
    PKG_MGR_NAME="pacman"
elif command -v dnf &>/dev/null; then
    echo "📦 Detected dnf (Fedora-based)"
    PKG_MGR_CMD="dnf list installed | tail -n +2 | awk '{print \$1 \"\\t\" \$2 \"\\trepo\"}'"
    PKG_MGR_NAME="dnf"
elif command -v zypper &>/dev/null; then
    echo "📦 Detected zypper (openSUSE)"
    PKG_MGR_CMD="zypper packages --installed-only | awk '/^[0-9]/ {print \$5 \"\\t\" \$6 \"\\trepo\"}'"
    PKG_MGR_NAME="zypper"
elif command -v apk &>/dev/null; then
    echo "📦 Detected apk (Alpine)"
    PKG_MGR_CMD="apk info -v | awk -F'-' '{print \$1 \"\\t\" \$2 \"\\trepo\"}'"
    PKG_MGR_NAME="apk"
else
    echo "❌ Unsupported or unknown package manager"
    log_event_action "ERROR" "failure" "Scan action failed: Unsupported package manager."
    exit 1
fi

log_event_action "INFO" "progress" "Detected package manager: $PKG_MGR_NAME."

eval "$PKG_MGR_CMD" > "$TMPFILE"
log_event_action "INFO" "progress" "Package list retrieved into temporary file."


# Filter by keyword
grep_output=$(grep -i "$FILTER" "$TMPFILE")
if [[ -z "$grep_output" ]]; then
    echo "⚠️ No packages found matching filter '$FILTER'."
    log_event_action "WARNING" "no_match" "No packages found matching filter." "{\"filter\": \"$FILTER\"}"
    # Create an empty filtered file so jq doesn't fail
    echo "" > "${TMPFILE}.filtered"
else
    echo "$grep_output" > "${TMPFILE}.filtered"
fi


# Backup if exist
if [[ -f "$GROUP_FILE" ]]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    mv "$GROUP_FILE" "$GROUP_FILE.bak-$TIMESTAMP"
    echo "🗂️  Backup created: $GROUP_FILE.bak-$TIMESTAMP"
    log_event_action "INFO" "progress" "Existing group file backed up." "{\"old_file\": \"$GROUP_FILE\", \"backup_file\": \"$GROUP_FILE.bak-$TIMESTAMP\"}"
fi

# Convert to JSON using jq
# --- MODIFIED: Default 'source' to "unknown" if empty ---
jq -Rs -s '
    split("\n") | map(select(length > 0)) |
    map(split("\t") | {
        name: .[0],
        version: .[1],
        source: (if .[2] == "" then "unknown" else (.[2] // "unknown") end)
    })' < "${TMPFILE}.filtered" > "$GROUP_FILE"
# END MODIFIED

if [[ $? -eq 0 ]]; then
    echo "✅ Saved: $GROUP_FILE"
    log_event_action "INFO" "success" "Package group file saved." "{\"file\": \"$GROUP_FILE\", \"filter\": \"$FILTER\"}"
else
    echo "❌ Failed to save group file: $GROUP_FILE"
    log_event_action "ERROR" "failure" "Failed to save package group file." "{\"file\": \"$GROUP_FILE\", \"filter\": \"$FILTER\"}"
    # Cleanup and exit on failure to create GROUP_FILE
    rm -f "$TMPFILE" "${TMPFILE}.filtered"
    exit 1
fi


# Update manifest
# The manifest is guaranteed to exist and be valid by dotup.sh
# We only need to update the 'packages' array in the manifest
if ! jq -e --arg pkg "$FILTER" '.packages | index($pkg)' "$DOTUP_OS_MANIFEST" >/dev/null; then
    TMP_MANIFEST=$(mktemp)
    jq --arg pkg "$FILTER" '.packages += [$pkg]' "$DOTUP_OS_MANIFEST" > "$TMP_MANIFEST"
    mv "$TMP_MANIFEST" "$DOTUP_OS_MANIFEST"
    echo "📌 Updated manifest: $DOTUP_OS_MANIFEST"
    log_event_action "INFO" "success" "OS manifest updated with new package filter." "{\"manifest_file\": \"$DOTUP_OS_MANIFEST\", \"filter_added\": \"$FILTER\"}"
else
    echo "ℹ️ Filter '$FILTER' already in manifest. No update needed."
    log_event_action "INFO" "progress" "Filter already exists in manifest." "{\"manifest_file\": \"$DOTUP_OS_MANIFEST\", \"filter\": \"$FILTER\"}"
fi


# Cleanup
rm -f "$TMPFILE" "${TMPFILE}.filtered"
log_event_action "INFO" "success" "Scan action completed." "{\"filter\": \"$FILTER\"}"
