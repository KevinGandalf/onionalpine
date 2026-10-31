# onionalpine

Zwei Wege, sicher über Tor ins Netz zu gehen:

| | [Tor-Box (Docker)](#tor-box-docker) | [Live-USB (Alpine)](#live-usb-alpine) |
|---|---|---|
| Browser | **offizieller Tor Browser** | LibreWolf, fest über Tor |
| VPN | WireGuard **und** OpenVPN, mit Killswitch | WireGuard |
| Läuft auf | Windows, macOS (Intel + Apple Silicon), Linux | x86_64-PCs, Secure Boot aus |
| Einrichtung | Docker Desktop installieren, Doppelklick | ISO auf USB-Stick schreiben, davon booten |
| Spuren | Container wird beim Beenden gelöscht | läuft nur im RAM |

**Für die meisten ist die Tor-Box der einfachere Weg.**

---

## Tor-Box (Docker)

Der offizielle Tor Browser in einem Container, bedient im ganz normalen
Web-Browser unter http://localhost:6080. Alles steht im Ordner
[`tor-box/`](tor-box/), die ausführliche Anleitung in
[`tor-box/LIESMICH.md`](tor-box/LIESMICH.md).

**Kurzanleitung**

1. [Docker Desktop](https://www.docker.com/products/docker-desktop/) installieren und starten.
2. Dieses Repo herunterladen (grüner Knopf „Code“ → „Download ZIP“) und entpacken.
3. Im Ordner `tor-box/` doppelklicken:
   - Windows: `Start-Windows.bat`
   - Mac: `Start-Mac.command` (beim ersten Mal Rechtsklick → Öffnen)
   - Linux: `docker compose up -d --build`
4. Der Browser öffnet http://localhost:6080, der Tor Browser verbindet sich selbst.

Beenden mit `Stop-Windows.bat` / `Stop-Mac.command` / `docker compose down`.
Dabei wird alles gelöscht außer dem Ordner `tor-box/downloads/`.

**Was drin ist**

- Tor Browser direkt von torproject.org, beim Bau gegen den Signaturschlüssel
  der Tor-Entwickler geprüft (`EF6E 286D DA85 EA2A 4BA7 DE68 4E2C 6E87 9329 8290`).
  Läuft nativ auf x86_64 und ARM64.
- Optional **WireGuard** (`.conf`) oder **OpenVPN** (`.ovpn`, ggf. mit `auth.txt`):
  Datei in `tor-box/vpn/` legen, neu starten. Weg: Rechner → VPN → Tor.
- **Killswitch:** Ist ein VPN eingerichtet, darf der Browser nur durch den
  Tunnel. Fällt das VPN aus, ist er offline statt ungeschützt.
  `REQUIRE_VPN: "1"` in `docker-compose.yml` sperrt ihn auch ohne VPN-Datei.
- IPv6 im Container abgeschaltet, Weboberfläche nur von `127.0.0.1` erreichbar.
- VPN-Dateien und Downloads sind per `.gitignore` vom Einchecken ausgeschlossen.

**Aktualisieren:** `docker compose build --no-cache --pull` im Ordner
`tor-box/` lädt den neuesten Tor Browser.

---

## Live-USB (Alpine)

Live-USB (BIOS + UEFI) auf **Alpine Linux 3.24**: XFCE startet automatisch,
LibreWolf geht nur über Tor, und eine Firewall lässt fast nichts an Tor vorbei
(fail-closed). IPv6 ist aus. Das ist nicht Tails und nicht der Tor Browser.
Details für den Stick stehen in [iso-build/src/Liesmich.txt](iso-build/src/Liesmich.txt).

| | |
|---|---|
| Image | `alpine-xfce-tor-3.24.2-x86_64.iso` ([Releases](https://github.com/KevinGandalf/onionalpine/releases)) |
| SHA256 | `4192121b54b24ac1ecb80cc51a40d4b7141423740132b21af0093d51edf10d84` |
| Anmeldung | `live` / `live` |
| Rechte | `doas` ohne Passwort |
| Tastatur | Deutsch, Alt+Shift auf US |
| Zeitzone | Europe/Berlin |
| VPN | WireGuard über das Desktop-Icon (`.conf` von Mullvad, Proton, IVPN, …) |

GitHub nimmt keine Dateien über 100 MB ins Git, die ISO liegt deshalb nur
als Release. Secure Boot muss aus sein.

### Auf USB schreiben

Gerät komplett ersetzen, nicht eine Partition (`sdX`, nicht `sdX1`):

```sh
sudo dd if=alpine-xfce-tor-3.24.2-x86_64.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

Windows/macOS: balenaEtcher, oder Rufus im DD-Modus.

### Bekannte Einschränkungen

- **Kein OpenVPN und kein Tor Browser** im Image; dafür die Tor-Box nutzen.
- **Nur x86_64.** Macs mit Apple Silicon und 32-Bit-UEFI-Geräte starten es nicht.
- **Secure Boot** muss aus sein (GRUB ist nicht signiert).
- **Manche schnelle USB-3-Sticks und USB-SSDs** (UAS, z. B. Samsung T7) werden
  beim Start nicht gefunden, weil das Init das Modul `uas` nicht lädt.
  Ergebnis: „Live-Medium nicht gefunden“. Dann einen einfachen USB-Stick nehmen.
- Die Firewall lässt UDP von Root-Prozessen ungefiltert hinaus.

### Bauen

Die Skripte erwarten diesen Baum unter `/workspace/iso-build` (Root-Rechte,
`apk`, `xorriso`, GRUB, syslinux). Nicht eingecheckt: `rootfs/` (installiertes
System), `sdk/` (Build-Chroot) und `out/` (SquashFS und ISO).

1. Rootfs aus dem Alpine-Minirootfs ziehen und Pakete aus [`iso-build/packages.txt`](iso-build/packages.txt) installieren
2. `configure.sh` — Benutzer, Tor, XFCE, Firewall
3. SquashFS + Initramfs
4. `src/build-iso.sh` — hybrides BIOS/UEFI-ISO nach `out/`

Für Schritt 1 und 3 liegen keine Skripte im Repo; die ISO lässt sich aus dem
Repo allein daher noch nicht reproduzierbar neu bauen.
