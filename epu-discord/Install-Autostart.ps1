<#
  Starts the EPU Discord bot when you log in to Windows, in a minimized window.

  Run once from this folder in PowerShell (no administrator needed):

    powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-Autostart.ps1

  It adds a Task Scheduler task "EPU Discord bot" for your Windows user that
  runs start.bat at logon, then starts it now. start.bat keeps the bot running:
  it restarts it after a crash and after the bot updates itself to a new release.

    Install-Autostart.ps1 -NoStart   add the task without starting the bot now
    Install-Autostart.ps1 -Remove    stop starting the bot at logon
#>
param(
  [switch]$NoStart,
  [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$TaskName = 'EPU Discord bot'
$Here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$StartBat = Join-Path $Here 'start.bat'
$User     = [Security.Principal.WindowsIdentity]::GetCurrent().Name

if ($Remove) {
  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed. The bot no longer starts at logon. A bot window that's open keeps running until you close it."
  } else {
    Write-Host "There was no '$TaskName' task to remove."
  }
  return
}

if (-not (Test-Path -LiteralPath $StartBat)) { throw "start.bat isn't next to this script ($Here)." }
if (-not (Test-Path -LiteralPath (Join-Path $Here 'config.json'))) {
  Write-Warning "config.json isn't here yet. The task is added anyway; the bot starts once config.json is filled in."
}

# Anything else that already starts the bot (a Startup-folder shortcut, another task) would
# open a second window. The bot refuses to run twice, but the extra window is clutter.
$others = @()
$shell = New-Object -ComObject WScript.Shell
foreach ($dir in [Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup')) {
  if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { continue }
  foreach ($f in Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue) {
    $text = ''
    if ($f.Extension -eq '.lnk') {
      try { $l = $shell.CreateShortcut($f.FullName); $text = "$($l.TargetPath) $($l.Arguments) $($l.WorkingDirectory)" } catch {}
    } elseif ($f.Extension -in '.bat', '.cmd', '.vbs', '.ps1') {
      try { $text = Get-Content -LiteralPath $f.FullName -Raw } catch {}
    }
    if ($text -match 'epu-discord|bot\.py') { $others += $f.FullName }
  }
}
foreach ($t in Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -ne $TaskName }) {
  foreach ($a in $t.Actions) {
    if ("$($a.Execute) $($a.Arguments) $($a.WorkingDirectory)" -match 'epu-discord') { $others += "Task Scheduler: $($t.TaskPath)$($t.TaskName)" }
  }
}

# cmd's "start /min" opens start.bat in its own minimized window titled "EPU Discord bot".
$action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" `
  -Argument "/c start `"$TaskName`" /min `"$StartBat`"" -WorkingDirectory $Here
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $User
$trigger.Delay = 'PT30S'   # let the network come up first
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
$principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
  -Principal $principal -Description 'Starts the EPU Guild Tools Discord bot (start.bat) at logon.' -Force | Out-Null

Write-Host "Added: the bot starts by itself, minimized, 30 seconds after you log in to Windows."
if ($others.Count) {
  Write-Host ""
  Write-Host "These also start the bot. You can delete them; until then the extra window just says the bot is already running:"
  $others | ForEach-Object { Write-Host "  $_" }
}
if (-not $NoStart) {
  Start-ScheduledTask -TaskName $TaskName
  Write-Host "Started it now in a minimized window titled '$TaskName' (look on the taskbar)."
}
