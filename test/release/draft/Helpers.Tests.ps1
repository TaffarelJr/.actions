#Requires -Version 7.0
<#
    Tests for release/draft's Helpers.psm1: deciding the version to
    draft, building the AI-summary prompt, and creating/updating the
    draft itself.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:TESTKIT_PATH) { throw 'Run this file through powershell/test/Invoke-Tests.ps1' }
Import-Module $env:TESTKIT_PATH -Force
Import-SourceModule 'Helpers'

$repo = New-TestRoot -Name 'release-draft'
Push-Location $repo
try {
    git init -q -b main
    git config user.email 'test@example.test'
    git config user.name 'Test'
    git commit --allow-empty -q -m 'chore: root'
    $rootSha = (git rev-parse HEAD).Trim()

    #───────────────────────────────────────────────────────────────────────────────
    Write-TestSection '1. Test-TagExists'
    #───────────────────────────────────────────────────────────────────────────────

    # Arrange
    git tag v1.0.0

    # Act / Assert
    Assert-That 'an existing tag is found' (Test-TagExists -Tag 'v1.0.0')
    Assert-That 'a tag that was never created is not' (-not (Test-TagExists -Tag 'v9.9.9'))

    #───────────────────────────────────────────────────────────────────────────────
    Write-TestSection '2. Resolve-DraftVersion'
    #───────────────────────────────────────────────────────────────────────────────

    # Act - the build recorded a version, and there is no request
    $fromBuild = Resolve-DraftVersion -Requested '' -Found $true -FromBuild '1.4.0' `
        -BuiltSha 'builtsha' -Fallback '' -CurrentSha $rootSha

    # Assert
    Assert-Equal 'uses the build''s own version' '1.4.0' $fromBuild.Version
    Assert-Equal 'uses the build''s own sha' 'builtsha' $fromBuild.Sha
    Assert-Equal 'reports the source as the build' 'Build' $fromBuild.Source

    # Act - nothing was built for this commit; falls back to GitVersion
    $fallback = Resolve-DraftVersion -Requested '' -Found $false -FromBuild '' `
        -BuiltSha '' -Fallback '1.5.0' -CurrentSha $rootSha

    # Assert
    Assert-Equal 'uses the fallback version' '1.5.0' $fallback.Version
    Assert-Equal 'uses the current commit, since the build has none' $rootSha $fallback.Sha
    Assert-Equal 'reports the source as the fallback' 'Fallback' $fallback.Source

    # Act / Assert - a named version can only come from the build that produced it
    Assert-Throws 'a requested version with no matching build is refused' {
        Resolve-DraftVersion -Requested '1.4.0' -Found $false -FromBuild '' `
            -BuiltSha '' -Fallback '' -CurrentSha $rootSha
    } 'No CI build of 1\.4\.0 is available'
    Assert-Throws 'a requested version differing from the build found is refused' {
        Resolve-DraftVersion -Requested 'v1.4.0' -Found $true -FromBuild '1.3.9' `
            -BuiltSha 'sha' -Fallback '' -CurrentSha $rootSha
    } 'No CI build of 1\.4\.0 is available'

    # Act - a requested version matching the build found is accepted (the v is stripped)
    $requested = Resolve-DraftVersion -Requested 'v1.4.0' -Found $true -FromBuild '1.4.0' `
        -BuiltSha 'sha' -Fallback '' -CurrentSha $rootSha

    # Assert
    Assert-Equal 'the matching build''s version is used' '1.4.0' $requested.Version

    # Act / Assert - nothing to release at all
    Assert-Throws 'no build and no fallback means nothing to release' {
        Resolve-DraftVersion -Requested '' -Found $false -FromBuild '' `
            -BuiltSha '' -Fallback '' -CurrentSha $rootSha
    } 'Could not determine a version'

    # Act / Assert - a pre-release shape is refused
    Assert-Throws 'a pre-release version is refused' {
        Resolve-DraftVersion -Requested '' -Found $true -FromBuild '1.4.0-PullRequest9.1' `
            -BuiltSha 'sha' -Fallback '' -CurrentSha $rootSha
    } 'is not a release version'

    # Act / Assert - an already-tagged version is refused
    Assert-Throws 'a version already tagged is refused' {
        Resolve-DraftVersion -Requested '' -Found $true -FromBuild '1.0.0' `
            -BuiltSha 'sha' -Fallback '' -CurrentSha $rootSha
    } 'is already tagged'

    #───────────────────────────────────────────────────────────────────────────────
    Write-TestSection '3. Get-SummaryPrompt'
    #───────────────────────────────────────────────────────────────────────────────

    # Act
    $prompt = Get-SummaryPrompt -Version '1.4.0' -Changelog '- fix: a thing'

    # Assert
    Assert-That 'names the version' ($prompt -match 'version 1\.4\.0')
    Assert-That 'asks for prose, not headings' ($prompt -match 'Plain prose, no preamble')
    Assert-That 'includes the changelog itself' ($prompt -match '- fix: a thing')

    #───────────────────────────────────────────────────────────────────────────────
    Write-TestSection '4. Get-ReleaseList and Test-DraftExists'
    #───────────────────────────────────────────────────────────────────────────────

    # Arrange
    Set-GhStub -Handler {
        param($ArgList)
        @{ Exit = 0; Out = @('[{"tagName":"v1.0.0","isDraft":false},{"tagName":"v1.4.0","isDraft":true}]') }
    }

    # Act
    $releases = Get-ReleaseList -Limit 100

    # Assert
    Assert-Equal 'reads every release gh reports' 2 $releases.Count
    Assert-That 'asked for the given limit' (Test-GhCall 'release list --limit 100')

    # Act / Assert
    Assert-That 'a draft for this tag is found' (Test-DraftExists -Release $releases -Tag 'v1.4.0')
    Assert-That 'a published release is not a draft' (-not (Test-DraftExists -Release $releases -Tag 'v1.0.0'))
    Assert-That 'a tag with no release at all is not a draft' (-not (Test-DraftExists -Release $releases -Tag 'v2.0.0'))
    Assert-That 'no releases at all means no draft' (-not (Test-DraftExists -Release @() -Tag 'v1.4.0'))

    #───────────────────────────────────────────────────────────────────────────────
    Write-TestSection '5. Remove-Draft'
    #───────────────────────────────────────────────────────────────────────────────

    # Arrange
    Set-GhStub -Handler { param($ArgList) @{ Exit = 0 } }

    # Act
    Remove-Draft -Tag 'v1.4.0'

    # Assert
    Assert-That 'deletes the named tag''s release, without confirming' (Test-GhCall 'release delete v1\.4\.0 --yes')

    #───────────────────────────────────────────────────────────────────────────────
    Write-TestSection '6. New-DraftRelease'
    #───────────────────────────────────────────────────────────────────────────────

    # Arrange
    Set-GhStub -Handler { param($ArgList) @{ Exit = 0; Out = @('https://github.test/owner/repo/releases/tag/v1.4.0') } }

    # Act
    $url = New-DraftRelease -Tag 'v1.4.0' -NotesPath 'Changelog.md' -TargetSha 'sha123'

    # Assert
    Assert-Equal 'returns the url gh reports' 'https://github.test/owner/repo/releases/tag/v1.4.0' $url
    Assert-That 'creates a draft with the tag as its title' (Test-GhCall 'release create v1\.4\.0 --draft --title v1\.4\.0')
    Assert-That 'targets the given commit' (Test-GhCall '--target sha123')
    Assert-That 'uses the given notes file' (Test-GhCall '--notes-file Changelog\.md')

    #───────────────────────────────────────────────────────────────────────────────
    Write-TestSection '7. Test-HasArtifact'
    #───────────────────────────────────────────────────────────────────────────────

    # Arrange
    $empty = Join-Path $repo 'empty-artifacts'
    $null = New-Item -ItemType Directory -Force -Path $empty
    $withFile = Join-Path $repo 'real-artifacts'
    $null = New-Item -ItemType Directory -Force -Path $withFile
    Set-Content -LiteralPath (Join-Path $withFile 'thing.txt') -Value 'contents'

    # Act / Assert
    Assert-That 'a folder that does not exist has no artifact' (-not (Test-HasArtifact -Path (Join-Path $repo 'nope')))
    Assert-That 'an empty folder has no artifact' (-not (Test-HasArtifact -Path $empty))
    Assert-That 'a folder with a file has an artifact' (Test-HasArtifact -Path $withFile)

    #───────────────────────────────────────────────────────────────────────────────
    Write-TestSection '8. Publish-ReleaseAsset'
    #───────────────────────────────────────────────────────────────────────────────

    # Arrange
    Set-Content -LiteralPath (Join-Path $withFile 'other.txt') -Value 'more'
    Set-GhStub -Handler { param($ArgList) @{ Exit = 0 } }

    # Act
    $count = Publish-ReleaseAsset -Tag 'v1.4.0' -Path $withFile

    # Assert
    Assert-Equal 'reports how many files it uploaded' 2 $count
    Assert-That 'uploads to the named tag, replacing any existing asset' `
        (Test-GhCall 'release upload v1\.4\.0.*--clobber')
    Assert-That 'each file under the folder is its own argument' (Test-GhCall 'thing\.txt.*other\.txt|other\.txt.*thing\.txt')

    #───────────────────────────────────────────────────────────────────────────────
    Write-TestSection '9. Get-DraftSummary'
    #───────────────────────────────────────────────────────────────────────────────

    # Act
    $summary = Get-DraftSummary -Tag 'v1.4.0' -Url 'https://github.test/owner/repo/releases/tag/v1.4.0'

    # Assert
    Assert-That 'links the tag to its url' ($summary -match '\[v1\.4\.0\]\(https://github\.test/owner/repo/releases/tag/v1\.4\.0\)')
    Assert-That 'tells the reader to press Publish' ($summary -match '\*\*Publish\*\*')
}
finally {
    Pop-Location
}

exit (Complete-TestRun)
