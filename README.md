# teamclaude-vscode-windows

Route the **VS Code Claude extension** through a [teamclaude](https://github.com/KarpelesLab/teamclaude) proxy on **Windows**, with one-click scripts.

## What and why

teamclaude is a local proxy that holds several Claude accounts and rotates between them as quotas run low. Its documented setup path is `teamclaude alias --install`, which writes a shell alias — and upstream states that the alias "affects `claude` typed at a prompt, not `claude` spawned by editors or scripts." The VS Code extension spawns its own `claude.exe`, so the documented path never reaches it. Upstream also carries no Windows guidance: no PowerShell, no `.cmd`, Unix-style paths throughout.

This repo closes both gaps, and offers two ways to point the extension at the proxy.

**Recommended — `launch-teamclaude-vscode.bat`.** It starts VS Code with `HTTPS_PROXY` pointing at teamclaude and `NODE_EXTRA_CA_CERTS` pointing at teamclaude's locally minted CA, so the extension still addresses `https://api.anthropic.com` and teamclaude intercepts the `CONNECT`. That is the same forward-proxy mode upstream's own `teamclaude run` uses **by default**. The variables are set on the launching process only and inherited by the VS Code it starts, so nothing machine-wide is touched.

**Older — `enter-teamclaude.bat` / `exit-teamclaude.bat`.** These set `ANTHROPIC_BASE_URL` to `http://localhost:3456` as a user-level variable, which any VS Code picks up at startup. Upstream has since made the forward proxy the default everywhere, so the enter script asks for this mode explicitly with `teamclaude env --no-mitm`. It forwards correctly, but pointing the base URL away from Anthropic makes the SDK switch off the features it gates on a first-party host — Remote Control and tool search both stop working. See [Remote Control](#remote-control) below.

Neither mode sets `ANTHROPIC_API_KEY`, and that is deliberate. teamclaude skips its proxy-key check for localhost clients, so the key is not needed — and setting it makes the extension present teamclaude's proxy key as its own identity instead of the OAuth login it already holds in secure storage. Rotation is unaffected either way, because the proxy overwrites the credential on every request it forwards.

## Prerequisites

- Windows, with VS Code and the Claude Code extension
- Node.js 20 or newer
- `npm i -g @karpeleslab/teamclaude`
- `teamclaude login` for at least one account — two or more if you want rotation to mean anything

## Usage

| Action | Double-click |
| --- | --- |
| Start VS Code in proxy mode (recommended) | `launch-teamclaude-vscode.bat` |
| Turn on the older base-URL mode | `enter-teamclaude.bat` |
| Stop the proxy, and clear the older mode | `exit-teamclaude.bat` |
| Warm every idle account once | `warm-teamclaude.bat` |

Things to know before you run any of them:

- **Close VS Code completely first.** Environment is read once at process start, so a running instance keeps the one it was started with — launching it again only signals it to open a window. Both modes therefore end any conversation in flight.
- **VS Code opened any other way does not use the proxy.** With the launcher, only the VS Code it starts is routed; the taskbar, the Start menu, and session restore all give you a plain environment. That is the price of not touching machine-wide state, and it is also the rollback: close VS Code, open it normally.
- **The server window that opens *is* the proxy.** It doubles as the live quota panel. Leave it open — closing it stops the proxy.

If the extension cannot connect, close VS Code and open it the normal way. If you had used `enter-teamclaude.bat`, run `exit-teamclaude.bat` first, since that mode does persist.

Running `enter-teamclaude.bat` when a proxy is **already** running is harmless. The second server finds port 3456 taken, prints `Port 3456 is already in use`, and exits without touching the one that is serving your traffic. Two cosmetic consequences: that failed window stays open (it is launched with `-NoExit`), and the enter script's own port check then sees the *old* server still listening and reports success. Close the stray window; nothing else needs doing.

## How to verify it is actually forwarding

An open panel does **not** prove your extension is using the proxy — entries in that panel can come from any client on the machine. The reliable check is which process holds the connection:

```powershell
Get-NetTCPConnection -RemotePort 3456 | ForEach-Object {
  (Get-Process -Id $_.OwningProcess).Path
}
```

Seeing the VS Code extension's `claude.exe` in that output is the proof.

Some remaining connections to `api.anthropic.com` are normal and do not mean the proxy is being bypassed: the proxy itself forwards upstream, and the extension sends telemetry that does not go through the proxy.

## Rotation on quota exhaustion

Verified on 2026-07-27: when the active account ran out of quota, teamclaude switched to another account **without interrupting the conversation in progress**. No error surfaced in the extension, no restart was needed, and the answer kept streaming — the switch was only visible as a change of active account in the server panel.

This is the whole point of routing through the proxy rather than swapping credentials by hand: the token is chosen per request, so nothing the extension holds open has to be torn down.

That run was under the older base-URL mode. The forward proxy hands each request to the *same* code inside teamclaude — it terminates the `CONNECT` and forwards through the same request listener, so per-request account selection and the retry on a quota `429` are the same code path — and a request sent through it with no client credentials at all comes back `200`, which shows the token is being injected. A live rotation has not yet been observed under the forward proxy specifically.

## Remote Control

Remote Control works in the recommended forward-proxy mode. It does **not** work in the older base-URL mode, and that is the main reason to prefer the launcher.

Started with `enter-teamclaude.bat`, the extension log stamps `OAuth tokens found in secure storage` and `Remote Control auto-enable failed` in the **same millisecond** — the feature gives up before any request leaves the machine, so it is a local pre-check rather than a forwarding or credential failure. teamclaude's relay is fine either way: it has a dedicated pass-through for `/v1/code/*` that forwards the client's own credential untouched, and a request to that path through the proxy returns a genuine Anthropic 401 with a `request_id` rather than a proxy error. Removing `ANTHROPIC_API_KEY` so the extension kept its own OAuth identity was tried too, and changed nothing.

The cause is that the SDK switches such features off when the base URL is not a first-party Anthropic host. The same log applies that policy to tool search, and says so out loud:

```text
[ToolSearch:optimistic] disabled: ANTHROPIC_BASE_URL=http://localhost:3456
is not a first-party Anthropic host.
```

The forward proxy never trips that check, because the base URL is never changed: the extension addresses `api.anthropic.com` and teamclaude intercepts the `CONNECT`. Launched that way, the same log reads:

```text
[remote-bridge] Fetched bridge credentials (expires_in=28800s)
[bridge:sdk] State change: connected
[ToolSearch:optimistic] mode=tst, ENABLE_TOOL_SEARCH=undefined, result=true
```

Both features return at once — which is also what identifies the gate. And the routing is genuinely still in place: the extension's `claude.exe` holds its connections to `127.0.0.1:3456`, with none going direct to `api.anthropic.com`. Remote Control is not being bought here by bypassing the proxy.

## After a reboot

**With the launcher, nothing to do.** It leaves no state behind, and it starts the proxy itself whenever nothing is listening on 3456 — so the first `launch-teamclaude-vscode.bat` after a reboot behaves like any other run.

That also means there is no reason to add a startup entry for the proxy. One would only leave a proxy running on the days you never open Claude, and if you point it at `enter-teamclaude.bat` it will re-apply that mode's user-level variables at every login, quietly putting a normally-opened VS Code back into base-URL mode.

**With `enter-teamclaude.bat`, there is a gotcha.** Its environment variables persist across reboots; the proxy does not. After a reboot the variables point at a dead port and the extension cannot connect. Rerun `enter-teamclaude.bat` to start the proxy again, or run `exit-teamclaude.bat` to go back to a direct connection.

## Limitations

- Starting VS Code in proxy mode means starting it fresh, which ends any in-flight conversation. This applies only to getting into the mode — once you are in it, account rotation itself needs no restart.
- With the launcher, only the VS Code it starts is routed. Opening VS Code from the taskbar, the Start menu, or session restore silently gives you a direct connection instead.
- Within that VS Code, *everything* inherits the proxy, not only the Claude extension — VS Code's own networking and any other extension that makes requests. teamclaude blind-tunnels every host that is not Anthropic's, so they keep working and their credentials are never touched, but their traffic does pass through the tunnel and stops if you close the server window.
- Remote Control and tool search do not work under `enter-teamclaude.bat` (see above). Use the launcher.
- Closing the server window stops the proxy. That is intentional, not a bug.
- Windows only. On macOS and Linux, use upstream's alias.
- On Node 24, short-lived `teamclaude` subcommands (e.g. `accounts`, once a profile fetch succeeds) print a libuv assertion to stderr as they exit; their output is still valid and the resident server is unaffected. The scripts run those commands through `cmd /c ... 2>&1` so that, under `$ErrorActionPreference = 'Stop'`, PowerShell 5.1 does not turn the assertion into a terminating error and abort the launch before anything happens.

## Credits

- [teamclaude](https://github.com/KarpelesLab/teamclaude) by KarpelesLab (MIT) — this repo is only a Windows entry point for it.
- [switch-account](https://github.com/John1106John/switch-account) — further reading if you want manual account switching instead of a proxy.

## License

MIT. See [LICENSE](LICENSE).
