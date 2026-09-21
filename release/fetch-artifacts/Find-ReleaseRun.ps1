#Requires -Version 7.0

<#
.SYNOPSIS
    Finds the CI run whose artifact should be released: the one that
    built this exact commit, or, given a version, the one that built
    that version.

.PARAMETER Workflow
    Name of the workflow whose artifacts should be released.

.PARAMETER Version
    Release this earlier build instead of this commit's. Empty means
    this commit's.

.PARAMETER Artifact
    Artifact holding the built output and version file.

.PARAMETER VersionFile
    File inside the artifact holding the version that was built.

.PARAMETER SearchDepth
    How many recent successful runs to search for that version.

.PARAMETER Sha
    The commit to find a run for, when Version is empty.

.PARAMETER Ref
    The ref this is running on, e.g. refs/heads/main.

.PARAMETER RefName
    The short name of Ref, e.g. main.

.PARAMETER Repository
    owner/repo the runs live in.

.PARAMETER Token
    Token used to read runs and artifacts.

.EXAMPLE
    ./release/fetch-artifacts/Find-ReleaseRun.ps1 -Workflow 'Continuous Integration' -Artifact packages -VersionFile version.txt -SearchDepth 50 -Sha $sha -Ref $ref -RefName $refName -Repository owner/repo -Token $token
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Workflow,
    [string]$Version = '',
    [Parameter(Mandatory)][string]$Artifact,
    [Parameter(Mandatory)][string]$VersionFile,
    [Parameter(Mandatory)][int]$SearchDepth,
    [Parameter(Mandatory)][string]$Sha,
    [Parameter(Mandatory)][string]$Ref,
    [Parameter(Mandatory)][string]$RefName,
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$Token
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:GH_TOKEN = $Token

Import-Module (Join-Path $PSScriptRoot 'Helpers.psm1') -Force

$requestedVersion = $Version.TrimStart('v')

if ($requestedVersion) {
    # A tag or a pull-request merge ref is not a branch a build ever ran
    # on - the ref name would be the tag itself or 'N/merge', and neither
    # has runs.
    $branch = Resolve-SearchBranch -Ref $Ref -RefName $RefName -Repository $Repository
    $run = Find-RunForVersion -Workflow $Workflow -Branch $branch -Version $requestedVersion `
        -Artifact $Artifact -VersionFile $VersionFile -SearchDepth $SearchDepth
    $wanted = "version $requestedVersion"
}
else {
    $run = Find-RunForCommit -Workflow $Workflow -Sha $Sha
    $wanted = $Sha
}

if (-not $run) {
    Write-Host "::warning::No successful '$Workflow' run found for $wanted."
    'found=false' >> $env:GITHUB_OUTPUT
    'run-id=' >> $env:GITHUB_OUTPUT
    'sha=' >> $env:GITHUB_OUTPUT
    exit 0
}

Write-Host "Releasing the output of run $($run.RunId), built from $($run.Sha)"
'found=true' >> $env:GITHUB_OUTPUT
"run-id=$($run.RunId)" >> $env:GITHUB_OUTPUT
"sha=$($run.Sha)" >> $env:GITHUB_OUTPUT
