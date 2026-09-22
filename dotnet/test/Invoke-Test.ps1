#Requires -Version 7.0

<#
.SYNOPSIS
    Tests a repo's .NET solution.

.PARAMETER Configuration
    The build configuration, e.g. Release or Debug.

.EXAMPLE
    ./dotnet/test/Invoke-Test.ps1 -Configuration Release
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Configuration)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..' 'Common-Build.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Helpers.psm1') -Force

$context = Get-BuildContext -Configuration $Configuration
Invoke-Test -Context $context
