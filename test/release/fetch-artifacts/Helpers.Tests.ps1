#Requires -Version 7.0
<#
    Tests for release/fetch-artifacts's Helpers.psm1: choosing which
    branch to search, finding a run by commit or by version, downloading
    an artifact, and reading its version file.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:TESTKIT_PATH) { throw 'Run this file through powershell/test/Invoke-Tests.ps1' }
Import-Module $env:TESTKIT_PATH -Force
Import-SourceModule 'Helpers'

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '1. Resolve-SearchBranch'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
Set-GhStub -Handler { param($ArgList) @{ Exit = 0; Out = @('main') } }

# Act
$onBranch = Resolve-SearchBranch -Ref 'refs/heads/feature-x' -RefName 'feature-x' -Repository 'owner/repo'

# Assert
Assert-Equal 'a real branch ref is used as-is' 'feature-x' $onBranch
Assert-That 'a real branch ref never asks gh for the default branch' (-not (Test-GhCall 'default_branch'))

# Arrange - reset so the next two cases' own calls are all that is recorded
Set-GhStub -Handler { param($ArgList) @{ Exit = 0; Out = @('main') } }

# Act
$onTag = Resolve-SearchBranch -Ref 'refs/tags/v1.0.0' -RefName 'v1.0.0' -Repository 'owner/repo'
$onPr = Resolve-SearchBranch -Ref 'refs/pull/9/merge' -RefName '9/merge' -Repository 'owner/repo'

# Assert
Assert-Equal 'a tag falls back to the default branch' 'main' $onTag
Assert-Equal 'a pull-request merge ref falls back too' 'main' $onPr
Assert-That 'the fallback asks for owner/repo specifically' (Test-GhCall 'repos/owner/repo')

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '2. Find-RunForCommit'
#───────────────────────────────────────────────────────────────────────────────

# Arrange - a run is found
Set-GhStub -Handler { param($ArgList) @{ Exit = 0; Out = @('[{"databaseId":111,"headSha":"abc123"}]') } }

# Act
$found = Find-RunForCommit -Workflow 'Continuous Integration' -Sha 'abc123'

# Assert
Assert-Equal 'returns the run id' '111' $found.RunId
Assert-Equal 'returns the sha' 'abc123' $found.Sha
Assert-That 'asked for exactly one successful run of the named workflow' `
    (Test-GhCall "run list --workflow Continuous Integration --commit abc123 --status success --limit 1")

# Arrange - no run at all
Set-GhStub -Handler { param($ArgList) @{ Exit = 0; Out = @('[]') } }

# Act
$missing = Find-RunForCommit -Workflow 'Continuous Integration' -Sha 'deadbeef'

# Assert
Assert-That 'no matching run means nothing found' ($null -eq $missing)

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '3. Get-VersionFileContent'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
$root = New-TestRoot -Name 'fetch-artifacts'
$versionFile = Join-Path $root 'version.txt'
Set-Content -LiteralPath $versionFile -Value "  1.4.0`n"

# Act
$content = Get-VersionFileContent -Path $versionFile
$missingFile = Get-VersionFileContent -Path (Join-Path $root 'nope.txt')

# Assert
Assert-Equal 'strips surrounding and internal whitespace' '1.4.0' $content
Assert-Equal 'a missing file reads as empty' '' $missingFile

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '4. Get-Artifact'
#───────────────────────────────────────────────────────────────────────────────

# Arrange - the artifact exists
$downloadRoot = Join-Path $root 'downloaded'
Set-GhStub -Handler {
    param($ArgList)
    $dirIndex = $ArgList.IndexOf('--dir')
    $dir = $ArgList[$dirIndex + 1]
    $null = New-Item -ItemType Directory -Force -Path $dir
    Set-Content -LiteralPath (Join-Path $dir 'version.txt') -Value '2.0.0'
    @{ Exit = 0 }
}

# Act
$downloaded = Get-Artifact -RunId '222' -Artifact 'packages' -Path $downloadRoot

# Assert
Assert-That 'reports success' $downloaded
Assert-Equal 'the file the stub wrote is really there' '2.0.0' `
    (Get-VersionFileContent -Path (Join-Path $downloadRoot 'version.txt'))
Assert-That 'downloaded the named run and artifact' (Test-GhCall 'run download 222 --name packages')

# Arrange - the artifact does not exist
Set-GhStub -Handler { param($ArgList) @{ Exit = 1 } }

# Act
$notDownloaded = Get-Artifact -RunId '222' -Artifact 'packages' -Path (Join-Path $root 'nothing')

# Assert
Assert-That 'reports failure without throwing' (-not $notDownloaded)

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '5. Find-RunForVersion'
#───────────────────────────────────────────────────────────────────────────────

# Arrange - the newest run's artifact matches
Set-GhStub -Handler {
    param($ArgList)
    if ($ArgList -contains 'download') {
        $dirIndex = $ArgList.IndexOf('--dir')
        $dir = $ArgList[$dirIndex + 1]
        $runId = $ArgList[2]
        $null = New-Item -ItemType Directory -Force -Path $dir
        $version = if ($runId -eq '301') { '1.5.0' } else { '1.4.0' }
        Set-Content -LiteralPath (Join-Path $dir 'version.txt') -Value $version
        return @{ Exit = 0 }
    }
    @{ Exit = 0; Out = @('[{"databaseId":301,"headSha":"newest"},{"databaseId":300,"headSha":"older"}]') }
}

# Act
$matched = Find-RunForVersion -Workflow 'Continuous Integration' -Branch 'main' -Version '1.5.0' `
    -Artifact 'packages' -VersionFile 'version.txt' -SearchDepth 50

# Assert
Assert-Equal 'matches the newest run without checking further' '301' $matched.RunId
Assert-Equal 'returns that run''s sha' 'newest' $matched.Sha

# Arrange - only the older run matches, so the newer one must be skipped past
Set-GhStub -Handler {
    param($ArgList)
    if ($ArgList -contains 'download') {
        $dirIndex = $ArgList.IndexOf('--dir')
        $dir = $ArgList[$dirIndex + 1]
        $runId = $ArgList[2]
        $null = New-Item -ItemType Directory -Force -Path $dir
        $version = if ($runId -eq '300') { '1.4.0' } else { '1.5.0' }
        Set-Content -LiteralPath (Join-Path $dir 'version.txt') -Value $version
        return @{ Exit = 0 }
    }
    @{ Exit = 0; Out = @('[{"databaseId":301,"headSha":"newest"},{"databaseId":300,"headSha":"older"}]') }
}

# Act
$olderMatch = Find-RunForVersion -Workflow 'Continuous Integration' -Branch 'main' -Version '1.4.0' `
    -Artifact 'packages' -VersionFile 'version.txt' -SearchDepth 50

# Assert
Assert-Equal 'keeps looking until it finds the match' '300' $olderMatch.RunId

# Arrange - the newest run's artifact has expired; the older one matches
Set-GhStub -Handler {
    param($ArgList)
    if ($ArgList -contains 'download') {
        $dirIndex = $ArgList.IndexOf('--dir')
        $dir = $ArgList[$dirIndex + 1]
        $runId = $ArgList[2]
        if ($runId -eq '301') { return @{ Exit = 1 } }
        $null = New-Item -ItemType Directory -Force -Path $dir
        Set-Content -LiteralPath (Join-Path $dir 'version.txt') -Value '1.4.0'
        return @{ Exit = 0 }
    }
    @{ Exit = 0; Out = @('[{"databaseId":301,"headSha":"newest"},{"databaseId":300,"headSha":"older"}]') }
}

# Act
$skippedExpired = Find-RunForVersion -Workflow 'Continuous Integration' -Branch 'main' -Version '1.4.0' `
    -Artifact 'packages' -VersionFile 'version.txt' -SearchDepth 50

# Assert
Assert-Equal 'an expired artifact is skipped, not fatal' '300' $skippedExpired.RunId

# Arrange - nothing matches at all
Set-GhStub -Handler {
    param($ArgList)
    if ($ArgList -contains 'download') {
        $dirIndex = $ArgList.IndexOf('--dir')
        $dir = $ArgList[$dirIndex + 1]
        $null = New-Item -ItemType Directory -Force -Path $dir
        Set-Content -LiteralPath (Join-Path $dir 'version.txt') -Value '9.9.9'
        return @{ Exit = 0 }
    }
    @{ Exit = 0; Out = @('[{"databaseId":301,"headSha":"newest"}]') }
}

# Act
$noMatch = Find-RunForVersion -Workflow 'Continuous Integration' -Branch 'main' -Version '1.4.0' `
    -Artifact 'packages' -VersionFile 'version.txt' -SearchDepth 50

# Assert
Assert-That 'no run matching the version means nothing found' ($null -eq $noMatch)

exit (Complete-TestRun)
