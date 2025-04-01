### **Step 1: Check if HostAPD is Running**
Run this command to check the status of the Wi-Fi hotspot service:
```bash
sudo systemctl status hostapd
```
If it's **inactive** or **failed**, restart it:
```bash
sudo systemctl restart hostapd
```

### **Step 2: Verify Wi-Fi Interface**
Check if `wlan0` is active:
```bash
iwconfig wlan0
```
If `wlan0` isn't listed, try bringing it up manually:
```bash
sudo ip link set wlan0 up
```

### **Step 3: Confirm SSID is Set Correctly**
Open the HostAPD configuration file:
```bash
sudo nano /etc/hostapd/hostapd.conf
```
Ensure it contains:
```plaintext
interface=wlan0
ssid=LS7
hw_mode=g
channel=7
wpa=2
wpa_passphrase=Therizzler2025
ignore_broadcast_ssid=0
```
If `ignore_broadcast_ssid=1`, change it to `0` to **make LS7 visible**.

### **Step 4: Restart Services**
After making changes, restart everything:
```bash
sudo systemctl restart hostapd
sudo systemctl restart dnsmasq
sudo systemctl restart networking
```

### **Step 5: Scan for Wi-Fi Networks**
On your PC or phone, scan for Wi-Fi networks again. If LS7 still doesn’t appear, try:
```bash
sudo iwlist wlan0 scan | grep SSID
```
This will show available networks. If LS7 isn't listed, there may be interference or a misconfiguration.

### **Step 6: Check for Conflicting Services**
If `NetworkManager` is running, it might interfere. Disable it:
```bash
sudo systemctl stop NetworkManager
sudo systemctl disable NetworkManager
```

### **Step 7: Reboot**
Finally, reboot your Raspberry Pi:
```bash
sudo reboot
```
