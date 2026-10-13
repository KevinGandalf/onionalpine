# Alpine XFCE + Tor

Live-USB (BIOS + UEFI) auf **Alpine Linux 3.24**: XFCE startet automatisch,
LibreWolf geht nur über Tor, und eine Firewall lässt fast nichts an Tor vorbei
(fail-closed). IPv6 ist aus.

Das ist nicht Tails und nicht der Tor Browser. Details für den Stick stehen in
[iso-build/src/Liesmich.txt](iso-build/src/Liesmich.txt).

| | |
|---|---|
| Image | `alpine-xfce-tor-3.24.2-x86_64.iso` |
| SHA256 | `f717103fd126c534e1d5d83e79a4aa733e2f706a2d6c43304a09cd98d1606563` |
| Anmeldung | `live` / `live` |
| Rechte | `doas` ohne Passwort |
| Tastatur | Deutsch, Alt+Shift auf US |
| Zeitzone | Europe/Berlin |

Die ISO selbst liegt als [Release](https://github.com/KevinGandalf/onionalpine/releases)
(GitHub nimmt keine Dateien über 100 MB ins Git). Secure Boot muss aus sein.

## Was im Repo liegt

- [iso-build/packages.txt](iso-build/packages.txt) — Paketliste
- [iso-build/src/](iso-build/src/) — Konfiguration, Tor, Firewall, Init, ISO-Bau

Nicht eingecheckt: `rootfs/` (installiertes System), `sdk/` (Build-Chroot)
und `out/` (SquashFS und ISO). Die entstehen beim Bau neu.

## Bauen

Die Skripte erwarten diesen Baum unter `/workspace/iso-build` (Root-Rechte,
`apk`, `xorriso`, GRUB, syslinux). Reihenfolge der vorhandenen Schritte:

1. Rootfs aus dem Alpine-Minirootfs ziehen und Pakete aus `packages.txt` installieren
2. `configure.sh` — Benutzer, Tor, XFCE, Firewall
3. SquashFS + Initramfs
4. `src/build-iso.sh` — hybrides BIOS/UEFI-ISO nach `out/`

## Auf USB schreiben

Gerät komplett ersetzen, nicht eine Partition (`sdX`, nicht `sdX1`):

```sh
sudo dd if=alpine-xfce-tor-3.24.2-x86_64.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

Windows: Rufus im DD-Modus oder balenaEtcher.
