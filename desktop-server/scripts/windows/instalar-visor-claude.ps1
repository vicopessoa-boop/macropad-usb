# Liga o Claude Code ao visor do Macropad USB.
# Adiciona hooks do tipo "http" em ~/.claude/settings.json que avisam o macropad
# quando o Claude comeca a trabalhar, pede autorizacao, termina ou da erro.
# Pode rodar quantas vezes quiser: substitui as entradas antigas do macropad.
param([int]$Port = 8091)

$path = Join-Path $HOME '.claude\settings.json'
New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
if (Test-Path $path) {
  Copy-Item $path "$path.backup-macropad" -Force
  $raw = Get-Content $path -Raw -Encoding UTF8
  $s = if ([string]::IsNullOrWhiteSpace($raw)) { [pscustomobject]@{} } else { $raw | ConvertFrom-Json }
} else {
  $s = [pscustomobject]@{}
}
if (-not $s.PSObject.Properties['hooks']) { $s | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) }

$url = "http://127.0.0.1:$Port/claude"
$events = 'SessionStart', 'UserPromptSubmit', 'PostToolUse', 'PermissionRequest', 'Notification', 'Stop', 'StopFailure', 'SessionEnd'
foreach ($e in $events) {
  $groups = @()
  if ($s.hooks.PSObject.Properties[$e]) {
    # Mantem os hooks que voce ja tinha; remove so os do macropad (reinstalacao).
    $groups = @(@($s.hooks.$e) | Where-Object { -not (@($_.hooks) | Where-Object { $_.url -like '*127.0.0.1*/claude' }) })
  }
  $groups += [pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'http'; url = $url; timeout = 3 }) }
  $s.hooks | Add-Member -Force -NotePropertyName $e -NotePropertyValue $groups
}
[IO.File]::WriteAllText($path, ($s | ConvertTo-Json -Depth 50))
Write-Host "Visor do Claude ativado em $path" -ForegroundColor Green
Write-Host "Feche e abra o Claude Code para comecar a usar." -ForegroundColor Green
