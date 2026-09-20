#Requires -Version 7.0

<#
.SYNOPSIS
    Installs the PowerShell modules the powershell/ actions need, as listed in
    RequiredModules.psd1, skipping any already present.

.PARAMETER ManifestPath
    The manifest to read. Defaults to powershell/RequiredModules.psd1.

.EXAMPLE
    ./powershell/restore/Restore-Modules.ps1
#>
[CmdletBinding()]
param([string]$ManifestPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..' 'Common-Modules.psm1') -Force

foreach ($module in (Get-RequiredModule -ManifestPath $ManifestPath)) {
    Write-Host "$($module.Name) $($module.MinimumVersion)+ ..." -NoNewline
    if (Test-RequiredModule -Name $module.Name -MinimumVersion $module.MinimumVersion) {
        Write-Host ' already installed' -ForegroundColor DarkGray
        continue
    }

    Install-RequiredModule -Name $module.Name -MinimumVersion $module.MinimumVersion
    Write-Host ' installed' -ForegroundColor Green
}
