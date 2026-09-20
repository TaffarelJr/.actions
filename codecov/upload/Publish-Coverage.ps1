#Requires -Version 7.0

<#
.SYNOPSIS
    Uploads coverage reports found under a folder to Codecov via codecovcli.

.DESCRIPTION
    Files directly under Path upload as one unflagged group. Without
    -GroupBySubfolder, every file found - loose or in a subfolder - uploads
    together in that one group, so a subfolder is just organization, not a
    split. With -GroupBySubfolder, each immediate subfolder becomes its own
    upload, flagged with that subfolder's name - one flag per build target
    (a .NET TFM, for example), however many exist.

.PARAMETER CliPath
    Path to the codecovcli binary, from Install-CodecovCli.ps1.

.PARAMETER Path
    Folder to search for coverage reports, recursively.

.PARAMETER Pattern
    Filename pattern for a coverage report.

.PARAMETER Token
    Codecov upload token. Omit to rely on codecovcli's own detection.

.PARAMETER GroupBySubfolder
    Upload each immediate subfolder of Path as its own flagged group.

.PARAMETER FailOnError
    Fail this step when an upload fails, rather than only warning.

.EXAMPLE
    ./codecov/upload/Publish-Coverage.ps1 -CliPath ./codecov

.EXAMPLE
    ./codecov/upload/Publish-Coverage.ps1 -CliPath ./codecov -GroupBySubfolder
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CliPath,
    [string]$Path = 'test/coverage',
    [string]$Pattern = '*.cobertura.xml',
    [string]$Token = '',
    [switch]$GroupBySubfolder,
    [switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Codecov-Upload-Tasks.psm1') -Force

$groups = Find-CoverageGroup -Path $Path -Pattern $Pattern
$plan = Get-UploadPlan -Group $groups -GroupBySubfolder $GroupBySubfolder.IsPresent `
    -Token $Token -FailOnError $FailOnError.IsPresent

if (-not $plan) {
    Write-Host "::warning::No coverage reports matching '$Pattern' found under '$Path'."
    exit 0
}

$failed = 0
foreach ($upload in $plan) {
    $label = if ($upload.Flag) { $upload.Flag } else { '(unflagged)' }
    Write-Host "Uploading $label ..."
    & $CliPath @($upload.Arguments)
    if ($LASTEXITCODE -ne 0) {
        $failed++
        Write-Host "::warning::Upload for $label failed (exit $LASTEXITCODE)."
    }
}

if ($failed -gt 0 -and $FailOnError) { exit $failed }
exit 0
