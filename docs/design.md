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

## Components

| File | Responsibility |
| --- | --- |
| `enter-teamclaude.ps1` | Check accounts exist, read values from `teamclaude env`, open a separate window running `teamclaude server` (the TUI is the live quota panel), set both User-level variables |
| `exit-teamclaude.ps1` | Remove both variables, stop the process listening on 3456 |
| `enter-teamclaude.bat` / `exit-teamclaude.bat` | One-click wrappers. Locate the `.ps1` via `%~dp0`, run it with `-NoProfile -ExecutionPolicy Bypass`, and `pause` so the restart instruction stays readable |
| `README.md` | Setup, usage, verification, limitations |
| `LICENSE` | MIT, matching upstream |

The scripts are already portable — no hardcoded user paths. Values come from
`teamclaude env` at runtime; the wrappers resolve their own directory.

## Data flow

```text
enter script ──> teamclaude env ──> ANTHROPIC_BASE_URL / ANTHROPIC_API_KEY (User scope)
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
- **Reboot gotcha.** The environment variables persist across reboots; the proxy does
  not. After a reboot the variables point at a dead port and the extension cannot
  connect. Rerun the enter script, or run the exit script to go back to a direct
  connection.
- **Closing the server window stops the proxy.** Intentional and stated, not a bug.
- Entering or leaving the mode requires a full VS Code restart, which ends any
  in-flight conversation.

## Out of scope

- A `verify` script. The verification procedure ships as README documentation instead.
- Auto-starting the proxy at login. That turns teamclaude into a resident default —
  a change of posture rather than a fix, and a poor thing to hand a stranger in a
  one-click script. The README may mention scheduling it as an advanced option.
