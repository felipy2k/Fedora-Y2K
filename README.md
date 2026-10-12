# 🐧 Fedora Y2K — Post-Install Setup Script

> An interactive post-installation script for **Fedora Workstation**, configured for **Fedora 44 + GNOME 50**.
> Automates everything from repositories and codecs to drivers, apps, extensions, and visual settings — through a clean modular menu.

---

## ⚠️ Before you start — NVIDIA and Secure Boot

**For NVIDIA installation, configure module signing or disable Secure Boot in your BIOS/UEFI.**

The NVIDIA driver (`akmod-nvidia`) is a kernel module that requires signing to work with Secure Boot enabled. The script detects Secure Boot and asks whether to continue; it does not sign the module automatically.

> 💡 **If you choose to disable Secure Boot:**
> 1. Restart your computer and enter BIOS/UEFI (usually `F2`, `F10`, `F12` or `Del` during boot)
> 2. Navigate to the **Security** or **Boot** tab
> 3. Find **Secure Boot** and set it to **Disabled**
> 4. Save and exit (`F10`)
> 5. Boot into Fedora and run the script

> 🔵 **Don't have an NVIDIA GPU?** You can skip this step — Secure Boot won't affect the rest of the installation.

---

## 💾 Disk Space Requirements

> Required space depends on the selected applications, package versions and shared Flatpak runtimes.

| 🗂️ Component | 📝 Storage notes |
|---|---|
| 📦 RPM apps, codecs and themes | Allow space for packages and dependencies |
| 🤖 ChatGPT | Approximately 1.7 GB installed on the reference PC |
| 🖱️ OpenLogi | Approximately 84 MB installed on the reference PC |
| 📱 Flatpaks | 27 apps plus shared GNOME/KDE runtimes |
| 🎮 Steam | Runtime and games require additional space |
| 🟢 NVIDIA + CUDA | Driver packages and optional CUDA Toolkit require additional space |

> ⚠️ The script warns if less than **15 GB free** is available before option **[1] Run EVERYTHING**. This threshold does not guarantee enough space for every installation; allow extra room for downloads, CUDA and games.

---

## 🚀 Quick Start

```bash
git clone https://github.com/felipy2k/Fedora-Y2K.git
cd Fedora-Y2K
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
║  [4] Install RPM packages + FreeOffice                        ║
║  [5] Install Flatpaks only                                    ║
║  [6] Install NVIDIA driver + CUDA only                        ║
║  [7] Install GNOME extensions only                            ║
║  [8] Apply visual settings only                               ║
║  [9] Final verification                                       ║
║  [u] Install Media Writer and remove Popsicle                 ║
║  [o] Install OpenLogi only                                    ║
║  [f] Install FreeOffice only                                  ║
║  [0] Exit                                                     ║
║  [r] Exit and reboot the system                               ║
╚═══════════════════════════════════════════════════════════════╝
```

**Option [1] Run EVERYTHING** — execution order:

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
| 🤖 | ChatGPT repository, configured by the official RPM |
| 🛡️ | NordVPN repository, configured by its installer |
| 🧪 | NVIDIA CUDA repository, when requested |

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
- 🔍 GPU detection via PCI display-device class codes
- 🔐 Secure Boot detection with confirmation prompt
- 📦 RPM Fusion: `akmod-nvidia`, `xorg-x11-drv-nvidia-cuda`, `nvidia-settings`, `nvidia-vaapi-driver`
- 🔨 Builds kernel module (`akmods --force`) + regenerates initramfs (`dracut --force`)
- ⚡ Enables power services: `nvidia-hibernate`, `nvidia-resume`, `nvidia-suspend`
- 🧪 Optional: full CUDA Toolkit (`nvcc`, cuBLAS, headers) via official NVIDIA repo
- 🟢 **GPU detected** → asks for confirmation (`yes`) before installation
- 🟡 **GPU not detected** → explains why and asks to confirm — install proceeds if confirmed

---

### 📥 RPM Packages

| 🗂️ Category | 📦 Apps |
|---|---|
| 🌐 Browsers | Firefox, Google Chrome, Tor Browser |
| 🎬 Multimedia | VLC, Audacity, Darktable, HandBrake, EasyEffects, OBS Studio, DistroAV, Cheese, Jellyfin server, Calf, Rygel |
| 🎨 Graphics / 3D | Inkscape, Blender |
| 🎮 Gaming | Steam |
| 🖥️ GNOME Apps | Files (Nautilus), Tweaks, Baobab, Déjà Dup, Boxes, Calculator, Calendar, Characters, Contacts, Simple Scan, Disk Utility, Text Editor, Font Viewer, Color Manager, Software, Clocks, Logs, Evince, Loupe, File Roller, ABRT, **Drawing**, Papers, Papers Nautilus integration, Dialect, Sushi, System Monitor, Settings, Ptyxis, Parental Controls |
| 🔧 Utilities | Timeshift, OpenLogi, fastfetch, pipx, DreamChess, lm_sensors, Deskflow, Fedora Media Writer, qBittorrent, Remmina (RDP/VNC) |
| 🛡️ VPN | **NordVPN** CLI + GUI (official installer, daemon enabled, user added to group) |
| 📝 Office | FreeOffice 2024 (official SoftMaker installer) |
| 🤖 AI | ChatGPT (official RPM download) |

---

### 📱 Flatpaks (26 Flathub + 1 Fedora)

| 🗂️ Category | 📦 Apps |
|---|---|
| 🔧 System | Extension Manager, Resources, Flatseal, Gear Lever, File Shredder (Raider), LocalSend, Switcheroo, Podman Desktop |
| 🎬 Multimedia | Shotcut, Video Trimmer, Camera Ctrls, Converseen, Jellyfin Desktop, Playlifin |
| 🧠 Productivity | GIMP, FreeCAD, Upscayl, Exhibit (3D Viewer) |
| 🎵 Entertainment | Blanket, Shortwave, Podcasts, Gcolor3, Sticky Notes, Alpaca, **Discord**, Telegram |
| 🖥️ Fedora remote | GNOME Connections |

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
| 🗑️ Other | GNOME Tour, Weather, Maps, Yelp, dconf-editor, htop, Piper, JACK, QjackCtl, Bruno Flatpak |
| 💾 USB writer | Popsicle — only when Fedora Media Writer is confirmed installed |

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
| 🐧 | Fedora Workstation — configured for **Fedora 44 + GNOME 50**, x86_64 |
| 🌐 | Internet connection |
| 🔑 | User account with `sudo` access |
| 🖥️ | Run from inside a graphical (GNOME) session — not SSH/TTY |
| 💾 | Free space for apps, dependencies and downloads; script warns below **15 GB** |

---

## 📝 Important Notes

<details>
<summary>⚠️ RPM Fusion update conflicts</summary>

When Fedora releases a system update and RPM Fusion hasn't yet published the matching freeworld package, DNF/GNOME Software can throw confusing dependency errors. The script sets `best=False` in `/etc/dnf/dnf.conf` **after the installation steps**. This can help with package-selection conflicts but does not guarantee that all dependency problems will be resolved.
</details>

<details>
<summary>🟢 NVIDIA + Secure Boot</summary>

If Secure Boot is enabled, the script detects it and prompts for confirmation. After installation, the `akmod` module must be manually signed. See: [RPM Fusion — Secure Boot](https://rpmfusion.org/Howto/Secure%20Boot)

**GPU not detected?** This can happen when booting with the onboard/integrated GPU, or when pre-installing the driver before the card is physically inserted. The script detects this, explains it, and asks for confirmation — type `yes` to proceed with the driver installation. Typical workflow: install driver → reboot → switch to NVIDIA in BIOS.
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
<summary>🤖 ChatGPT</summary>

Downloaded from the official RPM source for `x86_64` or `aarch64` in options **[1]** and **[4]**. The RPM includes its signing key and update repository. The script checks the package identity and installation result. No `assets/` folder is required. Already installed copies are skipped; sign in through the app after installation.
</details>

<details>
<summary>🖱️ OpenLogi</summary>

Installs **v0.8.1** from the developer's GitHub release for `amd64` or `arm64`, verifies SHA-256 and confirms installation. Use **[o]** to install only OpenLogi. Launch with `openlogi-desktop`. To enable its background agent:

```bash
systemctl --user enable --now openlogi-agent.service
```

ChatGPT and OpenLogi preserve the downloaded RPM and print a retry command if DNF installation fails.
</details>

<details>
<summary>💾 Fedora Media Writer</summary>

Use **[u]** to install `mediawriter` and remove Popsicle. Removal checks the user/system Flatpak copies and the RPM package. Popsicle is kept if Media Writer is missing. This check also runs during RPM installation and cleanup.
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
- 🔒 **Individual installs** — repository RPM applications are installed and checked separately; one failing package does not block the others
- 💾 **Package backup** — full RPM list saved before bloat removal
- 💿 **Disk space check** — warns if less than 15 GB free
- 🐧 **Kernel limit** — sets `installonly_limit=2` to limit retained kernel versions
- 📊 **Final verification** — checks every expected RPM, Flatpak and extension; reports missing items by name, warning count and log path
- 🔄 **Repeat runs** — installed catalog RPM apps and Flatpaks are detected and skipped
- 🚫 **Failure reporting** — application failures produce warnings while subsequent installations continue
</details>

---

*Made with ❤️ for Fedora users*
