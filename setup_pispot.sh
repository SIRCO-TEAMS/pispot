#!/bin/bash

set -e

# Dynamically get the username (prefer SUDO_USER, fallback to whoami)
USERNAME="${SUDO_USER:-$(whoami)}"
USERHOME="$(eval echo ~${USERNAME})"

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
    echo "Creating 5GB USB storage image..."
    sudo dd if=/dev/zero of=/usb_drive.img bs=1M count=5120
    sudo mkfs.ext4 /usb_drive.img
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

echo "Configuring nginx to listen on 192.168.4.1 only..."
sudo sed -i 's/listen 80 default_server;/listen 192.168.4.1:80 default_server;/' /etc/nginx/sites-available/default
sudo sed -i 's/listen \[::\]:80 default_server;/# listen [::]:80 default_server;/' /etc/nginx/sites-available/default

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
echo "Access the control panel at: http://192.168.4.1/"

# 8. Wi-Fi Hotspot Setup
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

echo "Configuring hostapd..."
sudo tee /etc/hostapd/hostapd.conf > /dev/null <<EOF
interface=wlan0
ssid=${PISPOT_SSID}
hw_mode=g
channel=7
wpa=2
wpa_passphrase=${PISPOT_PASS}
ignore_broadcast_ssid=${IGNORE_BROADCAST_SSID}
EOF

sudo sed -i 's|^DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

sudo systemctl restart hostapd || true

echo "==== PiSpot Wi-Fi Hotspot configured! ===="

echo "==== PiSpot setup complete! ===="
echo "Reboot required for all changes to take effect."
