#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "   Building Bootable ArchPup 26 (x86_64) "
echo "   Live Boot + OverlayFS RAM + JWM/X11   "
echo "=========================================="

WORK_DIR="/home/runner/archpup-build"
ISO_DIR="${WORK_DIR}/iso"
ROOTFS_DIR="${WORK_DIR}/rootfs"
INITRD_DIR="${WORK_DIR}/initrd"
OUT_DIR="$(pwd)/out"

# Clean slate
rm -rf "${WORK_DIR}"
mkdir -p "${ISO_DIR}/isolinux" "${ISO_DIR}/boot" "${ROOTFS_DIR}" "${INITRD_DIR}" "${OUT_DIR}"

BOOTSTRAP_URL="https://geo.mirror.pkgbuild.com/iso/2026.10.01/archlinux-bootstrap-2026.10.01-x86_64.tar.zst"
ARCHIVE_NAME="$(basename "${BOOTSTRAP_URL}")"

echo "=== [1/7] Downloading Arch Linux Bootstrap ==="
curl -fsSL --retry 3 "${BOOTSTRAP_URL}" -o "/tmp/${ARCHIVE_NAME}"

echo "=== [2/7] Extracting Rootfs ==="
tar --zstd -xf "/tmp/${ARCHIVE_NAME}" -C "${ROOTFS_DIR}" --strip-components=1

echo "=== [3/7] Setting Up Mirrors & Pacman Config ==="
cp /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"
echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' > "${ROOTFS_DIR}/etc/pacman.d/mirrorlist"
echo "archpup" > "${ROOTFS_DIR}/etc/hostname"

# Disable disk space check inside chroot
sed -i 's/^[[:space:]]*CheckSpace/#CheckSpace/' "${ROOTFS_DIR}/etc/pacman.conf"

# Bind mounts for chroot
mount --bind /dev "${ROOTFS_DIR}/dev"
mount --bind /proc "${ROOTFS_DIR}/proc"
mount --bind /sys "${ROOTFS_DIR}/sys"

echo "=== [4/7] Installing Core Packages, Kernel & JWM ==="
chroot "${ROOTFS_DIR}" /bin/bash -c "
set -e
pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm --needed \
    linux \
    busybox \
    xorg-server \
    xorg-xinit \
    xorg-xrandr \
    xorg-xsetroot \
    xf86-video-vesa \
    xf86-video-fbdev \
    xf86-input-libinput \
    jwm \
    xterm \
    feh \
    geany
pacman -Scc --noconfirm
"

# Copy kernel out of rootfs BEFORE unmounting
cp "${ROOTFS_DIR}/boot/vmlinuz-linux" "${ISO_DIR}/boot/vmlinuz"

# IMMEDIATELY UNMOUNT proc, sys, dev
umount -f -l "${ROOTFS_DIR}/dev" 2>/dev/null || true
umount -f -l "${ROOTFS_DIR}/proc" 2>/dev/null || true
umount -f -l "${ROOTFS_DIR}/sys" 2>/dev/null || true

echo "=== [5/7] Configuring Puppy Desktop & Auto-Login ==="
# Autologin on tty1
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/getty@tty1.service.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/systemd/system/getty@tty1.service.d/autologin.conf"
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear
