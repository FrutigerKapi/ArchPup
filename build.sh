#!/usr/bin/env bash
set -euo pipefail

echo "=== Building ArchPup 26 ==="
WORK_DIR="/home/runner/archpup-build"
ISO_DIR="${WORK_DIR}/iso"
ROOTFS="${WORK_DIR}/rootfs"
OUT_DIR="$(pwd)/out"

rm -rf "${WORK_DIR}"
mkdir -p "${ISO_DIR}/isolinux" "${ISO_DIR}/boot" "${ISO_DIR}/arch/x86_64" "${ROOTFS}" "${OUT_DIR}"

# 1. Download & Extract Arch bootstrap
curl -fsSL --retry 3 "https://geo.mirror.pkgbuild.com/iso/2026.10.01/archlinux-bootstrap-2026.10.01-x86_64.tar.zst" -o /tmp/arch.tar.zst
tar --zstd -xf /tmp/arch.tar.zst -C "${ROOTFS}" --strip-components=1

# 2. Config & Bind Mounts
cp /etc/resolv.conf "${ROOTFS}/etc/resolv.conf"
echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' > "${ROOTFS}/etc/pacman.d/mirrorlist"
echo "archpup" > "${ROOTFS}/etc/hostname"
sed -i 's/^[[:space:]]*CheckSpace/#CheckSpace/' "${ROOTFS}/etc/pacman.conf"

mount --bind /dev "${ROOTFS}/dev"
mount --bind /proc "${ROOTFS}/proc"
mount --bind /sys "${ROOTFS}/sys"

# 3. Install packages & generate full live initramfs
chroot "${ROOTFS}" /bin/bash -c "
pacman-key --init && pacman-key --populate archlinux
pacman -Sy --noconfirm --needed linux mkinitcpio mkinitcpio-archiso xorg-server xorg-xinit xorg-xrandr xorg-xsetroot xf86-video-vesa xf86-video-fbdev xf86-input-libinput jwm xterm feh geany
echo 'HOOKS=(base udev modconf archiso block filesystems)' > /etc/mkinitcpio.conf
KVER=\$(ls /lib/modules | head -n1)
mkinitcpio -k \"\${KVER}\" -c /etc/mkinitcpio.conf -g /boot/initramfs.img
pacman -Scc --noconfirm
"

# Copy kernel & initramfs out and unmount virtual filesystems
cp "${ROOTFS}/boot/vmlinuz-linux" "${ISO_DIR}/boot/vmlinuz"
cp "${ROOTFS}/boot/initramfs.img" "${ISO_DIR}/boot/initramfs.img"
umount -f -l "${ROOTFS}/dev" "${ROOTFS}/proc" "${ROOTFS}/sys" 2>/dev/null || true

# 4. Autologin & JWM Setup
mkdir -p "${ROOTFS}/etc/systemd/system/getty@tty1.service.d"
echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin root %I \$TERM" > "${ROOTFS}/etc/systemd/system/getty@tty1.service.d/autologin.conf"
echo '[[ -z $DISPLAY && $XDG_VTNR -eq 1 ]] && exec startx' > "${ROOTFS}/root/.bash_profile"
echo -e '#!/bin/sh\nxsetroot -solid "#2b4a6f" &\nexec jwm' > "${ROOTFS}/root/.xinitrc"
chmod +x "${ROOTFS}/root/.xinitrc"

# JWM minimal Puppy layout
cat << 'EOF' > "${ROOTFS}/root/.jwmrc"
<?xml version="1.0"?>
<JWM>
  <RootMenu label="Menu" height="24">
    <Program label="Terminal">xterm</Program>
    <Program label="Geany Text Editor">geany</Program>
    <Separator/>
    <Restart label="Restart JWM"/>
    <Exit label="Exit" confirm="true"/>
  </RootMenu>
  <Tray x="0" y="-1" autohide="off" height="28">
    <TrayButton label="ArchPup">root:1</TrayButton>
    <Spacer width="4"/>
    <TaskList maxwidth="200"/>
    <Dock/>
    <Clock format="%H:%M"/>
  </Tray>
</JWM>
EOF

rm -rf "${ROOTFS}/var/cache/pacman/pkg/"* "${ROOTFS}/tmp/"*

# 5. Compress rootfs into SquashFS
mksquashfs "${ROOTFS}" "${ISO_DIR}/arch/x86_64/airootfs.sfs" -comp xz -b 1024k -noappend -wildcards -e "dev/*" "proc/*" "sys/*" "run/*" "boot/*"

# 6. Syslinux & Hybrid ISO creation
cp /usr/lib/ISOLINUX/isolinux.bin "${ISO_DIR}/isolinux/"
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "${ISO_DIR}/isolinux/"

cat << 'EOF' > "${ISO_DIR}/isolinux/isolinux.cfg"
DEFAULT archpup
TIMEOUT 50
PROMPT 1

LABEL archpup
  KERNEL /boot/vmlinuz
  INITRD /boot/initramfs.img
  APPEND archisobasedir=arch archisolabel=ARCHPUP_26 quiet
EOF

xorriso -as mkisofs -iso-level 3 -R -J -l \
  -volid "ARCHPUP_26" \
  -b isolinux/isolinux.bin -c isolinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -o "${OUT_DIR}/ArchPup-26-x86_64.iso" "${ISO_DIR}"

isohybrid "${OUT_DIR}/ArchPup-26-x86_64.iso" || true
echo "=== ArchPup ISO built successfully ==="
