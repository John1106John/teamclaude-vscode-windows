# teamclaude-vscode-windows

Route the **VS Code Claude extension** through a [teamclaude](https://github.com/KarpelesLab/teamclaude) proxy on **Windows**, with one-click scripts.

## What and why

teamclaude is a local proxy that holds several Claude accounts and rotates between them as quotas run low. Its documented setup path is `teamclaude alias --install`, which writes a shell alias — and upstream states that the alias "affects `claude` typed at a prompt, not `claude` spawned by editors or scripts." The VS Code extension spawns its own `claude.exe`, so the documented path never reaches it. Upstream also carries no Windows guidance: no PowerShell, no `.cmd`, Unix-style paths throughout.

This repo closes both gaps. Instead of an alias, it sets `ANTHROPIC_BASE_URL` and `ANTHROPIC_API_KEY` as **user-level environment variables**, which the VS Code extension inherits at startup. Two scripts turn that on and off.

## Prerequisites

- Windows, with VS Code and the Claude Code extension
- Node.js 20 or newer
- `npm i -g @karpeleslab/teamclaude`
- `teamclaude login` for at least one account — two or more if you want rotation to mean anything

## Usage

| Action | Double-click |
| --- | --- |
| Turn proxy mode on | `enter-teamclaude.bat` |
| Turn proxy mode off | `exit-teamclaude.bat` |

Two things to know before you run either one:

- **Both directions require fully closing and reopening VS Code.** The environment variables are read once at process start, so a running extension will not pick up the change. This also ends any conversation that is in flight.
- **The server window that opens *is* the proxy.** It doubles as the live quota panel. Leave it open — closing it stops the proxy.

If the extension cannot connect after you restart, run `exit-teamclaude.bat` and restart VS Code again to get back to a direct connection.

## How to verify it is actually forwarding

An open panel does **not** prove your extension is using the proxy — entries in that panel can come from any client on the machine. The reliable check is which process holds the connection:

```powershell
Get-NetTCPConnection -RemotePort 3456 | ForEach-Object {
  (Get-Process -Id $_.OwningProcess).Path
}
```

Seeing the VS Code extension's `claude.exe` in that output is the proof.

Some remaining connections to `api.anthropic.com` are normal and do not mean the proxy is being bypassed: the proxy itself forwards upstream, and the extension sends telemetry that does not go through the proxy.

## Reboot gotcha

The environment variables persist across reboots. The proxy does not. After a reboot the variables point at a dead port and the extension cannot connect. Rerun `enter-teamclaude.bat` to start the proxy again, or run `exit-teamclaude.bat` to go back to a direct connection.

## Limitations

- **Automatic rotation on quota exhaustion is teamclaude's feature, and it has not been verified firsthand by this repo's author.** Only the forwarding path has been verified: the extension's `claude.exe` was observed holding an established connection to `127.0.0.1:3456`, with matching `POST /v1/messages` entries in the panel. Treat the rotation behavior as upstream's claim, not this repo's.
- Entering or leaving the mode requires a full VS Code restart, which ends any in-flight conversation.
- Closing the server window stops the proxy. That is intentional, not a bug.
- Windows only. On macOS and Linux, use upstream's alias.
- On very recent Node versions, short-lived `teamclaude` subcommands can print a libuv assertion as they exit. The enter script tolerates this — its output is still valid — and the resident server is unaffected.

## Credits

- [teamclaude](https://github.com/KarpelesLab/teamclaude) by KarpelesLab (MIT) — this repo is only a Windows entry point for it.
- [switch-account](https://github.com/John1106John/switch-account) — further reading if you want manual account switching instead of a proxy.

## License

MIT. See [LICENSE](LICENSE).
