<#
.SYNOPSIS
    Ensures a pinned Lune binary exists locally, downloading it if missing.

.DESCRIPTION
    Twin of Bootstrap-Rojo.ps1 for the headless test tier (verify.ps1 Tier 4).
    There is no toolchain manager (Rokit/Aftman/Foreman) or Rust on this machine, so
    this script bootstraps Lune itself: it downloads the pinned Windows release from
    GitHub into tools/bin/lune.exe the first time, then no-ops on every later call.

    Lune runs the pure Luau modules (FlightPhysics, GameConfig, RescueRules, ...)
    OUTSIDE Roblox for exit-code-gated logic tests. @lune/roblox supplies the
    Vector3/CFrame/Color3/Enum datatypes the kernel uses; tests/_loader.luau bridges
    Roblox-style `require(script.Parent.X)` onto Lune's string loader.

    Status messages go to the host; the ONLY thing written to the pipeline is the full
    path to lune.exe, so callers can do:  $lune = & tools\Bootstrap-Lune.ps1

.PARAMETER Force
    Re-download even if the correct version is already present.
#>
[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'

# --- Pin the version. 0.10.5 is the version PROVEN in the S40 feasibility run. ---
$Version = '0.10.5'
$Arch    = 'windows-x86_64'           # AMD64; change to windows-aarch64 on ARM hosts.
$Asset   = "lune-$Version-$Arch.zip"
$Url     = "https://github.com/lune-org/lune/releases/download/v$Version/$Asset"

$BinDir  = Join-Path $PSScriptRoot 'bin'
$Exe     = Join-Path $BinDir 'lune.exe'

function Test-LuneVersion {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    try {
        $v = & $Path '--version' 2>$null   # prints e.g. "lune 0.10.5"
        return ($v -match [regex]::Escape($Version))
    } catch { return $false }
}

if (-not $Force -and (Test-LuneVersion -Path $Exe)) {
    Write-Output $Exe
    return
}

Write-Host "Bootstrapping Lune $Version ($Arch) -> $Exe" -ForegroundColor Cyan

# PowerShell 5.1 needs TLS 1.2 forced for GitHub, and -Progress slows downloads hugely.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$oldProgress = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("lune-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $zip = Join-Path $tmp $Asset
    Write-Host "  downloading $Url" -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $Url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'lune-bootstrap' }

    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $extracted = Get-ChildItem -Path $tmp -Recurse -Filter 'lune.exe' | Select-Object -First 1
    if (-not $extracted) { throw "lune.exe not found inside $Asset" }

    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    Copy-Item -Path $extracted.FullName -Destination $Exe -Force
}
finally {
    $ProgressPreference = $oldProgress
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-LuneVersion -Path $Exe)) {
    throw "Lune bootstrap failed: $Exe did not report version $Version."
}

Write-Host "  Lune $Version ready." -ForegroundColor Green
Write-Output $Exe
