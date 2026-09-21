#Requires -Version 7.0
<#
    The logic behind drafting a release: deciding which version to draft,
    building the AI-summary prompt, and creating/updating the draft
    itself.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#───────────────────────────────────────────────────────────────────────────────
# Deciding the version
#───────────────────────────────────────────────────────────────────────────────

function Test-TagExists {
    <#
    .SYNOPSIS
        Returns whether a tag exists in the current checkout.
    #>
    param([Parameter(Mandatory)][string]$Tag)

    git rev-parse $Tag *> $null
    return $LASTEXITCODE -eq 0
}

function Resolve-DraftVersion {
    <#
    .SYNOPSIS
        Decides the version to draft a release for, and the commit it
        was built from. Throws when there is nothing valid to draft.
    .DESCRIPTION
        A named version can only come from the build that produced it -
        there is no fallback, since a release ships a build. Otherwise
        prefers the version the build recorded over recalculating it, so
        the release reports what is actually stamped into the binaries.
        Refuses a version that is not a plain X.Y.Z release version, or
        one already tagged - the tag is created when a release is
        published, so an existing one means this exact version is
        already public.
    .OUTPUTS
        A pscustomobject with Version, Sha, and Source ('Build' or
        'Fallback', for the caller to report which one was used).
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Requested,
        [Parameter(Mandatory)][bool]$Found,
        [Parameter(Mandatory)][AllowEmptyString()][string]$FromBuild,
        [Parameter(Mandatory)][AllowEmptyString()][string]$BuiltSha,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Fallback,
        [Parameter(Mandatory)][string]$CurrentSha
    )

    $requested = $Requested.TrimStart('v')
    if ($requested -and (-not $Found -or $FromBuild -ne $requested)) {
        throw "No CI build of $requested is available to release. Either it " +
        'was never built on this branch, or its artifact has expired.'
    }

    $version = if ($FromBuild) { $FromBuild } else { $Fallback }
    $source = if ($FromBuild) { 'Build' } else { 'Fallback' }
    if (-not $version) {
        throw 'Could not determine a version to release.'
    }

    if ($version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
        throw "'$version' is not a release version (expected X.Y.Z) - a " +
        'pull-request or branch build cannot be published.'
    }

    if (Test-TagExists -Tag "v$version") {
        throw "v$version is already tagged, so it has already been " +
        'released. Merge something, or raise next-version in ' +
        'gitversion.yml to choose the next number.'
    }

    $sha = if ($BuiltSha) { $BuiltSha } else { $CurrentSha }
    return [pscustomobject]@{ Version = $version; Sha = $sha; Source = $source }
}

#───────────────────────────────────────────────────────────────────────────────
# The AI-summary prompt
#───────────────────────────────────────────────────────────────────────────────

function Get-SummaryPrompt {
    <#
    .SYNOPSIS
        Builds the prompt asking a model to summarize a release's
        changelog into an opening paragraph.
    #>
    param(
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Changelog
    )

    return @"
Below is a generated changelog for version $Version.

Write 2-4 sentences for the top of the release notes,
saying what changed and why a reader should care. Lead with
the most significant change, and mention breaking changes
first if there are any. Do not list every commit, do not
use headings, and do not repeat the commit counts.
Plain prose, no preamble.

---

$Changelog
"@
}

#───────────────────────────────────────────────────────────────────────────────
# Creating the draft
#───────────────────────────────────────────────────────────────────────────────

function Get-ReleaseList {
    <#
    .SYNOPSIS
        Returns every release in the repo, up to Limit, always as an
        array.
    #>
    param([int]$Limit = 100)

    return @(gh release list --limit $Limit --json 'tagName,isDraft' | ConvertFrom-Json)
}

function Test-DraftExists {
    <#
    .SYNOPSIS
        Returns whether a draft release already exists for a tag, given
        the repo's releases.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Release,
        [Parameter(Mandatory)][string]$Tag
    )

    return [bool]($Release | Where-Object { $_.tagName -eq $Tag -and $_.isDraft })
}

function Remove-Draft {
    <#
    .SYNOPSIS
        Deletes the draft release for a tag.
    #>
    param([Parameter(Mandatory)][string]$Tag)

    gh release delete $Tag --yes
}

function New-DraftRelease {
    <#
    .SYNOPSIS
        Creates a draft release for a tag, targeting a commit, and
        returns its URL.
    .DESCRIPTION
        --target pins the release to the commit that was built, so the
        tag lands there when it is published even if main has moved on
        since.
    #>
    param(
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$NotesPath,
        [Parameter(Mandatory)][string]$TargetSha
    )

    return (gh release create $Tag --draft --title $Tag --notes-file $NotesPath --target $TargetSha |
        Select-Object -Last 1)
}

function Test-HasArtifact {
    <#
    .SYNOPSIS
        Returns whether a folder exists and holds at least one file.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    return [bool](Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
}

function Publish-ReleaseAsset {
    <#
    .SYNOPSIS
        Uploads every file directly under a folder to a release, and
        returns how many there were.
    #>
    param(
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Path
    )

    $files = @(Get-ChildItem -LiteralPath $Path -Force | ForEach-Object { $_.FullName })
    gh release upload $Tag @files --clobber
    return $files.Count
}

function Get-DraftSummary {
    <#
    .SYNOPSIS
        Builds the job summary announcing a draft release.
    #>
    param(
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Url
    )

    return @"
### Draft release [$Tag]($Url)

Review the notes, then press **Publish** to tag and ship.
"@
}

Export-ModuleMember -Function @(
    'Test-TagExists'
    'Resolve-DraftVersion'
    'Get-SummaryPrompt'
    'Get-ReleaseList'
    'Test-DraftExists'
    'Remove-Draft'
    'New-DraftRelease'
    'Test-HasArtifact'
    'Publish-ReleaseAsset'
    'Get-DraftSummary'
)
