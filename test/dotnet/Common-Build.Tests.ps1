#Requires -Version 7.0
<#
    Tests for dotnet/Common-Build.psm1: finding the one solution at the
    repo root and what it holds, and reporting a skipped task.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:TESTKIT_PATH) { throw 'Run this file through powershell/test/Invoke-Tests.ps1' }
Import-Module $env:TESTKIT_PATH -Force
Import-SourceModule 'Common-Build'

function New-Solution {
    <#
    .SYNOPSIS
        Creates an empty *.slnx file under a folder, and returns the folder.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Name = 'Placeholder'
    )

    $null = New-Item -ItemType Directory -Force -Path $Root
    Set-Content -LiteralPath (Join-Path $Root "$Name.slnx") -Value '<Solution />'
    return $Root
}

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '1. Get-BuildContext - finding the solution'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$none = New-TestRoot -Name 'common-build-none'
$many = New-Solution -Root (New-TestRoot -Name 'common-build-many') -Name 'First'
Set-Content -LiteralPath (Join-Path $many 'Second.slnx') -Value '<Solution />'

# Act / Assert
Push-Location $none
try {
    Assert-Throws 'no *.slnx at the repo root throws' `
        { Get-BuildContext -Configuration 'Release' } -Match 'No \*\.slnx found'
}
finally {
    Pop-Location
}

Push-Location $many
try {
    Assert-Throws 'more than one *.slnx throws' `
        { Get-BuildContext -Configuration 'Release' } -Match 'More than one \*\.slnx found'
}
finally {
    Pop-Location
}

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '2. Get-BuildContext - a solution with projects'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$withProjects = New-Solution -Root (New-TestRoot -Name 'common-build-projects')
Set-DotnetStub -Handler {
    param($Argv)
    return @{ Out = @('Project(s)', '----------', 'src\Foo\Foo.csproj') }
}

# Act
Push-Location $withProjects
try {
    $context = Get-BuildContext -Configuration 'Release' -Version '1.2.3'
}
finally {
    Pop-Location
}

# Assert
Assert-Equal 'the repo root is the current directory' (Resolve-Path $withProjects).Path $context.RepoRoot
Assert-Equal 'the solution name is the *.slnx file, without its extension' 'Placeholder' $context.SolutionName
Assert-Equal 'the configuration is passed through' 'Release' $context.Configuration
Assert-Equal 'the version is passed through' '1.2.3' $context.Version
Assert-Equal 'the artifact path is a sibling of the solution' (Join-Path $context.RepoRoot 'artifacts') $context.ArtifactPath
Assert-Equal 'the project line is kept, the header and rule are not' 'src\Foo\Foo.csproj' ($context.Projects -join ',')
Assert-That 'projects means HasProjects' $context.HasProjects
Assert-That 'and dotnet sln was really asked to list them' (Test-DotnetCall 'sln .*list')

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '3. Get-BuildContext - a solution with none'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$empty = New-Solution -Root (New-TestRoot -Name 'common-build-empty')
Set-DotnetStub -Handler {
    param($Argv)
    return @{ Exit = 1; Out = @('No projects found in the solution.') }
}

# Act
Push-Location $empty
try {
    $emptyContext = Get-BuildContext -Configuration 'Release'
}
finally {
    Pop-Location
}

# Assert
Assert-Equal 'no version means an empty string' '' $emptyContext.Version
Assert-Equal 'no project lines means an empty list' 0 $emptyContext.Projects.Count
Assert-That 'no projects means not HasProjects' (-not $emptyContext.HasProjects)
Assert-Equal 'a failing listing does not leak its exit code to the caller' 0 $LASTEXITCODE

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '4. Write-TaskSkip'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$savedCi = $env:CI
$savedActions = $env:GITHUB_ACTIONS
$env:CI = $null
$env:GITHUB_ACTIONS = 'true'

# Act
$inActions = (Get-Narration { Write-TaskSkip 'no projects' }).Lines

# Arrange
$env:GITHUB_ACTIONS = $null
$env:CI = $null

# Act
$plain = (Get-Narration { Write-TaskSkip 'no projects' }).Lines

# Arrange - restore, so later files see the real environment
$env:CI = $savedCi
$env:GITHUB_ACTIONS = $savedActions

# Assert
Assert-Equal 'in a workflow, a job annotation' '::notice::Skipped - no projects' $inActions[0]
Assert-Equal 'at a console, a plain line' '   skipped - no projects' $plain[0]

exit (Complete-TestRun)
