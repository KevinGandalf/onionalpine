#!/bin/sh
# Configure the Alpine rootfs. Run on the host; uses chroot for user and services.
set -eu
ROOT=/workspace/iso-build/rootfs
SRC=/workspace/iso-build/src

install -m 0644 "$SRC/torrc" "$ROOT/etc/tor/torrc"
mkdir -p "$ROOT/etc/iptables"
install -m 0644 "$SRC/rules-save" "$ROOT/etc/iptables/rules-save"
install -m 0644 "$SRC/rules6-save" "$ROOT/etc/iptables/rules6-save"

cat > "$ROOT/etc/init.d/mac-randomize" << 'EOF'
#!/sbin/openrc-run
description="Randomize MAC addresses before the network comes up"
depend() {
	before networkmanager net
	after udev
}
start() {
	local i
	for i in /sys/class/net/*; do
		i=${i##*/}
		[ "$i" = lo ] && continue
		[ -e "/sys/class/net/$i/address" ] || continue
		ip link set "$i" down 2>/dev/null || true
		macchanger -e "$i" >/dev/null 2>&1 || macchanger -r "$i" >/dev/null 2>&1 || true
	done
	return 0
}
EOF
chmod 0755 "$ROOT/etc/init.d/mac-randomize"

mkdir -p "$ROOT/etc/local.d"
gzip -dc "$ROOT/usr/share/bkeymaps/de/de.bmap.gz" > "$ROOT/etc/keymap.bmap"
cat > "$ROOT/etc/local.d/keymap.start" << 'EOF'
#!/bin/sh
[ -f /etc/keymap.bmap ] && loadkmap < /etc/keymap.bmap
EOF
chmod 0755 "$ROOT/etc/local.d/keymap.start"

mkdir -p "$ROOT/etc/X11/xorg.conf.d"
cat > "$ROOT/etc/X11/xorg.conf.d/00-keyboard.conf" << 'EOF'
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "de,us"
    Option "XkbModel" "pc105"
    Option "XkbVariant" ","
    Option "XkbOptions" "grp:alt_shift_toggle"
EndSection
EOF

mkdir -p "$ROOT/etc/sysctl.d"
cat > "$ROOT/etc/sysctl.d/tor-live.conf" << 'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF

mkdir -p "$ROOT/etc/NetworkManager/conf.d"
cat > "$ROOT/etc/NetworkManager/conf.d/tor-live.conf" << 'EOF'
[main]
plugins=keyfile
dhcp=internal
dns=none
rc-manager=unmanaged

[device]
wifi.backend=wpa_supplicant
wifi.scan-rand-mac-address=yes
EOF

printf '%s\n' 'nameserver 127.0.0.1' > "$ROOT/etc/resolv.conf"
printf '%s\n' 'alpine-tor' > "$ROOT/etc/hostname"
cat > "$ROOT/etc/hosts" << 'EOF'
127.0.0.1	localhost alpine-tor
::1		localhost alpine-tor
EOF
printf '%s\n' 'a1b2c3d4e5f64789a0b1c2d3e4f50617' > "$ROOT/etc/machine-id"
ln -sfn /usr/share/zoneinfo/Europe/Berlin "$ROOT/etc/localtime"
printf '%s\n' 'Europe/Berlin' > "$ROOT/etc/timezone"

cat > "$ROOT/etc/doas.conf" << 'EOF'
permit nopass :wheel
EOF
chmod 0640 "$ROOT/etc/doas.conf"

cat > "$ROOT/etc/motd" << 'EOF'
Alpine XFCE + Tor (Live)

Benutzer live, Passwort live.  doas für Root-Rechte.
Browser geht über Tor.  Lies ~/Liesmich.txt
EOF

# LightDM autologin into XFCE
python3 - << 'PY'
from pathlib import Path
p = Path("/workspace/iso-build/rootfs/etc/lightdm/lightdm.conf")
t = p.read_text()
repls = {
    "#greeter-session=example-gtk-gnome": "greeter-session=lightdm-gtk-greeter",
    "#user-session=default": "user-session=xfce",
    "#allow-guest=false": "allow-guest=false",
    "#autologin-user=": "autologin-user=live",
    "#autologin-user-timeout=0": "autologin-user-timeout=0",
    "#autologin-session=": "autologin-session=xfce",
}
for a,b in repls.items():
    if a not in t:
        raise SystemExit(f"missing lightdm line: {a}")
    t = t.replace(a, b, 1)
p.write_text(t)
print("lightdm ok")
PY

# LibreWolf: keep upstream policies, force Tor SOCKS.
python3 - << 'PY'
import json
from pathlib import Path
p = Path("/workspace/iso-build/rootfs/usr/lib/librewolf/distribution/policies.json")
data = json.loads(p.read_text())
pol = data.setdefault("policies", {})
pol["Proxy"] = {
    "Mode": "manual",
    "Locked": True,
    "SOCKSProxy": "127.0.0.1:9050",
    "SOCKSVersion": 5,
    "Passthrough": "localhost, 127.0.0.1",
}
pol["Homepage"] = {
    "URL": "https://check.torproject.org/",
    "StartPage": "homepage",
    "Locked": False,
}
prefs = pol.setdefault("Preferences", {})
prefs.update({
    "network.proxy.type": {"Value": 1, "Status": "locked"},
    "network.proxy.socks": {"Value": "127.0.0.1", "Status": "locked"},
    "network.proxy.socks_port": {"Value": 9050, "Status": "locked"},
    "network.proxy.socks_version": {"Value": 5, "Status": "locked"},
    "network.proxy.socks_remote_dns": {"Value": True, "Status": "locked"},
    "network.proxy.no_proxies_on": {"Value": "localhost, 127.0.0.1", "Status": "locked"},
    "media.peerconnection.enabled": {"Value": False, "Status": "locked"},
    "network.dns.disablePrefetch": {"Value": True, "Status": "locked"},
    "privacy.resistFingerprinting": {"Value": True, "Status": "locked"},
})
p.write_text(json.dumps(data, indent=2) + "\n")
print("policies ok", p.stat().st_size)
PY

# OpenRC runlevels (symlinks, do not start services here)
link() {
	level="$1"; svc="$2"
	mkdir -p "$ROOT/etc/runlevels/$level"
	ln -sfn "/etc/init.d/$svc" "$ROOT/etc/runlevels/$level/$svc"
}
for s in cgroups dmesg udev udev-trigger udev-settle procfs sysfs; do
	link sysinit "$s"
done
for s in hwclock modules sysctl hostname bootmisc seedrng loopback localmount iptables ip6tables mac-randomize; do
	link boot "$s"
done
for s in udev-postmount dbus elogind polkit wpa_supplicant networkmanager tor chronyd udisks2 local lightdm; do
	link default "$s"
done
for s in mount-ro killprocs savecache; do
	link shutdown "$s"
done

# User, under the ownership shim so home dirs are recorded.
chroot "$ROOT" /bin/sh -c '
set -eu
export LD_PRELOAD=/fakeown.so
export FAKEOWN_LOG=/fakeown.log
if ! id live >/dev/null 2>&1; then
  adduser -D -h /home/live -s /bin/bash live
fi
echo "live:live" | chpasswd
usermod -aG wheel,audio,video,input,plugdev,netdev,lp,cdrom,dialout,pulse-access live
passwd -l root >/dev/null 2>&1 || true
install -d -m 0755 /home/live/Desktop /home/live/.config/autostart
'
install -m 0644 "$SRC/Liesmich.txt" "$ROOT/home/live/Liesmich.txt"
install -m 0644 "$SRC/Liesmich.txt" "$ROOT/home/live/Desktop/Liesmich.txt"
# desktop launcher
python3 - << 'PY'
from pathlib import Path
src = Path("/workspace/iso-build/rootfs/usr/share/applications")
cands = list(src.glob("*ibrewolf*.desktop")) + list(src.glob("*irewolf*.desktop"))
print("desktop files", [c.name for c in cands])
if not cands:
    raise SystemExit("no librewolf desktop file")
text = cands[0].read_text()
# point name at Tor
lines=[]
for line in text.splitlines():
    if line.startswith("Name="):
        lines.append("Name=Browser über Tor")
    elif line.startswith("Comment="):
        lines.append("Comment=LibreWolf, fest über Tor")
    else:
        lines.append(line)
Path("/workspace/iso-build/rootfs/home/live/Desktop/browser-tor.desktop").write_text("\n".join(lines)+"\n")
PY
chmod 0755 "$ROOT/home/live/Desktop/browser-tor.desktop"

chroot "$ROOT" /bin/sh -c '
export LD_PRELOAD=/fakeown.so FAKEOWN_LOG=/fakeown.log
chown -R live:live /home/live
chown root:shadow /etc/shadow /etc/gshadow 2>/dev/null || true
chmod 640 /etc/shadow /etc/gshadow 2>/dev/null || true
chmod 0755 /home/live/Desktop/browser-tor.desktop
'
# immutable resolv.conf so NetworkManager cannot point DNS at the LAN
chroot "$ROOT" /bin/sh -c 'chattr +i /etc/resolv.conf' || echo "chattr skipped"

echo CONFIGURE_OK
id_line=$(grep '^live:' "$ROOT/etc/passwd")
echo "$id_line"
ls -l "$ROOT/etc/runlevels/default"
