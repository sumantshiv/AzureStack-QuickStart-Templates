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
        [string] $BlobName
)

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
        [string] $BlobName
    )

    $success = $false
    $retries = 20

    while($success -eq $false -and $retries -ge 0)
    {
        $success = $true
        
        try
        {
            $localDir = $env:Temp
            $TargetLocalRootPath = $localDir + "\" + $BlobName

            if(Test-Path -Path $TargetLocalRootPath)
            {                
                return $TargetLocalRootPath
            }
            
            $storageContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccessKey -Environment $AzureEnvironmentName
            Get-AzureStorageBlobContent -Blob $BlobName -Container $AzureContainerName -Destination $localDir -Context $storageContext | Out-Null
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
    return $TargetLocalRootPath
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


