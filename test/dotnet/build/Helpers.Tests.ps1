#Requires -Version 7.0
<#
    Tests for dotnet/build's Helpers.psm1: building the solution, stamping
    in a version when there is one, and skipping cleanly when there is
    nothing to build.
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
Write-TestSection '1. Invoke-Build'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$noProjects = [pscustomobject]@{ HasProjects = $false }
Set-DotnetStub -Handler { return @{} }

# Act
Invoke-Build -Context $noProjects

# Assert
Assert-Equal 'no projects means no dotnet call at all' 0 (Get-DotnetCall).Count

# Arrange
$unversioned = [pscustomobject]@{
    HasProjects   = $true
    Solution      = 'C:\repo\Placeholder.slnx'
    Configuration = 'Release'
    Version       = ''
}
Set-DotnetStub -Handler { return @{} }

# Act
Invoke-Build -Context $unversioned

# Assert
Assert-That 'builds the solution, in the given configuration' `
    (Test-DotnetCall '^build C:\\repo\\Placeholder\.slnx --nologo --no-restore --configuration Release$')

# Arrange
$versioned = [pscustomobject]@{
    HasProjects   = $true
    Solution      = 'C:\repo\Placeholder.slnx'
    Configuration = 'Debug'
    Version       = '1.2.3'
}
Set-DotnetStub -Handler { return @{} }

# Act
Invoke-Build -Context $versioned

# Assert
Assert-That 'a version stamps -p:Version and -p:PackageVersion too' `
    (Test-DotnetCall '^build C:\\repo\\Placeholder\.slnx --nologo --no-restore --configuration Debug -p:Version=1\.2\.3 -p:PackageVersion=1\.2\.3$')

# Arrange
Set-DotnetStub -Handler { return @{ Exit = 1 } }

# Act / Assert
Assert-Throws 'a failing build throws, naming the exit code' `
    { Invoke-Build -Context $unversioned } -Match 'dotnet build failed with exit code 1'

exit (Complete-TestRun)
