#Requires -Version 7.0
<#
    Tests for Common-Modules.psm1: reading the manifest, checking and
    installing what it lists, and the check-and-offer that runs before a
    module is needed.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:TESTKIT_PATH) { throw 'Run this file through powershell/test/Invoke-Tests.ps1' }
Import-Module $env:TESTKIT_PATH -Force
Import-SourceModule 'Common-Modules'

$root = New-TestRoot -Name 'common-modules'
$missing = "NoSuchModule-$([guid]::NewGuid().ToString('N'))"
$installCommand = 'Install-Module -Name Pester -MinimumVersion 6.0.0 -Repository PSGallery ' +
'-Scope CurrentUser -Force -SkipPublisherCheck'

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '1. Get-RequiredModule'
#───────────────────────────────────────────────────────────────────────────────

# Act
$shipped = Get-RequiredModule

# Assert
Assert-That 'always an array' ($shipped -is [array])
Assert-Equal 'the shipped manifest lists one module' 1 $shipped.Count
Assert-Equal 'which is Pester' 'Pester' $shipped[0].Name
Assert-That 'at 6.0.0 or newer' ($shipped[0].MinimumVersion -ge [version]'6.0.0')
Assert-That 'with a Uri to its install instructions' ($shipped[0].Uri -match '^https://')

# Arrange
$two = New-RequiredModulesManifest -Path $root -Name 'two' -Module @(
    @{ Name = 'Alpha'; MinimumVersion = '1.2.3' }
    @{ Name = 'Beta'; MinimumVersion = '4.5' }
)

# Act
$listed = Get-RequiredModule -ManifestPath $two

# Assert
Assert-Equal 'every entry is returned, in order' 'Alpha,Beta' ($listed.Name -join ',')
Assert-That 'the version is parsed' ($listed[0].MinimumVersion -is [version])
Assert-Equal 'and kept' '4.5' "$($listed[1].MinimumVersion)"

# Arrange
$empty = New-RequiredModulesManifest -Path $root -Name 'empty' -Module @()

# Act
$none = Get-RequiredModule -ManifestPath $empty

# Assert
Assert-Equal 'an empty manifest lists nothing' 0 $none.Count

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '2. Test-RequiredModule'
#───────────────────────────────────────────────────────────────────────────────

# Act - against what this process really has; the runner made sure Pester 6 is here
$present = Test-RequiredModule -Name Pester -MinimumVersion 6.0.0
$tooOld = Test-RequiredModule -Name Pester -MinimumVersion 999.0.0
$absent = Test-RequiredModule -Name $missing -MinimumVersion 1.0.0

# Assert
Assert-That 'an installed module at or above the minimum' $present
Assert-That 'not when every installed version is below the minimum' (-not $tooOld)
Assert-That 'not when nothing by that name is installed' (-not $absent)

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '3. Get-ModuleInstallCommand'
#───────────────────────────────────────────────────────────────────────────────

# Act
$command = Get-ModuleInstallCommand -Name Pester -MinimumVersion 6.0.0

# Assert
Assert-Equal 'is the exact line a person can paste' $installCommand $command

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '4. Install-RequiredModule'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
Set-InstallModuleStub

# Act
Install-RequiredModule -Name Alpha -MinimumVersion 1.2.3

# Assert
Assert-Equal 'installs from PSGallery, for the current user, forced, past the publisher check' `
    'Alpha 1.2.3 PSGallery CurrentUser -Force -SkipPublisherCheck' `
    (Get-InstallModuleCall)[0]

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '5. Import-RequiredModule'
#───────────────────────────────────────────────────────────────────────────────

# Act
Import-RequiredModule -Name Pester
$pester = Get-Module Pester

# Assert
Assert-That 'the module is loaded at the manifest version or newer' `
    ($null -ne $pester -and $pester.Version -ge [version]'6.0.0')
Assert-Throws 'a module the manifest does not list is refused' `
    { Import-RequiredModule -Name $missing } -Match 'not in'

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '6. Test-InteractiveHost'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$savedCi = $env:CI
$savedActions = $env:GITHUB_ACTIONS
$env:CI = $null
$env:GITHUB_ACTIONS = 'true'

# Act
$inActions = Test-InteractiveHost

# Arrange
$env:GITHUB_ACTIONS = $null
$env:CI = 'true'

# Act
$inCi = Test-InteractiveHost

# Arrange
$env:CI = $null

# Act
$plain = Test-InteractiveHost

# Arrange - restore, so later sections see the real environment
$env:CI = $savedCi
$env:GITHUB_ACTIONS = $savedActions

# Assert
Assert-That 'never in GitHub Actions' (-not $inActions)
Assert-That 'never under any CI' (-not $inCi)
Assert-Equal 'otherwise, whether stdin is a console' (-not [Console]::IsInputRedirected) $plain

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '7. Assert-RequiredModule'
#───────────────────────────────────────────────────────────────────────────────

# Arrange - everything present, and an answer ready in case it wrongly asks
$satisfied = New-RequiredModulesManifest -Path $root -Name 'satisfied' `
    -Module @(@{ Name = 'Pester'; MinimumVersion = '6.0.0' })
Set-InstallModuleStub
Set-ReadHostAnswer 'n'

# Act
$quiet = Get-Narration { Assert-RequiredModule -ManifestPath $satisfied -Interactive $true }

# Assert
Assert-Equal 'says nothing' 0 $quiet.Lines.Count
Assert-Equal 'installs nothing' 0 (Get-InstallModuleCall).Count

# Arrange - a missing module, nobody at the console
$unmet = New-RequiredModulesManifest -Path $root -Name 'unmet' `
    -Module @(@{ Name = $missing; MinimumVersion = '1.0.0' })

# Act / Assert
Assert-Throws 'fails, naming the module, the restore step, and the command' `
    { Assert-RequiredModule -ManifestPath $unmet -Interactive $false } `
    -Match "(?s)$missing 1\.0\.0 or newer.*powershell/restore.*Install-Module -Name $missing.*example\.test"
Assert-Equal 'and installs nothing on its own' 0 (Get-InstallModuleCall).Count

# Arrange - nobody at the console, CI's own default
$env:CI = 'true'

# Act / Assert
Assert-Throws 'in CI, the default -Interactive resolves to false too' `
    { Assert-RequiredModule -ManifestPath $unmet } -Match "$missing 1\.0\.0"
$env:CI = $savedCi
Assert-Equal 'still installs nothing' 0 (Get-InstallModuleCall).Count

# Arrange - a person who declines
Set-ReadHostAnswer 'n'

# Act / Assert
Assert-Throws 'fails the same way' `
    { Assert-RequiredModule -ManifestPath $unmet -Interactive $true 3>$null } `
    -Match 'Install-Module'
Assert-Equal 'without installing' 0 (Get-InstallModuleCall).Count

# Arrange - the multi-word "no" a person might type instead of "n"
Set-ReadHostAnswer 'no'

# Act / Assert
Assert-Throws 'a longer no still declines' `
    { Assert-RequiredModule -ManifestPath $unmet -Interactive $true 3>$null } `
    -Match 'Install-Module'
Assert-Equal 'installs nothing' 0 (Get-InstallModuleCall).Count

foreach ($accept in 'y', 'Y', 'yes', '') {
    # Arrange - every answer that means yes, including the default (Enter)
    Set-InstallModuleStub
    Set-ReadHostAnswer $accept

    # Act
    $accepted = Get-Narration { Assert-RequiredModule -ManifestPath $unmet -Interactive $true 3>$null }

    # Assert
    Assert-Equal "'$accept' installs it" "$missing 1.0.0 PSGallery CurrentUser -Force -SkipPublisherCheck" `
        (Get-InstallModuleCall)[0]
    Assert-That "'$accept' says so" ([bool]($accepted.Lines -match '^Installing .* done$'))
}

# Arrange - a stray answer that is neither yes nor no
Set-InstallModuleStub
Set-ReadHostAnswer 'x'

# Act / Assert
Assert-Throws 'anything else declines, same as no' `
    { Assert-RequiredModule -ManifestPath $unmet -Interactive $true 3>$null } `
    -Match 'Install-Module'
Assert-Equal 'installs nothing' 0 (Get-InstallModuleCall).Count

# Arrange - a manifest with a satisfied module ahead of a missing one
$mixed = New-RequiredModulesManifest -Path $root -Name 'mixed' -Module @(
    @{ Name = 'Pester'; MinimumVersion = '6.0.0' }
    @{ Name = $missing; MinimumVersion = '1.0.0' }
)
Set-InstallModuleStub
Set-ReadHostAnswer 'y'

# Act
$null = Get-Narration { Assert-RequiredModule -ManifestPath $mixed -Interactive $true 3>$null }

# Assert
Assert-Equal 'the satisfied module is skipped, only the missing one installs' 1 (Get-InstallModuleCall).Count
Assert-That 'and it is the missing one' ((Get-InstallModuleCall)[0] -match "^$missing ")

# Arrange - nothing required at all
$empty = New-RequiredModulesManifest -Path $root -Name 'nothing-required' -Module @()
Set-InstallModuleStub

# Act
$nothing = Get-Narration { Assert-RequiredModule -ManifestPath $empty -Interactive $true }

# Assert
Assert-Equal 'an empty manifest asks and installs nothing' 0 $nothing.Lines.Count
Assert-Equal 'installs nothing' 0 (Get-InstallModuleCall).Count

exit (Complete-TestRun)
