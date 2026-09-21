#Requires -Version 7.0

<#
.SYNOPSIS
    Repoints one alias tag at the newest release tag it matches.

.PARAMETER Alias
    The alias to move: vN for a major alias, vN.M for a major.minor alias.

.PARAMETER Tag
    Every real release tag that exists.

.PARAMETER Repository
    owner/repo the alias and tags live in.

.PARAMETER Token
    Token used to read and move the tag.

.EXAMPLE
    ./version/move-alias/Move-Alias.ps1 -Alias v1 -Tag $tags -Repository owner/repo -Token $token
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Alias,
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Tag,
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$Token
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:GH_TOKEN = $Token

Import-Module (Join-Path $PSScriptRoot 'Helpers.psm1') -Force

$result = Move-Alias -Repository $Repository -Alias $Alias -Tag $Tag
if ($result.Success) {
    Write-Host "::notice::$($result.Message)"
    exit 0
}

Write-Host "::error::$($result.Message)"
exit 1
