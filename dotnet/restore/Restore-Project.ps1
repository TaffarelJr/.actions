#Requires -Version 7.0

<#
.SYNOPSIS
    Restores a repo's .NET tools and NuGet packages.

.PARAMETER Configuration
    The build configuration, e.g. Release or Debug.

.EXAMPLE
    ./dotnet/restore/Restore-Project.ps1 -Configuration Release
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Configuration)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..' 'Common-Build.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Helpers.psm1') -Force

$context = Get-BuildContext -Configuration $Configuration
Restore-Tool -Context $context
Restore-Package -Context $context
