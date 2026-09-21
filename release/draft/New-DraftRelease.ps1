#Requires -Version 7.0

<#
.SYNOPSIS
    Creates (or replaces) the draft release for a tag, and attaches
    whatever artifacts were built.

.DESCRIPTION
    A draft is not idempotent - re-running would add a second draft for
    the same version - so replaces any existing draft for this tag
    first.

.PARAMETER Tag
    The release tag to draft, e.g. v1.4.2.

.PARAMETER Sha
    The commit the release targets.

.PARAMETER NotesPath
    The generated changelog to use as the release notes.

.PARAMETER ArtifactPath
    Folder holding the build's artifacts, if any.

.PARAMETER Token
    Token used to create the release.

.EXAMPLE
    ./release/draft/New-DraftRelease.ps1 -Tag v1.4.2 -Sha $sha -NotesPath Changelog.md -ArtifactPath artifacts -Token $token
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$Sha,
    [Parameter(Mandatory)][string]$NotesPath,
    [Parameter(Mandatory)][string]$ArtifactPath,
    [Parameter(Mandatory)][string]$Token
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:GH_TOKEN = $Token

Import-Module (Join-Path $PSScriptRoot 'Helpers.psm1') -Force

$releases = Get-ReleaseList -Limit 100
if (Test-DraftExists -Release $releases -Tag $Tag) {
    Write-Host "Replacing the existing draft for $Tag"
    Remove-Draft -Tag $Tag
}

$url = New-DraftRelease -Tag $Tag -NotesPath $NotesPath -TargetSha $Sha
"url=$url" >> $env:GITHUB_OUTPUT

if (Test-HasArtifact -Path $ArtifactPath) {
    $count = Publish-ReleaseAsset -Tag $Tag -Path $ArtifactPath
    Write-Host "Attached $count file(s)"
}
else {
    Write-Host '::notice::No artifacts to attach.'
}

Get-DraftSummary -Tag $Tag -Url $url >> $env:GITHUB_STEP_SUMMARY
