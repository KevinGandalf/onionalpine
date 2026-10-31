#!/bin/bash
# Startet optional ein VPN (WireGuard oder OpenVPN) samt Killswitch und
# danach Desktop, noVNC und Tor Browser über supervisord.
set -euo pipefail

log() { echo "[tor-box] $*"; }
die() { echo "[tor-box] FEHLER: $*" >&2; exit 1; }

VPN_DIR=/vpn
REQUIRE_VPN=${REQUIRE_VPN:-0}

shopt -s nullglob nocaseglob
wg_files=("$VPN_DIR"/*.conf)
ovpn_files=("$VPN_DIR"/*.ovpn)
shopt -u nocaseglob

n=$(( ${#wg_files[@]} + ${#ovpn_files[@]} ))
[ "$n" -le 1 ] || die "Im Ordner vpn/ darf nur EINE .conf- oder .ovpn-Datei liegen (gefunden: $n)."

# Downloads-Ordner beschreibbar machen (Bind-Mount vom Host)
chown app:app /home/app/Downloads 2>/dev/null || true

# iptables: nft-Backend, sonst auf legacy ausweichen
if ! iptables -w -S >/dev/null 2>&1; then
	update-alternatives --set iptables /usr/sbin/iptables-legacy >/dev/null 2>&1 || true
	update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy >/dev/null 2>&1 || true
fi

# Killswitch: Der Benutzer "app" (Browser + Tor) darf nur über lo und die
# VPN-Schnittstelle raus. Fällt das VPN aus, ist er offline statt ungeschützt.
killswitch() {
	# (Aufruf steht in "killswitch || die", dort greift set -e nicht: daher &&-Kette)
	{ iptables -w -N APP_OUT 2>/dev/null || iptables -w -F APP_OUT; } &&
	iptables -w -A APP_OUT -o lo -j ACCEPT &&
	iptables -w -A APP_OUT -o wg+ -j ACCEPT &&
	iptables -w -A APP_OUT -o tun+ -j ACCEPT &&
	iptables -w -A APP_OUT -o tap+ -j ACCEPT &&
	iptables -w -A APP_OUT -j REJECT &&
	{ iptables -w -C OUTPUT -m owner --uid-owner app -j APP_OUT 2>/dev/null ||
	  iptables -w -A OUTPUT -m owner --uid-owner app -j APP_OUT; } || return 1
	# IPv6 ist per sysctl aus; zusätzlich alles für "app" sperren, falls möglich
	ip6tables -w -C OUTPUT -m owner --uid-owner app ! -o lo -j REJECT 2>/dev/null \
		|| ip6tables -w -A OUTPUT -m owner --uid-owner app ! -o lo -j REJECT 2>/dev/null \
		|| log "Hinweis: ip6tables nicht verfügbar (IPv6 ist ohnehin abgeschaltet)."
}

start_wireguard() {
	local src=$1 dns
	log "WireGuard: $(basename "$src")"
	install -d -m 0700 /etc/wireguard
	# DNS/Skript-Zeilen entfernen, IPv6-Einträge streichen (IPv6 ist aus)
	/usr/local/bin/wg-sanitize "$src" > /etc/wireguard/wg0.conf
	chmod 0600 /etc/wireguard/wg0.conf
	grep -Eqi '^[[:space:]]*AllowedIPs[[:space:]]*=' /etc/wireguard/wg0.conf \
		|| die "WireGuard-Datei enthält keine IPv4-AllowedIPs."
	wg-quick up wg0 || die "WireGuard-Tunnel ließ sich nicht starten."
	dns=$(grep -Ei '^[[:space:]]*DNS[[:space:]]*=' "$src" | head -1 | cut -d= -f2- \
		| tr ',' '\n' | tr -d ' \t\r' | grep -E '^[0-9]+(\.[0-9]+){3}$' | head -1 || true)
	if [ -n "$dns" ]; then
		echo "nameserver $dns" > /etc/resolv.conf
	fi
}

start_openvpn() {
	local src=$1 i
	local args=(--config "$src" --cd "$VPN_DIR" --daemon --log /var/log/openvpn.log
		--writepid /run/openvpn.pid --script-security 2 --up /usr/local/bin/ovpn-dns-up
		--pull-filter ignore ifconfig-ipv6 --pull-filter ignore route-ipv6
		--pull-filter ignore block-outside-dns)
	log "OpenVPN: $(basename "$src")"
	[ -e /dev/net/tun ] || { mkdir -p /dev/net; mknod /dev/net/tun c 10 200 2>/dev/null || true; }
	[ -e /dev/net/tun ] || die "/dev/net/tun fehlt (devices-Eintrag in docker-compose.yml)."
	if [ -f "$VPN_DIR/auth.txt" ]; then
		args+=(--auth-user-pass "$VPN_DIR/auth.txt")
	fi
	openvpn "${args[@]}" || die "OpenVPN ließ sich nicht starten."
	for i in $(seq 1 60); do
		if grep -q 'Initialization Sequence Completed' /var/log/openvpn.log 2>/dev/null; then
			return 0
		fi
		if [ -f /run/openvpn.pid ] && ! kill -0 "$(cat /run/openvpn.pid)" 2>/dev/null; then
			break
		fi
		sleep 1
	done
	tail -n 30 /var/log/openvpn.log >&2 || true
	die "OpenVPN-Verbindung kam nicht zustande (Log oben)."
}

if [ "$n" -eq 1 ] || [ "$REQUIRE_VPN" = 1 ]; then
	killswitch || die "Killswitch (iptables) ließ sich nicht einrichten. Fehlt cap_add: NET_ADMIN?"
	log "Killswitch aktiv: Browser-Verkehr nur über das VPN."
fi

if [ ${#wg_files[@]} -eq 1 ]; then
	start_wireguard "${wg_files[0]}"
elif [ ${#ovpn_files[@]} -eq 1 ]; then
	start_openvpn "${ovpn_files[0]}"
elif [ "$REQUIRE_VPN" = 1 ]; then
	log "WARNUNG: REQUIRE_VPN=1, aber keine VPN-Datei in vpn/. Der Browser bleibt offline."
else
	log "Kein VPN konfiguriert: Tor verbindet sich direkt."
fi

[ -n "$(ip -o link show wg0 2>/dev/null)$(ip -o link show tun0 2>/dev/null)" ] && log "VPN steht."
log "Tor Browser $(cat /opt/tor-browser/VERSION.txt 2>/dev/null || echo ?)"
log "Öffnen: http://localhost:6080"

exec /usr/bin/supervisord -c /etc/supervisor/tor-box.conf
