#Requires -Version 7.0

<#
.SYNOPSIS
    Writes the prompt asking a model to summarize a release's changelog
    into an opening paragraph.

.PARAMETER Version
    The version being released.

.PARAMETER ChangelogPath
    The generated changelog to summarize.

.PARAMETER OutputPath
    Where to write the prompt.

.EXAMPLE
    ./release/draft/New-SummaryPrompt.ps1 -Version 1.4.2 -ChangelogPath Changelog.md -OutputPath prompt.txt
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$ChangelogPath,
    [Parameter(Mandatory)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Helpers.psm1') -Force

$changelog = Get-Content -LiteralPath $ChangelogPath -Raw
Get-SummaryPrompt -Version $Version -Changelog $changelog | Set-Content -LiteralPath $OutputPath -NoNewline
