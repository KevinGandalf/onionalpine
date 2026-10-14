#!/bin/sh
# NetworkManager dispatcher: tag WireGuard interfaces so the firewall
# can let tunnel traffic through without opening the rest of the LAN.
iface="$1"
action="$2"
[ "$action" = "pre-up" ] || [ "$action" = "up" ] || exit 0
[ -n "$iface" ] || exit 0
if ip -d link show "$iface" 2>/dev/null | grep -q wireguard; then
	ip link set dev "$iface" group 51820 || true
fi
exit 0
