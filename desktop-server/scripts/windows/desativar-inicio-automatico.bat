@echo off
title Macropad USB - desativar inicio automatico
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Macropad USB.lnk" 2>nul
taskkill /im macropad.exe /f >nul 2>&1
echo Inicio automatico desativado e Macropad USB parado.
echo Para usar de novo: iniciar.bat (com janela) ou ativar-inicio-automatico.bat.
pause
