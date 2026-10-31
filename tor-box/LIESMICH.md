# Tor-Box

Der offizielle **Tor Browser** in einem Docker-Container, bedient direkt im
normalen Web-Browser. Wahlweise läuft alles hinter **WireGuard** oder
**OpenVPN**, mit Killswitch: Fällt das VPN aus, ist der Tor Browser offline
statt ungeschützt.

Läuft unter Windows, macOS (Intel und Apple Silicon) und Linux.

## Einmalig

1. **Docker Desktop** installieren: https://www.docker.com/products/docker-desktop/
   und einmal starten.
2. Diesen Ordner irgendwohin entpacken, z. B. auf den Schreibtisch.

## Starten

- **Windows:** Doppelklick auf `Start-Windows.bat`
- **Mac:** Doppelklick auf `Start-Mac.command`
  (beim ersten Mal: Rechtsklick → Öffnen, weil macOS das Skript nicht kennt)
- **Linux:** im Ordner `docker compose up -d --build`, dann http://localhost:6080 öffnen

Der erste Start dauert einige Minuten: Das Image wird gebaut und der Tor
Browser direkt bei torproject.org geladen. Seine Signatur wird dabei geprüft;
stimmt sie nicht, bricht der Bau ab.

Danach öffnet sich im Browser die Seite **http://localhost:6080** mit dem
Tor Browser. Er verbindet sich automatisch mit Tor.

## VPN (optional)

Genau **eine** Datei in den Ordner `vpn/` legen und neu starten:

| VPN | Datei | Hinweis |
|---|---|---|
| WireGuard | `name.conf` | z. B. aus dem Mullvad-, Proton- oder IVPN-Konto |
| OpenVPN | `name.ovpn` | braucht der Anbieter Login-Daten: zusätzlich `auth.txt` (Zeile 1 Benutzer, Zeile 2 Passwort) |

Dann gilt: Rechner → VPN → Tor. Der VPN-Anbieter sieht nur, dass Tor
benutzt wird; das lokale Netz sieht nur das VPN.

Soll der Browser **nie** ohne VPN ins Netz, in `docker-compose.yml`
`REQUIRE_VPN: "1"` setzen.

## Beenden

- **Windows:** `Stop-Windows.bat` · **Mac:** `Stop-Mac.command` · **Linux:** `docker compose down`

Beim Beenden wird alles gelöscht: Verlauf, Cookies, Tor-Zustand. Nur der
Ordner `downloads/` bleibt erhalten.

## Aktualisieren

Der Tor Browser wird beim Bau des Images geladen. Für eine neue Version
(etwa einmal im Monat oder wenn er ein Update meldet):

```
docker compose build --no-cache --pull
```

Danach normal starten.

## Gut zu wissen

- Die Seite http://localhost:6080 ist nur vom eigenen Rechner aus erreichbar
  und hat kein Passwort.
- Docker selbst läuft mit vollen Rechten auf dem Rechner. Wer den Rechner
  kontrolliert, kann auch in den Container schauen.
- Der Tor Browser schützt nur, wenn man sich entsprechend verhält: keine
  persönlichen Konten, keine heruntergeladenen Dokumente öffnen, während man
  online ist.
- Für maximale Anonymität ist Tails (https://tails.net) die bessere Wahl;
  die Tor-Box ist ein bequemer Mittelweg.

## Fehlersuche

```
docker compose logs -f
```

zeigt, was beim Start passiert (VPN, Tor Browser-Version, Fehler).
