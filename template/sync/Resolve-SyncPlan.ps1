#Requires -Version 7.0

<#
.SYNOPSIS
    Decides whether there is anything to sync, and reports how many
    patches would come down.

.DESCRIPTION
    Compares by patch, not by commit id. Rebasing gives the parent's
    commits new ids on the way down, so asking "which commits are
    missing" would report the same work forever; asking "which patches
    are missing" is what actually converges.

.PARAMETER Remote
    Name of the parent's git remote.

.PARAMETER TemplateBranch
    Branch to sync from in the parent.

.PARAMETER BaseBranch
    Branch being synced into.

.PARAMETER SyncBranch
    Branch the pull request is opened from.

.PARAMETER Strategy
    Either 'rebase' or 'merge', reported in the notice only.

.EXAMPLE
    ./template/sync/Resolve-SyncPlan.ps1 -Remote template -TemplateBranch main -BaseBranch main -SyncBranch template-sync -Strategy rebase
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Remote,
    [Parameter(Mandatory)][string]$TemplateBranch,
    [Parameter(Mandatory)][string]$BaseBranch,
    [Parameter(Mandatory)][string]$SyncBranch,
    [Parameter(Mandatory)][string]$Strategy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Helpers.psm1') -Force

$upstream = "$Remote/$TemplateBranch"
$base = "origin/$BaseBranch"

$missing = Get-MissingPatchCount -Base $base -Upstream $upstream
"missing=$missing" >> $env:GITHUB_OUTPUT

if ($missing -eq 0) {
    'proceed=false' >> $env:GITHUB_OUTPUT
    Write-Host '::notice::Already carries every patch from the template.'
    exit 0
}

if (Test-SyncBranchCurrent -Base $base -Upstream $upstream -SyncBranchRef "origin/$SyncBranch") {
    'proceed=false' >> $env:GITHUB_OUTPUT
    Write-Host "::notice::The existing $SyncBranch branch is already current."
    exit 0
}

'proceed=true' >> $env:GITHUB_OUTPUT
Write-Host "::notice::$missing patch(es) to bring down via $Strategy."
