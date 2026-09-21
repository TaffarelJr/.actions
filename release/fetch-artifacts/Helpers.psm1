#Requires -Version 7.0
<#
    The logic behind finding the CI run to release and reading what it
    built: locating a run by commit or by version, downloading its
    artifact, and reading the version file inside it.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#───────────────────────────────────────────────────────────────────────────────
# Locating the run
#───────────────────────────────────────────────────────────────────────────────

function Resolve-SearchBranch {
    <#
    .SYNOPSIS
        Returns the branch recent runs should be searched on: the ref
        itself when it names a real branch, otherwise the repo's default
        branch - a tag or a pull-request merge ref never had a run of
        its own.
    #>
    param(
        [Parameter(Mandatory)][string]$Ref,
        [Parameter(Mandatory)][string]$RefName,
        [Parameter(Mandatory)][string]$Repository
    )

    if ($Ref -like 'refs/heads/*') { return $RefName }
    return (gh api "repos/$Repository" --jq '.default_branch' | Select-Object -Last 1)
}

function Find-RunForCommit {
    <#
    .SYNOPSIS
        Returns the id and sha of the newest successful run of a workflow
        for an exact commit, or $null when there is none.
    .DESCRIPTION
        Anything older is a different tree; anything unsuccessful was
        never verified.
    #>
    param(
        [Parameter(Mandatory)][string]$Workflow,
        [Parameter(Mandatory)][string]$Sha
    )

    $runs = @(gh run list --workflow $Workflow --commit $Sha --status success --limit 1 `
            --json databaseId, headSha | ConvertFrom-Json)
    if (-not $runs) { return $null }
    return [pscustomobject]@{ RunId = "$($runs[0].databaseId)"; Sha = $runs[0].headSha }
}

function Find-RunForVersion {
    <#
    .SYNOPSIS
        Returns the id and sha of the newest successful run whose
        artifact recorded the given version, or $null when none of the
        recent runs did.
    .DESCRIPTION
        Walks recent successful runs on the branch, newest first,
        downloading each one's artifact to a scratch folder and reading
        its version file until one matches. A run whose artifact has
        expired could not be released anyway, so it is skipped rather
        than fatal.
    #>
    param(
        [Parameter(Mandatory)][string]$Workflow,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Artifact,
        [Parameter(Mandatory)][string]$VersionFile,
        [Parameter(Mandatory)][int]$SearchDepth
    )

    $runs = @(gh run list --workflow $Workflow --branch $Branch --status success --limit $SearchDepth `
            --json databaseId, headSha | ConvertFrom-Json)

    foreach ($run in $runs) {
        $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid())
        try {
            if (-not (Get-Artifact -RunId $run.databaseId -Artifact $Artifact -Path $scratch)) {
                Write-Host "::notice::Run $($run.databaseId) no longer has a '$Artifact' artifact; skipped."
                continue
            }

            $built = Get-VersionFileContent -Path (Join-Path $scratch $VersionFile)
            if ($built -eq $Version) {
                return [pscustomobject]@{ RunId = "$($run.databaseId)"; Sha = $run.headSha }
            }
        }
        finally {
            Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    return $null
}

#───────────────────────────────────────────────────────────────────────────────
# Reading what it built
#───────────────────────────────────────────────────────────────────────────────

function Get-Artifact {
    <#
    .SYNOPSIS
        Downloads a run's named artifact into a folder, returning whether
        it existed.
    #>
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$Artifact,
        [Parameter(Mandatory)][string]$Path
    )

    gh run download $RunId --name $Artifact --dir $Path 2>$null
    return $LASTEXITCODE -eq 0
}

function Get-VersionFileContent {
    <#
    .SYNOPSIS
        Returns a version file's content with all whitespace stripped,
        or '' when the file does not exist.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    return ((Get-Content -LiteralPath $Path -Raw) -replace '\s+', '')
}

Export-ModuleMember -Function @(
    'Resolve-SearchBranch'
    'Find-RunForCommit'
    'Find-RunForVersion'
    'Get-Artifact'
    'Get-VersionFileContent'
)
