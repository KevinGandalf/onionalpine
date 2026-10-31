@echo off
rem Doppelklick beendet die Tor-Box. Alles ausser dem Ordner downloads wird geloescht.
cd /d "%~dp0"
docker compose down
echo Tor-Box beendet.
timeout /t 5 >nul
