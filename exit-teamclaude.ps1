<#
  exit-teamclaude.ps1 - leave teamclaude proxy mode
  1. Clears the teamclaude environment variables (Claude Code goes back to its own credentials)
  2. Stops the proxy server (port 3456)
  Fully restart VS Code afterwards to restore the direct connection to api.anthropic.com.
#>
$ErrorActionPreference = 'Stop'

# 1. Remove the user-level environment variables ($null actually removes them, rather than setting an empty string)
[Environment]::SetEnvironmentVariable('ANTHROPIC_BASE_URL', $null, 'User')
[Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY',  $null, 'User')
# Clear them in the current shell too
Remove-Item Env:\ANTHROPIC_BASE_URL -ErrorAction SilentlyContinue
Remove-Item Env:\ANTHROPIC_API_KEY  -ErrorAction SilentlyContinue
Write-Host "Cleared ANTHROPIC_BASE_URL / ANTHROPIC_API_KEY."

# 2. Stop the proxy server if it is still running
$conn = Get-NetTCPConnection -LocalPort 3456 -State Listen -ErrorAction SilentlyContinue
if ($conn) {
  Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 1
  if (Get-NetTCPConnection -LocalPort 3456 -State Listen -ErrorAction SilentlyContinue) {
    Write-Host "! Port 3456 is still listening. Close the server window manually."
  } else {
    Write-Host "Stopped the teamclaude server (port 3456)."
  }
} else {
  Write-Host "No server running on port 3456 (already stopped)."
}

Write-Host ""
Write-Host "OK Proxy mode is off."
Write-Host "   Fully close and reopen VS Code; the extension goes back to connecting directly to api.anthropic.com."
