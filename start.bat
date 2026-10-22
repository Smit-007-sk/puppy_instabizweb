@echo off
title TeddyPups Localhost Server
echo Starting TeddyPups server on http://localhost:3000...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" -Port 3000
pause
