#Requires -Version 7.0

<#
.SYNOPSIS
    Writes the release body for a version, from the git history.

.DESCRIPTION
    Produces two documents in one file: the release notes a reader needs to
    decide whether to upgrade, and the complete changelog folded below them.

    Reads git history only, so this behaves the same in every repo regardless
    of what the repo is written in.

    Self-contained on purpose. This ships inside a composite action, so it
    depends on nothing but git and its own task module - which is what lets a
    repo with no scripts/ folder still generate release notes. Progress goes
    out as GitHub workflow commands rather than through console helpers,
    because the only reader is a job log.

.PARAMETER Version
    The version being released, used for the heading and the compare link.

.PARAMETER OutputPath
    Where to write the Markdown. Defaults to 'Changelog.md'.

.PARAMETER FromTag
    Start from this tag instead of the most recent release tag. Use it to
    rebuild notes for an earlier release.

.PARAMETER ToRef
    The commit to release. Defaults to HEAD.

.PARAMETER SummaryPath
    A file holding the prose summary to put at the top - generated, or
    hand-written. When absent, a placeholder comment is emitted instead.

.PARAMETER Repository
    The 'owner/name' used to build links. Defaults to GITHUB_REPOSITORY so a
    workflow needs to pass nothing.

.EXAMPLE
    ./New-Changelog.ps1 -Version 1.4.0

    Writes Changelog.md covering everything since the last v* tag.

.EXAMPLE
    ./New-Changelog.ps1 -Version 1.4.0 -SummaryPath summary.md

    The same, with a prose summary in place of the placeholder.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Version,

    [string]$OutputPath = 'Changelog.md',

    [string]$FromTag,

    [string]$ToRef = 'HEAD',

    [string]$SummaryPath,

    [string]$Repository = $env:GITHUB_REPOSITORY
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'New-Changelog-Tasks.psm1') -Force

# Workflow commands, so the job log and the annotations both say something
# useful without dragging the interactive console helpers along.
function Write-Note { param([string]$Message) Write-Host "::notice::$Message" }
function Write-Alert { param([string]$Message) Write-Host "::warning::$Message" }
function Write-Line { param([string]$Message) Write-Host "  $Message" }

$headSha = (git rev-parse $ToRef).Trim()
$baseline = Get-ChangelogBaseline -HeadSha $headSha -FromTag $FromTag

$from = if ($baseline.Tag) {
    "$($baseline.Tag) ($($baseline.Sha.Substring(0, 7)))"
}
else { 'the start of history' }

Write-Line "Version : $Version"
Write-Line "From    : $from"
Write-Line "To      : $($headSha.Substring(0, 7))"

$commits = @(Get-ChangelogCommit -StartSha $baseline.Sha -EndSha $headSha)
Write-Line "Commits : $($commits.Count)"

$summary = ''
if ($SummaryPath) {
    if (-not (Test-Path $SummaryPath)) {
        # Not fatal: a missing summary costs a placeholder, and failing the
        # release over it would be worse.
        Write-Alert "No summary at '$SummaryPath'; using the placeholder."
    }
    else {
        $summary = (Get-Content $SummaryPath -Raw).Trim()
        Write-Line "Summary read from '$SummaryPath'"
    }
}

$lines = Format-ReleaseNote `
    -Version $Version `
    -Commits $commits `
    -Baseline $baseline `
    -Repository $Repository `
    -Summary $summary

foreach ($group in (Get-CategoryGroup $commits).Values) {
    Write-Line "$($group.Title) ($($group.Commits.Count))"
}

Set-Content -Path $OutputPath -Value $lines -Encoding utf8NoBOM
Write-Note "Wrote $OutputPath ($($lines.Count) lines) for $Version"
