#!/usr/bin/env bash
set -euo pipefail

echo "=== Building ArchPup 26.0.1 (Frutiger Aero Stable Edition) ==="
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

# 2. Resilient Multi-Mirror & Pacman Setup
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
pacman -Sy --noconfirm

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
  picom \
  pcmanfm \
  firefox \
  xterm \
  feh \
  fastfetch \
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

systemctl enable NetworkManager

# Configure live archiso hooks
echo 'HOOKS=(base udev modconf archiso archiso_loop_mnt block filesystems)' > /etc/mkinitcpio.conf
KVER=\$(ls /lib/modules | head -n1)
mkinitcpio -k \"\${KVER}\" -c /etc/mkinitcpio.conf -g /boot/initramfs.img
pacman -Scc --noconfirm
"

# Configure ArchPup 26.0.1 OS Identification (Replaces generic Arch Linux branding)
cat << 'EOF' > "${ROOTFS}/etc/os-release"
NAME="ArchPup"
PRETTY_NAME="ArchPup 26.0.1"
ID=archpup
ID_LIKE=arch
BUILD_ID=26.0.1
VERSION="26.0.1 (Frutiger Aero Edition)"
VERSION_ID="26.0.1"
ANSI_COLOR="0;36"
HOME_URL="https://github.com/FrutigerKapi/ArchPup"
SUPPORT_URL="https://github.com/FrutigerKapi/ArchPup"
BUG_REPORT_URL="https://github.com/FrutigerKapi/ArchPup/issues"
LOGO=archpup
EOF

cp "${ROOTFS}/etc/os-release" "${ROOTFS}/usr/lib/os-release" 2>/dev/null || true

cat << 'EOF' > "${ROOTFS}/etc/lsb-release"
LSB_VERSION=26.0.1
DISTRIB_ID=ArchPup
DISTRIB_RELEASE=26.0.1
DISTRIB_CODENAME=archpup
DISTRIB_DESCRIPTION="ArchPup 26.0.1"
EOF

echo "ArchPup 26.0.1" > "${ROOTFS}/etc/arch-release"
echo 'ArchPup 26.0.1 (\l)' > "${ROOTFS}/etc/issue"
echo "ArchPup 26.0.1" > "${ROOTFS}/etc/issue.net"

# Configure custom Fastfetch banner
mkdir -p "${ROOTFS}/root/.config/fastfetch" "${ROOTFS}/etc/fastfetch"
cat << 'EOF' > "${ROOTFS}/etc/archpup-ascii.txt"
       .---.
      (  O  )   .
       `---'   /
         \  .-'
          \( > )
           `--'
       ArchPup 26.0.1
EOF

cat << 'EOF' > "${ROOTFS}/root/.config/fastfetch/config.jsonc"
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "source": "/etc/archpup-ascii.txt",
    "color": {
      "1": "cyan",
      "2": "light_blue"
    }
  },
  "modules": [
    "title",
    "separator",
    "os",
    "host",
    "kernel",
    "uptime",
    "packages",
    "shell",
    "wm",
    "terminal",
    "cpu",
    "memory",
    "break",
    "colors"
  ]
}
EOF
cp "${ROOTFS}/root/.config/fastfetch/config.jsonc" "${ROOTFS}/etc/fastfetch/config.jsonc" 2>/dev/null || true

cat << 'EOF' >> "${ROOTFS}/root/.bashrc"
alias neofetch=fastfetch
if [ -n "$DISPLAY" ] && [ -t 1 ]; then
  fastfetch
fi
EOF

# Copy kernel and initramfs to ISO
cp "${ROOTFS}/boot/vmlinuz-linux" "${ISO_DIR}/boot/vmlinuz"
cp "${ROOTFS}/boot/initramfs.img" "${ISO_DIR}/boot/initramfs.img"

# 4. Auto-login root on tty1
mkdir -p "${ROOTFS}/etc/systemd/system/getty@tty1.service.d"
cat << 'EOF' > "${ROOTFS}/etc/systemd/system/getty@tty1.service.d/autologin.conf"
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin root %I $TERM
EOF

cat << 'EOF' >> "${ROOTFS}/root/.bash_profile"
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec startx
fi
EOF

# 5. Core Puppy Applications & Utilities

# --- A. Simple Network Setup (SNS) ---
cat << 'EOF' > "${ROOTFS}/usr/local/bin/sns"
#!/usr/bin/env bash
nmcli radio wifi on 2>/dev/null || true
IFACES=$(nmcli device status 2>/dev/null | awk 'NR>1 {print $1, $2, $3}')

DEV_LIST=""
while read -r DEV TYPE STATE; do
  [ -z "$DEV" ] && continue
  DEV_LIST="$DEV_LIST $DEV $TYPE $STATE"
done <<< "$IFACES"

SEL_DEV=$(yad --list --title="Simple Network Setup (SNS)" --window-icon="network-wireless" \
  --width=450 --height=250 --center \
  --text="Select network adapter to configure:" \
  --column="Interface" --column="Type" --column="Status" $DEV_LIST)

[ -z "$SEL_DEV" ] && exit 0
INTF=$(echo "$SEL_DEV" | cut -d'|' -f1)

if [[ "$SEL_DEV" == *"wifi"* ]]; then
  SSID_LIST=$(nmcli --colors no device wifi list ifname "$INTF" --rescan yes 2>/dev/null | awk 'NR>1 {print $2, $7"%", $8}' | sort -u)
  YAD_SSIDS=""
  while read -r S_SSID S_BARS S_SEC; do
    [ -z "$S_SSID" ] || [ "$S_SSID" = "--" ] && continue
    YAD_SSIDS="$YAD_SSIDS \"$S_SSID\" \"$S_BARS\" \"$S_SEC\""
  done <<< "$SSID_LIST"

  WIFI_PICK=$(eval yad --list --title="Connect to Wi-Fi ($INTF)" --window-icon="network-wireless" \
    --width=450 --height=320 --center \
    --column="SSID (Network)" --column="Signal" --column="Security" $YAD_SSIDS)

  [ -z "$WIFI_PICK" ] && exit 0
  SSID=$(echo "$WIFI_PICK" | cut -d'|' -f1)

  PASS=$(yad --entry --title="Wi-Fi Password" --window-icon="network-wireless" \
    --text="Enter password for <b>$SSID</b>:" --hide-text --center --width=350)

  if [ -n "$PASS" ]; then
    xterm -title "Connecting to $SSID" -e "nmcli device wifi connect '$SSID' password '$PASS' ifname '$INTF'; sleep 2"
  else
    xterm -title "Connecting to $SSID" -e "nmcli device wifi connect '$SSID' ifname '$INTF'; sleep 2"
  fi
else
  nmcli device connect "$INTF"
  yad --info --title="Wired Network" --text="Connected on $INTF" --width=250 --center
fi
EOF
chmod +x "${ROOTFS}/usr/local/bin/sns"

cat << 'EOF' > "${ROOTFS}/usr/share/applications/sns.desktop"
[Desktop Entry]
Name=Simple Network Setup (Wi-Fi)
Comment=Connect to Wi-Fi and wired networks
Exec=/usr/local/bin/sns
Icon=network-wireless
Terminal=false
Type=Application
Categories=Network;Settings;
EOF

# --- A2. Theme & Glass Effects Tool ---
cat << 'EOF' > "${ROOTFS}/usr/local/bin/puppy-theme-settings"
#!/usr/bin/env bash
THEME_CHOICE=$(yad --form --title="Puppy Theme & Glass Settings" --window-icon="preferences-desktop-theme" \
  --width=480 --center \
  --text="<b>Customise ArchPup Appearance & Glass Effects</b>" \
  --field="Glass Preset:CB" "Aero Glass (High Translucent)!Frosted Glass (Subtle Translucency)!Solid Opaque (Max Speed)" \
  --field="Active Window Opacity (%):NUM" "94!70!100!1" \
  --field="Inactive Window Opacity (%):NUM" "88!60!100!1" \
  --field="Window Drop Shadows:CHK" "TRUE" \
  --field="Rounded Window Corners (px):NUM" "8!0!20!1" \
  --field="Accent Color Theme:CB" "Ice Cyan (Aero)!Frost Emerald!Obsidian Dark!Classic Puppy Gold" \
  --button="Cancel:1" --button="Apply Theme:0")

[ $? -ne 0 ] && exit 0

PRESET=$(echo "$THEME_CHOICE" | cut -d'|' -f1)
ACTIVE_OP=$(echo "$THEME_CHOICE" | cut -d'|' -f2 | cut -d'.' -f1)
INACTIVE_OP=$(echo "$THEME_CHOICE" | cut -d'|' -f3 | cut -d'.' -f1)
SHADOW=$(echo "$THEME_CHOICE" | cut -d'|' -f4)
CORNER=$(echo "$THEME_CHOICE" | cut -d'|' -f5 | cut -d'.' -f1)
ACCENT=$(echo "$THEME_CHOICE" | cut -d'|' -f6)

mkdir -p /root/.config/picom

if [ "$PRESET" = "Solid Opaque (Max Speed)" ]; then
  pkill picom 2>/dev/null || true
  yad --info --title="Theme Applied" --text="Switched to Solid Opaque mode (compositor disabled)." --timeout=2 --width=320 --center &
  exit 0
fi

ACT_DEC=$(awk "BEGIN {printf \"%.2f\", $ACTIVE_OP/100}")
INACT_DEC=$(awk "BEGIN {printf \"%.2f\", $INACTIVE_OP/100}")
[ "$SHADOW" = "TRUE" ] && SHADOW_VAL="true" || SHADOW_VAL="false"

cat << PICOM_EOF > /root/.config/picom/picom.conf
backend = "xrender";
shadow = $SHADOW_VAL;
shadow-radius = 12;
shadow-opacity = 0.45;
shadow-offset-x = -12;
shadow-offset-y = -12;

fading = true;
fade-delta = 4;
fade-in-step = 0.04;
fade-out-step = 0.04;

active-opacity = $ACT_DEC;
inactive-opacity = $INACT_DEC;
frame-opacity = 0.85;
inactive-opacity-override = false;

corner-radius = $CORNER;
rounded-corners-exclude = [
  "window_type = 'dock'",
  "window_type = 'desktop'"
];

opacity-rule = [
  "100:class_g = 'Firefox'",
  "100:class_g = 'Gparted'",
  "100:class_g = 'LibreOffice'"
];
PICOM_EOF

pkill picom 2>/dev/null || true
picom -b --config /root/.config/picom/picom.conf 2>/dev/null &

which jwm >/dev/null 2>&1 && jwm -restart 2>/dev/null || true
yad --info --title="Theme Applied" --text="Glassy theme applied successfully!" --timeout=2 --width=280 --center &
EOF
chmod +x "${ROOTFS}/usr/local/bin/puppy-theme-settings"

# --- A3. Removable Pinned Apps Dock Manager ---
cat << 'EOF' > "${ROOTFS}/usr/local/bin/puppy-dock-manager"
#!/usr/bin/env bash
CONF="/root/.config/archpup-dock.conf"
JWMRC="/root/.jwmrc"

mkdir -p /root/.config
if [ ! -f "$CONF" ]; then
  cat << 'C_EOF' > "$CONF"
TRUE|AppStore|/usr/local/bin/quickpet
TRUE|Browser|firefox
TRUE|WiFi|/usr/local/bin/sns
TRUE|Settings|/usr/local/bin/puppy-settings
TRUE|Files|pcmanfm
TRUE|Terminal|xterm
TRUE|Save|/usr/local/bin/save2flash
C_EOF
fi

update_dock() {
  local BUTTONS=""
  while IFS='|' read -r ENABLED LABEL CMD; do
    [ -z "$LABEL" ] && continue
    if [ "$ENABLED" = "TRUE" ]; then
      BUTTONS="${BUTTONS}    <TrayButton label=\" ${LABEL} \">exec:${CMD}</TrayButton>\n"
    fi
  done < "$CONF"

  cat << JWM_EOF > "$JWMRC"
<?xml version="1.0"?>
<JWM>
  <RootMenu label="Puppy" height="26">
    <Program label="Puppy App Store (Quickpet)">/usr/local/bin/quickpet</Program>
    <Program label="Web Browser (Firefox)">firefox</Program>
    <Program label="Simple Network Setup (Wi-Fi)">/usr/local/bin/sns</Program>
    <Program label="Puppy Control Center (Settings)">/usr/local/bin/puppy-settings</Program>
    <Program label="Theme &amp; Glass Settings">/usr/local/bin/puppy-theme-settings</Program>
    <Program label="Dock &amp; Pinned Apps Manager">/usr/local/bin/puppy-dock-manager</Program>
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

  <Tray x="0" y="-1" autohide="off" height="34">
    <TrayButton label="  Puppy  ">root:1</TrayButton>
    <Spacer width="4"/>
$(echo -e -n "$BUTTONS")    <Spacer width="2"/>
    <TrayButton label=" ⚙ Dock ">exec:/usr/local/bin/puppy-dock-manager</TrayButton>
    <Spacer width="6"/>
    <TaskList maxwidth="200"/>
    <Dock/>
    <Clock format="%H:%M"><Button mask="123">exec:xterm -e cal</Button></Clock>
  </Tray>

  <TrayStyle>
    <Font>sans-serif-10:bold</Font>
    <Background>#112338:#1e3c5a</Background>
    <Foreground>#e0f2fe</Foreground>
    <Active>
      <Background>#0ea5e9:#0284c7</Background>
      <Foreground>#ffffff</Foreground>
    </Active>
  </TrayStyle>

  <TaskListStyle>
    <Font>sans-serif-9:bold</Font>
    <Active>
      <Background>#38bdf8:#0284c7</Background>
      <Foreground>#ffffff</Foreground>
    </Active>
    <Inactive>
      <Background>#0f1c2c:#182e44</Background>
      <Foreground>#94a3b8</Foreground>
    </Inactive>
  </TaskListStyle>

  <WindowStyle>
    <Font>sans-serif-10:bold</Font>
    <Width>2</Width>
    <Height>24</Height>
    <Active>
      <Text>#ffffff</Text>
      <Title>#253a4c:#15222d</Title>
      <Corner>#38bdf8</Corner>
      <Outline>#0284c7</Outline>
    </Active>
    <Inactive>
      <Text>#94a3b8</Text>
      <Title>#141b22:#0c1116</Title>
      <Corner>#475569</Corner>
      <Outline>#1e293b</Outline>
    </Inactive>
  </WindowStyle>
</JWM>
JWM_EOF

  which jwm >/dev/null 2>&1 && jwm -restart 2>/dev/null || true
}

ITEMS=""
while IFS='|' read -r ENABLED LABEL CMD; do
  [ -z "$LABEL" ] && continue
  ITEMS="$ITEMS \"$ENABLED\" \"$LABEL\" \"$CMD\""
done < "$CONF"

CHOICE=$(eval yad --list --checklist --title="Dock Manager - Pinned Apps" \
  --window-icon="preferences-desktop" --width=520 --height=380 --center \
  --text="<b>Check or uncheck apps to pin/unpin them from the dock:</b>" \
  --column="Pinned:CHK" --column="App Name" --column="Command" $ITEMS \
  --button="Add App:2" --button="Cancel:1" --button="Apply Dock:0")

RET=$?

if [ $RET -eq 0 ]; then
  NEW_CONF=""
  IFS=$'\n'
  for ROW in $CHOICE; do
    [ -z "$ROW" ] && continue
    PIN=$(echo "$ROW" | awk -F'|' '{print $1}')
    LBL=$(echo "$ROW" | awk -F'|' '{print $2}')
    C_CMD=$(echo "$ROW" | awk -F'|' '{print $3}')
    [ -z "$LBL" ] && continue
    NEW_CONF="${NEW_CONF}${PIN}|${LBL}|${C_CMD}\n"
  done
  echo -e -n "$NEW_CONF" > "$CONF"
  update_dock
  yad --info --title="Dock Updated" --text="Dock pinned apps updated successfully!" --timeout=2 --width=280 --center &

elif [ $RET -eq 2 ]; then
  ADD_FORM=$(yad --form --title="Add Pinned App to Dock" --width=400 --center \
    --field="App Name:" "" \
    --field="Launch Command:" "")
  if [ $? -eq 0 ] && [ -n "$ADD_FORM" ]; then
    NAME=$(echo "$ADD_FORM" | cut -d'|' -f1)
    COMMAND=$(echo "$ADD_FORM" | cut -d'|' -f2)
    if [ -n "$NAME" ] && [ -n "$COMMAND" ]; then
      echo "TRUE|$NAME|$COMMAND" >> "$CONF"
      update_dock
      yad --info --title="Added" --text="Added '$NAME' to dock!" --timeout=2 --width=250 --center &
    fi
  fi
fi
EOF
chmod +x "${ROOTFS}/usr/local/bin/puppy-dock-manager"

cat << 'EOF' > "${ROOTFS}/usr/share/applications/puppy-dock-manager.desktop"
[Desktop Entry]
Name=Dock & Pinned Apps Manager
Comment=Add or remove pinned application shortcuts on the dock
Exec=/usr/local/bin/puppy-dock-manager
Icon=preferences-desktop
Terminal=false
Type=Application
Categories=Settings;DesktopSettings;
EOF

# --- B. Puppy Control Center (Settings App) ---
cat << 'EOF' > "${ROOTFS}/usr/local/bin/puppy-settings"
#!/usr/bin/env bash
CHOICE=$(yad --list --title="Puppy Control Center" --window-icon="preferences-system" \
  --width=540 --height=440 --center \
  --column="Category" --column="Tool" --column="Description" --column="Command":HD \
  "Appearance" "Theme & Glass Effects" "Configure glassy window effects and opacity" "/usr/local/bin/puppy-theme-settings" \
  "Appearance" "Dock & Pinned Apps" "Add or remove pinned icons from the bottom dock" "/usr/local/bin/puppy-dock-manager" \
  "Network" "Simple Network Setup (Wi-Fi)" "Configure wireless and wired network" "/usr/local/bin/sns" \
  "Network" "Network Connections (Advanced)" "Edit static IP, VPN, and DNS" "nm-connection-editor" \
  "Display" "Screen Resolution (Xrandr)" "Adjust monitor resolution and layout" "xrandr" \
  "System" "First Boot Setup (QuickSetup)" "Timezone, locale, and keyboard" "/usr/local/bin/quicksetup" \
  "System" "Puppy App Store (Quickpet)" "Install popular apps and updates" "/usr/local/bin/quickpet" \
  "System" "PetGet Package Installer" "Install Puppy Linux .PET packages" "/usr/local/bin/petget" \
  "System" "FrugalPup Installer" "Install ArchPup to USB or Hard Drive" "/usr/local/bin/frugalpup" \
  "System" "Save Session (save2flash)" "Save current session and settings to storage" "/usr/local/bin/save2flash" \
  "Hardware" "GParted Partition Manager" "Format and manage disk partitions" "gparted")

if [ $? -eq 0 ] && [ -n "$CHOICE" ]; then
  CMD=$(echo "$CHOICE" | awk -F'|' '{print $4}')
  if [ -n "$CMD" ]; then
    eval "$CMD" &
  fi
fi
EOF
chmod +x "${ROOTFS}/usr/local/bin/puppy-settings"

# --- C. First Run QuickSetup Wizard ---
cat << 'EOF' > "${ROOTFS}/usr/local/bin/quicksetup"
#!/usr/bin/env bash
FLAG="/root/.config/quicksetup_done"
if [ -f "$FLAG" ] && [ "${1:-}" != "--force" ]; then
  exit 0
fi

ANS=$(yad --form --title="QuickSetup - First Run Settings" --window-icon="preferences-system" \
  --width=450 --center \
  --text="<b>Welcome to ArchPup 26.0.1!</b>\nConfigure your basic regional and network settings:" \
  --field="Hostname:" "archpup" \
  --field="Timezone:CB" "UTC!Europe/London!Europe/Amsterdam!America/New_York!America/Los_Angeles!Asia/Tokyo" \
  --field="Keyboard Layout:CB" "us!uk!de!fr!es" \
  --field="Launch Wi-Fi Setup on exit:CHK" TRUE \
  --button="OK:0")

if [ $? -eq 0 ] && [ -n "$ANS" ]; then
  HNAME=$(echo "$ANS" | cut -d'|' -f1)
  TZ=$(echo "$ANS" | cut -d'|' -f2)
  KBD=$(echo "$ANS" | cut -d'|' -f3)
  WIFI_CHK=$(echo "$ANS" | cut -d'|' -f4)

  [ -n "$HNAME" ] && hostnamectl set-hostname "$HNAME" 2>/dev/null || echo "$HNAME" > /etc/hostname
  [ -n "$TZ" ] && ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime 2>/dev/null || true
  [ -n "$KBD" ] && setxkbmap "$KBD" 2>/dev/null || true

  mkdir -p /root/.config
  touch "$FLAG"

  if [ "$WIFI_CHK" = "TRUE" ]; then
    /usr/local/bin/sns &
  fi
fi
EOF
chmod +x "${ROOTFS}/usr/local/bin/quicksetup"

# --- D. Native .PET Package Installer (PetGet) ---
cat << 'EOF' > "${ROOTFS}/usr/local/bin/petget"
#!/usr/bin/env bash
PET_FILE="$1"
if [ -z "$PET_FILE" ]; then
  PET_FILE=$(yad --file --title="Select Puppy .PET Package to Install" --file-filter="PET Packages | *.pet")
fi

[ -z "$PET_FILE" ] && exit 0
if [ ! -f "$PET_FILE" ]; then
  yad --error --title="PetGet Error" --text="File not found: $PET_FILE" --width=300 --center
  exit 1
fi

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

if tar -tzf "$PET_FILE" >/dev/null 2>&1; then
  tar -xzf "$PET_FILE"
else
  head -c -32 "$PET_FILE" | tar -xzf - 2>/dev/null || tar -xf "$PET_FILE" --wildcards "*/*" 2>/dev/null
fi

SUBDIR=$(find . -maxdepth 1 -mindepth 1 -type d | head -n1)
if [ -n "$SUBDIR" ]; then
  cp -a "$SUBDIR"/* / 2>/dev/null || true
else
  cp -a ./* / 2>/dev/null || true
fi

update-desktop-database /usr/share/applications 2>/dev/null || true
which jwm >/dev/null 2>&1 && jwm -restart 2>/dev/null || true
rm -rf "$TEMP_DIR"
yad --info --title="PetGet" --text="Successfully installed $(basename "$PET_FILE")!" --width=300 --center
EOF
chmod +x "${ROOTFS}/usr/local/bin/petget"

# --- E. Puppy App Store (Quickpet) ---
cat << 'EOF' > "${ROOTFS}/usr/local/bin/quickpet"
#!/usr/bin/env bash
while true; do
  CHOICE=$(yad --list --title="Puppy App Store (Quickpet)" --window-icon="system-software-install" \
    --width=580 --height=420 --center \
    --text="Install popular software or manage Puppy Linux tools:" \
    --column="Category" --column="Software" --column="Package" --column="Description" \
    "Internet" "Firefox" "firefox" "Standard web browser" \
    "Internet" "Chromium" "chromium" "Fast open-source web browser" \
    "Multimedia" "VLC Media Player" "vlc" "Audio and video playback" \
    "Multimedia" "MPV Player" "mpv" "Ultra-lightweight video player" \
    "Graphics" "GIMP" "gimp" "Image manipulation and drawing" \
    "Office" "LibreOffice Fresh" "libreoffice-fresh" "Word, Excel, PowerPoint suite" \
    "Development" "Geany Editor" "geany" "Fast IDE and code editor" \
    "System" "Htop" "htop" "Interactive system monitor" \
    "System" "Fastfetch" "fastfetch" "System summary and hardware info" \
    "Appearance" "Theme & Glass Settings" "puppy-theme-settings" "Translucency & theme settings" \
    "Appearance" "Dock Manager" "puppy-dock-manager" "Pin/unpin apps on bottom dock" \
    "Puppy" "Simple Network Setup (Wi-Fi)" "sns" "Manage Wi-Fi and Ethernet" \
    "Puppy" "Control Center (Settings)" "puppy-settings" "Puppy system settings" \
    "Puppy" "Frugal Installer" "frugalpup" "Install ArchPup to USB or Hard Drive" \
    "Puppy" "Save Session" "save2flash" "Save current session and settings")

  RET=$?
  if [ $RET -eq 1 ] || [ $RET -eq 252 ]; then
    break
  fi

  PKG=$(echo "$CHOICE" | awk -F'|' '{print $3}')
  if [ -n "$PKG" ]; then
    if [ "$PKG" = "frugalpup" ]; then
      /usr/local/bin/frugalpup &
    elif [ "$PKG" = "save2flash" ]; then
      /usr/local/bin/save2flash &
    elif [ "$PKG" = "sns" ]; then
      /usr/local/bin/sns &
    elif [ "$PKG" = "puppy-settings" ]; then
      /usr/local/bin/puppy-settings &
    elif [ "$PKG" = "puppy-theme-settings" ]; then
      /usr/local/bin/puppy-theme-settings &
    elif [ "$PKG" = "puppy-dock-manager" ]; then
      /usr/local/bin/puppy-dock-manager &
    elif [ -n "$PKG" ]; then
      xterm -title "Installing $PKG" -e "pacman -S --noconfirm --needed $PKG; echo 'Installation complete! Press Enter to exit'; read"
    fi
  fi
done
EOF
chmod +x "${ROOTFS}/usr/local/bin/quickpet"

# --- F. FrugalPup Live Installer ---
cat << 'EOF' > "${ROOTFS}/usr/local/bin/frugalpup"
#!/usr/bin/env bash
DISKS=$(lsblk -d -o NAME,SIZE,MODEL | awk 'NR>1 {print $1, $2, $3}')
TARGET=$(yad --list --title="FrugalPup Installer" --window-icon="drive-harddisk" \
  --width=450 --height=220 --center \
  --text="Select disk or drive partition for Frugal Install:" \
  --column="Drive" --column="Size" --column="Model" $DISKS)

if [ $? -eq 0 ] && [ -n "$TARGET" ]; then
  DEV="/dev/$(echo "$TARGET" | awk '{print $1}')"
  yad --info --title="Frugal Install" --text="To complete frugal install on $DEV, copy the /arch directory to your disk and configure your bootloader with kernel /boot/vmlinuz and initrd /boot/initramfs.img with archisobasedir=arch." --width=450 --center
fi
EOF
chmod +x "${ROOTFS}/usr/local/bin/frugalpup"

# --- G. Session Save Utility (save2flash) ---
cat << 'EOF' > "${ROOTFS}/usr/local/bin/save2flash"
#!/usr/bin/env bash
PARTS=$(lsblk -o NAME,LABEL,SIZE,MOUNTPOINT | awk 'NR>1 && $1 !~ /loop/ {print $1, ($2==""?"NONE":$2), $3, ($4==""?"NONE":$4)}')
PICK=$(yad --list --title="save2flash - Save Session" --window-icon="document-save" \
  --width=480 --height=240 --center \
  --text="Select partition to save personal changes and settings:" \
  --column="Partition" --column="Label" --column="Size" --column="Mounted" $PARTS)

[ -z "$PICK" ] && exit 0
PNAME=$(echo "$PICK" | cut -d'|' -f1)
MNT=$(echo "$PICK" | cut -d'|' -f4)

if [ "$MNT" = "NONE" ]; then
  mkdir -p "/mnt/$PNAME"
  mount "/dev/$PNAME" "/mnt/$PNAME" 2>/dev/null || true
  MNT="/mnt/$PNAME"
fi

tar -czf "$MNT/archpup-save-$(date +%Y%m%d).tar.gz" -C /root . 2>/dev/null
yad --info --title="Session Saved" --text="Personal session and settings saved to $MNT!" --width=350 --center
EOF
chmod +x "${ROOTFS}/usr/local/bin/save2flash"

# Conky System Monitor Overlay
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
    extra_newline = false,
    font = 'Sans:size=10',
    gap_x = 35,
    gap_y = 35,
    minimum_height = 200,
    minimum_width = 250,
    net_avg_samples = 2,
    no_buffers = true,
    out_to_console = false,
    out_to_ncurses = false,
    out_to_stderr = false,
    out_to_x = true,
    own_window = true,
    own_window_class = 'Conky',
    own_window_type = 'desktop',
    own_window_transparent = true,
    own_window_argb_visual = true,
    own_window_argb_value = 0,
    show_graph_range = false,
    show_graph_scale = false,
    stippled_borders = 0,
    update_interval = 1.0,
    uppercase = false,
    use_spacer = 'none',
    use_xft = true,
}

conky.text = [[
${color #38bdf8}${font Sans:size=28:bold}${time %H:%M}${font}${color}
${color #38bdf8}${font Sans:size=11:bold}${time %A %d %B %Y}${font}${color}
${color #64748b}${hr 1}${color}
${color #94a3b8}OS:${color} ArchPup 26.0.1
${color #94a3b8}Kernel:${color} $kernel
${color #94a3b8}RAM Usage:${color} $mem / $memmax
${color #94a3b8}CPU Usage:${color} $cpu%
${color #64748b}${hr 1}${color}
${color #38bdf8}Puppy Utilities:${color}
* Quickpet (App Store)
* PetGet (.PET Installer)
* Simple Network Setup (SNS)
* Control Center (Settings)
* Dock & Pinned Apps Manager
* Theme & Glass Settings
* FrugalPup (Live Installer)
* save2flash (Save Session)
]]
EOF

# Default Glassy Compositor Configuration
mkdir -p "${ROOTFS}/root/.config/picom"
cat << 'EOF' > "${ROOTFS}/root/.config/picom/picom.conf"
backend = "xrender";
shadow = true;
shadow-radius = 12;
shadow-opacity = 0.45;
shadow-offset-x = -12;
shadow-offset-y = -12;

fading = true;
fade-delta = 4;

active-opacity = 0.94;
inactive-opacity = 0.88;
frame-opacity = 0.85;

corner-radius = 8;
rounded-corners-exclude = [
  "window_type = 'dock'",
  "window_type = 'desktop'"
];

opacity-rule = [
  "100:class_g = 'Firefox'",
  "100:class_g = 'Gparted'",
  "100:class_g = 'LibreOffice'"
];
EOF

# Pre-generate default Frutiger Aero dock list
mkdir -p "${ROOTFS}/root/.config"
cat << 'EOF' > "${ROOTFS}/root/.config/archpup-dock.conf"
TRUE|AppStore|/usr/local/bin/quickpet
TRUE|Browser|firefox
TRUE|WiFi|/usr/local/bin/sns
TRUE|Settings|/usr/local/bin/puppy-settings
TRUE|Files|pcmanfm
TRUE|Terminal|xterm
TRUE|Save|/usr/local/bin/save2flash
EOF

# Set up Frutiger Aero Wallpaper
mkdir -p "${ROOTFS}/usr/share/backgrounds"
if [ -f "wallpaper.jpg" ]; then
  cp "wallpaper.jpg" "${ROOTFS}/usr/share/backgrounds/archpup-wallpaper.jpg"
elif [ -f "wp11964556-puppy-linux-wallpapers.jpg" ]; then
  cp "wp11964556-puppy-linux-wallpapers.jpg" "${ROOTFS}/usr/share/backgrounds/archpup-wallpaper.jpg"
elif curl -fsSL --retry 2 "https://raw.githubusercontent.com/FrutigerKapi/ArchPup/main/wallpaper.jpg" -o "${ROOTFS}/usr/share/backgrounds/archpup-wallpaper.jpg" 2>/dev/null; then
  echo "Downloaded wallpaper from repo."
fi

# Clean X11 startup (picom disabled by default to prevent VM black screen)
cat << 'EOF' > "${ROOTFS}/root/.xinitrc"
#!/bin/sh
xsetroot -solid "#112233" &
if [ -f "/usr/share/backgrounds/archpup-wallpaper.jpg" ]; then
  feh --bg-fill /usr/share/backgrounds/archpup-wallpaper.jpg &
fi
nm-applet &
conky -c /root/.config/conky/conky.conf &
/usr/local/bin/quicksetup &
exec jwm
EOF
chmod +x "${ROOTFS}/root/.xinitrc"

# JWM Configuration with Iced Glass Aesthetics & Standalone Dock
cat << 'EOF' > "${ROOTFS}/root/.jwmrc"
<?xml version="1.0"?>
<JWM>
  <RootMenu label="Puppy" height="26">
    <Program label="Puppy App Store (Quickpet)">/usr/local/bin/quickpet</Program>
    <Program label="Web Browser (Firefox)">firefox</Program>
    <Program label="Simple Network Setup (Wi-Fi)">/usr/local/bin/sns</Program>
    <Program label="Puppy Control Center (Settings)">/usr/local/bin/puppy-settings</Program>
    <Program label="Theme &amp; Glass Settings">/usr/local/bin/puppy-theme-settings</Program>
    <Program label="Dock &amp; Pinned Apps Manager">/usr/local/bin/puppy-dock-manager</Program>
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

  <Tray x="0" y="-1" autohide="off" height="34">
    <TrayButton label="  Puppy  ">root:1</TrayButton>
    <Spacer width="4"/>
    <TrayButton label=" AppStore ">exec:/usr/local/bin/quickpet</TrayButton>
    <TrayButton label=" Browser ">exec:firefox</TrayButton>
    <TrayButton label=" WiFi ">exec:/usr/local/bin/sns</TrayButton>
    <TrayButton label=" Settings ">exec:/usr/local/bin/puppy-settings</TrayButton>
    <TrayButton label=" Files ">exec:pcmanfm</TrayButton>
    <TrayButton label=" Terminal ">exec:xterm</TrayButton>
    <TrayButton label=" Save ">exec:/usr/local/bin/save2flash</TrayButton>
    <Spacer width="2"/>
    <TrayButton label=" ⚙ Dock ">exec:/usr/local/bin/puppy-dock-manager</TrayButton>
    <Spacer width="6"/>
    <TaskList maxwidth="200"/>
    <Dock/>
    <Clock format="%H:%M"><Button mask="123">exec:xterm -e cal</Button></Clock>
  </Tray>

  <TrayStyle>
    <Font>sans-serif-10:bold</Font>
    <Background>#112338:#1e3c5a</Background>
    <Foreground>#e0f2fe</Foreground>
    <Active>
      <Background>#0ea5e9:#0284c7</Background>
      <Foreground>#ffffff</Foreground>
    </Active>
  </TrayStyle>

  <TaskListStyle>
    <Font>sans-serif-9:bold</Font>
    <Active>
      <Background>#38bdf8:#0284c7</Background>
      <Foreground>#ffffff</Foreground>
    </Active>
    <Inactive>
      <Background>#0f1c2c:#182e44</Background>
      <Foreground>#94a3b8</Foreground>
    </Inactive>
  </TaskListStyle>

  <WindowStyle>
    <Font>sans-serif-10:bold</Font>
    <Width>2</Width>
    <Height>24</Height>
    <Active>
      <Text>#ffffff</Text>
      <Title>#253a4c:#15222d</Title>
      <Corner>#38bdf8</Corner>
      <Outline>#0284c7</Outline>
    </Active>
    <Inactive>
      <Text>#94a3b8</Text>
      <Title>#141b22:#0c1116</Title>
      <Corner>#475569</Corner>
      <Outline>#1e293b</Outline>
    </Inactive>
  </WindowStyle>
</JWM>
EOF

rm -rf "${ROOTFS}/var/cache/pacman/pkg/"* "${ROOTFS}/tmp/"*

# 6. Compress rootfs into SquashFS
echo "--> Compressing root filesystem into SquashFS..."
umount -l "${ROOTFS}/dev" "${ROOTFS}/proc" "${ROOTFS}/sys" 2>/dev/null || true

mksquashfs "${ROOTFS}" "${ISO_DIR}/arch/x86_64/airootfs.sfs" \
  -comp zstd \
  -noappend \
  -wildcards \
  -e "dev/*" "proc/*" "sys/*" "tmp/*" "run/*" "mnt/*" "media/*"

# 7. Syslinux & Hybrid Bootable ISO Creation (Live RAM Mode Default)
echo "--> Creating bootable ISO..."
cp /usr/lib/ISOLINUX/isolinux.bin "${ISO_DIR}/isolinux/"
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "${ISO_DIR}/isolinux/"

cat << 'EOF' > "${ISO_DIR}/isolinux/isolinux.cfg"
DEFAULT archpup
TIMEOUT 50
PROMPT 1

LABEL archpup
  MENU LABEL ArchPup 26.0.1 (Live RAM Mode - Default)
  KERNEL /boot/vmlinuz
  INITRD /boot/initramfs.img
  APPEND archisobasedir=arch archisolabel=ARCHPUP_26 quiet

LABEL archpup_persist
  MENU LABEL ArchPup 26.0.1 (Persistent Mode - Requires ARCHPUP_SAVE disk)
  KERNEL /boot/vmlinuz
  INITRD /boot/initramfs.img
  APPEND archisobasedir=arch archisolabel=ARCHPUP_26 cow_label=ARCHPUP_SAVE quiet
EOF

xorriso -as mkisofs -iso-level 3 -R -J -l \
  -volid "ARCHPUP_26" \
  -b isolinux/isolinux.bin -c isolinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  -o "${OUT_DIR}/ArchPup-26.0.1-x86_64.iso" "${ISO_DIR}"

isohybrid "${OUT_DIR}/ArchPup-26.0.1-x86_64.iso" 2>/dev/null || true

echo "=== Build Complete! ISO generated at ${OUT_DIR}/ArchPup-26.0.1-x86_64.iso ==="
