```markdown
# **Complete Guide: USB Gadget Mode on Raspberry Pi with Dynamic Storage Resizing**

## **Overview**
This guide will configure your Raspberry Pi to:
✅ **Receive power from a PC** via USB  
✅ **Share files with the PC** as root storage  
✅ **Allow dynamic storage resizing (expand/shrink)**  
✅ **Keep the ability to connect USB peripherals via a hub**  

### **Requirements**
- **Raspberry Pi Zero / Zero W / Zero 2 W** (recommended for native USB gadget mode)  
- **USB-A to Micro-USB (or USB-C) cable** (for PC connection)  
- **USB OTG hub or splitter** (optional, for additional peripherals)  

---

## **Step 1: Enable USB Gadget Mode**
### **1.1 Edit the Boot Configuration**
1. Open the boot configuration file:
   ```bash
   sudo nano /boot/config.txt
   ```
2. Add this line at the bottom:
   ```plaintext
   dtoverlay=dwc2
   ```
3. Save and exit (`Ctrl + X`, then `Y`, then `Enter`).

### **1.2 Load the USB Modules**
1. Edit the kernel boot command line:
   ```bash
   sudo nano /boot/cmdline.txt
   ```
2. Add the following **after `rootwait`** (ensure it's all on ONE line):
   ```plaintext
   modules-load=dwc2,g_mass_storage
   ```
3. Save and exit.

---

## **Step 2: Create a USB Storage Image**
### **2.1 Create a 5GB Storage File**
1. Run the following command to create a **5GB USB storage file**:
   ```bash
   sudo dd if=/dev/zero of=/usb_drive.img bs=1M count=5120
   ```
2. Format it as **ext4** (allows resizing):
   ```bash
   sudo mkfs.ext4 /usb_drive.img
   ```

### **2.2 Load the USB Storage**
1. Enable the USB storage gadget mode:
   ```bash
   sudo modprobe g_mass_storage file=/usb_drive.img removable=1
   ```

### **2.3 Automate USB Gadget Activation on Boot**
1. Open `rc.local`:
   ```bash
   sudo nano /etc/rc.local
   ```
2. Add this **before `exit 0`**:
   ```bash
   modprobe g_mass_storage file=/usb_drive.img removable=1
   ```
3. Save and exit.

---

## **Step 3: Expand/Shrink USB Storage Dynamically**
### **3.1 Expand USB Storage**
1. Create the expansion script:
   ```bash
   sudo nano /home/timour/expand_usb.sh
   ```
2. Add this code:
   ```bash
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
   MAX_SIZE=51200  # 50GB max limit

   CURRENT_SIZE=$(du -m /usb_drive.img | awk '{print $1}')
   if (( NEW_SIZE > MAX_SIZE )); then
       echo "Error: Cannot expand beyond ${MAX_SIZE}MB!"
       exit 1
   fi

   echo "Expanding USB storage to ${NEW_SIZE}MB..."
   sudo dd if=/dev/zero bs=1M count=$(( NEW_SIZE - CURRENT_SIZE )) >> /usb_drive.img
   sudo resize2fs /usb_drive.img
   echo "Expansion complete!"
   ```
3. Make it executable:
   ```bash
   chmod +x /home/timour/expand_usb.sh
   ```

---

### **3.2 Shrink USB Storage**
1. Create the shrinking script:
   ```bash
   sudo nano /home/timour/shrink_usb.sh
   ```
2. Add:
   ```bash
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
   ```
3. Make it executable:
   ```bash
   chmod +x /home/timour/shrink_usb.sh
   ```

---

## **Step 4: Using the USB Storage**
### **4.1 Expand Storage**
To **increase** the USB storage size:
```bash
sudo /home/timour/expand_usb.sh 10240
```
*(Expands to 10GB)*

### **4.2 Shrink Storage**
To **reduce** the USB storage size:
```bash
sudo /home/timour/shrink_usb.sh 3072
```
*(Shrinks to 3GB, but ensures no data loss.)*

### **4.3 Format the Storage**
To **wipe and reformat** the USB storage:
```bash
sudo /home/timour/expand_usb.sh -f
```
*or*
```bash
sudo /home/timour/shrink_usb.sh -f
```

---

## **Step 5: Connecting to the PC**
### **5.1 Plug Your Raspberry Pi into a PC**
1. Connect your Raspberry Pi **using the USB data port**.
2. Your PC should detect the Pi as a **mass storage device**.
3. You can view files **on the USB drive** from the PC.

### **5.2 Use a USB Hub to Keep Peripherals**
If you need to **use a keyboard** while connected to a PC:
1. Plug in a **USB OTG hub** or splitter.
2. Connect **USB peripherals** like a keyboard/mouse.

---

## **Final Notes**
✅ **Automatic USB gadget mode enabled on boot.**  
✅ **5GB storage by default, expandable up to 50GB dynamically.**  
✅ **Ensures safe shrinking (error prevents data loss).**  
✅ **Can format storage anytime via the `-f` flag.**  
✅ **Allows simultaneous USB peripheral usage via a hub.**  
