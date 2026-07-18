<#
.SYNOPSIS
    Ensures a pinned run-in-roblox binary exists locally, downloading it if missing.

.DESCRIPTION
    Twin of Bootstrap-Lune.ps1 / Bootstrap-Rojo.ps1 for the headless SMOKE-BOOT tier
    (verify.ps1 Tier 4.5, A6). run-in-roblox launches the installed Roblox Studio,
    opens the freshly built place, injects a server Script, runs it, forwards its
    print/warn to stdout, and exits non-zero if that script errors. This is what
    catches the "machine-green but the map is empty at RUNTIME" class that geometry
    tests (Tier 4) can't see.

    Requires Roblox Studio to be installed (it is — RobloxStudioBeta.exe under
    %LOCALAPPDATA%\Roblox\Versions). Downloads the pinned Windows release into
    tools/bin/run-in-roblox.exe the first time, then no-ops on every later call.

    Status messages go to the host; the ONLY thing written to the pipeline is the full
    path to run-in-roblox.exe, so callers can do:
        $rir = & tools\Bootstrap-RunInRoblox.ps1

.PARAMETER Force
    Re-download even if the binary is already present.
#>
[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'

# --- Pin the version. v0.3.0 is the current release with a win64 asset. ---
$Version = '0.3.0'
$Asset   = "run-in-roblox-$Version-win64.zip"
$Url     = "https://github.com/rojo-rbx/run-in-roblox/releases/download/v$Version/$Asset"

$BinDir  = Join-Path $PSScriptRoot 'bin'
$Exe     = Join-Path $BinDir 'run-in-roblox.exe'

# run-in-roblox --version output format is not guaranteed stable across builds, so
# presence-check rather than version-match (mirrors Lune's intent, avoids false
# re-downloads / bootstrap-failed throws if the format drifts).
if (-not $Force -and (Test-Path $Exe)) {
    Write-Output $Exe
    return
}

Write-Host "Bootstrapping run-in-roblox $Version (win64) -> $Exe" -ForegroundColor Cyan

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$oldProgress = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("rir-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $zip = Join-Path $tmp $Asset
    Write-Host "  downloading $Url" -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $Url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'rir-bootstrap' }

    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $extracted = Get-ChildItem -Path $tmp -Recurse -Filter 'run-in-roblox.exe' | Select-Object -First 1
    if (-not $extracted) { throw "run-in-roblox.exe not found inside $Asset" }

    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    Copy-Item -Path $extracted.FullName -Destination $Exe -Force
}
finally {
    $ProgressPreference = $oldProgress
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path $Exe)) {
    throw "run-in-roblox bootstrap failed: $Exe missing after extract."
}

Write-Host "  run-in-roblox $Version ready." -ForegroundColor Green
Write-Output $Exe
