#Requires -Version 7.0

<#
.SYNOPSIS
    Runs one test file under Pester's coverage tracer,
    writes its Cobertura report, and exits with the file's own exit code.

.DESCRIPTION
    Pester is only the coverage collector.
    The file runs as-is inside one It block:
    its assertions, its tally line, and its `exit` are its own
    and pass straight through, which is what Invoke-Tests.ps1 reads.
    Pester's own output is off so nothing else lands in between.

    This process is single-use, so TESTKIT_PATH, TEST_ROOT, and SOURCE_ROOT
    are set here rather than inherited:
    the test file reads them through Get-SourcePath,
    and nothing has to be restored afterwards.

.PARAMETER TestFile
    The *.Tests.ps1 to run.

.PARAMETER TestKitPath
    The harness to hand the test file, through TESTKIT_PATH.

.PARAMETER TestRoot
    The folder the test file's path is mirrored under, through TEST_ROOT.

.PARAMETER SourceRoot
    The folder the mirror resolves into, through SOURCE_ROOT.
    Its *.ps1 and *.psm1 files are also what coverage measures, recursively,
    test files excluded.

.PARAMETER OutputPath
    The Cobertura XML to write.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TestFile,
    [Parameter(Mandatory)][string]$TestKitPath,
    [Parameter(Mandatory)][string]$TestRoot,
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$env:TESTKIT_PATH = $TestKitPath
$env:TEST_ROOT = $TestRoot
$env:SOURCE_ROOT = $SourceRoot

Import-Module (Join-Path $PSScriptRoot '..' 'Common-Modules.psm1') -Force
Import-RequiredModule -Name Pester

$state = @{ ExitCode = 1 } # Stays 1 - crashed - unless the file reaches its own exit.

$container = New-PesterContainer -Data @{ TestFile = $TestFile; State = $state } -ScriptBlock {
    param([string]$TestFile, [hashtable]$State)

    Describe $TestFile {
        It 'runs to its own exit' {
            & $TestFile
            $State.ExitCode = $LASTEXITCODE
        }
    }
}

$configuration = New-PesterConfiguration
$configuration.Run.Container = $container
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'None'
$configuration.CodeCoverage.Enabled = $true
$configuration.CodeCoverage.Path = $SourceRoot
$configuration.CodeCoverage.ExcludeTests = $true
$configuration.CodeCoverage.ReportRoot = $SourceRoot
$configuration.CodeCoverage.OutputFormat = 'Cobertura'
$configuration.CodeCoverage.OutputPath = $OutputPath
# Breakpoints need a debugger, which a -NonInteractive host does not have.
$configuration.CodeCoverage.UseBreakpoints = $false

$run = Invoke-Pester -Configuration $configuration

# With Pester's output off, a crash inside the file would otherwise vanish.
foreach ($test in $run.Failed) {
    foreach ($record in $test.ErrorRecord) {
        Write-Host $record.Exception.Message
        Write-Host $record.ScriptStackTrace
    }
}

exit $state.ExitCode
