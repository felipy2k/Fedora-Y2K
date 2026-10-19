#!/usr/bin/env bash

set -uo pipefail

SCRIPT_VERSION="2026.10.19-r3"
if [[ "${1:-}" == --version ]]; then
  printf 'Fedora Y2K %s\n' "$SCRIPT_VERSION"
  exit 0
fi

# Setup logging — captures all output to a timestamped log file in $HOME
LOG_FILE="$HOME/fedora-y2k-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
printf 'Fedora Y2K %s | Script: %s\nLog: %s\n' "$SCRIPT_VERSION" "$(readlink -f -- "${BASH_SOURCE[0]}")" "$LOG_FILE"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[1;94m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "\n${GREEN}▶ $*${NC}"; }
step()    { echo -e "  ${CYAN}→ $*${NC}"; }
note()    { echo -e "  ${CYAN}ℹ $*${NC}"; }
warning() { echo -e "  ${YELLOW}⚠ $*${NC}"; ((WARN_COUNT++)) || true; }
fail()    { echo -e "${RED}✗ $*${NC}"; }
ok()      { echo -e "  ${GREEN}✓ $*${NC}"; }

# Counter to summarize warnings at the end
WARN_COUNT=0

# Robust try() — runs a command, logs a warning if it fails, and always
# returns 0 so a failure inside try() never aborts the script.
# NOTE: the script intentionally does NOT use `set -e`. The previous local
# `set +e / set -e` toggle was removed because it left `-e` ENABLED after
# every try() call, which could silently abort the script on the next
# unguarded command. With no global `-e`, the toggle was unnecessary.
try() {
  "$@"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    warning "Failed (exit $rc), continuing: $*"
  fi
  return 0
}

# ─────────────────────────────────────────────
# SUDO KEEPALIVE
# Validate sudo once and keep the timestamp fresh in the background so long
# install steps never pause to ask for the password again. Started lazily,
# only when a privileged action is actually chosen.
# ─────────────────────────────────────────────
SUDO_KEEPALIVE_PID=""
ensure_sudo() {
  if ! sudo -v; then
    fail "sudo authentication failed."
    return 1
  fi
  if [[ -z "$SUDO_KEEPALIVE_PID" ]]; then
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 60; done ) &>/dev/null &
    SUDO_KEEPALIVE_PID=$!
  fi
  return 0
}

cleanup() {
  [[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
  return 0
}
trap cleanup EXIT

# ─────────────────────────────────────────────
# GRAPHICAL SESSION DETECTION
# gsettings, dconf and `gext enable` all require a running user D-Bus session.
# Running over SSH or a bare TTY would otherwise produce a flood of confusing
# errors, so the visual steps are skipped (with a clear message) in that case.
# ─────────────────────────────────────────────
has_gui_session() {
  local desktop="${XDG_CURRENT_DESKTOP:-}"
  [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] &&
    [[ "${desktop,,}" == *gnome* ]] &&
    { [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] || [[ -S "/run/user/${UID}/bus" ]]; }
}

if [[ "$EUID" -eq 0 ]]; then
  fail "Do not run as root. Run as a regular user."
  exit 1
fi

FEDORA_VER="$(rpm -E %fedora)"


# Numeric PCI IDs avoid language-dependent vendor names and false matches.
gpu_devices_from_sysfs() {
  local path class vendor device seen=0
  local -a records=()
  for path in /sys/bus/pci/devices/*; do
    [[ -d "$path" ]] || continue
    read -r class < "$path/class" || return 1
    seen=1
    [[ "${class,,}" == 0x03* ]] || continue
    read -r vendor < "$path/vendor" || return 1
    read -r device < "$path/device" || return 1
    records+=("${path##*/} ${class:2:4}: ${vendor:2}:${device:2}")
  done
  [[ "$seen" -eq 1 ]] || return 1
  if [[ ${#records[@]} -gt 0 ]]; then
    printf '%s\n' "${records[@],,}"
  fi
  return 0
}

gpu_devices() {
  local devices
  if command -v lspci >/dev/null && devices=$(LC_ALL=C lspci -Dn); then
    awk '$2 ~ /^03[[:xdigit:]][[:xdigit:]]:$/ {print tolower($0)}' <<< "$devices"
    return 0
  fi
  # PCI sysfs does not require pciutils or an installed NVIDIA driver.
  gpu_devices_from_sysfs
}

gpu_vendor_present() {
  awk -v vendor="$1" '$3 ~ ("^" vendor ":") {found=1} END {exit !found}' <<< "$GPU_DEVICES"
}

find_nvcc() {
  local candidate mode="${1:-any}"
  # Prefer the system-selected Toolkit over an older compiler in PATH.
  if [[ -x /usr/local/cuda/bin/nvcc ]]; then
    printf '%s\n' /usr/local/cuda/bin/nvcc
    return 0
  fi
  while IFS= read -r candidate; do
    if [[ -x "$candidate" ]]; then printf '%s\n' "$candidate"; return 0; fi
  done < <(printf '%s\n' /usr/local/cuda-*/bin/nvcc | sort -Vr)
  # A user/Conda compiler is useful for diagnostics but must never become a
  # system-wide PATH entry written by this installer.
  if [[ "$mode" != system ]] && command -v nvcc >/dev/null; then
    command -v nvcc
    return 0
  fi
  return 1
}

protect_cuda_driver_packages() {
  local guard_file
  guard_file=$(mktemp --suffix=.repo) || return 1
  # DNF5 reads override files after the original .repo file. Use a glob so
  # existing CUDA repositories and ones added later receive the same guard.
  # Apply the guard before any DNF transaction, including when an older
  # CUDA repository configuration is already present.
  if ! printf '%s\n' '[cuda*]' \
      'excludepkgs=nvidia* libnvidia* kmod-nvidia* akmod-nvidia* xorg-x11-drv-nvidia* cuda-drivers*' > "$guard_file" ||
     ! sudo install -d -m 0755 /etc/dnf/repos.override.d ||
     ! sudo install -m 0644 "$guard_file" /etc/dnf/repos.override.d/zz-fedora-y2k-cuda.repo; then
    rm -f -- "$guard_file"
    warning "Could not protect RPM Fusion drivers from CUDA repository replacements."
    return 1
  fi
  rm -f -- "$guard_file"
}

verify_nvidia() {
  local GPU_DEVICES smi nvcc_path failures=0
  if ! GPU_DEVICES=$(gpu_devices); then
    warning "Cannot inspect PCI GPUs; NVIDIA status is unknown."
    return 1
  fi
  if ! gpu_vendor_present 10de; then
    note "No NVIDIA GPU enumerated; no active NVIDIA driver expected."
    return 0
  fi
  if ! rpm -q akmod-nvidia xorg-x11-drv-nvidia-cuda &>/dev/null; then
    warning "NVIDIA GPU detected but required driver packages are missing."
    return 1
  fi
  if ! modinfo -k "$(uname -r)" nvidia &>/dev/null; then
    warning "NVIDIA module is missing for the running kernel. Check akmods logs."
    failures=$((failures + 1))
  fi
  if smi=$(nvidia-smi 2>&1); then
    ok "NVIDIA driver is responding on the running system."
    printf '%s\n' "$smi"
  else
    warning "NVIDIA packages are present, but the driver is not responding. A reboot may be required; check akmods and Secure Boot if it persists."
    printf '%s\n' "$smi"
    failures=$((failures + 1))
  fi
  if nvcc_path=$(find_nvcc); then
    if "$nvcc_path" --version; then
      ok "CUDA compiler found: $nvcc_path"
    else
      warning "CUDA compiler exists but could not run."
      failures=$((failures + 1))
    fi
  else
    note "CUDA compiler not found. The full Toolkit is optional; driver status is reported separately."
  fi
  [[ "$failures" -eq 0 ]]
}

show_menu() {
  clear
  local W=63
  local bar
  printf -v bar '%*s' "$W" ''
  bar=${bar// /═}
  echo -e "${BOLD}${BLUE}"
  echo "╔${bar}╗"
  printf "║%-${W}s║\n" "          Fedora - Custom Post-Install Setup"
  printf "║%-${W}s║\n" "          Revision: $SCRIPT_VERSION | User: ${USER}"
  echo "╠${bar}╣"
  printf "║%-${W}s║\n" "  [1] Run EVERYTHING (recommended)"
  printf "║%-${W}s║\n" "  [2] Update system only"
  printf "║%-${W}s║\n" "  [3] Remove bloatware only"
  printf "║%-${W}s║\n" "  [4] Install RPM packages + FreeOffice"
  printf "║%-${W}s║\n" "  [5] Install Flatpaks only"
  printf "║%-${W}s║\n" "  [6] Install NVIDIA driver + CUDA only"
  printf "║%-${W}s║\n" "  [7] Install GNOME extensions only"
  printf "║%-${W}s║\n" "  [8] Apply visual settings only"
  printf "║%-${W}s║\n" "  [0] Exit"
  printf "║%-${W}s║\n" "  [r] Exit and reboot the system"
  echo "╚${bar}╝"
  echo -e "${NC}"
  read -rp "  Choose an option: " CHOICE || return 1
}

# ─────────────────────────────────────────────
# REPOS
# ─────────────────────────────────────────────
# NVIDIA-only actions must not depend on Chrome, NordVPN or other app repos.
nvidia_dnf() {
  sudo dnf --repo=fedora --repo=updates \
    --repo=rpmfusion-free --repo=rpmfusion-free-updates \
    --repo=rpmfusion-nonfree --repo=rpmfusion-nonfree-updates "$@"
}

rpmfusion_config_present() {
  local kind="$1"
  [[ -s "/etc/yum.repos.d/rpmfusion-${kind}.repo" &&
     -s "/etc/yum.repos.d/rpmfusion-${kind}-updates.repo" &&
     -s "/etc/pki/rpm-gpg/RPM-GPG-KEY-rpmfusion-${kind}-fedora-${FEDORA_VER}" ]]
}

ensure_rpmfusion() {
  local kind package installed temp_file identity base fetched action
  for kind in free nonfree; do
    package="rpmfusion-${kind}-release"
    installed=$(rpm -q --qf '%{VERSION}' "$package" 2>/dev/null) || installed=""
    if [[ "$installed" == "$FEDORA_VER" ]] && rpmfusion_config_present "$kind"; then
      note "$package for Fedora $FEDORA_VER is already installed."
      continue
    fi
    action=install
    [[ "$installed" != "$FEDORA_VER" ]] || action=reinstall
    temp_file=$(mktemp --suffix=.rpm) || return 1
    fetched=0
    for base in https://download1.rpmfusion.org https://mirrors.rpmfusion.org; do
      if curl --fail --location --proto '=https' --proto-redir '=https' \
          --connect-timeout 15 --max-time 90 --retry 1 \
          --output "$temp_file" "$base/$kind/fedora/$package-${FEDORA_VER}.noarch.rpm"; then
        identity=$(rpm -qp --qf '%{NAME} %{VERSION} %{ARCH}' "$temp_file" 2>/dev/null) || identity=""
        if [[ "$identity" == "$package $FEDORA_VER noarch" ]]; then
          fetched=1
          break
        fi
      fi
      warning "Could not obtain a valid $package from $base; trying the next source."
    done
    if [[ "$fetched" != 1 ]]; then
      rm -f "$temp_file"
      warning "RPM Fusion download failed (network/DNS or unavailable release). Repository setup stopped before driver installation. See $LOG_FILE"
      return 1
    fi
    if ! sudo dnf --repo=fedora --repo=updates "$action" -y "$temp_file"; then
      rm -f "$temp_file"
      warning "Could not install $package. See $LOG_FILE"
      return 1
    fi
    rm -f "$temp_file"
    installed=$(rpm -q --qf '%{VERSION}' "$package" 2>/dev/null) || installed=""
    if [[ "$installed" != "$FEDORA_VER" ]] || ! rpmfusion_config_present "$kind"; then
      warning "$package installation did not produce the expected repository configuration."
      return 1
    fi
  done
}

prepare_nvidia_repos() {
  if [[ ! "$FEDORA_VER" =~ ^[0-9]+$ || -e /run/ostree-booted || "$(uname -m)" != x86_64 ]]; then
    warning "NVIDIA setup requires traditional Fedora x86_64 with DNF."
    return 1
  fi
  step "Preparing Fedora and RPM Fusion repositories for NVIDIA"
  protect_cuda_driver_packages || return 1
  if ! sudo dnf --repo=fedora --repo=updates install -y pciutils curl mokutil; then
    warning "NVIDIA repository setup failed. See the DNF error above and $LOG_FILE"
    return 1
  fi
  ensure_rpmfusion
}

add_repos() {
  info "[REPOS] Adding repositories"
  if [[ ! "$FEDORA_VER" =~ ^[0-9]+$ || -e /run/ostree-booted ]]; then
    warning "This installer requires traditional Fedora with DNF, not an Atomic desktop."
    return 1
  fi
  if [[ "$(uname -m)" != x86_64 ]]; then
    warning "The complete application catalog currently requires x86_64."
    return 1
  fi
  protect_cuda_driver_packages || return 1
  if ! sudo dnf --repo=fedora --repo=updates install -y dnf5-plugins pciutils curl; then
    warning "Could not install required repository/hardware tools."
    return 1
  fi

  step "RPM Fusion (free + nonfree)"
  ensure_rpmfusion || return 1

  step "Enabling RPM Fusion tainted repositories"
  try sudo dnf install -y rpmfusion-free-release-tainted rpmfusion-nonfree-release-tainted

  step "Enabling fedora-cisco-openh264 repo (required for Firefox/WebRTC)"
  try sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1

  step "Google Chrome"
  if [[ ! -f /etc/yum.repos.d/google-chrome.repo ]]; then
    if ! sudo tee /etc/yum.repos.d/google-chrome.repo > /dev/null <<'EOF'
[google-chrome]
name=Google Chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
    then
      warning "Could not write the Google Chrome repository configuration."
      return 1
    fi
  fi

  sudo dnf makecache || { warning "Repository metadata refresh failed."; return 1; }
}

# ─────────────────────────────────────────────
# SYSTEM UPDATE
# ─────────────────────────────────────────────
update_system() {
  info "[SYSTEM] Updating system"
  # Keep three kernels in total, preserving fallback boot options.
  # Uses config-manager setopt (DNF5) so it works whether or not the line
  # already exists in dnf.conf — the old `sed` no-op'd when the line was absent.
  try sudo dnf config-manager setopt installonly_limit=3
  if ! sudo dnf upgrade --refresh -y; then
    warning "System update failed. Resolve the DNF error before installing additional packages."
    return 1
  fi
  ok "System update completed."
}

# Apply the chosen DNF solver preference after installation.
# Existing settings still apply during setup; best=False is not a conflict fix.
apply_dnf_safety_setting() {
  info "[DNF CONFIG] Applying best=False for future updates"
  if sudo dnf config-manager setopt best=False; then
    ok "DNF best=False configured. This does not guarantee conflict-free updates."
  else
    warning "Could not configure DNF best=False."
    return 1
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
    install_rpm_apps ffmpeg
  fi

  # Use explicit codec packages instead of depending on a release-specific group.
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
  # Inspect hardware once and distinguish query failure from absent hardware.
  local GPU_DEVICES
  if ! GPU_DEVICES=$(gpu_devices); then
    warning "Cannot inspect GPUs; skipping hardware-specific codec changes."
    return 1
  fi
  if gpu_vendor_present 1002; then
    step "AMD GPU detected — installing mesa freeworld drivers"
    if rpm -q mesa-va-drivers &>/dev/null && ! rpm -q mesa-va-drivers-freeworld &>/dev/null; then
      try sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
    fi
    if rpm -q mesa-vdpau-drivers &>/dev/null && ! rpm -q mesa-vdpau-drivers-freeworld &>/dev/null; then
      try sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
    fi
  fi

  if gpu_vendor_present 8086; then
    step "Intel GPU detected — installing intel-media-driver"
    try sudo dnf install -y --skip-unavailable intel-media-driver libva-intel-driver
  fi
}

# ─────────────────────────────────────────────
# RPMs
# Install EVERYTHING before removing anything
# to avoid breaking dependencies
# ─────────────────────────────────────────────
# Personal RPM apps captured from the reference PC (2026-10-12).
# These sources are separate from the Fedora/RPM Fusion hardware setup.
RPM_APP_PACKAGES=(
  dnf-plugins-core
  git
  wget
  curl
  flatpak
  fastfetch
  pipx
  papirus-icon-theme
  google-chrome-stable
  firefox
  torbrowser-launcher
  vlc
  audacity
  darktable
  HandBrake-gui
  easyeffects
  obs-studio
  cheese
  obs-studio-plugin-distroav
  jellyfin
  inkscape
  blender
  steam
  gnome-tweaks
  baobab
  nautilus
  deja-dup
  gnome-boxes
  gnome-calculator
  gnome-calendar
  gnome-characters
  gnome-abrt
  gnome-system-monitor
  gnome-contacts
  simple-scan
  gnome-disk-utility
  gnome-text-editor
  gnome-font-viewer
  gnome-color-manager
  gnome-software
  gnome-clocks
  gnome-logs
  evince
  loupe
  file-roller
  drawing
  papers
  papers-nautilus
  dialect
  sushi
  timeshift
  dreamchess
  lm_sensors
  deskflow
  mediawriter
  qbittorrent
  remmina
  remmina-plugins-rdp
  remmina-plugins-vnc
  calf
  rygel
  malcontent-control
  gnome-control-center
  ptyxis
)

FLATPAK_IDS=(
    # System utilities
    com.mattjakeman.ExtensionManager        # GNOME Extension Manager
    net.nokyan.Resources                    # Resource monitor
    com.github.tchx84.Flatseal              # Flatpak permissions manager
    com.github.ADBeveridge.Raider           # File Shredder
    org.localsend.localsend_app             # LocalSend (LAN file sharing)
    io.gitlab.adhami3310.Converter          # Switcheroo (image format converter)
    io.podman_desktop.PodmanDesktop         # Podman Desktop (container management)

    it.mijorus.gearlever                    # AppImage manager

    # Multimedia
    org.shotcut.Shotcut                     # Video editor
    org.gnome.gitlab.YaLTeR.VideoTrimmer    # Video trimmer
    hu.irl.cameractrls                      # Camera controls
    net.fasterland.converseen               # Batch image converter

    org.jellyfin.JellyfinDesktop            # Jellyfin desktop client
    net.krafting.Playlifin                  # Jellyfin music client

    # Productivity / Creativity
    org.gimp.GIMP                          # GIMP (PhotoGIMP customization is separate)
    org.freecad.FreeCAD                     # 3D CAD
    org.upscayl.Upscayl                     # AI image upscaler
    io.github.nokse22.Exhibit               # 3D model viewer

    # Entertainment / Sound / Other
    org.telegram.desktop                   # Telegram
    com.discordapp.Discord                  # Discord
    com.rafaelmardojai.Blanket              # Ambient sounds
    de.haeckerfelix.Shortwave               # Internet radio
    org.gnome.Podcasts                      # Podcasts
    nl.hjdskes.gcolor3                      # Color picker
    com.vixalien.sticky                     # Sticky Notes
    com.jeffser.Alpaca                      # Alpaca (local LLM)
)

EXTENSIONS=(
    AlphabeticalAppGrid@stuarthayhurst                  # Alphabetical App Grid
    appindicatorsupport@rgcjonas.gmail.com              # AppIndicator (system tray support)
    blur-my-shell@aunetx                                # Blur my Shell (blur panel, dash, overview)
    BringOutSubmenuOfPowerOffLogoutButton@pratap.fastmail.fm  # Bring Out Submenu Of Power Off Button
    caffeine@patapon.info                               # Caffeine (prevent suspend)
    clipboard-indicator@tudmotu.com                     # Clipboard Indicator (clipboard manager)
    dash-to-dock@micxgx.gmail.com                       # Dash to Dock
    gsconnect@andyholmes.github.io                      # GSConnect (KDE Connect for GNOME)
    tilingshell@ferrarodomenico.com                     # Tiling Shell
    Vitals@CoreCoding.com                               # Vitals (CPU/RAM/temp/network monitor in panel)
)

rpm_app_installed() {
  rpm -q --whatprovides "$1" &>/dev/null
}

install_rpm_apps() {
  local package failures=0 batch_failed=0
  local -a pending=()
  for package in "$@"; do
    if rpm_app_installed "$package"; then
      ok "$package already installed."
    else
      pending+=("$package")
    fi
  done
  [[ "${#pending[@]}" -gt 0 ]] || return 0
  step "Installing ${#pending[@]} missing RPM package(s) in one transaction"
  sudo dnf install -y "${pending[@]}" || batch_failed=1
  # A failed batch must not block unrelated applications. Also verify that
  # each requested capability really exists, even if DNF returned success.
  for package in "${pending[@]}"; do
    if rpm_app_installed "$package"; then
      ok "$package installation confirmed."
    elif [[ "${#pending[@]}" -gt 1 ]] &&
         sudo dnf install -y "$package" && rpm_app_installed "$package"; then
      ok "$package installation confirmed after individual retry."
    else
      warning "$package NOT installed successfully. See $LOG_FILE"
      failures=$((failures + 1))
    fi
  done
  if [[ "$batch_failed" -eq 1 && "$failures" -eq 0 ]]; then
    note "All requested packages are present after recovery from the batch failure."
  fi
  [[ "$failures" -eq 0 ]]
}

flatpak_app_installed() {
  flatpak info --user "$1" &>/dev/null || flatpak info --system "$1" &>/dev/null
}

remove_flatpak_app() {
  local app="$1" scope failures=0
  for scope in --user --system; do
    if flatpak info "$scope" "$app" &>/dev/null; then
      step "Removing $app ($scope)"
      if flatpak uninstall "$scope" -y "$app" &&
         ! flatpak info "$scope" "$app" &>/dev/null; then
        ok "$app removed ($scope)."
      else
        warning "$app removal failed ($scope). See $LOG_FILE"
        failures=$((failures + 1))
      fi
    fi
  done
  [[ "$failures" -eq 0 ]]
}

extension_installed() {
  [[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$1/metadata.json" ||
     -f "/usr/share/gnome-shell/extensions/$1/metadata.json" ]]
}

verify_app_inventory() {
  local app missing=0
  for app in "${RPM_APP_PACKAGES[@]}" chatgpt openlogi nordvpn nordvpn-gui softmaker-freeoffice-2024; do
    if ! rpm_app_installed "$app"; then
      warning "Missing RPM: $app"
      missing=$((missing + 1))
    fi
  done
  for app in "${FLATPAK_IDS[@]}" org.gnome.Connections; do
    if ! flatpak_app_installed "$app"; then
      warning "Missing Flatpak: $app"
      missing=$((missing + 1))
    fi
  done
  for app in "${EXTENSIONS[@]}"; do
    if ! extension_installed "$app"; then
      warning "Missing GNOME extension: $app"
      missing=$((missing + 1))
    fi
  done
  if [[ "$missing" -eq 0 ]]; then
    ok "All expected RPM apps, Flatpaks and extensions are installed."
  else
    warning "$missing expected item(s) missing. Review the names above and $LOG_FILE"
  fi
  [[ "$missing" -eq 0 ]]
}

install_chatgpt() {
  step "ChatGPT"
  if rpm -q chatgpt &>/dev/null; then
    ok "ChatGPT already installed (skipping)."
    return 0
  fi

  # The official RPM includes its signing key and update repository.
  # https://learn.chatgpt.com/docs/linux/linux-app
  local chatgpt_arch chatgpt_rpm chatgpt_identity
  chatgpt_arch=$(uname -m)
  case "$chatgpt_arch" in
    x86_64|aarch64) ;;
    *) warning "ChatGPT NOT installed: unsupported architecture: $chatgpt_arch"; return 1 ;;
  esac

  chatgpt_rpm=$(mktemp --suffix=.rpm) || {
    warning "ChatGPT NOT installed: cannot create download file."
    return 1
  }
  if ! curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fL \
      --retry 2 --connect-timeout 15 --max-time 1800 \
      "https://persistent.oaistatic.com/codex-app-prod/linux/rpm/latest/chatgpt.${chatgpt_arch}.rpm" \
      -o "$chatgpt_rpm"; then
    warning "ChatGPT NOT installed: download failed. See $LOG_FILE"
    rm -f -- "$chatgpt_rpm"
    return 1
  fi

  # Reject invalid downloads or a package for a different architecture.
  if ! chatgpt_identity=$(rpm -qp --qf '%{NAME} %{ARCH}' "$chatgpt_rpm") ||
     [[ "$chatgpt_identity" != "chatgpt $chatgpt_arch" ]]; then
    warning "ChatGPT NOT installed: downloaded file is not the expected RPM. See $LOG_FILE"
    rm -f -- "$chatgpt_rpm"
    return 1
  fi

  # Do not use try() here: it deliberately discards the command's exit code.
  if sudo dnf install -y "$chatgpt_rpm" && rpm -q chatgpt &>/dev/null; then
    ok "ChatGPT installation confirmed."
    rm -f -- "$chatgpt_rpm"
    return 0
  fi

  warning "ChatGPT NOT installed successfully. Review the DNF error in $LOG_FILE"
  note "Downloaded RPM kept for retry: $chatgpt_rpm"
  printf '  Retry: sudo dnf install -y %q\n' "$chatgpt_rpm"
  return 1
}

install_openlogi() {
  step "OpenLogi"
  if rpm -q openlogi &>/dev/null; then
    ok "OpenLogi already installed (skipping)."
    return 0
  fi

  local arch rpm_arch checksum rpm_file identity
  rpm_arch=$(uname -m)
  case "$rpm_arch" in
    x86_64)
      arch=amd64
      checksum=23aff73ee8ab6a2f9d340ad259ea3935177ee81fcd6596b231288027098f2d09 ;;
    aarch64)
      arch=arm64
      checksum=9c5e18650682d5075e3f4feb84fee5c9e8caa6659ff604b1a8d7a0be25f9559d ;;
    *) warning "OpenLogi NOT installed: unsupported architecture: $rpm_arch"; return 1 ;;
  esac

  rpm_file=$(mktemp --suffix=.rpm) || {
    warning "OpenLogi NOT installed: cannot create download file."
    return 1
  }
  step "Downloading OpenLogi v0.8.1 ($arch)"
  if ! curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fL \
      --retry 2 --connect-timeout 15 --max-time 1800 \
      "https://github.com/AprilNEA/OpenLogi/releases/download/v0.8.1/openlogi-v0.8.1-linux-${arch}.rpm" \
      -o "$rpm_file"; then
    warning "OpenLogi NOT installed: download failed. See $LOG_FILE"
    rm -f -- "$rpm_file"
    return 1
  fi

  if ! printf '%s  %s\n' "$checksum" "$rpm_file" | sha256sum --check; then
    warning "OpenLogi NOT installed: SHA-256 verification failed. See $LOG_FILE"
    rm -f -- "$rpm_file"
    return 1
  fi
  if ! identity=$(rpm -qp --qf '%{NAME} %{ARCH}' "$rpm_file") ||
     [[ "$identity" != "openlogi $rpm_arch" ]]; then
    warning "OpenLogi NOT installed: downloaded file is not the expected RPM."
    rm -f -- "$rpm_file"
    return 1
  fi

  step "Installing OpenLogi"
  if sudo dnf install -y "$rpm_file" && rpm -q openlogi &>/dev/null; then
    ok "OpenLogi installation confirmed."
    note "Open the app from the applications menu or run: openlogi-desktop"
    note "Enable its background agent with: systemctl --user enable --now openlogi-agent.service"
    rm -f -- "$rpm_file"
    return 0
  fi

  warning "OpenLogi installation failed. Review the DNF error in $LOG_FILE"
  note "Downloaded RPM kept for retry: $rpm_file"
  printf '  Retry: sudo dnf install -y %q\n' "$rpm_file"
  return 1
}

install_personal_rpms() {
  local failures=0
  install_chatgpt || failures=$((failures + 1))
  install_openlogi || failures=$((failures + 1))
  [[ "$failures" -eq 0 ]]
}

install_rpms() {
  info "[RPM] Installing RPM packages"
  local warnings_before=$WARN_COUNT

  install_codecs

  # Install missing apps together, then recover unresolved packages individually.

  install_rpm_apps "${RPM_APP_PACKAGES[@]}"

  install_personal_rpms

  install_nordvpn
  [[ "$WARN_COUNT" -eq "$warnings_before" ]]
}

install_nordvpn() {
  step "NordVPN"
  local nord_installer warnings_before=$WARN_COUNT
  if ! rpm_app_installed nordvpn; then
    nord_installer=$(mktemp) || { warning "Cannot prepare NordVPN download."; return 1; }
    if ! curl --proto '=https' --proto-redir '=https' -fL --retry 2 \
        --connect-timeout 15 --max-time 180 \
        https://downloads.nordcdn.com/apps/linux/install.sh -o "$nord_installer" ||
       [[ ! -s "$nord_installer" ]] || ! sh "$nord_installer" -p nordvpn-gui; then
      rm -f -- "$nord_installer"
      warning "NordVPN installer failed. See $LOG_FILE"
      return 1
    fi
    rm -f -- "$nord_installer"
  elif ! rpm_app_installed nordvpn-gui; then
    install_rpm_apps nordvpn-gui || return 1
  fi
  if ! rpm_app_installed nordvpn || ! rpm_app_installed nordvpn-gui; then
    warning "NordVPN CLI and GUI packages could not both be confirmed."
    return 1
  fi
  # Also repair service/group setup when packages were already installed.
  try sudo systemctl enable --now nordvpnd
  try sudo usermod -aG nordvpn "$USER"
  note "Log out and back in after group changes. Log in with: nordvpn login"
  if [[ "$WARN_COUNT" -eq "$warnings_before" ]]; then
    ok "NordVPN CLI, GUI and service configuration confirmed."
  else
    return 1
  fi
}

# ─────────────────────────────────────────────
# FREEOFFICE
# Replaces LibreOffice (removed afterwards)
# ─────────────────────────────────────────────
install_freeoffice() {
  info "[FREEOFFICE] Installing FreeOffice 2024"
  local installer
  if rpm_app_installed softmaker-freeoffice-2024; then
    ok "FreeOffice already installed."
    return 0
  fi
  installer=$(mktemp) || { warning "Cannot prepare FreeOffice download."; return 1; }
  if curl --proto '=https' --proto-redir '=https' -fL --retry 2 \
      --connect-timeout 15 --max-time 180 \
      https://softmaker.net/down/install-softmaker-freeoffice-2024.sh -o "$installer" &&
      [[ -s "$installer" ]] && sudo bash "$installer" &&
      rpm_app_installed softmaker-freeoffice-2024; then
    rm -f -- "$installer"
    ok "FreeOffice installation confirmed."
  else
    rm -f -- "$installer"
    warning "FreeOffice installation failed or its package is missing. LibreOffice will be kept."
    return 1
  fi
}

# ─────────────────────────────────────────────
# FLATPAKS
# ─────────────────────────────────────────────
install_flatpaks() {
  info "[FLATPAK] Installing apps from Flathub"
  local app failures=0
  local -a pending=()
  if ! command -v flatpak >/dev/null; then
    if ! ensure_sudo || ! sudo dnf install -y flatpak || ! command -v flatpak >/dev/null; then
      warning "Flatpak is unavailable. Cannot install Flatpak applications."
      return 1
    fi
  fi
  for app in "${FLATPAK_IDS[@]}"; do
    if flatpak_app_installed "$app"; then
      ok "$app already installed."
    else
      pending+=("$app")
    fi
  done
  if [[ "${#pending[@]}" -gt 0 ]]; then
    if flatpak remote-add --system --if-not-exists flathub \
        https://flathub.org/repo/flathub.flatpakrepo; then
      # Preserve per-application recovery and clear failure reporting.
      for app in "${pending[@]}"; do
        if flatpak install --system -y flathub "$app" && flatpak_app_installed "$app"; then
          ok "$app installation confirmed."
        else
          warning "$app NOT installed successfully. See $LOG_FILE"
          failures=$((failures + 1))
        fi
      done
    else
      warning "Could not configure Flathub. Flathub applications were not installed."
      failures=$((failures + 1))
    fi
  fi
  # An existing app in either scope needs no remote/network modification.
  if flatpak_app_installed org.gnome.Connections; then
    ok "Connections already installed."
  elif flatpak remote-add --system --if-not-exists fedora oci+https://registry.fedoraproject.org &&
       flatpak install --system -y fedora org.gnome.Connections &&
       flatpak_app_installed org.gnome.Connections; then
    ok "Connections installation confirmed."
  else
    warning "Connections NOT installed successfully. Check its Fedora remote. See $LOG_FILE"
    failures=$((failures + 1))
  fi
  [[ "$failures" -eq 0 ]]
}

# ─────────────────────────────────────────────
# NVIDIA — internal install logic
# Called by install_nvidia() after detection/confirmation
# ─────────────────────────────────────────────
_nvidia_do_install() {
  local sb_state target_kernel module_signer CUDA_CONFIRM nvcc_path repo_file repo_id
  # Unknown Secure Boot state must not be mistaken for disabled.
  if [[ -d /sys/firmware/efi ]]; then
    if ! command -v mokutil >/dev/null; then
      nvidia_dnf install -y mokutil || { warning "Cannot check Secure Boot."; return 1; }
    fi
    sb_state=$(LC_ALL=C mokutil --sb-state 2>&1) || { warning "Cannot determine Secure Boot state: $sb_state"; return 1; }
    if [[ "$sb_state" == *enabled* ]]; then
      if ! sudo mokutil --test-key /etc/pki/akmods/certs/public_key.der >/dev/null 2>&1; then
        warning "Secure Boot is enabled and the akmods signing key is not enrolled. NVIDIA setup paused."
        note "Follow https://rpmfusion.org/Howto/Secure%20Boot to generate/enroll the akmods key, reboot to confirm enrollment, then run option [6]."
        return 1
      fi
    elif [[ "$sb_state" != *disabled* ]]; then
      warning "Unrecognized Secure Boot state: $sb_state"
      return 1
    fi
  else
    sb_state=disabled
  fi

  # Build for the newest installed kernel, which may differ after an upgrade.
  if ! target_kernel=$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -1); then
    warning "Cannot query installed kernels."
    return 1
  fi
  if [[ -z "$target_kernel" || ! -d "/usr/lib/modules/$target_kernel" ]]; then
    warning "Cannot determine the installed target kernel."
    return 1
  fi
  step "Installing NVIDIA driver from RPM Fusion for kernel $target_kernel"
  if ! nvidia_dnf install -y \
      "kernel-devel-$target_kernel" akmod-nvidia xorg-x11-drv-nvidia \
      xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-cuda-libs \
      xorg-x11-drv-nvidia-power nvidia-settings; then
    warning "NVIDIA package installation failed. Stopping this stage."
    return 1
  fi
  if ! rpm -q akmod-nvidia xorg-x11-drv-nvidia-cuda &>/dev/null; then
    warning "Required NVIDIA packages are still missing."
    return 1
  fi
  if ! sudo akmods --force --kernels "$target_kernel" ||
     ! modinfo -k "$target_kernel" nvidia &>/dev/null; then
    warning "NVIDIA module build failed for $target_kernel. Check /var/cache/akmods/."
    return 1
  fi
  if [[ "$sb_state" == *enabled* ]]; then
    module_signer=$(modinfo -k "$target_kernel" -F signer nvidia)
    if [[ -z "$module_signer" ]]; then
      warning "NVIDIA module is unsigned; Secure Boot would reject it."
      return 1
    fi
  fi
  if ! sudo dracut --force --kver "$target_kernel"; then
    warning "Could not regenerate initramfs for $target_kernel."
    return 1
  fi
  try sudo systemctl enable nvidia-hibernate nvidia-resume nvidia-suspend
  try nvidia_dnf install -y nvidia-vaapi-driver libva-utils vdpauinfo
  ok "NVIDIA packages and module installed for $target_kernel; runtime validation follows after reboot."
  note "The GPU model must be supported by this driver branch; older cards may require a legacy branch."

  echo
  note "The full CUDA Toolkit adds the nvcc compiler and development libraries."
  read -rp "  Install the optional NVIDIA CUDA Toolkit? [y/N]: " CUDA_CONFIRM || return 0
  [[ "${CUDA_CONFIRM,,}" == y ]] || return 0
  if [[ "$(uname -m)" != x86_64 ]]; then
    warning "This Fedora CUDA repository path is supported here only for x86_64."
    return 1
  fi
  repo_id="cuda-fedora${FEDORA_VER}-x86_64"
  repo_file=$(mktemp --suffix=.repo) || return 1
  if ! curl --proto '=https' --proto-redir '=https' -fL --retry 2 \
      --connect-timeout 15 --max-time 60 \
      "https://developer.download.nvidia.com/compute/cuda/repos/fedora${FEDORA_VER}/x86_64/cuda-fedora${FEDORA_VER}.repo" -o "$repo_file"; then
    rm -f -- "$repo_file"
    warning "CUDA repository unavailable for this Fedora version; Toolkit was not installed."
    return 1
  fi
  # Install a validated repo file with exclusions already applied, avoiding a
  # window where the NVIDIA repository could replace RPM Fusion's driver.
  if ! grep -qxF "[$repo_id]" "$repo_file" || [[ $(grep -c '^\[' "$repo_file") != 1 ]]; then
    rm -f -- "$repo_file"
    warning "Unexpected CUDA repository configuration."
    return 1
  fi
  if ! sed -i '/^[[:space:]]*exclude[[:space:]]*=/d; /^[[:space:]]*excludepkgs[[:space:]]*=/d' "$repo_file" ||
     ! printf '\nexcludepkgs=nvidia* libnvidia* kmod-nvidia* akmod-nvidia* xorg-x11-drv-nvidia* cuda-drivers*\n' >> "$repo_file"; then
    rm -f -- "$repo_file"
    warning "Could not prepare CUDA repository protections."
    return 1
  fi
  if [[ -f "/etc/yum.repos.d/cuda-fedora${FEDORA_VER}.repo" ]] &&
     ! sudo cp -p -- "/etc/yum.repos.d/cuda-fedora${FEDORA_VER}.repo" "/etc/yum.repos.d/cuda-fedora${FEDORA_VER}.repo.backup-$(date +%Y%m%d-%H%M%S)"; then
    rm -f -- "$repo_file"
    warning "Could not back up the existing CUDA repository configuration."
    return 1
  fi
  if ! sudo install -m 0644 "$repo_file" "/etc/yum.repos.d/cuda-fedora${FEDORA_VER}.repo"; then
    rm -f -- "$repo_file"
    warning "Could not configure CUDA repository."
    return 1
  fi
  rm -f -- "$repo_file"
  if ! nvidia_dnf --repo="$repo_id" install -y --refresh cuda-toolkit || ! rpm -q cuda-toolkit &>/dev/null; then
    warning "CUDA Toolkit installation failed. NVIDIA driver status is separate."
    return 1
  fi
  if ! nvcc_path=$(find_nvcc system) || ! "$nvcc_path" --version; then
    warning "Toolkit package is present, but nvcc could not be verified."
    return 1
  fi
  if ! printf 'export PATH=%q${PATH:+:${PATH}}\n' "${nvcc_path%/*}" |
      sudo tee /etc/profile.d/fedora-y2k-cuda.sh >/dev/null; then
    warning "Could not configure CUDA PATH. Compiler: $nvcc_path"
    return 1
  fi
  ok "CUDA compiler verified. Open a new login shell to use nvcc from PATH."
  note "GPU execution and host-compiler compatibility still require a CUDA program test."
}

# ─────────────────────────────────────────────
# NVIDIA + CUDA
# Auto-detects GPU — when called from run_all, skips if not found.
# When called from menu [6], offers to force install if not detected
# (useful when booting with onboard GPU while NVIDIA card is present).
# ─────────────────────────────────────────────
install_nvidia() {
  info "[NVIDIA] Detecting GPU"
  local GPU_DEVICES GPU_CONFIRM mode="${1:-manual}" detection_ok=1
  if ! GPU_DEVICES=$(gpu_devices); then
    detection_ok=0
    warning "GPU query failed; this does not mean that no NVIDIA card is present."
    if [[ "$mode" == auto ]]; then
      note "Use option [6] to explicitly request installation after checking the hardware."
      return 1
    fi
  fi
  if [[ "$detection_ok" -eq 1 ]] && gpu_vendor_present 10de; then
    note "NVIDIA display device(s):"
    awk '$3 ~ /^10de:/ {print}' <<< "$GPU_DEVICES"
  elif [[ "$mode" == auto ]]; then
    note "No NVIDIA GPU detected; skipping NVIDIA and CUDA."
    return 0
  else
    warning "NVIDIA was not detected. Manual installation is available for hardware you know is supported."
    [[ -z "$GPU_DEVICES" ]] || printf 'Detected PCI display devices:\n%s\n' "$GPU_DEVICES"
  fi
  read -rp "  Install NVIDIA driver? [yes/sim/N]: " GPU_CONFIRM || return 0
  case "${GPU_CONFIRM,,}" in
    yes|y|sim|s) ;;
    *) note "NVIDIA installation skipped."; return 0 ;;
  esac
  if [[ "$mode" == manual ]]; then
    prepare_nvidia_repos || return 1
  fi
  if ! _nvidia_do_install; then
    warning "NVIDIA/CUDA stage stopped before completion. Review the exact error above. Log: $LOG_FILE"
    return 1
  fi
}

# ─────────────────────────────────────────────
# GNOME EXTENSIONS
# ─────────────────────────────────────────────
install_gnome_extensions() {
  info "[EXTENSIONS] Installing GNOME extensions"
  local ext warnings_before=$WARN_COUNT

  if ! has_gui_session; then
    warning "No graphical session detected (no D-Bus session bus)."
    warning "GNOME extensions need a running GNOME session to install and enable."
    warning "Run option [7] from inside your GNOME session (not over SSH/TTY). Skipping."
    return 1
  fi

  export PATH="$HOME/.local/bin:$PATH"

  if ! command -v gext &>/dev/null; then
    step "Installing gnome-extensions-cli via pipx"
    if ! command -v pipx >/dev/null; then
      ensure_sudo && install_rpm_apps pipx || return 1
    fi
    pipx install gnome-extensions-cli || { warning "Could not install extension manager CLI."; return 1; }
    export PATH="$HOME/.local/bin:$PATH"
  fi


  if command -v gext &>/dev/null; then
    local extension_failures=0
    for ext in "${EXTENSIONS[@]}"; do
      ext="${ext%%#*}"
      ext="${ext//[[:space:]]/}"
      [[ -z "$ext" ]] && continue
      step "$ext"
      if extension_installed "$ext" || { gext install "$ext" && extension_installed "$ext"; }; then
        ok "$ext installation confirmed."
        try gext enable "$ext"
      else
        warning "$ext installation failed. See $LOG_FILE"
        extension_failures=$((extension_failures + 1))
      fi
    done
    if [[ "$extension_failures" -eq 0 ]]; then
      ok "All requested extensions are installed."
    else
      warning "$extension_failures extension(s) failed to install."
    fi
    note "Log out and back in (or reboot) to activate them — on Wayland, GNOME Shell does not reload extensions live."
    note "Some extensions may need a compatibility update before they load on GNOME 50."
  else
    warning "gext not available. Install manually via Extension Manager."
    echo "  Required extensions:"
    printf '    - %s\n' "${EXTENSIONS[@]}"
  fi
  [[ "$WARN_COUNT" -eq "$warnings_before" ]]
}

# ─────────────────────────────────────────────
# BLOATWARE REMOVAL
# Run AFTER installing everything to avoid
# breaking dependencies during installation
# ─────────────────────────────────────────────
remove_bloat() {
  info "[CLEANUP] Removing bloatware"
  note "Only removing replaced apps when their replacements are installed."
  local warnings_before=${WARN_COUNT:-0}

  # Backup the package list before removing anything (recovery aid)
  BACKUP_FILE="$HOME/fedora-y2k-packages-before-cleanup-$(date +%Y%m%d-%H%M%S).txt"
  step "Backing up current package list to $BACKUP_FILE"
  if rpm -qa | sort > "$BACKUP_FILE" 2>/dev/null; then
    ok "Package inventory saved for recovery review: $BACKUP_FILE"
  else
    warning "Failed to write the package inventory; cleanup was not started."
    return 1
  fi

  step "Removing LibreOffice (replaced by FreeOffice)"
  if rpm_app_installed softmaker-freeoffice-2024; then
    try sudo dnf remove -y 'libreoffice*'
  else
    warning "Keeping LibreOffice: FreeOffice installation is not confirmed."
  fi

  step "Removing default GNOME media players (replaced by VLC)"
  # Covers both: Fedora ≤42 (Totem) and Fedora ≥43 (Showtime/Decibels)
  if rpm_app_installed vlc; then
  try sudo dnf remove -y \
    showtime \
    decibels \
    totem \
    totem-video-thumbnailer \
    gnome-music \
    rhythmbox
  else
    warning "Keeping media players: VLC is not installed."
  fi

  step "Removing duplicate terminal (keeping Ptyxis, default since Fedora 41)"
  if rpm_app_installed ptyxis; then
    try sudo dnf remove -y gnome-terminal
  else
    warning "Keeping GNOME Terminal: Ptyxis is not installed."
  fi

  step "Removing RPM Extensions app (replaced by Extension Manager Flatpak)"
  if flatpak_app_installed com.mattjakeman.ExtensionManager; then
    try sudo dnf remove -y gnome-extensions-app
  else
    warning "Keeping Extensions app: Extension Manager is not installed."
  fi

  step "Removing unnecessary apps"
  try sudo dnf remove -y \
    gnome-tour \
    gnome-weather \
    gnome-maps \
    yelp \
    dconf-editor \
    htop \
    'jack-audio-connection-kit*' \
    qjackctl


  if rpm_app_installed openlogi; then
    try sudo dnf remove -y piper
  else
    warning "Keeping Piper: OpenLogi is not installed."
  fi

  step "Removing unnecessary Flatpaks"
  local obsolete_app
  for obsolete_app in \
    org.gnome.Showtime org.gnome.Decibels org.gnome.Totem org.gnome.Music \
    org.freedesktop.Piper org.gnome.Help com.usebruno.Bruno; do
    case "$obsolete_app" in
      org.freedesktop.Piper)
        rpm_app_installed openlogi || continue ;;
      org.gnome.Showtime|org.gnome.Decibels|org.gnome.Totem|org.gnome.Music)
        rpm_app_installed vlc || continue ;;
    esac
    remove_flatpak_app "$obsolete_app"
  done

  # Keep unrelated orphan packages; this cleanup targets the explicit app list.

  if [[ "${WARN_COUNT:-0}" -gt "$warnings_before" ]]; then
    note "Cleanup finished with warnings. Review failed removals and retained applications above."
    return 1
  fi
  ok "Cleanup complete."
}

# ─────────────────────────────────────────────
# VISUAL SETTINGS & DEFAULT APPS
# ─────────────────────────────────────────────

configure_chrome_launcher() {
  local source="$1" destination="$2" temporary
  [[ -f "$source" ]] || { warning "Chrome launcher not found."; return 1; }
  mkdir -p "${destination%/*}" || return 1
  # Keep user customizations and modify only Chrome Exec entries.
  [[ ! -f "$destination" ]] || source="$destination"
  if ! grep -qE '^Exec=/usr/bin/google-chrome-stable([[:space:]]|$)' "$source"; then
    warning "Custom Chrome launcher uses an unexpected executable; keeping it unchanged."
    return 1
  fi
  temporary=$(mktemp "${destination}.XXXXXX") || return 1
  if ! awk '
    /^Exec=\/usr\/bin\/google-chrome-stable([[:space:]]|$)/ {
      if ($0 !~ /--ozone-platform=/)
        sub(/^Exec=\/usr\/bin\/google-chrome-stable/, "& --ozone-platform=wayland")
      if ($0 !~ /TouchpadOverscrollHistoryNavigation/) {
        if (match($0, /--enable-features=[^[:space:]]+/))
          $0=substr($0,1,RSTART+RLENGTH-1) ",TouchpadOverscrollHistoryNavigation" substr($0,RSTART+RLENGTH)
        else
          sub(/^Exec=\/usr\/bin\/google-chrome-stable/, "& --enable-features=TouchpadOverscrollHistoryNavigation")
      }
    }
    {print}
  ' "$source" > "$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  if [[ -f "$destination" ]] && ! cmp -s "$temporary" "$destination"; then
    cp -p -- "$destination" "${destination}.backup-$(date +%Y%m%d-%H%M%S)" || {
      rm -f -- "$temporary"; return 1;
    }
  fi
  if ! chmod 644 "$temporary" || ! mv -f -- "$temporary" "$destination"; then
    rm -f -- "$temporary"
    return 1
  fi
}

set_media_defaults() {
  local mime actual failures=0
  for mime in "$@"; do
    # Native tools preserve unrelated Added/Removed Associations sections.
    xdg-mime default vlc.desktop "$mime" || true
    gio mime "$mime" vlc.desktop >/dev/null 2>&1 || true
    actual=$(xdg-mime query default "$mime") || actual=""
    if [[ "$actual" != vlc.desktop ]]; then
      warning "Could not confirm VLC as the default for $mime."
      failures=$((failures + 1))
    fi
  done
  [[ "$failures" -eq 0 ]]
}

apply_settings() {
  info "[SETTINGS] Applying GNOME settings and default apps"
  local warnings_before=$WARN_COUNT wallpaper_tmp
  local DESKTOP_SRC DESKTOP_DEST WALLPAPER_URL WALLPAPER_PATH
  local -a MEDIA_TYPES
  local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"

  if ! has_gui_session; then
    warning "No graphical session detected (no D-Bus session bus)."
    warning "Visual settings rely on gsettings/gio and must run inside your GNOME session."
    warning "Run option [8] from a terminal inside GNOME (not over SSH/TTY). Skipping."
    return 1
  fi

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
  if [[ -f /usr/share/applications/google-chrome.desktop ]]; then
    try xdg-settings set default-web-browser google-chrome.desktop
  else
    warning "Chrome is absent; keeping the current default browser."
  fi

  # ── Default media player: VLC ──
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

  if set_media_defaults "${MEDIA_TYPES[@]}"; then
    ok "VLC defaults confirmed for the requested media types."
  fi
  fi

  # Apply Wayland flags only in a Wayland session. Preserve existing launchers.
  if [[ "${XDG_SESSION_TYPE:-}" == wayland || -n "${WAYLAND_DISPLAY:-}" ]]; then
    step "Configuring Chrome for Wayland touchpad gestures"
    DESKTOP_SRC="/usr/share/applications/google-chrome.desktop"
    DESKTOP_DEST="$data_home/applications/google-chrome.desktop"
    if configure_chrome_launcher "$DESKTOP_SRC" "$DESKTOP_DEST"; then
      ok "Chrome launcher configured; existing arguments preserved."
    else
      warning "Chrome launcher configuration was not completed."
    fi
  fi

  # ── Wallpaper ──
  step "Downloading and applying wallpaper"
  WALLPAPER_URL="https://raw.githubusercontent.com/felipy2k/Fedora-Y2K/main/Y2K_Wallpaper.jpeg"
  WALLPAPER_PATH="$HOME/Pictures/Y2K_Wallpaper.jpeg"
  if mkdir -p "$HOME/Pictures" && wallpaper_tmp=$(mktemp "$HOME/Pictures/.y2k-wallpaper.XXXXXX"); then
    if curl --proto '=https' --proto-redir '=https' -fL --retry 2 \
        --connect-timeout 15 --max-time 180 "$WALLPAPER_URL" -o "$wallpaper_tmp" &&
        [[ -s "$wallpaper_tmp" ]] && mv -f -- "$wallpaper_tmp" "$WALLPAPER_PATH"; then
      if gsettings set org.gnome.desktop.background picture-uri "file://$WALLPAPER_PATH" &&
         gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALLPAPER_PATH" &&
         gsettings set org.gnome.desktop.background picture-options zoom; then
        ok "Wallpaper applied."
      else
        warning "Wallpaper downloaded, but desktop settings could not be applied."
      fi
    else
      rm -f -- "$wallpaper_tmp"
      warning "Wallpaper download failed; previous image preserved."
    fi
  else
    warning "Cannot create the wallpaper download file."
  fi

  if [[ "$WARN_COUNT" -eq "$warnings_before" ]]; then
    ok "Settings applied."
  else
    warning "Some settings could not be applied; review the messages above."
    return 1
  fi
}

# ─────────────────────────────────────────────
# FINAL VERIFICATION
# ─────────────────────────────────────────────
verify_final() {
  info "[VERIFICATION] Checking final system state"

  echo
  echo -e "${BOLD}── Packages that should have been REMOVED ──${NC}"
  REMOVED_CHECK=$(rpm -qa --qf '%{NAME}\n' | grep -E \
    "libreoffice|^showtime|^decibels|^totem|totem-video-thumbnailer|gnome-music|^rhythmbox|gnome-tour|gnome-weather|gnome-maps|^yelp|^dconf-editor|^htop|^piper|^gnome-terminal$|gnome-extensions-app" \
    2>/dev/null || true)
  if [[ -z "$REMOVED_CHECK" ]]; then
    ok "No unwanted packages found."
  else
    warning "Still present:"
    echo "$REMOVED_CHECK"
  fi

  echo
  echo -e "${BOLD}── Expected app inventory ──${NC}"
  verify_app_inventory

  echo
  echo -e "${BOLD}── Essential codecs ──${NC}"
  if rpm -q ffmpeg &>/dev/null && ! rpm -q ffmpeg-free &>/dev/null; then
    ok "Full ffmpeg installed (ffmpeg-free replaced)."
  else
    warning "Full ffmpeg is missing or ffmpeg-free remains installed."
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
  echo -e "${BOLD}── NVIDIA GPU ──${NC}"
  verify_nvidia

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

  # Authenticate sudo up front (and keep it alive) so the long install
  # never pauses for a password halfway through.
  ensure_sudo || { warning "Cannot proceed without sudo authentication."; return; }

  # Reset warning counter for clean final summary
  WARN_COUNT=0

  add_repos || return 1
  update_system || return 1
  try install_rpms    # Installs everything (including codecs)
  try install_freeoffice # FreeOffice before removing LibreOffice
  try install_flatpaks
  try install_nvidia auto
  try install_gnome_extensions
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
    note "Setup complete with $WARN_COUNT warning(s) — review the log above."
  fi
  echo "  Full log saved to: $LOG_FILE"
  echo -e "${YELLOW}⚠ Reboot the system to activate all drivers and settings.${NC}"
  [[ "$WARN_COUNT" -eq 0 ]]
}

# ─────────────────────────────────────────────
# MAIN LOOP
# ─────────────────────────────────────────────
while true; do
  show_menu || break

  case "$CHOICE" in
    1) run_all ;;
    2) ensure_sudo && { protect_cuda_driver_packages && update_system; } ;;
    3) ensure_sudo && remove_bloat ;;
    4) ensure_sudo && {
      if add_repos; then
        rpm_status=0
        install_rpms || rpm_status=1
        install_freeoffice || rpm_status=1
        [[ "$rpm_status" -eq 0 ]]
      else
        false
      fi
    } ;;
    5) install_flatpaks ;;
    6) ensure_sudo && install_nvidia manual ;;
    7) install_gnome_extensions ;;
    8) apply_settings ;;
    0) echo "Exiting."; exit 0 ;;
    r|R) echo "Rebooting..."; sudo reboot ;;
    *) warning "Invalid option." ;;
  esac

  action_status=$?
  if [[ "$action_status" -ne 0 ]]; then
    warning "Option $CHOICE finished with errors (status $action_status). Review: $LOG_FILE"
  fi
  echo
  read -rp "Press ENTER to return to the menu..." _ || break
done
