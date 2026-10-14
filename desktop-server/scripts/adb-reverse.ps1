# Cria o túnel USB: localhost:PORT no celular -> localhost:PORT no desktop (Windows).
#   .\scripts\adb-reverse.ps1            # porta 8080
#   .\scripts\adb-reverse.ps1 -Port 9000 -Watch
param([int]$Port = 8080, [switch]$Watch)
$ErrorActionPreference = 'Stop'

$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) {
  $root = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
  if ($root) { $adb = Join-Path $root 'platform-tools\adb.exe' }
}
if (-not $adb -or -not (Test-Path $adb)) { Write-Error 'adb não encontrado. Instale o Android platform-tools.' }

function Apply {
  $serials = & $adb devices | Select-Object -Skip 1 | ForEach-Object {
    $f = $_ -split '\s+'; if ($f.Count -ge 2 -and $f[1] -eq 'device') { $f[0] }
  }
  if (-not $serials) { Write-Warning 'Nenhum aparelho autorizado. Ative a Depuração USB.'; return }
  foreach ($s in $serials) {
    $list = & $adb -s $s reverse --list
    if (-not ($list -match "tcp:$Port tcp:$Port")) {
      & $adb -s $s reverse "tcp:$Port" "tcp:$Port" | Out-Null
      Write-Host "OK [$s] celular localhost:$Port -> desktop localhost:$Port"
    }
  }
}

& $adb start-server | Out-Null
if ($Watch) { while ($true) { Apply; Start-Sleep -Seconds 3 } } else { Apply }
