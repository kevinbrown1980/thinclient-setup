#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Debian → Remmina thin-client master installer
# - Prompts technician for Windows VM IP, username, password
# - Creates kiosk-style Remmina (fullscreen, no top toolbar)
# - Sets LightDM autologin for 'thinclient'
# - Disables sleep/lock/DPMS/screensaver
# ============================================================

# ---- Defaults (all installs use 'thinclient' per your requirement) ----
LOCAL_USER="thinclient"
PROFILE_NAME="Windows-11-VDI"
PROFILE_FILE_NAME="win11-vdi"   # results in win11-vdi.remmina
REM_PROTOCOL="RDP"

# ---- Helpers ----
need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root (sudo bash $0)"; exit 1
  fi
}

user_home() {
  getent passwd "$1" | cut -d: -f6
}

ensure_user_exists() {
  local u="$1"
  if ! id "$u" &>/dev/null; then
    echo "Local user '$u' not found. Creating with password 'thinclient'..."
    useradd -m -s /bin/bash "$u"
    echo "$u:thinclient" | chpasswd
  fi
}

pkg_install() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update

  # Preseed LightDM as the default display manager to avoid interactive prompt
  echo "lightdm shared/default-x-display-manager select lightdm" | debconf-set-selections || true

  apt-get install -y --no-install-recommends \
    remmina remmina-plugin-rdp \
    x11-xserver-utils \
    lightdm lxde-core lxsession
}

add_line_once() {
  local line="$1" file="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  grep -qxF "$line" "$file" || echo "$line" >> "$file"
}

write_file() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "$path")"
  printf "%s" "$content" > "$path"
}

mask_sleeps() {
  systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target || true
}

remove_xscreensaver() {
  if dpkg -s xscreensaver >/dev/null 2>&1; then
    apt-get remove -y xscreensaver || true
  fi
}

# ---- Start ----
need_root
ensure_user_exists "$LOCAL_USER"

# Prompt technician for Windows VM details
echo "Please enter the Windows VM connection details:"
read -rp "  VM IP/Hostname: " RDP_SERVER
read -rp "  Windows Username: " RDP_USER
read -rsp "  Windows Password (hidden): " RDP_PASS; echo
read -rp "  RDP Domain (optional, press Enter to skip): " RDP_DOMAIN

USER_HOME_DIR="$(user_home "$LOCAL_USER")"
if [[ -z "${USER_HOME_DIR}" || ! -d "${USER_HOME_DIR}" ]]; then
  echo "Could not determine home for user '$LOCAL_USER'"; exit 1
fi

echo "Installing packages (Remmina, LightDM, LXDE)…"
pkg_install

# --- LightDM: autologin + no lock/DPMS ---
echo "Configuring LightDM autologin and no-DPMS…"
mkdir -p /etc/lightdm/lightdm.conf.d
write_file /etc/lightdm/lightdm.conf.d/10-autologin.conf "\
[Seat:*]
autologin-user=${LOCAL_USER}
autologin-user-timeout=0
"
write_file /etc/lightdm/lightdm.conf.d/10-nolock.conf "\
[Seat:*]
xserver-command=X -s 0 -dpms
"

# --- Disable sleep/blank/suspend ---
echo "Disabling sleep/blank/suspend/DPMS…"
mask_sleeps
remove_xscreensaver

# --- LXDE autostart: prevent blanking + launch Remmina profile ---
AUTOSTART_FILE="${USER_HOME_DIR}/.config/lxsession/LXDE/autostart"
add_line_once "@xset s off"      "$AUTOSTART_FILE"
add_line_once "@xset s noblank"  "$AUTOSTART_FILE"
add_line_once "@xset -dpms"      "$AUTOSTART_FILE"
add_line_once "@xset dpms 0 0 0" "$AUTOSTART_FILE"

# --- Remmina global preferences (fullscreen + hide fullscreen toolbar) ---
REM_PREF_DIR="${USER_HOME_DIR}/.config/remmina"
REM_PREF_FILE="${REM_PREF_DIR}/remmina.pref"
mkdir -p "$REM_PREF_DIR"
if [[ -f "$REM_PREF_FILE" ]]; then
  grep -q "^\[remmina_pref\]" "$REM_PREF_FILE" || sed -i '1i[remmina_pref]' "$REM_PREF_FILE"
  # Ensure the keys exist with desired values (idempotent)
  sed -i \
    -e 's/^save_view_mode=.*/save_view_mode=true/g' \
    -e 's/^default_mode=.*/default_mode=3/g' \
    -e 's/^fullscreen_toolbar_visibility=.*/fullscreen_toolbar_visibility=2/g' \
    -e 's/^hide_toolbar=.*/hide_toolbar=true/g' \
    "$REM_PREF_FILE" || true

  add_line_once "save_view_mode=true" "$REM_PREF_FILE"
  add_line_once "default_mode=3" "$REM_PREF_FILE"
  add_line_once "fullscreen_toolbar_visibility=2" "$REM_PREF_FILE"
  add_line_once "hide_toolbar=true" "$REM_PREF_FILE"
else
  write_file "$REM_PREF_FILE" "\
[remmina_pref]
save_view_mode=true
default_mode=3
fullscreen_toolbar_visibility=2
hide_toolbar=true
"
fi

# --- Build the .remmina profile with provided VM details ---
REM_DATA_DIR="${USER_HOME_DIR}/.local/share/remmina"
mkdir -p "$REM_DATA_DIR"
PROFILE_PATH="${REM_DATA_DIR}/${PROFILE_FILE_NAME}.remmina"

if [[ -n "${RDP_DOMAIN:-}" ]]; then
  DOMAIN_LINE="domain=${RDP_DOMAIN}"
else
  DOMAIN_LINE=""
fi

# WARNING: By design for kiosk usage, the password is stored in plaintext here.
PROFILE_CONTENT=$(cat <<EOF
[remmina]
name=${PROFILE_NAME}
protocol=${REM_PROTOCOL}
server=${RDP_SERVER}
username=${RDP_USER}
${DOMAIN_LINE}
password=${RDP_PASS}
# Display/behavior
viewmode=3                 # fullscreen
resolution_mode=0          # dynamic client-side/no fixed resolution
disableclipboard=0
sound=on
security=negotiate         # works with modern NLA/TLS
EOF
)
write_file "$PROFILE_PATH" "$PROFILE_CONTENT"
chmod 600 "$PROFILE_PATH"

# --- Auto-start the profile at login ---
add_line_once "@remmina -c ${PROFILE_PATH}" "$AUTOSTART_FILE"

# --- Ownership ---
chown -R "${LOCAL_USER}:${LOCAL_USER}" \
  "${USER_HOME_DIR}/.config" \
  "${USER_HOME_DIR}/.local"

# --- Summary ---
echo
echo "===================================================="
echo " Thin client setup complete for user: ${LOCAL_USER}"
echo "  - Remmina profile:  ${PROFILE_PATH}"
echo "  - Autostart file:   ${AUTOSTART_FILE}"
echo "  - LightDM configs:  /etc/lightdm/lightdm.conf.d/10-*.conf"
echo "===================================================="
echo "Reboot now to test (y/n)?"
read -r yn
if [[ "${yn,,}" == "y" ]]; then
  systemctl reboot
else
  echo "You can reboot later with: sudo reboot"
fi
