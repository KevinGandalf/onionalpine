#!/bin/bash
# Doppelklick beendet die Tor-Box. Alles außer dem Ordner downloads/ wird gelöscht.
cd "$(dirname "$0")" || exit 1
docker compose down
echo "Tor-Box beendet."
