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

    # Enable File and Printer Sharing and Network Discovery (Port 445)
    Enable-NetworkDiscovery

    # Get the decimal based index of the VM machine name (VM Scale set name the machines in the format {Prefix}{Suffix}
    # where Suffix is a 6 digit base36 number starting from 000000 to zzzzzz.
    # Get the decimal index of current node and match it with the index of required deployment node.
    $scaleSetDecimalIndex = ConvertFrom-Base36 -base36Num ($env:COMPUTERNAME.Substring(($vmNodeTypeName).Length))

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

    # Get Service fabric configuration file locally for update.
    Write-Verbose "Get Service fabric configuration from '$ConfigPath'"
    $request = Invoke-WebRequest $ConfigPath -UseBasicParsing
    $configContent = ConvertFrom-Json  $request.Content
    $ConfigFilePath = Join-Path -Path $setupDir -ChildPath 'ClusterConfig.json'
    Write-Verbose "Creating service fabric config file at: '$ConfigFilePath'"
    $configContent | Out-File $ConfigFilePath

    # Add Nodes configuration.
    Add-ServiceFabricNodeConfiguration -ConfigFilePath $ConfigFilePath -ClusterName $ClusterName -InstanceCount $InstanceCount -VMNodeTypeName $VMNodeTypeName

    # Add NodeType configuration.
    Add-ServiceFabricNodeTypeConfiguration -ConfigFilePath $ConfigFilePath `
                                            -VMNodeTypeName $VMNodeTypeName `
                                            -ClientConnectionEndpointPort $ClientConnectionEndpointPort `
                                            -HTTPGatewayEndpointPort $HTTPGatewayEndpointPort `
                                            -ReverseProxyEndpointPort $ReverseProxyEndpointPort `
                                            -EphemeralStartPort $EphemeralStartPort `
                                            -EphemeralEndPort $EphemeralEndPort `
                                            -ApplicationStartPort $ApplicationStartPort `
                                            -ApplicationEndPort $ApplicationEndPort

    # Add Deiagnostics configuration.
    Add-ServiceFabricDiagnosticsConfiguration -ConfigFilePath $ConfigFilePath `
                                                -DiagStoreAccountName $DiagStoreAccountName `
                                                -DiagStoreAccountKey $DiagStoreAccountKey `
                                                -DiagStoreAccountBlobUri $DiagStoreAccountBlobUri `
                                                -DiagStoreAccountTableUri $DiagStoreAccountTableUri

    # Add Security configuration.
    Add-ServiceFabricSecurityConfiguration -ConfigFilePath $ConfigFilePath `
                                            -CertificateStoreValue $CertificateStoreValue `
                                            -CertificateThumbprint $CertificateThumbprint `
                                            -ReverseProxyCertificateStoreValue $ReverseProxyCertificateStoreValue `
                                            -ReverseProxyCertificateThumbprint $ReverseProxyCertificateThumbprint `
                                            -AdminClientCertificateThumbprint $AdminClientCertificateThumbprint `
                                            -NonAdminClientCertificateThumbprint $NonAdminClientCertificateThumbprint

    # Validate and Deploy Service Fabric Configuration
    New-ServiceFabricDeployment -setupDir $setupDir -ConfigFilePath $ConfigFilePath -ServiceFabricUrl $ServiceFabricUrl

    # Validations
    Write-Verbose "Validating Service Fabric deployment."

    # Connection validation
    Test-ServiceFabricLocalConnection -setupDir $setupDir

    # Health validation
    Test-ServiceFabricHealth -setupDir $setupDir

    # Upgrade state validation
    Test-ServiceFabricUpgradeState -setupDir $setupDir -InstanceCount $InstanceCount
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

function ConvertFrom-Base36
{
    param
    (
        [String] $base36Num
    )

    $alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"

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

function Enable-NetworkDiscovery
{
    param()

    Write-Verbose "Opening TCP firewall port 445 for networking."
    Set-NetFirewallRule -Name 'FPS-SMB-In-TCP' -Enabled True
    Get-NetFirewallRule -DisplayGroup 'Network Discovery' | Set-NetFirewallRule -Profile 'Private, Public' -Enabled true
}

function Add-ServiceFabricNodeConfiguration
{
    param
    (
        [String] $ConfigFilePath,

        [String] $ClusterName,

        [System.UInt32] $InstanceCount,

        [String] $VMNodeTypeName
    )

    [String] $content = Get-Content -Path $ConfigFilePath
    $configContent = ConvertFrom-Json  $content

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
            $nodeScaleSetDecimalIndex = ConvertFrom-Base36 -base36Num ($nodeName.ToString().Substring(($VMNodeTypeName).Length))

            $fdIndex = $nodeScaleSetDecimalIndex + 1

            $node = New-Object PSObject
            $node | Add-Member -MemberType NoteProperty -Name "nodeName" -Value $($nodeName).ToString()
            $node | Add-Member -MemberType NoteProperty -Name "iPAddress" -Value $ip.IPAddressToString
            $node | Add-Member -MemberType NoteProperty -Name "nodeTypeRef" -Value "$VMNodeTypeName"
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

    $configContent = ConvertTo-Json $configContent -Depth 99
    $configContent | Out-File $ConfigFilePath
}

function Add-ServiceFabricNodeTypeConfiguration
{
    param
    (
        [System.String]
        $ConfigFilePath,

        [System.String]
        $VMNodeTypeName,

        [System.String]
        $ClientConnectionEndpointPort,

        [System.String]
        $HTTPGatewayEndpointPort,

        [System.String]
        $ReverseProxyEndpointPort,

        [System.String]
        $EphemeralStartPort,

        [System.String]
        $EphemeralEndPort,

        [System.String]
        $ApplicationStartPort,

        [System.String]
        $ApplicationEndPort
    )

    [String] $content = Get-Content -Path $ConfigFilePath
    $configContent = ConvertFrom-Json  $content

    # Adding Node Type to the configuration.
    Write-Verbose "Creating node type."
    $nodeTypes =@()

    $nodeType = New-Object PSObject
    $nodeType | Add-Member -MemberType NoteProperty -Name "name" -Value "$VMNodeTypeName"
    $nodeType | Add-Member -MemberType NoteProperty -Name "clientConnectionEndpointPort" -Value "$ClientConnectionEndpointPort"
    $nodeType | Add-Member -MemberType NoteProperty -Name "clusterConnectionEndpointPort" -Value "19001"
    $nodeType | Add-Member -MemberType NoteProperty -Name "leaseDriverEndpointPort" -Value "19002"
    $nodeType | Add-Member -MemberType NoteProperty -Name "serviceConnectionEndpointPort" -Value "19003"
    $nodeType | Add-Member -MemberType NoteProperty -Name "httpGatewayEndpointPort" -Value "$HTTPGatewayEndpointPort"
    $nodeType | Add-Member -MemberType NoteProperty -Name "reverseProxyEndpointPort" -Value "$ReverseProxyEndpointPort"

    $applicationPorts = New-Object PSObject
    $applicationPorts | Add-Member -MemberType NoteProperty -Name "startPort" -Value "$ApplicationStartPort"
    $applicationPorts | Add-Member -MemberType NoteProperty -Name "endPort" -Value "$ApplicationEndPort"

    $ephemeralPorts = New-Object PSObject
    $ephemeralPorts | Add-Member -MemberType NoteProperty -Name "startPort" -Value "$EphemeralStartPort"
    $ephemeralPorts | Add-Member -MemberType NoteProperty -Name "endPort" -Value "$EphemeralEndPort"

    $nodeType | Add-Member -MemberType NoteProperty -Name "applicationPorts" -Value $applicationPorts
    $nodeType | Add-Member -MemberType NoteProperty -Name "ephemeralPorts" -Value $ephemeralPorts

    $nodeType | Add-Member -MemberType NoteProperty -Name "isPrimary" -Value $true

    Write-Verbose "Adding Node Type to configuration."
    $nodeTypes += $nodeType
    $configContent.properties.nodeTypes = $nodeTypes

    $configContent = ConvertTo-Json $configContent -Depth 99
    $configContent | Out-File $ConfigFilePath
}

function Add-ServiceFabricDiagnosticsConfiguration
{
    param
    (
        [System.String]
        $ConfigFilePath,

        [System.String]
        $DiagStoreAccountName,

        [System.String]
        $DiagStoreAccountKey,

        [System.String]
        $DiagStoreAccountBlobUri,

        [System.String]
        $DiagStoreAccountTableUri
    )

    [String] $content = Get-Content -Path $ConfigFilePath
    $configContent = ConvertFrom-Json  $content

    # Adding Diagnostics store settings to the configuration.
    $diagStoreConnectinString = "xstore:DefaultEndpointsProtocol=https;AccountName=$DiagStoreAccountName;AccountKey=$DiagStoreAccountKey;BlobEndpoint=$DiagStoreAccountBlobUri;TableEndpoint=$DiagStoreAccountTableUri"

    Write-Verbose "Setting diagnostics store to: '$diagStoreConnectinString'"
    $configContent.properties.diagnosticsStore.connectionstring = $diagStoreConnectinString

    $configContent = ConvertTo-Json $configContent -Depth 99
    $configContent | Out-File $ConfigFilePath
}

function Add-ServiceFabricSecurityConfiguration
{
    param
    (
        [System.String]
        $ConfigFilePath,

        [System.String]
        $CertificateStoreValue,

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

    [String] $content = Get-Content -Path $ConfigFilePath
    $configContent = ConvertFrom-Json  $content

    # Adding Security settings to the configuration.
    Write-Verbose "Adding security settings for Service Fabric Configuration."
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

    $configContent = ConvertTo-Json $configContent -Depth 99
    $configContent | Out-File $ConfigFilePath
}

function New-ServiceFabricDeployment
{
    param
    (
        [System.String]
        $setupDir,

        [System.String]
        $ConfigFilePath,

        [System.String]
        $ServiceFabricUrl
    )

    Write-Verbose "Downloading Service Fabric deployment package from: '$serviceFabricUrl'"
    Invoke-WebRequest -Uri $serviceFabricUrl -OutFile (Join-Path -Path $setupDir -ChildPath ServiceFabric.zip) -UseBasicParsing
    Expand-Archive (Join-Path -Path $setupDir -ChildPath ServiceFabric.zip) -DestinationPath (Join-Path -Path $setupDir -ChildPath ServiceFabric) -Force

    # Deployment
    Write-Verbose "Validating Service Fabric input configuration"
    $output = .\ServiceFabric\TestConfiguration.ps1 -ClusterConfigFilePath $ConfigFilePath -Verbose

    $passStatus = $output | % {if($_ -like "Passed*"){$_}}
    $del = " ", ":"
    $configValidationresult = ($passStatus.Split($del, [System.StringSplitOptions]::RemoveEmptyEntries))[1]

    if($configValidationresult -ne "True")
    {
        throw ($output | Out-String)
    }

    Write-Verbose "Starting Service Fabric runtime deployment"
    $output = .\ServiceFabric\CreateServiceFabricCluster.ps1 -ClusterConfigFilePath $ConfigFilePath -AcceptEULA -Verbose
    Write-Verbose ($output | Out-String)
}

function Test-ServiceFabricLocalConnection
{
    param
    (
        [System.String]
        $setupDir
    )

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
}

function Test-ServiceFabricHealth
{
    param
    (
        [System.String]
        $setupDir
    )

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
}

function Test-ServiceFabricUpgradeState
{
    param
    (
        [System.String]
        $setupDir,

        [System.UInt32] $InstanceCount
    )

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


Export-ModuleMember -Function *-TargetResource

