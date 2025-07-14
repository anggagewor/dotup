#!/usr/bin/env bash
set -euo pipefail

FILTER=""
OUTPUT_BASE=""
TMPFILE=$(mktemp)

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
      exit 1
      ;;
  esac
done

# OS info
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
  OS_ID="$ID"
  OS_VERSION="$VERSION_ID"
  OS_KEY="${OS_ID}-${OS_VERSION}"
else
  echo "❌ Unsupported OS"
  exit 1
fi

# Validate
if [[ -z "$FILTER" ]]; then
  echo "❌ Please provide --filter"
  exit 1
fi

# Default output dir
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_BASE="${OUTPUT_BASE:-$ROOT_DIR/configs}"

CONFIG_DIR="$OUTPUT_BASE/$OS_KEY"
MANIFEST_FILE="$OUTPUT_BASE/$OS_KEY.json"
GROUP_FILE="$CONFIG_DIR/$FILTER.json"

mkdir -p "$CONFIG_DIR"

if command -v dpkg-query &>/dev/null; then
  echo "📦 Detected dpkg/apt (Debian-based)"
  dpkg-query -W -f='${Package}\t${Version}\t${Origin}\n' > "$TMPFILE"

elif command -v pacman &>/dev/null; then
  echo "📦 Detected pacman (Arch-based)"
  pacman -Q | awk '{print $1 "\t" $2 "\trepo"}' > "$TMPFILE"

elif command -v dnf &>/dev/null; then
  echo "📦 Detected dnf (Fedora-based)"
  dnf list installed | tail -n +2 | awk '{print $1 "\t" $2 "\trepo"}' > "$TMPFILE"

elif command -v zypper &>/dev/null; then
  echo "📦 Detected zypper (openSUSE)"
  zypper packages --installed-only | awk '/^[0-9]/ {print $5 "\t" $6 "\trepo"}' > "$TMPFILE"

elif command -v apk &>/dev/null; then
  echo "📦 Detected apk (Alpine)"
  apk info -v | awk -F'-' '{print $1 "\t" $2 "\trepo"}' > "$TMPFILE"

else
  echo "❌ Unsupported or unknown package manager"
  exit 1
fi


# Filter by keyword
grep -i "$FILTER" "$TMPFILE" > "${TMPFILE}.filtered" || true

# Backup if exist
if [[ -f "$GROUP_FILE" ]]; then
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  mv "$GROUP_FILE" "$GROUP_FILE.bak-$TIMESTAMP"
  echo "🗂️  Backup created: $GROUP_FILE.bak-$TIMESTAMP"
fi

# Convert to JSON using jq
jq -Rs -s '
  split("\n") | map(select(length > 0)) |
  map(split("\t") | {
    name: .[0],
    version: .[1],
    source: (.[2] // "repo")
  })' < "${TMPFILE}.filtered" > "$GROUP_FILE"

echo "✅ Saved: $GROUP_FILE"

# Update manifest
if [[ ! -f "$MANIFEST_FILE" ]]; then
  echo "{\"id\":\"$OS_ID\",\"version\":\"$OS_VERSION\",\"created_at\":\"$(date -Iseconds)\",\"packages\":[]}" > "$MANIFEST_FILE"
fi

if ! jq -e --arg pkg "$FILTER" '.packages | index($pkg)' "$MANIFEST_FILE" >/dev/null; then
  TMP_MANIFEST=$(mktemp)
  jq --arg pkg "$FILTER" '.packages += [$pkg]' "$MANIFEST_FILE" > "$TMP_MANIFEST"
  mv "$TMP_MANIFEST" "$MANIFEST_FILE"
  echo "📌 Updated manifest: $MANIFEST_FILE"
fi

# Cleanup
rm -f "$TMPFILE" "${TMPFILE}.filtered"
