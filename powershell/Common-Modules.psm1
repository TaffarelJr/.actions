#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ManifestPath = Join-Path $PSScriptRoot 'RequiredModules.psd1'
$script:Repository = 'PSGallery'

#───────────────────────────────────────────────────────────────────────────────
# The manifest
#───────────────────────────────────────────────────────────────────────────────

function Get-RequiredModule {
    <#
    .SYNOPSIS
        Returns the modules the manifest lists -
        Name, MinimumVersion, and the Uri of their install instructions -
        always as an array.
    .PARAMETER ManifestPath
        The manifest to read.
        Defaults to RequiredModules.psd1 beside this module.
    #>
    param([string]$ManifestPath)

    if (-not $ManifestPath) { $ManifestPath = $script:ManifestPath }
    $manifest = Import-PowerShellDataFile -LiteralPath $ManifestPath

    $modules = foreach ($entry in $manifest.Modules) {
        [pscustomobject]@{
            Name           = $entry.Name
            MinimumVersion = [version]$entry.MinimumVersion
            Uri            = $entry.Uri
        }
    }
    return , @($modules)
}

#───────────────────────────────────────────────────────────────────────────────
# Checking and installing
#───────────────────────────────────────────────────────────────────────────────

function Test-RequiredModule {
    <#
    .SYNOPSIS
        Reports whether a module of at least the given version is installed.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][version]$MinimumVersion
    )

    $installed = @(Get-Module -ListAvailable -Name $Name)
    return [bool]($installed | Where-Object { $_.Version -ge $MinimumVersion })
}

function Get-ModuleInstallParameter {
    <#
    .SYNOPSIS
        Returns the Install-Module parameters for a required module,
        so the command that runs and the command shown to a person
        are the same one.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][version]$MinimumVersion
    )

    return [ordered]@{
        Name               = $Name
        MinimumVersion     = "$MinimumVersion"
        Repository         = $script:Repository
        Scope              = 'CurrentUser'
        Force              = $true
        # Windows ships a signed Pester 3.4;
        # a newer build from the Gallery has a different publisher,
        # and Install-Module refuses it without this.
        SkipPublisherCheck = $true
    }
}

function Get-ModuleInstallCommand {
    <#
    .SYNOPSIS
        Returns the Install-Module line that installs a required module.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][version]$MinimumVersion
    )

    $parameters = Get-ModuleInstallParameter -Name $Name -MinimumVersion $MinimumVersion
    $parts = foreach ($key in $parameters.Keys) {
        $value = $parameters[$key]
        if ($value -is [bool]) {
            "-$key"
        }
        else {
            "-$key $value"
        }
    }

    return "Install-Module $($parts -join ' ')"
}

function Install-RequiredModule {
    <#
    .SYNOPSIS
        Installs a required module for the current user, from PSGallery only.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][version]$MinimumVersion
    )

    $parameters = Get-ModuleInstallParameter -Name $Name -MinimumVersion $MinimumVersion
    Install-Module @parameters
}

function Import-RequiredModule {
    <#
    .SYNOPSIS
        Imports a required module, at the manifest's minimum version or newer,
        into the global scope so the calling script can see it.
    #>
    param([Parameter(Mandatory)][string]$Name)

    $modules = Get-RequiredModule
    $module = $modules | Where-Object Name -eq $Name
    if (-not $module) {
        throw "'$Name' is not in $script:ManifestPath"
    }

    Import-Module -Name $Name -MinimumVersion $module.MinimumVersion -Global
}

#───────────────────────────────────────────────────────────────────────────────
# Interactive check
#───────────────────────────────────────────────────────────────────────────────

function Test-InteractiveHost {
    <#
    .SYNOPSIS
        Reports whether a person is at the console:
        not a CI run, and stdin not redirected.
    #>
    if ($env:CI -or $env:GITHUB_ACTIONS) { return $false }
    return -not [Console]::IsInputRedirected
}

function Get-MissingModuleMessage {
    <#
    .SYNOPSIS
        Returns the message for a missing module:
        what is missing, and the command and Uri to fix it.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][version]$MinimumVersion,
        [Parameter(Mandatory)][string]$Uri
    )

    $command = Get-ModuleInstallCommand -Name $Name -MinimumVersion $MinimumVersion
    $lines = @(
        "$Name $MinimumVersion or newer is required but not installed."
        'In a workflow, run powershell/restore first. Locally, run:'
        "  $command"
        "See $Uri"
    )
    return $lines -join "`n"
}

function Assert-RequiredModule {
    <#
    .SYNOPSIS
        Makes sure every module in the manifest is installed:
        offers to install a missing one when a person is present,
        and fails with the command to run when nobody is.
    .PARAMETER ManifestPath
        The manifest to check.
        Defaults to RequiredModules.psd1 beside this module.
    .PARAMETER Interactive
        Whether to offer to install. Defaults to Test-InteractiveHost.
    #>
    param(
        [string]$ManifestPath,
        [bool]$Interactive = (Test-InteractiveHost)
    )

    foreach ($module in (Get-RequiredModule -ManifestPath $ManifestPath)) {
        if (Test-RequiredModule -Name $module.Name -MinimumVersion $module.MinimumVersion) {
            continue
        }

        $message = Get-MissingModuleMessage -Name $module.Name -MinimumVersion $module.MinimumVersion -Uri $module.Uri
        if (-not $Interactive) { throw $message }

        Write-Warning ($message -split "`n")[0]
        $answer = Read-Host "Install $($module.Name) now? [Y/n]"
        if ($answer -and $answer -notmatch '^y') { throw $message }

        Write-Host "Installing $($module.Name) $($module.MinimumVersion)+ ..." -NoNewline
        Install-RequiredModule -Name $module.Name -MinimumVersion $module.MinimumVersion
        Write-Host ' done' -ForegroundColor Green
    }
}

Export-ModuleMember -Function @(
    'Get-RequiredModule'
    'Test-RequiredModule'
    'Get-ModuleInstallCommand'
    'Install-RequiredModule'
    'Import-RequiredModule'
    'Test-InteractiveHost'
    'Get-MissingModuleMessage'
    'Assert-RequiredModule'
)
