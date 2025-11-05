#!/usr/bin/env bash

set -euo pipefail

MOUNT_POINT="/mnt/pi-boot"
ROOT_MOUNT="/mnt/pi-root"
SUMMARY=""

# helper
err() { echo "ERROR: $*" >&2; }
info() { echo "$*"; }

### ---- Detect partitions ----
info "Searching for Raspberry Pi SD card boot partition..."
BOOT_PART=$(lsblk -rno NAME,FSTYPE | awk '$2 ~ /vfat|FAT/ {print "/dev/"$1; exit}' || true)
ROOT_PART=$(lsblk -rno NAME,FSTYPE | awk '$2 ~ /ext4/ {print "/dev/"$1; exit}' || true)

if [ -z "${BOOT_PART:-}" ]; then
  err "No boot partition found. Insert the SD card and try again."
  exit 1
fi

sudo mkdir -p "$MOUNT_POINT" "$ROOT_MOUNT"
info "Mounting $BOOT_PART -> $MOUNT_POINT"
sudo mount "$BOOT_PART" "$MOUNT_POINT"
if [ -n "${ROOT_PART:-}" ]; then
  info "Mounting $ROOT_PART -> $ROOT_MOUNT"
  sudo mount "$ROOT_PART" "$ROOT_MOUNT" || true
fi

echo
echo "Current configuration on the SD-card:"
[ -f "$MOUNT_POINT/ssh" ] && echo "  - ssh: already enabled" || echo "  - ssh: currently disabled"
[ -f "$MOUNT_POINT/wpa_supplicant.conf" ] && echo "  - wpa_supplicant.conf: present" || echo "  - wpa_supplicant.conf: not present"

### ---- Enable SSH ----
read -p "Enable SSH on first boot? (Y/n, default Y): " ENABLE_SSH
ENABLE_SSH=${ENABLE_SSH:-Y}
if [[ "$ENABLE_SSH" =~ ^[Yy] ]]; then
  sudo touch "$MOUNT_POINT/ssh"
  SUMMARY+="\nSSH: Enabled"
  info "ssh file created in boot partition."
else
  sudo rm -f "$MOUNT_POINT/ssh"
  SUMMARY+="\nSSH: Disabled"
  info "SSH will be disabled on first boot."
fi

### ---- Ethernet static or dynamic ----
echo
read -p "Should Ethernet (eth0) use a static IP or dynamic (DHCP)? (static/dynamic, default dynamic): " ETH_CHOICE
ETH_CHOICE=${ETH_CHOICE:-dynamic}

if [[ "$ETH_CHOICE" == "static" ]]; then
  read -p "   Desired static Ethernet IP (e.g. 192.168.50.10): " ETH_IP
  read -p "   Gateway (default 192.168.50.1): " ETH_GW
  ETH_GW=${ETH_GW:-192.168.50.1}
  read -p "   DNS servers (space-separated, default 1.1.1.1 8.8.8.8): " ETH_DNS
  ETH_DNS=${ETH_DNS:-"1.1.1.1 8.8.8.8"}

  info "Checking whether $ETH_IP responds to ping..."
  if ping -c1 -W1 "$ETH_IP" >/dev/null 2>&1; then
    err "IP $ETH_IP appears to be in use (responded to ping). Choose another IP or set DHCP."
    SUMMARY+="\nEthernet: static ($ETH_IP) - conflict detected (skipped)"
    ETH_SET=false
  else
    ETH_SET=true
    if [ -x "$ROOT_MOUNT/usr/bin/nmcli" ]; then
      info "NetworkManager detected in rootfs — adding first-boot service to set eth static via nmcli."
      sudo bash -c "cat > $ROOT_MOUNT/etc/systemd/system/set-eth-static.service <<'EOF'
[Unit]
Description=Set static IPv4 for eth0 via NetworkManager on first boot
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/nmcli connection show --active | /bin/grep -q eth0 && true || true
ExecStart=/usr/bin/nmcli connection modify 'Wired connection 1' ipv4.addresses ${ETH_IP}/24 || true
ExecStart=/usr/bin/nmcli connection modify 'Wired connection 1' ipv4.gateway ${ETH_GW} || true
ExecStart=/usr/bin/nmcli connection modify 'Wired connection 1' ipv4.dns \"${ETH_DNS}\" || true
ExecStart=/usr/bin/nmcli connection modify 'Wired connection 1' ipv4.method manual || true
ExecStart=/usr/bin/nmcli connection up 'Wired connection 1' || true
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF"
      sudo chroot "$ROOT_MOUNT" systemctl enable set-eth-static.service 2>/dev/null || true
      SUMMARY+="\nEthernet: static ($ETH_IP) via NetworkManager service (first-boot)"
    else
      # fallback to dhcpcd.conf
      info "No NetworkManager in rootfs — appending to /etc/dhcpcd.conf"
      sudo bash -c "cat >> $ROOT_MOUNT/etc/dhcpcd.conf <<EOF

# Added by rpi_setup.sh - static eth0
interface eth0
static ip_address=${ETH_IP}/24
static routers=${ETH_GW}
static domain_name_servers=${ETH_DNS}
EOF"
      SUMMARY+="\nEthernet: static ($ETH_IP) via dhcpcd.conf"
    fi
  fi
else
  SUMMARY+="\nEthernet: dynamic (DHCP)"
  ETH_SET=false
fi


info
info "Setting default 'pi' user with password 'raspberry' (userconf.txt)..."
HASH_PI=$(openssl passwd -6 "raspberry")
echo "pi:$HASH_PI" | sudo tee "$MOUNT_POINT/userconf.txt" >/dev/null
SUMMARY+="\nUser: pi (password: raspberry)"

echo
read -p "Would you like to create an additional user on first boot? (y/n, default n): " CREATE_EXTRA
CREATE_EXTRA=${CREATE_EXTRA:-n}
if [[ "$CREATE_EXTRA" =~ ^[Yy] ]]; then
  read -p "   Enter new username (no spaces): " EXTRA_USER
  if [[ -z "$EXTRA_USER" ]]; then
    err "No username entered — skipping extra user creation."
    SUMMARY+="\nExtra user: none"
  else
    read -s -p "   Enter password for $EXTRA_USER: " EXTRA_PASS; echo
    read -s -p "   Confirm password: " EXTRA_PASS2; echo
    if [[ "$EXTRA_PASS" != "$EXTRA_PASS2" ]]; then
      err "Passwords do not match — skipping extra user creation."
      SUMMARY+="\nExtra user: skipped (password mismatch)"
    else
      if [ -d "$ROOT_MOUNT/etc" ]; then
        info "Creating first-boot script to add user $EXTRA_USER..."
        sudo bash -c "cat > $ROOT_MOUNT/usr/local/sbin/create-extra-user.sh <<'EOF'
#!/bin/bash
# create-extra-user.sh - run at first boot to add an extra user
set -e
USERNAME='${EXTRA_USER}'
PASSWORD='${EXTRA_PASS}'
if ! id \"\$USERNAME\" >/dev/null 2>&1; then
  useradd -m -s /bin/bash \"\$USERNAME\"
  echo \"\$USERNAME:\$PASSWORD\" | chpasswd
  usermod -aG sudo \"\$USERNAME\"
fi
# remove this script afterwards
rm -f /usr/local/sbin/create-extra-user.sh
EOF"
        sudo chmod +x "$ROOT_MOUNT/usr/local/sbin/create-extra-user.sh"
        sudo bash -c "cat > $ROOT_MOUNT/etc/systemd/system/create-extra-user.service <<'EOF'
[Unit]
Description=Create extra user on first boot
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/create-extra-user.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF"
        sudo chroot "$ROOT_MOUNT" systemctl enable create-extra-user.service 2>/dev/null || true
        SUMMARY+="\nExtra user: $EXTRA_USER (created on first boot)"
      else
        err "Root partition not mounted — cannot create extra-user service."
        SUMMARY+="\nExtra user: failed (root not mounted)"
      fi
    fi
  fi
else
  SUMMARY+="\nExtra user: none"
fi

echo
echo "===================================="
echo "SD card prepared. Next steps:"
echo "  1) Unmount the SD card from this machine (if not already)."
echo "  2) Insert SD into Raspberry Pi and power it on."
echo "===================================="
echo

read -p "Unmount the SD card now? (Y/n, default Y): " DO_UM
DO_UM=${DO_UM:-Y}
if [[ "$DO_UM" =~ ^[Yy] ]]; then
  sudo umount "$MOUNT_POINT" || true
  sudo umount "$ROOT_MOUNT" || true
  info "SD card unmounted. Insert into Raspberry Pi and power it on."
else
  info "SD card remains mounted. Make sure to unmount before removing."
fi

echo
if [[ "$ETH_CHOICE" == "static" && "$ETH_SET" == true ]]; then
  echo "Since you chose a static Ethernet IP ($ETH_IP), once the Pi is powered you can SSH to it."
  read -p "Do you want the script to attempt to SSH now to ${ETH_IP}? (y/n): " DO_SSH
  if [[ "$DO_SSH" =~ ^[Yy]$ ]]; then
    read -p "SSH username (default 'pi'): " SSH_USER
    SSH_USER=${SSH_USER:-pi}
    info "Attempting to connect: ssh ${SSH_USER}@${ETH_IP}"
    echo "If SSH hangs, press Ctrl+C and try later."
    ssh "${SSH_USER}@${ETH_IP}" || {
      err "SSH attempt failed or was interrupted. You can retry manually: ssh ${SSH_USER}@${ETH_IP}"
    }
  else
    info "Skipping SSH attempt. You can connect after boot: ssh pi@${ETH_IP}"
  fi

else
  read -p "ETH set to dynamic or static was skipped. Would you like to scan the network to find the Pi? (y/n): " DO_SCAN
  DO_SCAN=${DO_SCAN:-n}
  if [[ "$DO_SCAN" =~ ^[Yy]$ ]]; then
    if ! command -v nmap >/dev/null 2>&1; then
      err "nmap is not installed on this machine. Install it (sudo apt install nmap) and re-run the scan."
    else
      read -p "Enter subnet to scan (default 192.168.50.0/24): " SUBNET
      SUBNET=${SUBNET:-192.168.50.0/24}
      echo "Scanning ${SUBNET} every 8s until a Raspberry Pi is found (Ctrl+C to cancel)..."
      while true; do
        FOUND=$(sudo nmap -sn "$SUBNET" 2>/dev/null | grep -iE "Raspberry Pi Trading|Raspberry Pi Foundation" || true)
        if [[ -n "$FOUND" ]]; then
          echo "🍓 Raspberry Pi detected on the network:"
          sudo nmap -sn "$SUBNET" | awk '
            /Nmap scan report/ {ip=$5; name=$4; next}
            /MAC Address/ {
              mac=$3; vendor=$0;
              if ($0 ~ /Raspberry Pi Trading|Raspberry Pi Foundation/) {
                printf("  Raspberry Pi: %s (%s) [%s]\n", name, ip, mac);
              }
            }'
          break
        else
          echo "No Raspberry Pi found yet — retrying in 8s..."
          sleep 8
        fi
      done
    fi
  else
    info "Skipping network scan."
  fi
fi


echo
echo "====== SUMMARY ======"
echo -e "$SUMMARY"
echo "====================================="
echo "Notes:"
echo " - Default user 'pi' with password 'raspberry' will be created (userconf.txt)."
echo " - Extra user (if configured) will be created on first boot."
echo " - If you created NetworkManager first-boot services they will run the first time the Pi boots and then remain enabled."
echo " - To re-enable Wi-Fi (if you blocked it earlier) on the Pi: sudo rfkill unblock wifi"
echo
info "Setup script finished."
