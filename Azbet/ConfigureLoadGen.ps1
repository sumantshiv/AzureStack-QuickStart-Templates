<#
.SYNOPSIS
Configures AzBet LoadGen (First time).

.DESCRIPTION
This command creates the database and tables based on a schema required by AzBet application.
The function also populates the table with sample application data.

.PARAMETER AzureStoreKey
The shared access key from Azure private container where the database configure package.zip is located.
#>
param
(   
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $StorageAccessKey,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $AzureEnvironmentName,
    
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $AzureContainerName,
    
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $AzureBlobName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $AzBetTargetUrl,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $DeploymentEnvironmentName
)
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

Import-Module $PSScriptRoot\SetupAzBet.psm1 -Force

<#
.SYNOPSIS
The main top level function to configure AzBet SQL Database (First time).

.DESCRIPTION
This command creates the database and tables based on a schema required by AzBet application.
The function also populates the table with sample application data.

.PARAMETER StorageAccessKey
The shared access key from Azure private container where the database configure package.zip is located.
#>
function Set-LoadGenForAzbet
{
     param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $StorageAccessKey,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $AzureEnvironmentName,
    
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $StorageAccountName,
    
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $AzureContainerName,
    
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $AzureBlobName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $AzBetTargetUrl,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $DeploymentEnvironmentName
    )

    # Get the setup files and scripts from Azure blob storage.
    $localPath = Get-InfraFileFromAzure -StorageAccessKey $StorageAccessKey `
                                    -BlobName $AzureBlobName `
                                    -StorageAccountName $StorageAccountName `
                                    -AzureContainerName $AzureContainerName `
                                    -AzureEnvironmentName $AzureEnvironmentName
    
    if(-not (Test-Path -Path $localPath))
    {
        throw "Path does not exist: $localPath"
    }

    # Run the deploy load-gen scrit.

    $deployScriptPath = "$PSScriptRoot\Deploy-RoboCustos-WindowsService-Remote.ps1"    

    if(-not (Test-Path -Path $deployScriptPath))
    {
        throw "Could not find path: '$deployScriptPath'"
    }

    $deployParams = "-PackageUrl $localPath -AzBetTargetUrl $AzBetTargetUrl -DeploymentEnvironmentName $DeploymentEnvironmentName"

    $deployCommand = "$deployScriptPath $deployParams"

    Invoke-Expression $deployCommand


}

###
## Calling Script
###

# Install ARM PS cmdlets.
Get-ARMPSModule

Set-LoadGenForAzbet -StorageAccessKey $StorageAccessKey `
                  -AzureEnvironmentName $AzureEnvironmentName `
                  -AzureContainerName $AzureContainerName `
                  -StorageAccountName $StorageAccountName `
                  -AzureBlobName $AzureBlobName `
                  -AzBetTargetUrl $AzBetTargetUrl `
                  -DeploymentEnvironmentName $DeploymentEnvironmentName



