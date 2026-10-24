#!/usr/bin/env bash
set -euo pipefail

echo "=== Building ArchPup 26 ==="
WORK_DIR="/home/runner/archpup-build"
ISO_DIR="${WORK_DIR}/iso"
ROOTFS="${WORK_DIR}/rootfs"
INITRD="${WORK_DIR}/initrd"
OUT_DIR="$(pwd)/out"

rm -rf "${WORK_DIR}"
mkdir -p "${ISO_DIR}/isolinux" "${ISO_DIR}/boot" "${ROOTFS}" "${INITRD}/"{bin,sbin,dev,proc,sys,mnt,newroot} "${OUT_DIR}"

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

# 3. Install packages inside rootfs
chroot "${ROOTFS}" /bin/bash -c "
pacman-key --init && pacman-key --populate archlinux
pacman -Sy --noconfirm --needed linux busybox xorg-server xorg-xinit xorg-xrandr xorg-xsetroot xf86-video-vesa xf86-video-fbdev xf86-input-libinput jwm xterm feh geany
pacman -Scc --noconfirm
"

# Copy kernel out and unmount virtual filesystems immediately
cp "${ROOTFS}/boot/vmlinuz-linux" "${ISO_DIR}/boot/vmlinuz"
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

# 5. Build live initramfs
cp "${ROOTFS}/usr/bin/busybox" "${INITRD}/bin/busybox"
chmod +x "${INITRD}/bin/busybox"
for t in sh mount umount mkdir switch_root sleep echo cat ls blkid modprobe; do ln -sf busybox "${INITRD}/bin/$t"; done

cat << 'EOF' > "${INITRD}/init"
#!/bin/sh
export PATH=/bin:/sbin
mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mkdir -p /mnt/cdrom /mnt/sfs /mnt/rw /newroot
for dev in /dev/sr* /dev/sd* /dev/vd*; do
  [ -b "$dev" ] || continue
  mount -o ro "$dev" /mnt/cdrom 2>/dev/null || continue
  [ -f /mnt/cdrom/01-archpup.sfs ] && break
  umount /mnt/cdrom 2>/dev/null
done
mount -t squashfs -o loop /mnt/cdrom/01-archpup.sfs /mnt/sfs
mount -t tmpfs -o mode=0755 tmpfs /mnt/rw
mkdir -p /mnt/rw/upper /mnt/rw/work
mount -t overlay overlay -o lowerdir=/mnt/sfs,upperdir=/mnt/rw/upper,workdir=/mnt/rw/work /newroot
mkdir -p /newroot/mnt/cdrom
mount --move /mnt/cdrom /newroot/mnt/cdrom
umount /sys /proc /dev
exec switch_root /newroot /sbin/init
EOF
chmod +x "${INITRD}/init"
(cd "${INITRD}" && find . -print0 | cpio --null -ov --format=newc | gzip -9) > "${ISO_DIR}/boot/initrd.img"

# 6. SquashFS & ISO creation
mksquashfs "${ROOTFS}" "${ISO_DIR}/01-archpup.sfs" -comp xz -b 1024k -noappend -wildcards -e "dev/*" "proc/*" "sys/*" "run/*"
cp /usr/lib/ISOLINUX/isolinux.bin "${ISO_DIR}/isolinux/"
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "${ISO_DIR}/isolinux/"

cat << 'EOF' > "${ISO_DIR}/isolinux/isolinux.cfg"
DEFAULT archpup
TIMEOUT 50
PROMPT 1
LABEL archpup
  KERNEL /boot/vmlinuz
  INITRD /boot/initrd.img
  APPEND quiet
EOF

xorriso -as mkisofs -iso-level 3 -R -J -l \
  -b isolinux/isolinux.bin -c isolinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -o "${OUT_DIR}/ArchPup-26-x86_64.iso" "${ISO_DIR}"

isohybrid "${OUT_DIR}/ArchPup-26-x86_64.iso" || true
echo "=== ArchPup ISO built successfully ==="
