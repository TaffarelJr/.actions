#Requires -Version 7.0
<#
    Reads git history and renders it as release notes.

    Everything here works from commits and tags alone, so it behaves the same
    in a .NET repo, a Node repo, or anything else.

    The output deliberately separates two different documents that are usually
    conflated:

      Release notes  what a reader needs to decide whether to upgrade. The
                     summary, the counts, and the breaking changes. Short, and
                     always visible.

      Changelog      the complete record of what changed, grouped by type.
                     Long, mechanical, and folded away behind a <details> so
                     it is available without burying the notes.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


#───────────────────────────────────────────────────────────────────────────────
# Configuration
#───────────────────────────────────────────────────────────────────────────────

# The Conventional Commit types, their display names, and the order they
# appear in - most important first. Keep in step with GitVersion.yml and
# docs/ConventionalCommits.md.
$script:Categories = [ordered]@{
    'break'    = '💥 Breaking Changes' # Aggregated, not a real type
    'revert'   = '↩️ Reverted Changes'
    'feat'     = '✨ New Features'
    'fix'      = '🪲 Bug Fixes'
    'perf'     = '⏱️ Performance Improvements'
    'refactor' = '🔄 Code Refactoring'
    'test'     = '🧪 Tests'
    'infra'    = '🛠️ Infrastructure'
    'build'    = '📦 Build System'
    'ci'       = '🤖 Continuous Integration'
    'docs'     = '📚 Documentation'
    'style'    = '🎨 Code Style'
    'chore'    = '🔧 Maintenance'
    'other'    = '📄 Other Changes'
}

# Breaking changes belong in the notes, not behind a fold: they are the one
# thing a reader must not miss.
$script:NoteCategories = @('break')

# A commit message can contain newlines, so JSON and line-oriented parsing
# both break on it. Delimit with characters no message will ever hold.
$script:CommitDelimiter = 'ↄ'
$script:FieldDelimiter = 'ⅎ'

# A scope renders as a shields.io badge, coloured from a hash of its own text
# so the same scope is always the same colour.
$script:BadgeStyle = 'flat-square'

#───────────────────────────────────────────────────────────────────────────────
# History
#───────────────────────────────────────────────────────────────────────────────

function Get-VersionTag {
    <#
    .SYNOPSIS
        Lists the release tags, newest version first.
    .DESCRIPTION
        Sorts by parsed SemVer rather than by date or by name, so v10.0.0
        sorts above v9.0.0 and a re-tagged commit cannot reorder the list.

        Only a strict 'vX.Y.Z' shape counts - [SemanticVersion]::TryParse
        also accepts 'v1' and 'v1.2', which would otherwise let the floating
        major/minor alias tags masquerade as releases and pick the wrong
        baseline.

        No leading comma on the return, unlike this repo's usual array-safe
        convention - every caller pipes this into Where-Object for per-tag
        filtering, and a comma-wrapped array arrives there as one object
        instead of enumerating, breaking .Tag/.Sha access on it entirely.
    #>
    $tags = @(git tag --list 'v*') | Where-Object { $_ -match '^v\d+\.\d+\.\d+$' }

    $parsed = foreach ($tag in $tags) {
        $candidate = $tag -replace '^v', ''
        $semver = $null
        if (-not [System.Management.Automation.SemanticVersion]::TryParse(
                $candidate, [ref]$semver)) {
            continue
        }

        [pscustomobject]@{
            Tag     = $tag
            Version = $semver
            Sha     = (git rev-list -n 1 $tag).Trim()
        }
    }

    return @($parsed | Sort-Object -Property Version -Descending)
}

function Test-AncestorCommit {
    <#
    .SYNOPSIS
        Returns whether Sha is an ancestor of (or equal to) OfSha.
    #>
    param(
        [Parameter(Mandatory)][string]$Sha,
        [Parameter(Mandatory)][string]$OfSha
    )

    git merge-base --is-ancestor $Sha $OfSha 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Get-ChangelogBaseline {
    <#
    .SYNOPSIS
        Finds the commit the notes should start after.
    .DESCRIPTION
        Normally the previous release tag. With no tags at all, a null Sha,
        meaning "all of history" - so an initial release still gets full
        notes including the root commit, which a range would exclude.

        Only a tag that is actually an ancestor of HeadSha is eligible - the
        newest tag overall can be on an unrelated line of history (e.g. when
        releasing an earlier build named by 'version', after a newer one has
        already shipped), and picking it anyway would produce an empty or
        nonsensical range.
    .PARAMETER HeadSha
        The commit being released.
    .PARAMETER FromTag
        Start from this tag instead of the most recent one.
    #>
    param(
        [Parameter(Mandatory)][string]$HeadSha,
        [string]$FromTag
    )

    if ($FromTag) {
        $match = Get-VersionTag | Where-Object { $_.Tag -eq $FromTag }
        if (-not $match) { throw "Tag '$FromTag' was not found." }
        return $match
    }

    # Exclude a tag already pointing at HEAD: re-running for the same release,
    # or running from a pushed tag, should not produce empty notes.
    $previous = Get-VersionTag | Where-Object {
        $_.Sha -ne $HeadSha -and (Test-AncestorCommit -Sha $_.Sha -OfSha $HeadSha)
    } | Select-Object -First 1

    if ($previous) { return $previous }

    return [pscustomobject]@{ Tag = $null; Version = $null; Sha = $null }
}

function Get-ChangelogCommit {
    <#
    .SYNOPSIS
        Reads and parses the commits after StartSha up to and including EndSha.
    .PARAMETER StartSha
        Exclusive lower bound. Null means all of history.
    #>
    param(
        [AllowNull()][string]$StartSha,
        [Parameter(Mandatory)][string]$EndSha
    )

    $format = "%H$($script:FieldDelimiter)%s$($script:FieldDelimiter)%b$($script:CommitDelimiter)"
    $range = if ($StartSha) { "$StartSha..$EndSha" } else { $EndSha }
    $raw = git log --reverse $range --format=$format
    if (-not $raw) { return , @() }

    $records = ($raw -join "`n") -split $script:CommitDelimiter

    $commits = @($records |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' } |
            ForEach-Object {
                $fields = $_ -split $script:FieldDelimiter, 3
                ConvertTo-ParsedCommit `
                    -Sha $fields[0].Trim() `
                    -Subject $fields[1].Trim() `
                    -Body $(if ($fields.Count -gt 2) { $fields[2].Trim() } else { '' })
            })

    # A merge commit restates what its own commits already say.
    return , @($commits | Where-Object { -not $_.IsMerge })
}

function ConvertTo-ParsedCommit {
    <#
    .SYNOPSIS
        Splits a commit into its Conventional Commit parts.
    #>
    param(
        [Parameter(Mandatory)][string]$Sha,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Subject,
        [AllowEmptyString()][string]$Body = ''
    )

    $isMerge = $Subject -match '^Merge (pull request|branch|remote)'
    $isConventional = $Subject -match
        '^\s*([a-z]+)\s*(\(([^)]*)\))?\s*(!)?\s*:\s*(.+?)\s*$'

    $type = ''
    $scope = ''
    $description = $Subject
    $bang = $false

    if ($isConventional) {
        $type = $Matches[1].ToLowerInvariant()
        $scope = if ($Matches[3]) { $Matches[3].Trim() } else { '' }
        $bang = ($Matches[4] -eq '!')
        $description = $Matches[5].Trim()
    }

    return [pscustomobject]@{
        Sha         = $Sha
        Type        = $type
        Scope       = $scope
        Description = $description
        Body        = $Body
        IsBreaking  = ($bang -or ($Body -match '(?im)^BREAKING[ -]CHANGE\s*:'))
        IsMerge     = $isMerge
    }
}

#───────────────────────────────────────────────────────────────────────────────
# Rendering
#───────────────────────────────────────────────────────────────────────────────

function Get-ScopeBadge {
    <#
    .SYNOPSIS
        Renders a commit's scope as a coloured badge, or nothing if unscoped.
    #>
    param([Parameter(Mandatory)][pscustomobject]$Commit)

    if (-not $Commit.Scope) { return '' }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Commit.Scope)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    $color = ([System.BitConverter]::ToString($hash) -replace '-', '').
        Substring(40, 6)

    # A literal '-' in a shields.io label has to be doubled.
    $label = [uri]::EscapeDataString($Commit.Scope) -replace '-', '--'

    # ${color} is braced because '?' is legal in a variable name, so
    # "$color?style" would parse as one name.
    $url = "https://img.shields.io/badge/$label-${color}?style=$($script:BadgeStyle)"
    return "![$($Commit.Scope)]($url) "
}

function Get-CommitLine {
    <#
    .SYNOPSIS
        Renders one commit as a bullet, linked to the commit it came from.
    #>
    param(
        [Parameter(Mandatory)][pscustomobject]$Commit,
        [Parameter(Mandatory)][string]$CategoryKey,
        [AllowEmptyString()][string]$Repository
    )

    # In the aggregated and catch-all sections the type is not implied by the
    # heading, so it has to be stated.
    $prefix = ''
    if ($CategoryKey -in 'break', 'other' -and $Commit.Type) {
        $prefix = "**$($Commit.Type)**: "
    }

    $badge = Get-ScopeBadge $Commit
    $suffix = if ($CategoryKey -ne 'break' -and $Commit.IsBreaking) { ' 💥' } else { '' }

    $short = $Commit.Sha.Substring(0, 7)
    $link = if ($Repository) {
        " ([``$short``](https://github.com/$Repository/commit/$($Commit.Sha)))"
    }
    else { " (``$short``)" }

    return "- $prefix$badge$($Commit.Description)$suffix$link"
}

function Get-BreakingDetail {
    <#
    .SYNOPSIS
        Extracts the text explaining a breaking change, if the author wrote it.
    #>
    param([Parameter(Mandatory)][pscustomobject]$Commit)

    $pattern = '(?ims)^BREAKING[ -]CHANGE\s*:\s*(.+?)(\r?\n\r?\n|\z)'
    if ($Commit.Body -notmatch $pattern) { return '' }

    $text = ($Matches[1] -replace '\s+', ' ').Trim()
    if (-not $text) { return '' }
    return "  > $text"
}

function Get-CategoryGroup {
    <#
    .SYNOPSIS
        Assigns every commit to exactly one category, in priority order.
    .DESCRIPTION
        Each category claims the commits the ones above it did not, so nothing
        is listed twice. 'break' is a view over the others and claims nothing;
        'other' sweeps up whatever is left, so no commit is ever dropped.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Commits)

    $remaining = [System.Collections.Generic.List[object]]::new()
    $Commits | ForEach-Object { $remaining.Add($_) }

    $groups = [ordered]@{}

    foreach ($category in $script:Categories.GetEnumerator()) {
        $key = $category.Key

        # The switch is wrapped: it unwraps a single-item result to a scalar,
        # which then has no .Count.
        $matched = @(switch ($key) {
                'break' { @($Commits | Where-Object { $_.IsBreaking }) }
                'other' { @($remaining) }
                default { @($remaining | Where-Object { $_.Type -eq $key }) }
            })

        if ($key -ne 'break') {
            $matched | ForEach-Object { $remaining.Remove($_) | Out-Null }
        }

        if ($matched.Count) {
            $groups[$key] = [pscustomobject]@{
                Key      = $key
                Title    = $category.Value
                Commits  = $matched
                IsNote   = ($key -in $script:NoteCategories)
            }
        }
    }

    return $groups
}

function Get-CountSentence {
    <#
    .SYNOPSIS
        Renders the shape of a release as one sentence.
    #>
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Commits)

    $breaking = @($Commits | Where-Object { $_.IsBreaking }).Count
    $features = @($Commits | Where-Object { $_.Type -eq 'feat' }).Count
    $fixes = @($Commits | Where-Object { $_.Type -eq 'fix' }).Count
    $other = $Commits.Count - $breaking - $features - $fixes

    $parts = [System.Collections.Generic.List[string]]::new()
    if ($breaking) { $parts.Add("**$breaking breaking**") }
    if ($features) { $parts.Add("$features new feature$(if ($features -ne 1) { 's' })") }
    if ($fixes) { $parts.Add("$fixes bug fix$(if ($fixes -ne 1) { 'es' })") }
    if ($other -gt 0) { $parts.Add("$other other change$(if ($other -ne 1) { 's' })") }

    if (-not $parts.Count) { return '' }
    return "$($Commits.Count) commits: $($parts -join ', ')."
}

function Format-ReleaseNote {
    <#
    .SYNOPSIS
        Renders the full release body: notes first, changelog folded below.
    .PARAMETER Summary
        Prose describing the release. Written by a human or generated. When
        empty, a placeholder comment is emitted instead so the shape of the
        document does not change.
    #>
    param(
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Commits,
        [Parameter(Mandatory)]$Baseline,
        [AllowEmptyString()][string]$Repository = '',
        [AllowEmptyString()][string]$Summary = ''
    )

    $lines = [System.Collections.Generic.List[string]]::new()

    # ── Release notes ──────────────────────────────────────────────────────
    if ($Summary.Trim()) {
        $lines.Add($Summary.Trim())
    }
    else {
        $lines.Add('<!-- Write the highlights here: what changed and why it matters. -->')
    }
    $lines.Add('')

    $counts = Get-CountSentence $Commits
    if ($counts) {
        $lines.Add($counts)
        $lines.Add('')
    }

    $groups = Get-CategoryGroup $Commits

    foreach ($group in $groups.Values | Where-Object { $_.IsNote }) {
        $lines.Add("## $($group.Title)")
        $lines.Add('')
        foreach ($commit in $group.Commits) {
            $lines.Add((Get-CommitLine -Commit $commit -CategoryKey $group.Key `
                        -Repository $Repository))
            $detail = Get-BreakingDetail $commit
            if ($detail) { $lines.Add($detail) }
        }
        $lines.Add('')
    }

    # ── Changelog, folded ──────────────────────────────────────────────────
    $detailGroups = @($groups.Values | Where-Object { -not $_.IsNote })
    if ($detailGroups.Count) {
        $lines.Add('<details>')
        $lines.Add("<summary>📋 <b>Full changelog</b> ($($Commits.Count) commits)</summary>")
        # A blank line after the summary tag is required, or the Markdown
        # inside the fold is rendered as literal text.
        $lines.Add('')

        foreach ($group in $detailGroups) {
            $lines.Add("### $($group.Title)")
            $lines.Add('')
            foreach ($commit in $group.Commits) {
                $lines.Add((Get-CommitLine -Commit $commit -CategoryKey $group.Key `
                            -Repository $Repository))
            }
            $lines.Add('')
        }

        $lines.Add('</details>')
        $lines.Add('')
    }

    # The compare link is where the commit-by-commit detail lives, so nothing
    # has to be inlined to be available.
    if ($Repository -and $Baseline.Tag) {
        $url = "https://github.com/$Repository/compare/$($Baseline.Tag)...v$Version"
        $lines.Add("**Full Changelog**: [$($Baseline.Tag)...v$Version]($url)")
    }
    elseif ($Repository) {
        $url = "https://github.com/$Repository/commits/v$Version"
        $lines.Add("**Full Changelog**: [all commits]($url)")
    }

    return $lines
}

Export-ModuleMember -Function @(
    'Get-VersionTag'
    'Test-AncestorCommit'
    'Get-ChangelogBaseline'
    'Get-ChangelogCommit'
    'ConvertTo-ParsedCommit'
    'Get-CategoryGroup'
    'Get-CountSentence'
    'Format-ReleaseNote'
)
