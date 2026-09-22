#Requires -Version 7.0
<#
    The logic behind building a repo's .NET solution.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Build {
    <#
    .SYNOPSIS
        Builds the solution, stamping in the context's version when it has
        one, or skips when it has no projects to build.
    #>
    param([Parameter(Mandatory)][pscustomobject]$Context)

    if (-not $Context.HasProjects) {
        Write-TaskSkip 'no projects in the solution'
        return
    }

    $versionArgument = Get-VersionArgument -Context $Context
    dotnet build $Context.Solution --nologo --no-restore --configuration $Context.Configuration @versionArgument
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed with exit code $LASTEXITCODE."
    }
}

Export-ModuleMember -Function @(
    'Invoke-Build'
)
