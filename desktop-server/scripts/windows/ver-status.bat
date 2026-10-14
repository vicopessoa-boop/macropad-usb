@echo off
title Macropad USB - status
cd /d "%~dp0"
echo === Programa ===
tasklist /fi "imagename eq macropad.exe" | find /i "macropad.exe" >nul && (echo Rodando em segundo plano.) || (echo PARADO - de dois cliques em iniciar-oculto.vbs ou iniciar.bat)
echo.
echo === Ultimas linhas do log (macropad.log) ===
if exist macropad.log (powershell -NoProfile -Command "Get-Content -Tail 15 -Encoding UTF8 'macropad.log'") else (echo Sem log ainda.)
echo.
pause
