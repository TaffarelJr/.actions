#Requires -Version 7.0
<#
    Tests for version/move-alias's Helpers.psm1: which tags an alias can
    move to, picking the newest one, deciding create/update/none, the gh
    calls that read and write the tag, and the retrying orchestrator.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $env:TESTKIT_PATH) { throw 'Run this file through powershell/test/Invoke-Tests.ps1' }
Import-Module $env:TESTKIT_PATH -Force
Import-SourceModule 'Helpers'

$repo = 'TaffarelJr/.actions'

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '1. Get-AliasFilterPattern'
#───────────────────────────────────────────────────────────────────────────────

# Act
$major = Get-AliasFilterPattern -Alias 'v1'
$minor = Get-AliasFilterPattern -Alias 'v1.4'

# Assert
Assert-Equal 'a major alias matches any patch under it' '^v1\.[0-9]+\.[0-9]+$' $major
Assert-Equal 'a major.minor alias matches any patch under it' '^v1\.4\.[0-9]+$' $minor
Assert-Throws 'anything else is rejected' { Get-AliasFilterPattern -Alias 'v1.4.2' } 'not a major or major\.minor alias'
Assert-Throws 'so is nonsense' { Get-AliasFilterPattern -Alias 'latest' } 'not a major or major\.minor alias'

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '2. Get-NewestMatchingTag'
#───────────────────────────────────────────────────────────────────────────────

# Act
$none = Get-NewestMatchingTag -Tag @() -Pattern '^v1\.[0-9]+\.[0-9]+$'
$noMatch = Get-NewestMatchingTag -Tag @('v2.0.0', 'v2.1.0') -Pattern '^v1\.[0-9]+\.[0-9]+$'
$single = Get-NewestMatchingTag -Tag @('v1.0.0') -Pattern '^v1\.[0-9]+\.[0-9]+$'
$highest = Get-NewestMatchingTag -Tag @('v1.0.0', 'v1.10.0', 'v1.2.0') -Pattern '^v1\.[0-9]+\.[0-9]+$'
$filtered = Get-NewestMatchingTag -Tag @('v1.5.0', 'v2.0.0', 'v1.9.0') -Pattern '^v1\.[0-9]+\.[0-9]+$'

# Assert
Assert-That 'no tags at all means no match' ($null -eq $none)
Assert-That 'no matching tags means no match' ($null -eq $noMatch)
Assert-Equal 'a single match wins by default' 'v1.0.0' $single
Assert-Equal 'the highest version wins, not the last one listed' 'v1.10.0' $highest
Assert-Equal 'a higher major is not a candidate' 'v1.9.0' $filtered

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '3. Get-AliasMoveAction'
#───────────────────────────────────────────────────────────────────────────────

# Act
$none2 = Get-AliasMoveAction -CurrentCommit 'abc' -TargetCommit 'abc'
$update = Get-AliasMoveAction -CurrentCommit 'abc' -TargetCommit 'def'
$create = Get-AliasMoveAction -CurrentCommit $null -TargetCommit 'def'

# Assert
Assert-Equal 'already at the target commit needs nothing' 'None' $none2
Assert-Equal 'a different current commit needs an update' 'Update' $update
Assert-Equal 'no current commit needs a create' 'Create' $create

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '4. Get-TagCommit'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
Set-GhStub -Handler { param($ArgList) @{ Exit = 0; Out = @('deadbeef') } }

# Act
$sha = Get-TagCommit -Repository $repo -Tag 'v1.4.2'

# Assert
Assert-Equal 'returns the sha gh reports' 'deadbeef' $sha
Assert-That 'asked gh for that exact tag''s commit' (Test-GhCall 'commits/v1\.4\.2')

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '5. Get-AliasCommit'
#───────────────────────────────────────────────────────────────────────────────

# Arrange - the alias already exists
Set-GhStub -Handler { param($ArgList) @{ Exit = 0; Out = @('cafef00d') } }

# Act
$existing = Get-AliasCommit -Repository $repo -Alias 'v1'

# Assert
Assert-Equal 'returns the sha the alias points to' 'cafef00d' $existing
Assert-That 'asked gh for that alias ref' (Test-GhCall 'git/ref/tags/v1(\s|$)')

# Arrange - the alias does not exist yet (gh exits non-zero)
Set-GhStub -Handler { param($ArgList) @{ Exit = 1 } }

# Act
$missing = Get-AliasCommit -Repository $repo -Alias 'v1'

# Assert
Assert-That 'a failed lookup means the alias does not exist' ($null -eq $missing)

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '6. Set-AliasCommit'
#───────────────────────────────────────────────────────────────────────────────

# Arrange
Set-GhStub -Handler { param($ArgList) @{ Exit = 0 } }

# Act
$updated = Set-AliasCommit -Repository $repo -Alias 'v1' -Commit 'deadbeef' -Exists $true
$created = Set-AliasCommit -Repository $repo -Alias 'v1' -Commit 'deadbeef' -Exists $false

# Assert
Assert-That 'an existing alias is updated' $updated
Assert-That 'update goes through PATCH, forced' (Test-GhCall 'PATCH.*git/refs/tags/v1.*force=true')
Assert-That 'a missing alias is created' $created
Assert-That 'create goes through POST with the ref spelled out' (Test-GhCall 'POST.*git/refs.*ref=refs/tags/v1')

# Arrange - the API call itself fails
Set-GhStub -Handler { param($ArgList) @{ Exit = 1 } }

# Act
$failed = Set-AliasCommit -Repository $repo -Alias 'v1' -Commit 'deadbeef' -Exists $true

# Assert
Assert-That 'a failed call is reported, not swallowed' (-not $failed)

#───────────────────────────────────────────────────────────────────────────────
Write-TestSection '7. Move-Alias'
#───────────────────────────────────────────────────────────────────────────────

# Arrange - nothing matches the alias at all
Set-GhStub -Handler { param($ArgList) @{ Exit = 0 } }

# Act
$noTag = Move-Alias -Repository $repo -Alias 'v1' -Tag @('v2.0.0') -RetryDelaySeconds 0

# Assert
Assert-That 'fails cleanly when no tag matches the alias' (-not $noTag.Success)
Assert-That 'says why' ($noTag.Message -match 'No tag matches v1')

# Arrange - the alias is already at the newest matching tag
Set-GhStub -Handler {
    param($ArgList)
    $joined = $ArgList -join ' '
    if ($joined -match 'commits/') { return @{ Exit = 0; Out = @('deadbeef') } }
    if ($joined -match 'git/ref/tags/') { return @{ Exit = 0; Out = @('deadbeef') } }
    return @{ Exit = 0 }
}

# Act
$already = Move-Alias -Repository $repo -Alias 'v1' -Tag @('v1.0.0', 'v1.1.0') -RetryDelaySeconds 0

# Assert
Assert-That 'reports success without moving anything' $already.Success
Assert-That 'names the tag it is already at' ($already.Message -match 'already at v1\.1\.0')
Assert-That 'never calls PATCH or POST' (-not (Test-GhCall '--method'))

# Arrange - the alias needs to move (exists, different commit)
Set-GhStub -Handler {
    param($ArgList)
    $joined = $ArgList -join ' '
    if ($joined -match 'commits/') { return @{ Exit = 0; Out = @('newsha') } }
    if ($joined -match 'git/ref/tags/') { return @{ Exit = 0; Out = @('oldsha') } }
    return @{ Exit = 0 }
}

# Act
$moved = Move-Alias -Repository $repo -Alias 'v1' -Tag @('v1.0.0', 'v1.1.0') -RetryDelaySeconds 0

# Assert
Assert-That 'reports success' $moved.Success
Assert-That 'names the tag it moved to' ($moved.Message -match 'v1\.1\.0')
Assert-That 'updates rather than creates' (Test-GhCall '--method PATCH')

# Arrange - the alias does not exist yet, and the first create attempt fails transiently
Set-GhStub -Handler {
    param($ArgList)
    $joined = $ArgList -join ' '
    if ($joined -match 'commits/') { return @{ Exit = 0; Out = @('newsha') } }
    if ($joined -match 'git/ref/tags/') { return @{ Exit = 1 } }
    if ($joined -match '--method POST') {
        $attempts = @($global:GhStub.Calls | Where-Object { $_ -match '--method POST' }).Count
        if ($attempts -le 1) { return @{ Exit = 1 } }
        return @{ Exit = 0 }
    }
    return @{ Exit = 0 }
}

# Act
$retried = Move-Alias -Repository $repo -Alias 'v1' -Tag @('v1.0.0') -RetryDelaySeconds 0

# Assert
Assert-That 'succeeds after retrying' $retried.Success
$calls = Get-GhCall
$postCalls = @($calls | Where-Object { $_ -match '--method POST' })
Assert-Equal 'retried exactly once before succeeding' 2 $postCalls.Count

# Arrange - every attempt fails
Set-GhStub -Handler {
    param($ArgList)
    $joined = $ArgList -join ' '
    if ($joined -match 'commits/') { return @{ Exit = 0; Out = @('newsha') } }
    if ($joined -match 'git/ref/tags/') { return @{ Exit = 1 } }
    return @{ Exit = 1 }
}

# Act
$exhausted = Move-Alias -Repository $repo -Alias 'v1' -Tag @('v1.0.0') -MaxAttempts 3 -RetryDelaySeconds 0

# Assert
Assert-That 'reports failure once every attempt is spent' (-not $exhausted.Success)
Assert-That 'says how many attempts it made' ($exhausted.Message -match 'after 3 attempts')

exit (Complete-TestRun)
