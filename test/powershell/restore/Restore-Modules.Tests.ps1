#Requires -Version 7.0
<#
    Tests for Restore-Modules.ps1: leaving an installed module alone and
    installing a missing one, against a stubbed Install-Module.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:TESTKIT_PATH) { throw 'Run this file through powershell/test/Invoke-Tests.ps1' }
Import-Module $env:TESTKIT_PATH -Force

$script = Get-SourcePath -Name 'Restore-Modules.ps1'
$root = New-TestRoot -Name 'restore-modules'

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '1. Everything already installed'
#───────────────────────────────────────────────────────────────────────────────

# Arrange - the shipped manifest; the runner made sure it is satisfied already.
# Common-Modules.psm1 is not this file's own mirror (it lives one level up,
# shared by every powershell/ action), so it is already loaded globally by
# Invoke-TestFile.ps1 rather than reached through Import-SourceModule here.
$shipped = (Get-RequiredModule)[0]
Set-InstallModuleStub

# Act
$kept = Get-Narration { & $script }

# Assert
Assert-That 'reports the module as present' `
    ([bool]($kept.Lines -match "^$($shipped.Name) $($shipped.MinimumVersion)\+ \.\.\. already installed$"))
Assert-Equal 'and installs nothing' 0 (Get-InstallModuleCall).Count

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '2. A module that is missing'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$missing = "NoSuchModule-$([guid]::NewGuid().ToString('N'))"
$manifest = New-RequiredModulesManifest -Path $root -Name 'missing' `
    -Module @(@{ Name = $missing; MinimumVersion = '2.0.0' })
Set-InstallModuleStub

# Act
$installed = Get-Narration { & $script -ManifestPath $manifest }

# Assert
Assert-Equal 'installs it at the manifest''s minimum, from PSGallery' `
    "$missing 2.0.0 PSGallery CurrentUser -Force -SkipPublisherCheck" `
    (Get-InstallModuleCall)[0]
Assert-That 'and says so' ([bool]($installed.Lines -match "^$missing 2\.0\.0\+ \.\.\. installed$"))

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '3. One of each'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$mixed = New-RequiredModulesManifest -Path $root -Name 'mixed' -Module @(
    @{ Name = $shipped.Name; MinimumVersion = "$($shipped.MinimumVersion)" }
    @{ Name = $missing; MinimumVersion = '2.0.0' }
)
Set-InstallModuleStub

# Act
$both = Get-Narration { & $script -ManifestPath $mixed }
$alreadyLines = @($both.Lines -match '^\S+ \S+\+ \.\.\. already installed$')

# Assert
Assert-Equal 'the present module is reported, not installed' 1 $alreadyLines.Count
Assert-Equal 'only the missing one is installed' 1 (Get-InstallModuleCall).Count

exit (Complete-TestRun)
