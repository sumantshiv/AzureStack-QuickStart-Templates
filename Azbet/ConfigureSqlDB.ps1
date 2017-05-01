<#
.SYNOPSIS
Configures AzBet SQL Database (First time).

.DESCRIPTION
This command creates the database and tables based on a schema required by AzBet application.
The function also populates the table with sample application data.

.PARAMETER AzureStoreKey
The shared access key from Azure private container where the database configure package.zip is located.

.PARAMETER SqlServerName
The Net Bios name of the Sql Server machine.

.PARAMETER DatabaseName
The Database name to be given to the AzBet application database.

.PARAMETER SqlAdminUserName
The Sql Admin username.

.PARAMETER SqlAdminPassword
The Sql Admin password.
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
    [string] $SqlServerName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $DatabaseName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $SqlAdminUserName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $SqlAdminPassword
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

.PARAMETER SqlServerName
The Net Bios name of the Sql Server machine.

.PARAMETER DatabaseName
The Database name to be given to the AzBet application database.

.PARAMETER SqlAdminUserName
The Sql Admin username.

.PARAMETER SqlAdminPassword
The Sql Admin password.
#>
function Set-AzBetDatabase
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
        [string] $SqlServerName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $DatabaseName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $SqlAdminUserName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $SqlAdminPassword
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

    $unzipPath = Get-UnzipFiles -zipFilePath $localPath -outPath "$env:temp"

    # Set the Sql connection string info.
    $connectionString = Get-SqlConnectionString -ServerName $SqlServerName -DatabaseName $DatabaseName -UserName $SqlAdminUserName -Password $SqlAdminPassword
    
    $connectionStringFilePath = Join-Path -Path $unzipPath -ChildPath "ServiceConfig\sqlinfo.txt"
    
    Set-Content -Path $connectionStringFilePath -Value $connectionString -Force

    # Run the Sql database setup scripts.

    pushd $unzipPath

    $loadDataFilePath = "$unzipPath\loadAllDatafromScratch.cmd"

    if(-not (Test-Path -Path $loadDataFilePath))
    {
        throw "Could not find path: '$loadDataFilePath'"
    }

   & $loadDataFilePath

   popd

   $aspregSqlExePath = Join-Path -Path $env:windir -ChildPath "Microsoft.NET\Framework64\v2.0.50727\aspnet_regsql.exe"

   $aspregSqlArgs = "-S $SqlServerName -U $SqlAdminUserName -P $SqlAdminPassword -ssadd -sstype p"

   $command = "$aspregSqlExePath $aspregSqlArgs"

   Invoke-Expression $command
}

###
## Calling Script
###

# Install ARM PS cmdlets.
Get-ARMPSModule

Set-AzBetDatabase -StorageAccessKey $StorageAccessKey `
                  -AzureEnvironmentName $AzureEnvironmentName `
                  -AzureContainerName $AzureContainerName `
                  -StorageAccountName $StorageAccountName `
                  -AzureBlobName $AzureBlobName `
                  -SqlServerName $SqlServerName `
                  -DatabaseName $DatabaseName `
                  -SqlAdminUserName $SqlAdminUserName `
                  -SqlAdminPassword $SqlAdminPassword



