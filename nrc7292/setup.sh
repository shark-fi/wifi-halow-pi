#!/usr/bin/env bash
# ALFA AHPI7292S (Newracom NRC7292) setup for Raspberry Pi OS.
# Verified on Raspberry Pi CM4, bookworm 64-bit Lite, kernel 6.6.51+rpt-rpi-v8.
#
# Run as your normal user, NOT with sudo - it calls sudo where needed, and
# running the whole thing as root puts ~/nrc_pkg in /root.
set -euo pipefail

REPO="https://github.com/craigpeacock/nrc7292_sw_pkg.git"
DRIVER_REF_66="cce7d1589"     # "Add support for v6.2. Tested on v6.6.51"
DRIVER_REF_618="master"       # targets 6.18
WORKDIR="${HOME}/halow-nrc"
KSRC="${KSRC:-/lib/modules/$(uname -r)/build}"
EXPECT_BD_MD5="bbe184e9b5212cddcc520cd0ef7e0cd2"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn(){ printf '\033[1;33m    %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

say "Preflight"
[ "$(id -u)" -ne 0 ] || die "Do not run with sudo. Run: bash setup.sh"

KREL="$(uname -r)"; KMAJ="${KREL%%.*}"; KMIN="$(echo "$KREL" | cut -d. -f2)"
MODEL="$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo unknown)"
echo "kernel: $KREL"
echo "model : $MODEL"

[ -d "$KSRC" ] || die "No kernel headers at $KSRC.
       sudo apt install linux-headers-\$(uname -r)"
[ -f "$KSRC/Module.symvers" ] || die "$KSRC/Module.symvers is missing.
       The module will build but not load. This is the WLAN Pi OS packaging
       defect - use stock Raspberry Pi OS. See notes/wlanpi-kernel-headers.md"
echo "hdrs  : OK"

case "$MODEL" in
  *"Pi 5"*|*"Compute Module 5"*)
    warn "Pi 5 / CM5: the overlay declares compatible only through bcm2711 and"
    warn "the reset line uses a hardcoded BCM GPIO behind RP1. Expect failure."
    sleep 4 ;;
esac

if   [ -f /boot/firmware/config.txt ]; then BOOT=/boot/firmware
elif [ -f /boot/config.txt ];          then BOOT=/boot
else die "Cannot find config.txt"; fi
echo "boot  : $BOOT"

# Pick the driver commit that matches this kernel.
if [ "$KMAJ" -eq 6 ] && [ "$KMIN" -le 12 ]; then
    DRIVER_REF="$DRIVER_REF_66"
    echo "driver: $DRIVER_REF (6.6-era API)"
else
    DRIVER_REF="$DRIVER_REF_618"
    echo "driver: $DRIVER_REF (6.18-era API)"
fi

say "Installing dependencies"
sudo apt-get update -qq
sudo apt-get install -y build-essential git device-tree-compiler python3 \
    wireless-tools iw wpasupplicant iptables tcpdump

mkdir -p "$WORKDIR"; cd "$WORKDIR"

say "Cloning the maintained fork"
if [ -d nrc7292_sw_pkg/.git ]; then
    git -C nrc7292_sw_pkg remote set-url origin "$REPO"
    git -C nrc7292_sw_pkg fetch --quiet origin
    git -C nrc7292_sw_pkg checkout --quiet master
    git -C nrc7292_sw_pkg reset --hard --quiet origin/master
else
    rm -rf nrc7292_sw_pkg
    git clone --quiet "$REPO"
fi
SRC="$WORKDIR/nrc7292_sw_pkg"; PKG="$SRC/package"
git -C "$SRC" log --oneline -1

say "Installing device tree overlay"
# Two overlays ship; the 5.16+ one is correct on any modern kernel.
if [ "$KMAJ" -gt 5 ] || { [ "$KMAJ" -eq 5 ] && [ "$KMIN" -ge 16 ]; }; then
    DTS="$SRC/dts/newracom_for_5.16_or_later.dts"
else
    DTS="$SRC/dts/newracom.dts"
fi
[ -f "$DTS" ] || die "Overlay source not found: $DTS"
echo "  $(basename "$DTS")"
dtc -@ -I dts -O dtb -o /tmp/newracom.dtbo "$DTS" 2>/dev/null \
    || dtc -I dts -O dtb -o /tmp/newracom.dtbo "$DTS"
sudo install -m 0644 /tmp/newracom.dtbo "$BOOT/overlays/newracom.dtbo"
grep -qE '^\s*dtoverlay=newracom' "$BOOT/config.txt" \
    || echo 'dtoverlay=newracom' | sudo tee -a "$BOOT/config.txt" >/dev/null
grep -qE '^\s*dtparam=spi=on' "$BOOT/config.txt" \
    || echo 'dtparam=spi=on' | sudo tee -a "$BOOT/config.txt" >/dev/null

# MUST run from master: the AHPI7292S board file and 64-bit cli_app exist only there.
say "Installing runtime package from master (~/nrc_pkg)"
cd "$PKG/evk/sw_pkg" && chmod +x ./update.sh && ./update.sh

say "Verifying board data file"
BD=~/nrc_pkg/sw/firmware/nrc7292_bd.dat
[ -f "$BD" ] || die "No board data file at $BD"
BD_MD5="$(md5sum "$BD" | awk '{print $1}')"
echo "  $(wc -c < "$BD") bytes  md5=$BD_MD5"
if [ "$BD_MD5" = "$EXPECT_BD_MD5" ]; then
    echo "  OK - ALFA AHPI7292S board file"
else
    warn "NOT the AHPI7292S board file. The 2104-byte Newracom EVK file has a"
    warn "target-version field that does not match this board; the driver will"
    warn "reject it with 'BD file is invalid! Stop loading FW'."
fi

say "Building driver from $DRIVER_REF"
cd "$SRC"
[ "$DRIVER_REF" = "master" ] || git checkout --quiet "$DRIVER_REF"
cd "$PKG/src/nrc"
make clean >/dev/null 2>&1 || true
make 2>&1 | tee /tmp/nrc-build.log || die "Build failed - see /tmp/nrc-build.log
       If the errors name timer_delete_sync_try, timer_container_of or
       ieee80211_emulate_add_chanctx, the source is newer than your kernel."
cp -f nrc.ko ~/nrc_pkg/sw/driver/
echo "  $(file -b ~/nrc_pkg/sw/driver/nrc.ko | cut -c1-46)"
# Leave the tree back on master so update.sh is never run from the old commit.
git -C "$SRC" checkout --quiet master

say "Patching start.py"
# Lines 780-788 use script+path; the variable defined at line 7 is script_path.
if grep -q 'script+path' ~/nrc_pkg/script/start.py; then
    sed -i 's/script+path/script_path/g' ~/nrc_pkg/script/start.py
    echo "  fixed script+path -> script_path"
else
    echo "  already correct"
fi

say "Loading mac80211"
# start.py uses insmod, which does not resolve dependencies. The NRC driver is
# softmac; the Pi's onboard Broadcom radio is fullmac and only pulls in cfg80211.
sudo modprobe mac80211
grep -qx mac80211 /etc/modules 2>/dev/null || echo mac80211 | sudo tee -a /etc/modules >/dev/null

say "Releasing wlan0 from NetworkManager"
# Otherwise NM's supplicant and start.py's fight, and scans return EBUSY (-16).
sudo tee /etc/NetworkManager/conf.d/99-halow-unmanaged.conf >/dev/null <<'EOF'
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
sudo systemctl disable --now wpa_supplicant.service 2>/dev/null || true
sudo systemctl restart NetworkManager 2>/dev/null || true

say "Onboard Wi-Fi"
# start.py hardcodes wlan0, which is the Broadcom radio unless we disable it.
# Refuse if this session is running over a wireless interface.
SSH_IP="$(echo "${SSH_CONNECTION:-}" | awk '{print $3}')"
LINK_IF=""
[ -n "$SSH_IP" ] && LINK_IF="$(ip -o -4 addr show | awk -v ip="$SSH_IP" '$4 ~ "^"ip"/" {print $2; exit}')"
if [ -n "$LINK_IF" ] && [ "${LINK_IF#wlan}" != "$LINK_IF" ]; then
    warn "This session is on $LINK_IF - NOT disabling onboard Wi-Fi."
    warn "Move to Ethernet, then add 'dtoverlay=disable-wifi' to $BOOT/config.txt"
else
    [ -n "$LINK_IF" ] && echo "  session is on ${LINK_IF} - safe"
    grep -qE '^\s*dtoverlay=disable-wifi' "$BOOT/config.txt" \
        || echo 'dtoverlay=disable-wifi' | sudo tee -a "$BOOT/config.txt" >/dev/null
    echo "  onboard Wi-Fi disabled; HaLow radio becomes wlan0"
fi

cat <<'EOF'

--------------------------------------------------------------------------
Reboot, then:
--------------------------------------------------------------------------
    sudo reboot

Station mode (edit the SSID first - it defaults to "halow_demo"):

    sed -i 's/ssid="halow_demo"/ssid="YOUR-SSID"/' ~/nrc_pkg/script/conf/US/sta_halow_open.conf
    ~/nrc_pkg/script/start.py 0 0 US
    sudo dhclient wlan0 && iw dev wlan0 link

AP mode:

    ~/nrc_pkg/script/start.py 1 0 US

Monitor mode:

    bash monitor.sh 2447

EOF
