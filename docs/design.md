# Design — teamclaude-vscode-windows

Date: 2026-07-26
Status: approved, not yet implemented

## Problem

[teamclaude](https://github.com/KarpelesLab/teamclaude) is a local proxy that rotates
between several Claude accounts as quotas run low. Its documented setup path is
`teamclaude alias --install`, which writes a shell alias — and its own README states
the alias "affects `claude` typed at a prompt, not `claude` spawned by editors or
scripts."

So the documented path does not reach the **VS Code extension**, which spawns its own
`claude.exe`. The upstream README also carries no Windows guidance at all: no
PowerShell, no `.cmd`, and Unix-style paths throughout.

This repo closes that gap: it points the VS Code extension at the teamclaude proxy on
Windows, with one-click scripts.

## Repository

Name: `teamclaude-vscode-windows` — descriptive over clever, so that searching
"teamclaude vscode" or "teamclaude windows" finds it.

It is created in place from the existing working directory, which already holds
the scripts and needs no restructuring. Public, MIT.

Before the scripts are rewritten in English, the working Chinese copies are backed up,
because `exit-teamclaude.ps1` is the author's safety net for getting out of proxy mode
and must not be broken mid-edit.

## Approach

Set `ANTHROPIC_BASE_URL` and `ANTHROPIC_API_KEY` as **User-level** environment
variables. The VS Code extension inherits them when it starts, so its `claude.exe`
sends requests to the local proxy instead of `api.anthropic.com`. Because the
variables are read at process start, entering or leaving the mode requires a full
VS Code restart.

Verified working on 2026-07-26: the extension's `claude.exe` held an established TCP
connection to `127.0.0.1:3456`, and the proxy panel logged matching
`POST /v1/messages` entries.

**Update 2026-08-13:** `ANTHROPIC_API_KEY` is no longer set — only `ANTHROPIC_BASE_URL`
is. teamclaude skips its proxy-key check for localhost clients, so the key was never
needed, and setting it made the extension present teamclaude's proxy key as its own
identity instead of the OAuth login it holds in secure storage. Verified without the
key: inference still works and the extension still routes through the proxy. Rotation
is unaffected either way, since the proxy overwrites the credential on every forwarded
request. The exit script still clears both variables so a key left by an earlier
version gets removed.

**Update 2026-08-13 (later the same day):** the base-URL approach above is now the
*older* of two. Pointing `ANTHROPIC_BASE_URL` away from Anthropic turns out to trip an
SDK gate that disables Remote Control and tool search (see Known limitations). Upstream
does not hit this because its own default is the forward proxy, not base-URL routing —
`index.js` computes `useMitm = !tcFlags.includes('--no-mitm')`, so base-URL routing is
what you get from `--no-mitm`.

So the recommended path is now `launch-teamclaude-vscode.ps1`: set `HTTPS_PROXY` at
teamclaude and `NODE_EXTRA_CA_CERTS` at its locally minted CA, leave `ANTHROPIC_BASE_URL`
unset, and launch VS Code as a child. The base URL stays `https://api.anthropic.com`, so
the gate never fires; teamclaude terminates the `CONNECT` and forwards through the same
request listener as the reverse-proxy path, so rotation is unchanged.

The variables are deliberately set on the **launching process only**, not at User level.
`HTTPS_PROXY` at User level would route every later process on the machine through
teamclaude — fine while it runs, since non-Anthropic hosts are blind-tunnelled, but a
dead proxy would then break `npm`, `git` and `curl` rather than just Claude. That is a
poor thing to hand a stranger in a one-click script. The cost of process scope is that
VS Code opened any other way silently gets a direct connection; that is stated in the
README, and it doubles as the rollback.

## Components

| File | Responsibility |
| --- | --- |
| `enter-teamclaude.ps1` | Check accounts exist, read the base URL from `teamclaude env`, open a separate window running `teamclaude server` (the TUI is the live quota panel), set the User-level `ANTHROPIC_BASE_URL` |
| `launch-teamclaude-vscode.ps1` | The recommended path. Refuse to run while VS Code is up, start the proxy if it is not already listening, mint the CA if missing, then launch Code.exe with `HTTPS_PROXY` / `NODE_EXTRA_CA_CERTS` set on this process and `ANTHROPIC_BASE_URL` removed |
| `exit-teamclaude.ps1` | Remove both variables, stop the process listening on 3456 |
| `*.bat` | One-click wrappers. Locate the `.ps1` via `%~dp0`, run it with `-NoProfile -ExecutionPolicy Bypass`, and `pause` so the restart instruction stays readable |
| `README.md` | Setup, usage, verification, limitations |
| `LICENSE` | MIT, matching upstream |

The scripts are already portable — no hardcoded user paths. Values come from
`teamclaude env` at runtime; the wrappers resolve their own directory.

## Data flow

Recommended (forward proxy, process scope):

```text
launch script ──> HTTPS_PROXY + NODE_EXTRA_CA_CERTS (this process only)
                                              │
                                    (starts Code.exe as a child)
                                              ↓
VS Code extension (claude.exe) ──> CONNECT api.anthropic.com:443
                                              ↓
                                   127.0.0.1:3456 terminates it ──> api.anthropic.com
                                   (same listener; injects the active account's token)
```

Older (base-URL routing, User scope):

```text
enter script ──> teamclaude env ──> ANTHROPIC_BASE_URL (User scope)
                                              │
                                    (VS Code restart)
                                              ↓
VS Code extension (claude.exe) ──> 127.0.0.1:3456 ──> api.anthropic.com
                                    (teamclaude injects the active account's token)
```

## Work required

The scripts exist and run, but are not publishable as-is:

1. **Translate to English.** Every comment and `Write-Host` string is currently
   Chinese. Repo content, README, and commit messages are all English.
2. **Remove `sa` coupling.** Five messages across the two scripts refer to restoring
   "sa manual mode". `sa` ([switch-account](https://github.com/John1106John/switch-account))
   is the author's separate tool and means nothing to an outside user. Reword to
   "restore the direct connection to api.anthropic.com"; mention switch-account only
   under Credits as further reading.

## Error handling

Existing behavior, kept as is:

- No accounts configured → print how to run `teamclaude login`, exit 1.
- `teamclaude env` yields no usable values → print and exit 1.
- Proxy not listening on 3456 after startup → warn and point at the server window.
- On exit, nothing listening on 3456 → report it as already stopped, not an error.
- On exit, the process survives the stop attempt → tell the user to close the server
  window manually.

## Testing

These scripts are almost entirely side effects on global machine state — User-level
environment variables and a background process — so there is no pure core to unit
test, unlike switch-account. Verification is therefore:

- **Syntax check** both scripts with `[Parser]::ParseFile` (catches breakage without
  executing anything).
- **A documented manual verification procedure in the README**, since "the panel is
  open" does not prove the extension is forwarding. Panel entries alone can come from
  another client. The reliable check is which process holds the connection:

  ```powershell
  Get-NetTCPConnection -RemotePort 3456 | ForEach-Object {
    (Get-Process -Id $_.OwningProcess).Path
  }
  ```

  Seeing the VS Code extension's `claude.exe` is the proof.

Note that `exit-teamclaude.ps1` cannot be exercised from inside a Claude conversation
that is itself running through the proxy — stopping the proxy severs that
conversation. It has to be run by hand.

## Known limitations (to state honestly in the README)

- **Automatic rotation on quota exhaustion is teamclaude's feature, and this repo's
  author has not verified it firsthand.** Only the forwarding path is verified. The
  README must not claim otherwise.
  **Update 2026-07-27:** rotation has since been verified firsthand — a quota ran out
  and the account switched with no interruption to the conversation in progress. The
  README now documents this, and this constraint no longer applies.
- **Reboot gotcha.** The environment variables persist across reboots; the proxy does
  not. After a reboot the variables point at a dead port and the extension cannot
  connect. Rerun the enter script, or run the exit script to go back to a direct
  connection.
- **Remote Control is unavailable in proxy mode.** Found 2026-08-13. The extension
  aborts `Remote Control auto-enable` in the same millisecond it reads its OAuth
  tokens, i.e. before any request leaves the machine, so it is a local pre-check
  rather than a relay or credential failure — teamclaude's `/v1/code/*` pass-through
  returns a genuine upstream 401, and removing `ANTHROPIC_API_KEY` changed nothing.
  Most likely the SDK refuses the feature on a non-first-party base URL, the same
  policy the log shows applied to ToolSearch. Inference, not proof: the gate is inside
  the packaged binary. The README states this as a limitation.
  **Update, same day:** confirmed and fixed. Launched through the forward proxy — base
  URL untouched — the log shows `[remote-bridge] Fetched bridge credentials`,
  `[bridge:sdk] State change: connected` and `[ToolSearch:optimistic] ... result=true`,
  with no `auto-enable failed` at all. Both gated features returning together is what
  turns the inference into a diagnosis. The control also held: the extension's
  `claude.exe` kept its connections to `127.0.0.1:3456` and had none direct to
  api.anthropic.com, so this was not Remote Control bought by leaving the proxy. The
  limitation now applies only to the older base-URL mode.
- **Closing the server window stops the proxy.** Intentional and stated, not a bug.
- Entering or leaving the mode requires a full VS Code restart, which ends any
  in-flight conversation.

## Out of scope

- A `verify` script. The verification procedure ships as README documentation instead.
- Auto-starting the proxy at login. That turns teamclaude into a resident default —
  a change of posture rather than a fix, and a poor thing to hand a stranger in a
  one-click script. The README may mention scheduling it as an advanced option.
