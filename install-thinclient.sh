sudo tee /usr/local/sbin/install-thinclient.sh >/dev/null <<'EOF'
#!/bin/sh
#
# install-thinclient.sh — Configure Debian with LXDE + SSH on a clean install.
# POSIX /bin/sh, no bashisms. Works on Debian 12+.

set -eu
export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -y"

log() { printf "\033[1;32m[+]\033[0m %s\n" "$*"; }
fail() { printf "\033[1;31m[!]\033[0m %s\n" "$*" >&2; exit 1; }

require_root() { [ "$(id -u)" -eq 0 ] || fail "Run as root (sudo)."; }

detect_debian() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    [ "$ID" = "debian" ] || fail "This script is for Debian; detected ID='$ID'."
    log "Detected Debian $VERSION_CODENAME ($VERSION)"
  else
    fail "/etc/os-release not found; cannot verify Debian."
  fi
}

require_root
detect_debian

log "Updating package index and upgrading base system…"
apt-get update
apt-get dist-upgrade -y

log "Installing X.Org, LightDM, LXDE core, NetworkManager, and OpenSSH…"
apt-get install $APT_OPTS \
  xorg lightdm lightdm-gtk-greeter lxde-core \
  network-manager \
  openssh-server

# If you prefer the full LXDE task (more packages), use:
# apt-get install $APT_OPTS task-lxde-desktop openssh-server

log "Enabling LightDM and SSH services…"
systemctl enable lightdm
systemctl enable ssh
systemctl restart ssh || true

# SSH password auth (set to 'no' if you want key-only):
log "Ensuring SSH allows password login (adjust to 'no' if desired)…"
SSH_CFG="/etc/ssh/sshd_config"
if grep -qE '^\s*PasswordAuthentication' "$SSH_CFG"; then
  sed -i 's/^\s*PasswordAuthentication\s\+.*/PasswordAuthentication yes/' "$SSH_CFG"
else
  printf "\nPasswordAuthentication yes\n" >> "$SSH_CFG"
fi
systemctl reload ssh || true

# Optional: create an admin user (uncomment and customize):
# NEW_USER="kevin"
# NEW_PW="changeme"
# if ! id "$NEW_USER" >/dev/null 2>&1; then
#   log "Creating user '$NEW_USER' and adding to sudo and netdev groups…"
#   apt-get install $APT_OPTS sudo
#   useradd -m -s /bin/bash -G sudo,netdev "$NEW_USER"
#   echo "$NEW_USER:$NEW_PW" | chpasswd
# fi

log "Done. Reboot recommended if kernel/display stack was updated (sudo reboot)."
EOF
sudo chmod +x /usr/local/sbin/install-thinclient.sh
