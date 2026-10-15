# Abre uma janela do PowerShell (opcionalmente rodando um comando) ou, se a janela
# aberta por este mesmo botao ainda existir, apenas traz ela para frente.
#   janela.ps1 -Id powershell
#   janela.ps1 -Id claude-zx -Dir C:\Users\Acer\zx-control-semana1 -Comando claude
param(
  [Parameter(Mandatory)][string]$Id,
  [string]$Dir = $HOME,
  [string]$Comando = ''
)

$estado = Join-Path $env:LOCALAPPDATA 'macropad-janelas'
New-Item -ItemType Directory -Force $estado | Out-Null
$arquivoPid = Join-Path $estado "$Id.pid"

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class MPJanela {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
'@

function Focar([System.Diagnostics.Process]$p) {
  $h = $p.MainWindowHandle
  if ($h -eq [IntPtr]::Zero) { return $false }
  if ([MPJanela]::IsIconic($h)) { [MPJanela]::ShowWindow($h, 9) | Out-Null }  # 9 = restaurar
  # O Windows so deixa trazer janelas para frente apos uma tecla; Alt pressionado libera isso.
  [MPJanela]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
  $ok = [MPJanela]::SetForegroundWindow($h)
  [MPJanela]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
  return $ok
}

if (Test-Path $arquivoPid) {
  $antigo = Get-Process -Id ([int](Get-Content $arquivoPid)) -ErrorAction SilentlyContinue
  # Confere o nome: o numero do processo pode ter sido reaproveitado por outro programa.
  if ($antigo -and $antigo.ProcessName -eq 'conhost' -and (Focar $antigo)) {
    'Janela ja aberta: trazida para frente'
    exit 0
  }
}

# conhost = janela classica do console: tem um processo proprio para localizar depois
# (no Windows Terminal todas as abas dividem o mesmo processo).
$argumentos = @('powershell.exe', '-NoExit')
if ($Comando) { $argumentos += @('-Command', $Comando) }
try {
  $p = Start-Process conhost.exe -ArgumentList $argumentos -WorkingDirectory $Dir -PassThru -ErrorAction Stop
} catch {
  Write-Output "Nao foi possivel abrir a janela: $($_.Exception.Message)"
  exit 1
}
$p.Id | Set-Content $arquivoPid
'Nova janela aberta'
