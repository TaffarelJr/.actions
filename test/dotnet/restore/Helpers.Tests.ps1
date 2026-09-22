#Requires -Version 7.0
<#
    Tests for dotnet/restore's Helpers.psm1: restoring tools and packages,
    and skipping each cleanly when there is nothing to restore.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:TESTKIT_PATH) { throw 'Run this file through powershell/test/Invoke-Tests.ps1' }
Import-Module $env:TESTKIT_PATH -Force

# Common-Build.psm1 is a sibling of the action folder this file mirrors,
# not inside it - Import-SourceModule only ever looks in the mirror itself.
Import-Module (Join-Path (Get-SourcePath) '..' 'Common-Build.psm1') -Force -Global
Import-SourceModule 'Helpers'

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '1. Restore-Tool'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$noManifest = New-TestRoot -Name 'dotnet-restore-no-manifest'
$context = [pscustomobject]@{ RepoRoot = $noManifest }
Set-DotnetStub -Handler { return @{} }

# Act
Restore-Tool -Context $context

# Assert
Assert-Equal 'no manifest means no dotnet call at all' 0 (Get-DotnetCall).Count

# Arrange
$withManifest = New-TestRoot -Name 'dotnet-restore-with-manifest'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $withManifest '.config')
Set-Content -LiteralPath (Join-Path $withManifest '.config' 'dotnet-tools.json') -Value '{}'
$toolContext = [pscustomobject]@{ RepoRoot = $withManifest }
Set-DotnetStub -Handler { return @{} }

# Act
Restore-Tool -Context $toolContext

# Assert
Assert-That 'a manifest means dotnet tool restore runs' (Test-DotnetCall '^tool restore$')

# Arrange
Set-DotnetStub -Handler { return @{ Exit = 1 } }

# Act / Assert
Assert-Throws 'a failing tool restore throws, naming the exit code' `
    { Restore-Tool -Context $toolContext } -Match 'dotnet tool restore failed with exit code 1'

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '2. Restore-Package'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$noProjects = [pscustomobject]@{ HasProjects = $false }
Set-DotnetStub -Handler { return @{} }

# Act
Restore-Package -Context $noProjects

# Assert
Assert-Equal 'no projects means no dotnet call at all' 0 (Get-DotnetCall).Count

# Arrange
$hasProjects = [pscustomobject]@{ HasProjects = $true; Solution = 'C:\repo\Placeholder.slnx' }
Set-DotnetStub -Handler { return @{} }

# Act
Restore-Package -Context $hasProjects

# Assert
Assert-That 'projects means dotnet restore runs against the solution' `
    (Test-DotnetCall '^restore C:\\repo\\Placeholder\.slnx --nologo$')

# Arrange
Set-DotnetStub -Handler { return @{ Exit = 1 } }

# Act / Assert
Assert-Throws 'a failing restore throws, naming the exit code' `
    { Restore-Package -Context $hasProjects } -Match 'dotnet restore failed with exit code 1'

exit (Complete-TestRun)
