<#
  EPU Guild Tools updater.

  Finds your WoW: Forever AddOns folder, checks GitHub for the newest
  EPU Guild Tools release, and installs it if yours is older. Your saved
  data (requests, settings) lives in WTF\ and is never touched.

    Update-EPU.ps1                 check and update (shows a window)
    Update-EPU.ps1 -Quiet          same, no window unless something changed or failed
    Update-EPU.ps1 -Startup        also run quietly every time Windows starts
    Update-EPU.ps1 -NoStartup      stop running at startup
    Update-EPU.ps1 -ChooseFolder   pick the WoW folder again
#>
param(
  [switch]$Quiet,
  [switch]$Startup,
  [switch]$NoStartup,
  [switch]$ChooseFolder,
  [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
$Repo      = 'Donaga/epu-guild-tools'
$AddonName = 'EPUGuild'
$Keep      = @('Inbox.lua')        # written by the Discord companion; never overwrite
$StateDir  = Join-Path $env:APPDATA 'EPUGuildUpdater'
$StateFile = Join-Path $StateDir 'settings.json'
$Self      = $MyInvocation.MyCommand.Path
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Add-Type -AssemblyName System.Windows.Forms | Out-Null
function Say([string]$msg, [string]$icon = 'Information') {
  if ($Quiet -and $icon -eq 'Information') { Write-Host $msg; return }
  [System.Windows.Forms.MessageBox]::Show($msg, 'EPU Guild Tools updater', 'OK', $icon) | Out-Null
}

function Load-State {
  if (Test-Path $StateFile) { try { return Get-Content $StateFile -Raw | ConvertFrom-Json } catch {} }
  return [pscustomobject]@{ addons = $null }
}
function Save-State($s) {
  New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
  $s | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8
}

# --- Find the WoW: Forever AddOns folder --------------------------------------
function Find-AddOns {
  $roots = New-Object System.Collections.Generic.List[string]
  foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
                   'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft') {
    try {
      $p = (Get-ItemProperty -Path $key -ErrorAction Stop).InstallPath
      if ($p) { $roots.Add((Split-Path ($p.TrimEnd('\')) -Parent)); $roots.Add($p.TrimEnd('\')) }
    } catch {}
  }
  foreach ($drive in (Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root })) {
    foreach ($sub in 'Program Files (x86)\World of Warcraft', 'Program Files\World of Warcraft', 'World of Warcraft', 'Games\World of Warcraft') {
      $roots.Add((Join-Path $drive $sub))
    }
  }
  foreach ($r in $roots) {
    foreach ($flavor in '_forever_', '_camelot_') {
      $a = Join-Path $r "$flavor\Interface\AddOns"
      if (Test-Path $a) { return $a }
      if (Test-Path (Join-Path $r $flavor)) {
        New-Item -ItemType Directory -Force -Path $a | Out-Null
        return $a
      }
    }
  }
  return $null
}

function Pick-AddOns {
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description = 'Pick your World of Warcraft\_forever_ folder'
  if ($dlg.ShowDialog() -ne 'OK') { return $null }
  $p = $dlg.SelectedPath.TrimEnd('\')
  if ($p -match '\\AddOns$') { return $p }
  if ($p -match '\\Interface$') { return (Join-Path $p 'AddOns') }
  if (Test-Path (Join-Path $p '_forever_')) { $p = Join-Path $p '_forever_' }
  $a = Join-Path $p 'Interface\AddOns'
  New-Item -ItemType Directory -Force -Path $a | Out-Null
  return $a
}

function Installed-Version($addons) {
  $toc = Join-Path $addons "$AddonName\$AddonName.toc"
  if (-not (Test-Path $toc)) { return $null }
  $line = Select-String -Path $toc -Pattern '^##\s*Version:\s*(.+)$' | Select-Object -First 1
  if ($line) { return $line.Matches[0].Groups[1].Value.Trim() }
  return $null
}

function Version-Key([string]$v) {
  # "0.4.0" -> "00000.00004.00000", so versions compare correctly as text
  $n = @([regex]::Matches(($v -replace '^v', ''), '\d+') | ForEach-Object { [int]$_.Value }) + @(0, 0, 0)
  return ('{0:D5}.{1:D5}.{2:D5}' -f $n[0], $n[1], $n[2])
}

# --- Startup shortcut -------------------------------------------------------------
$StartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'EPU Guild Tools updater.lnk'
if ($NoStartup) {
  if (Test-Path $StartupLnk) { Remove-Item $StartupLnk }
  Say 'EPU Guild Tools will no longer update itself at startup.'
  exit 0
}
if ($Startup) {
  $sh = New-Object -ComObject WScript.Shell
  $lnk = $sh.CreateShortcut($StartupLnk)
  $lnk.TargetPath = (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')
  $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Self`" -Quiet"
  $lnk.WindowStyle = 7
  $lnk.Save()
}

# --- Main -----------------------------------------------------------------------
try {
  $state = Load-State
  $addons = $state.addons
  if ($ChooseFolder -or -not $addons -or -not (Test-Path $addons)) {
    $addons = Find-AddOns
    if (-not $addons -or $ChooseFolder) { $addons = Pick-AddOns }
    if (-not $addons) { Say "Couldn't find WoW: Forever. Run the updater again and pick your World of Warcraft\_forever_ folder." 'Warning'; exit 1 }
    $state = [pscustomobject]@{ addons = $addons }
    Save-State $state
  }

  $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{ 'User-Agent' = 'EPU-Guild-Tools-Updater' }
  $latest = ($release.tag_name -replace '^v', '')
  $asset = $release.assets | Where-Object { $_.name -match "^$AddonName-.*\.zip$" } | Select-Object -First 1
  if (-not $asset) { throw "The latest release ($($release.tag_name)) has no $AddonName zip yet. Try again in a few minutes." }

  $have = Installed-Version $addons
  if ($have -and ((Version-Key $have) -ge (Version-Key $latest))) {
    if (-not $Quiet) { Say "EPU Guild Tools is up to date (version $have).$(if ($Startup) { "`n`nIt will also check for updates each time Windows starts." })" }
    exit 0
  }

  $tmp = Join-Path $env:TEMP ("epu-update-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $zip = Join-Path $tmp $asset.name
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'EPU-Guild-Tools-Updater' }
  Expand-Archive -Path $zip -DestinationPath (Join-Path $tmp 'x') -Force
  $src = Get-ChildItem -Path (Join-Path $tmp 'x') -Recurse -Directory | Where-Object { $_.Name -eq $AddonName -and (Test-Path (Join-Path $_.FullName "$AddonName.toc")) } | Select-Object -First 1
  if (-not $src) { throw "The download didn't contain a $AddonName folder." }

  $dest = Join-Path $addons $AddonName
  try {
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    # remove files the new version no longer has (but keep the Discord inbox)
    $newFiles = Get-ChildItem $src.FullName -Recurse -File | ForEach-Object { $_.FullName.Substring($src.FullName.Length) }
    Get-ChildItem $dest -Recurse -File | Where-Object {
      ($Keep -notcontains $_.Name) -and ($newFiles -notcontains $_.FullName.Substring($dest.Length))
    } | Remove-Item -Force
    Get-ChildItem $src.FullName -Recurse -File | ForEach-Object {
      $rel = $_.FullName.Substring($src.FullName.Length)
      $target = Join-Path $dest $rel
      if (($Keep -contains $_.Name) -and (Test-Path $target)) { return }
      New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
      Copy-Item $_.FullName $target -Force
    }
  } catch [System.UnauthorizedAccessException] {
    if ($Elevated) { throw }
    # Program Files needs admin rights on some PCs: ask once, then retry
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$Self`" -Elevated" + $(if ($Quiet) { ' -Quiet' } else { '' })
    Start-Process powershell -Verb RunAs -ArgumentList $argList
    exit 0
  } finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }

  $was = if ($have) { "from $have " } else { '' }
  Say "EPU Guild Tools updated $($was)to $latest.`n`nIf WoW is open, type /reload to load it."
  exit 0
} catch {
  if ($Quiet) { exit 1 }
  Say ("The update didn't work: " + $_.Exception.Message + "`n`nYou can always download it by hand from https://github.com/$Repo/releases/latest") 'Error'
  exit 1
}
