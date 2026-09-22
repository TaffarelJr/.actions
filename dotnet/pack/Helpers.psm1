#Requires -Version 7.0
<#
    The logic behind packing a repo's .NET solution.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Pack {
    <#
    .SYNOPSIS
        Packs every packable project into the context's artifact path,
        stamping in its version when it has one.
    .DESCRIPTION
        Skips when the solution has no projects,
        or - separately - when packing produced no .nupkg at all:
        which project is packable is IsPackable's own decision,
        not something to guess at here,
        so a solution built entirely of non-packable projects is not an error.
    #>
    param([Parameter(Mandatory)][pscustomobject]$Context)

    if (-not $Context.HasProjects) {
        Write-TaskSkip 'no projects in the solution'
        return
    }

    $versionArgument = Get-VersionArgument -Context $Context
    dotnet pack $Context.Solution `
        --nologo `
        --no-build `
        --configuration $Context.Configuration `
        --output $Context.ArtifactPath `
        @versionArgument

    if ($LASTEXITCODE -ne 0) {
        throw "dotnet pack failed with exit code $LASTEXITCODE."
    }

    $packages = @(Get-ChildItem -LiteralPath $Context.ArtifactPath -Filter '*.nupkg' -File -ErrorAction SilentlyContinue)
    if (-not $packages.Count) {
        Write-TaskSkip 'no project is packable'
    }
}

Export-ModuleMember -Function @(
    'Invoke-Pack'
)
