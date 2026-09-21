#Requires -Version 7.0
<#
    Tests for codecov/upload's Helpers.psm1: picking the right binary,
    finding what to upload, building codecovcli's arguments, and the
    group-by-subfolder policy that decides what gets flagged.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:TESTKIT_PATH) { throw 'Run this file through powershell/test/Invoke-Tests.ps1' }
Import-Module $env:TESTKIT_PATH -Force
Import-SourceModule 'Helpers'

$root = New-TestRoot -Name 'codecov-upload'

function Write-CoverageFile {
    <#
    .SYNOPSIS
        Writes a fake coverage report under the scratch root, creating its
        folder, and returns its full path.
    #>
    param([Parameter(Mandatory)][string]$Relative)

    $path = Join-Path $root $Relative
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path)
    Set-Content -LiteralPath $path -Value '<coverage/>'
    return (Resolve-Path -LiteralPath $path).Path
}

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '1. Get-CodecovCliUrl and Get-CodecovCliFileName'
#───────────────────────────────────────────────────────────────────────────────

# Act
$windowsUrl = Get-CodecovCliUrl -IsWindows $true
$linuxUrl = Get-CodecovCliUrl -IsWindows $false
$windowsName = Get-CodecovCliFileName -IsWindows $true
$linuxName = Get-CodecovCliFileName -IsWindows $false

# Assert
Assert-Equal 'Windows gets the .exe binary' 'https://cli.codecov.io/latest/windows/codecov.exe' $windowsUrl
Assert-Equal 'anything else gets the Linux binary' 'https://cli.codecov.io/latest/linux/codecov' $linuxUrl
Assert-Equal 'Windows file name' 'codecov.exe' $windowsName
Assert-Equal 'Linux file name' 'codecov' $linuxName

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '2. Find-CoverageGroup'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$empty = Join-Path $root 'empty'
$null = New-Item -ItemType Directory -Force -Path $empty

# Act
$none = Find-CoverageGroup -Path $empty -Pattern '*.cobertura.xml'
$missing = Find-CoverageGroup -Path (Join-Path $root 'nope') -Pattern '*.cobertura.xml'

# Assert
Assert-Equal 'an empty folder has no groups' 0 $none.Count
Assert-Equal 'a folder that does not exist has no groups' 0 $missing.Count

# Arrange - loose files only, no subfolders
$looseOnly = Join-Path $root 'loose-only'
$null = Write-CoverageFile 'loose-only/one.cobertura.xml'
$null = Write-CoverageFile 'loose-only/two.cobertura.xml'
$null = Write-CoverageFile 'loose-only/ignored.txt'

# Act
$loose = Find-CoverageGroup -Path $looseOnly -Pattern '*.cobertura.xml'

# Assert
Assert-Equal 'one group, for the loose files' 1 $loose.Count
Assert-That 'it has no name' ($null -eq $loose[0].Name)
Assert-Equal 'both matching files, not the unmatched one' 2 $loose[0].Files.Count

# Arrange - subfolders only, one file nested two levels deep
$subOnly = Join-Path $root 'sub-only'
$null = Write-CoverageFile 'sub-only/net8.0/coverage.cobertura.xml'
$null = Write-CoverageFile 'sub-only/net48/nested/coverage.cobertura.xml'
$null = Write-CoverageFile 'sub-only/empty-sub/notes.txt'

# Act
$subs = Find-CoverageGroup -Path $subOnly -Pattern '*.cobertura.xml'

# Assert
Assert-Equal 'one group per subfolder that actually matches, sorted' 'net48,net8.0' `
    (($subs.Name | Sort-Object) -join ',')
Assert-Equal 'a nested file is still found' 1 (($subs | Where-Object Name -eq 'net48').Files.Count)
Assert-That 'a subfolder with no match gets no group' (-not ($subs.Name -contains 'empty-sub'))

# Arrange - both loose files and subfolders together
$mixed = Join-Path $root 'mixed'
$null = Write-CoverageFile 'mixed/root.cobertura.xml'
$null = Write-CoverageFile 'mixed/net9.0/coverage.cobertura.xml'

# Act
$both = Find-CoverageGroup -Path $mixed -Pattern '*.cobertura.xml'

# Assert
Assert-Equal 'the loose group and the subfolder group both appear' 2 $both.Count
Assert-Equal 'exactly one unnamed group' 1 (@($both | Where-Object { $null -eq $_.Name })).Count
Assert-Equal 'exactly one named group' 'net9.0' (($both | Where-Object Name).Name -join ',')

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '3. Get-UploadArgument'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$group = [pscustomobject]@{ Name = 'net8.0'; Files = @('a.xml', 'b.xml') }

# Act
$bare = Get-UploadArgument -Group $group
$flagged = Get-UploadArgument -Group $group -Flag 'net8.0'
$tokened = Get-UploadArgument -Group $group -Token 'abc123'
$strict = Get-UploadArgument -Group $group -FailOnError $true

# Assert
Assert-Equal 'always starts with upload-process and disables search' 'upload-process,--disable-search' `
    (($bare[0, 1]) -join ',')
Assert-That 'no flag means no -F at all' (-not ($bare -ccontains '-F'))
Assert-Equal 'every file becomes its own -f pair, in order' 'upload-process,--disable-search,-f,a.xml,-f,b.xml' `
    ($bare -join ',')
Assert-Equal 'a flag adds -F right after --disable-search' 'net8.0' $flagged[$flagged.IndexOf('-F') + 1]
Assert-Equal 'a token adds -t' 'abc123' $tokened[$tokened.IndexOf('-t') + 1]
Assert-That 'no token means no -t at all' (-not ($bare -contains '-t'))
Assert-That 'fail-on-error appends the bare flag' ($strict -contains '--fail-on-error')
Assert-That 'omitting it does not' (-not ($bare -contains '--fail-on-error'))

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '4. Get-UploadPlan'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$looseGroup = [pscustomobject]@{ Name = $null; Files = @('root.xml') }
$net8Group = [pscustomobject]@{ Name = 'net8.0'; Files = @('a.xml') }
$net9Group = [pscustomobject]@{ Name = 'net9.0'; Files = @('b.xml') }

# Act
$noGroups = Get-UploadPlan -Group @() -GroupBySubfolder $false -FailOnError $false

# Assert
Assert-Equal 'no groups at all means no plan' 0 $noGroups.Count

# Act - ungrouped, everything merges into one unflagged upload
$merged = Get-UploadPlan -Group @($looseGroup, $net8Group, $net9Group) -GroupBySubfolder $false -FailOnError $false

# Assert
Assert-Equal 'exactly one upload' 1 $merged.Count
Assert-That 'unflagged' ($null -eq $merged[0].Flag)
Assert-That 'no per-group flag, despite two of the groups having names' (-not ($merged[0].Arguments -ccontains '-F'))
Assert-Equal 'every file from every group is in it, in order' 'upload-process,--disable-search,-f,root.xml,-f,a.xml,-f,b.xml' `
    ($merged[0].Arguments -join ',')

# Act - grouped, one upload per named group, loose files stay unflagged
$split = Get-UploadPlan -Group @($looseGroup, $net8Group, $net9Group) -GroupBySubfolder $true -FailOnError $false

# Assert
Assert-Equal 'three uploads, one per group' 3 $split.Count
Assert-Equal 'flags are the group names, loose stays unflagged' ',net8.0,net9.0' `
    (($split | ForEach-Object { $_.Flag }) -join ',')

# Act - a token and fail-on-error both thread through to every upload in the plan
$withToken = Get-UploadPlan -Group @($net8Group, $net9Group) -GroupBySubfolder $true -Token 'tok' -FailOnError $true

# Assert
Assert-That 'every upload in the plan carries the token' `
    (@($withToken | Where-Object { $_.Arguments -contains '-t' }).Count -eq $withToken.Count)
Assert-That 'and fail-on-error' `
    (@($withToken | Where-Object { $_.Arguments -contains '--fail-on-error' }).Count -eq $withToken.Count)

exit (Complete-TestRun)
