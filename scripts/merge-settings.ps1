# ClaudeThrottle settings.json merge tool
# Usage: powershell.exe -File merge-settings.ps1 install|uninstall
param([string]$Action)

$SettingsFile = Join-Path $env:USERPROFILE ".claude\settings.json"

function Load-Settings {
    if (Test-Path $SettingsFile) {
        $content = Get-Content $SettingsFile -Raw -Encoding UTF8
        return $content | ConvertFrom-Json
    }
    return [PSCustomObject]@{}
}

function Save-Settings($settings) {
    $json = $settings | ConvertTo-Json -Depth 20
    # UTF-8 without BOM
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($SettingsFile, ($json + "`n"), $utf8NoBom)
}

function Has-ThrottleHook($entry) {
    foreach ($h in $entry.hooks) {
        if ($h.command -like "*throttle*") { return $true }
    }
    return $false
}

function Do-Install {
    $settings = Load-Settings

    if (-not $settings.PSObject.Properties["hooks"]) {
        $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([PSCustomObject]@{})
    }

    $hooksToAdd = @{
        "PreToolUse" = [PSCustomObject]@{
            matcher = "Agent"
            hooks = @([PSCustomObject]@{
                type    = "command"
                command = "bash ~/.claude/throttle/hooks/pre-tool-use.sh"
            })
        }
        "Stop" = [PSCustomObject]@{
            matcher = ""
            hooks = @([PSCustomObject]@{
                type    = "command"
                command = "bash ~/.claude/throttle/hooks/stop.sh"
            })
        }
    }

    $changed = $false
    foreach ($event in $hooksToAdd.Keys) {
        if (-not $settings.hooks.PSObject.Properties[$event]) {
            $settings.hooks | Add-Member -NotePropertyName $event -NotePropertyValue @()
        }
        $existing = $settings.hooks.$event
        $alreadyInstalled = $false
        foreach ($e in $existing) {
            if (Has-ThrottleHook $e) { $alreadyInstalled = $true; break }
        }
        if (-not $alreadyInstalled) {
            $settings.hooks.$event = @($existing) + @($hooksToAdd[$event])
            Write-Host "  Added $event hook"
            $changed = $true
        } else {
            Write-Host "  $event hook already exists, skipped"
        }
    }

    if ($changed) {
        Save-Settings $settings
        Write-Host "settings.json updated"
    } else {
        Write-Host "settings.json unchanged"
    }
}

function Do-Uninstall {
    if (-not (Test-Path $SettingsFile)) {
        Write-Host "settings.json not found, skipped"
        return
    }
    $settings = Load-Settings
    if (-not $settings.PSObject.Properties["hooks"]) {
        Write-Host "No hooks config, skipped"
        return
    }

    $changed = $false
    $events = @($settings.hooks.PSObject.Properties.Name)
    foreach ($event in $events) {
        $before = @($settings.hooks.$event).Count
        $settings.hooks.$event = @($settings.hooks.$event | Where-Object { -not (Has-ThrottleHook $_) })
        $after = @($settings.hooks.$event).Count
        if ($before -ne $after) {
            Write-Host "  Removed $event throttle hook"
            $changed = $true
        }
        if (@($settings.hooks.$event).Count -eq 0) {
            $settings.hooks.PSObject.Properties.Remove($event)
        }
    }

    if ($changed) {
        Save-Settings $settings
        Write-Host "settings.json updated"
    } else {
        Write-Host "No throttle hooks found, unchanged"
    }
}

switch ($Action) {
    "install"   { Do-Install }
    "uninstall" { Do-Uninstall }
    default {
        Write-Host "Usage: powershell.exe -File merge-settings.ps1 install|uninstall"
        exit 1
    }
}
