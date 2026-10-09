# Gpt Notify

Gpt Notify sends ntfy push notifications to your iPhone and Windows laptop when local Codex stops because it needs required information. The hook is installed at the Windows-user level, so it can run in any local Codex project.

## What sends a notification

- **Required information:** Codex's `Stop` event sends a notification when its final message clearly says it needs your answer to continue. Successful completions and ordinary follow-up offers stay quiet. Detection uses text patterns, so vague requests may be missed.
- **Approvals:** Approval notifications are disabled. Codex may still show its normal approval prompt, but Gpt Notify will not send an approval push, including when automatic approval is enabled.

These are local Codex hooks. They do not run in ordinary ChatGPT chats or remote/cloud Codex sessions. The computer must be awake and connected when the hook runs; the phone must have internet access and ntfy notifications enabled.

## Requirements

- Windows with Codex installed.
- Node.js 18 or newer and npm.
- Python 3 and the Windows Python launcher (`py -3`). No third-party Python packages are needed.
- The ntfy app on iPhone. For laptop alerts, use ntfy Web in a browser that allows notifications.

## Install and configure

Install the published npm package from any PowerShell window:

```sh
npm install --global codex-gpt-notify
codex-gpt-notify setup
```

`setup` creates a random ntfy topic if one does not already exist, copies the handler to a stable location, and registers one global `Stop` hook. It removes Gpt Notify's old approval hook and preserves unrelated hooks already in your Codex hooks file. You can run setup again after moving to a new computer or cloning the source; it reuses the existing topic on that Windows account.

To try the package before its first npm release, clone this repository, open PowerShell in the repository root, and run:

```powershell
npm install --global .
codex-gpt-notify setup
```

It installs these files outside the repository:

- `%APPDATA%\GptNotify\config.json` — ntfy server and private topic.
- `%APPDATA%\GptNotify\notify.py` — installed notification handler.
- `%USERPROFILE%\.codex\hooks.json` — the global `Stop` registration.

The hooks file is written as UTF-8 without a byte-order mark so Codex can parse it. The private topic is a secret: anyone who knows it can publish to and subscribe to your topic. Don’t put it in this repository or commit it to GitHub.

### Subscribe your devices

1. On iPhone, install and open **ntfy** from the App Store. Subscribe to the topic printed by setup and allow iOS notifications.
2. On Windows, open [ntfy Web](https://ntfy.sh/app), subscribe to the same topic, and allow browser notifications. You can install the web app from your browser if you want it to behave more like a desktop app.

If setup says a topic is already configured, it keeps using that topic. To see it again, open `%APPDATA%\GptNotify\config.json` locally; **don’t paste or publish its contents**.

## Enable and trust the hooks

After setup, restart the Codex CLI so it reloads the global hooks. If you are currently in the CLI, press **Esc** to close `/hooks`, type `/exit`, and press **Enter**. Then start a fresh CLI session.

If PowerShell says `codex` is not recognized, launch the executable directly. The version-specific folder can change after updates; list the available paths with:

```powershell
Get-ChildItem "$env:LOCALAPPDATA\OpenAI\Codex\bin" -Filter codex.exe -Recurse |
    Select-Object -ExpandProperty FullName
```

Run the path it prints, for example:

```powershell
& "C:\path\shown\above\codex.exe"
```

At the Codex prompt, type `/hooks`. Find `Stop`, select it, and press **Enter** to review its handler. Use the trust option shown by Codex. `Stop` should show **Installed 1** and, after trust, **Active 1**. You only need to trust the hook once per unchanged definition.

The registrations are global to this Windows Codex account; you do not need to install or select the Gpt Notify plugin in every project.

## Add this to ChatGPT/Codex custom instructions

This instruction encourages Codex to phrase a genuine information blocker in a way the stop hook can recognize. Paste it into your Custom Instructions or project instructions:

```text
When you genuinely cannot continue because you need information from me, stop and write this exact sentence first:

“I need your input before I can continue.”

Then ask one clear question about the specific information you need, and wait for my answer. Don’t guess or continue the blocked task.

Use this only when my answer is required. Don’t use it for optional preferences, successful task completions, or routine follow-up offers.

When an action needs Codex’s permission, make the tool request normally and let Codex show its approval prompt. Don’t replace the approval prompt with a text question. Gpt Notify does not send approval notifications.
```

This helps the stop-message filter recognize required information. These instructions only affect local Codex notifications when used with this hook setup.

## Test it

### Test ntfy delivery directly

After installation and setup, the CLI can send a test notification and report whether ntfy accepted it:

```sh
codex-gpt-notify test
```

Alternatively, this PowerShell test bypasses the npm CLI and sends a test to the configured topic. It prints the HTTP status without printing the private topic:

```powershell
$config = Get-Content "$env:APPDATA\GptNotify\config.json" -Raw | ConvertFrom-Json
try {
    $response = Invoke-WebRequest `
        -Uri "$($config.server.TrimEnd('/'))/$($config.topic)" `
        -Method Post `
        -Body "Manual Gpt Notify test from PowerShell" `
        -ContentType "text/plain; charset=utf-8" `
        -Headers @{ Title = "Gpt Notify test" }
    "ntfy accepted the message: HTTP $($response.StatusCode)"
} catch {
    "Send failed: $($_.Exception.Message)"
}
```

An HTTP success and an iPhone alert confirm ntfy delivery. They do not by themselves confirm that Codex hooks are active.

### Test the Codex events

Start a fresh local Codex session in any project after the hooks are trusted.

1. **Required information:** prompt Codex: `For a notification test, tell me: “I need your input before I can continue. Which color should I choose, red or blue?” Then stop and wait.` You should receive a notification with the question.
2. **Successful completion:** prompt Codex: `Reply only with “Test complete.”` You should not receive a notification.
3. **Approval behavior:** trigger or wait for an approval prompt. Codex may display it, but Gpt Notify should send no notification for it.

## Troubleshooting

- **`/hooks` reports a JSON parse error at line 1, column 1:** rerun setup. It writes the global hooks file as UTF-8 without a byte-order mark.
- **`Stop` shows `Installed 0`:** check that `%USERPROFILE%\.codex\hooks.json` exists, rerun setup, fully exit the CLI, and launch a fresh session.
- **An event shows `Installed 1, Active 0`:** open its details in `/hooks` and complete the trust/review step.
- **The direct ntfy test works but Codex does not notify:** verify the `Stop` hook is active, then test from a fresh local Codex session. The input notification only sends for clear, required-information requests; normal completion stays silent.
- **The direct ntfy test fails:** confirm `%APPDATA%\GptNotify\config.json` exists, the phone is subscribed to that exact topic, and the phone has internet and notification permission. Keep the topic private when asking for help.

## GitHub

The repository contains the handler, installer, and these setup instructions. Never commit a private ntfy topic or personal config file. The topic and installed handler live under `%APPDATA%`, outside this repository. After cloning on another Windows account or computer, run the setup script there and subscribe its devices to the newly printed topic.
