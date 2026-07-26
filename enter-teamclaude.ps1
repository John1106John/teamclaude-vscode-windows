<#
  enter-teamclaude.ps1 - enter teamclaude proxy mode
  1. Opens a separate window running `teamclaude server` (live quota panel + resident proxy)
  2. Sets user-level environment variables so Claude Code routes through the proxy
  Fully restart VS Code afterwards for this to take effect. Use exit-teamclaude.ps1 to undo.
#>
$ErrorActionPreference = 'Stop'
$env:TEAMCLAUDE_DISABLE_AUTOUPDATE = '1'

# 1. Confirm teamclaude has accounts (the command prints assertion noise on exit; its output is still valid)
$accounts = teamclaude accounts 2>&1
if ($accounts -match 'No accounts configured') {
  Write-Host "X No teamclaude accounts. Run: teamclaude login (at least one, preferably two)."
  exit 1
}
Write-Host "Accounts detected:"
$accounts | Where-Object { $_ -match '^\s*\[' } | ForEach-Object { Write-Host "  $_" }

# 2. Read the environment values to set from teamclaude env
$envLines = teamclaude env 2>&1 | Where-Object { $_ -match '^export ' }
$baseUrl = $null; $apiKey = $null
foreach ($l in $envLines) {
  if ($l -match 'ANTHROPIC_BASE_URL=(.+)$') { $baseUrl = $Matches[1].Trim() }
  if ($l -match 'ANTHROPIC_API_KEY=(.+)$')  { $apiKey  = $Matches[1].Trim() }
}
if (-not $baseUrl -or -not $apiKey) { Write-Host "X Could not read the environment values from teamclaude env."; exit 1 }

# 3. Open a new PowerShell window running the TUI server (panel + resident proxy; closing that window stops the proxy)
Write-Host "Opening the teamclaude server window (live quota panel)..."
Start-Process powershell -ArgumentList '-NoExit', '-Command', 'teamclaude server'
Start-Sleep -Seconds 3
if (Get-NetTCPConnection -LocalPort 3456 -State Listen -ErrorAction SilentlyContinue) {
  Write-Host "  Proxy is listening on 127.0.0.1:3456."
} else {
  Write-Host "  ! No proxy detected on 3456 yet. Wait a few seconds, or check the new window for errors."
}

# 4. Set user-level environment variables (persistent; SetEnvironmentVariable is cleaner than setx)
[Environment]::SetEnvironmentVariable('ANTHROPIC_BASE_URL', $baseUrl, 'User')
[Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY',  $apiKey,  'User')

Write-Host ""
Write-Host "OK teamclaude proxy mode is on."
Write-Host "   Set ANTHROPIC_BASE_URL = $baseUrl"
Write-Host "   Set ANTHROPIC_API_KEY  = (teamclaude proxy key)"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  (1) Fully close and reopen VS Code so the extension picks up the proxy."
Write-Host "  (2) The server window that just opened is your live quota panel. Leave it open (closing it stops the proxy)."
Write-Host "  (3) Check: does the extension still answer? Does /usage look sane? Does it rotate when a quota runs out?"
Write-Host "  (4) To go back to a direct connection: run exit-teamclaude.ps1, then restart VS Code."
Write-Host ""
Write-Host "  !! If the extension cannot connect after restarting, run exit-teamclaude.ps1 and restart VS Code to recover."
