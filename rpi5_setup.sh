#!/usr/bin/env bash
# KerZol 05.11.2025
set -e

MOUNT_POINT="/mnt/pi-boot"
ROOT_MOUNT="/mnt/pi-root"
SUMMARY=""

echo "Searching for Raspberry Pi SD card..."
BOOT_PART=$(lsblk -rno NAME,FSTYPE | awk '$2 ~ /vfat|FAT/ {print "/dev/"$1; exit}')
ROOT_PART=$(lsblk -rno NAME,FSTYPE | awk '$2 ~ /ext4/ {print "/dev/"$1; exit}')
[ -z "$BOOT_PART" ] && { echo "No boot partition found."; exit 1; }

sudo mkdir -p "$MOUNT_POINT" "$ROOT_MOUNT"
sudo mount "$BOOT_PART" "$MOUNT_POINT"
[ -n "$ROOT_PART" ] && sudo mount "$ROOT_PART" "$ROOT_MOUNT" || true

echo
echo "Current configuration:"
[ -f "$MOUNT_POINT/ssh" ] && echo "SSH enabled" || echo "SSH disabled"
[ -f "$MOUNT_POINT/wpa_supplicant.conf" ] && grep -E 'ssid=' "$MOUNT_POINT/wpa_supplicant.conf" || echo "No Wi-Fi config"

read -p "Enable SSH? (y/n, blank = keep): " ENABLE_SSH
case "$ENABLE_SSH" in
  [Yy]*) sudo touch "$MOUNT_POINT/ssh"; SUMMARY+="\nSSH: Enabled";;
  [Nn]*) sudo rm -f "$MOUNT_POINT/ssh"; SUMMARY+="\nSSH: Disabled";;
  *) SUMMARY+="\nSSH: unchanged";;
esac

echo
read -p "Configure Wi-Fi? (y/n): " CHANGE_WIFI
if [[ "$CHANGE_WIFI" =~ ^[Yy]$ ]]; then
  command -v nmcli >/dev/null && sudo nmcli dev wifi list | awk 'NR==1 || /([2-5]G)/{print}'
  echo
  read -p "   SSID: " WIFI_SSID
  read -s -p "   Password: " WIFI_PASS; echo
  read -p "   Country code (e.g. GB, DE, FR, HU): " COUNTRY
  echo "Writing Wi-Fi config..."
  cat <<EOF | sudo tee "$MOUNT_POINT/wpa_supplicant.conf" >/dev/null
country=$COUNTRY
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
network={
    ssid="$WIFI_SSID"
    psk="$WIFI_PASS"
    key_mgmt=WPA-PSK
}
EOF
  SUMMARY+="\nWi-Fi: $WIFI_SSID ($COUNTRY)"

  ### --- Wi-Fi static or dynamic ---
  echo
  read -p "Should Wi-Fi use a static IP? (y/n): " WIFI_STATIC
  if [[ "$WIFI_STATIC" =~ ^[Yy]$ && -d "$ROOT_MOUNT/etc" ]]; then
      read -p "   Static Wi-Fi IP (default 192.168.50.20): " WIFI_IP
      WIFI_IP=${WIFI_IP:-192.168.50.20}
      read -p "   Gateway (default 192.168.50.1): " WIFI_GW
      WIFI_GW=${WIFI_GW:-192.168.50.1}
      read -p "   DNS (default 1.1.1.1 8.8.8.8): " WIFI_DNS
      WIFI_DNS=${WIFI_DNS:-"1.1.1.1 8.8.8.8"}

      if ping -c1 -W1 "$WIFI_IP" >/dev/null 2>&1; then
          echo "$WIFI_IP already in use. Skipping static Wi-Fi IP."
          SUMMARY+="\nWi-Fi IP: conflict detected"
      else
          if [ -x "$ROOT_MOUNT/usr/bin/nmcli" ]; then
              echo "NetworkManager detected – creating first-boot static IP service..."
              sudo bash -c "cat <<EOF > $ROOT_MOUNT/etc/systemd/system/set-wifi-static.service
[Unit]
Description=Configure static Wi-Fi via NetworkManager
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/nmcli connection modify \"$WIFI_SSID\" ipv4.addresses $WIFI_IP/24
ExecStart=/usr/bin/nmcli connection modify \"$WIFI_SSID\" ipv4.gateway $WIFI_GW
ExecStart=/usr/bin/nmcli connection modify \"$WIFI_SSID\" ipv4.dns \"$WIFI_DNS\"
ExecStart=/usr/bin/nmcli connection modify \"$WIFI_SSID\" ipv4.method manual
ExecStart=/usr/bin/nmcli connection up \"$WIFI_SSID\"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF"
              sudo chroot "$ROOT_MOUNT" systemctl enable set-wifi-static.service 2>/dev/null || true
              SUMMARY+="\nWi-Fi static IP ($WIFI_IP) via NetworkManager"
          else
              echo "No NetworkManager found – falling back to dhcpcd.conf"
              cat <<EOF | sudo tee -a "$ROOT_MOUNT/etc/dhcpcd.conf" >/dev/null

# Static Wi-Fi added by rpi_setup.sh
interface wlan0
static ip_address=$WIFI_IP/24
static routers=$WIFI_GW
static domain_name_servers=$WIFI_DNS
EOF
              SUMMARY+="\nWi-Fi static IP ($WIFI_IP) via dhcpcd"
          fi
      fi
  else
      SUMMARY+="\nWi-Fi IP: dynamic (DHCP)"
  fi

  ### --- Auto-set Wi-Fi country ---
  if [ -d "$ROOT_MOUNT/etc" ]; then
    echo "Adding first-boot Wi-Fi country fix..."
    sudo bash -c "cat <<'EOF' > $ROOT_MOUNT/etc/systemd/system/set-wifi-country.service
[Unit]
Description=Set Wi-Fi country to unblock WLAN
After=network-pre.target
Before=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/raspi-config nonint do_wifi_country $COUNTRY
ExecStartPost=/usr/sbin/rfkill unblock wifi
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF"
    sudo chroot "$ROOT_MOUNT" systemctl enable set-wifi-country.service 2>/dev/null || true
    SUMMARY+="\nWi-Fi country: $COUNTRY (auto-set on first boot)"
  fi
else
  SUMMARY+="\nWi-Fi: unchanged"
fi

### --- Default user ---
echo
HASH=$(openssl passwd -6 "raspberry")
echo "pi:$HASH" | sudo tee "$MOUNT_POINT/userconf.txt" >/dev/null
SUMMARY+="\nUser: pi / raspberry"

echo
read -p "Set a static IP for eth0? (y/n): " ETH_STATIC
if [[ "$ETH_STATIC" =~ ^[Yy]$ && -d "$ROOT_MOUNT/etc" ]]; then
  read -p "   Static Ethernet IP (default 192.168.50.10): " ETH_IP
  ETH_IP=${ETH_IP:-192.168.50.10}
  read -p "   Gateway (default 192.168.50.1): " ETH_GW
  ETH_GW=${ETH_GW:-192.168.50.1}
  read -p "   DNS (default 1.1.1.1): " ETH_DNS
  ETH_DNS=${ETH_DNS:-1.1.1.1}
  if ping -c1 -W1 "$ETH_IP" >/dev/null 2>&1; then
      echo "$ETH_IP already in use. Skipping Ethernet static IP."
      SUMMARY+="\nEthernet IP: conflict detected"
  else
      cat <<EOF | sudo tee -a "$ROOT_MOUNT/etc/dhcpcd.conf" >/dev/null

# Static Ethernet added by rpi_setup.sh
interface eth0
static ip_address=$ETH_IP/24
static routers=$ETH_GW
static domain_name_servers=$ETH_DNS
EOF
      SUMMARY+="\nEthernet static IP: $ETH_IP"
  fi
else
  SUMMARY+="\nEthernet IP: dynamic (DHCP)"
fi

echo
read -p "Unmount and finish? (y/n): " UNMOUNT
if [[ "$UNMOUNT" =~ ^[Yy]$ ]]; then
  sudo umount "$MOUNT_POINT" || true
  sudo umount "$ROOT_MOUNT" || true
  echo "SD card ready to boot."
else
  echo "Remember to unmount manually: sudo umount $MOUNT_POINT && sudo umount $ROOT_MOUNT"
fi

echo
echo "====== CONFIGURATION SUMMARY ======"
echo -e "$SUMMARY"
echo "====================================="
echo "Insert the SD card into your Raspberry Pi and power it on."
echo "   Wi-Fi static IP and country will be applied automatically on first boot."
echo

read -p "Would you like to run an Nmap network scan to find your Raspberry Pi? (y/n): " RUN_NMAP
if [[ "$RUN_NMAP" =~ ^[Yy]$ ]]; then
  if ! command -v nmap >/dev/null 2>&1; then
      echo "Nmap not found. Install it with: sudo apt install nmap"
  else
      read -p "   Enter subnet to scan (default 192.168.50.0/24): " SUBNET
      SUBNET=${SUBNET:-192.168.50.0/24}
      echo "Scanning your network for Raspberry Pi devices..."
      sudo nmap -sn "$SUBNET" | grep -E "Nmap scan report|MAC Address"
      echo "Scan complete."
  fi
else
  echo "Skipping network scan."
fi
