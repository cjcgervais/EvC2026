<#
.SYNOPSIS
    Ensures a pinned Rojo binary exists locally, downloading it if missing.

.DESCRIPTION
    There is no toolchain manager (Rokit/Aftman/Foreman) or Rust on this machine, so
    this script bootstraps Rojo itself: it downloads the pinned Windows release from
    GitHub into tools/bin/rojo.exe the first time, then no-ops on every later call.

    Status messages go to the host; the ONLY thing written to the pipeline is the full
    path to rojo.exe, so callers can do:  $rojo = & tools\Bootstrap-Rojo.ps1

.PARAMETER Force
    Re-download even if the correct version is already present.
#>
[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'

# --- Pin the version. Rojo 7.x speaks the project format default.project.json uses. ---
$Version = '7.6.1'
$Arch    = 'windows-x86_64'           # AMD64; change to windows-aarch64 on ARM hosts.
$Asset   = "rojo-$Version-$Arch.zip"
$Url     = "https://github.com/rojo-rbx/rojo/releases/download/v$Version/$Asset"

$BinDir  = Join-Path $PSScriptRoot 'bin'
$Exe     = Join-Path $BinDir 'rojo.exe'

function Test-RojoVersion {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    try {
        $v = & $Path '--version' 2>$null   # prints e.g. "Rojo 7.6.1"
        return ($v -match [regex]::Escape($Version))
    } catch { return $false }
}

if (-not $Force -and (Test-RojoVersion -Path $Exe)) {
    Write-Output $Exe
    return
}

Write-Host "Bootstrapping Rojo $Version ($Arch) -> $Exe" -ForegroundColor Cyan

# PowerShell 5.1 needs TLS 1.2 forced for GitHub, and -Progress slows downloads hugely.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$oldProgress = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("rojo-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $zip = Join-Path $tmp $Asset
    Write-Host "  downloading $Url" -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $Url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'rojo-bootstrap' }

    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $extracted = Get-ChildItem -Path $tmp -Recurse -Filter 'rojo.exe' | Select-Object -First 1
    if (-not $extracted) { throw "rojo.exe not found inside $Asset" }

    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    Copy-Item -Path $extracted.FullName -Destination $Exe -Force
}
finally {
    $ProgressPreference = $oldProgress
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-RojoVersion -Path $Exe)) {
    throw "Rojo bootstrap failed: $Exe did not report version $Version."
}

Write-Host "  Rojo $Version ready." -ForegroundColor Green
Write-Output $Exe
