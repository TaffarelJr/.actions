#Requires -Version 7.0

<#
.SYNOPSIS
    Decides the version to draft a release for, and reports it -
    or fails if there is nothing valid to draft.

.PARAMETER Requested
    The version asked for, e.g. 1.4.2 or v1.4.2.
    Empty means this commit's.

.PARAMETER Found
    Whether release/fetch-artifacts found a CI build for this commit or version.

.PARAMETER FromBuild
    The version that build recorded, or empty.

.PARAMETER BuiltSha
    The commit that build was built from, or empty.

.PARAMETER Fallback
    version/calculate's fallback, used when there is no build to read from.

.PARAMETER CurrentSha
    This commit, used when BuiltSha is empty.

.EXAMPLE
    ./release/draft/Resolve-DraftVersion.ps1 -Found $false -Fallback 1.4.2 -CurrentSha $sha
#>
[CmdletBinding()]
param(
    [string]$Requested = '',
    [Parameter(Mandatory)][bool]$Found,
    [string]$FromBuild = '',
    [string]$BuiltSha = '',
    [string]$Fallback = '',
    [Parameter(Mandatory)][string]$CurrentSha
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Helpers.psm1') -Force

try {
    $resolved = Resolve-DraftVersion -Requested $Requested -Found $Found -FromBuild $FromBuild `
        -BuiltSha $BuiltSha -Fallback $Fallback -CurrentSha $CurrentSha
}
catch {
    Write-Host "::error::$($_.Exception.Message)"
    exit 1
}

if ($resolved.Source -eq 'Build') {
    Write-Host "Version from the build: $($resolved.Version)"
}
else {
    Write-Host "::warning::No version from the build; using GitVersion ($($resolved.Version))."
}

"version=$($resolved.Version)" >> $env:GITHUB_OUTPUT
"sha=$($resolved.Sha)" >> $env:GITHUB_OUTPUT
