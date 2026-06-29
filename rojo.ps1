<#
.SYNOPSIS  Thin wrapper around the bootstrapped Rojo binary — forwards all arguments.
.EXAMPLE  .\rojo.ps1 --version
.EXAMPLE  .\rojo.ps1 plugin install      # install the Rojo companion plugin into Studio
.EXAMPLE  .\rojo.ps1 sourcemap --output sourcemap.json
#>
$ErrorActionPreference = 'Stop'
$rojo = & (Join-Path $PSScriptRoot 'tools\Bootstrap-Rojo.ps1')
& $rojo @args
