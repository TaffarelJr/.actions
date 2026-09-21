#Requires -Version 7.0
<#
    The logic behind syncing a parent template's changes down: validating
    the configuration, deciding whether there is anything to bring down,
    building the sync branch (including resolving the deletion side of a
    conflict), and opening or updating the pull request.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#───────────────────────────────────────────────────────────────────────────────
# Configuration
#───────────────────────────────────────────────────────────────────────────────

function Test-TemplateUrl {
    <#
    .SYNOPSIS
        Returns whether a template URL points at this repo - meaning
        the caller inherited the workflow without retargeting it.
    #>
    param(
        [Parameter(Mandatory)][string]$TemplateUrl,
        [Parameter(Mandatory)][string]$Repository
    )

    $repoName = $Repository -replace '^[^/]+/', ''
    return $TemplateUrl.EndsWith("/$repoName.git")
}

function Test-SyncStrategy {
    <#
    .SYNOPSIS
        Returns whether a strategy name is one this action knows.
    #>
    param([Parameter(Mandatory)][string]$Strategy)

    return $Strategy -in 'rebase', 'merge'
}

#───────────────────────────────────────────────────────────────────────────────
# Deciding whether to proceed
#───────────────────────────────────────────────────────────────────────────────

function Test-RefExists {
    <#
    .SYNOPSIS
        Returns whether a ref exists in the current checkout.
    #>
    param([Parameter(Mandatory)][string]$Ref)

    git rev-parse --verify -q $Ref *> $null
    return $LASTEXITCODE -eq 0
}

function Test-Ancestor {
    <#
    .SYNOPSIS
        Returns whether Ancestor is an ancestor of (or equal to)
        Descendant.
    #>
    param(
        [Parameter(Mandatory)][string]$Ancestor,
        [Parameter(Mandatory)][string]$Descendant
    )

    git merge-base --is-ancestor $Ancestor $Descendant *> $null
    return $LASTEXITCODE -eq 0
}

function Get-MissingPatchCount {
    <#
    .SYNOPSIS
        Returns how many patches Upstream holds that Base does not, by
        patch content rather than commit id - a patch already on Base
        under a different id (e.g. after a rebase) does not count as
        missing.
    #>
    param(
        [Parameter(Mandatory)][string]$Base,
        [Parameter(Mandatory)][string]$Upstream
    )

    $lines = @(git cherry $Base $Upstream)
    return @($lines | Where-Object { $_ -match '^\+' }).Count
}

function Test-SyncBranchCurrent {
    <#
    .SYNOPSIS
        Returns whether an existing sync branch already carries every
        patch Base is missing and is built on the current Base - so
        rebuilding it would just repeat work and discard any conflict
        resolution someone already pushed to it.
    #>
    param(
        [Parameter(Mandatory)][string]$Base,
        [Parameter(Mandatory)][string]$Upstream,
        [Parameter(Mandatory)][string]$SyncBranchRef
    )

    if (-not (Test-RefExists -Ref $SyncBranchRef)) { return $false }
    if ((Get-MissingPatchCount -Base $SyncBranchRef -Upstream $Upstream) -ne 0) { return $false }
    return (Test-Ancestor -Ancestor $Base -Descendant $SyncBranchRef)
}

#───────────────────────────────────────────────────────────────────────────────
# Building the sync branch
#───────────────────────────────────────────────────────────────────────────────

function Test-PathAtRef {
    <#
    .SYNOPSIS
        Returns whether a path exists in the tree at a given ref.
    #>
    param(
        [Parameter(Mandatory)][string]$Ref,
        [Parameter(Mandatory)][string]$Path
    )

    git cat-file -e "${Ref}:${Path}" *> $null
    return $LASTEXITCODE -eq 0
}

function Test-PathChanged {
    <#
    .SYNOPSIS
        Returns whether a path differs between two refs.
    #>
    param(
        [Parameter(Mandatory)][string]$FromRef,
        [Parameter(Mandatory)][string]$ToRef,
        [Parameter(Mandatory)][string]$Path
    )

    git diff --quiet $FromRef $ToRef -- $Path *> $null
    return $LASTEXITCODE -ne 0
}

function Get-MergeBase {
    <#
    .SYNOPSIS
        Returns the point in history two refs last agreed on.
    #>
    param(
        [Parameter(Mandatory)][string]$RefA,
        [Parameter(Mandatory)][string]$RefB
    )

    return (git merge-base $RefA $RefB | Select-Object -Last 1)
}

function Get-UnmergedPath {
    <#
    .SYNOPSIS
        Returns every currently-conflicted path, always as an array.
    #>
    return , [string[]]@(git diff --name-only --diff-filter=U)
}

function Get-RenamedFrom {
    <#
    .SYNOPSIS
        Returns the path a file was renamed from, between two refs, or
        '' when it was not renamed there.
    #>
    param(
        [Parameter(Mandatory)][string]$FromRef,
        [Parameter(Mandatory)][string]$ToRef,
        [Parameter(Mandatory)][string]$Path
    )

    $lines = @(git diff --name-status -M --diff-filter=R $FromRef $ToRef)
    foreach ($line in $lines) {
        $fields = $line -split '\s+'
        if ($fields.Count -ge 3 -and $fields[2] -eq $Path) { return $fields[1] }
    }
    return ''
}

function Resolve-DeletionAction {
    <#
    .SYNOPSIS
        Decides what to do with one conflicted path during a sync: keep
        this repo's own version, treat it as a deletion this repo made
        on purpose, or leave it for a human to resolve.
    .DESCRIPTION
        A file this repo deliberately deleted, which the parent has
        since edited, conflicts on every single sync. The repo's answer
        is already on record - it is not in Base - so honour that
        instead of raising the same question forever. Anything still
        present in Base is a real conflict.

        A rename on the parent's side complicates that: git reports the
        conflict at the NEW path, so "is it in Base?" sees a path that
        never existed here and calls the delete safe - even if the
        parent's rename paired it with a path this repo already owns
        under the OLD name. If this repo's copy of that old name has
        diverged from the parent since they last shared history, the
        delete would erase content that only looks unfamiliar because
        of the rename, so that case is left for a human too.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$KeepOurs,
        [Parameter(Mandatory)][string]$Base,
        [Parameter(Mandatory)][string]$Upstream,
        [Parameter(Mandatory)][string]$MergeBase
    )

    if ($Path -in $KeepOurs) { return 'KeepOurs' }
    if (Test-PathAtRef -Ref $Base -Path $Path) { return 'LeaveForHuman' }

    $renamedFrom = Get-RenamedFrom -FromRef $MergeBase -ToRef $Upstream -Path $Path
    if ($renamedFrom `
            -and (Test-PathAtRef -Ref $Base -Path $renamedFrom) `
            -and (Test-PathChanged -FromRef $MergeBase -ToRef $Base -Path $renamedFrom)) {
        return 'LeaveForHuman'
    }

    return 'Delete'
}

function Resolve-Deletion {
    <#
    .SYNOPSIS
        Applies Resolve-DeletionAction's decision to every currently
        conflicted path, and returns which paths were kept as ours and
        which were treated as deletions. A path left for a human stays
        conflicted, in neither list.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$KeepOurs,
        [Parameter(Mandatory)][string]$Base,
        [Parameter(Mandatory)][string]$Upstream,
        [Parameter(Mandatory)][string]$MergeBase
    )

    $kept = [System.Collections.Generic.List[string]]::new()
    $deleted = [System.Collections.Generic.List[string]]::new()

    foreach ($path in (Get-UnmergedPath)) {
        $action = Resolve-DeletionAction -Path $path -KeepOurs $KeepOurs -Base $Base -Upstream $Upstream -MergeBase $MergeBase
        switch ($action) {
            'KeepOurs' {
                git checkout --ours -- $path *> $null
                git add -- $path *> $null
                $kept.Add($path)
            }
            'Delete' {
                git rm -q -f -- $path *> $null
                $deleted.Add($path)
            }
        }
    }

    return [pscustomobject]@{ KeptOurs = [string[]]$kept.ToArray(); Deleted = [string[]]$deleted.ToArray() }
}

function Sync-RebaseBranch {
    <#
    .SYNOPSIS
        Replays Upstream onto Base by rebase, resolving deletions at
        each conflict, and returns the result.
    .DESCRIPTION
        Rebase drops patches Base already has, so only genuinely new
        work lands, and the result stays linear.
    .OUTPUTS
        A pscustomobject with Conflict (bool), Kept and Deleted (the
        paths Resolve-Deletion resolved), and ConflictPath (whatever is
        still unmerged - left for a human).
    #>
    param(
        [Parameter(Mandatory)][string]$SyncBranch,
        [Parameter(Mandatory)][string]$Base,
        [Parameter(Mandatory)][string]$Upstream,
        [Parameter(Mandatory)][string]$MergeBase,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$KeepOurs
    )

    git checkout -B $SyncBranch $Upstream *> $null
    git rebase $Base *> $null

    $kept = [System.Collections.Generic.List[string]]::new()
    $deleted = [System.Collections.Generic.List[string]]::new()
    $conflictPath = [System.Collections.Generic.List[string]]::new()

    while ((Test-Path -LiteralPath '.git/rebase-merge') -or (Test-Path -LiteralPath '.git/rebase-apply')) {
        $resolution = Resolve-Deletion -KeepOurs $KeepOurs -Base $Base -Upstream $Upstream -MergeBase $MergeBase
        $kept.AddRange([string[]]$resolution.KeptOurs)
        $deleted.AddRange([string[]]$resolution.Deleted)
        $conflictPath.AddRange([string[]](Get-UnmergedPath))

        git add -A *> $null
        git -c core.editor=true rebase --continue *> $null
    }

    return [pscustomobject]@{
        Conflict     = ($conflictPath.Count -gt 0)
        Kept         = [string[]]$kept.ToArray()
        Deleted      = [string[]]$deleted.ToArray()
        ConflictPath = [string[]]$conflictPath.ToArray()
    }
}

function Sync-MergeBranch {
    <#
    .SYNOPSIS
        Merges Upstream into Base, resolving deletions on conflict, and
        returns the result.
    .OUTPUTS
        A pscustomobject with Conflict (bool), Kept and Deleted (the
        paths Resolve-Deletion resolved), and ConflictPath (whatever is
        still unmerged - left for a human).
    #>
    param(
        [Parameter(Mandatory)][string]$SyncBranch,
        [Parameter(Mandatory)][string]$Base,
        [Parameter(Mandatory)][string]$Upstream,
        [Parameter(Mandatory)][string]$MergeBase,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$KeepOurs
    )

    git checkout -B $SyncBranch $Base *> $null
    git merge --no-edit $Upstream *> $null

    if ($LASTEXITCODE -eq 0) {
        return [pscustomobject]@{
            Conflict     = $false
            Kept         = [string[]]@()
            Deleted      = [string[]]@()
            ConflictPath = [string[]]@()
        }
    }

    $resolution = Resolve-Deletion -KeepOurs $KeepOurs -Base $Base -Upstream $Upstream -MergeBase $MergeBase
    $conflictPath = Get-UnmergedPath

    # MERGE_HEAD is still set, so this keeps both parents and git records
    # that the merge happened. Left uncommitted, the next run would
    # attempt the same merge again.
    git add -A *> $null
    git -c core.editor=true commit --no-edit *> $null

    return [pscustomobject]@{
        Conflict     = ($conflictPath.Count -gt 0)
        Kept         = $resolution.KeptOurs
        Deleted      = $resolution.Deleted
        ConflictPath = $conflictPath
    }
}

function Remove-UnwantedScripts {
    <#
    .SYNOPSIS
        Removes a scripts/ folder the parent added, when this repo - a
        leaf - had none of its own before the sync, and amends it into
        the sync commit that just landed. Returns whether it did.
    .DESCRIPTION
        A file added under scripts/ merges in cleanly - Resolve-Deletion
        never sees it, because nothing conflicted. Swept up here
        instead, the same way a conflicted deletion already is, so "a
        leaf has no scripts/" stays true without a human having to
        notice the add.
    #>
    param([Parameter(Mandatory)][bool]$HadScripts)

    if ($HadScripts -or -not (Test-Path -LiteralPath 'scripts' -PathType Container)) {
        return $false
    }

    git rm -rq -- scripts *> $null
    git add -A *> $null
    git -c core.editor=true commit --amend --no-edit *> $null
    return $true
}

#───────────────────────────────────────────────────────────────────────────────
# The pull request
#───────────────────────────────────────────────────────────────────────────────

function Get-SyncPullRequestBody {
    <#
    .SYNOPSIS
        Builds the pull request body announcing a template sync.
    #>
    param(
        [Parameter(Mandatory)][int]$Missing,
        [Parameter(Mandatory)][string]$TemplateUrl,
        [Parameter(Mandatory)][string]$Strategy,
        [Parameter(Mandatory)][bool]$Conflict,
        [string]$Deleted = '',
        [string]$KeptOurs = ''
    )

    $note = if ($Conflict) {
        '⚠️ **Conflicts were committed as-is and must be resolved before merging.** See the job log for the file list.'
    }
    else {
        '✅ Applied cleanly.'
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add("Automated sync of $Missing patch(es) from ``$TemplateUrl`` via ``$Strategy``.")
    $parts.Add($note)
    if ($Deleted) { $parts.Add("Left deleted, because this repo had already removed them: ``$Deleted``") }
    if ($KeptOurs) { $parts.Add("Kept this repo's own version, as always: ``$KeptOurs``") }
    $parts.Add('This branch is rebuilt whenever either side moves, so it stays current until merged.')

    return ($parts -join "`n`n")
}

function Find-OpenSyncPullRequest {
    <#
    .SYNOPSIS
        Returns the number of the open pull request from a branch, or
        '' when there is none.
    #>
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$SyncBranch
    )

    return (gh pr list --repo $Repository --head $SyncBranch --state open --json number `
            --jq '.[0].number // empty' | Select-Object -Last 1)
}

function Set-SyncPullRequest {
    <#
    .SYNOPSIS
        Creates the sync pull request, or updates an existing one's
        title and body, and returns its number.
    #>
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$BaseBranch,
        [Parameter(Mandatory)][string]$SyncBranch,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Body,
        [AllowEmptyString()][string]$ExistingNumber = ''
    )

    if (-not $ExistingNumber) {
        gh pr create --repo $Repository --base $BaseBranch --head $SyncBranch `
            --title $Title --body $Body --label 'template sync' *> $null
        return (Find-OpenSyncPullRequest -Repository $Repository -SyncBranch $SyncBranch)
    }

    gh pr edit $ExistingNumber --repo $Repository --title $Title --body $Body *> $null
    return $ExistingNumber
}

function Set-SyncPullRequestLabel {
    <#
    .SYNOPSIS
        Adds or removes the 'needs fix' label to match whether the sync
        left a conflict.
    #>
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Number,
        [Parameter(Mandatory)][bool]$Conflict
    )

    if ($Conflict) {
        gh pr edit $Number --repo $Repository --add-label 'needs fix' *> $null
    }
    else {
        gh pr edit $Number --repo $Repository --remove-label 'needs fix' *> $null
    }
}

Export-ModuleMember -Function @(
    'Test-TemplateUrl'
    'Test-SyncStrategy'
    'Test-RefExists'
    'Test-Ancestor'
    'Get-MissingPatchCount'
    'Test-SyncBranchCurrent'
    'Test-PathAtRef'
    'Test-PathChanged'
    'Get-MergeBase'
    'Get-UnmergedPath'
    'Get-RenamedFrom'
    'Resolve-DeletionAction'
    'Resolve-Deletion'
    'Sync-RebaseBranch'
    'Sync-MergeBranch'
    'Remove-UnwantedScripts'
    'Get-SyncPullRequestBody'
    'Find-OpenSyncPullRequest'
    'Set-SyncPullRequest'
    'Set-SyncPullRequestLabel'
)
