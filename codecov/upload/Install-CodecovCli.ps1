#Requires -Version 7.0

<#
.SYNOPSIS
    Downloads the codecovcli binary matching the runner's OS, and reports
    where it landed.

.PARAMETER OutputPath
    Where to save the binary. Defaults to a name matching the OS under
    RUNNER_TEMP.

.EXAMPLE
    ./codecov/upload/Install-CodecovCli.ps1
#>
[CmdletBinding()]
param([string]$OutputPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Codecov-Upload-Tasks.psm1') -Force

if (-not $OutputPath) {
    $name = Get-CodecovCliFileName -IsWindows $IsWindows
    $OutputPath = Join-Path $env:RUNNER_TEMP $name
}

$url = Get-CodecovCliUrl -IsWindows $IsWindows
Write-Host "Downloading $url ..." -NoNewline
Invoke-WebRequest -Uri $url -OutFile $OutputPath
if (-not $IsWindows) { & chmod +x $OutputPath }
Write-Host ' done' -ForegroundColor Green

"path=$OutputPath" >> $env:GITHUB_OUTPUT
