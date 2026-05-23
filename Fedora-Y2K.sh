#!/usr/bin/env bash

set -uo pipefail

# Setup logging — captures all output to a timestamped log file in $HOME
LOG_FILE="$HOME/fedora-y2k-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "\n${GREEN}▶ $*${NC}"; }
step()    { echo -e "  ${CYAN}→ $*${NC}"; }
warning() { echo -e "  ${YELLOW}⚠ $*${NC}"; ((WARN_COUNT++)) || true; }
fail()    { echo -e "${RED}✗ $*${NC}"; }
ok()      { echo -e "  ${GREEN}✓ $*${NC}"; }

# Counter to summarize warnings at the end
WARN_COUNT=0

# Robust try() — works correctly with set -e/pipefail by toggling it locally.
# Returns 0 always, so a failure inside try() never aborts the script.
try() {
  set +e
  "$@"
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    warning "Failed (exit $rc), continuing: $*"
  fi
  return 0
}

if [[ "$EUID" -eq 0 ]]; then
  fail "Do not run as root. Run as a regular user."
  exit 1
fi

FEDORA_VER="$(rpm -E %fedora)"

show_menu() {
  clear
  echo -e "${BOLD}${BLUE}"
  echo "╔═══════════════════════════════════════════════════════════════╗"
  echo "║          Fedora — Custom Post-Install Setup                   ║"
  echo "║          User: ${USER}                                        ║"
  echo "╠═══════════════════════════════════════════════════════════════╣"
  echo "║  [1] Run EVERYTHING (recommended)                            ║"
  echo "║  [2] Update system only                                      ║"
  echo "║  [3] Remove bloatware only                                   ║"
  echo "║  [4] Install RPM packages only                               ║"
  echo "║  [5] Install Flatpaks only                                   ║"
  echo "║  [6] Install NVIDIA driver + CUDA only                       ║"
  echo "║  [7] Install GNOME extensions only                           ║"
  echo "║  [8] Apply visual settings only                              ║"
  echo "║  [9] Final verification                                      ║"
  echo "║  [0] Exit                                                    ║"
  echo "║  [r] Exit and reboot the system                              ║"
  echo "╚═══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  read -rp "  Choose an option: " CHOICE
}

# ─────────────────────────────────────────────
# REPOS
# ─────────────────────────────────────────────
add_repos() {
  info "[REPOS] Adding repositories"

  step "RPM Fusion (free + nonfree)"
  try sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"

  step "Enabling RPM Fusion AppStream metadata for GNOME Software"
  try sudo dnf install -y rpmfusion-free-release-tainted rpmfusion-nonfree-release-tainted 2>/dev/null || true

  step "Enabling fedora-cisco-openh264 repo (required for Firefox/WebRTC)"
  try sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1

  step "Google Chrome"
  if [[ ! -f /etc/yum.repos.d/google-chrome.repo ]]; then
    sudo tee /etc/yum.repos.d/google-chrome.repo > /dev/null <<'EOF'
[google-chrome]
name=Google Chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
  fi

  try sudo dnf makecache
}

# ─────────────────────────────────────────────
# SYSTEM UPDATE
# ─────────────────────────────────────────────
update_system() {
  info "[SYSTEM] Updating system"
  # Keep only 2 old kernels to save disk space
  try sudo sed -i 's/^installonly_limit=.*/installonly_limit=2/' /etc/dnf/dnf.conf
  try sudo dnf upgrade --refresh -y
}

# Apply best=False only AFTER all installs are done.
# This prevents DNF from silently skipping packages during the initial install
# transactions, but still protects against future RPM Fusion update conflicts.
apply_dnf_safety_setting() {
  info "[DNF CONFIG] Applying best=False for future updates"
  if ! grep -q '^best=False' /etc/dnf/dnf.conf 2>/dev/null; then
    try sudo sed -i '/^\[main\]/a best=False' /etc/dnf/dnf.conf
    ok "best=False added to dnf.conf (protects future updates from RPM Fusion lag)."
  else
    ok "best=False already set in dnf.conf."
  fi
}

# ─────────────────────────────────────────────
# CODECS — Official Fedora 43+ method (RPM Fusion)
# Based on: docs.fedoraproject.org + RPM Fusion
# ─────────────────────────────────────────────
install_codecs() {
  info "[CODECS] Installing multimedia codecs (official method)"

  step "Swapping ffmpeg-free for full ffmpeg (with proprietary codecs)"
  if rpm -q ffmpeg-free &>/dev/null; then
    try sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
  else
    ok "ffmpeg-free already swapped (skipping)."
  fi

  # DNF5 (Fedora 43+) does not recognize the @multimedia group.
  # Install equivalent packages individually for full compatibility.
  step "Installing GStreamer codec stack (DNF5-compatible individual packages)"
  try sudo dnf install -y \
    --setopt="install_weak_deps=False" \
    --exclude=PackageKit-gstreamer-plugin \
    gstreamer1-plugins-base \
    gstreamer1-plugins-good \
    gstreamer1-plugins-bad-free \
    gstreamer1-plugins-bad-freeworld \
    gstreamer1-plugins-ugly \
    gstreamer1-plugins-ugly-free \
    gstreamer1-plugin-openh264 \
    gstreamer1-plugin-libav \
    lame \
    lame-libs \
    mozilla-openh264

  step "Hardware video acceleration (VA-API/VDPAU)"
  # Auto-detects GPU to apply the correct freeworld drivers
  if lspci -d ::0300 -d ::0302 -d ::0380 2>/dev/null | grep -qi 'amd\|radeon\|ati'; then
    step "AMD GPU detected — installing mesa freeworld drivers"
    if rpm -q mesa-va-drivers &>/dev/null && ! rpm -q mesa-va-drivers-freeworld &>/dev/null; then
      try sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
    fi
    if rpm -q mesa-vdpau-drivers &>/dev/null && ! rpm -q mesa-vdpau-drivers-freeworld &>/dev/null; then
      try sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
    fi
  fi

  if lspci -d ::0300 -d ::0302 -d ::0380 2>/dev/null | grep -qi 'intel'; then
    step "Intel GPU detected — installing intel-media-driver"
    try sudo dnf install -y --skip-unavailable intel-media-driver libva-intel-driver
  fi
}

# ─────────────────────────────────────────────
# RPMs
# Install EVERYTHING before removing anything
# to avoid breaking dependencies
# ─────────────────────────────────────────────
install_rpms() {
  info "[RPM] Installing RPM packages"

  install_codecs

  # Install in logical groups so a failure in one group doesn't silently
  # cascade and skip everything else. Each group has its own try().
  # NO --skip-unavailable here — we want to know if a package fails.

  step "Base tools"
  try sudo dnf install -y \
    dnf-plugins-core git wget curl flatpak fastfetch pipx papirus-icon-theme

  step "Browsers"
  try sudo dnf install -y \
    google-chrome-stable firefox torbrowser-launcher

  step "Multimedia apps"
  try sudo dnf install -y \
    vlc audacity darktable handbrake-gui easyeffects obs-studio

  step "Graphics / 3D"
  try sudo dnf install -y \
    gimp inkscape blender

  step "Gaming"
  try sudo dnf install -y steam

  step "GNOME apps"
  try sudo dnf install -y \
    gnome-tweaks baobab nautilus deja-dup gnome-boxes gnome-calculator \
    gnome-calendar snapshot gnome-characters gnome-abrt gnome-connections \
    gnome-contacts simple-scan gnome-disk-utility gnome-text-editor \
    gnome-font-viewer gnome-color-manager gnome-software gnome-clocks \
    gnome-logs evince loupe file-roller

  step "Utilities"
  try sudo dnf install -y \
    timeshift solaar dreamchess lm_sensors deskflow

  # ── NordVPN — official installer (handles repo + GPG + install) ──
  step "NordVPN"
  if ! command -v nordvpn &>/dev/null; then
    if curl -sSf --max-time 10 -o /dev/null https://downloads.nordcdn.com/apps/linux/install.sh 2>/dev/null; then
      step "Running official NordVPN installer (CLI + GUI)"
      if sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh) -p nordvpn-gui; then
        ok "NordVPN installed."
        try sudo systemctl enable --now nordvpnd
        try sudo usermod -aG nordvpn "$USER"
        ok "Log in with: nordvpn login"
        warning "Group membership requires logout/reboot. For immediate use: newgrp nordvpn"
      else
        warning "NordVPN installer failed. Try manually after reboot:"
        echo "  sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh)"
      fi
    else
      warning "Cannot reach nordcdn.com — skipping NordVPN."
    fi
  else
    ok "NordVPN already installed (skipping)."
  fi
}

# ─────────────────────────────────────────────
# FREEOFFICE
# Replaces LibreOffice (removed afterwards)
# ─────────────────────────────────────────────
install_freeoffice() {
  info "[FREEOFFICE] Installing FreeOffice 2024"

  # Check connectivity before attempting curl | bash
  if ! curl -fsSL --max-time 5 -o /dev/null https://softmaker.net/down/install-softmaker-freeoffice-2024.sh 2>/dev/null; then
    warning "Cannot reach softmaker.net — skipping FreeOffice installation."
    warning "Run option [4] later when connected, or install manually:"
    echo "  curl -fsSL https://softmaker.net/down/install-softmaker-freeoffice-2024.sh | sudo bash"
    return
  fi

  step "Downloading and running official installer"
  if curl -fsSL https://softmaker.net/down/install-softmaker-freeoffice-2024.sh | sudo bash; then
    ok "FreeOffice installed successfully."
  else
    warning "Failed to install FreeOffice. Try manually:"
    echo "  curl -fsSL https://softmaker.net/down/install-softmaker-freeoffice-2024.sh | sudo bash"
  fi
}

# ─────────────────────────────────────────────
# FLATPAKS
# ─────────────────────────────────────────────
install_flatpaks() {
  info "[FLATPAK] Installing apps from Flathub"

  try flatpak remote-add --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo

  FLATPAK_IDS=(
    # System utilities
    com.mattjakeman.ExtensionManager        # GNOME Extension Manager
    net.nokyan.Resources                    # Resource monitor
    com.github.tchx84.Flatseal              # Flatpak permissions manager
    com.system76.Popsicle                   # USB image flasher
    com.github.ADBeveridge.Raider           # File Shredder
    org.localsend.localsend_app             # LocalSend (LAN file sharing)
    io.gitlab.adhami3310.Converter          # Switcheroo (image format converter)
    io.podman_desktop.PodmanDesktop         # Podman Desktop (container management)

    # Multimedia
    org.shotcut.Shotcut                     # Video editor
    org.gnome.gitlab.YaLTeR.VideoTrimmer    # Video trimmer
    hu.irl.cameractrls                      # Camera controls
    net.fasterland.converseen               # Batch image converter

    # Productivity / Creativity
    org.freecad.FreeCAD                     # 3D CAD
    org.upscayl.Upscayl                     # AI image upscaler
    io.github.nokse22.Exhibit               # 3D model viewer
    com.github.phase1geo.Minder             # Mind mapping
    com.motrix.Motrix                       # Download manager

    # Entertainment / Sound / Other
    com.rafaelmardojai.Blanket              # Ambient sounds
    de.haeckerfelix.Shortwave               # Internet radio
    org.gnome.Podcasts                      # Podcasts
    nl.hjdskes.gcolor3                      # Color picker
    com.vixalien.sticky                     # Sticky Notes
    com.jeffser.Alpaca                      # Alpaca (local LLM)
  )

  for app in "${FLATPAK_IDS[@]}"; do
    # Strip inline comments
    app="${app%%#*}"
    app="${app//[[:space:]]/}"
    [[ -z "$app" ]] && continue
    step "$app"
    try flatpak install -y flathub "$app"
  done
}

# ─────────────────────────────────────────────
# NVIDIA + CUDA
# Auto-detects GPU — installs only if found
# Filters by VGA/3D/Display to avoid false positives
# ─────────────────────────────────────────────
install_nvidia() {
  info "[NVIDIA] Detecting GPU"

  # Precise filter using PCI class codes:
  #   0300 = VGA, 0302 = 3D controller, 0380 = Display controller
  if ! lspci -d ::0300 -d ::0302 -d ::0380 2>/dev/null | grep -qi nvidia; then
    warning "No NVIDIA GPU detected. Skipping driver installation."
    return
  fi

  GPU_INFO="$(lspci -d ::0300 -d ::0302 -d ::0380 2>/dev/null | grep -i nvidia | head -1)"
  ok "NVIDIA GPU detected: $GPU_INFO"

  # Secure Boot warning
  if command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
    warning "Secure Boot is ENABLED."
    warning "After installation you will need to manually sign the akmod module."
    warning "See: https://rpmfusion.org/Howto/Secure%20Boot"
    read -rp "  Continue anyway? [y/N]: " SB_CONFIRM
    [[ "${SB_CONFIRM,,}" != "y" ]] && { warning "NVIDIA installation cancelled."; return; }
  fi

  step "Installing NVIDIA driver from RPM Fusion (akmod)"
  # cuda-toolkit does NOT exist in RPM Fusion. xorg-x11-drv-nvidia-cuda already
  # enables CUDA/NVENC/NVDEC support for apps (Blender, OBS, etc.).
  # For the full CUDA Toolkit (nvcc, headers), see the prompt below.
  try sudo dnf install -y --skip-unavailable \
    akmod-nvidia \
    xorg-x11-drv-nvidia \
    xorg-x11-drv-nvidia-cuda \
    xorg-x11-drv-nvidia-cuda-libs \
    xorg-x11-drv-nvidia-power \
    nvidia-settings \
    nvidia-vaapi-driver \
    libva-utils \
    vdpauinfo

  step "Building akmod module (may take a few minutes...)"
  try sudo akmods --force

  step "Regenerating initramfs"
  try sudo dracut --force

  step "Enabling NVIDIA power management services"
  try sudo systemctl enable nvidia-hibernate nvidia-resume nvidia-suspend

  echo
  echo -e "${BOLD}── Full CUDA Toolkit? ──${NC}"
  echo "The installed driver already provides CUDA support for apps (Blender, OBS, etc.)."
  echo "The FULL CUDA Toolkit (nvcc, cuBLAS headers, samples) requires the official NVIDIA repo."
  read -rp "  Add the official NVIDIA CUDA repo now? [y/N]: " CUDA_CONFIRM
  if [[ "${CUDA_CONFIRM,,}" == "y" ]]; then
    step "Adding official NVIDIA CUDA repository for Fedora ${FEDORA_VER}"
    try sudo dnf config-manager addrepo \
      --from-repofile="https://developer.download.nvidia.com/compute/cuda/repos/fedora${FEDORA_VER}/$(uname -m)/cuda-fedora${FEDORA_VER}.repo"
    try sudo dnf clean all

    # Exclude packages that conflict with RPM Fusion
    try sudo dnf config-manager setopt \
      "cuda-fedora${FEDORA_VER}-$(uname -m).exclude=nvidia-driver,nvidia-modprobe,nvidia-persistenced,nvidia-settings,nvidia-libXNVCtrl,nvidia-xconfig"

    step "Installing cuda-toolkit (nvcc, libs, headers)"
    try sudo dnf install -y cuda-toolkit
    ok "CUDA Toolkit installed. Run 'nvcc --version' after rebooting."
  else
    ok "Driver-only CUDA support (no nvcc). Sufficient for most applications."
  fi

  ok "NVIDIA driver installed. Reboot to load the kernel module."
}

# ─────────────────────────────────────────────
# GNOME EXTENSIONS
# ─────────────────────────────────────────────
install_gnome_extensions() {
  info "[EXTENSIONS] Installing GNOME extensions"

  export PATH="$HOME/.local/bin:$PATH"

  if ! command -v gext &>/dev/null; then
    step "Installing gnome-extensions-cli via pipx"
    try pipx install gnome-extensions-cli
    export PATH="$HOME/.local/bin:$PATH"
  fi

  EXTENSIONS=(
    AlphabeticalAppGrid@stuarthayhurst                  # Alphabetical App Grid
    appindicatorsupport@rgcjonas.gmail.com              # AppIndicator (system tray support)
    blur-my-shell@aunetx                                # Blur my Shell (blur panel, dash, overview)
    BringOutSubmenuOfPowerOffLogoutButton@pratap.fastmail.fm  # Bring Out Submenu Of Power Off Button
    caffeine@patapon.info                               # Caffeine (prevent suspend)
    clipboard-indicator@tudmotu.com                     # Clipboard Indicator (clipboard manager)
    dash-to-dock@micxgx.gmail.com                       # Dash to Dock
    editdesktopfiles@dannflower                         # Edit Desktop Files
    gsconnect@andyholmes.github.io                      # GSConnect (KDE Connect for GNOME)
    just-perfection-desktop@just-perfection             # Just Perfection (GNOME Shell tweaker)
    tilingshell@ferrarodomenico.com                     # Tiling Shell
    Vitals@CoreCoding.com                               # Vitals (CPU/RAM/temp/network monitor in panel)
  )

  if command -v gext &>/dev/null; then
    for ext in "${EXTENSIONS[@]}"; do
      ext="${ext%%#*}"
      ext="${ext//[[:space:]]/}"
      [[ -z "$ext" ]] && continue
      step "$ext"
      try gext install "$ext"
      try gext enable "$ext"
    done
    ok "Extensions installed. Some may show errors until the next GNOME Shell update."
  else
    warning "gext not available. Install manually via Extension Manager."
    echo "  Required extensions:"
    printf '    - %s\n' "${EXTENSIONS[@]}"
  fi
}

# ─────────────────────────────────────────────
# BLOATWARE REMOVAL
# Run AFTER installing everything to avoid
# breaking dependencies during installation
# ─────────────────────────────────────────────
remove_bloat() {
  info "[CLEANUP] Removing bloatware"
  warning "Run this step AFTER installing everything to avoid dependency issues."

  # Backup the package list before removing anything (recovery aid)
  BACKUP_FILE="$HOME/fedora-y2k-packages-before-cleanup-$(date +%Y%m%d-%H%M%S).txt"
  step "Backing up current package list to $BACKUP_FILE"
  if rpm -qa | sort > "$BACKUP_FILE" 2>/dev/null; then
    ok "Backup saved (restore with: sudo dnf install \$(cat $BACKUP_FILE))."
  else
    warning "Failed to write backup."
  fi

  step "Removing LibreOffice (replaced by FreeOffice)"
  try sudo dnf remove -y 'libreoffice*'

  step "Removing default GNOME media players (replaced by VLC)"
  # Covers both: Fedora ≤42 (Totem) and Fedora ≥43 (Showtime/Decibels)
  try sudo dnf remove -y \
    showtime \
    decibels \
    totem \
    totem-video-thumbnailer \
    gnome-music \
    rhythmbox

  step "Removing duplicate terminal (keeping Ptyxis, default since Fedora 41)"
  try sudo dnf remove -y gnome-terminal

  step "Removing RPM Extensions app (replaced by Extension Manager Flatpak)"
  try sudo dnf remove -y gnome-extensions-app

  step "Removing unnecessary apps"
  try sudo dnf remove -y \
    cheese \
    gnome-tour \
    mediawriter \
    gnome-weather \
    gnome-maps \
    yelp \
    dconf-editor \
    htop \
    piper \
    'jack-audio-connection-kit*' \
    qjackctl

  step "Removing unnecessary Flatpaks"
  try flatpak uninstall -y \
    org.gnome.Showtime \
    org.gnome.Decibels \
    org.gnome.Totem \
    org.gnome.Music \
    org.freedesktop.Piper \
    org.gnome.Help \
    com.usebruno.Bruno 2>/dev/null || true

  step "Cleaning orphan dependencies"
  try sudo dnf autoremove -y

  ok "Cleanup complete."
}

# ─────────────────────────────────────────────
# VISUAL SETTINGS & DEFAULT APPS
# ─────────────────────────────────────────────
apply_settings() {
  info "[SETTINGS] Applying GNOME settings and default apps"

  # ── Appearance ──
  try gsettings set org.gnome.desktop.interface icon-theme         'Papirus'
  try gsettings set org.gnome.desktop.interface color-scheme       'prefer-dark'
  try gsettings set org.gnome.desktop.interface clock-show-date    true
  try gsettings set org.gnome.desktop.interface clock-show-seconds true

  # ── Title bar buttons: add Minimize and Maximize (right side) ──
  try gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'

  # ── Dock favorites (Chrome, Files, Text Editor, Terminal, Calculator) ──
  # The App Grid button is always shown automatically by Dash to Dock — no config needed
  step "Setting dock shortcuts"
  try gsettings set org.gnome.shell favorite-apps \
    "['google-chrome.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.TextEditor.desktop', 'org.gnome.Ptyxis.desktop', 'org.gnome.Calculator.desktop']"

  # ── Default browser: Google Chrome ──
  step "Setting Google Chrome as default web browser"
  try xdg-settings set default-web-browser google-chrome.desktop

  # ── Default media player: VLC ──
  # Uses three methods combined for reliability on modern GNOME:
  #   1. xdg-mime  — writes to ~/.config/mimeapps.list
  #   2. gio mime  — GNOME's own tool, overrides gnome-mimeapps.list entries
  #   3. Direct write to mimeapps.list — guarantees persistence across sessions
  step "Setting VLC as default audio and video player"

  if [[ ! -f /usr/share/applications/vlc.desktop ]]; then
    warning "VLC is not installed yet — skipping default media player setup."
    warning "Re-run option [8] after installing VLC (RPM: vlc)."
  else
    MEDIA_TYPES=(
    video/mp4
    video/x-matroska
    video/webm
    video/avi
    video/quicktime
    video/x-msvideo
    video/mpeg
    video/x-flv
    video/3gpp
    video/ogg
    audio/mpeg
    audio/ogg
    audio/flac
    audio/x-wav
    audio/aac
    audio/mp4
    audio/x-m4a
    audio/opus
    audio/webm
  )

  for mime in "${MEDIA_TYPES[@]}"; do
    try xdg-mime default vlc.desktop "$mime"
    gio mime "$mime" vlc.desktop 2>/dev/null || true
  done

  # Direct write to mimeapps.list as final guarantee
  MIMEAPPS="$HOME/.config/mimeapps.list"
  mkdir -p "$HOME/.config"

  # Ensure [Default Applications] section exists
  if ! grep -q '^\[Default Applications\]' "$MIMEAPPS" 2>/dev/null; then
    echo '[Default Applications]' >> "$MIMEAPPS"
  fi

  # For each MIME type: remove any existing entry then add VLC
  for mime in "${MEDIA_TYPES[@]}"; do
    sed -i "/^${mime//\//\\/}=/d" "$MIMEAPPS" 2>/dev/null || true
    sed -i "/^\[Default Applications\]/a ${mime}=vlc.desktop" "$MIMEAPPS"
  done

  ok "VLC set as default for audio and video (xdg-mime + gio mime + mimeapps.list)."
  fi

  # ── Chrome: Wayland + touchpad two-finger back/forward gestures ──
  step "Configuring Chrome for Wayland touchpad gestures"

  FLAGS_FILE="$HOME/.config/chrome-flags.conf"
  mkdir -p "$HOME/.config"
  grep -qxF -- '--ozone-platform=wayland' "$FLAGS_FILE" 2>/dev/null \
    || echo '--ozone-platform=wayland' >> "$FLAGS_FILE"
  grep -qxF -- '--enable-features=TouchpadOverscrollHistoryNavigation' "$FLAGS_FILE" 2>/dev/null \
    || echo '--enable-features=TouchpadOverscrollHistoryNavigation' >> "$FLAGS_FILE"

  DESKTOP_SRC="/usr/share/applications/google-chrome.desktop"
  DESKTOP_DEST="$HOME/.local/share/applications/google-chrome.desktop"
  mkdir -p "$HOME/.local/share/applications"
  if [[ -f "$DESKTOP_SRC" ]]; then
    cp "$DESKTOP_SRC" "$DESKTOP_DEST"
    sed -i '/^Exec=\/usr\/bin\/google-chrome-stable/ s|%U|--ozone-platform=wayland --enable-features=TouchpadOverscrollHistoryNavigation %U|g' "$DESKTOP_DEST"
    ok "Chrome configured for Wayland and touchpad gestures."
  else
    warning "google-chrome.desktop not found — Chrome may not be installed yet. Re-run option [8] after installing Chrome."
  fi

  # ── Wallpaper ──
  step "Downloading and applying wallpaper"
  WALLPAPER_URL="https://image-1.uhdpaper.com/wallpaper/lighthouse-sunset-scenery-digital-art-4k-wallpaper-uhdpaper.com-326@1@m.jpg"
  WALLPAPER_PATH="$HOME/Pictures/nasa-wallpaper.jpg"
  mkdir -p "$HOME/Pictures"
  if curl -fsSL "$WALLPAPER_URL" -o "$WALLPAPER_PATH"; then
    try gsettings set org.gnome.desktop.background picture-uri      "file://$WALLPAPER_PATH"
    try gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALLPAPER_PATH"
    try gsettings set org.gnome.desktop.background picture-options  'zoom'
    ok "Wallpaper applied."
  else
    warning "Failed to download wallpaper. Check your connection."
  fi

  ok "Settings applied."
}

# ─────────────────────────────────────────────
# FINAL VERIFICATION
# ─────────────────────────────────────────────
verify_final() {
  info "[VERIFICATION] Checking final system state"

  echo
  echo -e "${BOLD}── Packages that should have been REMOVED ──${NC}"
  REMOVED_CHECK=$(rpm -qa | grep -E \
    "libreoffice|^showtime|^decibels|^totem|totem-video-thumbnailer|gnome-music|^rhythmbox|^cheese|gnome-tour|^mediawriter|gnome-weather|gnome-maps|^yelp|^dconf-editor|^htop|^piper|^gnome-terminal$|gnome-extensions-app" \
    2>/dev/null || true)
  if [[ -z "$REMOVED_CHECK" ]]; then
    ok "No unwanted packages found."
  else
    warning "Still present:"
    echo "$REMOVED_CHECK"
  fi

  echo
  echo -e "${BOLD}── RPM packages that should exist ──${NC}"
  rpm -qa | grep -E \
    "google-chrome-stable|firefox|^vlc|audacity|darktable|handbrake|inkscape|easyeffects|^gimp|^blender|^steam|^dreamchess|^nordvpn|^deskflow|obs-studio|gnome-software|papirus|softmaker|freeoffice|^solaar|timeshift|deja-dup" \
    2>/dev/null || warning "Some RPM packages may not be installed."

  echo
  echo -e "${BOLD}── Essential codecs ──${NC}"
  if rpm -q ffmpeg &>/dev/null && ! rpm -q ffmpeg-free &>/dev/null; then
    ok "Full ffmpeg installed (ffmpeg-free replaced)."
  else
    warning "ffmpeg-free still present — proprietary codecs may be missing."
  fi

  echo
  echo -e "${BOLD}── Default applications ──${NC}"
  BROWSER=$(xdg-settings get default-web-browser 2>/dev/null || echo "not set")
  echo "  Default browser : $BROWSER"
  VIDEO_DEFAULT=$(xdg-mime query default video/mp4 2>/dev/null || echo "not set")
  echo "  Default video   : $VIDEO_DEFAULT"
  AUDIO_DEFAULT=$(xdg-mime query default audio/mpeg 2>/dev/null || echo "not set")
  echo "  Default audio   : $AUDIO_DEFAULT"
  BUTTONS=$(gsettings get org.gnome.desktop.wm.preferences button-layout 2>/dev/null || echo "not set")
  echo "  Title bar btns  : $BUTTONS"
  if [[ "$BROWSER" == *"google-chrome"* ]]; then ok "Chrome is default browser."; else warning "Chrome is NOT the default browser."; fi
  if [[ "$VIDEO_DEFAULT" == *"vlc"* ]];     then ok "VLC is default video player."; else warning "VLC is NOT the default video player."; fi
  if [[ "$AUDIO_DEFAULT" == *"vlc"* ]];     then ok "VLC is default audio player."; else warning "VLC is NOT the default audio player."; fi
  if [[ "$BUTTONS" == *"minimize,maximize"* ]]; then ok "Minimize/Maximize buttons active."; else warning "Minimize/Maximize buttons not set."; fi

  echo
  echo -e "${BOLD}── Installed Flatpaks ──${NC}"
  flatpak list --app --columns=application 2>/dev/null | grep -E \
    "Alpaca|Resources|Flatseal|Blanket|Raider|FreeCAD|Upscayl|Shotcut|VideoTrimmer|cameractrls|converseen|nokse22.Exhibit|Minder|Motrix|localsend|Podcasts|Popsicle|Shortwave|sticky|Converter|ExtensionManager|PodmanDesktop" \
    || warning "Some expected Flatpaks may not be installed."

  echo
  echo -e "${BOLD}── NVIDIA GPU ──${NC}"
  if lspci -d ::0300 -d ::0302 -d ::0380 2>/dev/null | grep -qi nvidia; then
    if rpm -q akmod-nvidia &>/dev/null; then
      ok "NVIDIA driver installed."
      nvidia-smi 2>/dev/null | head -4 || warning "nvidia-smi not available (reboot to load the module)."
      if command -v nvcc &>/dev/null; then
        ok "Full CUDA Toolkit present: $(nvcc --version | grep release)"
      else
        echo "  ℹ CUDA Toolkit (nvcc) not installed — driver-only CUDA support active."
      fi
    else
      warning "NVIDIA GPU detected but driver NOT installed."
    fi
  else
    ok "No NVIDIA GPU (no driver needed)."
  fi

  echo
  echo -e "${BOLD}── GNOME Extensions ──${NC}"
  if command -v gnome-extensions &>/dev/null; then
    gnome-extensions list --enabled 2>/dev/null || true
  else
    warning "gnome-extensions not available."
  fi
}

# ─────────────────────────────────────────────
# RUN EVERYTHING
# Correct order: install everything → remove bloat
# ─────────────────────────────────────────────
run_all() {
  echo
  echo -e "${YELLOW}This will run all steps in the correct order.${NC}"
  echo -e "${CYAN}Order: repos → update → RPMs → FreeOffice → Flatpaks → NVIDIA → Extensions → Remove bloat → Settings${NC}"
  echo

  # Disk space check — full install needs roughly 15+ GB free
  AVAIL_GB=$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')
  if [[ -n "$AVAIL_GB" ]]; then
    echo -e "${BOLD}Free space on /: ${AVAIL_GB} GB${NC}"
    if [[ "$AVAIL_GB" -lt 15 ]]; then
      warning "Less than 15 GB free — full install may run out of space (Steam + Blender + CUDA can easily exceed this)."
      read -rp "Continue anyway? [y/N]: " DISK_CONFIRM
      [[ "${DISK_CONFIRM,,}" != "y" ]] && { warning "Cancelled."; return; }
    fi
  fi

  read -rp "Confirm? [y/N]: " CONFIRM
  [[ "${CONFIRM,,}" != "y" ]] && { warning "Cancelled."; return; }

  # Reset warning counter for clean final summary
  WARN_COUNT=0

  add_repos
  update_system
  install_rpms        # Installs everything (including codecs)
  install_freeoffice  # FreeOffice before removing LibreOffice
  install_flatpaks
  install_nvidia      # Auto-detects — skips if no NVIDIA GPU found
  install_gnome_extensions
  remove_bloat        # Removes LibreOffice and bloat AFTER installing everything
  apply_settings      # Visual settings + default apps
  apply_dnf_safety_setting  # best=False — only AFTER everything is installed
  verify_final

  echo
  echo -e "${BOLD}════════════════════════════════════════${NC}"
  echo -e "${BOLD}   SETUP SUMMARY${NC}"
  echo -e "${BOLD}════════════════════════════════════════${NC}"
  if [[ "$WARN_COUNT" -eq 0 ]]; then
    ok "Setup complete with no warnings!"
  else
    warning "Setup complete with $WARN_COUNT warning(s) — review the log above."
  fi
  echo "  Full log saved to: $LOG_FILE"
  echo -e "${YELLOW}⚠ Reboot the system to activate all drivers and settings.${NC}"
}

# ─────────────────────────────────────────────
# MAIN LOOP
# ─────────────────────────────────────────────
while true; do
  show_menu

  case "$CHOICE" in
    1) run_all ;;
    2) add_repos; update_system ;;
    3) remove_bloat ;;
    4) add_repos; install_rpms ;;
    5) install_flatpaks ;;
    6) add_repos; install_nvidia ;;
    7) install_gnome_extensions ;;
    8) apply_settings ;;
    9) verify_final ;;
    0) echo "Exiting."; exit 0 ;;
    r|R) echo "Rebooting..."; sudo reboot ;;
    *) warning "Invalid option." ;;
  esac

  echo
  read -rp "Press ENTER to return to the menu..." _
done
