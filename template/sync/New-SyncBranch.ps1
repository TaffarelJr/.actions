#Requires -Version 7.0

<#
.SYNOPSIS
    Builds the sync branch by rebase or merge,
    resolving the deletion side of any conflict along the way,
    and reports what happened.

.DESCRIPTION
    This repo's own version of README.md and .github/settings.yml
    always wins over the parent's,
    because the answer never changes between syncs:
    settings.yml is a genuinely different document per repo,
    and README.md is split by design.
    Asking a human the same question every single sync gets nothing.

.PARAMETER Remote
    Name of the parent's git remote.

.PARAMETER TemplateBranch
    Branch to sync from in the parent.

.PARAMETER BaseBranch
    Branch being synced into.

.PARAMETER SyncBranch
    Branch to build.

.PARAMETER Strategy
    'rebase' replays the parent's commits so history stays linear;
    'merge' merges them in as one commit.

.EXAMPLE
    ./template/sync/New-SyncBranch.ps1 -Remote template -TemplateBranch main -BaseBranch main -SyncBranch template-sync -Strategy rebase
#>
using namespace System.Collections.Generic

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
$keepOurs = @('README.md', '.github/settings.yml')

# A leaf has no scripts/ of its own.
# Captured before the merge/rebase runs,
# so a new file the parent adds there
# can be told apart from one this repo already had.
$hadScripts = Test-PathAtRef -Ref $base -Path 'scripts'

# Needed to tell a real rename on the parent's side apart from a coincidence:
# the point in history the two sides last agreed on.
$mergeBase = Get-MergeBase -RefA $base -RefB $upstream

$result = if ($Strategy -eq 'rebase') {
    Sync-RebaseBranch -SyncBranch $SyncBranch -Base $base -Upstream $upstream -MergeBase $mergeBase -KeepOurs $keepOurs
}
else {
    Sync-MergeBranch -SyncBranch $SyncBranch -Base $base -Upstream $upstream -MergeBase $mergeBase -KeepOurs $keepOurs
}

$scriptsRemoved = Remove-UnwantedScripts -HadScripts $hadScripts

"conflict=$(([string]$result.Conflict).ToLower())" >> $env:GITHUB_OUTPUT

$deleted = [List[string]]::new()
$deleted.AddRange([string[]]$result.Deleted)
if ($scriptsRemoved) { $deleted.Add('scripts/') }
$deletedText = (@($deleted) | Sort-Object -Unique) -join ' '
if ($deletedText) {
    "deleted=$deletedText" >> $env:GITHUB_OUTPUT
    Write-Host "::notice::Kept deleted, as this repo already had: $deletedText"
}

$keptText = (@($result.Kept) | Sort-Object -Unique) -join ' '
if ($keptText) {
    "kept-ours=$keptText" >> $env:GITHUB_OUTPUT
    Write-Host "::notice::Kept this repo's own version, as always: $keptText"
}

if ($result.Conflict) {
    $conflictText = (@($result.ConflictPath) | Sort-Object -Unique) -join ' '
    Write-Host "::warning::Conflicts, committed as-is, in: $conflictText"
}
