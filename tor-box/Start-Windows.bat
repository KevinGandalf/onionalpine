@echo off
rem Doppelklick startet die Tor-Box und oeffnet sie im Browser.
cd /d "%~dp0"
docker info >nul 2>&1
if errorlevel 1 (
  echo Docker laeuft nicht. Bitte Docker Desktop starten und erneut versuchen.
  pause
  exit /b 1
)
echo Tor-Box wird gestartet (beim ersten Mal dauert das einige Minuten) ...
docker compose up -d --build
if errorlevel 1 (
  echo Fehler beim Start.
  pause
  exit /b 1
)
for /l %%i in (1,1,60) do (
  curl -fs -o nul http://localhost:6080/ && goto open
  timeout /t 1 /nobreak >nul
)
:open
start "" "http://localhost:6080/"
echo Fertig. Dieses Fenster kann geschlossen werden.
timeout /t 5 >nul
