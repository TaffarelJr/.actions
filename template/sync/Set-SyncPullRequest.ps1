#Requires -Version 7.0

<#
.SYNOPSIS
    Creates or updates the pull request announcing a template sync, and
    labels it to match whether it needs a conflict resolved.

.PARAMETER Repository
    owner/repo to open the pull request in.

.PARAMETER BaseBranch
    Branch the pull request merges into.

.PARAMETER SyncBranch
    Branch the pull request is opened from.

.PARAMETER TemplateUrl
    Clone URL of the parent template, reported in the body.

.PARAMETER Strategy
    'rebase' or 'merge', reported in the body.

.PARAMETER Conflict
    Whether the sync left conflict markers needing resolution.

.PARAMETER Deleted
    Paths kept out of this repo rather than landing from the sync, for
    the body.

.PARAMETER KeptOurs
    Paths where this repo's own version always wins, for the body.

.PARAMETER Missing
    How many patches the parent held that this repo did not, for the
    body.

.PARAMETER Token
    Token used to create or edit the pull request.

.EXAMPLE
    ./template/sync/Set-SyncPullRequest.ps1 -Repository owner/repo -BaseBranch main -SyncBranch template-sync -TemplateUrl https://github.com/owner/.template -Strategy rebase -Conflict $false -Missing 3 -Token $token
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$BaseBranch,
    [Parameter(Mandatory)][string]$SyncBranch,
    [Parameter(Mandatory)][string]$TemplateUrl,
    [Parameter(Mandatory)][string]$Strategy,
    [Parameter(Mandatory)][bool]$Conflict,
    [string]$Deleted = '',
    [string]$KeptOurs = '',
    [Parameter(Mandatory)][int]$Missing,
    [Parameter(Mandatory)][string]$Token
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:GH_TOKEN = $Token

Import-Module (Join-Path $PSScriptRoot 'Helpers.psm1') -Force

$title = 'Merge changes from template repo'
$body = Get-SyncPullRequestBody -Missing $Missing -TemplateUrl $TemplateUrl -Strategy $Strategy `
    -Conflict $Conflict -Deleted $Deleted -KeptOurs $KeptOurs

$existing = Find-OpenSyncPullRequest -Repository $Repository -SyncBranch $SyncBranch
$number = Set-SyncPullRequest -Repository $Repository -BaseBranch $BaseBranch -SyncBranch $SyncBranch `
    -Title $title -Body $body -ExistingNumber $existing
Set-SyncPullRequestLabel -Repository $Repository -Number $number -Conflict $Conflict

Write-Host "::notice::Pull request #$number is ready for review."
