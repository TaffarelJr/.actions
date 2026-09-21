#Requires -Version 7.0

<#
.SYNOPSIS
    Reads the version a build recorded, and reports it.

.DESCRIPTION
    Reporting the version the build stamped in, rather than
    recalculating it, is what stops a release from naming a different
    number than the binaries it is shipping. The version file is
    deleted after reading, so it is never published as a release asset.

.PARAMETER Path
    Folder the artifact was downloaded into.

.PARAMETER VersionFile
    File inside the artifact holding the version that was built.

.EXAMPLE
    ./release/fetch-artifacts/Get-BuildVersion.ps1 -Path artifacts -VersionFile version.txt
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$VersionFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Helpers.psm1') -Force

$file = Join-Path $Path $VersionFile
$version = Get-VersionFileContent -Path $file

if ($version) {
    Write-Host "Version from the build: $version"
    Remove-Item -LiteralPath $file -Force
}
else {
    Write-Host "::notice::No $VersionFile in the artifact."
}

"version=$version" >> $env:GITHUB_OUTPUT
