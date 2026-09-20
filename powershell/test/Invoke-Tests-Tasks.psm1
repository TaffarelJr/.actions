#Requires -Version 7.0
<#
    Finds the test files, runs each in its own pwsh under Invoke-TestFile.ps1,
    reads the tally each prints, and sums them up.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:WrapperPath = Join-Path $PSScriptRoot 'Invoke-TestFile.ps1'
$script:TestKitPath = Join-Path $PSScriptRoot 'TestKit.psm1'

#───────────────────────────────────────────────────────────────────────────────
# Finding and naming
#───────────────────────────────────────────────────────────────────────────────

function Find-TestFile {
    <#
    .SYNOPSIS
        Returns every *.Tests.ps1 under a folder whose name matches the filter,
        sorted by path, always as an array.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Filter = '*'
    )

    $files = Get-ChildItem -LiteralPath $Path -Recurse -File -Filter "$Filter.Tests.ps1"
    return , @($files | Sort-Object FullName)
}

function Get-TestDisplayName {
    <#
    .SYNOPSIS
        Returns a test file's path relative to the test folder, without the
        suffix and with forward slashes, so two files of the same name in
        different folders still read apart.
    #>
    param(
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][string]$File
    )

    $relative = [System.IO.Path]::GetRelativePath($TestRoot, $File)
    return ($relative -replace '\.Tests\.ps1$' -replace '\\', '/')
}

function Get-CoverageReportPath {
    <#
    .SYNOPSIS
        Returns where a test file's coverage report goes: its display name
        under the output folder, as Cobertura XML.
    #>
    param(
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$Name
    )

    $relative = $Name -replace '/', [System.IO.Path]::DirectorySeparatorChar
    return Join-Path $OutputPath "$relative.cobertura.xml"
}

#───────────────────────────────────────────────────────────────────────────────
# Reading and rendering a result
#───────────────────────────────────────────────────────────────────────────────

function Read-TestTally {
    <#
    .SYNOPSIS
        Reads a file's "N passed, M failed" line out of its output, and decides
        whether it crashed: no tally at all, or a failing exit with nothing
        failed.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Output,
        [Parameter(Mandatory)][int]$ExitCode
    )

    $tallyLine = @($Output -match '^(\d+) passed, (\d+) failed$') | Select-Object -Last 1
    $tally = if ($tallyLine) { [regex]::Match($tallyLine, '^(\d+) passed, (\d+) failed$') }

    $passed = if ($tally) { [int]$tally.Groups[1].Value } else { 0 }
    $failed = if ($tally) { [int]$tally.Groups[2].Value } else { 0 }

    return [pscustomobject]@{
        Passed  = $passed
        Failed  = $failed
        Crashed = -not $tally -or ($ExitCode -ne 0 -and $failed -eq 0)
    }
}

function Test-FileFailed {
    <#
    .SYNOPSIS
        Reports whether a file's result should count as a failure of the run:
        a non-zero exit, or a crash even at exit 0.
    #>
    param([Parameter(Mandatory)][pscustomobject]$Result)

    return $Result.ExitCode -ne 0 -or $Result.Crashed
}

function Format-TestVerdict {
    <#
    .SYNOPSIS
        Renders one file's result the way the runner prints it.
    #>
    param([Parameter(Mandatory)][pscustomobject]$Result)

    if ($Result.Crashed) { return "💥 crashed (exit $($Result.ExitCode))" }
    if ($Result.ExitCode -ne 0) { return "❌ $($Result.Passed) passed, $($Result.Failed) failed" }
    return "✅ $($Result.Passed) passed"
}

function Format-TestSummary {
    <#
    .SYNOPSIS
        Renders the closing line: files, cases passed and failed, crashes,
        and the wall time.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Results,
        [Parameter(Mandatory)][timespan]$Elapsed
    )

    $passed = 0
    $failed = 0
    $crashed = 0
    foreach ($result in $Results) {
        $passed += $result.Passed
        $failed += $result.Failed
        if ($result.Crashed) { $crashed++ }
    }

    return '{0} file(s) · {1} passed · {2} failed · {3} crashed · {4:m\:ss}' -f @(
        $Results.Count
        $passed
        $failed
        $crashed
        $Elapsed
    )
}

function Write-TestResult {
    <#
    .SYNOPSIS
        Prints one file's verdict and time, then its output when it failed or
        -ShowOutput asked for it.
    #>
    param(
        [Parameter(Mandatory)][pscustomobject]$Result,
        [switch]$ShowOutput
    )

    $verdict = Format-TestVerdict -Result $Result
    $seconds = '{0,6:N1}s' -f $Result.Seconds
    $color = if ($Result.ExitCode -eq 0) { 'Green' } else { 'Red' }
    Write-Host " $verdict  $seconds" -ForegroundColor $color

    if (-not $ShowOutput -and $Result.ExitCode -eq 0) { return }
    foreach ($line in $Result.Output) { Write-Host "    $line" }
}

#───────────────────────────────────────────────────────────────────────────────
# Running
#───────────────────────────────────────────────────────────────────────────────

function Invoke-TestFileProcess {
    <#
    .SYNOPSIS
        Runs one test file in a fresh pwsh under the coverage wrapper and
        returns its result: name, tally, exit code, time, and captured output.
    #>
    param(
        [Parameter(Mandatory)][string]$File,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$TestRoot,
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][string]$ReportPath
    )

    $pwsh = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $arguments = @(
        '-NoProfile', '-NonInteractive', '-File', $script:WrapperPath
        '-TestFile', $File
        '-TestKitPath', $script:TestKitPath
        '-TestRoot', $TestRoot
        '-SourceRoot', $SourceRoot
        '-OutputPath', $ReportPath
    )

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $raw = & $pwsh @arguments 2>&1
    $exitCode = $LASTEXITCODE
    $clock.Stop()

    $output = @($raw | ForEach-Object { "$_" })
    $tally = Read-TestTally -Output $output -ExitCode $exitCode

    return [pscustomobject]@{
        Name     = $Name
        Passed   = $tally.Passed
        Failed   = $tally.Failed
        Crashed  = $tally.Crashed
        ExitCode = $exitCode
        Seconds  = $clock.Elapsed.TotalSeconds
        Output   = $output
    }
}

function Invoke-TestRun {
    <#
    .SYNOPSIS
        Runs every matching test file under coverage, prints each result and
        the summary, and returns the results with the exit code to end with:
        the number of failed files, or 1 when there were no files at all.
    .DESCRIPTION
        The source folder measured for coverage is the test folder's own
        parent, since a test always mirrors its source one level down.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$OutputPath,
        [string]$Filter = '*',
        [switch]$ShowOutput
    )

    $testRoot = (Resolve-Path -LiteralPath $Path).Path
    $sourceRoot = Split-Path -Parent $testRoot
    $files = Find-TestFile -Path $testRoot -Filter $Filter
    if (-not $files) {
        Write-Host "No test file matches '$Filter.Tests.ps1' under $testRoot" -ForegroundColor Yellow
        return [pscustomobject]@{ Results = @(); ExitCode = 1 }
    }

    $reportRoot = (New-Item -ItemType Directory -Force -Path $OutputPath).FullName

    $total = [System.Diagnostics.Stopwatch]::StartNew()
    $results = foreach ($file in $files) {
        $name = Get-TestDisplayName -TestRoot $testRoot -File $file.FullName
        $reportPath = Get-CoverageReportPath -OutputPath $reportRoot -Name $name
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $reportPath)

        Write-Host "▶ $name ..." -NoNewline -ForegroundColor Cyan
        if ($ShowOutput) { Write-Host '' }

        $result = Invoke-TestFileProcess `
            -File $file.FullName `
            -Name $name `
            -TestRoot $testRoot `
            -SourceRoot $sourceRoot `
            -ReportPath $reportPath
        Write-TestResult -Result $result -ShowOutput:$ShowOutput
        $result
    }
    $total.Stop()

    $failedFiles = @($results | Where-Object { Test-FileFailed -Result $_ })
    $color = if ($failedFiles) { 'Red' } else { 'Green' }
    $summary = Format-TestSummary -Results @($results) -Elapsed $total.Elapsed
    Write-Host ''
    Write-Host $summary -ForegroundColor $color
    Write-Host "Coverage reports in $reportRoot" -ForegroundColor DarkGray

    return [pscustomobject]@{ Results = @($results); ExitCode = $failedFiles.Count }
}

Export-ModuleMember -Function @(
    'Find-TestFile'
    'Get-TestDisplayName'
    'Get-CoverageReportPath'
    'Read-TestTally'
    'Test-FileFailed'
    'Format-TestVerdict'
    'Format-TestSummary'
    'Write-TestResult'
    'Invoke-TestFileProcess'
    'Invoke-TestRun'
)
