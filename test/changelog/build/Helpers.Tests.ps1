#Requires -Version 7.0
<#
    Tests for changelog/build's Helpers.psm1: parsing commits, grouping
    them, rendering the notes, and reading tags and history from a real
    git repo.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:TESTKIT_PATH) { throw 'Run this file through powershell/test/Invoke-Tests.ps1' }
Import-Module $env:TESTKIT_PATH -Force
Import-SourceModule 'Helpers'

$tasks = Get-Module Helpers

function New-Commit {
    <#
    .SYNOPSIS
        Builds a parsed-commit object the way ConvertTo-ParsedCommit would.
    #>
    param(
        [string]$Type = '',
        [string]$Scope = '',
        [string]$Description = 'did a thing',
        [string]$Body = '',
        [bool]$Breaking = $false,
        [bool]$Merge = $false,
        [string]$Sha = 'abcdef0123456789abcdef0123456789abcdef01'
    )

    return [pscustomobject]@{
        Sha         = $Sha
        Type        = $Type
        Scope       = $Scope
        Description = $Description
        Body        = $Body
        IsBreaking  = $Breaking
        IsMerge     = $Merge
    }
}

function Invoke-Commit {
    <#
    .SYNOPSIS
        Makes an empty commit with the given subject and optional body, and
        returns its sha.
    #>
    param(
        [Parameter(Mandatory)][string]$Subject,
        [string]$Body = ''
    )

    if ($Body) { git commit --allow-empty -q -m $Subject -m $Body }
    else { git commit --allow-empty -q -m $Subject }
    return (git rev-parse HEAD).Trim()
}

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '1. ConvertTo-ParsedCommit'
#───────────────────────────────────────────────────────────────────────────────

# Act
$scoped = ConvertTo-ParsedCommit -Sha 'a' -Subject 'feat(api): add the thing'
$bang = ConvertTo-ParsedCommit -Sha 'b' -Subject 'fix!: drop the old flag'
$footer = ConvertTo-ParsedCommit -Sha 'c' -Subject 'refactor: move it' `
    -Body "Some detail.`n`nBREAKING CHANGE: the path changed"
$plain = ConvertTo-ParsedCommit -Sha 'd' -Subject 'Fixed a typo in the README'
$merge = ConvertTo-ParsedCommit -Sha 'e' -Subject "Merge pull request #7 from o/topic"
$loud = ConvertTo-ParsedCommit -Sha 'f' -Subject 'DOCS:   explain   it  '

# Assert
Assert-Equal 'type is read' 'feat' $scoped.Type
Assert-Equal 'scope is read' 'api' $scoped.Scope
Assert-Equal 'description is read' 'add the thing' $scoped.Description
Assert-That 'no bang, no footer means not breaking' (-not $scoped.IsBreaking)

Assert-That 'a bang marks it breaking' $bang.IsBreaking
Assert-Equal 'the bang is not part of the scope' '' $bang.Scope

Assert-That 'a BREAKING CHANGE footer marks it breaking' $footer.IsBreaking
Assert-Equal 'the body is kept' "Some detail.`n`nBREAKING CHANGE: the path changed" $footer.Body

Assert-Equal 'a non-conventional subject has no type' '' $plain.Type
Assert-Equal 'and keeps its whole subject as the description' 'Fixed a typo in the README' `
    $plain.Description
Assert-That 'and is not a merge' (-not $plain.IsMerge)

Assert-That 'a merge subject is flagged' $merge.IsMerge

Assert-Equal 'the type is lowercased' 'docs' $loud.Type
Assert-Equal 'surrounding whitespace is trimmed' 'explain   it' $loud.Description

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '2. Get-CategoryGroup'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$shaA = 'a' * 40
$shaC = 'c' * 40
$shaD = 'd' * 40
$commits = @(
    (New-Commit -Type 'feat' -Description 'a feature' -Breaking $true -Sha $shaA)
    (New-Commit -Type 'fix' -Description 'a fix' -Sha ('b' * 40))
    (New-Commit -Type 'wip' -Description 'an unknown type' -Sha $shaC)
    (New-Commit -Description 'no type at all' -Sha $shaD)
    (New-Commit -Type 'docs' -Description 'some docs' -Sha ('e' * 40))
)

# Act
$groups = Get-CategoryGroup -Commits $commits

# Assert
Assert-Equal 'categories come out in the configured order' 'break,feat,fix,docs,other' `
    (@($groups.Keys) -join ',')
Assert-Equal 'break is a view, so the breaking feature is also under feat' $shaA `
    $groups['feat'].Commits[0].Sha
Assert-Equal 'and appears under break too' $shaA $groups['break'].Commits[0].Sha
Assert-That 'break is the only note category' `
    ($groups['break'].IsNote -and -not $groups['feat'].IsNote)
Assert-Equal 'other sweeps up the unknown type and the untyped commit' "$shaC,$shaD" `
    (@($groups['other'].Commits.Sha) -join ',')
Assert-Equal 'every non-breaking commit is listed exactly once' 5 `
    (@($groups.Values | Where-Object { -not $_.IsNote } | ForEach-Object { $_.Commits }).Count)

# Act
$empty = Get-CategoryGroup -Commits @()

# Assert
Assert-Equal 'no commits means no groups' 0 $empty.Count

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '3. Get-CountSentence'
#───────────────────────────────────────────────────────────────────────────────

# Act
$one = Get-CountSentence -Commits @((New-Commit -Type 'feat'))
$many = Get-CountSentence -Commits @(
    (New-Commit -Type 'feat' -Breaking $true)
    (New-Commit -Type 'feat')
    (New-Commit -Type 'fix')
    (New-Commit -Type 'fix')
    (New-Commit -Type 'docs')
)
$none = Get-CountSentence -Commits @()

# Assert
Assert-Equal 'one feature reads singular' '1 commits: 1 new feature.' $one
Assert-Equal 'breaking is bolded and counted apart from its own type' `
    '5 commits: **1 breaking**, 2 new features, 2 bug fixes, 1 other change.' $many
Assert-Equal 'no commits means no sentence' '' $none

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '4. Get-ScopeBadge'
#───────────────────────────────────────────────────────────────────────────────

# Act
$unscoped = & $tasks { param($c) Get-ScopeBadge -Commit $c } (New-Commit)
$scoped = & $tasks { param($c) Get-ScopeBadge -Commit $c } (New-Commit -Scope 'my-scope')
$again = & $tasks { param($c) Get-ScopeBadge -Commit $c } (New-Commit -Scope 'my-scope')

# Assert
Assert-Equal 'no scope, no badge' '' $unscoped
Assert-That 'a scope becomes a shields.io badge' `
    ($scoped -match '^!\[my-scope\]\(https://img\.shields\.io/badge/my--scope-[0-9A-F]{6}\?style=flat-square\) $') `
    $scoped
Assert-Equal 'the same scope always gets the same colour' $scoped $again

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '5. Get-BreakingDetail'
#───────────────────────────────────────────────────────────────────────────────

# Act
$detail = & $tasks { param($c) Get-BreakingDetail -Commit $c } `
    (New-Commit -Body "BREAKING CHANGE:  the   path`nmoved`n`nUnrelated trailer.")
$dashed = & $tasks { param($c) Get-BreakingDetail -Commit $c } `
    (New-Commit -Body 'BREAKING-CHANGE: also counts')
$absent = & $tasks { param($c) Get-BreakingDetail -Commit $c } (New-Commit -Body 'just a body')

# Assert
Assert-Equal 'the footer text is quoted with its whitespace collapsed' '  > the path moved' $detail
Assert-Equal 'the dashed spelling is accepted' '  > also counts' $dashed
Assert-Equal 'no footer, no detail' '' $absent

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '6. Get-CommitLine'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$render = { param($c, $k, $r) Get-CommitLine -Commit $c -CategoryKey $k -Repository $r }
$fix = New-Commit -Type 'fix' -Description 'patch it' -Sha 'abcdef0123456789abcdef0123456789abcdef01'

# Act
$linked = & $tasks $render $fix 'fix' 'o/r'
$unlinked = & $tasks $render $fix 'fix' ''
$inOther = & $tasks $render $fix 'other' 'o/r'
$breaking = & $tasks $render (New-Commit -Type 'feat' -Description 'x' -Breaking $true) 'feat' 'o/r'
$inBreak = & $tasks $render (New-Commit -Type 'feat' -Description 'x' -Breaking $true) 'break' 'o/r'

# Assert
Assert-Equal 'links to the commit when the repo is known' `
    '- patch it ([`abcdef0`](https://github.com/o/r/commit/abcdef0123456789abcdef0123456789abcdef01))' `
    $linked
Assert-Equal 'shows only the short sha otherwise' '- patch it (`abcdef0`)' $unlinked
Assert-That 'the type is stated in the catch-all section' ($inOther -like '- **fix**: patch it*')
Assert-That 'a breaking commit gets the marker in its own section' ($breaking -like '*x 💥 (*')
Assert-That 'but not in the breaking section, where it is implied' ($inBreak -notlike '*💥*')

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '7. Format-ReleaseNote'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$commits = @(
    (New-Commit -Type 'feat' -Description 'the big one' -Breaking $true -Sha ('a' * 40) `
        -Body 'BREAKING CHANGE: it changed')
    (New-Commit -Type 'fix' -Description 'a fix' -Sha ('b' * 40))
)
$tagged = [pscustomobject]@{ Tag = 'v1.4.0'; Version = $null; Sha = 'x'; LinkFrom = 'v1.4.0' }
$rootSha = '0123456789abcdef0123456789abcdef01234567'
$first = [pscustomobject]@{ Tag = $null; Version = $null; Sha = $null; LinkFrom = $rootSha }

# Act
$body = Format-ReleaseNote -Version '1.5.0' -Commits $commits -Baseline $tagged -Repository 'o/r'
$summarized = Format-ReleaseNote -Version '1.5.0' -Commits $commits -Baseline $tagged `
    -Repository 'o/r' -Summary "  Ship it.  "
$initial = Format-ReleaseNote -Version '1.0.0' -Commits $commits -Baseline $first -Repository 'o/r'
$local = Format-ReleaseNote -Version '1.5.0' -Commits $commits -Baseline $tagged

# Assert
Assert-Equal 'without a summary the notes open with the placeholder' `
    '<!-- Write the highlights here: what changed and why it matters. -->' $body[0]
Assert-Equal 'with one, the trimmed summary opens them' 'Ship it.' $summarized[0]
Assert-That 'the count sentence follows' ($body -contains '2 commits: **1 breaking**, 1 new feature, 1 bug fix.')
Assert-That 'breaking changes are a visible heading' ($body -contains '## 💥 Breaking Changes')
Assert-That 'with the footer quoted under the commit' ($body -contains '  > it changed')
Assert-That 'the rest is folded' (($body -contains '<details>') -and ($body -contains '</details>'))
Assert-That 'under a summary tag that counts the commits' `
    ($body -contains '<summary>📋 <b>Full changelog</b> (2 commits)</summary>')
Assert-Equal 'a previous tag gives a tag-to-tag compare link' `
    '**Full Changelog**: [v1.4.0...v1.5.0](https://github.com/o/r/compare/v1.4.0...v1.5.0)' `
    $body[-1]
Assert-Equal 'a first release compares from the root commit, labelled short' `
    "**Full Changelog**: [0123456...v1.0.0](https://github.com/o/r/compare/$rootSha...v1.0.0)" `
    $initial[-1]
Assert-That 'no repository means no link at all' (-not ($local -match 'Full Changelog\*\*'))

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '8. Tags and history, against a real repo'
#───────────────────────────────────────────────────────────────────────────────

# Arrange - a linear history with real release tags and the alias tags a
# consumer pins, plus an unrelated branch carrying the numerically newest tag.
$repo = New-TestRoot -Name 'changelog'
Push-Location $repo
try {
    git init -q -b main
    git config core.autocrlf false
    git config user.email 'tests@example.com'
    git config user.name 'Tests'

    $root = Invoke-Commit 'chore: root'
    git tag v1
    $second = Invoke-Commit 'feat(api): add thing'
    git tag v1.0.0
    $third = Invoke-Commit 'fix: patch it' -Body 'BREAKING CHANGE: the api moved'
    git tag v9.0.0
    $fourth = Invoke-Commit 'docs: explain'
    git tag v10.0.0
    git tag v10.0
    $head = Invoke-Commit 'chore: latest'

    git checkout -q -b side $root
    $null = Invoke-Commit 'feat: elsewhere'
    git tag v50.0.0
    git checkout -q main

    # Act
    $tags = Get-VersionTag

    # Assert
    Assert-Equal 'only vX.Y.Z tags count, newest version first' 'v50.0.0,v10.0.0,v9.0.0,v1.0.0' `
        (@($tags.Tag) -join ',')
    Assert-That 'v10 sorts above v9, by version not by name' `
        (@($tags.Tag).IndexOf('v10.0.0') -lt @($tags.Tag).IndexOf('v9.0.0'))
    Assert-Equal 'each tag resolves to its commit' $fourth $tags[1].Sha

    # Act
    $baseline = Get-ChangelogBaseline -HeadSha $head

    # Assert
    Assert-Equal 'the baseline is the newest tag that is an ancestor' 'v10.0.0' $baseline.Tag
    Assert-Equal 'so the numerically newer tag on the side branch is skipped' $fourth $baseline.Sha
    Assert-Equal 'and the compare link starts from that tag' 'v10.0.0' $baseline.LinkFrom

    # Arrange
    git tag v11.0.0

    # Act
    $atHead = Get-ChangelogBaseline -HeadSha $head

    # Assert
    Assert-Equal 'a tag already at HEAD is skipped, so a re-run gets full notes' 'v10.0.0' $atHead.Tag
    git tag -d v11.0.0 | Out-Null

    # Act
    $named = Get-ChangelogBaseline -HeadSha $head -FromTag 'v1.0.0'

    # Assert
    Assert-Equal 'FromTag picks that tag' 'v1.0.0' $named.Tag
    Assert-Equal 'with its commit' $second $named.Sha
    Assert-Throws 'an unknown FromTag throws' { Get-ChangelogBaseline -HeadSha $head -FromTag 'v0.0.9' } `
        -Match "was not found"

    # Assert
    Assert-That 'the root is an ancestor of HEAD' (Test-AncestorCommit -Sha $root -OfSha $head)
    Assert-That 'HEAD is not an ancestor of the root' (-not (Test-AncestorCommit -Sha $head -OfSha $root))
    Assert-That 'a commit is its own ancestor' (Test-AncestorCommit -Sha $head -OfSha $head)

    # Act
    $all = Get-ChangelogCommit -StartSha $null -EndSha $head
    $since = Get-ChangelogCommit -StartSha $second -EndSha $head

    # Assert
    Assert-Equal 'no start means all of history, root included' 5 $all.Count
    Assert-Equal 'in commit order, oldest first' 'chore: root' "$($all[0].Type): $($all[0].Description)"
    Assert-Equal 'a start sha is exclusive' 3 $since.Count
    Assert-Equal 'starting right after it' $third $since[0].Sha
    Assert-That 'the body is carried, so the footer is seen' $since[0].IsBreaking
    Assert-Equal 'and the scope is parsed' 'api' $all[1].Scope

    # Act
    $none = Get-ChangelogCommit -StartSha $head -EndSha $head

    # Assert
    Assert-Equal 'no commits in range means an empty list' 0 $none.Count

    # Arrange
    git checkout -q -b topic
    $null = Invoke-Commit 'feat: topic work'
    git checkout -q main
    git merge -q --no-ff -m "Merge branch 'topic'" topic
    $merged = (git rev-parse HEAD).Trim()

    # Act
    $afterMerge = Get-ChangelogCommit -StartSha $head -EndSha $merged

    # Assert
    Assert-Equal 'the merge commit itself is dropped, its work is kept' 'topic work' `
        (@($afterMerge.Description) -join ',')

    # Arrange - a blank line between paragraphs is a genuine element of git
    # log's raw output array, not an absent one.
    $paragraphs = Invoke-Commit 'chore: two paragraphs' -Body "First paragraph.`n`nSecond paragraph."

    # Act
    $withBlankLine = Get-ChangelogCommit -StartSha $merged -EndSha $paragraphs

    # Assert
    Assert-Equal 'a blank line inside a body does not break parsing' 1 $withBlankLine.Count
    Assert-Equal 'and the whole body, blank line included, is kept' "First paragraph.`n`nSecond paragraph." `
        $withBlankLine[0].Body
}
finally {
    Pop-Location
}

# Arrange
$bare = New-TestRoot -Name 'changelog-untagged'
Push-Location $bare
try {
    git init -q -b main
    git config core.autocrlf false
    git config user.email 'tests@example.com'
    git config user.name 'Tests'
    $first = Invoke-Commit 'chore: first'
    git tag v1
    $last = Invoke-Commit 'feat: second'

    # Act - wrapped, because the module returns unwrapped for its piping callers
    $none = @(Get-VersionTag)
    $fresh = Get-ChangelogBaseline -HeadSha $last

    # Assert
    Assert-Equal 'an alias tag alone is not a release' 0 $none.Count
    Assert-That 'so there is no tag to start after' ($null -eq $fresh.Tag -and $null -eq $fresh.Sha)
    Assert-Equal 'but the compare link still starts somewhere: the root commit' $first $fresh.LinkFrom
}
finally {
    Pop-Location
}

exit (Complete-TestRun)
