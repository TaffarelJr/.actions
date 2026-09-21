#Requires -Version 7.0
<#
    Tests for powershell/test's Helpers.psm1: finding and naming test
    files, reading a file's tally, deciding what counts as a failure,
    rendering results, and a real run over a scratch repo with a
    passing, a failing, and a crashing file.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:TESTKIT_PATH) { throw 'Run this file through powershell/test/Invoke-Tests.ps1' }
Import-Module $env:TESTKIT_PATH -Force
Import-SourceModule 'Helpers'

$root = New-TestRoot -Name 'invoke-tests'

function Write-RepoFile {
    <#
    .SYNOPSIS
        Writes a file under the scratch root, creating its folder, and returns
        its full path.
    #>
    param(
        [Parameter(Mandatory)][string]$Relative,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    $path = Join-Path $root $Relative
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path)
    Set-Content -LiteralPath $path -Value $Text
    return $path
}

function Format-Outcome {
    <#
    .SYNOPSIS
        Renders a result's Passed, Failed, ExitCode, and Crashed as one
        comma-separated string, for a single Assert-Equal against all four.
    #>
    param([Parameter(Mandatory)][pscustomobject]$Result)

    return "$($Result.Passed),$($Result.Failed),$($Result.ExitCode),$($Result.Crashed)"
}

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '1. Find-TestFile'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$null = Write-RepoFile 'find/a/Alpha.Tests.ps1' ''
$null = Write-RepoFile 'find/a/b/Beta.Tests.ps1' ''
$null = Write-RepoFile 'find/a/Zed.Tests.ps1' ''
$null = Write-RepoFile 'find/a/Notes.ps1' ''
$null = Write-RepoFile 'find/a/Three.Tests.ps1.bak' ''
$find = Join-Path $root 'find'

# Act
$all = Find-TestFile -Path $find
$one = Find-TestFile -Path $find -Filter 'Beta'
$none = Find-TestFile -Path $find -Filter 'Nothing'

# Assert - Alpha and Zed sit beside each other; Beta is one level deeper, so
# only sorting (not discovery order) can put it between them.
Assert-Equal 'sorted by path, not discovery order' 'Alpha.Tests.ps1,Beta.Tests.ps1,Zed.Tests.ps1' `
    ($all.Name -join ',')
Assert-Equal 'a filter narrows by the name before the suffix' 'Beta.Tests.ps1' ($one.Name -join ',')
Assert-Equal 'no match is an empty array' 0 $none.Count

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '2. Get-TestDisplayName and Get-CoverageReportPath'
#───────────────────────────────────────────────────────────────────────────────

# Act
$nested = Get-TestDisplayName -TestRoot $find -File (Join-Path $find 'a' 'b' 'Beta.Tests.ps1')
$top = Get-TestDisplayName -TestRoot $find -File (Join-Path $find 'Alpha.Tests.ps1')
$report = Get-CoverageReportPath -OutputPath (Join-Path $root 'out') -Name 'a/b/Beta'

# Assert
Assert-Equal 'relative, forward slashes, no suffix' 'a/b/Beta' $nested
Assert-Equal 'a file at the root is just its name' 'Alpha' $top
Assert-Equal 'the report mirrors the name under the output folder' `
    (Join-Path $root 'out' 'a' 'b' 'Beta.cobertura.xml') $report

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '3. Read-TestTally'
#───────────────────────────────────────────────────────────────────────────────

# Act
$clean = Read-TestTally -Output @('  PASS  x', '', '3 passed, 0 failed') -ExitCode 0
$failing = Read-TestTally -Output @('  FAIL  y', '2 passed, 1 failed') -ExitCode 1
$noTally = Read-TestTally -Output @('boom') -ExitCode 0
$silentExit = Read-TestTally -Output @('3 passed, 0 failed') -ExitCode 1
$empty = Read-TestTally -Output @() -ExitCode 1
$twice = Read-TestTally -Output @('1 passed, 0 failed', '5 passed, 2 failed') -ExitCode 2

# Assert
Assert-Equal 'a clean file: its counts, not crashed' '3,0,False' "$($clean.Passed),$($clean.Failed),$($clean.Crashed)"
Assert-Equal 'a failing file: its counts, not crashed' '2,1,False' `
    "$($failing.Passed),$($failing.Failed),$($failing.Crashed)"
Assert-That 'no tally line is a crash, whatever the exit code' $noTally.Crashed
Assert-That 'a failing exit with nothing failed is a crash too' $silentExit.Crashed
Assert-That 'as is no output at all' $empty.Crashed
Assert-Equal 'the last tally line wins' '5,2' "$($twice.Passed),$($twice.Failed)"

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '4. Test-FileFailed'
#───────────────────────────────────────────────────────────────────────────────

# Arrange - a file that crashed silently: no tally, but exited 0 anyway
$silent = [pscustomobject]@{ ExitCode = 0; Crashed = $true }
$clean = [pscustomobject]@{ ExitCode = 0; Crashed = $false }
$failed = [pscustomobject]@{ ExitCode = 1; Crashed = $false }

# Act / Assert
Assert-That 'a crash counts as a failure even at exit 0' (Test-FileFailed -Result $silent)
Assert-That 'a clean exit is not a failure' (-not (Test-FileFailed -Result $clean))
Assert-That 'a non-zero exit is a failure' (Test-FileFailed -Result $failed)

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '5. Format-TestVerdict and Format-TestSummary'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$ok = [pscustomobject]@{ Passed = 4; Failed = 0; Crashed = $false; ExitCode = 0 }
$bad = [pscustomobject]@{ Passed = 3; Failed = 2; Crashed = $false; ExitCode = 2 }
$dead = [pscustomobject]@{ Passed = 0; Failed = 0; Crashed = $true; ExitCode = 1 }

# Act
$verdicts = @($ok, $bad, $dead | ForEach-Object { Format-TestVerdict -Result $_ })
$summary = Format-TestSummary -Results @($ok, $bad, $dead) -Elapsed ([timespan]::FromSeconds(65))
$nothing = Format-TestSummary -Results @() -Elapsed ([timespan]::Zero)

# Assert
Assert-Equal 'a pass shows the count' '✅ 4 passed' $verdicts[0]
Assert-Equal 'a fail shows both counts' '❌ 3 passed, 2 failed' $verdicts[1]
Assert-Equal 'a crash shows the exit code' '💥 crashed (exit 1)' $verdicts[2]
Assert-Equal 'the summary sums the files' '3 file(s) · 7 passed · 2 failed · 1 crashed · 1:05' $summary
Assert-Equal 'and copes with none' '0 file(s) · 0 passed · 0 failed · 0 crashed · 0:00' $nothing

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '6. Write-TestResult'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$loud = [pscustomobject]@{
    Passed = 1; Failed = 1; Crashed = $false; ExitCode = 1; Seconds = 0.5
    Output = @('  PASS  a', '  FAIL  b')
}
$quiet = [pscustomobject]@{
    Passed = 1; Failed = 0; Crashed = $false; ExitCode = 0; Seconds = 0.5
    Output = @('  PASS  a')
}

# Act
$shown = (Get-Narration { Write-TestResult -Result $loud }).Lines
$hidden = (Get-Narration { Write-TestResult -Result $quiet }).Lines
$forced = (Get-Narration { Write-TestResult -Result $quiet -ShowOutput }).Lines

# Assert
Assert-Equal 'a failing file prints its verdict, then its output' 3 $shown.Count
Assert-That 'the verdict names both counts' ([bool]($shown[0] -match '❌ 1 passed, 1 failed\s+0[.,]5s$'))
Assert-Equal 'then the output, indented' '      PASS  a' $shown[1]
Assert-Equal 'a passing file prints only the verdict' 1 $hidden.Count
Assert-Equal 'unless -ShowOutput' 2 $forced.Count

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '7. Invoke-TestRun over a scratch repo'
#───────────────────────────────────────────────────────────────────────────────

# Arrange - a source module, a passing test, a failing test, and one that crashes
$repo = Join-Path $root 'repo'
$null = Write-RepoFile 'repo/src/Thing.psm1' @'
function Get-Thing {
    return 42
}

function Get-Unused {
    return 'never called'
}

Export-ModuleMember -Function Get-Thing, Get-Unused
'@
$null = Write-RepoFile 'repo/test/src/Thing.Pass.Tests.ps1' @'
Import-Module $env:TESTKIT_PATH -Force
Import-SourceModule 'Thing'
Assert-Equal 'answers' 42 (Get-Thing)
Assert-That 'and again' ((Get-Thing) -eq 42)
exit (Complete-TestRun)
'@
$null = Write-RepoFile 'repo/test/src/Thing.Fail.Tests.ps1' @'
Import-Module $env:TESTKIT_PATH -Force
Import-SourceModule 'Thing'
Assert-Equal 'answers' 42 (Get-Thing)
Assert-Equal 'wrongly' 43 (Get-Thing)
exit (Complete-TestRun)
'@
$null = Write-RepoFile 'repo/test/Crash.Tests.ps1' @'
Import-Module $env:TESTKIT_PATH -Force
throw 'boom before any tally'
'@

# Act
$narrated = Get-Narration {
    Invoke-TestRun -Path (Join-Path $repo 'test') -OutputPath (Join-Path $repo 'test' 'coverage')
}
$outcome = $narrated.Output[0]
$byName = @{}
foreach ($result in $outcome.Results) { $byName[$result.Name] = $result }

# Assert - the results
Assert-Equal 'every file ran, in path order' 'Crash,src/Thing.Fail,src/Thing.Pass' ($outcome.Results.Name -join ',')
Assert-Equal 'the passing file: both cases, exit 0' '2,0,0,False' (Format-Outcome $byName['src/Thing.Pass'])
Assert-Equal 'the failing file: one of each, exit 1' '1,1,1,False' (Format-Outcome $byName['src/Thing.Fail'])
Assert-That 'the crashing file is a crash' $byName['Crash'].Crashed
Assert-Equal 'and stays at its sentinel exit code' 1 $byName['Crash'].ExitCode
Assert-That 'and its error is in the captured output' ([bool]($byName['Crash'].Output -match 'boom before any tally'))
Assert-Equal 'two files failed' 2 $outcome.ExitCode

# Assert - what was printed
Assert-That 'a pass line' ([bool]($narrated.Lines -match '✅ 2 passed'))
Assert-That 'a fail line' ([bool]($narrated.Lines -match '❌ 1 passed, 1 failed'))
Assert-That 'a crash line' ([bool]($narrated.Lines -match '💥 crashed'))
Assert-That 'the summary' ([bool]($narrated.Lines -match '^3 file\(s\) · 3 passed · 1 failed · 1 crashed'))

# Assert - the coverage reports
$passReport = Join-Path $repo 'test' 'coverage' 'src' 'Thing.Pass.cobertura.xml'
Assert-That 'one report per file, mirroring its path' (Test-Path -LiteralPath $passReport)
Assert-That 'the crashing file still gets one' `
    (Test-Path -LiteralPath (Join-Path $repo 'test' 'coverage' 'Crash.cobertura.xml'))
$xml = [xml](Get-Content -LiteralPath $passReport -Raw)
$classes = @($xml.SelectNodes('//class'))
$class = @($classes | Where-Object { $_.filename -match 'Thing\.psm1' })
Assert-Equal 'the source module is measured' 1 $class.Count
Assert-Equal 'by a path relative to the repo, not the drive' `
    ($class[0].filename -replace '\\', '/') 'src/Thing.psm1'
$hits = @{}
foreach ($line in $class[0].SelectNodes('lines/line')) { $hits[[int]$line.number] = [int]$line.hits }
Assert-Equal 'the line the reached function returns from was hit' 1 $hits[2]
Assert-Equal 'the line the unused function returns from was not' 0 $hits[6]
Assert-That 'test files themselves are not measured' (-not ($classes.filename -match 'Tests\.ps1'))

# Arrange - the same repo, asking only for the file that passes cleanly
# Act
$greenNarrated = Get-Narration {
    Invoke-TestRun -Path (Join-Path $repo 'test') -OutputPath (Join-Path $repo 'test' 'coverage') -Filter 'Thing.Pass'
}
$green = $greenNarrated.Output[0]

# Assert
Assert-Equal 'a filter runs only the matching file' 'src/Thing.Pass' ($green.Results.Name -join ',')
Assert-Equal 'an all-green run exits 0' 0 $green.ExitCode
Assert-That 'and its summary is the green one' `
    ([bool]($greenNarrated.Lines -match '^1 file\(s\) · 2 passed · 0 failed · 0 crashed'))

# Arrange - a test folder with nothing in it
$bare = New-TestFolder -Path (Join-Path $root 'bare' 'test')

# Act
$emptyRun = Get-Narration { Invoke-TestRun -Path $bare -OutputPath (Join-Path $root 'bare' 'coverage') }

# Assert
Assert-Equal 'no files is a failure' 1 $emptyRun.Output[0].ExitCode
Assert-That 'and says so' ([bool]($emptyRun.Lines -match '^No test file matches'))

exit (Complete-TestRun)
