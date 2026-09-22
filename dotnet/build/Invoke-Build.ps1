#Requires -Version 7.0

<#
.SYNOPSIS
    Builds a repo's .NET solution.

.PARAMETER Configuration
    The build configuration, e.g. Release or Debug.

.PARAMETER Version
    The version to stamp into the build, e.g. 1.4.0.
    Empty builds without one.

.EXAMPLE
    ./dotnet/build/Invoke-Build.ps1 -Configuration Release -Version 1.4.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Configuration,
    [AllowEmptyString()][string]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..' 'Common-Build.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Helpers.psm1') -Force

$context = Get-BuildContext -Configuration $Configuration -Version $Version
Invoke-Build -Context $context
