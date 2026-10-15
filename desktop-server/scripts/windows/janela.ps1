# Abre o terminal (Windows Terminal) de um botao do macropad, ou, se a janela aberta
# por esse mesmo botao ainda existir, apenas traz ela para frente.
#   janela.ps1 -Id powershell -Titulo 'Macropad PowerShell'
#   janela.ps1 -Id claude-zx -Titulo 'Macropad Claude' -Dir C:\Users\Acer\zx-control-semana1 -Comando claude
# Sem Windows Terminal instalado, usa a janela classica do console.
param(
  [Parameter(Mandatory)][string]$Id,
  [string]$Titulo = '',
  [string]$Dir = $HOME,
  [string]$Comando = ''
)
if (-not $Titulo) { $Titulo = "Macropad $Id" }

$estado = Join-Path $env:LOCALAPPDATA 'macropad-janelas'
New-Item -ItemType Directory -Force $estado | Out-Null
$arquivo = Join-Path $estado "$Id.hwnd"

Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class MPJanela {
  delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr p);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  public static string Classe(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
  public static string Titulo(IntPtr h) { var s = new StringBuilder(512); GetWindowText(h, s, 512); return s.ToString(); }
  // Janelas de primeiro nivel com esta classe e este titulo.
  public static List<IntPtr> Procurar(string classe, string titulo) {
    var r = new List<IntPtr>();
    EnumWindows((h, p) => { if (Classe(h) == classe && Titulo(h) == titulo) r.Add(h); return true; }, IntPtr.Zero);
    return r;
  }
}
'@

$classesTerminal = @('CASCADIA_HOSTING_WINDOW_CLASS', 'ConsoleWindowClass')

function Focar([IntPtr]$h) {
  if ([MPJanela]::IsIconic($h)) { [MPJanela]::ShowWindow($h, 9) | Out-Null }  # 9 = restaurar
  # O Windows so deixa trazer uma janela para frente apos uma tecla; Alt pressionado libera isso.
  [MPJanela]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
  [MPJanela]::SetForegroundWindow($h) | Out-Null
  [MPJanela]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
}

# 1. Janela aberta antes por este botao ainda existe? Traz para frente.
if (Test-Path $arquivo) {
  $h = [IntPtr][long](Get-Content $arquivo)
  if ([MPJanela]::IsWindow($h) -and $classesTerminal -contains [MPJanela]::Classe($h)) {
    Focar $h
    'Terminal ja aberto: trazido para frente'
    exit 0
  }
}

# 2. Abre uma nova.
$wt = Get-Command wt.exe -ErrorAction SilentlyContinue
try {
  if ($wt) {
    # Janela nomeada (-w): mesmo se o registro se perder, o botao nunca cria uma segunda janela.
    # --suppressApplicationTitle mantem o titulo fixo (o Claude Code tenta trocar o titulo).
    $argumentos = "-w macropad-$Id new-tab --title `"$Titulo`" --suppressApplicationTitle -d `"$Dir`" powershell.exe -NoExit"
    if ($Comando) { $argumentos += " -Command $Comando" }
    Start-Process $wt.Source -ArgumentList $argumentos -ErrorAction Stop
    $classe = 'CASCADIA_HOSTING_WINDOW_CLASS'
  } else {
    $argumentos = @('powershell.exe', '-NoExit', '-Command', "`$Host.UI.RawUI.WindowTitle = '$Titulo'; $Comando")
    Start-Process conhost.exe -ArgumentList $argumentos -WorkingDirectory $Dir -ErrorAction Stop
    $classe = 'ConsoleWindowClass'
  }
} catch {
  Write-Output "Nao foi possivel abrir o terminal: $($_.Exception.Message)"
  exit 1
}

# 3. Guarda a janela nova para o proximo toque (espera ela aparecer, ate ~8 s).
for ($i = 0; $i -lt 40; $i++) {
  Start-Sleep -Milliseconds 200
  $achadas = [MPJanela]::Procurar($classe, $Titulo)
  if ($achadas.Count -gt 0) {
    [long]$achadas[0] | Set-Content $arquivo
    'Terminal aberto'
    exit 0
  }
}
'Terminal aberto (janela nao localizada para o proximo toque)'
