# Stage a complete addon and keep a recoverable previous installation.
function Install-EPUAddon([string]$Source, [string]$Destination) {
  $sourcePath = (Resolve-Path -LiteralPath $Source -ErrorAction Stop).Path
  $destinationPath = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
  if ((Split-Path $destinationPath -Leaf) -ne 'EPUGuild') { throw 'Expected an EPUGuild destination folder.' }
  $parentPath = Split-Path $destinationPath -Parent
  $stagePath = Join-Path $parentPath ('.EPUGuild-stage-' + [guid]::NewGuid().ToString('N'))
  $backupPath = Join-Path $parentPath ('.EPUGuild-backup-' + [guid]::NewGuid().ToString('N'))
  # Verify absolute sibling targets before any recursive operation or move.
  foreach ($targetPath in @($stagePath, $backupPath)) {
    if ((Split-Path ([IO.Path]::GetFullPath($targetPath)) -Parent) -ne $parentPath) { throw 'Invalid update staging path.' }
  }
  if (-not (Test-Path -LiteralPath (Join-Path $sourcePath 'EPUGuild.toc'))) { throw 'Missing addon manifest.' }
  $hadInstall = Test-Path -LiteralPath $destinationPath
  $movedOld = $false
  $ownsLock = $false
  $lockPath = Join-Path $parentPath '.EPUGuild-update.lock'
  if ((Test-Path -LiteralPath $lockPath) -and ((Get-Date) - (Get-Item -LiteralPath $lockPath).LastWriteTime).TotalMinutes -lt 10) {
    throw 'Another EPU update is already running.'
  }
  try {
    New-Item -ItemType Directory -Force -Path $parentPath | Out-Null
    if (Test-Path -LiteralPath $lockPath) { Remove-Item -LiteralPath $lockPath -Force -ErrorAction Stop }
    $lockFile = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $ownsLock = $true
    $lockFile.Dispose()
    New-Item -ItemType Directory -Force -Path $stagePath | Out-Null
    Copy-Item -Path (Join-Path $sourcePath '*') -Destination $stagePath -Recurse -Force -ErrorAction Stop
    foreach ($line in Get-Content -LiteralPath (Join-Path $stagePath 'EPUGuild.toc')) {
      $entry = $line.Trim()
      if ($entry -match '\.lua$') {
        $filePath = [IO.Path]::GetFullPath((Join-Path $stagePath $entry))
        if (-not $filePath.StartsWith($stagePath + '\', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $filePath)) {
          throw "Incomplete update: $entry is missing or outside the addon."
        }
      }
    }
    if ($hadInstall) {
      # Read the inbox last so actions queued while downloading aren't replaced.
      $inboxPath = Join-Path $destinationPath 'Inbox.lua'
      if (Test-Path -LiteralPath $inboxPath) { Copy-Item -LiteralPath $inboxPath -Destination (Join-Path $stagePath 'Inbox.lua') -Force -ErrorAction Stop }
      [IO.Directory]::Move($destinationPath, $backupPath)
      $movedOld = $true
    }
    [IO.Directory]::Move($stagePath, $destinationPath)
    # Keep the previous installation as a hidden sibling for recovery. Its folder
    # name doesn't match EPUGuild.toc, so WoW won't load it as a second addon.
    if ($movedOld) { return $backupPath }
  } catch {
    if ($movedOld -and -not (Test-Path -LiteralPath $destinationPath)) {
      Move-Item -LiteralPath $backupPath -Destination $destinationPath -ErrorAction Stop
    }
    throw
  } finally {
    if (Test-Path -LiteralPath $stagePath) { Remove-Item -LiteralPath $stagePath -Recurse -Force -ErrorAction SilentlyContinue }
    if ($ownsLock) { Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue }
  }
}
