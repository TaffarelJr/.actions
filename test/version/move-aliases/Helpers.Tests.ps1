#Requires -Version 7.0
<#
    Tests for version/move-aliases's Helpers.psm1: validating a release
    tag, deriving the two aliases it moves, and listing every real tag.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:TESTKIT_PATH) { throw 'Run this file through powershell/test/Invoke-Tests.ps1' }
Import-Module $env:TESTKIT_PATH -Force
Import-SourceModule 'Helpers'

$repo = 'TaffarelJr/.actions'

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '1. Assert-ReleaseTag'
#───────────────────────────────────────────────────────────────────────────────

# Act / Assert
Assert-That 'a real vX.Y.Z tag passes silently' ($null -eq (Assert-ReleaseTag -Tag 'v1.4.2'))
Assert-Throws 'a pre-release suffix is rejected' { Assert-ReleaseTag -Tag 'v1.4.2-alpha.1' } 'not a vX\.Y\.Z release tag'
Assert-Throws 'a missing v is rejected' { Assert-ReleaseTag -Tag '1.4.2' } 'not a vX\.Y\.Z release tag'
Assert-Throws 'an empty tag is rejected' { Assert-ReleaseTag -Tag '' } 'not a vX\.Y\.Z release tag'

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '2. Get-AliasesForTag'
#───────────────────────────────────────────────────────────────────────────────

# Act
$aliases = Get-AliasesForTag -Tag 'v1.4.2'
$doubleDigit = Get-AliasesForTag -Tag 'v12.34.56'

# Assert
Assert-Equal 'the major alias' 'v1' $aliases.Major
Assert-Equal 'the major.minor alias' 'v1.4' $aliases.Minor
Assert-Equal 'multi-digit components are not truncated' 'v12' $doubleDigit.Major
Assert-Equal 'multi-digit components are not truncated' 'v12.34' $doubleDigit.Minor

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '3. Get-ReleaseTags'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
Set-GhStub -Handler { param($ArgList) @{ Exit = 0; Out = @('v1.0.0', 'v1.1.0', 'v1.1.1') } }

# Act
$tags = Get-ReleaseTags -Repository $repo

# Assert
Assert-Equal 'returns every tag gh reports' 'v1.0.0,v1.1.0,v1.1.1' ($tags -join ',')
Assert-That 'asked gh for every tag, paginated' (Test-GhCall 'tags.*--paginate')

exit (Complete-TestRun)
