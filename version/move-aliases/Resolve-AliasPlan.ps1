#Requires -Version 7.0

<#
.SYNOPSIS
    Works out which alias tags a release moves,
    and every real tag they can be recomputed from.

.DESCRIPTION
    Recomputes each alias from every vX.Y.Z tag that exists,
    rather than just moving it to whichever tag triggered this run,
    so publishing a backport out of order (v1.0.6 after v1.1.0 already shipped)
    can never move vMAJOR backwards -
    and a previous bad move corrects itself on the next publish.
    Reads the tag list once and writes it as an output,
    for version/move-alias's two calls to share.

.PARAMETER Tag
    Release tag to move the aliases to, e.g. v1.4.2.
    Falls back to EventTag when not given.

.PARAMETER EventTag
    The tag from the release event that triggered the workflow.

.PARAMETER Repository
    owner/repo the aliases and tags live in.

.PARAMETER Token
    Token used to read the tag list.

.EXAMPLE
    ./version/move-aliases/Resolve-AliasPlan.ps1 -Tag v1.4.2 -Repository owner/repo -Token $token
#>
[CmdletBinding()]
param(
    [string]$Tag = '',
    [string]$EventTag = '',
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$Token
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:GH_TOKEN = $Token

Import-Module (Join-Path $PSScriptRoot 'Helpers.psm1') -Force

$resolvedTag = if ($Tag) { $Tag } else { $EventTag }
Assert-ReleaseTag -Tag $resolvedTag

$aliases = Get-AliasesForTag -Tag $resolvedTag
$tags = Get-ReleaseTags -Repository $Repository

"alias-major=$($aliases.Major)" >> $env:GITHUB_OUTPUT
"alias-minor=$($aliases.Minor)" >> $env:GITHUB_OUTPUT

$delimiter = [guid]::NewGuid().ToString()
"tags<<$delimiter" >> $env:GITHUB_OUTPUT
$tags >> $env:GITHUB_OUTPUT
$delimiter >> $env:GITHUB_OUTPUT
