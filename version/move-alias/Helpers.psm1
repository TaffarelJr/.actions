#Requires -Version 7.0
<#
    The logic behind repointing an alias tag:
    which release tags it can move to, which of those is newest,
    reading and writing the tag through gh,
    and the retry that makes that read-then-act safe.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#───────────────────────────────────────────────────────────────────────────────
# Deciding
#───────────────────────────────────────────────────────────────────────────────

function Get-AliasFilterPattern {
    <#
    .SYNOPSIS
        Returns the regex that selects the release tags an alias can move to:
        vN for a major alias, vN.M for a major.minor alias.
    #>
    param([Parameter(Mandatory)][string]$Alias)

    if ($Alias -match '^v(?<major>[0-9]+)$') {
        return "^v$($Matches.major)\.[0-9]+\.[0-9]+$"
    }

    if ($Alias -match '^v(?<major>[0-9]+)\.(?<minor>[0-9]+)$') {
        return "^v$($Matches.major)\.$($Matches.minor)\.[0-9]+$"
    }

    throw "'$Alias' is not a major or major.minor alias (expected vN or vN.N)."
}

function Get-NewestMatchingTag {
    <#
    .SYNOPSIS
        Returns the highest-versioned tag matching a pattern,
        or $null when none match.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Tag,
        [Parameter(Mandatory)][string]$Pattern
    )

    $matching = @($Tag | Where-Object { $_ -match $Pattern })
    if (-not $matching) {
        return $null
    }

    return ($matching |
        Sort-Object { [version]($_ -replace '^v') } |
        Select-Object -Last 1)
}

function Get-AliasMoveAction {
    <#
    .SYNOPSIS
        Decides whether an alias needs to be created, updated,
        or left as is, given its current commit (if any)
        and the commit it should point to.
    #>
    param(
        [string]$CurrentCommit,
        [Parameter(Mandatory)][string]$TargetCommit
    )

    if ($CurrentCommit -eq $TargetCommit) {
        return 'None'
    }

    if ($CurrentCommit) {
        return 'Update'
    }

    return 'Create'
}

#───────────────────────────────────────────────────────────────────────────────
# Reading and writing the tag
#───────────────────────────────────────────────────────────────────────────────

function Get-TagCommit {
    <#
    .SYNOPSIS
        Returns the commit sha a tag points to.
    #>
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Tag
    )

    return (gh api "repos/$Repository/commits/$Tag" --jq '.sha' |
        Select-Object -Last 1)
}

function Get-AliasCommit {
    <#
    .SYNOPSIS
        Returns the commit sha an alias tag currently points to,
        or $null if the alias does not exist yet.
    #>
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Alias
    )

    $sha = gh api "repos/$Repository/git/ref/tags/$Alias" --jq '.object.sha' 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return ($sha | Select-Object -Last 1)
}

function Set-AliasCommit {
    <#
    .SYNOPSIS
        Creates or updates an alias tag to point at a commit,
        returning whether the API call succeeded.
    #>
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][bool]$Exists
    )

    if ($Exists) {
        gh api `
            --method PATCH "repos/$Repository/git/refs/tags/$Alias" `
            -f "sha=$Commit" `
            -F force=true |
        Out-Null
    }
    else {
        gh api `
            --method POST "repos/$Repository/git/refs" `
            -f "ref=refs/tags/$Alias" `
            -f "sha=$Commit" |
        Out-Null
    }

    return $LASTEXITCODE -eq 0
}

#───────────────────────────────────────────────────────────────────────────────
# Orchestrating
#───────────────────────────────────────────────────────────────────────────────

function Move-Alias {
    <#
    .SYNOPSIS
        Repoints an alias tag at the newest release tag it matches,
        retrying a few times on a transient failure.
    .DESCRIPTION
        Read-then-act, retried from a fresh read each time:
        a transient inconsistency right after GitHub creates a tag
        (observed live - a brand-new alias's own existence check
        briefly disagreed with reality, turning its first-ever creation into
        a "reference does not exist" failure) should not fail the whole run.
    .OUTPUTS
        A pscustomobject with Success (bool) and Message (string),
        for the caller to report.
    #>
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Tag,
        [int]$MaxAttempts = 3,
        [int]$RetryDelaySeconds = 2
    )

    $pattern = Get-AliasFilterPattern -Alias $Alias
    $newest = Get-NewestMatchingTag -Tag $Tag -Pattern $pattern
    if (-not $newest) {
        return [pscustomobject]@{
            Success = $false
            Message = "No tag matches $Alias ($pattern)."
        }
    }

    $targetCommit = Get-TagCommit -Repository $Repository -Tag $newest

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $currentCommit = Get-AliasCommit -Repository $Repository -Alias $Alias
        $action = Get-AliasMoveAction -CurrentCommit $currentCommit -TargetCommit $targetCommit

        if ($action -eq 'None') {
            return [pscustomobject]@{
                Success = $true
                Message = "$Alias already at $newest ($targetCommit)"
            }
        }

        $ok = Set-AliasCommit `
            -Repository $Repository `
            -Alias $Alias `
            -Commit $targetCommit `
            -Exists ($action -eq 'Update')

        if ($ok) {
            return [pscustomobject]@{
                Success = $true
                Message = "$Alias -> $newest ($targetCommit)"
            }
        }

        if ($attempt -lt $MaxAttempts) {
            Start-Sleep -Seconds ($attempt * $RetryDelaySeconds)
        }
    }

    return [pscustomobject]@{
        Success = $false
        Message = "Could not move $Alias after $MaxAttempts attempts."
    }
}

Export-ModuleMember -Function @(
    'Get-AliasFilterPattern'
    'Get-NewestMatchingTag'
    'Get-AliasMoveAction'
    'Get-TagCommit'
    'Get-AliasCommit'
    'Set-AliasCommit'
    'Move-Alias'
)
