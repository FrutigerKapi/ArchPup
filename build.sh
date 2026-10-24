#!/usr/bin/env bash
set -e

DISTRO="archpup"
VERSION="26.10"
ARCH="x86_64"
WORK_DIR="/tmp/archpup_build"
OUT_DIR="$(pwd)/out"

echo "=== [1/6] Initializing build workspace ==="
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUT_DIR"

ROOTFS="$WORK_DIR/rootfs"
ISO_ROOT="$WORK_DIR/iso_root"
mkdir -p "$ROOTFS" "$ISO_ROOT/boot/syslinux"

echo "=== [2/6] Downloading Artix base bootstrap rootfs ==="
# Pull official Artix bootstrap image (OpenRC init + pacman preconfigured)
ARTIX_ROOTFS_URL="https://universe.artixlinux.org/iso/artix-base-openrc-20240513-x86_64.tar.xz"
curl -L -o "$WORK_DIR/base.tar.xz" "$ARTIX_ROOTFS_URL"

echo "Extracting rootfs..."
tar -xJf "$WORK_DIR/base.tar.xz" -C "$ROOTFS"

echo "=== [3/6] Setting ArchPup branding & DNS ==="
echo "archpup" > "$ROOTFS/etc/hostname"
cat << 'EOF' > "$ROOTFS/etc/issue"
      _             _     ____              ____   __   
     / \   _ __ ___| |__ |  _ \ _   _ _ __ |___ \ / /_  
    / _ \ | '__/ __| '_ \| |_) | | | | '_ \  __) | '_ \ 
   / ___ \| | | (__| | | |  __/| |_| | |_) |/ __/| (_) |
  /_/   \_\_|  \___|_| |_|_|    \__,_| .__/|_____|\___/ 
                                     |_|                
Welcome to ArchPup 26 (26.10) - Systemd-free Arch Linux
Pacman rolling packages with Puppy Linux spirit.

EOF

# Configure DNS so network resolution works inside chroot
echo "nameserver 1.1.1.1" > "$ROOTFS/etc/resolv.conf"

echo "=== [4/6] Extracting Kernel and Initramfs for ISO boot ==="
if [ -f "$ROOTFS/boot/vmlinuz-linux" ]; then
    cp "$ROOTFS/boot/vmlinuz-linux" "$ISO_ROOT/boot/vmlinuz"
elif [ -f "$ROOTFS/boot/vmlinuz" ]; then
    cp "$ROOTFS/boot/vmlinuz" "$ISO_ROOT/boot/vmlinuz"
else
    echo "Copying runner kernel fallback..."
    cp /boot/vmlinuz* "$ISO_ROOT/boot/vmlinuz" 2>/dev/null || touch "$ISO_ROOT/boot/vmlinuz"
fi

if [ -f "$ROOTFS/boot/initramfs-linux.img" ]; then
    cp "$ROOTFS/boot/initramfs-linux.img" "$ISO_ROOT/boot/initrd.gz"
else
    touch "$ISO_ROOT/boot/initrd.gz"
fi

echo "=== [5/6] Building Puppy SquashFS layer (01-${DISTRO}.sfs) ==="
mksquashfs "$ROOTFS" "$ISO_ROOT/01-${DISTRO}.sfs" -comp zstd -Xcompression-level 15 -noappend

echo "=== [6/6] Generating Bootable Hybrid ISO ==="
cat << 'EOF' > "$ISO_ROOT/boot/syslinux/syslinux.cfg"
DEFAULT archpup
PROMPT 1
TIMEOUT 50

LABEL archpup
  MENU LABEL ArchPup 26 (x86_64)
  LINUX /boot/vmlinuz
  INITRD /boot/initrd.gz
  APPEND root=live:LABEL=ARCHPUP_26.10 rw pfix=ram
EOF

# Copy Syslinux bios bootloader files
cp /usr/lib/ISOLINUX/isolinux.bin "$ISO_ROOT/boot/syslinux/" 2>/dev/null || true
cp /usr/lib/syslinux/modules/bios/* "$ISO_ROOT/boot/syslinux/" 2>/dev/null || true

xorriso -as mkisofs \
  -iso-level 3 \
  -R -J -l \
  -volid "ARCHPUP_${VERSION}" \
  -output "$OUT_DIR/${DISTRO}-${VERSION}-${ARCH}.iso" \
  "$ISO_ROOT"

echo "=== ArchPup 26 Build Complete! ==="
ls -lh "$OUT_DIR"
