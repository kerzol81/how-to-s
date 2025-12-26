#!/usr/bin/env bash
set -euo pipefail

# KZ 26.12.2025.
# ------------------------------------------------------------------
# This installer sets up a systemd .path + .service pair that moves
# newly created .torrent files from:
#   /home/kerenyiz/Downloads
# to:
#   /home/kerenyiz/synology/TORRENTS
#
# How detection works:
# - systemd .path units use the Linux kernel inotify API
# - the kernel reports filesystem events (create, rename, write-close)
# - there is NO polling or periodic checking
# - reaction time is typically milliseconds
#
# Why PathModified is used:
# - browsers often create a temp file and rename it when finished
# - the rename triggers a directory modification event
#
# When triggered:
# - systemd starts a oneshot service
# - the service finds all *.torrent files and moves them
# - mv -n prevents overwriting existing files
# ------------------------------------------------------------------

SERVICE_NAME="move-torrents"
SYSTEMD_DIR="/etc/systemd/system"

SOURCE_DIR="/home/kerenyiz/Downloads"
DEST_DIR="/home/kerenyiz/synology/TORRENTS"

SERVICE_FILE="${SYSTEMD_DIR}/${SERVICE_NAME}.service"
PATH_FILE="${SYSTEMD_DIR}/${SERVICE_NAME}.path"

# ------------------------------------------------------------------
# Checks
# ------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
  echo "[-] Please run this installer as root (use sudo)"
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "[-] Source directory does not exist: $SOURCE_DIR"
  exit 1
fi

if [[ ! -d "$DEST_DIR" ]]; then
  echo "[-] Destination directory does not exist: $DEST_DIR"
  exit 1
fi

echo "[+] Paths verified"

# ------------------------------------------------------------------
# Install systemd service unit
# ------------------------------------------------------------------

echo "[*] Installing systemd service unit..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Move newly created torrent files

[Service]
Type=oneshot
ExecStart=/usr/bin/find $SOURCE_DIR -maxdepth 1 -type f -name '*.torrent' -exec mv -n {} $DEST_DIR/ \\;
EOF

# ------------------------------------------------------------------
# Install systemd path unit
# ------------------------------------------------------------------

echo "[*] Installing systemd path unit..."

cat > "$PATH_FILE" <<EOF
[Unit]
Description=Watch Downloads directory for new torrent files

[Path]
PathModified=$SOURCE_DIR
Unit=$SERVICE_NAME.service

[Install]
WantedBy=default.target
EOF

# ------------------------------------------------------------------
# Reload and enable
# ------------------------------------------------------------------

echo "[*] Reloading systemd..."
systemctl daemon-reexec
systemctl daemon-reload

echo "[*] Enabling and starting watcher..."
systemctl enable --now "$SERVICE_NAME.path"

echo
echo "[+] Installation complete"
echo "[*] Watching: $SOURCE_DIR"
echo "[*] Moving to: $DEST_DIR"
echo
echo "[*] Check status with:"
echo "    systemctl status $SERVICE_NAME.path"
