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

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $AzureEnvironmentName,

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
        Install-Module -Name AzureRM -RequiredVersion "1.2.9"
    }
}

<#
.SYNOPSIS
[Helper function] Gets SQL connection string.
#>
function Get-SqlConnectionString
{
     param
    (
        [Parameter(Mandatory=$true)]
        [string] $ServerName,

        [Parameter(Mandatory=$true)]
        [string] $DatabaseName,

        [Parameter(Mandatory=$true)]
        [string] $UserName,

        [Parameter(Mandatory=$true)]
        [string] $Password
    )
    
    return "Server=tcp:$ServerName,1433;Integrated Security=false;User ID=$UserName;Password=$Password;Database=$DatabaseName"
}

<#
.SYNOPSIS
[Helper function] Unzips a file into $env:Temp directory and return the explanded path.
#>
function Get-UnzipFiles
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$zipFilePath,
    
        [Parameter(Mandatory=$true)]
        [string]$outPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem    

    $packageName = (Get-Item -Path $zipFilePath).BaseName   
    $desiredPath = Join-Path -Path $outPath -ChildPath $packageName

    if(Test-Path -Path $desiredPath)
    {
        Remove-Item -Path $desiredPath -Force -Recurse
    }
    
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFilePath, $desiredPath)
    
    return $desiredPath
}

