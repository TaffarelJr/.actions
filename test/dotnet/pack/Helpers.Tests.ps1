#Requires -Version 7.0
<#
    Tests for dotnet/pack's Helpers.psm1: packing the solution, stamping
    in a version when there is one, and skipping cleanly - both when there
    is nothing to pack, and when packing produced no package at all.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:TESTKIT_PATH) { throw 'Run this file through powershell/test/Invoke-Tests.ps1' }
Import-Module $env:TESTKIT_PATH -Force

# Common-Build.psm1 is a sibling of the action folder this file mirrors,
# not inside it - Import-SourceModule only ever looks in the mirror itself.
Import-Module (Join-Path (Get-SourcePath) '..' 'Common-Build.psm1') -Force -Global
Import-SourceModule 'Helpers'

function New-DotnetStubWithPackage {
    <#
    .SYNOPSIS
        Installs a dotnet stub that, like a real pack, drops a fake .nupkg
        into whatever --output it was given.
    #>
    Set-DotnetStub -Handler {
        param($Argv)
        $index = [array]::IndexOf($Argv, '--output')
        if ($index -ge 0) {
            $null = New-Item -ItemType Directory -Force -Path $Argv[$index + 1]
            Set-Content -LiteralPath (Join-Path $Argv[$index + 1] 'Placeholder.1.0.0.nupkg') -Value ''
        }
        return @{}
    }
}

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '1. Invoke-Pack'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$noProjects = [pscustomobject]@{ HasProjects = $false }
Set-DotnetStub -Handler { return @{} }

# Act
Invoke-Pack -Context $noProjects

# Assert
Assert-Equal 'no projects means no dotnet call at all' 0 (Get-DotnetCall).Count

# Arrange
$artifactPath = Join-Path (New-TestRoot -Name 'dotnet-pack-unversioned') 'artifacts'
$unversioned = [pscustomobject]@{
    HasProjects   = $true
    Solution      = 'C:\repo\Placeholder.slnx'
    Configuration = 'Release'
    Version       = ''
    ArtifactPath  = $artifactPath
}
New-DotnetStubWithPackage

# Act
$unversionedNarration = Get-Narration { Invoke-Pack -Context $unversioned }

# Assert
Assert-That 'packs the solution, into the artifact path, in the given configuration' `
    (Test-DotnetCall ([regex]::Escape("pack C:\repo\Placeholder.slnx --nologo --no-build --configuration Release --output $artifactPath")))
Assert-Equal 'a package was produced, so nothing is reported as skipped' 0 $unversionedNarration.Lines.Count

# Arrange
$versionedRoot = Join-Path (New-TestRoot -Name 'dotnet-pack-versioned') 'artifacts'
$versioned = [pscustomobject]@{
    HasProjects   = $true
    Solution      = 'C:\repo\Placeholder.slnx'
    Configuration = 'Debug'
    Version       = '1.2.3'
    ArtifactPath  = $versionedRoot
}
New-DotnetStubWithPackage

# Act
Invoke-Pack -Context $versioned

# Assert
Assert-That 'a version stamps -p:Version and -p:PackageVersion too' `
    (Test-DotnetCall ([regex]::Escape("pack C:\repo\Placeholder.slnx --nologo --no-build --configuration Debug --output $versionedRoot -p:Version=1.2.3 -p:PackageVersion=1.2.3")))

# Arrange - the pack succeeds, but no project was actually packable
$unpackableRoot = Join-Path (New-TestRoot -Name 'dotnet-pack-none') 'artifacts'
$unpackable = [pscustomobject]@{
    HasProjects   = $true
    Solution      = 'C:\repo\Placeholder.slnx'
    Configuration = 'Release'
    Version       = ''
    ArtifactPath  = $unpackableRoot
}
Set-DotnetStub -Handler { return @{} }

# Act
$unpackableNarration = Get-Narration { Invoke-Pack -Context $unpackable }

# Assert
Assert-Equal 'no .nupkg means the run is reported as skipped, not failed' 1 $unpackableNarration.Lines.Count
Assert-That 'naming why' ([bool]($unpackableNarration.Lines[0] -match 'no project is packable'))

# Arrange
Set-DotnetStub -Handler { return @{ Exit = 1 } }

# Act / Assert
Assert-Throws 'a failing pack throws, naming the exit code' `
    { Invoke-Pack -Context $unversioned } -Match 'dotnet pack failed with exit code 1'

exit (Complete-TestRun)
