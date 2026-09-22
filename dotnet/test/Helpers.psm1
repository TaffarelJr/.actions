#Requires -Version 7.0
<#
    The logic behind testing a repo's .NET solution.
#>
using namespace System.Collections.Generic

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TestFramework {
    <#
    .SYNOPSIS
        Returns every target framework any test project under test/
        declares, always as an array - empty when none of them do,
        which is the cue to run the suite once, unlabeled.
    .DESCRIPTION
        Matches both spellings: a project that targets one framework
        writes the singular <TargetFramework>, and matching only the
        plural form would silently report that it targets nothing.
    #>
    param([Parameter(Mandatory)][pscustomobject]$Context)

    $testPath = Join-Path $Context.RepoRoot 'test'
    $projects = @(Get-ChildItem -LiteralPath $testPath -Filter '*.csproj' -Recurse -File -ErrorAction SilentlyContinue)

    $frameworks = [List[string]]::new()
    foreach ($project in $projects) {
        $xml = [xml](Get-Content -LiteralPath $project.FullName -Raw)
        $nodes = $xml.SelectNodes('//TargetFrameworks | //TargetFramework')

        foreach ($node in $nodes) {
            foreach ($tfm in ($node.InnerText -split ';')) {
                $trimmed = $tfm.Trim()

                # An MSBuild property can hold a $(...) reference, which is
                # not a framework name and cannot be run against.
                if (-not $trimmed -or $trimmed.Contains('$(')) {
                    continue
                }

                if ($frameworks -notcontains $trimmed) {
                    $frameworks.Add($trimmed)
                }
            }
        }
    }

    return , [string[]]$frameworks
}

function Invoke-Test {
    <#
    .SYNOPSIS
        Runs the solution's tests once per target framework it declares,
        or once, unlabeled, when it declares none.
    #>
    param([Parameter(Mandatory)][pscustomobject]$Context)

    $frameworks = Get-TestFramework -Context $Context
    if (-not $frameworks.Count) {
        Invoke-TestFramework -Context $Context
        return
    }

    foreach ($framework in $frameworks) {
        Invoke-TestFramework -Context $Context -Framework $framework
    }
}

function Invoke-TestFramework {
    <#
    .SYNOPSIS
        Runs the solution's tests once - for one target framework, or the
        single implicit one when Framework is empty - and relocates its
        coverage report out of the collector's own randomly named
        subfolder. Skips when there are no projects to test.
    #>
    param(
        [Parameter(Mandatory)][pscustomobject]$Context,
        [string]$Framework = ''
    )

    if (-not $Context.HasProjects) {
        Write-TaskSkip 'no projects in the solution'
        return
    }

    $resultsPath = if ($Framework) {
        Join-Path $Context.RepoRoot 'test' 'results' $Framework
    }
    else {
        Join-Path $Context.RepoRoot 'test' 'results'
    }

    $coveragePath = if ($Framework) {
        Join-Path $Context.RepoRoot 'test' 'coverage' $Framework
    }
    else {
        Join-Path $Context.RepoRoot 'test' 'coverage'
    }

    $arguments = [List[string]]::new()
    $arguments.AddRange([string[]]@(
            $Context.Solution
            '--nologo', '--no-build'
            '--configuration', $Context.Configuration
            '--results-directory', $resultsPath
        ))
    if ($Framework) {
        $arguments.AddRange([string[]]@('--framework', $Framework))
    }

    $settingsPath = Join-Path $Context.RepoRoot 'test' 'Test.runsettings'
    if (Test-Path -LiteralPath $settingsPath) {
        $arguments.AddRange([string[]]@('--settings', $settingsPath))
    }

    if (Test-CIEnvironment) {
        # LogFilePath must be absolute - a relative one resolves against the
        # test project's own directory, not --results-directory, so every
        # framework would write the same file and only the last would survive.
        $junitPath = Join-Path $resultsPath 'results.junit.xml'
        $logger = "junit;LogFilePath=$junitPath;MethodFormat=Full;FailureBodyFormat=Verbose"
        $arguments.AddRange([string[]]@('--logger', $logger))
    }

    dotnet test @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet test failed with exit code $LASTEXITCODE."
    }

    Copy-CoverageReport -ResultsPath $resultsPath -CoveragePath $coveragePath
}

function Copy-CoverageReport {
    <#
    .SYNOPSIS
        Copies the coverage collector's report out of its own randomly
        named subfolder and into CoveragePath, flat - or does nothing
        when there is none.
    #>
    param(
        [Parameter(Mandatory)][string]$ResultsPath,
        [Parameter(Mandatory)][string]$CoveragePath
    )

    $report = Get-ChildItem -LiteralPath $ResultsPath -Filter 'coverage.cobertura.xml' -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $report) {
        return
    }

    $null = New-Item -ItemType Directory -Force -Path $CoveragePath
    Copy-Item -LiteralPath $report.FullName -Destination (Join-Path $CoveragePath 'coverage.cobertura.xml') -Force
}

Export-ModuleMember -Function @(
    'Get-TestFramework'
    'Invoke-Test'
)
