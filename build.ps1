<#
.SYNOPSIS  Build a one-shot Roblox place file from the project (Rojo build).
.PARAMETER Output  Output file name (default EaglesVsCrows.rbxlx, gitignored).
.PARAMETER Watch   Rebuild automatically on source changes.
.EXAMPLE  .\build.ps1
.EXAMPLE  .\build.ps1 -Watch
#>
[CmdletBinding()]
param(
    [string]$Output = 'EaglesVsCrows.rbxlx',
    [switch]$Watch
)
$ErrorActionPreference = 'Stop'
$rojo = & (Join-Path $PSScriptRoot 'tools\Bootstrap-Rojo.ps1')
$proj = Join-Path $PSScriptRoot 'default.project.json'
$out  = Join-Path $PSScriptRoot $Output

if ($Watch) {
    Write-Host "Building $out and watching for changes (Ctrl+C to stop)..." -ForegroundColor Cyan
    & $rojo build $proj -o $out --watch
} else {
    & $rojo build $proj -o $out
    Write-Host "Built $out" -ForegroundColor Green
}
