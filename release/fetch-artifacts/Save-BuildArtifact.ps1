#Requires -Version 7.0

<#
.SYNOPSIS
    Downloads a CI run's built artifact into a folder.

.DESCRIPTION
    actions/download-artifact raises a job-level error
    when the named artifact does not exist, even with continue-on-error -
    alarming for what is, for a repo with nothing to package, the routine case.
    `gh run download` reports the same condition as plain text instead.

.PARAMETER RunId
    The run to download from.

.PARAMETER Artifact
    Name of the artifact to download.

.PARAMETER Path
    Folder to download it into.

.PARAMETER Token
    Token used to read the artifact.

.EXAMPLE
    ./release/fetch-artifacts/Save-BuildArtifact.ps1 -RunId $runId -Artifact packages -Path artifacts -Token $token
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$Artifact,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Token
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:GH_TOKEN = $Token

Import-Module (Join-Path $PSScriptRoot 'Helpers.psm1') -Force

if (-not (Get-Artifact -RunId $RunId -Artifact $Artifact -Path $Path)) {
    Write-Host "::notice::Run $RunId has no '$Artifact' artifact (expired, or this repo has nothing to package)."
}
