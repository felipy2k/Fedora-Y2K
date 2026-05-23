# 🐧 Fedora Y2K — Post-Install Setup Script

> An interactive post-installation script for **Fedora Workstation 41+**, optimized for **Fedora 44 + GNOME 50**.  
> Automates everything from repositories and codecs to drivers, apps, extensions, and visual settings — through a clean modular menu.

---

## ⚠️ Before you start — Disable Secure Boot

**Secure Boot must be disabled in your BIOS/UEFI before running this script.**

The NVIDIA driver (`akmod-nvidia`) is a kernel module that requires signing to work with Secure Boot enabled. If you skip this step, the system may boot without GPU acceleration or fail to load the driver entirely.

> 💡 **How to disable Secure Boot:**
> 1. Restart your computer and enter BIOS/UEFI (usually `F2`, `F10`, `F12` or `Del` during boot)
> 2. Navigate to the **Security** or **Boot** tab
> 3. Find **Secure Boot** and set it to **Disabled**
> 4. Save and exit (`F10`)
> 5. Boot into Fedora and run the script

> 🔵 **Don't have an NVIDIA GPU?** You can skip this step — Secure Boot won't affect the rest of the installation.

---

## 🚀 Quick Start

```bash
git clone https://github.com/felipy2k/fedora-Y2K.git
cd fedora-Y2K
bash Fedora-Y2K.sh
```

> ⚠️ **Do not run as root.** The script uses `sudo` internally where needed.

---

## 🗂️ Menu

```
╔═══════════════════════════════════════════════════════════════╗
║          Fedora — Custom Post-Install Setup                   ║
╠═══════════════════════════════════════════════════════════════╣
║  [1] Run EVERYTHING (recommended)                            ║
║  [2] Update system only                                      ║
║  [3] Remove bloatware only                                   ║
║  [4] Install RPM packages only                               ║
║  [5] Install Flatpaks only                                   ║
║  [6] Install NVIDIA driver + CUDA only                       ║
║  [7] Install GNOME extensions only                           ║
║  [8] Apply visual settings only                              ║
║  [9] Final verification                                      ║
║  [0] Exit                                                    ║
║  [r] Exit and reboot                                         ║
╚═══════════════════════════════════════════════════════════════╝
```

**Option [1] Run EVERYTHING** — correct execution order guaranteed:

```
repos → update → RPMs → FreeOffice → Flatpaks → NVIDIA → Extensions → Remove bloat → Settings → best=False
```

---

## ✨ What gets installed

### 📦 Repositories
| | |
|---|---|
| 🔴 | RPM Fusion Free + Nonfree + Tainted |
| 🌐 | Google Chrome |
| 🔓 | fedora-cisco-openh264 (H.264 for Firefox/WebRTC) |

---

### 🎬 Multimedia Codecs
- 🔄 Swaps `ffmpeg-free` → full `ffmpeg` (H.264, H.265, AAC, MP3…) — **idempotent**
- 🎛️ Full GStreamer stack — **DNF5/Fedora 44 compatible** (individual packages, no broken group commands)
- ⚡ Hardware acceleration auto-detected by GPU:
  - 🔴 **AMD** → `mesa-va-drivers-freeworld` + `mesa-vdpau-drivers-freeworld`
  - 🔵 **Intel** → `intel-media-driver` + `libva-intel-driver`
  - 🟢 **NVIDIA** → handled by the dedicated driver section

---

### 🖥️ NVIDIA Driver + CUDA
- 🔍 GPU detection via PCI class codes — no false positives
- 🔐 Secure Boot detection with confirmation prompt
- 📦 RPM Fusion: `akmod-nvidia`, `xorg-x11-drv-nvidia-cuda`, `nvidia-settings`, `nvidia-vaapi-driver`
- 🔨 Builds kernel module (`akmods --force`) + regenerates initramfs (`dracut --force`)
- ⚡ Enables power services: `nvidia-hibernate`, `nvidia-resume`, `nvidia-suspend`
- 🧪 Optional: full CUDA Toolkit (`nvcc`, cuBLAS, headers) via official NVIDIA repo

---

### 📥 RPM Packages

| 🗂️ Category | 📦 Apps |
|---|---|
| 🌐 Browsers | Firefox, Google Chrome, Tor Browser |
| 🎬 Multimedia | VLC, Audacity, Darktable, Handbrake, EasyEffects, OBS Studio |
| 🎨 Graphics / 3D | GIMP, Inkscape, Blender |
| 🎮 Gaming | Steam |
| 🖥️ GNOME Apps | Tweaks, Baobab, Déjà Dup, Boxes, Calculator, Calendar, Snapshot, Characters, Connections, Contacts, Simple Scan, Disk Utility, Text Editor, Font Viewer, Color Manager, Software, Clocks, Logs, Evince, Loupe, **File Roller** |
| 🔧 Utilities | Timeshift, Solaar, fastfetch, pipx, DreamChess, lm_sensors, Deskflow |
| 🛡️ VPN | **NordVPN** CLI + GUI (official installer, daemon enabled, user added to group) |
| 📝 Office | FreeOffice 2024 (official SoftMaker installer) |

---

### 📱 Flatpaks (Flathub)

| 🗂️ Category | 📦 Apps |
|---|---|
| 🔧 System | Extension Manager, Resources, Flatseal, Popsicle, File Shredder (Raider), LocalSend, Switcheroo, Podman Desktop |
| 🎬 Multimedia | Shotcut, Video Trimmer, Camera Ctrls, Converseen |
| 🧠 Productivity | FreeCAD, Upscayl, Exhibit (3D Viewer), Minder, Motrix |
| 🎵 Entertainment | Blanket, Shortwave, Podcasts, Gcolor3, Sticky Notes, Alpaca |

---

### 🧩 GNOME Extensions

| 🔌 Extension | 📋 Purpose |
|---|---|
| AlphabeticalAppGrid | Sorts app grid alphabetically |
| AppIndicator Support | System tray icons |
| Blur my Shell | Blur effect on panel, dash and overview |
| Bring Out Submenu Of Power Off Button | Expands power menu options |
| Caffeine | Prevent sleep/suspend |
| Clipboard Indicator | Clipboard history manager |
| Dash to Dock | Persistent app dock |
| Edit Desktop Files | Edit `.desktop` files from the app grid |
| GSConnect | KDE Connect integration for GNOME |
| Just Perfection | Fine-tune GNOME Shell elements |
| Tiling Shell | Window tiling manager |
| Vitals | CPU, RAM, temp, fan, network in panel (uses `lm_sensors`) |

---

### 🎯 Default Apps & Settings

| ⚙️ Setting | 🎯 Value |
|---|---|
| 🌐 Web browser | Google Chrome |
| 🎬 Video player | VLC (via xdg-mime + gio mime + mimeapps.list) |
| 🎵 Audio player | VLC (same 3-method approach) |
| 🪟 Title bar | Minimize + Maximize + Close (right side) |
| 🚀 Dock | Chrome · Files · Text Editor · Ptyxis · Calculator · App Grid |
| 👆 Chrome touchpad | Two-finger swipe back/forward (Wayland flags) |

---

### 🧹 Bloatware Removed

| ❌ Type | 🗑️ What goes away |
|---|---|
| 📝 Office | LibreOffice → replaced by FreeOffice |
| 🎬 Video | Showtime, Totem, totem-video-thumbnailer |
| 🎵 Audio | Decibels, GNOME Music, Rhythmbox |
| 💻 Terminal | GNOME Terminal → keeps **Ptyxis** (default since Fedora 41) |
| 🧩 Extensions | gnome-extensions-app → replaced by Extension Manager Flatpak |
| 🗑️ Other | Cheese, GNOME Tour, Mediawriter, Weather, Maps, Yelp, dconf-editor, htop, Piper, JACK |

---

### 🎨 Visual Settings

| 🎨 | |
|---|---|
| 🖼️ | Icon theme: **Papirus** |
| 🌑 | Color scheme: **Dark mode** |
| 🕐 | Clock with date and seconds |
| 🪟 | Minimize + Maximize buttons on title bar |
| 🚀 | Dock shortcuts configured |
| 👆 | Chrome Wayland touchpad gestures |
| 🌌 | Wallpaper applied automatically |

---

## ⚙️ Requirements

| | |
|---|---|
| 🐧 | Fedora Workstation **41 or later** (optimized for Fedora 44 + GNOME 50) |
| 🌐 | Internet connection |
| 🔑 | User account with `sudo` access |
| 💾 | ~15 GB free disk space (Steam + Blender + CUDA) |

---

## 📝 Important Notes

<details>
<summary>⚠️ RPM Fusion update conflicts</summary>

When Fedora releases a system update and RPM Fusion hasn't yet published the matching freeworld package, DNF/GNOME Software can throw confusing dependency errors. The script sets `best=False` in `/etc/dnf/dnf.conf` **only after all packages are installed** — so future updates skip unresolvable packages rather than aborting, without affecting the initial install.
</details>

<details>
<summary>🟢 NVIDIA + Secure Boot</summary>

If Secure Boot is enabled, the script detects it and prompts for confirmation. After installation, the `akmod` module must be manually signed. See: [RPM Fusion — Secure Boot](https://rpmfusion.org/Howto/Secure%20Boot)
</details>

<details>
<summary>🧪 CUDA Toolkit</summary>

The RPM Fusion driver already includes CUDA runtime for apps (Blender, OBS, etc.). The full Toolkit (`nvcc`, cuBLAS, headers) is optional — installed from the official NVIDIA repo upon confirmation, with automatic conflict exclusion against RPM Fusion packages.
</details>

<details>
<summary>🛡️ NordVPN</summary>

Installed via the official NordVPN installer (`downloads.nordcdn.com`) — handles repo, GPG key, and packages in one step. Both **CLI and GUI** are installed (`-p nordvpn-gui`). The `nordvpnd` daemon is enabled and your user is added to the `nordvpn` group. After install: `nordvpn login`. For immediate use without logout: `newgrp nordvpn`.
</details>

<details>
<summary>🎬 VLC as default player</summary>

GNOME's system-level `gnome-mimeapps.list` can override user settings. The script uses **three methods simultaneously** — `xdg-mime`, `gio mime`, and direct `~/.config/mimeapps.list` writes — covering 19 MIME types.
</details>

<details>
<summary>👆 Chrome touchpad gestures</summary>

Writes `--ozone-platform=wayland` and `--enable-features=TouchpadOverscrollHistoryNavigation` to `~/.config/chrome-flags.conf` and a user-level `.desktop` copy. Idempotent — safe to re-run.
</details>

<details>
<summary>🛡️ Reliability & recovery</summary>

- 📋 **Logging** — timestamped log saved to `~/fedora-y2k-YYYYMMDD-HHMMSS.log`
- 🔒 **Grouped installs** — 7 independent RPM groups; failures are isolated and visible
- 💾 **Package backup** — full RPM list saved before bloat removal
- 💿 **Disk space check** — warns if less than 15 GB free
- 📊 **Final summary** — total warnings + log path
- 🔄 **Idempotent** — safe to re-run; already-applied changes are detected and skipped
- 🛡️ **Non-blocking** — `try()` wraps every command; failures log warnings and never abort
</details>

---

*Made with ❤️ for Fedora users*
