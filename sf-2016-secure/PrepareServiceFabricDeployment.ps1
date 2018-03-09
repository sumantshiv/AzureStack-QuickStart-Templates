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
        [string] $ClusterCertPassword,

        [Parameter(Mandatory=$true)]
        [string] $CertificateThumbprint,

        [Parameter(Mandatory=$false)]
        [string] $ReverseProxyCertName="",

        [Parameter(Mandatory=$false)]
        [string] $ReverseProxyCertPassword="",

        [Parameter(Mandatory=$false)]
        [string] $ReverseProxyCertificateThumbprint=""
)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$VerbosePreference = "Continue"

# Enable File and Printer Sharing for Network Discovery (Port 445)
Write-Verbose "Opening TCP firewall port 445 for networking."
Set-NetFirewallRule -Name 'FPS-SMB-In-TCP' -Enabled True
Get-NetFirewallRule -DisplayGroup 'Network Discovery' | Set-NetFirewallRule -Profile 'Private, Public' -Enabled true

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

# As per Service fabric documentation at: https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-windows-cluster-x509-security#install-the-certificates
# set the access control on this certificate so that the Service Fabric process, which runs under the Network Service account, 
# can use it by running the following script. Provide the thumbprint of the certificate and NETWORK SERVICE for the service account.
function Grant-CertAccess
{
    param
    (
    [Parameter(Position=1, Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$pfxThumbPrint,

    [Parameter(Position=2, Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$serviceAccount
    )

    $cert = Get-ChildItem -Path cert:\LocalMachine\My | Where-Object -FilterScript { $PSItem.ThumbPrint -eq $pfxThumbPrint; }

    # Specify the user, the permissions, and the permission type
    $permission = "$($serviceAccount)","FullControl","Allow"
    $accessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule -ArgumentList $permission

    # Location of the machine-related keys
    $keyPath = Join-Path -Path $env:ProgramData -ChildPath "\Microsoft\Crypto\RSA\MachineKeys"
    $keyName = $cert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
    $keyFullPath = Join-Path -Path $keyPath -ChildPath $keyName

    # Get the current ACL of the private key
    $acl = (Get-Item $keyFullPath).GetAccessControl('Access')

    # Add the new ACE to the ACL of the private key
    $acl.SetAccessRule($accessRule)

    # Write back the new ACL
    Set-Acl -Path $keyFullPath -AclObject $acl -ErrorAction Stop

    # Observe the access rights currently assigned to this certificate
    get-acl $keyFullPath| fl
}

# Install ARM PS cmdlets.
#Get-ARMPSModule

$localDir = $env:Temp

$certPwdMapping = @{}
if( -not $certPwdMapping.ContainsKey($ClusterCertName))
{
    $certPwdMapping.Add($ClusterCertName, $ClusterCertPassword)
}

if(-not [string]::IsNullOrEmpty($ReverseProxyCertName))
{
    if( -not $certPwdMapping.ContainsKey($ReverseProxyCertName))
    {
        $certPwdMapping.Add($ReverseProxyCertName, $ReverseProxyCertPassword)
    }
}

$certThumbprintMapping = @{}
if( -not $certThumbprintMapping.ContainsKey($ClusterCertName))
{
    $certThumbprintMapping.Add($ClusterCertName, $certificateThumbprint)
}

if(-not ([string]::IsNullOrEmpty($ReverseProxyCertName)) -and -not([string]::IsNullOrEmpty($ReverseProxyCertificateThumbprint)))
{
    if( -not $certThumbprintMapping.ContainsKey($ReverseProxyCertName))
    {
        $certThumbprintMapping.Add($ReverseProxyCertName, $reverseProxyCertificateThumbprint)
    }
}

$certPwdMapping.Keys | % {

                    <#
                    Get-InfraFileFromAzure -StorageAccessKey $StorageAccessKey `
                                            -BlobName $_ `
                                            -StorageAccountName $StorageAccountName `
                                            -AzureContainerName $ContainerName `
                                            -AzureEnvironmentName $EnvironmentName `
                                            -LocalOutPath  $localDir

                    # Import Certs.
                    $certPath = Join-Path -Path $localDir -ChildPath $_
                    Import-PfxCertificate -Exportable -CertStoreLocation Cert:\LocalMachine\My -FilePath $certPath -Password (ConvertTo-SecureString -String $($certPwdMapping.$_) -AsPlainText -Force)
                    #>

                    # Grant Network Service access to certificates as per the documentation at: 
                    # https://docs.microsoft.com/en-us/azure/service-fabric/service-fabric-windows-cluster-x509-security#install-the-certificates
                    Grant-CertAccess -pfxThumbPrint $($certThumbprintMapping.$_) -serviceAccount "Network Service"
                }