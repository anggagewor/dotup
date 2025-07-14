#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OS_ID="$(. /etc/os-release && echo "${ID}-${VERSION_ID}")"
TARGET_DIR="$ROOT_DIR/configs/$OS_ID"
DOTFILES_DIR="$ROOT_DIR/dotfiles/config"
BACKUP_META_DIR="$TARGET_DIR/backup_metadata"

mkdir -p "$TARGET_DIR"/{themes,fonts,icons,config}
mkdir -p "$DOTFILES_DIR"
mkdir -p "$BACKUP_META_DIR"

echo "📦 Starting backup for style configuration"
echo "🖥️  Detected OS: $OS_ID"

# ================================
# 🧰 Helpers
# ================================
relpath() {
  local full_path
  full_path="$(realpath -m "$1")"
  local home_path
  home_path="$(realpath -m "$HOME")"

  if [[ "$full_path" == "$home_path"* ]]; then
    echo "~${full_path#$home_path}"
  else
    echo "$full_path"
  fi
}

backup_metadata() {
  local meta_path="$1"
  local name
  name="$(basename "$meta_path")"

  if [[ -f "$meta_path" ]]; then
    echo "♻️  Moving existing metadata: $name"
    mv "$meta_path" "$BACKUP_META_DIR/${name%.json}-$(date +%s).json"
  fi
}

load_meta_pattern() {
  local category="$1"
  local item_name="$2"
  local meta_dir="$TARGET_DIR/$category/_meta"

  [[ -d "$meta_dir" ]] || return 0

  for file in "$meta_dir"/*.json; do
    [[ -f "$file" ]] || continue

    # Jika langsung meta (tanpa name_pattern), cocokin dari nama file
    if ! jq -e 'has("name_pattern")' "$file" >/dev/null 2>&1; then
      filename="$(basename "$file" .json)"
      if [[ "$item_name" == $filename* ]]; then
        cat "$file"
        return
      fi
      continue
    fi

    # Jika ada name_pattern, cocokkan pakai pattern-nya
    pattern=$(jq -r '.name_pattern' "$file")
    if [[ "$item_name" == $pattern ]]; then
      jq '.meta' "$file"
      return
    fi
  done

  echo '{}'
}

write_meta_json() {
  local path="$1"
  local name="$2"
  local source="$3"
  local target_path="$4"
  local category="$5"

  local old_meta="{}"
  [[ -f "$path" ]] && old_meta="$(< "$path")"

  local meta_part
  meta_part=$(echo "$old_meta" | jq '{meta: (.meta // {})}')

  # Kalau meta masih kosong, cari dari pattern
  if jq -e '.meta == {}' <<<"$meta_part" >/dev/null 2>&1; then
    pattern_meta="$(load_meta_pattern "$category" "$name")"
    meta_part=$(jq -n --argjson m "$pattern_meta" '{meta: $m}')
  fi

  local new_meta
  new_meta=$(jq -n \
    --arg name "$name" \
    --arg source "$source" \
    --arg path "$target_path" \
    '{name: $name, source: $source, path: $path}')

  echo "$new_meta" | jq -s '.[0] + .[1]' - <<<"$meta_part" > "$path"
}


# ================================
# 🔹 Backup ~/.config apps
# ================================
CONFIG_ITEMS=("kitty" "hypr" "waybar" "fish" "code" "starship")

for item in "${CONFIG_ITEMS[@]}"; do
  SRC="$HOME/.config/$item"
  DEST="$DOTFILES_DIR/$item"
  META="$TARGET_DIR/config/$item.json"

  if [[ -d "$SRC" ]]; then
    echo "📁 Backing up config: $item"
    mkdir -p "$(dirname "$DEST")"
    backup_metadata "$META"

    rsync -a --delete "$SRC/" "$DEST/"
    write_meta_json "$META" "$item" "local" "$(relpath "$DEST")" "config"
  fi
done

# ================================
# 🎨 Backup GTK Themes
# ================================
THEME_DIRS=("$HOME/.themes" "$HOME/.local/share/themes")

for theme_dir in "${THEME_DIRS[@]}"; do
  [[ -d "$theme_dir" ]] || continue
  for theme in "$theme_dir/"*; do
    [[ -d "$theme" ]] || continue
    name="$(basename "$theme")"
    meta="$TARGET_DIR/themes/$name.json"

    echo "🎨 Backing up theme: $name (from $theme_dir)"
    backup_metadata "$meta"
    write_meta_json "$meta" "$name" "manual" "$(relpath "$theme_dir/$name")" "themes"
  done
done

# ================================
# 🖼️ Backup Icon Themes
# ================================
ICON_DIRS=("$HOME/.icons" "$HOME/.local/share/icons")

for icon_dir in "${ICON_DIRS[@]}"; do
  [[ -d "$icon_dir" ]] || continue
  for icon in "$icon_dir/"*; do
    [[ -d "$icon" ]] || continue
    name="$(basename "$icon")"
    meta="$TARGET_DIR/icons/$name.json"

    echo "🖼️  Backing up icon: $name (from $icon_dir)"
    backup_metadata "$meta"
    write_meta_json "$meta" "$name" "manual" "$(relpath "$icon_dir/$name")" "icons"
  done
done

# ================================
# 🔤 Backup Fonts
# ================================
FONT_DIRS=("$HOME/.local/share/fonts" "$HOME/.fonts")

for font_dir in "${FONT_DIRS[@]}"; do
  [[ -d "$font_dir" ]] || continue
  for font in "$font_dir/"*; do
    [[ -e "$font" ]] || continue
    name="$(basename "$font")"
    meta="$TARGET_DIR/fonts/$name.json"

    echo "🔤 Backing up font: $name (from $font_dir)"
    backup_metadata "$meta"
    write_meta_json "$meta" "$name" "manual" "$(relpath "$font_dir/$name")" "fonts"
  done
done

echo "✅ Backup style selesai di: $TARGET_DIR"
