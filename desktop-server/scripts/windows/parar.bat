@echo off
title Macropad USB - parar
taskkill /im macropad.exe /f >nul 2>&1 && (echo Macropad USB parado.) || (echo O Macropad USB nao estava rodando.)
pause
