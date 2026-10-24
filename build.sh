#!/usr/bin/env bash
set -e

DISTRO="archpup"
VERSION="26.10"
ARCH="x86_64"
WORK_DIR="/tmp/archpup_build"
OUT_DIR="$(pwd)/out"

echo "=== [1/5] Initializing build environment ==="
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" "$OUT_DIR"

ROOTFS="$WORK_DIR/rootfs"
ISO_ROOT="$WORK_DIR/iso_root"
mkdir -p "$ROOTFS" "$ISO_ROOT"

echo "=== [2/5] Creating basic filesystem tree ==="
mkdir -p "$ROOTFS"/{bin,sbin,usr/bin,usr/sbin,etc,proc,sys,dev,tmp,root,home,run,var}
chmod 1777 "$ROOTFS/tmp"

echo "archpup" > "$ROOTFS/etc/hostname"
echo "ArchPup 26 ($VERSION) - Lightweight Arch/Puppy Hybrid" > "$ROOTFS/etc/issue"

echo "=== [3/5] Setting up Puppy-style layout ==="
mkdir -p "$ISO_ROOT/boot/syslinux"

echo "Compressing base SquashFS layer (01-${DISTRO}.sfs)..."
mksquashfs "$ROOTFS" "$ISO_ROOT/01-${DISTRO}.sfs" -comp zstd -Xcompression-level 15 -noappend

echo "=== [4/5] Preparing bootloader files ==="
cat << 'EOF' > "$ISO_ROOT/boot/syslinux/syslinux.cfg"
DEFAULT archpup
PROMPT 0
TIMEOUT 50

LABEL archpup
  MENU LABEL ArchPup 26 (x86_64)
  LINUX /boot/vmlinuz
  INITRD /boot/initrd.gz
  APPEND pfix=ram
EOF

mkdir -p "$ISO_ROOT/boot"
touch "$ISO_ROOT/boot/vmlinuz"
touch "$ISO_ROOT/boot/initrd.gz"

echo "=== [5/5] Building bootable ISO with xorriso ==="
xorriso -as mkisofs \
  -iso-level 3 \
  -full-iso-9660-filenames \
  -volid "ARCHPUP_${VERSION}" \
  -output "$OUT_DIR/${DISTRO}-${VERSION}-${ARCH}.iso" \
  "$ISO_ROOT"

echo "=== Build finished! Created: $OUT_DIR/${DISTRO}-${VERSION}-${ARCH}.iso ==="
