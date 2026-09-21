#Requires -Version 7.0

<#
.SYNOPSIS
    Validates a Codecov configuration file against Codecov's own
    validator, and reports the result.

.PARAMETER ConfigPath
    Path to the Codecov configuration file.

.PARAMETER Endpoint
    Codecov's validation endpoint.

.EXAMPLE
    ./codecov/validate/Test-CodecovConfig.ps1 -ConfigPath .github/codecov.yml -Endpoint https://codecov.io/validate
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$Endpoint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Helpers.psm1') -Force

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    "valid=false" >> $env:GITHUB_OUTPUT
    Write-Host "::error::$ConfigPath not found."
    exit 1
}

$result = Invoke-CodecovValidation -ConfigPath $ConfigPath -Endpoint $Endpoint
Write-Host $result.Output

if (-not $result.Valid) {
    "valid=false" >> $env:GITHUB_OUTPUT
    Write-Host "::error file=${ConfigPath}::$ConfigPath is not valid. The validator's reason is in the log above."
    exit 1
}

"valid=true" >> $env:GITHUB_OUTPUT
Write-Host "✅ $ConfigPath is valid"
