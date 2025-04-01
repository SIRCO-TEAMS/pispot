### **Step 1: Enable Manual LED Control**
1. Open a terminal and run:
   ```bash
   sudo nano /sys/class/leds/led0/trigger
   ```
2. Replace its contents with:
   ```plaintext
   heartbeat
   ```
3. Save and exit (`Ctrl + X`, then `Y`, then `Enter`).

🔹 This will make the LED **blink dynamically based on system load**, but if you want **precise blinking every 10 seconds**, follow the next steps.

---

### **Step 2: Create a Blinking Script**
1. Open a new script file:
   ```bash
   sudo nano /home/timour/blink_led.sh
   ```
2. Add the following code:
   ```bash
   #!/bin/bash

   while true; do
       echo 1 | sudo tee /sys/class/leds/led0/brightness > /dev/null
       sleep 0.1  # Blink duration
       echo 0 | sudo tee /sys/class/leds/led0/brightness > /dev/null
       sleep 10   # Wait for 10 seconds before next blink
   done
   ```

3. Save and exit.
4. Make it executable:
   ```bash
   chmod +x /home/timour/blink_led.sh
   ```

---

### **Step 3: Run on Boot**
1. Edit `rc.local`:
   ```bash
   sudo nano /etc/rc.local
   ```
2. Add this **before `exit 0`**:
   ```bash
   /home/timour/blink_led.sh &
   ```
3. Save and exit.
4. Restart your Raspberry Pi:
   ```bash
   sudo reboot
   ```

---

## **Final Behavior**
✅ **System LED blinks once every 10 seconds** to confirm it's powered on.  
✅ **Keeps the LED off otherwise**, ensuring safe unplugging.  
✅ **Runs automatically after reboot** without manual intervention.  
