#Requires -Version 7.0
<#
    The logic behind validating a Codecov configuration file:
    posting it to Codecov's own validator and interpreting the response.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-CodecovValidation {
    <#
    .SYNOPSIS
        Posts a Codecov configuration file to Codecov's own validator,
        returning whether it was accepted
        and the validator's own response text.
    .DESCRIPTION
        -SkipHttpErrorCheck reads a rejection's body
        the same way a success's is read, rather than throwing -
        the body is the only place the validator says what is wrong.
    #>
    param(
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$Endpoint
    )

    $response = Invoke-WebRequest -Uri $Endpoint -Method Post -InFile $ConfigPath -SkipHttpErrorCheck
    $valid = $response.StatusCode -ge 200 -and $response.StatusCode -lt 300
    return [pscustomobject]@{ Valid = $valid; Output = $response.Content }
}

Export-ModuleMember -Function @(
    'Invoke-CodecovValidation'
)
