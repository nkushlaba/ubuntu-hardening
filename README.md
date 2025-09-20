# 🛡️ Ubuntu Autoinstall Remaster Script

This project provides a Bash script (`remaster-ubuntu-autoinstall.sh`) that takes an official **Ubuntu Desktop or Server ISO** and rebuilds it into a **preconfigured autoinstall ISO** with enhanced security features:

- **Secure Boot enforced**
- **Full-disk encryption (LUKS)** with interactive passphrase
- **Interactive prompts** for username, password, and partitioning
- **TPM2 + Clevis** installed for hardware-backed encryption
- **Automatic MOK keypair generation and enrollment**
- **Kernel and module auto-signing hook**
- **System summary log** generated on first boot (`/var/log/autoinstall-summary.log`)

The output ISO can be written to a USB stick and booted directly for an unattended yet secure Ubuntu installation.

---

## ⚙️ Features

### 🔒 Secure Boot Enforcement
- Forces Secure Boot to be enabled (`update-secureboot-policy --enforce`).
- Ensures unsigned kernels/modules cannot boot.

### 🔑 Full Disk Encryption
- Installer prompts you for a LUKS passphrase interactively.
- Encryption applies to chosen partitions.
- `clevis` and TPM2 integration preinstalled for future automated unlock.

### 👤 Interactive User Setup
- Identity (username/password) and partitioning remain interactive.
- Everything else is automated.

### 🖊️ MOK Keypair & Module Signing
- Generates a **Machine Owner Key (MOK)** at install time.
- Enrolls the MOK certificate into firmware (`mokutil --import`).
- Installs a hook in `/etc/kernel/postinst.d/`:
  - Signs every new kernel image with the MOK.
  - Signs all kernel modules with the MOK.
- Ensures system stays Secure Boot–compliant after updates.

### 📋 Autoinstall Summary Log
On first boot, systemd runs a one-shot service that collects and writes:

- Secure Boot state
- TPM device presence
- LUKS volume information
- MOK key enrollment status  

to:

```
/var/log/autoinstall-summary.log
```

Then the service disables itself.

---

## 🖥️ ISO Type Detection

The script supports **both Desktop and Server ISOs**:

- **Desktop (Ubuntu 24.04+ GRUB-only)**  
  Uses `EFI/BOOT/bootx64.efi` (or `EFI/boot/grubx64.efi`) for EFI boot.  
  Builds GRUB-only ISO with GPT hybrid layout.

- **Server (20.04/22.04 legacy)**  
  Uses both GRUB + ISOLINUX for BIOS/UEFI hybrid boot.  
  Builds ISO with isolinux options.

---

## 📦 Prerequisites

Run on a Linux system with:

```bash
sudo apt update
sudo apt install xorriso rsync pv -y
```

---

## 🚀 Usage

1. Make script executable:
   ```bash
   chmod +x remaster-ubuntu-autoinstall.sh
   ```

2. Run against an Ubuntu ISO:
   ```bash
   sudo ./remaster-ubuntu-autoinstall.sh ubuntu-24.04.3-desktop-amd64.iso
   ```

3. Output ISO:
   ```
   ubuntu-autoinstall.iso
   ```

4. Write to USB:
   ```bash
   sudo dd if=ubuntu-autoinstall.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```

---

## 🔍 What to Expect During Install

- Installer boots directly with **autoinstall enabled**.  
- You will be prompted for:
  - Username & password
  - Partition layout
  - LUKS encryption passphrase
- After installation:
  - Secure Boot enforced
  - Disk encryption enabled
  - TPM2 tools installed
  - Kernel and modules auto-signed
  - Log file created at `/var/log/autoinstall-summary.log`

---

## 📝 Example Log Output

```
===== Ubuntu Autoinstall Summary =====
Date: Sat Sep 21 13:45:00 UTC 2025

[ Secure Boot Status ]
SecureBoot enabled

[ TPM Devices ]
crw------- 1 root root 10, 224 Sep 21 13:45 /dev/tpm0

[ LUKS Devices ]
LUKS header information
Version:        2
Cipher name:    aes
...

[ MOK Enrollment Files ]
-rw------- 1 root root 3243 Sep 21 13:45 MOK.crt
-rw------- 1 root root 1679 Sep 21 13:45 MOK.key
```

---

## ⚠️ Notes & Limitations

- Secure Boot must be enabled in BIOS/UEFI firmware.  
- User must confirm MOK enrollment on first reboot (blue screen prompt).  
- ISO rebuild may take several minutes.  
- Script modifies `grub.cfg` and (for legacy ISOs) `isolinux/txt.cfg`.  
- Only tested on **Ubuntu 20.04, 22.04, and 24.04 ISOs**.  

---

## 🛠️ Future Enhancements

- Add progress bars to `rsync` and ISO creation with `pv`.  
- Extend summary log with **TPM PCR measurements** for attestation.  
- Support remastering on macOS (currently Linux only).  

---

## 🖼️ Example Workflow (Ubuntu 24.04 Desktop)

1. Download the Ubuntu 24.04.3 Desktop ISO:
   ```bash
   wget https://releases.ubuntu.com/24.04/ubuntu-24.04.3-desktop-amd64.iso
   ```

2. Run the remaster script:
   ```bash
   sudo ./remaster-ubuntu-autoinstall.sh ubuntu-24.04.3-desktop-amd64.iso
   ```

   Output:
   ```
   [*] ISO type detected: desktop
   [*] Creating GRUB-only Desktop ISO...
   [*] Done. New ISO created: ubuntu-autoinstall.iso
   ```

3. Write to USB stick:
   ```bash
   sudo dd if=ubuntu-autoinstall.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```

4. Boot from USB:
   - Autoinstall kicks in automatically.  
   - Provide username, password, disk layout, and LUKS passphrase.  
   - Rest is automatic.

5. After reboot, check summary log:
   ```bash
   cat /var/log/autoinstall-summary.log
   ```
