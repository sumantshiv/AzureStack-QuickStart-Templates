function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.UInt32]
        $DeploymentNodeIndex,

        [parameter(Mandatory = $true)]
        [System.UInt32]
        $InstanceCount,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClusterName,

        [parameter(Mandatory = $true)]
        [System.String]
        $VMNodeTypeName,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $HTTPGatewayEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ReverseProxyEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $EphemeralStartPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $EphemeralEndPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ApplicationStartPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ApplicationEndPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ConfigPath,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServiceFabricUrl,

        [parameter(Mandatory = $true)]
        [System.String]
        $DiagStoreAccountName,

        [parameter(Mandatory = $true)]
        [System.String]
        $DiagStoreAccountKey,

        [parameter(Mandatory = $true)]
        [System.String]
        $DiagStoreAccountBlobUri,

        [parameter(Mandatory = $true)]
        [System.String]
        $DiagStoreAccountTableUri,

        [parameter(Mandatory = $true)]
        [System.String]
        $CertificateStoreValue,

        [parameter(Mandatory = $true)]
        [System.String]
        $CertificateThumbprint
    )

}


function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.UInt32]
        $DeploymentNodeIndex,

        [parameter(Mandatory = $true)]
        [System.UInt32]
        $InstanceCount,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClusterName,

        [parameter(Mandatory = $true)]
        [System.String]
        $VMNodeTypeName,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $HTTPGatewayEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ReverseProxyEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $EphemeralStartPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $EphemeralEndPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ApplicationStartPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ApplicationEndPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ConfigPath,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServiceFabricUrl,

        [parameter(Mandatory = $true)]
        [System.String]
        $DiagStoreAccountName,

        [parameter(Mandatory = $true)]
        [System.String]
        $DiagStoreAccountKey,

        [parameter(Mandatory = $true)]
        [System.String]
        $DiagStoreAccountBlobUri,

        [parameter(Mandatory = $true)]
        [System.String]
        $DiagStoreAccountTableUri,

        [parameter(Mandatory = $true)]
        [System.String]
        $CertificateStoreValue,

        [parameter(Mandatory = $true)]
        [System.String]
        $CertificateThumbprint,

        [System.String]
        $ReverseProxyCertificateStoreValue,

        [System.String]
        $ReverseProxyCertificateThumbprint,

        [System.String]
        $AdminClientCertificateThumbprint,

        [System.String]
        $NonAdminClientCertificateThumbprint
    )

    $ErrorActionPreference = "Stop"

    # Enable File and Printer Sharing for Network Discovery (Port 445)
    Write-Verbose "Opening TCP firewall port 445 for networking."
    Set-NetFirewallRule -Name 'FPS-SMB-In-TCP' -Enabled True
    Get-NetFirewallRule -DisplayGroup 'Network Discovery' | Set-NetFirewallRule -Profile 'Private, Public' -Enabled true

    # Get the index of current node and match it with the index of required deployment node.
    $alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"

    $base36Num = $env:COMPUTERNAME.Substring(($vmNodeTypeName).Length)
    $inputarray = $base36Num.tolower().tochararray()
    [array]::reverse($inputarray)
                
    [long]$scaleSetDecimalIndex=0
    $pos=0

    foreach ($c in $inputarray)
    {
        $scaleSetDecimalIndex += $alphabet.IndexOf($c) * [long][Math]::Pow(36, $pos)
        $pos++
    }

    # Return in case the current node is not the deployment node, else continue with SF deployment.
    if($scaleSetDecimalIndex -ne $DeploymentNodeIndex)
    {
        Write-Verbose "Service Fabric deployment runs on Node with index: '$DeploymentNodeIndex'."
        return
    }

    Write-Verbose "Starting service fabric deployment on Node: '$env:COMPUTERNAME'."

    # Store setup files on Temp disk.
    $setupDir = "D:\SFSetup"
    New-Item -Path $setupDir -ItemType Directory -Force
    cd $setupDir
    $CofigFilePath = Join-Path -Path $setupDir -ChildPath 'ClusterConfig.json'
                
    Write-Verbose "Get Service fabric configuration from '$ConfigPath'"
    $request = Invoke-WebRequest $ConfigPath -UseBasicParsing
    $configContent = ConvertFrom-Json  $request.Content

    $configContent.name = "$ClusterName"

    # Getting the IP address of the first node with index 0 to start counting Node IPs from this address.
    $startNodeIpAddressLable = (Get-NetIPAddress).IPv4Address | ? {$_ -ne "" -and $_ -ne "127.0.0.1"}
    $startNodeIpAddress = [IPAddress](([String]$startNodeIpAddressLable).Trim(' '))                

    Write-Verbose "Start node IPAddress: '$startNodeIpAddress'"

    # Adding Nodes to the configuration.
    $i = 0
    $sfnodes = @()
				
    try
    {
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value * -Force

        while($i -lt $InstanceCount)
        {

		    $IpStartBytes = $startNodeIpAddress.GetAddressBytes()
		    $IpStartBytes[3] = $IpStartBytes[3] + $i
		    $ip = [IPAddress]($IpStartBytes)
                    
		    $nodeName = Invoke-Command -ScriptBlock {hostname} -ComputerName "$($ip.IPAddressToString)"

            # Get the decimal based index of the VM machine name (VM Scale set name the machines in the format {Prefix}{Suffix}
            # where Suffix is a 6 digit base36 number starting from 000000 to zzzzzz.
            # Getting the decimal equivalent of the index to use it in the FD and UD name.
            $nodeScaleSetDecimalIndex = ConvertFrom-Base36 -base36Num ($nodeName.ToString().Substring(($vmNodeTypeName).Length))            

            $fdIndex = $nodeScaleSetDecimalIndex + 1

            $node = New-Object PSObject 
					
		    $node | Add-Member -MemberType NoteProperty -Name "nodeName" -Value $($nodeName).ToString()
            $node | Add-Member -MemberType NoteProperty -Name "iPAddress" -Value $ip.IPAddressToString
            $node | Add-Member -MemberType NoteProperty -Name "nodeTypeRef" -Value "$vmNodeTypeName"
            $node | Add-Member -MemberType NoteProperty -Name "faultDomain" -Value "fd:/dc$fdIndex/r0"
            $node | Add-Member -MemberType NoteProperty -Name "upgradeDomain" -Value "UD$nodeScaleSetDecimalIndex"

            Write-Verbose "Adding Node to configuration: '$nodeName'"
		    $sfnodes += $node
		    $i++
	    }
    }
    finally
    {
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value "" -Force    
    }

    $configContent.nodes = $sfnodes

    # Adding Node Type to the configuration.
    Write-Verbose "Creating node type '$vmNodeTypeName'"
    $nodeTypes =@()
                
    $nodeType = New-Object PSObject
    $nodeType | Add-Member -MemberType NoteProperty -Name "name" -Value "$vmNodeTypeName"
    $nodeType | Add-Member -MemberType NoteProperty -Name "clientConnectionEndpointPort" -Value "$clientConnectionEndpointPort"
    $nodeType | Add-Member -MemberType NoteProperty -Name "clusterConnectionEndpointPort" -Value "19001"
    $nodeType | Add-Member -MemberType NoteProperty -Name "leaseDriverEndpointPort" -Value "19002"
    $nodeType | Add-Member -MemberType NoteProperty -Name "serviceConnectionEndpointPort" -Value "19003"
    $nodeType | Add-Member -MemberType NoteProperty -Name "httpGatewayEndpointPort" -Value "$httpGatewayEndpointPort"
    $nodeType | Add-Member -MemberType NoteProperty -Name "reverseProxyEndpointPort" -Value "$reverseProxyEndpointPort"
                
    $applicationPorts = New-Object PSObject
    $applicationPorts | Add-Member -MemberType NoteProperty -Name "startPort" -Value "$applicationStartPort"
    $applicationPorts | Add-Member -MemberType NoteProperty -Name "endPort" -Value "$applicationEndPort"

    $ephemeralPorts = New-Object PSObject
    $ephemeralPorts | Add-Member -MemberType NoteProperty -Name "startPort" -Value "$ephemeralStartPort"
    $ephemeralPorts | Add-Member -MemberType NoteProperty -Name "endPort" -Value "$ephemeralEndPort"
                
    $nodeType | Add-Member -MemberType NoteProperty -Name "applicationPorts" -Value $applicationPorts
    $nodeType | Add-Member -MemberType NoteProperty -Name "ephemeralPorts" -Value $ephemeralPorts

    $nodeType | Add-Member -MemberType NoteProperty -Name "isPrimary" -Value $true

    Write-Verbose "Adding Node Type to configuration: '$vmNodeTypeName'"
    $nodeTypes += $nodeType
    $configContent.properties.nodeTypes = $nodeTypes

    # Adding Diagnostics store settings to the configuration.
    Write-Verbose "Creating diagnostics share at: '$DiagStoreAccountName' blob store"

    $diagStoreConnectinString = "xstore:DefaultEndpointsProtocol=https;AccountName=$DiagStoreAccountName;AccountKey=$DiagStoreAccountKey;BlobEndpoint=$DiagStoreAccountBlobUri;TableEndpoint=$DiagStoreAccountTableUri"

    Write-Verbose "Setting diagnostics store to: '$diagStoreConnectinString'"
    $configContent.properties.diagnosticsStore.connectionstring = $diagStoreConnectinString

    # Adding Security settings to the configuration.
    $configContent.properties.security.CertificateInformation.ClusterCertificate.Thumbprint = $certificateThumbprint
    $configContent.properties.security.CertificateInformation.ClusterCertificate.X509StoreName = $certificateStoreValue

    $configContent.properties.security.CertificateInformation.ServerCertificate.Thumbprint = $certificateThumbprint
    $configContent.properties.security.CertificateInformation.ServerCertificate.X509StoreName = $certificateStoreValue

    $configContent.properties.security.CertificateInformation.ReverseProxyCertificate.Thumbprint = $reverseProxyCertificateThumbprint
    $configContent.properties.security.CertificateInformation.ReverseProxyCertificate.X509StoreName = $reverseProxyCertificateStoreValue

    Write-Verbose "Creating Client Certificate Thumbprint data."
    $ClientCertificateThumbprints = @()
                
    $adminClientCertificate = New-Object PSObject
    $adminClientCertificate | Add-Member -MemberType NoteProperty -Name "CertificateThumbprint" -Value "$adminClientCertificateThumbprint"
    $adminClientCertificate | Add-Member -MemberType NoteProperty -Name "IsAdmin" -Value $true

    $ClientCertificateThumbprints += $adminClientCertificate

    $nonAdminClientCertificate = New-Object PSObject
    $nonAdminClientCertificate | Add-Member -MemberType NoteProperty -Name "CertificateThumbprint" -Value "$nonAdminClientCertificateThumbprint"
    $nonAdminClientCertificate | Add-Member -MemberType NoteProperty -Name "IsAdmin" -Value $false

    $ClientCertificateThumbprints += $nonAdminClientCertificate

    $configContent.properties.security.CertificateInformation.ClientCertificateThumbprints = $ClientCertificateThumbprints

				
    # Creating configuration json.
    $configContent = ConvertTo-Json $configContent -Depth 99
    Write-Verbose $configContent
    Write-Verbose "Creating service fabric config file at: '$CofigFilePath'"
    $configContent | Out-File $CofigFilePath

    Write-Verbose "Downloading Service Fabric deployment package from: '$serviceFabricUrl'"
    Invoke-WebRequest -Uri $serviceFabricUrl -OutFile (Join-Path -Path $setupDir -ChildPath ServiceFabric.zip) -UseBasicParsing
    Expand-Archive (Join-Path -Path $setupDir -ChildPath ServiceFabric.zip) -DestinationPath (Join-Path -Path $setupDir -ChildPath ServiceFabric) -Force
                
    # Deployment

    Write-Verbose "Validating Service Fabric input configuration"
    $output = .\ServiceFabric\TestConfiguration.ps1 -ClusterConfigFilePath $CofigFilePath -Verbose

    $passStatus = $output | % {if($_ -like "Passed*"){$_}}
    $del = " ", ":"
    $configValidationresult = ($passStatus.Split($del, [System.StringSplitOptions]::RemoveEmptyEntries))[1]

    if($configValidationresult -ne "True")
    {
        throw ($output | Out-String)
    }

    Write-Verbose "Starting Service Fabric runtime deployment"
    $output = .\ServiceFabric\CreateServiceFabricCluster.ps1 -ClusterConfigFilePath $CofigFilePath -AcceptEULA -Verbose
    Write-Verbose ($output | Out-String)
                
    # Validations
                
    Write-Verbose "Validating Service Fabric deployment."
                
    # Connection validation
    $timeoutTime = (Get-Date).AddMinutes(5)
    $connectSucceeded = $false
    $lastException
                
    while(-not $connectSucceeded -and (Get-Date) -lt $timeoutTime)
    {
        try
        {   
            Import-Module ServiceFabric -ErrorAction SilentlyContinue -Verbose:$false
            $connection = Connect-ServiceFabricCluster
            if($connection -and $connection[0])
            {
                Write-Verbose "Service Fabric connection successful." 
                $connectSucceeded = $true    
            }
            else
            {
                throw "Could not connect to service fabric cluster."
            }
        }
        catch
        {
            $lastException = $_.Exception
            Write-Verbose "Connection failed because: $lastException. Retrying until $timeoutTime."
            Write-Verbose "Waiting for 60 seconds..."
            Start-Sleep -Seconds 60
        }
    }

    if(-not $connectSucceeded)
    {
        throw "Cluster validation failed with error: $lastException.`n Please check the detailed DSC logs and Service fabric deployment traces at: '$setupDir\ServiceFabric\DeploymentTraces' on the VM: '$env:ComputerName'."
    }

    # Health validation
    $timeoutTime = (Get-Date).AddMinutes(5)
    $isHealthy = $false
                
    while((-not $isHealthy) -and ((Get-Date) -lt $timeoutTime))
    {
        $Error.Clear()
        $healthReport = Get-ServiceFabricClusterHealth #Get-ServiceFabricClusterHealth ToString is bugged, so calling twice
        $healthReport = Get-ServiceFabricClusterHealth
        if(($healthReport.HealthEvents.Count > 0) -or ($healthReport.UnhealthyEvaluations.Count > 0))
        {
            Write-Verbose "Cluster health events were raised. Retrying until $timeoutTime."
            Start-Sleep -Seconds 60
        }
        else
        {
            Write-Verbose "Service Fabric cluster is healthy." 
            $isHealthy = $true
        }
    }

    if(-not $isHealthy)                
    {
        throw "Cluster validation failed with error: Cluster unhealthy.`n Please check the detailed DSC logs and Service fabric deployment traces at: '$setupDir\ServiceFabric\DeploymentTraces' on the VM: '$env:ComputerName'."
    }

    # Upgrade state validation
    $minutesToWait = 5 * $InstanceCount
    $timeoutTime = (Get-Date).AddMinutes($minutesToWait)
    $upgradeComplete = $false
    $lastException

    while((-not $upgradeComplete) -and ((Get-Date) -lt $timeoutTime))
    {
        try
        {
            $upgradeStatus = (Get-ServiceFabricClusterConfigurationUpgradeStatus).UpgradeState

            if($upgradeStatus -eq "RollingForwardCompleted")
            {
                Write-Verbose "Expected service Fabric upgrade status '$upgradeStatus' set." 
                $upgradeComplete = $true
            }
            else
            {
                throw "Unexpected Upgrade status: '$upgradeStatus'."
            }
        }
        catch
        {
            $lastException = $_.Exception
            Write-Verbose "Upgrade status check failed because: $lastException. Retrying until $timeoutTime."
            Write-Verbose "Waiting for 60 seconds..."
            Start-Sleep -Seconds 60
        }
    }

    if(-not $upgradeComplete)                
    {
        throw "Cluster validation failed with error: $lastException.`n Please check the detailed DSC logs and Service fabric deployment traces at: '$setupDir\ServiceFabric\DeploymentTraces' on the VM: '$env:ComputerName'."
    }


}


function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.UInt32]
        $DeploymentNodeIndex,

        [parameter(Mandatory = $true)]
        [System.UInt32]
        $InstanceCount,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClusterName,

        [parameter(Mandatory = $true)]
        [System.String]
        $VMNodeTypeName,

        [parameter(Mandatory = $true)]
        [System.String]
        $ClientConnectionEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $HTTPGatewayEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ReverseProxyEndpointPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $EphemeralStartPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $EphemeralEndPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ApplicationStartPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ApplicationEndPort,

        [parameter(Mandatory = $true)]
        [System.String]
        $ConfigPath,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServiceFabricUrl,

        [parameter(Mandatory = $true)]
        [System.String]
        $DiagStoreAccountName,

        [parameter(Mandatory = $true)]
        [System.String]
        $DiagStoreAccountKey,

        [parameter(Mandatory = $true)]
        [System.String]
        $DiagStoreAccountBlobUri,

        [parameter(Mandatory = $true)]
        [System.String]
        $DiagStoreAccountTableUri,

        [parameter(Mandatory = $true)]
        [System.String]
        $CertificateStoreValue,

        [parameter(Mandatory = $true)]
        [System.String]
        $CertificateThumbprint,

        [System.String]
        $ReverseProxyCertificateStoreValue,

        [System.String]
        $ReverseProxyCertificateThumbprint,

        [System.String]
        $AdminClientCertificateThumbprint,

        [System.String]
        $NonAdminClientCertificateThumbprint
    )

    return $false
}

function ConvertTo-Base36
{
    param
    (
        [String] $base36Num
    )

    $inputarray = $base36Num.tolower().tochararray()
    [array]::reverse($inputarray)
                
    [long]$decimalIndex=0
    $pos=0

    foreach ($c in $inputarray)
    {
        $decimalIndex += $alphabet.IndexOf($c) * [long][Math]::Pow(36, $pos)
        $pos++
    }

    return $decimalIndex
}


Export-ModuleMember -Function *-TargetResource

