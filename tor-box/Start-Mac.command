#!/bin/bash
# Doppelklick startet die Tor-Box und öffnet sie im Browser.
cd "$(dirname "$0")" || exit 1
if ! docker info >/dev/null 2>&1; then
	echo "Docker läuft nicht. Bitte Docker Desktop starten und erneut versuchen."
	read -r -p "Enter zum Schließen" _
	exit 1
fi
echo "Tor-Box wird gestartet (beim ersten Mal dauert das einige Minuten) ..."
docker compose up -d --build || { read -r -p "Fehler. Enter zum Schließen" _; exit 1; }
for _ in $(seq 1 60); do
	curl -fs -o /dev/null http://localhost:6080/ && break
	sleep 1
done
open "http://localhost:6080/"
echo "Fertig. Dieses Fenster kann geschlossen werden."
