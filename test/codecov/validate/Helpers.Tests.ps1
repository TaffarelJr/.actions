#Requires -Version 7.0
<#
    Tests for codecov/validate's Helpers.psm1: posting a config file to
    Codecov's validator and interpreting the response.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:TESTKIT_PATH) { throw 'Run this file through powershell/test/Invoke-Tests.ps1' }
Import-Module $env:TESTKIT_PATH -Force
Import-SourceModule 'Helpers'

$root = New-TestRoot -Name 'codecov-validate'
$configPath = Join-Path $root 'codecov.yml'
Set-Content -LiteralPath $configPath -Value 'coverage: {}'

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '1. Invoke-CodecovValidation'
#───────────────────────────────────────────────────────────────────────────────

# Arrange - the validator accepts the file
Set-WebRequestStub -Handler { param($Call) @{ StatusCode = 200; Content = 'valid' } }

# Act
$accepted = Invoke-CodecovValidation -ConfigPath $configPath -Endpoint 'https://example.test/validate'
$calls = Get-WebRequestCall

# Assert
Assert-That 'accepted' $accepted.Valid
Assert-Equal "reports the validator's own response" 'valid' $accepted.Output
Assert-Equal 'posts to the given endpoint' 'https://example.test/validate' $calls[0].Uri
Assert-Equal 'posts as the request method' 'Post' $calls[0].Method
Assert-Equal 'uploads the file itself, not its contents inline' $configPath $calls[0].InFile

# Arrange - the validator rejects the file
Set-WebRequestStub -Handler { param($Call) @{ StatusCode = 422; Content = 'threshold must be a number' } }

# Act
$rejected = Invoke-CodecovValidation -ConfigPath $configPath -Endpoint 'https://example.test/validate'

# Assert
Assert-That 'rejected' (-not $rejected.Valid)
Assert-Equal 'reports why, from the body' 'threshold must be a number' $rejected.Output

# Arrange - a server error is a rejection too, not a special case
Set-WebRequestStub -Handler { param($Call) @{ StatusCode = 500; Content = 'internal error' } }

# Act
$serverError = Invoke-CodecovValidation -ConfigPath $configPath -Endpoint 'https://example.test/validate'

# Assert
Assert-That 'a 5xx is not valid either' (-not $serverError.Valid)

exit (Complete-TestRun)
