<#
.SYNOPSIS  Live-sync the project into Roblox Studio (Rojo serve).
.DESCRIPTION
    Bootstraps Rojo if needed, then starts the live-sync server. Open Studio, connect
    with the Rojo plugin (install it once via: .\rojo.ps1 plugin install). Ctrl+C stops.
    Any extra args are passed through to `rojo serve` (e.g. .\serve.ps1 --port 34873).
#>
$ErrorActionPreference = 'Stop'
$rojo = & (Join-Path $PSScriptRoot 'tools\Bootstrap-Rojo.ps1')
$proj = Join-Path $PSScriptRoot 'default.project.json'
Write-Host "Rojo live-sync serving $proj  (Ctrl+C to stop)" -ForegroundColor Cyan
& $rojo serve $proj @args
