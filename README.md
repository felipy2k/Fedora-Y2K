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

## 💾 Disk Space Requirements

> Sizes reflect **installed size on disk**, not download size.  
> Flatpak runtimes (GNOME, KDE) are shared between apps and counted once.

| 🗂️ Component | 💿 Size | 📝 Notes |
|---|---|---|
| 🎬 Codecs (ffmpeg + GStreamer stack) | ~25 MB | |
| 🌐 Browsers (Chrome + Firefox + Tor) | ~350 MB | |
| 🎥 Multimedia apps (VLC, Audacity, Darktable, Handbrake, EasyEffects, OBS) | ~300 MB | |
| 🎨 Graphics / 3D (GIMP, Inkscape, Blender) | ~500 MB | Blender alone is ~300 MB |
| 🖥️ GNOME apps + Utilities | ~300 MB | |
| 🖼️ Papirus icon theme | ~195 MB | Large — hundreds of icon variants |
| 📝 FreeOffice 2024 | ~700 MB | |
| 🎮 Steam (RPM package) | ~2 MB | Tiny package — bootstraps on first launch |
| 🎮 Steam runtime (downloaded on first launch) | ~1.5 GB | Downloaded by Steam itself, not by the script |
| 📱 Flatpaks (24 apps + GNOME/KDE runtimes) | ~3.5 GB | Largest single component |
| 🟢 NVIDIA driver (akmod + libs) | ~250 MB | Only if NVIDIA GPU present |
| 🧪 CUDA Toolkit (nvcc, cuBLAS, headers) | ~4.0 GB | **Optional** — prompted during install |

### Totals

| 🗂️ Scenario | 💿 Disk Used | 💡 Recommended Free Space |
|---|---|---|
| Base (RPMs + FreeOffice + Flatpaks, no Steam runtime) | ~5.5 GB | **8 GB** |
| + Steam runtime (typical gaming setup) | ~7.0 GB | **10 GB** |
| + NVIDIA driver | ~7.3 GB | **10 GB** |
| + CUDA Toolkit | ~11.3 GB | **15 GB** |

> ⚠️ The script checks for **15 GB free** before running option **[1] Run EVERYTHING** — this safely covers the full scenario including CUDA. If you are skipping CUDA, 10 GB is sufficient.

---

## 🚀 Quick Start

```bash
git clone https://github.com/felipy2k/fedora-Y2K.git
cd fedora-Y2K
bash Fedora-Y2K.sh
```

> ⚠️ **Do not run as root.** The script uses `sudo` internally where needed.
> 🖥️ **Run it from inside your GNOME session** (a terminal in the desktop), not over SSH or a bare TTY — the visual steps need a graphical session.

---

## 🗂️ Menu

```
╔═══════════════════════════════════════════════════════════════╗
║          Fedora - Custom Post-Install Setup                   ║
╠═══════════════════════════════════════════════════════════════╣
║  [1] Run EVERYTHING (recommended)                             ║
║  [2] Update system only                                       ║
║  [3] Remove bloatware only                                    ║
║  [4] Install RPM packages only                                ║
║  [5] Install Flatpaks only                                    ║
║  [6] Install NVIDIA driver + CUDA only                        ║
║  [7] Install GNOME extensions only                            ║
║  [8] Apply visual settings only                               ║
║  [9] Final verification                                       ║
║  [0] Exit                                                     ║
║  [r] Exit and reboot the system                               ║
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
- 🟢 **GPU detected** → installs automatically
- 🟡 **GPU not detected** → explains why and asks to confirm — install proceeds if confirmed

---

### 📥 RPM Packages

| 🗂️ Category | 📦 Apps |
|---|---|
| 🌐 Browsers | Firefox, Google Chrome, Tor Browser |
| 🎬 Multimedia | VLC, Audacity, Darktable, Handbrake, EasyEffects, OBS Studio |
| 🎨 Graphics / 3D | GIMP, Inkscape, Blender |
| 🎮 Gaming | Steam |
| 🖥️ GNOME Apps | Files (Nautilus), Tweaks, Baobab, Déjà Dup, Boxes, Calculator, Calendar, Snapshot, Characters, Connections, Contacts, Simple Scan, Disk Utility, Text Editor, Font Viewer, Color Manager, Software, Clocks, Logs, Evince, Loupe, File Roller, ABRT, **Drawing** |
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
| 🎵 Entertainment | Blanket, Shortwave, Podcasts, Gcolor3, Sticky Notes, Alpaca, **Discord** |

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
| GSConnect | KDE Connect integration for GNOME |
| Just Perfection | Fine-tune GNOME Shell elements |
| Tiling Shell | Window tiling manager |
| Vitals | CPU, RAM, temp, fan, network in panel (uses `lm_sensors`) |

> ℹ️ After installing, **log out and back in (or reboot)** to activate the extensions — on Wayland, GNOME Shell does not reload them live. A few may need a compatibility update before they load on GNOME 50.

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

![Wallpaper Preview](https://raw.githubusercontent.com/felipy2k/Fedora-Y2K/main/Y2K_Wallpaper.jpeg)

---

## ⚙️ Requirements

| | |
|---|---|
| 🐧 | Fedora Workstation **41 or later** (optimized for Fedora 44 + GNOME 50) |
| 🌐 | Internet connection |
| 🔑 | User account with `sudo` access |
| 🖥️ | Run from inside a graphical (GNOME) session — not SSH/TTY |
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

**GPU not detected?** This can happen when booting with the onboard/integrated GPU, or when pre-installing the driver before the card is physically inserted. The script detects this, explains it, and asks for confirmation — just say `y` and the driver installs normally. Typical workflow: install driver → reboot → switch to NVIDIA in BIOS.
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

Two complementary mechanisms apply `--ozone-platform=wayland` and `--enable-features=TouchpadOverscrollHistoryNavigation`:

1. **`~/.config/chrome-flags.conf`** — read by the launcher wrappers of several Chrome/Chromium packagings (and covers command-line launches). Harmless if a given build ignores it.
2. **A user-level `.desktop` copy** with the flags added to its `Exec=` line — reliably applies them when Chrome is opened from the dock or app grid.

Idempotent — safe to re-run.
</details>

<details>
<summary>🖥️ Graphical session required for visual steps</summary>

The visual steps — **[8] Apply visual settings** and **[7] Install GNOME extensions** — depend on a running user D-Bus session (`gsettings`, `dconf`, `gext`). If you run the script over SSH or a bare TTY, those steps detect the missing session and **skip with a clear message** instead of flooding the log with errors. Run them from a terminal inside your GNOME session (the heavy installs in `run_all` still work fine either way).
</details>

<details>
<summary>🛡️ Reliability & recovery</summary>

- 📋 **Logging** — timestamped log saved to `~/fedora-y2k-YYYYMMDD-HHMMSS.log`
- 🔑 **Sudo keepalive** — authenticates once, then refreshes the `sudo` timestamp in the background so long installs never pause for a password mid-run
- 🖥️ **Session-aware** — visual steps skip cleanly when no graphical session is present (SSH/TTY)
- 🔒 **Grouped installs** — independent RPM groups; failures are isolated and visible
- 💾 **Package backup** — full RPM list saved before bloat removal
- 💿 **Disk space check** — warns if less than 15 GB free
- 🐧 **Kernel cap** — keeps only 2 old kernels (`installonly_limit=2`) to save `/boot` space
- 📊 **Final summary** — total warnings + log path
- 🔄 **Idempotent** — safe to re-run; already-applied changes are detected and skipped
- 🚫 **Non-blocking** — every step is wrapped so a single failure logs a warning and never aborts the run
</details>

---

*Made with ❤️ for Fedora users*
