# ⚙️ Dotup

> Personal modular setup system for Linux hackers 😎
> Mirip `dotfiles`, tapi dengan semangat DSL dan automation bawaan.

---

## 🚀 Apa Itu Dotup?

**Dotup** adalah framework portabel untuk mengelola konfigurasi sistem, aplikasi, dan preferensi pribadi lo di Linux.
Mirip `dotfiles`, tapi lebih modular dan bisa jalanin *action* script seperti `scan`, `install`, dll.

Lo bisa:
- Simpan konfigurasi setup per distro
- Jalankan skrip modular per task
- Override action default dengan versi lo sendiri
- Support runtime multi-bahasa: bash, python, bahkan binary
- Enkripsi file rahasia (planned)
- Cocok buat backup & restore lingkungan kerja lo

---

## 🧱 Struktur Proyek
```
dotup/
├── bin/ # Berisi runner utama: dotup.sh
├── actions/ # Action default yang bisa di-override user
│ └── scan/ # Contoh action
│ ├── scan.sh
│ └── action.json
├── configs/ # Konfigurasi sistem lo (per OS/distro)
└── .config/dotup/ # Config user (auto-generate)
```
---

## 🛠 Cara Pakai

### 📦 Jalankan Action

```bash
./bin/dotup.sh scan --filter php
./bin/dotup.sh install nginx
./bin/dotup.sh about
Otomatis nyari action dari ~/.dotup/actions lalu fallback ke ./actions.
```
### 🔁 Format Action
Setiap action harus punya:
```
actions/<nama_action>/
├── <entry>.sh / .py / binary
└── action.json
```

Contoh action.json:

```json
{
  "name": "scan",
  "runtime": "bash",
  "entry": "scan.sh"
}
```
### 🎯 Runtime yang didukung (default):
- bash
- python
- exec (untuk binary)
Bisa nambah node, perl, dll via `~/.config/dotup/config.json`

### ⚙️ Konfigurasi Dotup
Config global lo disimpan di:
`~/.config/dotup/config.json`
Contoh isi default:
```json
{
  "actions_paths": [
    "~/.dotup/actions",
    "./actions"
  ],
  "default_configs_path": "./configs",
  "runtimes": {
    "bash": "bash {entry} {args}",
    "python": "python3 {entry} {args}",
    "exec": "{entry} {args}"
  }
}
```
### 💡 Fitur yang Direncanakan
- [x] Modular action + path override
- [x] Config generator otomatis
- [x] Multi-runtime extensible
- [ ] dotup install
- [ ] dotup encrypt / decrypt untuk file sensitif
- [ ] dotup install auto install dari configs/
- [ ] dotup new untuk generate action template
- [ ] GUI / TUI opsional (via fzf, gum, dsb)

### 🧠 Filosofi
Semua harus modular, portabel, dan override-able
Lo bisa push semua setup lo ke repo publik, tanpa nyimpen file rahasia
Framework lo sendiri, sesuai gaya lo

### 📜 Lisensi
MIT — Bebas pakai, modifikasi

🧪 Contoh Real Use
- Lagi nyiapin setup custom?
- Lagi migrasi SSD?
- Lagi setting laptop kantor biar sama kayak rumah?

Dotup bisa bantu lo dokumentasiin semuanya, terus tinggal:

`dotup install`
Boom 💥 semua environment kembali.

### 🙏 Credits
Made with 🤘 from Djakardah

Inspired by dotfiles, Nix, Ansible, dan Linux hacking harian.
