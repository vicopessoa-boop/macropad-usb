@echo off
title Macropad USB - ativar inicio automatico
cd /d "%~dp0"
set "DIR=%~dp0"
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut([Environment]::GetFolderPath('Startup')+'\Macropad USB.lnk'); $s.TargetPath='wscript.exe'; $s.Arguments='\"%DIR%iniciar-oculto.vbs\"'; $s.WorkingDirectory='%DIR%'; $s.Save()"
if errorlevel 1 (
  echo Nao foi possivel criar o atalho de inicializacao.
  pause
  exit /b 1
)
wscript.exe "%DIR%iniciar-oculto.vbs"
echo.
echo Pronto! O Macropad USB agora:
echo  - esta rodando em segundo plano (sem janela);
echo  - vai iniciar sozinho sempre que voce ligar o computador;
echo  - reconecta sozinho quando voce plugar o cabo do celular.
echo.
echo Para ver se esta funcionando: ver-status.bat
echo Para parar: parar.bat   ^|   Para desligar o inicio automatico: desativar-inicio-automatico.bat
echo.
pause
