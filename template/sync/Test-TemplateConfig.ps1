#Requires -Version 7.0

<#
.SYNOPSIS
    Validates the inputs a sync needs before touching anything, and
    reports whether it is configured to run at all.

.DESCRIPTION
    A base template has no parent, so its caller leaves TemplateUrl
    empty rather than omitting it - GitHub Actions only rejects a
    wholly missing input, not an empty one. That case is reported, not
    an error, so the caller can skip cleanly rather than let an empty
    URL reach `git remote add` and fail ungracefully later.

.PARAMETER TemplateUrl
    Clone URL of the parent template. Empty means there is no parent.

.PARAMETER Strategy
    Either 'rebase' or 'merge'.

.PARAMETER Repository
    owner/repo this action is running in.

.EXAMPLE
    ./template/sync/Test-TemplateConfig.ps1 -TemplateUrl https://github.com/owner/.template -Strategy rebase -Repository owner/repo
#>
[CmdletBinding()]
param(
    [string]$TemplateUrl = '',
    [Parameter(Mandatory)][string]$Strategy,
    [Parameter(Mandatory)][string]$Repository
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Helpers.psm1') -Force

if (-not $TemplateUrl) {
    'configured=false' >> $env:GITHUB_OUTPUT
    Write-Host '::notice::No parent template configured. Nothing to sync.'
    exit 0
}

if (Test-TemplateUrl -TemplateUrl $TemplateUrl -Repository $Repository) {
    Write-Host '::error::template-url points at this repo. A base template has no parent to sync from.'
    exit 1
}

if (-not (Test-SyncStrategy -Strategy $Strategy)) {
    Write-Host "::error::strategy must be 'rebase' or 'merge', not '$Strategy'."
    exit 1
}

'configured=true' >> $env:GITHUB_OUTPUT
