#!/bin/bash

set -e

# Dynamically get the username (prefer SUDO_USER, fallback to whoami)
USERNAME="${SUDO_USER:-$(whoami)}"
USERHOME="$(eval echo ~${USERNAME})"

# Save settings and log actions
SETTINGS_FILE="$USERHOME/pispot/settings.txt"
LOG_FILE="$USERHOME/pispot/setup.log"
mkdir -p "$USERHOME/pispot"

# Unblock Wi-Fi and set country code early to avoid rfkill issues
sudo rfkill unblock wifi
sudo raspi-config nonint do_wifi_country US
sudo sed -i '/^country=/d' /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null || true
echo "country=US" | sudo tee -a /etc/wpa_supplicant/wpa_supplicant.conf

# Define log and save_setting functions EARLY so they're available for all uses
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

save_setting() {
    echo "$1" >> "$SETTINGS_FILE"
}

# Clear previous settings/log
: > "$SETTINGS_FILE"
: > "$LOG_FILE"

# --- RESET EVERYTHING SECTION ---
echo "==== PiSpot: Resetting all previous configuration ===="
# Stop and purge nginx and hostapd if present
sudo systemctl stop nginx || true
sudo systemctl stop hostapd || true
sudo apt-get purge -y nginx nginx-common hostapd || true
sudo apt-get autoremove -y || true

# Remove config files and scripts
sudo rm -f /etc/hostapd/hostapd.conf
sudo rm -f /etc/rc.local
sudo rm -f /usb_drive.img
sudo rm -f /var/www/html/pispot.html
sudo rm -f ~/expand_usb.sh ~/shrink_usb.sh ~/autosave.sh ~/blink_led.sh
sudo rm -f /home/*/expand_usb.sh /home/*/shrink_usb.sh /home/*/autosave.sh /home/*/blink_led.sh 2>/dev/null || true

# Remove any leftover PiSpot config in /boot
sudo sed -i '/dtoverlay=dwc2/d' /boot/config.txt || true
sudo sed -i 's/ modules-load=dwc2,g_mass_storage//' /boot/cmdline.txt || true

echo "==== PiSpot: Reset complete ===="

echo "==== PiSpot Automated Setup ===="

# 1. LED Setup
echo "Choose LED mode:"
echo "1) Off (safe unplug)"
echo "2) Blink every 10s (status indicator)"
read -p "Enter 1 or 2 [default: 1]: " LEDMODE
LEDMODE=${LEDMODE:-1}

if [[ "$LEDMODE" == "1" ]]; then
    # Turn LED off via /boot/config.txt
    if ! grep -q "dtparam=act_led_trigger=none" /boot/config.txt; then
        echo "Disabling status LED..."
        echo "dtparam=act_led_trigger=none" | sudo tee -a /boot/config.txt
        echo "dtparam=act_led_activelow=on" | sudo tee -a /boot/config.txt
    fi
else
    # Enable manual LED control and blinking script
    echo "Enabling manual LED blink every 10s..."
    sudo sh -c "echo heartbeat > /sys/class/leds/led0/trigger" || true
    cat <<'EOF' | sudo tee "${USERHOME}/blink_led.sh" > /dev/null
#!/bin/bash
while true; do
    echo 1 | sudo tee /sys/class/leds/led0/brightness > /dev/null
    sleep 0.1
    echo 0 | sudo tee /sys/class/leds/led0/brightness > /dev/null
    sleep 10
done
EOF
    sudo chmod +x "${USERHOME}/blink_led.sh"
    if ! grep -q "${USERHOME}/blink_led.sh &" /etc/rc.local; then
        sudo sed -i "/^exit 0/i ${USERHOME}/blink_led.sh &" /etc/rc.local
    fi
fi

# 2. Auto-save script and cron
echo "Setting up auto-save script..."
cat <<'EOF' | sudo tee "${USERHOME}/autosave.sh" > /dev/null
#!/bin/bash
echo "Auto-saving system data..."
sudo sync
EOF
sudo chmod +x "${USERHOME}/autosave.sh"
if ! sudo crontab -l | grep -q "${USERHOME}/autosave.sh"; then
    (sudo crontab -l 2>/dev/null; echo "*/2 * * * * ${USERHOME}/autosave.sh") | sudo crontab -
fi

# 3. USB Gadget Mode
echo "Configuring USB gadget mode..."
if ! grep -q "dtoverlay=dwc2" /boot/config.txt; then
    echo "dtoverlay=dwc2" | sudo tee -a /boot/config.txt
fi
if ! grep -q "modules-load=dwc2,g_mass_storage" /boot/cmdline.txt; then
    sudo sed -i 's/rootwait/rootwait modules-load=dwc2,g_mass_storage/' /boot/cmdline.txt
fi

# 4. USB Storage Image
if [ ! -f /usb_drive.img ]; then
    echo "Creating 5GB USB storage image (fast)..."
    if sudo fallocate -l 5G /usb_drive.img 2>/dev/null; then
        echo "fallocate succeeded."
    else
        echo "fallocate not supported, falling back to slow dd..."
        sudo dd if=/dev/zero of=/usb_drive.img bs=1M count=5120
    fi
    sudo mkfs.ext4 /usb_drive.img
fi

# Ensure /etc/rc.local exists and is executable
if [ ! -f /etc/rc.local ]; then
    echo "Creating /etc/rc.local..."
    sudo tee /etc/rc.local > /dev/null <<'EORC'
#!/bin/bash
exit 0
EORC
    sudo chmod +x /etc/rc.local
fi

# 5. Load USB storage on boot
if ! grep -q "modprobe g_mass_storage file=/usb_drive.img removable=1" /etc/rc.local; then
    sudo sed -i '/^exit 0/i modprobe g_mass_storage file=/usb_drive.img removable=1' /etc/rc.local
fi

# 6. Expand/shrink scripts
echo "Installing expand/shrink scripts..."
cat <<'EOF' | sudo tee "${USERHOME}/expand_usb.sh" > /dev/null
#!/bin/bash
if [[ "$1" == "-f" ]]; then
    echo "Formatting USB storage..."
    sudo mkfs.ext4 /usb_drive.img
    exit 0
elif [[ -z "$1" ]]; then
    echo "Usage: expand_usb.sh <size_in_MB> or expand_usb.sh -f"
    exit 1
fi
NEW_SIZE=$1
MAX_SIZE=51200
CURRENT_SIZE=$(du -m /usb_drive.img | awk '{print $1}')
if (( NEW_SIZE > MAX_SIZE )); then
    echo "Error: Cannot expand beyond ${MAX_SIZE}MB!"
    exit 1
fi
echo "Expanding USB storage to ${NEW_SIZE}MB..."
sudo dd if=/dev/zero bs=1M count=$(( NEW_SIZE - CURRENT_SIZE )) >> /usb_drive.img
sudo resize2fs /usb_drive.img
echo "Expansion complete!"
EOF

cat <<'EOF' | sudo tee "${USERHOME}/shrink_usb.sh" > /dev/null
#!/bin/bash
if [[ "$1" == "-f" ]]; then
    echo "Formatting USB storage..."
    sudo mkfs.ext4 /usb_drive.img
    exit 0
elif [[ -z "$1" ]]; then
    echo "Usage: shrink_usb.sh <size_in_MB> or shrink_usb.sh -f"
    exit 1
fi
NEW_SIZE=$1
CURRENT_SIZE=$(du -m /usb_drive.img | awk '{print $1}')
USED_SIZE=$(df -m /usb_drive.img | awk 'NR==2 {print $3}')
if (( NEW_SIZE < USED_SIZE )); then
    echo "Error: Cannot shrink below ${USED_SIZE}MB! Files would be lost."
    exit 1
fi
echo "Shrinking USB storage to ${NEW_SIZE}MB..."
sudo resize2fs /usb_drive.img "$NEW_SIZE"M
sudo truncate -s "${NEW_SIZE}M" /usb_drive.img
echo "Shrink complete!"
EOF

sudo chmod +x "${USERHOME}/expand_usb.sh"
sudo chmod +x "${USERHOME}/shrink_usb.sh"

# 7. Install nginx and deploy control panel
echo "Installing nginx web server..."
sudo apt-get update
sudo apt-get install -y nginx

# Ask user for nginx port (default: 80)
read -p "Enter port for PiSpot web panel (nginx) [default: 80]: " NGINX_PORT
NGINX_PORT=${NGINX_PORT:-80}

# Update nginx to listen on the chosen port
sudo sed -i "s/listen 80 default_server;/listen ${NGINX_PORT} default_server;/" /etc/nginx/sites-available/default
sudo sed -i "s/listen \[::\]:80 default_server;/listen [::]:${NGINX_PORT} default_server;/" /etc/nginx/sites-available/default

echo "Deploying PiSpot control panel..."
sudo tee /var/www/html/pispot.html > /dev/null <<'EOPANEL'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>PiSpot Control Panel</title>
  <style>
    body { font-family: sans-serif; background: #222; color: #eee; margin: 0; padding: 0; }
    .container { max-width: 600px; margin: 40px auto; background: #333; border-radius: 8px; padding: 2em; }
    h1 { color: #6cf; }
    button { padding: 0.5em 1.5em; margin: 0.5em 0; font-size: 1em; border-radius: 4px; border: none; background: #6cf; color: #222; cursor: pointer; }
    button:disabled { background: #888; }
    .info { margin: 1em 0; }
    .footer { margin-top: 2em; font-size: 0.9em; color: #aaa; }
  </style>
</head>
<body>
  <div class="container">
    <h1>PiSpot Control Panel</h1>
    <div class="info">
      <b>Status LED:</b> <span id="led-status">Manual setup required</span><br>
      <b>USB Storage:</b> <span id="usb-status">/usb_drive.img</span>
    </div>
    <form method="POST" action="/expand">
      <label>Expand USB Storage (MB):</label>
      <input type="number" name="size" min="1" max="51200" required>
      <button type="submit">Expand</button>
    </form>
    <form method="POST" action="/shrink">
      <label>Shrink USB Storage (MB):</label>
      <input type="number" name="size" min="1" max="51200" required>
      <button type="submit">Shrink</button>
    </form>
    <form method="POST" action="/format">
      <button type="submit" style="background:#f66;">Format USB Storage</button>
    </form>
    <div class="footer">
      PiSpot &copy; 2024 &mdash; <a href="https://github.com/" style="color:#6cf;">GitHub</a>
    </div>
  </div>
</body>
</html>
EOPANEL

# Set pispot.html as the default nginx index
sudo sed -i 's/index.nginx-debian.html/pispot.html/' /etc/nginx/sites-available/default

sudo systemctl restart nginx

echo "==== Nginx and PiSpot control panel installed! ===="
echo "Access the control panel at: http://${PISPOT_IP}:${NGINX_PORT}/"

# --- Cockpit Setup ---
read -p "Enter port for Cockpit web interface [default: 9090]: " COCKPIT_PORT
COCKPIT_PORT=${COCKPIT_PORT:-9090}

echo "Installing Cockpit web system manager..."
sudo apt-get install -y cockpit

if [ "$COCKPIT_PORT" != "9090" ]; then
    sudo mkdir -p /etc/systemd/system/cockpit.socket.d
    sudo tee /etc/systemd/system/cockpit.socket.d/listen.conf > /dev/null <<EOF
[Socket]
ListenStream=
ListenStream=${COCKPIT_PORT}
EOF
fi

sudo systemctl enable cockpit.socket
sudo systemctl restart cockpit.socket

log "Cockpit installed and configured on port $COCKPIT_PORT"
save_setting "COCKPIT_PORT=$COCKPIT_PORT"
save_setting "COCKPIT_URL=http://${PISPOT_IP}:${COCKPIT_PORT}/"

echo "==== Cockpit web system manager installed! ===="
echo "Access Cockpit at: http://${PISPOT_IP}:${COCKPIT_PORT}/"

# 8. Wi-Fi Hotspot Setup
echo "Installing hostapd..."
sudo apt-get install -y hostapd
sudo systemctl unmask hostapd
sudo systemctl enable hostapd

# Ensure /etc/hostapd exists
sudo mkdir -p /etc/hostapd

# Ask user for PiSpot IP address (default: 192.168.4.1)
read -p "Enter PiSpot IP address [default: 192.168.4.1]: " PISPOT_IP
PISPOT_IP=${PISPOT_IP:-192.168.4.1}
read -p "Enter DHCP range start [default: 192.168.4.2]: " DHCP_START
DHCP_START=${DHCP_START:-192.168.4.2}
read -p "Enter DHCP range end [default: 192.168.4.20]: " DHCP_END
DHCP_END=${DHCP_END:-192.168.4.20}

# Disable dhcpcd and wpa_supplicant for wlan0 to avoid conflicts (for offline AP mode)
sudo sed -i '/^interface wlan0/d' /etc/dhcpcd.conf 2>/dev/null || true
echo "interface wlan0" | sudo tee -a /etc/dhcpcd.conf
echo "    static ip_address=${PISPOT_IP}/24" | sudo tee -a /etc/dhcpcd.conf

# Ensure dhcpcd is installed before attempting to restart
if ! dpkg -l | grep -qw dhcpcd5; then
    echo "dhcpcd not found, installing..."
    sudo apt-get install -y dhcpcd5
fi

# Try to restart dhcpcd if the service exists
if systemctl list-unit-files | grep -q '^dhcpcd\.service'; then
    sudo systemctl restart dhcpcd
else
    echo "Warning: dhcpcd.service not found, skipping restart."
fi

# Stop wpa_supplicant on wlan0 to prevent it from interfering with AP mode
sudo systemctl stop wpa_supplicant@wlan0.service || true
sudo systemctl disable wpa_supplicant@wlan0.service || true

echo "==== PiSpot Wi-Fi Hotspot Setup ===="
read -p "Enter desired SSID [default: PiSpot]: " PISPOT_SSID
PISPOT_SSID=${PISPOT_SSID:-PiSpot}
read -p "Enter Wi-Fi password (min 8 chars) [default: pistop123]: " PISPOT_PASS
PISPOT_PASS=${PISPOT_PASS:-pistop123}
while [ ${#PISPOT_PASS} -lt 8 ]; do
    echo "Password must be at least 8 characters."
    read -p "Enter Wi-Fi password (min 8 chars): " PISPOT_PASS
done
read -p "Should the network be visible? (y/n) [default: y]: " PISPOT_VISIBLE
PISPOT_VISIBLE=${PISPOT_VISIBLE:-y}
if [[ "$PISPOT_VISIBLE" =~ ^[Yy]$ ]]; then
    IGNORE_BROADCAST_SSID=0
else
    IGNORE_BROADCAST_SSID=1
fi

# Set Wi-Fi country to US for regulatory compliance
echo "Setting Wi-Fi country to US..."
sudo sed -i '/^country=/d' /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null || true
echo "country=US" | sudo tee -a /etc/wpa_supplicant/wpa_supplicant.conf

echo "Configuring hostapd..."
sudo tee /etc/hostapd/hostapd.conf > /dev/null <<EOF
interface=wlan0
ssid=${PISPOT_SSID}
hw_mode=g
channel=7
wpa=2
wpa_passphrase=${PISPOT_PASS}
ignore_broadcast_ssid=${IGNORE_BROADCAST_SSID}
country_code=US
EOF

sudo sed -i 's|^DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

sudo systemctl restart hostapd || true

# Set up a basic DHCP server for clients (dnsmasq)
echo "Installing dnsmasq for DHCP..."
sudo apt-get install -y dnsmasq
sudo tee /etc/dnsmasq.conf > /dev/null <<EOF
interface=wlan0
dhcp-range=${DHCP_START},${DHCP_END},255.255.255.0,24h
EOF
sudo systemctl restart dnsmasq

# After setting up Wi-Fi SSID and password, save them for reference
WIFI_SETTINGS_FILE="$USERHOME/pispot/wifi_settings.txt"
echo "SSID: $PISPOT_SSID" > "$WIFI_SETTINGS_FILE"
echo "Password: $PISPOT_PASS" >> "$WIFI_SETTINGS_FILE"
echo "Visible: $PISPOT_VISIBLE" >> "$WIFI_SETTINGS_FILE"

log "LED mode selected: $LEDMODE"
save_setting "LED_MODE=$LEDMODE"

log "Auto-save script installed"
save_setting "AUTOSAVE_SCRIPT=enabled"

log "USB gadget mode configured"
save_setting "USB_GADGET=enabled"

log "USB storage image created"
save_setting "USB_STORAGE_IMG=5GB"

log "Expand/shrink scripts installed"
save_setting "EXPAND_SHRINK_SCRIPTS=enabled"

log "nginx installed and control panel deployed"
save_setting "WEBSERVER=nginx"
save_setting "WEB_PANEL_URL=http://${PISPOT_IP}:${NGINX_PORT}/"

log "hostapd installed and configured"
save_setting "SSID=$PISPOT_SSID"
save_setting "WIFI_PASSWORD=$PISPOT_PASS"
save_setting "WIFI_VISIBLE=$PISPOT_VISIBLE"
save_setting "WIFI_COUNTRY=US"
save_setting "STATIC_IP=${PISPOT_IP}"
save_setting "DHCP_RANGE=${DHCP_START}-${DHCP_END}"

log "dnsmasq installed for DHCP"
save_setting "DHCP_SERVER=dnsmasq"

echo "==== PiSpot Wi-Fi Hotspot configured! ====" | tee -a "$LOG_FILE"
echo "==== PiSpot setup complete! ====" | tee -a "$LOG_FILE"
echo "Settings saved to $SETTINGS_FILE" | tee -a "$LOG_FILE"
echo "Log saved to $LOG_FILE" | tee -a "$LOG_FILE"

echo
echo "==== FINAL STEP ===="
echo "Unplug the ethernet cable from your Pi now."
read -p "Press ENTER to reboot and finish setup..." _
log "User prompted to unplug ethernet and reboot"
sudo reboot
