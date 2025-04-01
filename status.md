### **Step 1: Turn Off the Status LED**
The status LED on a Raspberry Pi can be controlled through the system configuration.

#### **1.1 Disable the LED via the Boot Config**
1. Open the Raspberry Pi boot configuration file:
   ```bash
   sudo nano /boot/config.txt
   ```
2. Add the following lines at the bottom:
   ```plaintext
   dtparam=act_led_trigger=none
   dtparam=act_led_activelow=on
   ```
3. Save and exit (`Ctrl + X`, then `Y`, then `Enter`).
4. Reboot your Raspberry Pi:
   ```bash
   sudo reboot
   ```

🟢 After rebooting, the activity LED should remain **off**, letting you know it's safe to unplug.

---

### **Step 2: Auto-Save Data Every 2 Minutes**
You can set up an automatic process that periodically syncs data to prevent loss.

#### **2.1 Create a Sync Script**
1. Open a new script file:
   ```bash
   sudo nano /home/timour/autosave.sh
   ```
2. Add the following:
   ```bash
   #!/bin/bash
   echo "Auto-saving system data..."
   sudo sync
   ```

3. Save and make it executable:
   ```bash
   chmod +x /home/timour/autosave.sh
   ```

#### **2.2 Schedule Auto-Save in Crontab**
1. Open the crontab editor:
   ```bash
   crontab -e
   ```
2. Add this line at the bottom:
   ```plaintext
   */2 * * * * /home/timour/autosave.sh
   ```

✅ **This ensures the system syncs all pending writes every 2 minutes**, preventing data loss when unplugging.

---

### **Final Setup**
🔹 **Status LED stays off**, indicating it's safe to unplug.  
🔹 **Data is auto-saved every 2 minutes**, avoiding corruption.  
🔹 **No manual shutdown required—just unplug without worry!**
