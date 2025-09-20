# 🖼️ Example Workflow: Remastering & Using the Script on Ubuntu 24.04 Desktop

This walkthrough shows how to take the stock **Ubuntu 24.04.3 Desktop ISO**, process it with the `remaster-ubuntu-autoinstall.sh` script, and install a hardened system with **Secure Boot**, **TPM**, **LUKS disk encryption**, and **MOK module signing**.

---

## 1. Download the stock ISO

On a Linux system, fetch the latest ISO:

```bash
wget https://releases.ubuntu.com/24.04/ubuntu-24.04.3-desktop-amd64.iso
```

Expected output:

```
Saving to: ‘ubuntu-24.04.3-desktop-amd64.iso’
ubuntu-24.04.3-desktop-amd64.iso  100%[================================>]  4.3G  25MB/s in 3m 0s
```

---

## 2. Prepare environment

Install the required tools:

```bash
sudo apt update
sudo apt install xorriso rsync pv -y
```

---

## 3. Run the remaster script

Make sure your script is executable:

```bash
chmod +x remaster-ubuntu-autoinstall.sh
```

Run it against the ISO:

```bash
sudo ./remaster-ubuntu-autoinstall.sh ubuntu-24.04.3-desktop-amd64.iso
```

Expected terminal output (simplified):

```
[*] Cleaning up...
[*] Mounting ISO...
[*] Copying ISO contents...
    4.3GiB  100%  30.5MB/s    0:02:20 (rsync progress bar)
[*] Unmounting ISO...
[*] Adding shared autoinstall config...
[*] Detecting ISO type...
[*] ISO type detected: desktop
[*] Patching GRUB (UEFI boot)...
[*] Creating GRUB-only Desktop ISO...
    4.3GiB  100%  28.1MB/s    0:02:15 (pv progress bar)
[*] Done. New ISO created: ubuntu-autoinstall.iso
```

---

## 4. Write the remastered ISO to USB

Insert a USB stick and identify its device path (`lsblk` can help, e.g. `/dev/sdb`). Then write:

```bash
sudo dd if=ubuntu-autoinstall.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Replace `/dev/sdX` with your USB device. This erases the drive.

Expected output:

```
4430000000 bytes (4.4 GB, 4.1 GiB) copied, 150 s, 29.5 MB/s
```

---

## 5. Boot from USB

Reboot the target machine and boot from the USB stick.

- **GRUB boot menu** appears briefly.  
- The installer starts with **autoinstall enabled**.  

You’ll see the **interactive sections**:  
- Create a user (username/password)  
- Choose disk layout  
- Enter a LUKS passphrase  

Everything else (package installs, Secure Boot enforcement, TPM tools, MOK generation) happens automatically.

---

## 6. MOK Enrollment Prompt

On the **first reboot after installation**, you’ll see the **blue MOK Manager screen**:

1. Choose **Enroll MOK**.  
2. Confirm the certificate.  
3. Reboot again.  

After this, the system will accept kernels/modules signed with your auto-generated MOK.

---

## 7. Verify installation

Log into the system and check the autoinstall summary log:

```bash
cat /var/log/autoinstall-summary.log
```

Expected contents:

```
===== Ubuntu Autoinstall Summary =====
Date: Sun Sep 21 14:15:00 UTC 2025

[ Secure Boot Status ]
SecureBoot enabled

[ TPM Devices ]
crw------- 1 root root 10, 224 Sep 21 14:15 /dev/tpm0

[ LUKS Devices ]
LUKS header information
Version:        2
Cipher name:    aes
...

[ MOK Enrollment Files ]
-rw------- 1 root root 3243 Sep 21 14:15 MOK.crt
-rw------- 1 root root 1679 Sep 21 14:15 MOK.key
```

---

## 8. Test kernel updates

Update the system to trigger kernel signing:

```bash
sudo apt update && sudo apt upgrade -y
```

During kernel install, you should see messages like:

```
[*] Signing kernel /boot/vmlinuz-6.8.0-36-generic...
```

This confirms the **postinst hook** is signing kernels and modules with your MOK automatically.

---

## ✅ End Result

- Ubuntu 24.04 Desktop installed with:
  - Secure Boot enforced
  - Full-disk LUKS encryption
  - TPM2 tools + Clevis preinstalled
  - Auto MOK enrollment
  - Kernel and module signing automation
- Verifiable log at `/var/log/autoinstall-summary.log`
