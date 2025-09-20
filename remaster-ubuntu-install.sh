#!/bin/bash
# Unified Ubuntu ISO Remaster Script (Desktop + Server)
# - Secure Boot enforced
# - Disk encryption (interactive LUKS passphrase)
# - User creds & partitioning interactive
# - TPM2 + Clevis installed
# - Auto MOK keypair + enrollment
# - Kernel/module auto-signing hook
# - Autoinstall summary log on first boot
#
# Usage: ./remaster-ubuntu-autoinstall.sh ubuntu.iso

set -e

ISO="$1"
if [[ -z "$ISO" ]]; then
  echo "Usage: $0 <ubuntu.iso>"
  exit 1
fi

WORKDIR=ubuntu-iso-work
MOUNTDIR=iso-mount
NEWISO=ubuntu-autoinstall.iso

echo "[*] Cleaning up..."
rm -rf "$WORKDIR" "$MOUNTDIR"
mkdir -p "$WORKDIR" "$MOUNTDIR"

echo "[*] Mounting ISO..."
sudo mount -o loop "$ISO" "$MOUNTDIR"

echo "[*] Copying ISO contents..."
rsync -a "$MOUNTDIR"/ "$WORKDIR"/

echo "[*] Unmounting ISO..."
sudo umount "$MOUNTDIR"

echo "[*] Fixing ownership..."
sudo chown -R "$USER:$USER" "$WORKDIR"

echo "[*] Adding shared autoinstall config..."
mkdir -p "$WORKDIR/autoinstall"
cat > "$WORKDIR/autoinstall/user-data" <<'EOF'
#cloud-config
autoinstall:
  version: 1
  early-commands:
    - curtin in-target --target=/target -- update-secureboot-policy --enforce
  identity: {}
  storage: {}
  interactive-sections:
    - identity
    - storage
    - luks
  keyboard:
    layout: us
  locale: en_US.UTF-8
  packages:
    - tpm2-tools
    - clevis
    - clevis-luks
    - clevis-initramfs
    - dkms
    - sbsigntool
  user-data:
    disable_root: true
  late-commands:
    - curtin in-target --target=/target mkdir -p /root/mok
    - curtin in-target --target=/target openssl req -new -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -subj "/CN=Auto MOK Secure Boot/" -keyout /root/mok/MOK.key -out /root/mok/MOK.crt
    - curtin in-target --target=/target mokutil --import /root/mok/MOK.crt || true
    - curtin in-target --target=/target bash -c 'cat > /etc/kernel/postinst.d/zz-sign-kernel << "HOOK"
#!/bin/bash
MOK_KEY=/root/mok/MOK.key
MOK_CRT=/root/mok/MOK.crt
KERNEL_VER="$1"
KERNEL_IMG="/boot/vmlinuz-${KERNEL_VER}"
SIGNED_IMG="/boot/vmlinuz-${KERNEL_VER}.signed"

if [ -f "$MOK_KEY" ] && [ -f "$MOK_CRT" ]; then
    echo "[*] Signing kernel ${KERNEL_IMG}..."
    sbsign --key $MOK_KEY --cert $MOK_CRT --output $SIGNED_IMG $KERNEL_IMG
    grub-mkconfig -o /boot/grub/grub.cfg
fi

SIGN_SCRIPT="/usr/src/linux-headers-${KERNEL_VER}/scripts/sign-file"
if [ -x "$SIGN_SCRIPT" ]; then
    find /lib/modules/${KERNEL_VER} -type f -name "*.ko" -print0 | \
    xargs -0 -n1 -I{} $SIGN_SCRIPT sha256 $MOK_KEY $MOK_CRT {}
fi
HOOK
chmod +x /etc/kernel/postinst.d/zz-sign-kernel'

    # Add autoinstall summary systemd unit
    - curtin in-target --target=/target bash -c 'cat > /etc/systemd/system/autoinstall-summary.service << "UNIT"
[Unit]
Description=Autoinstall Summary Logger
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/autoinstall-summary.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
UNIT'

    - curtin in-target --target=/target bash -c 'cat > /usr/local/bin/autoinstall-summary.sh << "SCRIPT"
#!/bin/bash
LOGFILE=/var/log/autoinstall-summary.log

{
  echo "===== Ubuntu Autoinstall Summary ====="
  echo "Date: $(date)"
  echo
  echo "[ Secure Boot Status ]"
  mokutil --sb-state 2>/dev/null || echo "mokutil not available"
  echo
  echo "[ TPM Devices ]"
  ls -l /dev/tpm* 2>/dev/null || echo "No TPM device found"
  echo
  echo "[ LUKS Devices ]"
  for dev in /dev/disk/by-uuid/*; do
    cryptsetup luksDump "\$dev" 2>/dev/null | head -n 10 && echo "---"
  done || echo "No LUKS devices detected"
  echo
  echo "[ MOK Enrollment Files ]"
  ls -l /root/mok 2>/dev/null || echo "No MOK dir found"
} > "\$LOGFILE" 2>&1

systemctl disable autoinstall-summary.service
SCRIPT
chmod +x /usr/local/bin/autoinstall-summary.sh'

    - curtin in-target --target=/target systemctl enable autoinstall-summary.service
EOF

cat > "$WORKDIR/autoinstall/meta-data" <<EOF
instance-id: ubuntu-autoinstall
local-hostname: ubuntu-secure
EOF

echo "[*] Detecting ISO type..."
if [[ -f $WORKDIR/boot/grub/grub.cfg && -f $WORKDIR/isolinux/txt.cfg ]]; then
    ISO_TYPE="server"   # legacy server ISOs (20.04/22.04) with isolinux
elif [[ -f $WORKDIR/boot/grub/grub.cfg ]]; then
    ISO_TYPE="desktop"  # modern desktop (24.04+) and grub-only ISOs
else
    echo "Unknown ISO type. Exiting."
    exit 1
fi

echo "[*] ISO type detected: $ISO_TYPE"

if [[ "$ISO_TYPE" == "desktop" ]]; then
    echo "[*] Patching GRUB (UEFI boot)..."
    sed -i 's/quiet splash/quiet splash autoinstall ds=nocloud;s=\/cdrom\/autoinstall\//' "$WORKDIR/boot/grub/grub.cfg"

    if [[ -f $WORKDIR/isolinux/txt.cfg ]]; then
        echo "[*] Patching ISOLINUX (BIOS boot)..."
        sed -i 's/quiet splash/quiet splash autoinstall ds=nocloud;s=\/cdrom\/autoinstall\//' "$WORKDIR/isolinux/txt.cfg"
    fi
fi

if [[ "$ISO_TYPE" == "server" ]]; then
    echo "[*] Patching GRUB (UEFI+BIOS boot)..."
    sed -i 's/---/ autoinstall ds=nocloud;s=\/cdrom\/autoinstall\/ ---/' "$WORKDIR/boot/grub/grub.cfg"
fi

echo "[*] Building new ISO..."
cd "$WORKDIR"

if [[ "$ISO_TYPE" == "desktop" ]]; then
    echo "[*] Creating GRUB-only Desktop ISO..."

    EFI_FILE=""
    if [[ -f EFI/BOOT/bootx64.efi ]]; then
        EFI_FILE="EFI/BOOT/bootx64.efi"
    elif [[ -f EFI/boot/grubx64.efi ]]; then
        EFI_FILE="EFI/boot/grubx64.efi"
    else
        echo "ERROR: Could not find EFI boot file in ISO."
        exit 1
    fi

    xorriso -as mkisofs -r -V "UBUNTU_AUTOINSTALL" \
      -o ../"$NEWISO" \
      -J -l -iso-level 3 \
      -isohybrid-gpt-basdat \
      -partition_offset 16 \
      -eltorito-alt-boot \
      -e "$EFI_FILE" \
      -no-emul-boot \
      .
else
    echo "[*] Creating hybrid Server ISO..."
    xorriso -as mkisofs -r -V "UBUNTU_AUTOINSTALL" \
      -o ../"$NEWISO" \
      -J -l -cache-inodes -iso-level 3 -isohybrid-mbr isolinux/isohdpfx.bin \
      -partition_offset 16 \
      -b isolinux/isolinux.bin -c isolinux/boot.cat \
      -no-emul-boot -boot-load-size 4 -boot-info-table \
      -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
      .
fi

cd ..
echo "[*] Done. New ISO created: $NEWISO"
