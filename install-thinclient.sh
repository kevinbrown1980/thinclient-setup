sudo tee /usr/local/sbin/setup-lxde-ssh.sh >/dev/null <<'EOF'
#!/bin/sh
# setup-lxde-ssh.sh — Configure Debian with LXDE + SSH on a clean install.
# POSIX /bin/sh; no bashisms. Works on Debian 12+.

set -eu
export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -y"

log() { printf "\033[1;32m[+]\033[0m %s\n" "$*"; }
fail() { printf "\033[1;31m[!]\033[0m %s\n" "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Run as root (sudo)."

# Sanity check: Debian
if [ -r /etc/os-release ]; then
  . /etc/os-release
  [ "${ID:-}" = "debian" ] || fail "This script is for Debian (detected: ${ID:-unknown})."
else
  fail "/etc/os-release not found; cannot verify Debian."
fi

log "Updating package index and upgrading base system…"
apt-get update
apt-get dist-upgrade -y

log "Installing LXDE desktop (task), OpenSSH server, and essentials…"
# task-lxde-desktop = full LXDE task (drivers, fonts, helpers)
apt-get install $APT_OPTS task-lxde-desktop openssh-server

log "Enabling LightDM display manager and SSH at boot…"
systemctl enable lightdm
systemctl enable ssh
systemctl restart ssh || true

# SSH policy: allow password logins (switch to 'no' later for key-only)
log "Ensuring SSH allows password login (adjust to 'no' if you prefer keys only)…"
SSH_CFG="/etc/ssh/sshd_config"
if grep -qE '^\s*PasswordAuthentication' "$SSH_CFG"; then
  sed -i 's/^\s*PasswordAuthentication\s\+.*/PasswordAuthentication yes/' "$SSH_CFG"
else
  printf "\nPasswordAuthentication yes\n" >> "$SSH_CFG"
fi
systemctl reload ssh || true

log "All done. A reboot is recommended if the kernel or display stack was updated."
log "Run: sudo reboot"
EOF

sudo chmod +x /usr/local/sbin/setup-lxde-ssh.sh
sudo /usr/local/sbin/setup-lxde-ssh.sh
