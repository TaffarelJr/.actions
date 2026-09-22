#Requires -Version 7.0
<#
    Shared logic every dotnet/* action needs: finding the one solution at
    the repo root and what it holds, and reporting a task that did nothing.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-BuildContext {
    <#
    .SYNOPSIS
        Finds the one solution file at the repo root and reports what it
        holds: every project it lists, whether there are any, and where
        packed output goes.
    .DESCRIPTION
        Throws when there is no *.slnx at the repo root, or more than one -
        there is nothing to guess between. A repo with no projects at all
        (a template's own Placeholder, say) is not an error - HasProjects
        is what every task checks before deciding to no-op.
    #>
    param(
        [Parameter(Mandatory)][string]$Configuration,
        [AllowEmptyString()][string]$Version = ''
    )

    $repoRoot = (Get-Location).Path
    $candidates = @(Get-ChildItem -LiteralPath $repoRoot -Filter '*.slnx' -File)
    if ($candidates.Count -eq 0) {
        throw "No *.slnx found at '$repoRoot'."
    }
    if ($candidates.Count -gt 1) {
        throw "More than one *.slnx found at '$repoRoot': $($candidates.Name -join ', ')."
    }

    $solution = $candidates[0].FullName
    $lines = @(dotnet sln $solution list 2>$null)

    # A nonzero exit here means the listing itself is unreliable, not that
    # the solution is unusable - Restore/Build/Test/Pack each make their own
    # real dotnet call next and fail loudly on their own if something is
    # actually wrong. Reset explicitly so that later failure is never
    # mistaken for this one: an unqualified assignment would only shadow
    # this function's own copy, leaving the caller's $LASTEXITCODE untouched.
    $global:LASTEXITCODE = 0

    $projects = @($lines | Where-Object { $_ -match '\.(cs|fs|vb)proj$' })

    return [pscustomobject]@{
        RepoRoot      = $repoRoot
        Solution      = $solution
        SolutionName  = $candidates[0].BaseName
        Configuration = $Configuration
        Version       = $Version
        Projects      = $projects
        HasProjects   = [bool]$projects.Count
        ArtifactPath  = Join-Path $repoRoot 'artifacts'
    }
}

function Get-VersionArgument {
    <#
    .SYNOPSIS
        Returns the -p:Version/-p:PackageVersion arguments for a build
        context's version, or an empty array when it has none to stamp.
    #>
    param([Parameter(Mandatory)][pscustomobject]$Context)

    if (-not $Context.Version) {
        return , @()
    }

    return , @("-p:Version=$($Context.Version)", "-p:PackageVersion=$($Context.Version)")
}

function Write-TaskSkip {
    <#
    .SYNOPSIS
        Reports that a task did nothing: a CI annotation in a workflow,
        a grey line at a console - the same CI/interactive split
        Test-InteractiveHost uses.
    #>
    param([Parameter(Mandatory)][string]$Reason)

    if ($env:CI -or $env:GITHUB_ACTIONS) {
        Write-Host "::notice::Skipped - $Reason"
    }
    else {
        Write-Host "   skipped - $Reason" -ForegroundColor DarkGray
    }
}

Export-ModuleMember -Function @(
    'Get-BuildContext'
    'Get-VersionArgument'
    'Write-TaskSkip'
)
