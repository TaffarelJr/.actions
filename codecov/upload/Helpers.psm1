#Requires -Version 7.0
<#
    The logic behind installing codecovcli and uploading coverage with it:
    picking the right binary, finding what to upload, and building the exact
    arguments codecovcli gets called with.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#───────────────────────────────────────────────────────────────────────────────
# Installing
#───────────────────────────────────────────────────────────────────────────────

function Get-CodecovCliUrl {
    <#
    .SYNOPSIS
        Returns the download URL for the codecovcli binary matching the OS.
    #>
    param([Parameter(Mandatory)][bool]$IsWindows)

    if ($IsWindows) { return 'https://cli.codecov.io/latest/windows/codecov.exe' }
    return 'https://cli.codecov.io/latest/linux/codecov'
}

function Get-CodecovCliFileName {
    <#
    .SYNOPSIS
        Returns the file name codecovcli should be saved as, matching the OS.
    #>
    param([Parameter(Mandatory)][bool]$IsWindows)

    if ($IsWindows) { return 'codecov.exe' }
    return 'codecov'
}

#───────────────────────────────────────────────────────────────────────────────
# Finding what to upload
#───────────────────────────────────────────────────────────────────────────────

function Find-CoverageGroup {
    <#
    .SYNOPSIS
        Returns the coverage files under a folder as upload groups, always as
        an array.
    .DESCRIPTION
        Files directly under the folder become one group with no Name. Each
        immediate subfolder that contains a match becomes its own group,
        named after that subfolder - a caller decides whether that name
        becomes a flag.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Pattern
    )

    if (-not (Test-Path -LiteralPath $Path)) { return , @() }
    $root = (Resolve-Path -LiteralPath $Path).Path

    $groups = [System.Collections.Generic.List[pscustomobject]]::new()

    $loose = @(Get-ChildItem -LiteralPath $root -File -Filter $Pattern)
    if ($loose) {
        $groups.Add([pscustomobject]@{ Name = $null; Files = @($loose.FullName) })
    }

    $subfolders = @(Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name)
    foreach ($subfolder in $subfolders) {
        $files = @(Get-ChildItem -LiteralPath $subfolder.FullName -Recurse -File -Filter $Pattern)
        if ($files) {
            $groups.Add([pscustomobject]@{ Name = $subfolder.Name; Files = @($files.FullName) })
        }
    }

    return , @($groups)
}

#───────────────────────────────────────────────────────────────────────────────
# Uploading
#───────────────────────────────────────────────────────────────────────────────

function Get-UploadArgument {
    <#
    .SYNOPSIS
        Returns the codecovcli arguments for uploading one group, always as
        an array.
    .PARAMETER Group
        One result from Find-CoverageGroup.
    .PARAMETER Flag
        The flag to upload the group under. Omit for an unflagged upload.
    .PARAMETER Token
        The Codecov upload token. Omit to rely on codecovcli's own detection.
    .PARAMETER FailOnError
        Whether codecovcli should exit non-zero when the upload itself fails.
    #>
    param(
        [Parameter(Mandatory)][pscustomobject]$Group,
        [string]$Flag,
        [string]$Token,
        [bool]$FailOnError
    )

    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add('upload-process')
    $arguments.Add('--disable-search')
    if ($Token) { $arguments.AddRange([string[]]@('-t', $Token)) }
    if ($Flag) { $arguments.AddRange([string[]]@('-F', $Flag)) }
    foreach ($file in $Group.Files) { $arguments.AddRange([string[]]@('-f', $file)) }
    if ($FailOnError) { $arguments.Add('--fail-on-error') }

    return , [string[]]$arguments
}

function Get-UploadPlan {
    <#
    .SYNOPSIS
        Returns the codecovcli invocations to make for a set of groups,
        always as an array, applying the group-by-subfolder policy.
    .DESCRIPTION
        Without grouping, every file across every group uploads once,
        unflagged - a subfolder found by Find-CoverageGroup is just how
        the files happened to be organized, not a signal to split by. With
        grouping, each named group becomes its own flagged upload, and any
        unnamed (loose-file) group stays unflagged.
    #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Group,
        [Parameter(Mandatory)][bool]$GroupBySubfolder,
        [string]$Token,
        [bool]$FailOnError
    )

    if (-not $GroupBySubfolder) {
        $files = @($Group | ForEach-Object { $_.Files })
        if (-not $files) { return , @() }
        $merged = [pscustomobject]@{ Name = $null; Files = $files }
        $arguments = Get-UploadArgument -Group $merged -Token $Token -FailOnError $FailOnError
        return , @([pscustomobject]@{ Flag = $null; Arguments = $arguments })
    }

    $plan = foreach ($entry in $Group) {
        $arguments = Get-UploadArgument -Group $entry -Flag $entry.Name -Token $Token -FailOnError $FailOnError
        [pscustomobject]@{ Flag = $entry.Name; Arguments = $arguments }
    }
    return , @($plan)
}

Export-ModuleMember -Function @(
    'Get-CodecovCliUrl'
    'Get-CodecovCliFileName'
    'Find-CoverageGroup'
    'Get-UploadArgument'
    'Get-UploadPlan'
)
