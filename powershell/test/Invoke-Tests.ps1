#Requires -Version 7.0

<#
.SYNOPSIS
    Runs every *.Tests.ps1 under a folder,
    each in its own PowerShell process with line coverage,
    and exits with the number of files that failed.

.DESCRIPTION
    Discovery is by pattern and recursive:
    a test lives under the test folder
    at the same relative path as the file it exercises,
    and is picked up by existing.
    A fresh process per file
    keeps module state and stubs from leaking between files,
    so each file only has to reset between its own cases.

    Every file receives the shared harness
    through the TESTKIT_PATH environment variable,
    and finds its source through TEST_ROOT and SOURCE_ROOT.

    Each file runs under Pester's coverage tracer,
    which writes one Cobertura report per file into the output folder,
    mirroring the test's path.
    powershell/restore installs Pester for a workflow;
    this script offers to install it itself when run at a console.

    A file's own output is shown only when it fails, unless -ShowOutput.

.PARAMETER Path
    The folder holding the tests.
    Defaults to 'test' under the current directory.

.PARAMETER Filter
    A wildcard over the file name, without the .Tests.ps1 suffix.

.PARAMETER OutputPath
    Where the coverage reports go. Defaults to 'test/coverage'.

.EXAMPLE
    ./powershell/test/Invoke-Tests.ps1

.EXAMPLE
    ./powershell/test/Invoke-Tests.ps1 -Filter TestKit -ShowOutput
#>
using namespace System.Text

[CmdletBinding()]
param(
    [string]$Path = 'test',
    [string]$Filter = '*',
    [string]$OutputPath = 'test/coverage',
    [switch]$ShowOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..' 'Common-Modules.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Helpers.psm1') -Force

# The files print UTF-8 (the console markers, non-ASCII paths under test);
# without this a Windows console decodes their output as its legacy code page.
[Console]::OutputEncoding = [UTF8Encoding]::new()

Assert-RequiredModule

$run = Invoke-TestRun `
    -Path $Path `
    -Filter $Filter `
    -OutputPath $OutputPath `
    -ShowOutput:$ShowOutput
exit $run.ExitCode
