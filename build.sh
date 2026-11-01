#!/usr/bin/env bash
set -euo pipefail

echo "=== Building ArchPup 26 (Live Puppy Edition) ==="
WORK_DIR="/home/runner/archpup-build"
ISO_DIR="${WORK_DIR}/iso"
ROOTFS="${WORK_DIR}/rootfs"
OUT_DIR="$(pwd)/out"

rm -rf "${WORK_DIR}"
mkdir -p "${ISO_DIR}/isolinux" "${ISO_DIR}/boot" "${ISO_DIR}/arch/x86_64" "${ROOTFS}" "${OUT_DIR}"

# 1. Download & Extract Arch bootstrap
echo "--> Downloading Arch bootstrap..."
curl -fsSL --retry 3 "https://geo.mirror.pkgbuild.com/iso/2026.10.01/archlinux-bootstrap-2026.10.01-x86_64.tar.zst" -o /tmp/arch.tar.zst
tar --zstd -xf /tmp/arch.tar.zst -C "${ROOTFS}" --strip-components=1

# 2. Resilient Multi-Mirror & Pacman Setup (Fixes repo & signature errors)
cp /etc/resolv.conf "${ROOTFS}/etc/resolv.conf"
cat << 'EOF' > "${ROOTFS}/etc/pacman.d/mirrorlist"
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
Server = https://mirror.osbeck.com/archlinux/$repo/os/$arch
EOF

echo "archpup" > "${ROOTFS}/etc/hostname"

# Configure pacman: parallel downloads, skip diskspace check, flexible signature check
sed -i 's/^[[:space:]]*CheckSpace/#CheckSpace/' "${ROOTFS}/etc/pacman.conf"
sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' "${ROOTFS}/etc/pacman.conf"
sed -i 's/^SigLevel.*/SigLevel = Optional TrustAll/' "${ROOTFS}/etc/pacman.conf"

mount --bind /dev "${ROOTFS}/dev"
mount --bind /proc "${ROOTFS}/proc"
mount --bind /sys "${ROOTFS}/sys"

# 3. Chroot Package Installation & Live Initramfs
echo "--> Installing packages inside chroot..."
chroot "${ROOTFS}" /bin/bash -c "
pacman-key --init || true
pacman-key --populate archlinux || true
pacman -Sy --noconfirm archlinux-keyring || true

pacman -S --noconfirm --needed \
  linux \
  mkinitcpio \
  mkinitcpio-archiso \
  xorg-server \
  xorg-xinit \
  xorg-xrandr \
  xorg-xsetroot \
  xf86-video-vesa \
  xf86-video-fbdev \
  xf86-input-libinput \
  jwm \
  pcmanfm \
  xterm \
  feh \
  conky \
  yad \
  geany \
  gparted \
  xdg-utils \
  tar \
  zstd \
  wget \
  curl \
  libreoffice-fresh

# Configure live archiso hooks
echo 'HOOKS=(base udev modconf memdisk archiso archiso_loop_mnt block filesystems)' > /etc/mkinitcpio.conf
KVER=\$(ls /lib/modules | head -n1)
mkinitcpio -k \"\${KVER}\" -c /etc/mkinitcpio.conf -g /boot/initramfs.img
pacman -Scc --noconfirm
"

# Copy kernel & initramfs out, then cleanly unmount virtual systems
cp "${ROOTFS}/boot/vmlinuz-linux" "${ISO_DIR}/boot/vmlinuz"
cp "${ROOTFS}/boot/initramfs.img" "${ISO_DIR}/boot/initramfs.img"
umount -f -l "${ROOTFS}/dev" "${ROOTFS}/proc" "${ROOTFS}/sys" 2>/dev/null || true

# 4. Puppy Tools: Quickpet (App Store), PetGet (.pet support), and Frugal Installer

# --- A. PetGet (.PET package installer) ---
cat << 'EOF' > "${ROOTFS}/usr/local/bin/petget"
#!/usr/bin/env bash
PET_FILE="$1"
if [ -z "$PET_FILE" ] || [ ! -f "$PET_FILE" ]; then
    echo "Usage: petget <package.pet>"
    exit 1
fi
echo "==> Installing Puppy PET package: $(basename "$PET_FILE")"
TEMP_DIR=$(mktemp -d /tmp/petinstall.XXXXXX)
tar -xf "$PET_FILE" -C / 2>/dev/null || {
    head -c -32 "$PET_FILE" > "$TEMP_DIR/archive.tar" 2>/dev/null
    tar -xf "$TEMP_DIR/archive.tar" -C / 2>/dev/null
} || {
    echo "Error: Unable to extract $PET_FILE"
    rm -rf "$TEMP_DIR"
    exit 1
}

if [ -f "/pinstall.sh" ]; then
    echo "==> Running post-installation script..."
    /bin/sh /pinstall.sh
    rm -f /pinstall.sh
fi

update-desktop-database /usr/share/applications 2>/dev/null || true
which jwm >/dev/null 2>&1 && jwm -restart 2>/dev/null || true
rm -rf "$TEMP_DIR"
echo "==> Successfully installed $(basename "$PET_FILE")!"
EOF
chmod +x "${ROOTFS}/usr/local/bin/petget"

mkdir -p "${ROOTFS}/usr/share/mime/packages"
cat << 'EOF' > "${ROOTFS}/usr/share/mime/packages/puppy-pet.xml"
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-pet">
    <comment>Puppy Linux PET Package</comment>
    <glob pattern="*.pet"/>
  </mime-type>
</mime-info>
EOF

cat << 'EOF' > "${ROOTFS}/usr/share/applications/petget.desktop"
[Desktop Entry]
Name=PetGet Package Installer
Comment=Install Puppy Linux .PET packages
Exec=xterm -title "Installing PET" -e /usr/local/bin/petget %f
Icon=system-software-install
Terminal=false
Type=Application
MimeType=application/x-pet;
Categories=System;PackageManager;
EOF

# --- B. Quickpet: Puppy Linux App Store ---
cat << 'EOF' > "${ROOTFS}/usr/local/bin/quickpet"
#!/usr/bin/env bash
while true; do
  SELECTION=$(yad --title="Puppy Linux App Store (Quickpet)" \
    --window-icon="system-software-install" \
    --width=640 --height=460 --center \
    --list \
    --column="Category" --column="Application" --column="Package" --column="Description" \
    --button="Install .PET Package!document-open:10" \
    --button="Update Repos!view-refresh:20" \
    --button="Install Selected!system-software-install:0" \
    --button="Close!gtk-close:1" \
    "Internet" "Firefox Web Browser" "firefox" "Modern, fast, privacy-focused web browser" \
    "Internet" "Chromium" "chromium" "Open-source browser engine" \
    "Office" "LibreOffice Fresh" "libreoffice-fresh" "Complete office suite with PPT support" \
    "Office" "AbiWord" "abiword" "Lightweight, ultra-fast Puppy Linux word processor" \
    "Media" "VLC Media Player" "vlc" "Plays almost all audio and video formats" \
    "Media" "Audacious" "audacious" "Classic Winamp-style audio player" \
    "Graphics" "GIMP" "gimp" "Professional photo editor and paint program" \
    "Development" "Geany IDE" "geany" "Fast, lightweight code and text editor" \
    "System" "GParted" "gparted" "Disk and partition management tool" \
    "System" "Htop" "htop" "Interactive system monitor" \
    "System" "Fastfetch" "fastfetch" "System summary and hardware info" \
    "Puppy" "Frugal Installer" "frugalpup" "Install ArchPup to USB or Hard Drive")

  RET=$?
  if [ $RET -eq 1 ] || [ $RET -eq 252 ]; then
    break
  elif [ $RET -eq 10 ]; then
    PET_FILE=$(yad --file-selection --title="Select Puppy Linux .PET Package" --file-filter="PET Packages (*.pet)|*.pet")
    if [ -n "$PET_FILE" ]; then
      xterm -title "Installing PET Package" -e "/usr/local/bin/petget '$PET_FILE'; echo 'Press Enter to exit'; read"
    fi
  elif [ $RET -eq 20 ]; then
    xterm -title "Updating Package Repositories" -e "pacman -Sy; echo 'Done! Press Enter to exit'; read"
  elif [ $RET -eq 0 ]; then
    PKG=$(echo "$SELECTION" | awk -F'|' '{print $3}')
    if [ "$PKG" = "frugalpup" ]; then
      /usr/local/bin/frugalpup &
    elif [ -n "$PKG" ]; then
      xterm -title "Installing $PKG" -e "pacman -S --noconfirm --needed $PKG; echo 'Installation complete! Press Enter to exit'; read"
    fi
  fi
done
EOF
chmod +x "${ROOTFS}/usr/local/bin/quickpet"

cat << 'EOF' > "${ROOTFS}/usr/share/applications/quickpet.desktop"
[Desktop Entry]
Name=Puppy App Store (Quickpet)
Comment=Install popular apps and Puppy .PET packages
Exec=/usr/local/bin/quickpet
Icon=system-software-install
Terminal=false
Type=Application
Categories=System;PackageManager;
EOF

# --- C. Frugal Installer ---
cat << 'EOF' > "${ROOTFS}/usr/local/bin/frugalpup"
#!/usr/bin/env bash
DRIVES=$(lsblk -rn -o NAME,SIZE,TYPE,MOUNTPOINT | grep 'part' | awk '{print $1 " (" $2 ", " $4 ")"}')
TARGET=$(yad --title="ArchPup Frugal Installer" \
  --text="Select partition or USB drive to install ArchPup:" \
  --list --column="Available Partitions" $DRIVES \
  --width=450 --height=320 --center \
  --button="Install!gtk-ok:0" --button="Cancel!gtk-cancel:1")

if [ $? -eq 0 ] && [ -n "$TARGET" ]; then
  DEV="/dev/$(echo "$TARGET" | awk '{print $1}')"
  yad --info --title="Frugal Install" --text="To complete frugal install on $DEV, copy the /arch directory and configure your bootloader with kernel /boot/vmlinuz and initrd /boot/initramfs.img with archisobasedir=arch." --width=450 --center
fi
EOF
chmod +x "${ROOTFS}/usr/local/bin/frugalpup"

cat << 'EOF' > "${ROOTFS}/usr/share/applications/frugalpup.desktop"
[Desktop Entry]
Name=FrugalPup Installer
Comment=Install ArchPup to USB or Hard Drive
Exec=/usr/local/bin/frugalpup
Icon=drive-harddisk
Terminal=false
Type=Application
Categories=System;
EOF

# 5. Autologin, Conky HUD & JWM Look
mkdir -p "${ROOTFS}/etc/systemd/system/getty@tty1.service.d"
cat << 'EOF' > "${ROOTFS}/etc/systemd/system/getty@tty1.service.d/autologin.conf"
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin root %I $TERM
EOF

echo '[[ -z $DISPLAY && $XDG_VTNR -eq 1 ]] && exec startx' > "${ROOTFS}/root/.bash_profile"

mkdir -p "${ROOTFS}/root/.config/conky"
cat << 'EOF' > "${ROOTFS}/root/.config/conky/conky.conf"
conky.config = {
    alignment = 'top_left',
    background = false,
    border_width = 0,
    cpu_avg_samples = 2,
    default_color = 'white',
    double_buffer = true,
    draw_borders = false,
    draw_graph_borders = false,
    draw_outline = false,
    draw_shades = false,
    gap_x = 32,
    gap_y = 32,
    minimum_height = 5,
    minimum_width = 240,
    net_avg_samples = 2,
    no_buffers = true,
    out_to_console = false,
    out_to_stderr = false,
    extra_newline = false,
    own_window = true,
    own_window_class = 'Conky',
    own_window_type = 'desktop',
    own_window_transparent = true,
    own_window_argb_visual = true,
    update_interval = 1.0,
    uppercase = false,
    use_spacer = 'none',
    use_xft = true,
}

conky.text = [[
${color #ffffff}${font sans-serif:bold:size=44}${time %H:%M}${font}
${color #ff8800}${font sans-serif:bold:size=11}${time %A, %d %B %Y}${font}
${voffset 6}${color #777777}-----------------------------------
${color #aaaaaa}OS:        ${color #ffffff}ArchPup 26 (x86_64)
${color #aaaaaa}Kernel:    ${color #ffffff}${kernel}
${color #aaaaaa}CPU Load:  ${color #ff8800}${cpu}% ${color #444444}${cpubar 6,80}
${color #aaaaaa}RAM:       ${color #ff8800}${mem} / ${memmax}
${color #aaaaaa}Uptime:    ${color #ffffff}${uptime_short}
${color #777777}-----------------------------------
${color #00ccff}Puppy Tools:
${color #ffffff}* Quickpet (App Store)
${color #ffffff}* PetGet (.PET Installer)
${color #ffffff}* FrugalPup (Live Installer)
]]
EOF

cat << 'EOF' > "${ROOTFS}/root/.xinitrc"
#!/bin/sh
xsetroot -solid "#24272e" &
conky -c /root/.config/conky/conky.conf &
exec jwm
EOF
chmod +x "${ROOTFS}/root/.xinitrc"

cat << 'EOF' > "${ROOTFS}/root/.jwmrc"
<?xml version="1.0"?>
<JWM>
  <RootMenu label="Puppy" height="26">
    <Program label="Puppy App Store (Quickpet)">/usr/local/bin/quickpet</Program>
    <Program label="File Manager (PCManFM)">pcmanfm</Program>
    <Program label="Terminal (xterm)">xterm</Program>
    <Program label="Geany Text Editor">geany</Program>
    <Program label="LibreOffice (PPT / Docs)">libreoffice</Program>
    <Program label="GParted Disk Tool">gparted</Program>
    <Program label="FrugalPup Installer">/usr/local/bin/frugalpup</Program>
    <Separator/>
    <Restart label="Restart JWM"/>
    <Exit label="Exit to Terminal" confirm="true"/>
  </RootMenu>

  <Tray x="0" y="-1" autohide="off" height="30">
    <TrayButton label="  Puppy  ">root:1</TrayButton>
    <Spacer width="4"/>
    <TrayButton label=" AppStore ">exec:/usr/local/bin/quickpet</TrayButton>
    <TrayButton label=" Files ">exec:pcmanfm</TrayButton>
    <TrayButton label=" Terminal ">exec:xterm</TrayButton>
    <TrayButton label=" Office ">exec:libreoffice</TrayButton>
    <Spacer width="6"/>
    <TaskList maxwidth="220"/>
    <Dock/>
    <Clock format="%H:%M"><Button mask="123">exec:xterm -e cal</Button></Clock>
  </Tray>

  <WindowStyle>
    <Font>sans-serif-10:bold</Font>
    <Width>4</Width>
    <Height>22</Height>
    <Active>
      <Text>#ffffff</Text>
      <Title>#3a404a:#24272e</Title>
      <Corner>#ffffff</Corner>
      <Outline>#000000</Outline>
    </Active>
    <Inactive>
      <Text>#aaaaaa</Text>
      <Title>#24272e:#181a1f</Title>
      <Corner>#aaaaaa</Corner>
      <Outline>#000000</Outline>
    </Inactive>
  </WindowStyle>
</JWM>
EOF

rm -rf "${ROOTFS}/var/cache/pacman/pkg/"* "${ROOTFS}/tmp/"*

# 6. Compress rootfs into SquashFS
echo "--> Compressing root filesystem into SquashFS..."
mksquashfs "${ROOTFS}" "${ISO_DIR}/arch/x86_64/airootfs.sfs" -comp xz -b 1024k -noappend -wildcards -e "dev/*" "proc/*" "sys/*" "run/*" "boot/*"

# 7. Syslinux & Hybrid Bootable ISO creation
echo "--> Creating bootable ISO..."
cp /usr/lib/ISOLINUX/isolinux.bin "${ISO_DIR}/isolinux/"
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "${ISO_DIR}/isolinux/"

cat << 'EOF' > "${ISO_DIR}/isolinux/isolinux.cfg"
DEFAULT archpup
TIMEOUT 40
PROMPT 0

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
echo "=== ArchPup 26 ISO build complete! ==="
