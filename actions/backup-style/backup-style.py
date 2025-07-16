#!/usr/bin/env python3
import os
import json
import shutil
from pathlib import Path
from datetime import datetime

HOME = Path.home()
ROOT_DIR = Path(__file__).resolve().parents[2]

def detect_os_id():
    os_release = Path("/etc/os-release")
    if not os_release.exists():
        return "unknown-unknown"

    values = {}
    with os_release.open() as f:
        for line in f:
            if "=" in line:
                key, val = line.strip().split("=", 1)
                values[key] = val.strip('"')

    return f"{values.get('ID', 'unknown')}-{values.get('VERSION_ID', 'unknown')}"

OS_ID = detect_os_id()
TARGET_DIR = ROOT_DIR / "configs" / OS_ID
DOTFILES_DIR = ROOT_DIR / "dotfiles" / "config"
BACKUP_META_DIR = TARGET_DIR / "backup_metadata"

CONFIG_ITEMS = ["fastfetch","menus","gtk-3.0","gtk-4.0","JetBrains"]
THEME_DIRS = [HOME / ".themes", HOME / ".local/share/themes"]
ICON_DIRS = [HOME / ".icons", HOME / ".local/share/icons"]
FONT_DIRS = [HOME / ".local/share/fonts", HOME / ".fonts"]

# ==========================
# 🔧 Helper Functions
# ==========================
def relpath(path: Path) -> str:
    try:
        return "~" + str(path.resolve()).removeprefix(str(HOME.resolve()))
    except Exception:
        return str(path.resolve())

def ensure_dirs():
    for d in [TARGET_DIR / p for p in ["themes", "fonts", "icons", "config"]] + [DOTFILES_DIR, BACKUP_META_DIR]:
        d.mkdir(parents=True, exist_ok=True)

def backup_metadata(meta_path: Path):
    if meta_path.exists():
        timestamp = datetime.now().strftime("%Y%m%d%H%M%S")
        backup_path = BACKUP_META_DIR / f"{meta_path.stem}-{timestamp}.json"
        shutil.move(str(meta_path), backup_path)

def load_meta_pattern(category: str, name: str) -> dict:
    meta_dir = TARGET_DIR / category / "_meta"
    if not meta_dir.exists():
        return {}

    for f in meta_dir.glob("*.json"):
        try:
            with f.open() as file:
                data = json.load(file)

            if "name_pattern" not in data:
                if f.stem and name.startswith(f.stem):
                    return data.get("meta", {})
                continue

            pattern = data["name_pattern"]
            if name.startswith(pattern.replace("*", "")):
                return data.get("meta", {})
        except Exception:
            continue
    return {}

def write_meta_json(path: Path, name: str, source: str, target_path: str, category: str):
    meta = {}
    if path.exists():
        try:
            with path.open() as f:
                meta = json.load(f)
        except Exception:
            pass

    if "meta" not in meta or not meta["meta"]:
        pattern_meta = load_meta_pattern(category, name)
        meta["meta"] = pattern_meta

    meta.update({
        "name": name,
        "source": source,
        "path": target_path,
    })

    with path.open("w") as f:
        json.dump(meta, f, indent=2)

# ==========================
# 🚀 Main Backup Logic
# ==========================
def backup_config_items():
    for item in CONFIG_ITEMS:
        src = HOME / ".config" / item
        dst = DOTFILES_DIR / item
        meta = TARGET_DIR / "config" / f"{item}.json"

        if src.exists():
            print(f"📁 Backing up config: {item}")
            dst.parent.mkdir(parents=True, exist_ok=True)
            if dst.exists():
                shutil.rmtree(dst)
            shutil.copytree(src, dst)
            backup_metadata(meta)
            write_meta_json(meta, item, "local", relpath(dst), "config")

def backup_dir_items(dirs, category):
    for d in dirs:
        if not d.exists():
            continue
        for item in d.iterdir():
            if not item.is_dir() and category != "fonts":
                continue
            name = item.name
            meta = TARGET_DIR / category / f"{name}.json"
            print(f"📦 Backing up {category}: {name} (from {d})")
            backup_metadata(meta)
            write_meta_json(meta, name, "manual", relpath(item), category)

def main():
    print(f"📦 Starting backup for style configuration")
    print(f"🖥️  Detected OS: {OS_ID}")
    ensure_dirs()
    backup_config_items()
    backup_dir_items(THEME_DIRS, "themes")
    backup_dir_items(ICON_DIRS, "icons")
    # backup_dir_items(FONT_DIRS, "fonts")
    print(f"✅ Backup style selesai di: {TARGET_DIR}")

if __name__ == "__main__":
    main()
