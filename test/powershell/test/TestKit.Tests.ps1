#Requires -Version 7.0
<#
    Tests for TestKit.psm1's Get-SourcePath: the two branches nothing in this
    repo's own test suite exercises - no TEST_ROOT/SOURCE_ROOT, and no -Name.

    Deliberately does not Import-SourceModule 'TestKit': that would re-import,
    with -Force, the very module this file runs under, resetting its tally
    mid-run. Every function under test is already in scope from the
    TESTKIT_PATH import every file does.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:TESTKIT_PATH) { throw 'Run this file through powershell/test/Invoke-Tests.ps1' }
Import-Module $env:TESTKIT_PATH -Force

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '1. Get-SourcePath without TEST_ROOT or SOURCE_ROOT'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$savedTestRoot = $env:TEST_ROOT
$savedSourceRoot = $env:SOURCE_ROOT
$env:TEST_ROOT = $null
$env:SOURCE_ROOT = $null

# Act / Assert
Assert-Throws 'fails, naming the script that should have set them' `
    { Get-SourcePath } -Match 'Invoke-Tests\.ps1'

# Arrange - restore, so section 2 (and every later file) sees the real mirror
$env:TEST_ROOT = $savedTestRoot
$env:SOURCE_ROOT = $savedSourceRoot

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '2. Get-SourcePath without -Name'
#───────────────────────────────────────────────────────────────────────────────

# Act
$folder = Get-SourcePath
$file = Get-SourcePath -Name 'TestKit.psm1'

# Assert
Assert-Equal 'returns the mirrored folder itself' (Split-Path -Parent $file) $folder

exit (Complete-TestRun)
