#Requires -Version 7.0

<#
.SYNOPSIS
    Runs every *.Tests.ps1 under a folder, each in its own PowerShell process,
    and exits with the number of files that failed.

.DESCRIPTION
    Discovery is by pattern and recursive, so an action gets coverage by
    dropping a <Module>.Tests.ps1 beside the module it exercises - nothing here
    is edited. A fresh process per file keeps module state and the gh and
    Read-Host stubs from leaking between files, so each file only has to reset
    between its own cases.

    Every file receives the shared harness through the TESTKIT_PATH environment
    variable, which is what lets a file live anywhere in the repo without
    knowing where the harness is.

    A file's own output is shown only when it fails, unless -ShowOutput.

.PARAMETER Path
    The folder to search. Defaults to the current directory.

.PARAMETER Filter
    A wildcard over the file name, without the .Tests.ps1 suffix.

.PARAMETER TestKitPath
    The harness to hand every file. Defaults to the TestKit.psm1 beside this
    script.

.EXAMPLE
    ./test-scripts/Run-Tests.ps1

.EXAMPLE
    ./test-scripts/Run-Tests.ps1 -Filter New-Changelog-Tasks -ShowOutput
#>
[CmdletBinding()]
param(
    [string]$Path = '.',
    [string]$Filter = '*',
    [string]$TestKitPath = (Join-Path $PSScriptRoot 'TestKit.psm1'),
    [switch]$ShowOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The files print UTF-8 (the console markers, non-ASCII paths under test);
# without this a Windows console decodes their output as its legacy code page.
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$root = (Resolve-Path -LiteralPath $Path).Path
$files = Get-ChildItem -Path $root -Recurse -Filter "$Filter.Tests.ps1" -File |
    Sort-Object FullName
if (-not $files) {
    Write-Host "No test file matches '$Filter.Tests.ps1' under $root" -ForegroundColor Yellow
    exit 1
}

# Inherited by each child process, which is how a file finds the harness.
$env:TESTKIT_PATH = (Resolve-Path -LiteralPath $TestKitPath).Path

$pwsh = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$total = [System.Diagnostics.Stopwatch]::StartNew()
$results = foreach ($file in $files) {
    # Shown relative to the root and without the suffix, so two modules with
    # the same name in different folders still read apart.
    $name = [System.IO.Path]::GetRelativePath($root, $file.FullName) `
        -replace '\.Tests\.ps1$' -replace '\\', '/'
    Write-Host "▶ $name ..." -NoNewline -ForegroundColor Cyan
    if ($ShowOutput) { Write-Host '' }

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $output = @(& $pwsh -NoProfile -NonInteractive -File $file.FullName 2>&1 |
            ForEach-Object { "$_" })
    $exitCode = $LASTEXITCODE
    $clock.Stop()

    # The file's own tally line; absent when it crashed before reaching one.
    $tally = @($output -match '^(\d+) passed, (\d+) failed$') | Select-Object -Last 1
    $passed = if ($tally) { [int]($tally -replace ' passed.*') } else { 0 }
    $failed = if ($tally) { [int]($tally -replace '.* passed, ' -replace ' failed') } else { 0 }
    $crashed = -not $tally -or ($exitCode -ne 0 -and $failed -eq 0)

    $seconds = '{0,6:N1}s' -f $clock.Elapsed.TotalSeconds
    $verdict = if ($crashed) { "💥 crashed (exit $exitCode)" }
    elseif ($exitCode -ne 0) { "❌ $passed passed, $failed failed" }
    else { "✅ $passed passed" }
    $color = if ($exitCode -eq 0) { 'Green' } else { 'Red' }
    Write-Host " $verdict  $seconds" -ForegroundColor $color

    if ($ShowOutput -or $exitCode -ne 0) {
        foreach ($line in $output) { Write-Host "    $line" }
    }

    [pscustomobject]@{
        Name     = $name
        Passed   = $passed
        Failed   = $failed
        Crashed  = $crashed
        ExitCode = $exitCode
    }
}

$total.Stop()
$failedFiles = @($results | Where-Object { $_.ExitCode -ne 0 })
$summary = '{0} file(s) · {1} passed · {2} failed · {3} crashed · {4:m\:ss}' -f @(
    $results.Count
    ($results | Measure-Object Passed -Sum).Sum
    ($results | Measure-Object Failed -Sum).Sum
    @($results | Where-Object Crashed).Count
    $total.Elapsed
)

$color = if ($failedFiles) { 'Red' } else { 'Green' }
Write-Host "`n$summary" -ForegroundColor $color
exit $failedFiles.Count
