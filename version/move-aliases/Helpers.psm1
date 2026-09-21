#Requires -Version 7.0
<#
    The logic behind repointing a release's aliases: validating the tag,
    deriving which two aliases it moves, and listing every real tag
    an alias can be recomputed from.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#───────────────────────────────────────────────────────────────────────────────
# Deciding
#───────────────────────────────────────────────────────────────────────────────

function Assert-ReleaseTag {
    <#
    .SYNOPSIS
        Throws unless the tag is a real vX.Y.Z release tag.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Tag)

    if ($Tag -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+$') {
        throw "'$Tag' is not a vX.Y.Z release tag."
    }
}

function Get-AliasesForTag {
    <#
    .SYNOPSIS
        Returns the major and major.minor alias names a release tag moves.
    #>
    param([Parameter(Mandatory)][string]$Tag)

    $parts = $Tag.TrimStart('v') -split '\.'
    return [pscustomobject]@{
        Major = "v$($parts[0])"
        Minor = "v$($parts[0]).$($parts[1])"
    }
}

#───────────────────────────────────────────────────────────────────────────────
# Reading
#───────────────────────────────────────────────────────────────────────────────

function Get-ReleaseTags {
    <#
    .SYNOPSIS
        Returns every real tag in the repo, always as an array.
    #>
    param([Parameter(Mandatory)][string]$Repository)

    return , [string[]]@(gh api `
            "repos/$Repository/tags" `
            --paginate `
            --jq '.[].name')
}

Export-ModuleMember -Function @(
    'Assert-ReleaseTag'
    'Get-AliasesForTag'
    'Get-ReleaseTags'
)
