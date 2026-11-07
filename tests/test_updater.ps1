param([Parameter(Mandatory=$true)][string]$ScratchRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../updater/Install-EPU.ps1')
function Assert-That($condition, [string]$label) {
  if (-not $condition) { throw "FAIL $label" }
  Write-Output "PASS $label"
}
$testRoot = Join-Path (Resolve-Path -LiteralPath $ScratchRoot).Path ('updater-test-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $testRoot 'source'
$addons = Join-Path $testRoot 'AddOns'
$destination = Join-Path $addons 'EPUGuild'
New-Item -ItemType Directory -Force -Path $source,$destination | Out-Null
Set-Content -LiteralPath (Join-Path $source 'EPUGuild.toc') -Value @('## Version: test','Core.lua','Inbox.lua')
Set-Content -LiteralPath (Join-Path $source 'Core.lua') -Value '-- new code'
Set-Content -LiteralPath (Join-Path $source 'Inbox.lua') -Value '-- empty inbox'
Set-Content -LiteralPath (Join-Path $destination 'Inbox.lua') -Value 'EPUGuildInbox = {pending=true}'
Set-Content -LiteralPath (Join-Path $destination 'Old.lua') -Value '-- old code'
$backup = Install-EPUAddon -Source $source -Destination $destination
Assert-That ((Get-Content -LiteralPath (Join-Path $destination 'Core.lua')) -eq '-- new code') 'staged addon installed'
Assert-That ((Get-Content -LiteralPath (Join-Path $destination 'Inbox.lua')) -eq 'EPUGuildInbox = {pending=true}') 'Discord inbox preserved'
Assert-That (-not (Test-Path -LiteralPath (Join-Path $destination 'Old.lua'))) 'obsolete files removed from active install'
Assert-That (Test-Path -LiteralPath (Join-Path $backup 'Old.lua')) 'previous installation retained for recovery'
Assert-That (-not (Test-Path -LiteralPath (Join-Path $addons '.EPUGuild-update.lock'))) 'update lock released'
Set-Content -LiteralPath (Join-Path $source 'EPUGuild.toc') -Value @('Core.lua','Missing.lua')
$failed = $false
try { Install-EPUAddon -Source $source -Destination $destination | Out-Null } catch { $failed = $true }
Assert-That $failed 'incomplete package rejected'
Assert-That ((Get-Content -LiteralPath (Join-Path $destination 'Core.lua')) -eq '-- new code') 'failed package leaves installed code intact'
$errorsFound = $null
[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../updater/Update-EPU.ps1'),[ref]$null,[ref]$errorsFound) | Out-Null
Assert-That ($errorsFound.Count -eq 0) 'updater parses successfully'
