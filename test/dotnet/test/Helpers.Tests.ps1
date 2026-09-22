#Requires -Version 7.0
<#
    Tests for dotnet/test's Helpers.psm1: discovering target frameworks,
    running the suite once per framework (or once, unlabeled), and
    relocating its coverage report out of the collector's own subfolder.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:TESTKIT_PATH) { throw 'Run this file through powershell/test/Invoke-Tests.ps1' }
Import-Module $env:TESTKIT_PATH -Force

# Common-Build.psm1 is a sibling of the action folder this file mirrors,
# not inside it - Import-SourceModule only ever looks in the mirror itself.
Import-Module (Join-Path (Get-SourcePath) '..' 'Common-Build.psm1') -Force -Global
Import-SourceModule 'Helpers'

# Every case below runs at a console, not in a workflow, unless a case
# says otherwise - the CI logger's own tests toggle this deliberately.
$env:CI = $null
$env:GITHUB_ACTIONS = $null

function New-TestProject {
    <#
    .SYNOPSIS
        Writes a minimal test .csproj under a scratch root's test/ folder,
        with the given PropertyGroup XML inside it, and returns the root.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PropertyXml,
        [string]$Name = 'Some.Tests'
    )

    $projectFolder = Join-Path $Root 'test' $Name
    $null = New-Item -ItemType Directory -Force -Path $projectFolder
    Set-Content -LiteralPath (Join-Path $projectFolder "$Name.csproj") -Value @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    $PropertyXml
  </PropertyGroup>
</Project>
"@
    return $Root
}

function New-DotnetStubWithCoverage {
    <#
    .SYNOPSIS
        Installs a dotnet stub that, like a real test run, drops a fake
        coverage report inside a randomly named subfolder of whatever
        --results-directory it was given.
    #>
    Set-DotnetStub -Handler {
        param($Argv)
        $index = [array]::IndexOf($Argv, '--results-directory')
        if ($index -ge 0) {
            $guidFolder = Join-Path $Argv[$index + 1] ([guid]::NewGuid())
            $null = New-Item -ItemType Directory -Force -Path $guidFolder
            Set-Content -LiteralPath (Join-Path $guidFolder 'coverage.cobertura.xml') -Value '<coverage/>'
        }
        return @{}
    }
}

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '1. Get-TestFramework'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$none = New-TestRoot -Name 'dotnet-test-frameworks-none'
$context = [pscustomobject]@{ RepoRoot = $none }

# Act / Assert
Assert-Equal 'no test project at all means no frameworks' 0 (Get-TestFramework -Context $context).Count

# Arrange
$single = New-TestProject -Root (New-TestRoot -Name 'dotnet-test-frameworks-single') `
    -PropertyXml '<TargetFramework>net8.0</TargetFramework>'
$singleContext = [pscustomobject]@{ RepoRoot = $single }

# Act / Assert
Assert-Equal 'the singular element counts too' 'net8.0' `
    ((Get-TestFramework -Context $singleContext) -join ',')

# Arrange
$multi = New-TestProject -Root (New-TestRoot -Name 'dotnet-test-frameworks-multi') `
    -PropertyXml '<TargetFrameworks>net8.0;$(SomeProp);net9.0</TargetFrameworks>'
$multiContext = [pscustomobject]@{ RepoRoot = $multi }

# Act / Assert
Assert-Equal 'a semicolon list is split, an MSBuild property reference is skipped' 'net8.0,net9.0' `
    ((Get-TestFramework -Context $multiContext) -join ',')

# Arrange - a second project repeating one of the first's frameworks
$dedupeRoot = New-TestProject -Root (New-TestRoot -Name 'dotnet-test-frameworks-dedupe') `
    -PropertyXml '<TargetFrameworks>net8.0;net9.0</TargetFrameworks>'
$null = New-TestProject -Root $dedupeRoot -Name 'Other.Tests' `
    -PropertyXml '<TargetFramework>net9.0</TargetFramework>'
$dedupeContext = [pscustomobject]@{ RepoRoot = $dedupeRoot }

# Act / Assert - order across separate project files is not part of the
# contract, only that a repeat does not appear twice
Assert-Equal 'the same framework across projects is listed once' 'net8.0,net9.0' `
    (((Get-TestFramework -Context $dedupeContext) | Sort-Object) -join ',')

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '2. Invoke-Test - the per-framework loop'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$skipped = [pscustomobject]@{ RepoRoot = $none; HasProjects = $false }
New-DotnetStubWithCoverage

# Act
Invoke-Test -Context $skipped

# Assert
Assert-Equal 'no projects means no dotnet call at all' 0 (Get-DotnetCall).Count

# Arrange
$unlabeledContext = [pscustomobject]@{
    RepoRoot = $none; HasProjects = $true; Solution = 'C:\repo\Placeholder.slnx'; Configuration = 'Release'
}
New-DotnetStubWithCoverage

# Act
Invoke-Test -Context $unlabeledContext

# Assert
Assert-Equal 'no declared framework means exactly one, unlabeled, run' 1 (Get-DotnetCall).Count
Assert-That 'and it names no --framework at all' (-not (Test-DotnetCall '--framework')) (Get-DotnetCall)[0]

# Arrange
$loopContext = [pscustomobject]@{
    RepoRoot = $multi; HasProjects = $true; Solution = 'C:\repo\Placeholder.slnx'; Configuration = 'Release'
}
New-DotnetStubWithCoverage

# Act
Invoke-Test -Context $loopContext

# Assert
$calls = Get-DotnetCall
Assert-Equal 'one run per declared framework' 2 $calls.Count
Assert-That 'the first names net8.0' (Test-DotnetCall '--framework net8\.0(\s|$)')
Assert-That 'the second names net9.0' (Test-DotnetCall '--framework net9\.0(\s|$)')
Assert-That 'each framework wrote its own coverage file' `
    ((Test-Path (Join-Path $multi 'test' 'coverage' 'net8.0' 'coverage.cobertura.xml')) -and
    (Test-Path (Join-Path $multi 'test' 'coverage' 'net9.0' 'coverage.cobertura.xml')))

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '3. Invoke-Test - one run, in detail'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$detailRoot = New-TestRoot -Name 'dotnet-test-detail'
$detailContext = [pscustomobject]@{
    RepoRoot = $detailRoot; HasProjects = $true; Solution = 'C:\repo\Placeholder.slnx'; Configuration = 'Release'
}
New-DotnetStubWithCoverage

# Act
Invoke-Test -Context $detailContext

# Assert
Assert-That 'no Test.runsettings means no --settings at all' (-not (Test-DotnetCall '--settings'))
Assert-That 'no CI environment means no --logger at all' (-not (Test-DotnetCall '--logger'))
Assert-That 'the coverage report lands flat, out of its own subfolder' `
    (Test-Path (Join-Path $detailRoot 'test' 'coverage' 'coverage.cobertura.xml'))

# Arrange
$null = New-Item -ItemType Directory -Force -Path (Join-Path $detailRoot 'test')
Set-Content -LiteralPath (Join-Path $detailRoot 'test' 'Test.runsettings') -Value '<RunSettings />'
New-DotnetStubWithCoverage

# Act
Invoke-Test -Context $detailContext

# Assert
Assert-That 'a Test.runsettings at the repo root is passed along' `
    (Test-DotnetCall ([regex]::Escape((Join-Path $detailRoot 'test' 'Test.runsettings'))))

# Arrange
$env:GITHUB_ACTIONS = 'true'
New-DotnetStubWithCoverage

# Act
Invoke-Test -Context $detailContext
$env:GITHUB_ACTIONS = $null

# Assert
Assert-That 'in a workflow, a JUnit logger with an absolute path is added' `
    (Test-DotnetCall ([regex]::Escape('--logger junit;LogFilePath=' + (Join-Path $detailRoot 'test' 'results' 'results.junit.xml'))))

# Arrange
Set-DotnetStub -Handler { return @{ Exit = 1 } }

# Act / Assert
Assert-Throws 'a failing run throws, naming the exit code' `
    { Invoke-Test -Context $detailContext } -Match 'dotnet test failed with exit code 1'

exit (Complete-TestRun)
