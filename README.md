# **Complete Raspberry Pi Setup Guide**

---

## **Part 1: Setting Up a Wi-Fi Hotspot**

### 1.1 Download and Install Raspberry Pi OS
1. Download **Raspberry Pi OS Lite** from [Raspberry Pi OS Downloads](https://www.raspberrypi.org/software/operating-systems/).
2. Flash the OS image onto an SD card using [Raspberry Pi Imager](https://www.raspberrypi.org/software/) or [Balena Etcher](https://www.balena.io/etcher/).
3. Insert the SD card into your Raspberry Pi and power it on.

### 1.2 Install Necessary Packages
1. Connect to your Raspberry Pi (via SSH or a monitor/keyboard).
2. Run the following to update the system:
   ```bash
   sudo apt update
   sudo apt upgrade

3. Install required packages:
   ```bash
   sudo apt install hostapd dnsmasq iptables iw
   ```

### 1.3 Configure Dnsmasq
1. Open the Dnsmasq configuration file:
   ```bash
   sudo nano /etc/dnsmasq.conf
   ```
2. Add the following lines:
   ```plaintext
   interface=wlan0
   dhcp-range=192.168.4.10,192.168.4.100,255.255.255.0,24h
   ```
3. Save and exit.

### 1.4 Configure HostAPD
1. Open the HostAPD configuration file:
   ```bash
   sudo nano /etc/hostapd/hostapd.conf
   ```
2. Add the following configuration:
   ```plaintext
   interface=wlan0
   ssid=LS7
   hw_mode=g
   channel=7
   wpa=2
   wpa_passphrase=Therizzler2025
   ignore_broadcast_ssid=1
   ```
3. Save and exit.

### 1.5 Start HostAPD and Dnsmasq Services
1. Enable and start HostAPD:
   ```bash
   sudo systemctl unmask hostapd
   sudo systemctl enable hostapd
   sudo systemctl start hostapd
   ```
2. Enable and start Dnsmasq:
   ```bash
   sudo systemctl enable dnsmasq
   sudo systemctl start dnsmasq
   ```

---

## **Part 2: Setting Up Automatic Shutdown at 6:00 PM**

### 2.1 Create the Shutdown Script
1. Create a new script:
   ```bash
   sudo nano /home/timour/shutdown_at_6pm.sh
   ```
2. Add the following content:
   ```bash
   #!/bin/bash
   if [ -f /home/timour/stop_shutdown ]; then
       echo "Shutdown aborted because the override file exists."
       exit 0
   fi
   sudo shutdown -h now
   ```
3. Save and make the script executable:
   ```bash
   chmod +x /home/timour/shutdown_at_6pm.sh
   ```

### 2.2 Schedule the Script
1. Open the crontab editor:
   ```bash
   crontab -e
   ```
2. Add the following line to run the script at 6:00 PM:
   ```plaintext
   0 18 * * * /home/timour/shutdown_at_6pm.sh
   ```

### 2.3 Create the Override Command
1. To prevent the shutdown for a day, create an override file:
   ```bash
   touch /home/timour/stop_shutdown
   ```
2. To re-enable shutdown, remove the override file:
   ```bash
   rm /home/timour/stop_shutdown
   ```

---

## **Part 3: Setting Up Nginx**

### 3.1 Install and Configure Nginx
1. Install Nginx:
   ```bash
   sudo apt install nginx
   ```
2. Open the Nginx default site configuration:
   ```bash
   sudo nano /etc/nginx/sites-available/default
   ```
3. Change the port configuration:
   ```plaintext
   server {
       listen 8080 default_server;
       listen [::]:8080 default_server;
   }
   ```
4. Save and restart Nginx:
   ```bash
   sudo systemctl restart nginx
   ```

---

## **Part 4: Setting Up a Web Console**

### 4.1 Install Cockpit
1. Install Cockpit:
   ```bash
   sudo apt install cockpit
   ```
2. Open the Cockpit configuration file:
   ```bash
   sudo nano /etc/cockpit/cockpit.conf
   ```
3. Add the following:
   ```plaintext
   [WebService]
   Port = 9090
   ```
4. Enable and start Cockpit:
   ```bash
   sudo systemctl enable cockpit.socket
   sudo systemctl start cockpit.socket
   ```

---

## **Part 5: Configuring a Mesh Network**

### 5.1 Install and Configure batman-adv
1. Install batman-adv:
   ```bash
   sudo apt install batctl
   ```
2. Configure `wlan0` for Mesh Networking:
   ```bash
   sudo nano /etc/network/interfaces.d/wlan0
   ```
3. Add the following:
   ```plaintext
   auto wlan0
   iface wlan0 inet manual
   pre-up iw dev wlan0 set type ibss
   pre-up ip link set wlan0 mtu 1528
   pre-up ip link set wlan0 up
   post-up iw dev wlan0 ibss join LS7 2432
   post-up batctl if add wlan0
   post-up ip link set up dev bat0
   ```

---

## **Part 6: Restricting Internet Access**

### 6.1 Update Firewall Rules
1. Flush all existing firewall rules:
   ```bash
   sudo iptables -F
   sudo iptables -t nat -F
   ```
2. Add rules to allow only local traffic:
   ```bash
   sudo iptables -A INPUT -i wlan0 -p tcp --dport 80 -j ACCEPT
   sudo iptables -A INPUT -i wlan0 -p tcp --dport 8080 -j ACCEPT
   sudo iptables -A FORWARD -i wlan0 -o eth0 -j DROP
   ```
3. Save the new rules:
   ```bash
   sudo sh -c "iptables-save > /etc/iptables.ipv4.nat"
   ```
4. Ensure the rules are restored on boot:
   ```bash
   sudo nano /etc/rc.local
   ```
5. Add this before `exit 0`:
   ```plaintext
   iptables-restore < /etc/iptables.ipv4.nat
   ```

---

## **Final Steps**

1. **Reboot the Raspberry Pi**:
   ```bash
   sudo reboot
   ```

2. **Verify Your Setup**:
   - Test Wi-Fi Hotspot (SSID: LS7, WPA2 passphrase: Therizzler2025).
   - Access Nginx on port `8080` and Cockpit on port `9090`.
   - Ensure automatic shutdown works as planned with the override option.
   - Confirm mesh networking configuration.

---
