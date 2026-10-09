$ErrorActionPreference = 'Stop'

$configDirectory = Join-Path $env:APPDATA 'GptNotify'
$configPath = Join-Path $configDirectory 'config.json'
New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null

$hasTopic = $false
if (Test-Path -LiteralPath $configPath) {
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if ($config.topic) {
        $topic = $config.topic
        $server = if ($config.server) { $config.server } else { 'https://ntfy.sh' }
        $hasTopic = $true
    }
}

if (-not $hasTopic) {
    $bytes = New-Object byte[] 24
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $topic = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $rng.Dispose()

    $server = 'https://ntfy.sh'
    $config = [ordered]@{
        server = $server
        topic = $topic
    }
    $config | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8
}

# Install a stable copy so hooks work in every Codex project, not only this repo.
$sourceScript = Join-Path $PSScriptRoot '..\plugins\gpt-notify\hooks\notify.py'
$sourceScript = [System.IO.Path]::GetFullPath($sourceScript)
if (-not (Test-Path -LiteralPath $sourceScript)) {
    throw "Notification handler not found: $sourceScript"
}
$installedScript = Join-Path $configDirectory 'notify.py'
Copy-Item -LiteralPath $sourceScript -Destination $installedScript -Force

# Merge the input-needed handler into the user's global hooks file while preserving
# unrelated hooks and other top-level configuration.
$codexDirectory = Join-Path $env:USERPROFILE '.codex'
$hooksPath = Join-Path $codexDirectory 'hooks.json'
New-Item -ItemType Directory -Path $codexDirectory -Force | Out-Null
if (Test-Path -LiteralPath $hooksPath) {
    $hooksJson = (Get-Content -LiteralPath $hooksPath -Raw).TrimStart([char]0xFEFF)
    $hooksConfig = $hooksJson | ConvertFrom-Json
} else {
    $hooksConfig = [pscustomobject]@{ hooks = [pscustomobject]@{} }
}
if (-not $hooksConfig.PSObject.Properties['hooks']) {
    $hooksConfig | Add-Member -MemberType NoteProperty -Name hooks -Value ([pscustomobject]@{})
}
if (-not $hooksConfig.hooks) {
    $hooksConfig.hooks = [pscustomobject]@{}
}

$notifyCommand = 'py -3 "' + $installedScript + '"'
$notifyHandler = [pscustomobject]@{
    type = 'command'
    command = $notifyCommand
    commandWindows = $notifyCommand
    timeout = 3
    async = $true
}

foreach ($eventName in @('Stop', 'PermissionRequest')) {
    $existingEvent = $hooksConfig.hooks.PSObject.Properties[$eventName]
    $groups = @()
    if ($existingEvent) {
        foreach ($group in @($existingEvent.Value)) {
            $remainingHandlers = @(
                foreach ($handler in @($group.hooks)) {
                    $handlerCommand = [string]$handler.command
                    $handlerCommandWindows = [string]$handler.commandWindows
                    $isGptNotifyHandler = (
                        $handlerCommand -like '*GptNotify*notify.py*' -or
                        $handlerCommandWindows -like '*GptNotify*notify.py*'
                    )
                    if (-not $isGptNotifyHandler) {
                        $handler
                    }
                }
            )
            if ($remainingHandlers.Count -gt 0) {
                $group.hooks = $remainingHandlers
                $groups += $group
            }
        }
    }
    if ($eventName -eq 'Stop') {
        $groups += [pscustomobject]@{ hooks = @($notifyHandler) }
    }

    if ($groups.Count -gt 0) {
        $hooksConfig.hooks | Add-Member -MemberType NoteProperty -Name $eventName -Value $groups -Force
    } else {
        $hooksConfig.hooks.PSObject.Properties.Remove($eventName)
    }
}

$hooksJson = $hooksConfig | ConvertTo-Json -Depth 30
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($hooksPath, $hooksJson, $utf8WithoutBom)

Write-Host ''
Write-Host 'Gpt Notify is configured for required-information stops across Codex projects on this Windows account.'
Write-Host "Private topic: $topic"
Write-Host "Config file: $configPath"
Write-Host "Global hooks: $hooksPath"
Write-Host "Installed handler: $installedScript"
Write-Host ''
Write-Host 'Subscribe to this topic in the ntfy app on your iPhone.'
Write-Host 'For laptop notifications, subscribe to the same topic at https://ntfy.sh/app and enable browser notifications.'
Write-Host 'Restart Codex, then review and trust the Stop hook in /hooks. Approval notifications are disabled.'
