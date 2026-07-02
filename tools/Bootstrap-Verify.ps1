<#
.SYNOPSIS
    Ensures a pinned static-analysis binary (luau-lsp or selene) exists locally,
    downloading it if missing. Companion to Bootstrap-Rojo.ps1.

.DESCRIPTION
    There is no toolchain manager (Rokit/Aftman/Foreman) or Rust on this machine,
    so this bootstraps the analysis tools directly from their GitHub releases into
    tools/bin/, then no-ops on later calls. Same contract as Bootstrap-Rojo.ps1:
    status messages go to the host; the ONLY thing written to the pipeline is the
    full path to the exe, so callers can do:  $exe = & tools\Bootstrap-Verify.ps1 -Tool selene

    This is BEST-EFFORT: if a download fails (offline, moved asset, new machine),
    the caller (verify.ps1) treats that tier as UNAVAILABLE and carries on. Nothing
    here is required for build.ps1 / serve.ps1.

.PARAMETER Tool
    Which tool to ensure: 'luau-lsp' or 'selene'.

.PARAMETER Force
    Re-download even if the correct version is already present.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('luau-lsp', 'selene')][string]$Tool,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# --- Pinned versions (bump deliberately; these are the tested-known asset names). ---
# Windows x86_64 only. Asset layouts differ per project, hence the per-tool table.
$Spec = switch ($Tool) {
    'luau-lsp' {
        @{
            Version = '1.32.1'
            Exe     = 'luau-lsp.exe'
            # e.g. luau-lsp-win64.zip  ->  luau-lsp.exe
            Url     = 'https://github.com/JohnnyMorganz/luau-lsp/releases/download/{0}/luau-lsp-win64.zip'
            VerArg  = '--version'
        }
    }
    'selene' {
        @{
            Version = '0.28.1'
            Exe     = 'selene.exe'
            # e.g. selene-0.28.1-windows.zip  ->  selene.exe
            Url     = 'https://github.com/Kampfkarren/selene/releases/download/{0}/selene-{0}-windows.zip'
            VerArg  = '--version'
        }
    }
}

$Version = $Spec.Version
$Url     = ($Spec.Url -f $Version)
$BinDir  = Join-Path $PSScriptRoot 'bin'
$Exe     = Join-Path $BinDir $Spec.Exe

function Test-ToolVersion {
    param([string]$Path, [string]$Arg, [string]$Want)
    if (-not (Test-Path $Path)) { return $false }
    try {
        $v = & $Path $Arg 2>$null      # prints e.g. "selene 0.28.1" / "luau-lsp v1.32.1"
        return ($v -match [regex]::Escape($Want))
    } catch { return $false }
}

if (-not $Force -and (Test-ToolVersion -Path $Exe -Arg $Spec.VerArg -Want $Version)) {
    Write-Output $Exe
    return
}

Write-Host "Bootstrapping $Tool $Version (windows-x86_64) -> $Exe" -ForegroundColor Cyan

# PowerShell 5.1 needs TLS 1.2 forced for GitHub; -Progress slows downloads hugely.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$oldProgress = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("$Tool-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $zip = Join-Path $tmp "$Tool.zip"
    Write-Host "  downloading $Url" -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $Url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'evc-verify-bootstrap' }

    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $extracted = Get-ChildItem -Path $tmp -Recurse -Filter $Spec.Exe | Select-Object -First 1
    if (-not $extracted) { throw "$($Spec.Exe) not found inside the release asset." }

    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    Copy-Item -Path $extracted.FullName -Destination $Exe -Force
}
finally {
    $ProgressPreference = $oldProgress
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Test-ToolVersion -Path $Exe -Arg $Spec.VerArg -Want $Version)) {
    throw "$Tool bootstrap failed: $Exe did not report version $Version (asset name may have changed for this release)."
}

Write-Host "  $Tool $Version ready." -ForegroundColor Green
Write-Output $Exe
