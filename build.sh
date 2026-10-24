#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "   Building Bootable ArchPup 26 (x86_64) "
echo "   Live Boot + OverlayFS RAM + JWM/X11   "
echo "=========================================="

WORK_DIR="/tmp/archpup-build"
ISO_DIR="${WORK_DIR}/iso"
ROOTFS_DIR="${WORK_DIR}/rootfs"
INITRD_DIR="${WORK_DIR}/initrd"
OUT_DIR="$(pwd)/out"

rm -rf "${WORK_DIR}"
mkdir -p "${ISO_DIR}/boot/syslinux" "${ROOTFS_DIR}" "${INITRD_DIR}" "${OUT_DIR}"

BOOTSTRAP_URL="https://geo.mirror.pkgbuild.com/iso/2026.10.01/archlinux-bootstrap-2026.10.01-x86_64.tar.zst"
ARCHIVE_NAME="$(basename "${BOOTSTRAP_URL}")"

echo "=== [1/7] Downloading Arch Linux Rootfs ==="
curl -fsSL --retry 3 "${BOOTSTRAP_URL}" -o "/tmp/${ARCHIVE_NAME}"

echo "=== [2/7] Extracting rootfs ==="
tar --zstd -xf "/tmp/${ARCHIVE_NAME}" -C "${ROOTFS_DIR}" --strip-components=1

echo "=== [3/7] Configuring Mirrors, DNS & Keys ==="
cp /etc/resolv.conf "${ROOTFS_DIR}/etc/resolv.conf"
echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' > "${ROOTFS_DIR}/etc/pacman.d/mirrorlist"
echo "archpup" > "${ROOTFS_DIR}/etc/hostname"

# Mount virtual filesystems for chroot
mount --bind /dev "${ROOTFS_DIR}/dev"
mount --bind /proc "${ROOTFS_DIR}/proc"
mount --bind /sys "${ROOTFS_DIR}/sys"

cleanup() {
    umount -l "${ROOTFS_DIR}/dev" 2>/dev/null || true
    umount -l "${ROOTFS_DIR}/proc" 2>/dev/null || true
    umount -l "${ROOTFS_DIR}/sys" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== [4/7] Installing Kernel & Desktop Packages (Xorg + JWM) ==="
chroot "${ROOTFS_DIR}" /bin/bash -c "
set -e
pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm --needed \
    linux \
    syslinux \
    busybox \
    xorg-server \
    xorg-xinit \
    xorg-xrandr \
    xorg-xsetroot \
    jwm \
    xterm \
    feh \
    leafpad
pacman -Scc --noconfirm
"

# Copy kernel out of rootfs
cp "${ROOTFS_DIR}/boot/vmlinuz-linux" "${ISO_DIR}/boot/vmlinuz"

# Copy isolinux binaries
cp "${ROOTFS_DIR}/usr/lib/syslinux/bios/isolinux.bin" "${ISO_DIR}/boot/syslinux/" || cp /usr/lib/syslinux/bios/isolinux.bin "${ISO_DIR}/boot/syslinux/" 2>/dev/null || cp /usr/lib/ISOLINUX/isolinux.bin "${ISO_DIR}/boot/syslinux/"
cp "${ROOTFS_DIR}/usr/lib/syslinux/bios/ldlinux.c32" "${ISO_DIR}/boot/syslinux/" || cp /usr/lib/syslinux/bios/ldlinux.c32 "${ISO_DIR}/boot/syslinux/" 2>/dev/null || cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "${ISO_DIR}/boot/syslinux/"

echo "=== [5/7] Setting up Desktop Autologin & JWM ==="
# Auto-start X11 on login
cat << 'EOF' > "${ROOTFS_DIR}/root/.bash_profile"
[[ -z $DISPLAY && $XDG_VTNR -eq 1 ]] && exec startx
EOF

cat << 'EOF' > "${ROOTFS_DIR}/root/.xinitrc"
#!/bin/sh
xsetroot -solid "#2b4a6f" &
exec jwm
EOF
chmod +x "${ROOTFS_DIR}/root/.xinitrc"

cat << 'EOF' > "${ROOTFS_DIR}/root/.jwmrc"
<?xml version="1.0"?>
<JWM>
    <RootMenu label="Menu" height="24">
        <Program label="Terminal">xterm</Program>
        <Program label="Text Editor">leafpad</Program>
        <Separator/>
        <Restart label="Restart JWM"/>
        <Exit label="Exit to Prompt" confirm="true"/>
    </RootMenu>

    <Tray x="0" y="-1" autohide="off" height="28">
        <TrayButton label="ArchPup">root:1</TrayButton>
        <Spacer width="4"/>
        <TaskList maxwidth="200"/>
        <Dock/>
        <Clock format="%H:%M"><Button mask="123">exec:xterm -e cal</Button></Clock>
    </Tray>

    <Style>
        <Font>Sans-10</Font>
        <Width>4</Width>
        <Height>22</Height>
        <Active>
            <Text>#ffffff</Text>
            <Title>#2b4a6f:#17293e</Title>
            <Corner>#ffffff</Corner>
            <Outline>#000000</Outline>
        </Active>
        <Inactive>
            <Text>#aaaaaa</Text>
            <Title>#444444:#222222</Title>
            <Corner>#aaaaaa</Corner>
            <Outline>#000000</Outline>
        </Inactive>
    </Style>

    <Key key="Up">up</Key>
    <Key key="Down">down</Key>
    <Key key="Right">right</Key>
    <Key key="Left">left</Key>
    <Key key="Escape">escape</Key>
    <Key mask="A" key="Tab">nextstacked</Key>
    <Key mask="A" key="F4">close</Key>
</JWM>
EOF

# Auto-login as root on tty1
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/getty@tty1.service.d"
cat << 'EOF' > "${ROOTFS_DIR}/etc/systemd/system/getty@tty1.service.d/autologin.conf"
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin root %I $TERM
EOF

# Strip caches before squashing
rm -rf "${ROOTFS_DIR}/var/cache/pacman/pkg/"*
rm -rf "${ROOTFS_DIR}/tmp/"*

echo "=== [6/7] Building Puppy-Style Live Initramfs ==="
mkdir -p "${INITRD_DIR}"/{bin,sbin,dev,proc,sys,mnt,newroot}
cp "${ROOTFS_DIR}/usr/bin/busybox" "${INITRD_DIR}/bin/busybox"
chmod +x "${INITRD_DIR}/bin/busybox"
for tool in sh mount umount mkdir switch_root sleep echo cat ls blkid modprobe; do
    ln -sf busybox "${INITRD_DIR}/bin/${tool}"
done

cat << 'EOF' > "${INITRD_DIR}/init"
#!/bin/sh
export PATH=/bin:/sbin

mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys

echo "=========================================="
echo "   ArchPup 26 Live Boot Init              "
echo "=========================================="

mkdir -p /mnt/cdrom /mnt/sfs /mnt/overlay /mnt/rw /newroot

# Scan for media containing 01-archpup.sfs
SFS_FOUND=0
for dev in /dev/sr* /dev/sd* /dev/vd*; do
    [ -b "$dev" ] || continue
    mount -o ro "$dev" /mnt/cdrom 2>/dev/null || continue
    if [ -f /mnt/cdrom/01-archpup.sfs ]; then
        echo "Found ArchPup media on $dev"
        SFS_FOUND=1
        break
    fi
    umount /mnt/cdrom 2>/dev/null
done

if [ "$SFS_FOUND" -ne 1 ]; then
    echo "ERROR: Could not locate 01-archpup.sfs on any drive!"
    echo "Dropping to rescue shell..."
    exec sh
fi

# Mount the SquashFS layer
mount -t squashfs -o loop /mnt/cdrom/01-archpup.sfs /mnt/sfs

# Setup writable RAM overlay
mount -t tmpfs -o mode=0755 tmpfs /mnt/rw
mkdir -p /mnt/rw/upper /mnt/rw/work
mount -t overlay overlay -o lowerdir=/mnt/sfs,upperdir=/mnt/rw/upper,workdir=/mnt/rw/work /newroot

# Move mounts to new root
mkdir -p /newroot/mnt/cdrom
mount --move /mnt/cdrom /newroot/mnt/cdrom

umount /sys
umount /proc
umount /dev

echo "Pivoting root and launching ArchPup..."
exec switch_root /newroot /sbin/init
EOF

chmod +x "${INITRD_DIR}/init"

# Package the initramfs
(cd "${INITRD_DIR}" && find . -print0 | cpio --null -ov --format=newc | gzip -9) > "${ISO_DIR}/boot/initrd.img"

echo "=== [7/7] Squashing Rootfs & Creating Bootable Hybrid ISO ==="
mksquashfs "${ROOTFS_DIR}" "${ISO_DIR}/01-archpup.sfs" -comp xz -b 1024k -noappend

cat << 'EOF' > "${ISO_DIR}/boot/syslinux/syslinux.cfg"
DEFAULT archpup
TIMEOUT 50
PROMPT 1

LABEL archpup
    MENU LABEL ArchPup 26 (x86_64) Live
    KERNEL /boot/vmlinuz
    INITRD /boot/initrd.img
    APPEND quiet
EOF

xorriso -as mkisofs \
    -iso-level 3 \
    -R -J -l \
    -b boot/syslinux/isolinux.bin \
    -c boot/syslinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -o "${OUT_DIR}/ArchPup-26-x86_64.iso" \
    "${ISO_DIR}"

echo "=========================================="
echo " Bootable ISO created successfully!       "
echo " ISO: ${OUT_DIR}/ArchPup-26-x86_64.iso   "
echo "=========================================="
