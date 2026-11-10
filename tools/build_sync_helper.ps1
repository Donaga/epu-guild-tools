param([Parameter(Mandatory=$true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version)
$ErrorActionPreference='Stop'
python -m PyInstaller --noconfirm --clean --onefile --windowed --name EPU-Sync-Helper --paths epu-discord sync-helper/helper.py
if($LASTEXITCODE -ne 0){throw 'The Windows helper could not be built'}
$helperExe=Join-Path (Get-Location) 'dist/EPU-Sync-Helper.exe'
if(-not (Test-Path -LiteralPath $helperExe) -or (Get-Item -LiteralPath $helperExe).Length -lt 1MB){throw 'The helper executable is missing or incomplete'}
$package=Join-Path (Get-Location) "dist/EPU-Sync-Helper-$Version.zip"
Compress-Archive -LiteralPath $helperExe,'sync-helper/README.md' -DestinationPath $package -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[System.IO.Compression.ZipFile]::OpenRead($package)
try {
  if(-not ($zip.Entries.FullName -contains 'EPU-Sync-Helper.exe') -or -not ($zip.Entries.FullName -contains 'README.md')){throw 'Helper package is incomplete'}
} finally {$zip.Dispose()}
Write-Output "Built and verified EPU-Sync-Helper-$Version.zip"
