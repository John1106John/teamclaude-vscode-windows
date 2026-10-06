<#
  launch-teamclaude-vscode.ps1 - start VS Code with teamclaude in forward-proxy (MITM) mode

  This is the recommended way to use this repo. Unlike enter-teamclaude.ps1, it does
  NOT change any machine-wide state: the proxy settings are set on THIS process and
  inherited only by the VS Code it launches. Rolling back means closing VS Code and
  opening it the normal way.

  Why the forward proxy rather than ANTHROPIC_BASE_URL: the extension keeps talking to
  https://api.anthropic.com and teamclaude intercepts the CONNECT, so the base URL stays
  a first-party Anthropic host. Features the SDK gates on that (Remote Control, tool
  search) keep working, which they do not under base-URL routing. See the README.
#>
$ErrorActionPreference = 'Stop'
$env:TEAMCLAUDE_DISABLE_AUTOUPDATE = '1'

$port     = 3456
$proxyUrl = "http://127.0.0.1:$port"
$caPath   = Join-Path $env:USERPROFILE '.config\teamclaude-ca.pem'

function Test-ProxyUp { [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) }

# 1. VS Code must be fully closed. A running instance would only be signalled to open a
#    window, and would keep the environment it was originally started with.
if (Get-Process Code -ErrorAction SilentlyContinue) {
  Write-Host "X VS Code is still running. Close it completely, then run this again."
  Write-Host "  (Launching it again would just signal the running instance, which keeps its old environment.)"
  exit 1
}

$codeExe = @(
  (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'),
  (Join-Path $env:ProgramFiles 'Microsoft VS Code\Code.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $codeExe) { Write-Host "X Could not find Code.exe. Edit this script and set the path by hand."; exit 1 }

# 2. Confirm teamclaude has accounts. On Node 24 this command prints a libuv assertion
#    to stderr as it exits even though its output is valid. With $ErrorActionPreference =
#    'Stop', PowerShell 5.1 turns that stderr line into a terminating error, so let cmd
#    merge the streams first and hand PowerShell plain strings.
$accounts = cmd /c "teamclaude accounts 2>&1"
if ($accounts -match 'No accounts configured') {
  Write-Host "X No teamclaude accounts. Run: teamclaude login (at least one, preferably two)."
  exit 1
}
Write-Host "Accounts detected:"
$accounts | Where-Object { $_ -match '^\s*\[' } | ForEach-Object { Write-Host "  $_" }

# 3. Start the proxy if it is not already up. That window is the live quota panel;
#    closing it stops the proxy.
if (Test-ProxyUp) {
  Write-Host "Proxy already listening on 127.0.0.1:$port - reusing it."
} else {
  Write-Host "Opening the teamclaude server window (live quota panel)..."
  # The panel's activity rows live only in memory, so a rotation, a 429 or an
  # event-loop stall is unreadable once it scrolls away - exactly when you want
  # to know why a switch did or did not happen. --activity-log appends those
  # same lines to a file, one per day so a given night stays easy to find.
  $logDir = Join-Path $env:LOCALAPPDATA 'teamclaude'
  if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
  $activityLog = Join-Path $logDir ('activity-' + (Get-Date -Format 'yyyyMMdd') + '.log')
  Start-Process powershell -ArgumentList '-NoExit', '-Command', "teamclaude server --activity-log `"$activityLog`""
  Start-Sleep -Seconds 3
  if (-not (Test-ProxyUp)) {
    Write-Host "X No proxy on $port. Check the new window for errors, then run this again."
    exit 1
  }
  Write-Host "  Proxy is listening on 127.0.0.1:$port."
  Write-Host "  Activity log: $activityLog"
}

# 4. The MITM certificate authority. teamclaude mints it lazily on the first intercepted
#    CONNECT, so on a fresh install it does not exist yet. Send one CONNECT to its
#    built-in test host to force it: the TLS handshake afterwards is expected to fail
#    (we do not trust the CA yet, which is the whole point) and its result is ignored -
#    the side effect on disk is all we are after.
if (-not (Test-Path $caPath)) {
  Write-Host "Minting the teamclaude CA certificate..."
  curl.exe -s --connect-timeout 5 --proxy $proxyUrl https://www.example.org/ *> $null
  Start-Sleep -Milliseconds 500
}
if (-not (Test-Path $caPath)) {
  Write-Host "X teamclaude did not create $caPath. Run 'teamclaude run -- --version' once, then try again."
  exit 1
}

# 5. Forward-proxy environment, matching what upstream's `teamclaude run` sets.
#    ANTHROPIC_BASE_URL must NOT be set - the point is that traffic still addresses
#    api.anthropic.com. Remove it in case enter-teamclaude.ps1 left one behind.
if ([Environment]::GetEnvironmentVariable('ANTHROPIC_BASE_URL', 'User')) {
  Write-Host ""
  Write-Host "  ! ANTHROPIC_BASE_URL is set machine-wide, so a normally-opened VS Code would"
  Write-Host "    still use the older base-URL mode. Run exit-teamclaude.bat once to clear it."
}
Remove-Item Env:\ANTHROPIC_BASE_URL -ErrorAction SilentlyContinue
Remove-Item Env:\ANTHROPIC_API_KEY  -ErrorAction SilentlyContinue
$env:HTTPS_PROXY = $proxyUrl
$env:HTTP_PROXY  = $proxyUrl
$env:https_proxy = $proxyUrl
$env:http_proxy  = $proxyUrl
# 169.254.169.254 is the cloud instance-metadata endpoint. A credential chain in
# some tool the launched VS Code starts probes it to decide whether it is running
# on a cloud VM; with the proxy set process-wide that probe arrives at teamclaude,
# which refuses every link-local target (its SSRF policy) and logs a line each time.
# Excluding it lets the probe fail locally and fast, exactly as it does with no proxy.
$noProxy = 'localhost,127.0.0.1,::1,169.254.169.254,metadata.google.internal'
$env:NO_PROXY    = $noProxy
$env:no_proxy    = $noProxy
$env:NODE_EXTRA_CA_CERTS = $caPath

Write-Host ""
Write-Host "Launching VS Code through the teamclaude forward proxy:"
Write-Host "   HTTPS_PROXY         = $proxyUrl"
Write-Host "   NODE_EXTRA_CA_CERTS = $caPath"
Write-Host "   ANTHROPIC_BASE_URL  = (unset on purpose; traffic still addresses api.anthropic.com)"

Start-Process $codeExe

Write-Host ""
Write-Host "OK VS Code is starting."
Write-Host "   Only this VS Code routes through the proxy. Nothing else on the machine is affected,"
Write-Host "   and nothing persistent was changed."
Write-Host ""
Write-Host "Notes:"
Write-Host "  (1) Verify with: Get-NetTCPConnection -RemotePort $port | ForEach-Object { (Get-Process -Id `$_.OwningProcess).Path }"
Write-Host "  (2) The server window is your live quota panel. Leave it open (closing it stops the proxy)."
Write-Host "  (3) To stop using the proxy, close VS Code and open it the normal way."
Write-Host "  (4) VS Code opened any other way (taskbar, Start menu, session restore) does NOT use the proxy."
