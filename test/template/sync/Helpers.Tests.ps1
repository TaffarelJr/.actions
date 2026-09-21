#Requires -Version 7.0
<#
    Tests for template/sync's Helpers.psm1: validating configuration,
    deciding whether there is anything to sync, resolving the deletion
    side of a conflict, building the sync branch by rebase or merge,
    and the pull request that announces it.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:TESTKIT_PATH) { throw 'Run this file through powershell/test/Invoke-Tests.ps1' }
Import-Module $env:TESTKIT_PATH -Force
Import-SourceModule 'Helpers'

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '1. Test-TemplateUrl and Test-SyncStrategy'
#───────────────────────────────────────────────────────────────────────────────

# Act / Assert
Assert-That 'a url ending in this repo''s own name is rejected' `
    (Test-TemplateUrl -TemplateUrl 'https://github.com/owner/repo.git' -Repository 'owner/repo')
Assert-That 'a url naming a different repo is fine' `
    (-not (Test-TemplateUrl -TemplateUrl 'https://github.com/owner/.template.git' -Repository 'owner/repo'))
Assert-That 'rebase is a known strategy' (Test-SyncStrategy -Strategy 'rebase')
Assert-That 'merge is a known strategy' (Test-SyncStrategy -Strategy 'merge')
Assert-That 'anything else is not' (-not (Test-SyncStrategy -Strategy 'squash'))

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '2. Test-RefExists, Test-Ancestor, Get-MissingPatchCount, Test-SyncBranchCurrent'
#───────────────────────────────────────────────────────────────────────────────

$root = New-TestRoot -Name 'template-sync'
$repo1 = Join-Path $root 'plan'
$null = New-Item -ItemType Directory -Force -Path $repo1
Push-Location $repo1
try {
    git init -q -b base
    git config user.email 'test@example.test'
    git config user.name 'Test'
    Set-Content -LiteralPath 'file.txt' -Value 'v1'
    git add -A
    git commit -q -m 'chore: root'

    git branch upstream
    git checkout -q upstream
    Set-Content -LiteralPath 'file.txt' -Value 'v2'
    git commit -q -am 'feat: upstream change one'
    Set-Content -LiteralPath 'file.txt' -Value 'v3'
    git commit -q -am 'feat: upstream change two'
    git checkout -q base

    # Act / Assert
    Assert-That 'an existing branch is found' (Test-RefExists -Ref 'upstream')
    Assert-That 'a branch that was never created is not' (-not (Test-RefExists -Ref 'nope'))
    Assert-That 'base is an ancestor of upstream' (Test-Ancestor -Ancestor 'base' -Descendant 'upstream')
    Assert-That 'upstream is not an ancestor of base' (-not (Test-Ancestor -Ancestor 'upstream' -Descendant 'base'))
    Assert-Equal 'two patches are missing' 2 (Get-MissingPatchCount -Base 'base' -Upstream 'upstream')
    Assert-Equal 'a branch with nothing new has none missing' 0 (Get-MissingPatchCount -Base 'upstream' -Upstream 'upstream')

    # Arrange - a sync branch built on the current base, carrying every patch
    git checkout -q -b sync upstream
    git rebase -q base
    git checkout -q base

    # Act / Assert
    Assert-That 'a sync branch that is fully current is reported as such' `
        (Test-SyncBranchCurrent -Base 'base' -Upstream 'upstream' -SyncBranchRef 'sync')
    Assert-That 'a sync branch that does not exist is never current' `
        (-not (Test-SyncBranchCurrent -Base 'base' -Upstream 'upstream' -SyncBranchRef 'nope'))

    # Arrange - upstream moves again, so the sync branch is now stale
    git checkout -q upstream
    Set-Content -LiteralPath 'file.txt' -Value 'v4'
    git commit -q -am 'feat: upstream change three'
    git checkout -q base

    # Act / Assert
    Assert-That 'a sync branch missing a newer patch is no longer current' `
        (-not (Test-SyncBranchCurrent -Base 'base' -Upstream 'upstream' -SyncBranchRef 'sync'))
}
finally {
    Pop-Location
}

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '3. Test-PathAtRef, Test-PathChanged, Get-MergeBase, Get-RenamedFrom'
#───────────────────────────────────────────────────────────────────────────────

$repo2 = Join-Path $root 'paths'
$null = New-Item -ItemType Directory -Force -Path $repo2
Push-Location $repo2
try {
    git init -q -b merge-base
    git config user.email 'test@example.test'
    git config user.name 'Test'
    Set-Content -LiteralPath 'README.md' -Value 'template'
    Set-Content -LiteralPath 'old.txt' -Value 'content'
    Set-Content -LiteralPath 'old2.txt' -Value 'content2'
    Set-Content -LiteralPath 'gone.txt' -Value 'v1'
    git add -A
    git commit -q -m 'chore: root'
    $mergeBase = (git rev-parse HEAD).Trim()

    git branch base2
    git branch upstream2

    git checkout -q base2
    Set-Content -LiteralPath 'README.md' -Value 'ours'
    Set-Content -LiteralPath 'old.txt' -Value 'ours changed'
    git rm -q gone.txt
    git commit -q -am 'chore: base changes'

    git checkout -q upstream2
    Set-Content -LiteralPath 'README.md' -Value 'theirs'
    git mv old.txt new.txt
    git mv old2.txt new2.txt
    Set-Content -LiteralPath 'gone.txt' -Value 'theirs updated'
    git commit -q -am 'chore: upstream changes'

    git checkout -q base2

    # Act / Assert
    Assert-That 'README.md exists at base2' (Test-PathAtRef -Ref 'base2' -Path 'README.md')
    Assert-That 'gone.txt does not exist at base2' (-not (Test-PathAtRef -Ref 'base2' -Path 'gone.txt'))
    Assert-That 'old.txt changed between merge-base and base2' `
        (Test-PathChanged -FromRef $mergeBase -ToRef 'base2' -Path 'old.txt')
    Assert-That 'old2.txt did not' (-not (Test-PathChanged -FromRef $mergeBase -ToRef 'base2' -Path 'old2.txt'))
    Assert-Equal 'the merge-base is where the two sides last agreed' $mergeBase (Get-MergeBase -RefA 'base2' -RefB 'upstream2')
    Assert-Equal 'old.txt was renamed to new.txt on upstream' 'old.txt' `
        (Get-RenamedFrom -FromRef $mergeBase -ToRef 'upstream2' -Path 'new.txt')
    Assert-Equal 'a path that was not a rename target has no origin' '' `
        (Get-RenamedFrom -FromRef $mergeBase -ToRef 'upstream2' -Path 'gone.txt')

    #───────────────────────────────────────────────────────────────────────────
    Write-TestSection '4. Resolve-DeletionAction'
    #───────────────────────────────────────────────────────────────────────────

    # Act / Assert
    Assert-Equal 'a path in KeepOurs is kept, before anything else is checked' 'KeepOurs' `
        (Resolve-DeletionAction -Path 'README.md' -KeepOurs @('README.md') -Base 'base2' -Upstream 'upstream2' -MergeBase $mergeBase)
    Assert-Equal 'a path still present in base is a real conflict' 'LeaveForHuman' `
        (Resolve-DeletionAction -Path 'README.md' -KeepOurs @() -Base 'base2' -Upstream 'upstream2' -MergeBase $mergeBase)
    Assert-Equal 'a rename paired with a path that diverged in base is left for a human' 'LeaveForHuman' `
        (Resolve-DeletionAction -Path 'new.txt' -KeepOurs @() -Base 'base2' -Upstream 'upstream2' -MergeBase $mergeBase)
    Assert-Equal 'a rename paired with a path unchanged in base is a safe delete' 'Delete' `
        (Resolve-DeletionAction -Path 'new2.txt' -KeepOurs @() -Base 'base2' -Upstream 'upstream2' -MergeBase $mergeBase)
    Assert-Equal 'a plain deletion with no rename involved is a safe delete' 'Delete' `
        (Resolve-DeletionAction -Path 'gone.txt' -KeepOurs @() -Base 'base2' -Upstream 'upstream2' -MergeBase $mergeBase)
}
finally {
    Pop-Location
}

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '5. Get-UnmergedPath, Resolve-Deletion, Sync-RebaseBranch, Sync-MergeBranch'
#───────────────────────────────────────────────────────────────────────────────

function New-ConflictRepo {
    <#
    .SYNOPSIS
        Builds a fresh scratch repo with a base and an upstream branch
        that conflict on a kept-ours file and on a plain deletion, and
        returns its path.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $null = New-Item -ItemType Directory -Force -Path $Path
    Push-Location $Path
    try {
        git init -q -b base3
        git config user.email 'test@example.test'
        git config user.name 'Test'
        Set-Content -LiteralPath 'README.md' -Value 'template'
        Set-Content -LiteralPath 'other.txt' -Value 'v1'
        git add -A
        git commit -q -m 'chore: root'

        git branch upstream3
        Set-Content -LiteralPath 'README.md' -Value 'ours'
        git rm -q other.txt
        git commit -q -am 'chore: base changes'

        git checkout -q upstream3
        Set-Content -LiteralPath 'README.md' -Value 'theirs'
        Set-Content -LiteralPath 'other.txt' -Value 'v2'
        git commit -q -am 'chore: upstream changes'

        git checkout -q base3
    }
    finally {
        Pop-Location
    }
}

$rebaseRepo = Join-Path $root 'rebase-conflict'
New-ConflictRepo -Path $rebaseRepo
Push-Location $rebaseRepo
try {
    $result = Sync-RebaseBranch -SyncBranch 'template-sync' -Base 'base3' -Upstream 'upstream3' `
        -MergeBase (Get-MergeBase -RefA 'base3' -RefB 'upstream3') -KeepOurs @('README.md')

    # Assert
    Assert-That 'both conflicts resolve automatically, nothing left for a human' (-not $result.Conflict)
    Assert-Equal 'README.md was kept as ours' 'README.md' ($result.Kept -join ',')
    Assert-Equal 'other.txt was deleted' 'other.txt' ($result.Deleted -join ',')
    Assert-Equal 'README.md keeps this repo''s own content' 'ours' (Get-Content -LiteralPath 'README.md' -Raw).Trim()
    Assert-That 'other.txt is gone from the working tree' (-not (Test-Path -LiteralPath 'other.txt'))
}
finally {
    Pop-Location
}

$mergeRepo = Join-Path $root 'merge-conflict'
New-ConflictRepo -Path $mergeRepo
Push-Location $mergeRepo
try {
    $result = Sync-MergeBranch -SyncBranch 'template-sync' -Base 'base3' -Upstream 'upstream3' `
        -MergeBase (Get-MergeBase -RefA 'base3' -RefB 'upstream3') -KeepOurs @('README.md')

    # Assert
    Assert-That 'both conflicts resolve automatically, nothing left for a human' (-not $result.Conflict)
    Assert-Equal 'README.md was kept as ours' 'README.md' ($result.Kept -join ',')
    Assert-Equal 'other.txt was deleted' 'other.txt' ($result.Deleted -join ',')
    Assert-Equal 'the merge itself is recorded as a commit' 2 `
        (@(git log --oneline -2 --format='%H') | Measure-Object).Count
}
finally {
    Pop-Location
}

$cleanRepo = Join-Path $root 'merge-clean'
$null = New-Item -ItemType Directory -Force -Path $cleanRepo
Push-Location $cleanRepo
try {
    git init -q -b base4
    git config user.email 'test@example.test'
    git config user.name 'Test'
    Set-Content -LiteralPath 'file.txt' -Value 'v1'
    git add -A
    git commit -q -m 'chore: root'

    git branch upstream4
    Set-Content -LiteralPath 'ours-only.txt' -Value 'added by us'
    git add -A
    git commit -q -am 'chore: base adds its own file'

    git checkout -q upstream4
    Set-Content -LiteralPath 'theirs-only.txt' -Value 'added by the template'
    git add -A
    git commit -q -am 'chore: upstream adds its own file'
    git checkout -q base4

    # Act - two different new files, nothing for either side to conflict over
    $clean = Sync-MergeBranch -SyncBranch 'template-sync' -Base 'base4' -Upstream 'upstream4' `
        -MergeBase (Get-MergeBase -RefA 'base4' -RefB 'upstream4') -KeepOurs @('README.md')

    # Assert
    Assert-That 'a clean merge reports no conflict' (-not $clean.Conflict)
    Assert-Equal 'nothing was kept' 0 $clean.Kept.Count
    Assert-Equal 'nothing was deleted' 0 $clean.Deleted.Count
    Assert-That 'both files landed' `
        ((Test-Path -LiteralPath 'ours-only.txt') -and (Test-Path -LiteralPath 'theirs-only.txt'))
}
finally {
    Pop-Location
}

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '6. Remove-UnwantedScripts'
#───────────────────────────────────────────────────────────────────────────────

$scriptsRepo = Join-Path $root 'scripts-cleanup'
$null = New-Item -ItemType Directory -Force -Path $scriptsRepo
Push-Location $scriptsRepo
try {
    git init -q -b main
    git config user.email 'test@example.test'
    git config user.name 'Test'
    Set-Content -LiteralPath 'file.txt' -Value 'v1'
    git add -A
    git commit -q -m 'chore: root'

    # Act / Assert - this repo already had its own scripts/, so nothing is removed
    $null = New-Item -ItemType Directory -Force -Path 'scripts'
    Set-Content -LiteralPath 'scripts/existing.ps1' -Value '# already ours'
    git add -A
    git commit -q -m 'chore: had scripts already'
    Assert-That 'a repo that already had scripts/ keeps it' (-not (Remove-UnwantedScripts -HadScripts $true))
    Assert-That 'scripts/ is still there' (Test-Path -LiteralPath 'scripts')

    # Arrange - a leaf with no scripts/ of its own, until the parent just added one
    git rm -rq scripts
    git commit -q -m 'chore: back to no scripts'

    $null = New-Item -ItemType Directory -Force -Path 'scripts'
    Set-Content -LiteralPath 'scripts/new.ps1' -Value '# from the parent'
    git add -A
    git commit -q -m 'chore: parent added scripts'

    # Act
    $removed = Remove-UnwantedScripts -HadScripts $false

    # Assert
    Assert-That 'a leaf with none of its own has the new scripts/ removed' $removed
    Assert-That 'scripts/ is gone from the working tree' (-not (Test-Path -LiteralPath 'scripts'))
    Assert-Equal 'the removal amended the commit rather than adding a new one' 4 `
        (@(git log --oneline --format='%H') | Measure-Object).Count
}
finally {
    Pop-Location
}

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '7. Get-SyncPullRequestBody'
#───────────────────────────────────────────────────────────────────────────────

# Act
$clean = Get-SyncPullRequestBody -Missing 3 -TemplateUrl 'https://github.test/owner/.template' `
    -Strategy 'rebase' -Conflict $false
$withConflict = Get-SyncPullRequestBody -Missing 1 -TemplateUrl 'https://github.test/owner/.template' `
    -Strategy 'merge' -Conflict $true
$withNotes = Get-SyncPullRequestBody -Missing 2 -TemplateUrl 'https://github.test/owner/.template' `
    -Strategy 'rebase' -Conflict $false -Deleted 'a.txt b.txt' -KeptOurs 'README.md'

# Assert
Assert-That 'names how many patches and the strategy' ($clean -match 'Automated sync of 3 patch\(es\).*via `rebase`')
Assert-That 'a clean sync says so' ($clean -match 'Applied cleanly')
Assert-That 'a conflicted sync warns instead' ($withConflict -match 'must be resolved')
Assert-That 'deleted paths are reported when there are any' ($withNotes -match 'a\.txt b\.txt')
Assert-That 'kept paths are reported when there are any' ($withNotes -match 'README\.md')
Assert-That 'a clean sync with nothing deleted or kept omits both notes' `
    (($clean -notmatch 'Left deleted') -and ($clean -notmatch 'Kept this repo'))

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '8. Find-OpenSyncPullRequest, Set-SyncPullRequest, Set-SyncPullRequestLabel'
#───────────────────────────────────────────────────────────────────────────────

# Arrange - no open pull request yet
Set-GhStub -Handler { param($ArgList) @{ Exit = 0; Out = @('') } }

# Act
$none = Find-OpenSyncPullRequest -Repository 'owner/repo' -SyncBranch 'template-sync'

# Assert
Assert-Equal 'no open pull request means empty' '' $none

# Arrange - creating one for the first time
Set-GhStub -Handler {
    param($ArgList)
    if ($ArgList -contains 'create') { return @{ Exit = 0 } }
    @{ Exit = 0; Out = @('42') }
}

# Act
$created = Set-SyncPullRequest -Repository 'owner/repo' -BaseBranch 'main' -SyncBranch 'template-sync' `
    -Title 'Merge changes from template repo' -Body 'body text' -ExistingNumber ''

# Assert
Assert-Equal 'returns the number of the pull request just created' '42' $created
Assert-That 'created against the right base and head' (Test-GhCall 'pr create.*--base main.*--head template-sync')
Assert-That 'labeled as a template sync' (Test-GhCall 'pr create.*--label template sync')

# Arrange - updating an existing one
Set-GhStub -Handler { param($ArgList) @{ Exit = 0 } }

# Act
$updated = Set-SyncPullRequest -Repository 'owner/repo' -BaseBranch 'main' -SyncBranch 'template-sync' `
    -Title 'Merge changes from template repo' -Body 'new body' -ExistingNumber '42'

# Assert
Assert-Equal 'returns the same number, unchanged' '42' $updated
Assert-That 'edits the existing pull request rather than creating another' (Test-GhCall 'pr edit 42.*--title')
Assert-That 'never calls create when one already exists' (-not (Test-GhCall 'pr create'))

# Arrange / Act / Assert - the label follows whether there is a conflict
Set-GhStub -Handler { param($ArgList) @{ Exit = 0 } }
Set-SyncPullRequestLabel -Repository 'owner/repo' -Number '42' -Conflict $true
Assert-That 'a conflict adds the needs-fix label' (Test-GhCall 'pr edit 42.*--add-label needs fix')

Set-GhStub -Handler { param($ArgList) @{ Exit = 0 } }
Set-SyncPullRequestLabel -Repository 'owner/repo' -Number '42' -Conflict $false
Assert-That 'a clean sync removes it instead' (Test-GhCall 'pr edit 42.*--remove-label needs fix')

exit (Complete-TestRun)
