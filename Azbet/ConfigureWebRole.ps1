<#
.SYNOPSIS
Configures the web role in IIS for the application.
Also, Configures IIS settings required to run the website with SSL.

.DESCRIPTION
This command creates the database and tables based on a schema required by AzBet application.
The function also populates the table with sample application data.

.PARAMETER AzureStoreKey
The shared access key from Azure private container where the website contents are located (Example - AzBet_Website.zip).

.PARAMETER SqlServerName
The Net Bios name of the Sql Server machine.

.PARAMETER DatabaseName
The Database name to be given to the AzBet application database.

.PARAMETER SqlAdminUserName
The Sql Admin username.

.PARAMETER SqlAdminPassword
The Sql Admin password.

.PARAMETER CertificateToImport
Path of the SSL certificate to import.

.PARAMETER ListeningPort
Website Listening port. Default is 443.

.PARAMETER WebSiteName
Name of the Website. Default is: "Default Web Site".
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
    [string] $SqlAdminPassword,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [String] $CertificateToImport,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $CertificatePassword,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $DeploymentEnvironmentName,
    
    [int] $ListeningPort = 443,
    
    [String] $WebSiteName = "Default Web Site"
)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

Import-Module $PSScriptRoot\SetupAzBet.psm1 -Force

<#
.SYNOPSIS
The main top level function to configure the website on IIS with SSL support.

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

.PARAMETER CertificateToImport
Path of the SSL certificate to import.
#>
function Set-AzBetWebsite
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
        [string] $SqlAdminPassword,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String] $CertificateToImport,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $CertificatePassword,

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

    $unzipPath = Get-UnzipFiles -zipFilePath $localPath -outPath "$env:temp"

    # Set the Sql connection string info.
    $connectionString = Get-SqlConnectionString -ServerName $SqlServerName -DatabaseName $DatabaseName -UserName $SqlAdminUserName -Password $SqlAdminPassword

    $SQLSessionStoreConnectionString = Get-SqlConnectionString -ServerName $SqlServerName -DatabaseName "ASPState" -UserName $SqlAdminUserName -Password $SqlAdminPassword

    # Set Web Config
    $WebConfigPath = Join-Path -Path $unzipPath -ChildPath "Web.config"

    Set-WebConfig -WebConfigPath $WebConfigPath -SQLConnectionString $connectionString -DeploymentEnvironmentName $DeploymentEnvironmentName -SQLSessionStoreConnectionString $SQLSessionStoreConnectionString

    # Copy Website files to IIS Directory
    $iisRootPath = "$env:SystemDrive\inetpub\wwwroot"
    
    if(-not (Test-Path -Path $iisRootPath))
    {
        throw "Cannot find Default application web root path: $iisRootPath"
    }

    Copy-Item -Path "$unzipPath\*" -Destination $iisRootPath -Force -Recurse 

    # Set SSL certificate binding.
    
    # Get the certificate from Azure blob storage.
    $certLocalPath = Get-InfraFileFromAzure -StorageAccessKey $StorageAccessKey `
                                        -BlobName $CertificateToImport `
                                        -StorageAccountName $StorageAccountName `
                                        -AzureContainerName $AzureContainerName `
                                        -AzureEnvironmentName $AzureEnvironmentName

    Set-SecureCertificate -CertificateToImport $certLocalPath -CertificatePassword $CertificatePassword

    # Install URL ReWrite.
    Install-URLReWrite
    & iisreset
}

<#
.SYNOPSIS
[Helper function] Updates the Web.Config for the website with the SQL Connection String.

.DESCRIPTION
This command updates the Web.config with the SQL connection string.

.PARAMETER WebConfigPath
Path of the Web.Config file.

.PARAMETER SQLConnectionString
The SQL connection string.
#>
function Set-WebConfig
{
     param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $WebConfigPath,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $SQLConnectionString,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $SQLSessionStoreConnectionString,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $DeploymentEnvironmentName
    )

    [Xml] $webConfig = Get-Content -Path $WebConfigPath

    $connectionElement = $webConfig.configuration.connectionStrings.add | ? Name -EQ "DefaultConnection"
    $connectionElement.connectionString = $SQLConnectionString

    $sessionStoreconnectionElement = $webConfig.configuration.connectionStrings.add | ? Name -EQ "SessionStoreConnection"
    $sessionStoreconnectionElement.connectionString = $SQLSessionStoreConnectionString

    $logEnvironment = $webConfig.configuration.appSettings.add | ? key -EQ "LogEnvironment"
    $logEnvironment.value = $DeploymentEnvironmentName

    $webConfig.Save($WebConfigPath)
}

<#
.SYNOPSIS
[Helper function] Install the URL Rewrite 2.0 IIS feature from the web.

.DESCRIPTION
This command installs the URL Rewrite 2.0 feature from the microsoft download center.
#>
function Install-URLReWrite
{

    $iisFeature = Get-WindowsFeature Web-Server

    if(-not $iisFeature.Installed)
    {
        throw "IIS is not installed on this machine."
    }

    $uri = "http://download.microsoft.com/download/6/7/D/67D80164-7DD0-48AF-86E3-DE7A182D6815/rewrite_2.0_rtw_x64.msi"

    Invoke-WebRequest -Uri $uri -OutFile $env:temp\urlrewrite.msi

    & $env:temp\urlrewrite.msi /quiet
}

<#
.SYNOPSIS
[Helper function] Imports and binds the secure certificate in IIS.

.DESCRIPTION
This command imports the provided Pfx Certificate in the local machine scope and binds it with ISS website.

.PARAMETER CertificateToImport
Path of the .pfx certificate file.

.PARAMETER CertificatePassword
Certificate password.

.PARAMETER ListeningPort
Website Listening port. Default is 443.

.PARAMETER WebSiteName
Name of the Website. Default is: "Default Web Site".
#>
function Set-SecureCertificate
{
    param
    (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String] $CertificateToImport,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $CertificatePassword,
        
        [int] $ListeningPort = 443,
        
        [String] $WebSiteName = "Default Web Site"
    )

    $securePwd = ConvertTo-SecureString $CertificatePassword -AsPlainText -Force

    $cert = Import-PfxCertificate -CertStoreLocation cert:\localmachine\my -Exportable -Password $securePwd -FilePath $CertificateToImport

    if($(Get-WebBinding -Protocol https -port $ListeningPort -Name $WebSiteName) -eq $null)
    {
        New-WebBinding -Protocol https -port $ListeningPort -Name $WebSiteName |out-null
    }

    Get-Item -Path "IIS:\SslBindings\0.0.0.0!$ListeningPort" -ErrorAction ignore |remove-item
    New-Item -Path "IIS:\SslBindings\0.0.0.0!$ListeningPort" -Value $cert -Force
}

###
## Calling Script
###

Get-ARMPSModule

Set-AzBetWebsite -StorageAccessKey $StorageAccessKey `
                 -AzureEnvironmentName $AzureEnvironmentName `
                 -AzureContainerName $AzureContainerName `
                 -StorageAccountName $StorageAccountName `
                 -AzureBlobName $AzureBlobName `
                 -SqlServerName $SqlServerName `
                 -DatabaseName $DatabaseName `
                 -SqlAdminUserName $SqlAdminUserName `
                 -SqlAdminPassword $SqlAdminPassword `
                 -CertificateToImport $CertificateToImport `
                 -CertificatePassword $CertificatePassword `
                 -DeploymentEnvironmentName $DeploymentEnvironmentName
                 
                 


