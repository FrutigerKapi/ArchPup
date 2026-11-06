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
  mesa \
  xf86-input-libinput \
  jwm \
  picom \
  pcmanfm \
  firefox \
  xterm \
  feh \
  fastfetch \
  chafa \
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


# Install Official ArchPup Hybrid Logos (Dock, Fastfetch, Dialogs, Menu)
echo "--> Installing ArchPup system logos..."
mkdir -p "${ROOTFS}/usr/share/pixmaps"
mkdir -p "${ROOTFS}/usr/share/icons/hicolor/256x256/apps"
mkdir -p "${ROOTFS}/usr/share/icons/hicolor/48x48/apps"
mkdir -p "${ROOTFS}/usr/share/icons/hicolor/24x24/apps"

cat << 'B64_EOF' | base64 -d > "${ROOTFS}/usr/share/pixmaps/archpup.png"
iVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAMAAABrrFhUAAADAFBMVEX///////7///3///v+///9///+//z+//n8///8//r5//3//v/+/v/+/v7+/f7//v3+/v3+/f3+/vv//vf9/v79/f79/f39/fr8/v78/f38/fn6/v74/v75/vr+/P79/P38/P78/Pz9/Pn9+v39+vf7/P37+/37+/v7+v35+/35+/j5+fr3+PX4+PH59/j39/r39/j39/f69/X49/X59/H39/b39/T59vj49vn49vf39vv69vX79vH49vX49vL69fj49fr89fT49fT78/v79PX1/f31+vf0+fb1+fL1+Pr1+Pf2+PX19/v29/j19vr29/f19/P29vXy+/ny+fry+fby+Pzz9/fv+/ru9/vo9/ry8vTr8vfr6+zg7/XS6/Ph4eHX3uHX19fT09PXz8nR0dHQ0NDPz8/Ozs7Nzc3MzMzLzMvLy8vKysrKw7/F5e+74e232+jJycmu0+LExMSi0+SZy96Lxt59wtyztLSfn59xuthnsdJTr9hLqdVGpdQ9ntAxntUmnNYpmM8olc0clc4YldEdlNAZlNEYlNMYlNEYlMwdk88ak9AZk9EZk80Yk9UYk9IYk9EYk9AYk88Yk80XltIXlNQXlNEXlM0Xk9UXk9MXk9IXk9EXk9AXk88SmdISl9IUltUTls4QltQVldYVldIVldAVlc4VlcsTldMTldARldUSldIVlNYVlNMVlNIWlNEVlNEWlNAWlM8VlNAWlM0UlNQUlNESlNcSlNIWk9UWk9MWk9IWk9EWk88Vk9YVk9IRk9M8kb8ekM8dkNAckdMckc0bkdMbkNUbkcwakdQaktIaktAaks0aj9AZkdUZktMZktIZkNcZktEZks8ZkMwXktcYktUYktQYktMXktQYkdcYktIXktIYktAXkM0VktgVktMUkNMUkcsUjswQkNMQkMwQjs4OkM4KkM+DhIRwcHAjicEWi8oTjNEUjMkPjc0KispfXl5KUVVCQkI2NjYoKCkbGhoREREKCgoFBQUDAwMCAgIBAQEAAgIAAABO1h22AABMKUlEQVR42t29CTyUax8/fFuS0ggJ2TqW86gkZDeWhMNYUg0h2+E9bW/nRZax76eaM9XIkmRmPEIYyhLGHEvqyT5EYaSkeWos6aAjS5u//30PSZYj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
B64_EOF

cat << 'B64_EOF' | base64 -d > "${ROOTFS}/usr/share/pixmaps/archpup-menu.png"
iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAMAAADXqc3KAAAAwFBMVEX//////vr9/v///fr//fn9/f79+vn4+vv49/b39/fy+Pr19vf09vf29PPv8/Xl6+7a6/Lf3t7S5/DB4vHO0NGs2O2l0+mZ0Oqmx9eurq6Dw+NsstVbst1HqNk/qNwyoNYmmtMnls4dldEbldIbldEaldIXltVDlL0alNIalNEZlNIZlNEZk9AYlNEYk9EXk9EXk9AUk9IykL8VktEVkc8UktERkNAOkdMPj9AMjs8UjMkIjM8HjM4Gi85MgZtGR0eF1d/iAAABkklEQVR42lVS23KjMAwVDSVNS8olBgYKCV2v0zhKcKcsAQcM//9Xa1Oms6vxg6Qzx0c32GhzHTvMipKfyyILbcc1OTB528+p7GptnWS5b7vfwIsVs0FwKvNcUl4PLLZeDOBayVBTIZja7RQTgtZDojng2vGAKATeDuuHQ2e88xCvXHB8XutIsD4BSJSmCqy574CdDyYQ2O3g4bm8XbVPh9yGcE4L2mdR+LhQdBhCJrl2qvrXKzwDLBQuMyiMnqAqA1htNk7SzypdAWVTaUJTBiQlxt6XGM6LQuARAo9ekLV8rmUGrreDl6Zj+hqM6dNe4gyYr6iKrXSaNDCRIOlO81daHLv9ep1O4zhO4JHoT10ZcV0uUxFsSDqZRzyIJZpyQ4Yyh2j/sYWAeMHbIYK8R92gnSueFaprP8h2G7zdW1Vkv5UeieMjNpIitvevr3t/RCobRD1EdxWrk+n2cmzbI/vUTZ2UGfvPokR1uVSm2bpPLHderR1zvVo0o0AuhtOy2u9jYLJrhGj+O4af87le/zmfv77eSafTq38lAAAAAElFTkSuQmCC
B64_EOF

cp "${ROOTFS}/usr/share/pixmaps/archpup.png" "${ROOTFS}/usr/share/icons/hicolor/256x256/apps/archpup.png"
cp "${ROOTFS}/usr/share/pixmaps/archpup.png" "${ROOTFS}/usr/share/icons/hicolor/48x48/apps/archpup.png"
cp "${ROOTFS}/usr/share/pixmaps/archpup-menu.png" "${ROOTFS}/usr/share/icons/hicolor/24x24/apps/archpup.png"

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
                                     …·‘‚‚‚‚‚‚‚‚‚‚‚‚‚‚‚‚‚‚‘·…
                                …‚‚‚‚‘‘‘‚‚‚‚‚‚‚‚‚‚‚‚‚‚‚‚‚‚‘‘‘‚‚‚‚…
                             …‘‚­‚‚‘…                        …‘‚‚­‚‘…
                          ‘‚‚‚‚‘                ··                ‘‚‚‚‚‘
                       …‚­‚‘…                  ‚’’‚                  …‘‚­‚…
                     …‚­‚…                     ;¨¨;                     …‚­‚…
                   …‚­‚                       ;›  ›;                       ‚­‚…
                  ‚­‚                        ›;    ;;                        ‚­‘
                …°‚                         ’;      ;›                         ‚‚…
               :‚…                          ;’       ;’                         …‘:
              ‘‘                           ››        ’;                           ‘‘
             ‚‚                           ‚;          ›;                           ‚‚
            ‚‚                           ·`‚…          ;;                           ‚‘
           ‘‚                           ‚ˆ   ;’·        ;;                           ‘:
          ’‚                           ˜›`;›¸ …`         ;;                           ‚…
         …­                           ˜;¨   `¹‚·          ;;                          …°
         ‚‘                          ’;´                   ;›                          ‚‚
        …‚                          ´;’                     ;‚                          ­…
        ‘‚                         ·;…       ‹;ª/«/““»¬!÷¬“’··˜·                        ‚‚
        ‚‘                        …‹ `;¹· ·¹›                   ´                       ‘‚
        ‚…                       ·› ˜          ›¬•/““•»|ª‹;‘‚º …‚                       …‚
       …‘                       ¨; ; ›·¨   ·ˆ …˜          ¸  – ›‚˜                       ‘…
       …’                      ¨;… °´…˜^”~°– ‚ °ˆ       ´‚·¹;| – ;˜                      ‘…
       …’                     ¨;˜ …‘´    ³²—~˜ “…      „¯­`‚  ´² ´;˜                     ‘…
       …‘                    ¨;˜   ² …         ‹      ;›   ›‘„`ˆ   ;‚                   …‚
        ‚…                  ¨;˜    ª  ¬ª¹ ;^ª  —      ‚°–°„÷  ’ ¸ :¨´;`                 ‘‚
        ‘‘                 ¨;˜    ¸¹¨ “   ;  ; ¦…°—“³²º …°;   ; ;`   ‘                  ‚‚
        …‚                ¨;˜     ¸­` ÷ˆ  ˆ–º‘ ;   ˆ‚;·˜’     ¹ ’ ¹¹…‚                  ­…
         ‚‘              ¨;˜       „ ¹ ªª¹;  …~; ;¦„‚ …° º¡ˆ;˜˜´˜    ’‹‹´              ‚‚
         …­             ¨;˜      ˜‚: :  ²º“ª—¯  °·  ·ˆ~    : — °¨      ’;’             ­…
          ’‚           ¨›…   ’;;;;;‚  ²¸       …     :­˜‚°; ›; ‚››;;’    ;‚           ‚’
           ‘‘        ¨:›  :;;;;›`      ;–¸     ²„—:ª~    ¨º”‚     ’;;;;;  ;‘´        ‘‘
            ‘’          …›››`           ˆ–°””:        ’„­­¨          `›;›; `        ’‘
             ‘‘      ·ˆ–‘                 ·ˆ…‹‘:–°°–:‘‹ˆ¨  ·             ‘’˜·      ‘‘
              ‚‚                           …` ˆ;’‘‘’;ˆ ¨                          ‘‘
               ‚‚                                                               ·’‘
                ‘­‚                                                            ‚­‘
                 …‚­‚                                                        ‚­‚
                   …‚­‚                                                    ‚­‚…
                     …‚­‚                                                ‚­‚…
                       …‚­‚‘                                          ‘‚­‚…
                         …‚‚­‚‘…                                  …‘‚­‚‚…
                            …‚‚‚‚‚‚’                          ’‚‚‚‚‚‚…
                                …‘‚‚‚‚‚‚‚‚‚‚‘·…    …·‘‚‚‚‚‚‚‚‚‚‚‘…
                                    …‘‚‚‚‚‚‚‘‘‘‘’’‘‘‘‘‚‚‚‚‚‚‘…
                                               …………
EOF

cat << 'EOF' > "${ROOTFS}/root/.config/fastfetch/config.jsonc"
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "type": "file",
    "source": "/etc/archpup-ascii.txt",
    "color": {
      "1": "cyan",
      "2": "light_blue"
    },
    "padding": {
      "top": 0,
      "left": 1,
      "right": 2
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

SEL_DEV=$(yad --list --title="Simple Network Setup (SNS)" --window-icon="/usr/share/pixmaps/archpup.png" \
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

  WIFI_PICK=$(eval yad --list --title="Connect to Wi-Fi ($INTF)" --window-icon="/usr/share/pixmaps/archpup.png" \
    --width=450 --height=320 --center \
    --column="SSID (Network)" --column="Signal" --column="Security" $YAD_SSIDS)

  [ -z "$WIFI_PICK" ] && exit 0
  SSID=$(echo "$WIFI_PICK" | cut -d'|' -f1)

  PASS=$(yad --entry --title="Wi-Fi Password" --window-icon="/usr/share/pixmaps/archpup.png" \
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
  <IconPath>/usr/share/pixmaps:/usr/share/icons/hicolor/24x24/apps:/usr/share/icons/hicolor/48x48/apps</IconPath>
  <RootMenu label="ArchPup" icon="/usr/share/pixmaps/archpup-menu.png" height="26">
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
    <TrayButton icon="/usr/share/pixmaps/archpup-menu.png" label=" ArchPup">root:1</TrayButton>
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
  --window-icon="/usr/share/pixmaps/archpup.png" --width=520 --height=380 --center \
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


cat << 'EOF' > "${ROOTFS}/usr/share/applications/quickpet.desktop"
[Desktop Entry]
Name=Puppy App Store (Quickpet)
Comment=Install applications and utilities
Exec=/usr/local/bin/quickpet
Icon=/usr/share/pixmaps/archpup.png
Terminal=false
Type=Application
Categories=System;PackageManager;
EOF

cat << 'EOF' > "${ROOTFS}/usr/share/applications/puppy-settings.desktop"
[Desktop Entry]
Name=Puppy Control Center
Comment=System settings and control panel
Exec=/usr/local/bin/puppy-settings
Icon=/usr/share/pixmaps/archpup.png
Terminal=false
Type=Application
Categories=Settings;
EOF

cat << 'EOF' > "${ROOTFS}/usr/share/applications/frugalpup.desktop"
[Desktop Entry]
Name=FrugalPup Installer
Comment=Install ArchPup frugally to USB or hard drive
Exec=/usr/local/bin/frugalpup
Icon=/usr/share/pixmaps/archpup.png
Terminal=false
Type=Application
Categories=System;
EOF

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
CHOICE=$(yad --list --title="Puppy Control Center" --window-icon="/usr/share/pixmaps/archpup.png" --image="/usr/share/pixmaps/archpup.png" \
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

ANS=$(yad --form --title="QuickSetup - First Run Settings" --window-icon="/usr/share/pixmaps/archpup.png" --image="/usr/share/pixmaps/archpup.png" \
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
  CHOICE=$(yad --list --title="Puppy App Store (Quickpet)" --window-icon="/usr/share/pixmaps/archpup.png" --image="/usr/share/pixmaps/archpup.png" \
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
TARGET=$(yad --list --title="FrugalPup Installer" --window-icon="/usr/share/pixmaps/archpup.png" \
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
PICK=$(yad --list --title="save2flash - Save Session" --window-icon="/usr/share/pixmaps/archpup.png" \
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
# Reliable baseline for physical PCs and virtual machines:
# keep compositing and transparent widgets off during startup.
xsetroot -solid "#b9e8f5"

if [ -r "/usr/share/backgrounds/archpup-wallpaper.jpg" ]; then
  feh --bg-fill /usr/share/backgrounds/archpup-wallpaper.jpg \
    >/tmp/archpup-feh.log 2>&1 &
fi

nm-applet >/tmp/archpup-network.log 2>&1 &
/usr/local/bin/quicksetup >/tmp/archpup-quicksetup.log 2>&1 &
exec jwm
EOF
chmod +x "${ROOTFS}/root/.xinitrc"

# JWM Configuration with Iced Glass Aesthetics & Standalone Dock
cat << 'EOF' > "${ROOTFS}/root/.jwmrc"
<?xml version="1.0"?>
<JWM>
  <IconPath>/usr/share/pixmaps:/usr/share/icons/hicolor/24x24/apps:/usr/share/icons/hicolor/48x48/apps</IconPath>
  <RootMenu label="ArchPup" icon="/usr/share/pixmaps/archpup-menu.png" height="26">
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
    <TrayButton icon="/usr/share/pixmaps/archpup-menu.png" label=" ArchPup">root:1</TrayButton>
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

