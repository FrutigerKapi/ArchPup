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
  networkmanager \
  network-manager-applet \
  wireless_tools \
  wpa_supplicant \
  dhcpcd \
  xorg-server \
  xorg-xinit \
  xorg-xrandr \
  xorg-xsetroot \
  xf86-video-vesa \
  xf86-video-fbdev \
  xf86-input-libinput \
  jwm \
  pcmanfm \
  firefox \
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
  tzdata \
  libreoffice-fresh

# Enable NetworkManager for immediate Wi-Fi & Ethernet connectivity
systemctl enable NetworkManager

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

# 4. Puppy Tools Suite

# --- A. Puppy SNS (Simple Network Setup) - Wi-Fi & Ethernet Manager ---
cat << 'EOF' > "${ROOTFS}/usr/local/bin/sns"
#!/usr/bin/env bash
# Puppy Simple Network Setup (SNS) - Wi-Fi & Wired Manager

if [ "${1:-}" = "--status" ]; then
  DEV_STAT=$(nmcli dev status 2>/dev/null || ip link)
  IP_STAT=$(ip -4 addr show 2>/dev/null | grep inet | awk '{print $2 " (" $NF ")"}')
  yad --info --title="Network Status" \
    --window-icon="network-wireless" \
    --text="<b>Network Devices:</b>\n$DEV_STAT\n\n<b>Active IP Addresses:</b>\n$IP_STAT" \
    --width=480 --center
  exit 0
fi

ACTION=$(yad --title="Puppy Simple Network Setup (SNS)" \
  --window-icon="network-wireless" \
  --width=460 --height=260 --center \
  --text="<b>Puppy Simple Network Setup (SNS)</b>\nSelect connection type or check network status:" \
  --button="Wireless Wi-Fi!network-wireless:10" \
  --button="Wired Ethernet!network-wired:20" \
  --button="Network Status!dialog-information:30" \
  --button="Close!gtk-close:1")

RET=$?
if [ $RET -eq 10 ]; then
  # Scan Wi-Fi networks
  (
    echo "10"; echo "# Scanning for Wi-Fi networks..."
    nmcli dev wifi rescan 2>/dev/null || true
    echo "100"; echo "# Scan complete!"
  ) | yad --progress --pulsate --title="Scanning Wi-Fi" --auto-close --width=300

  NETWORKS=$(nmcli -t -f IN-USE,SSID,BARS,SECURITY dev wifi list 2>/dev/null | grep -v '^$' | awk -F':' '{
    inuse=($1=="*")?"[Connected]":"";
    printf "%s|%s|%s|%s\n", inuse, $2, $3, $4
  }')

  if [ -z "$NETWORKS" ]; then
    yad --warning --title="No Wi-Fi Networks" --text="No wireless networks found.\nEnsure your Wi-Fi device is enabled." --width=350 --center
    exit 0
  fi

  CHOSEN=$(echo "$NETWORKS" | yad --title="Puppy Wi-Fi Setup" \
    --window-icon="network-wireless" \
    --width=540 --height=400 --center \
    --list \
    --column="Status" --column="SSID (Network Name)" --column="Signal" --column="Security" \
    --button="Connect!network-wireless:0" \
    --button="Back!gtk-go-back:1")

  if [ $? -eq 0 ] && [ -n "$CHOSEN" ]; then
    SSID=$(echo "$CHOSEN" | awk -F'|' '{print $2}')
    SEC=$(echo "$CHOSEN" | awk -F'|' '{print $4}')

    PASS=""
    if [ "$SEC" != "--" ] && [ -n "$SEC" ]; then
      PASS=$(yad --entry --title="Wi-Fi Password" \
        --text="Enter password for <b>$SSID</b>:" \
        --hide-text --width=360 --center)
    fi

    if [ -n "$SSID" ]; then
      xterm -title "Connecting to $SSID" -e "nmcli dev wifi connect '$SSID' ${PASS:+password '$PASS'}; echo 'Press Enter to close'; read"
    fi
  fi

elif [ $RET -eq 20 ]; then
  xterm -title "Connecting Wired Network" -e "dhcpcd; echo 'Wired network initialized. Press Enter to close'; read"

elif [ $RET -eq 30 ]; then
  /usr/local/bin/sns --status
fi
EOF
chmod +x "${ROOTFS}/usr/local/bin/sns"

cat << 'EOF' > "${ROOTFS}/usr/share/applications/sns.desktop"
[Desktop Entry]
Name=Simple Network Setup (SNS)
Comment=Puppy Wi-Fi and Ethernet Manager
Exec=/usr/local/bin/sns
Icon=network-wireless
Terminal=false
Type=Application
Categories=Network;Settings;
EOF

# --- B. Puppy Control Center (Settings App) ---
cat << 'EOF' > "${ROOTFS}/usr/local/bin/puppy-settings"
#!/usr/bin/env bash
# Puppy Control Center / Settings Manager

CHOICE=$(yad --title="Puppy Control Center (Settings)" \
  --window-icon="preferences-system" \
  --width=640 --height=440 --center \
  --list \
  --column="Category" --column="Tool" --column="Description" --column="Command" \
  --button="Launch!preferences-system:0" \
  --button="Close!gtk-close:1" \
  "Network" "Simple Network Setup (SNS)" "Scan and connect to Wi-Fi and Ethernet" "/usr/local/bin/sns" \
  "Network" "Network Status" "Check IP address, interfaces, and gateway" "/usr/local/bin/sns --status" \
  "Display" "Screen Resolution" "Change display resolution (xrandr)" "xrandr-gui" \
  "Display" "Toggle Conky HUD" "Show or hide desktop clock and monitor" "toggle-conky" \
  "System" "First Run Setup (QuickSetup)" "Configure keyboard, timezone, and hostname" "/usr/local/bin/quicksetup --force" \
  "System" "Puppy App Store (Quickpet)" "Install popular apps and updates" "/usr/local/bin/quickpet" \
  "System" "PetGet Package Installer" "Install Puppy Linux .PET packages" "/usr/local/bin/petget" \
  "System" "FrugalPup Installer" "Install ArchPup to USB or Hard Drive" "/usr/local/bin/frugalpup" \
  "System" "Save Session (save2flash)" "Save current session and settings to storage" "/usr/local/bin/save2flash" \
  "Hardware" "GParted Partition Manager" "Format and manage disk partitions" "gparted")

if [ $? -eq 0 ] && [ -n "$CHOICE" ]; then
  CMD=$(echo "$CHOICE" | awk -F'|' '{print $4}')
  if [ "$CMD" = "xrandr-gui" ]; then
    RES=$(xrandr 2>/dev/null | grep -E '\bconnected\b' -A 10 | grep -E '^[ ]+[0-9]+x[0-9]+' | awk '{print $1}' | sort -u)
    PICK=$(echo "$RES" | yad --title="Screen Resolution" --list --column="Available Resolutions" --width=300 --height=300 --center)
    [ -n "$PICK" ] && xrandr -s "$(echo "$PICK" | cut -d'|' -f1)"
  elif [ "$CMD" = "toggle-conky" ]; then
    if pgrep -x conky >/dev/null; then
      pkill -x conky
    else
      conky -c /root/.config/conky/conky.conf &
    fi
  elif [ -n "$CMD" ]; then
    $CMD &
  fi
fi
EOF
chmod +x "${ROOTFS}/usr/local/bin/puppy-settings"

cat << 'EOF' > "${ROOTFS}/usr/share/applications/puppy-settings.desktop"
[Desktop Entry]
Name=Puppy Control Center
Comment=Puppy Settings and System Management
Exec=/usr/local/bin/puppy-settings
Icon=preferences-system
Terminal=false
Type=Application
Categories=Settings;
EOF

# --- C. Quicksetup: Puppy First Boot Wizard ---
cat << 'EOF' > "${ROOTFS}/usr/local/bin/quicksetup"
#!/usr/bin/env bash
FLAG="/root/.quicksetup_done"
if [ -f "$FLAG" ] && [ "${1:-}" != "--force" ]; then
    exit 0
fi

CHOICE=$(yad --title="ArchPup 26 - First Run Setup" \
    --window-icon="preferences-system" \
    --width=520 --height=380 --center \
    --form \
    --text="<b>Welcome to ArchPup 26!</b>\nPlease configure your locale, keyboard, and timezone." \
    --field="Keyboard Layout:CB" "us!gb!de!fr!es!it!nl!pl!ru!se" \
    --field="Timezone:CB" "UTC!Europe/Amsterdam!Europe/London!Europe/Berlin!America/New_York!America/Los_Angeles!Asia/Tokyo" \
    --field="Hostname:TEXT" "archpup" \
    --button="Apply Settings!gtk-ok:0" \
    --button="Skip!gtk-cancel:1")

if [ $? -eq 0 ] && [ -n "$CHOICE" ]; then
    KBD=$(echo "$CHOICE" | awk -F'|' '{print $1}')
    TZ=$(echo "$CHOICE" | awk -F'|' '{print $2}')
    HN=$(echo "$CHOICE" | awk -F'|' '{print $3}')

    [ -n "$KBD" ] && loadkeys "$KBD" 2>/dev/null || true
    [ -n "$TZ" ] && [ -f "/usr/share/zoneinfo/$TZ" ] && ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
    [ -n "$HN" ] && echo "$HN" > /etc/hostname
    touch "$FLAG"
    yad --info --title="Settings Applied" --text="Settings saved successfully!" --width=300 --center
fi
EOF
chmod +x "${ROOTFS}/usr/local/bin/quicksetup"

# --- D. PetGet (.PET package installer) ---
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

# --- E. Quickpet: Puppy Linux App Store ---
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
    "Puppy" "Simple Network Setup (Wi-Fi)" "sns" "Manage Wi-Fi and Ethernet" \
    "Puppy" "Control Center (Settings)" "puppy-settings" "Puppy system settings" \
    "Puppy" "Frugal Installer" "frugalpup" "Install ArchPup to USB or Hard Drive" \
    "Puppy" "Save Session" "save2flash" "Save current session and settings")

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
    elif [ "$PKG" = "save2flash" ]; then
      /usr/local/bin/save2flash &
    elif [ "$PKG" = "sns" ]; then
      /usr/local/bin/sns &
    elif [ "$PKG" = "puppy-settings" ]; then
      /usr/local/bin/puppy-settings &
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

# --- F. Frugal Installer ---
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
  yad --info --title="Frugal Install" --text="To complete frugal install on $DEV, copy the /arch directory and configure your bootloader with kernel /boot/vmlinuz and initrd /boot/initramfs.img with archisobasedir=arch cow_label=ARCHPUP_SAVE." --width=450 --center
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

# --- G. save2flash: Puppy Session Save Tool ---
cat << 'EOF' > "${ROOTFS}/usr/local/bin/save2flash"
#!/usr/bin/env bash
DEST_DIR=$(yad --file-selection --directory --title="Select Destination to Save Session Backup")
if [ -n "$DEST_DIR" ]; then
  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  SAVE_FILE="${DEST_DIR}/archpupsave_${TIMESTAMP}.tar.gz"
  (
    echo "10"; echo "# Archiving /root..."
    tar -czf "$SAVE_FILE" -C / root etc/pacman.d 2>/dev/null || true
    echo "100"; echo "# Save complete!"
  ) | yad --progress --title="Saving Session" --text="Backing up changes..." --percentage=0 --auto-close
  yad --info --title="Session Saved" --text="Session backup saved to:\n$SAVE_FILE\n\nNote: If booted from USB with a partition labelled ARCHPUP_SAVE, all changes are saved automatically!" --width=450 --center
fi
EOF
chmod +x "${ROOTFS}/usr/local/bin/save2flash"

cat << 'EOF' > "${ROOTFS}/usr/share/applications/save2flash.desktop"
[Desktop Entry]
Name=Save Session (save2flash)
Comment=Save personal settings and changes
Exec=/usr/local/bin/save2flash
Icon=document-save
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
${color #ffffff}* Simple Network Setup (SNS)
${color #ffffff}* Control Center (Settings)
${color #ffffff}* FrugalPup (Live Installer)
${color #ffffff}* save2flash (Save Session)
]]
EOF

cat << 'EOF' > "${ROOTFS}/root/.xinitrc"
#!/bin/sh
xsetroot -solid "#24272e" &
nm-applet &
conky -c /root/.config/conky/conky.conf &
/usr/local/bin/quicksetup &
exec jwm
EOF
chmod +x "${ROOTFS}/root/.xinitrc"

# JWM Configuration with dedicated Dock shortcuts for WiFi and Settings
cat << 'EOF' > "${ROOTFS}/root/.jwmrc"
<?xml version="1.0"?>
<JWM>
  <RootMenu label="Puppy" height="26">
    <Program label="Puppy App Store (Quickpet)">/usr/local/bin/quickpet</Program>
    <Program label="Web Browser (Firefox)">firefox</Program>
    <Program label="Simple Network Setup (Wi-Fi)">/usr/local/bin/sns</Program>
    <Program label="Puppy Control Center (Settings)">/usr/local/bin/puppy-settings</Program>
    <Program label="File Manager (PCManFM)">pcmanfm</Program>
    <Program label="Terminal (xterm)">xterm</Program>
    <Program label="Geany Text Editor">geany</Program>
    <Program label="LibreOffice (PPT / Docs)">libreoffice</Program>
    <Program label="GParted Disk Tool">gparted</Program>
    <Program label="FrugalPup Installer">/usr/local/bin/frugalpup</Program>
    <Program label="First Run Setup (QuickSetup)">/usr/local/bin/quicksetup --force</Program>
    <Program label="Save Session (save2flash)">/usr/local/bin/save2flash</Program>
    <Separator/>
    <Restart label="Restart JWM"/>
    <Exit label="Exit to Terminal" confirm="true"/>
  </RootMenu>

  <Tray x="0" y="-1" autohide="off" height="30">
    <TrayButton label="  Puppy  ">root:1</TrayButton>
    <Spacer width="4"/>
    <TrayButton label=" AppStore ">exec:/usr/local/bin/quickpet</TrayButton>
    <TrayButton label=" Browser ">exec:firefox</TrayButton>
    <TrayButton label=" WiFi ">exec:/usr/local/bin/sns</TrayButton>
    <TrayButton label=" Settings ">exec:/usr/local/bin/puppy-settings</TrayButton>
    <TrayButton label=" Files ">exec:pcmanfm</TrayButton>
    <TrayButton label=" Terminal ">exec:xterm</TrayButton>
    <TrayButton label=" Save ">exec:/usr/local/bin/save2flash</TrayButton>
    <Spacer width="6"/>
    <TaskList maxwidth="200"/>
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

# 7. Syslinux & Hybrid Bootable ISO creation with Persistence Support
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
  APPEND archisobasedir=arch archisolabel=ARCHPUP_26 cow_label=ARCHPUP_SAVE quiet
EOF

xorriso -as mkisofs -iso-level 3 -R -J -l \
  -volid "ARCHPUP_26" \
  -b isolinux/isolinux.bin -c isolinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -o "${OUT_DIR}/ArchPup-26-x86_64.iso" "${ISO_DIR}"

isohybrid "${OUT_DIR}/ArchPup-26-x86_64.iso" || true
echo "=== ArchPup 26 ISO build complete! ==="
