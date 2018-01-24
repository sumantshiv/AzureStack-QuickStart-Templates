param
(
        [Parameter(Mandatory=$true)]
        [string] $StorageAccessKey,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $StorageAccountName,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $ContainerName,

        [Parameter(Mandatory=$false)]
        [string] $EnvironmentName = "AzureCloud",

        [Parameter(Mandatory=$true)]
        [string] $ClusterCertName,

        [Parameter(Mandatory=$true)]
        [Security.SecureString] $ClusterCertPassword,

        [Parameter(Mandatory=$true)]
        [string] $ReverseProxyCertName,

        [Parameter(Mandatory=$true)]
        [Security.SecureString] $ReverseProxyCertPassword
)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

<#
.SYNOPSIS
[Helper function] Download artifacts from Azure private container.
#>
function Get-InfraFileFromAzure
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string] $StorageAccessKey,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $StorageAccountName,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $AzureContainerName,

        [Parameter(Mandatory=$false)]
        [string] $AzureEnvironmentName = "AzureCloud",

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $BlobName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $LocalOutPath
    )

    $success = $false
    $retries = 20

    while($success -eq $false -and $retries -ge 0)
    {
        $success = $true
        
        try
        {
            $TargetLocalRootPath = Join-Path -Path $LocalOutPath  -ChildPath $BlobName

            if(Test-Path -Path $TargetLocalRootPath)
            {                
                return $TargetLocalRootPath
            }
            
            $storageContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccessKey -Environment $AzureEnvironmentName
            Get-AzureStorageBlobContent -Blob $BlobName -Container $AzureContainerName -Destination $LocalOutPath -Context $storageContext | Out-Null
        }
        catch
        {
            $success = $false
            Start-Sleep -Seconds 10
        }
        $retries--
        if($success = $false)
        {
            Start-Sleep -Seconds 10
        }

    }
    if($success -eq $false)
    {
        $errMsg =  "Failed to download $blobName from Azure after retries"
        throw $errMsg
    }
}

<#
.SYNOPSIS
[Helper function] Installs Azure RM PowerShell module if absent.
#>
function Get-ARMPSModule
{
    $module = Get-Module -ListAvailable | ? Name -eq "AzureRM"

    if(-not $module)
    {
        Get-Packageprovider -Name NuGet -Force
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        Install-Module -Name AzureRM -RequiredVersion "1.2.11"
    }
}

# Install ARM PS cmdlets.
Get-ARMPSModule

$localDir = $env:Temp

$CertTable = @{"$ClusterCertName" = $ClusterCertPassword; "$ReverseProxyCertName" = $ReverseProxyCertPassword}

$CertTable.Keys | % {
                    Get-InfraFileFromAzure -StorageAccessKey $StorageAccessKey `
                                            -BlobName $_ `
                                            -StorageAccountName $StorageAccountName `
                                            -AzureContainerName $ContainerName `
                                            -AzureEnvironmentName $EnvironmentName `
                                            -LocalOutPath  $localDir

                    # Import Certs.

                    $certPath = Join-Path -Path $localDir -ChildPath $_

                    Import-PfxCertificate -Exportable -CertStoreLocation Cert:\LocalMachine\My -FilePath $certPath -Password $($CertTable.$_)
                }





