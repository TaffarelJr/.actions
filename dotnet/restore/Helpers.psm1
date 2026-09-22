#Requires -Version 7.0
<#
    The logic behind restoring a repo's .NET tools and NuGet packages.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Restore-Tool {
    <#
    .SYNOPSIS
        Restores the tools listed in .config/dotnet-tools.json,
        or skips when the repo has no manifest.
    #>
    param([Parameter(Mandatory)][pscustomobject]$Context)

    $manifest = Join-Path $Context.RepoRoot '.config' 'dotnet-tools.json'
    if (-not (Test-Path -LiteralPath $manifest)) {
        Write-TaskSkip 'no .config/dotnet-tools.json'
        return
    }

    dotnet tool restore
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet tool restore failed with exit code $LASTEXITCODE."
    }
}

function Restore-Package {
    <#
    .SYNOPSIS
        Restores the solution's NuGet packages,
        or skips when it has no projects to restore.
    #>
    param([Parameter(Mandatory)][pscustomobject]$Context)

    if (-not $Context.HasProjects) {
        Write-TaskSkip 'no projects in the solution'
        return
    }

    dotnet restore $Context.Solution --nologo
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet restore failed with exit code $LASTEXITCODE."
    }
}

Export-ModuleMember -Function @(
    'Restore-Tool'
    'Restore-Package'
)
