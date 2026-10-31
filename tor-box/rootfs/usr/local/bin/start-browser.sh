#!/bin/sh
# Startet den Tor Browser im Vordergrund (supervisord startet ihn neu, wenn er geschlossen wird).
cd /opt/tor-browser || exit 1
# Warten, bis der X-Server läuft
i=0
while [ ! -S /tmp/.X11-unix/X1 ] && [ "$i" -lt 30 ]; do
	sleep 1
	i=$((i + 1))
done
exec ./Browser/start-tor-browser
