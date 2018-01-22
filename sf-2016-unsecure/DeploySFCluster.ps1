﻿Configuration InstallServiceFabricConfiguration
{
    param
    (
    [Parameter(Mandatory = $false)]
    [Int] $DeploymentNodeIndex = 0,

    [Parameter(Mandatory = $true)]
    [int] $InstanceCount,

    [Parameter(Mandatory = $true)]
    [string] $ClusterName,

    [Parameter(Mandatory = $true)]
    [string] $vmNodeTypeName,

    [Parameter(Mandatory = $true)]
    [string] $clientConnectionEndpointPort,

    [Parameter(Mandatory = $true)]
    [string] $httpGatewayEndpointPort,

    [Parameter(Mandatory = $true)]
    [string] $reverseProxyEndpointPort,

    [Parameter(Mandatory = $true)]
    [string] $ephemeralStartPort,

    [Parameter(Mandatory = $true)]
    [string] $ephemeralEndPort,

    [Parameter(Mandatory = $true)]
    [string] $applicationStartPort,

    [Parameter(Mandatory = $true)]
    [string] $applicationEndPort,

    [Parameter(Mandatory = $true)]
    [string] $ConfigPath,

    [Parameter(Mandatory = $false)]
    [string] $serviceFabricUrl = "http://go.microsoft.com/fwlink/?LinkId=730690",

    [Parameter(Mandatory = $true)]
    [PSCredential] $Credential,

    [Parameter(Mandatory = $true)]
    [string] $DiagStoreAccountName,

    [Parameter(Mandatory = $true)]
    [string] $DiagStoreAccountKey,

    [Parameter(Mandatory = $true)]
    [string] $DiagStoreAccountBlobUri,

    [Parameter(Mandatory = $true)]
    [string] $DiagStoreAccountTableUri,

    [Parameter(Mandatory = $true)]
    [string] $clusterEndpoint
    )

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'

    Node localhost {
        Script InstallServiceFabric
        {
            GetScript = {
            }

            SetScript = 
            {
                $ErrorActionPreference = "Stop"

                # Enable File and Printer Sharing for Network Discovery (Port 445)
                Write-Verbose "Opening TCP firewall port 445 for networking."
                Set-NetFirewallRule -Name 'FPS-SMB-In-TCP' -Enabled True
                Get-NetFirewallRule -DisplayGroup 'Network Discovery' | Set-NetFirewallRule -Profile 'Private, Public' -Enabled true

                # Get the index of current node and match it with the index of required deployment node.
                $alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"

                $base36Num = $env:COMPUTERNAME.Substring(($using:vmNodeTypeName).Length)
                $inputarray = $base36Num.tolower().tochararray()
                [array]::reverse($inputarray)
                
                [long]$scaleSetDecimalIndex=0
                $pos=0

                foreach ($c in $inputarray)
                {
                    $scaleSetDecimalIndex += $alphabet.IndexOf($c) * [long][Math]::Pow(36, $pos)
                    $pos++
                }

                # Check if current Node is master node.
                $isMasterNode = $scaleSetDecimalIndex -eq $using:DeploymentNodeIndex

                # Check if Cluster already exists
                try
                {
                    Import-Module ServiceFabric -ErrorAction SilentlyContinue -Verbose:$false
                    $connection = Connect-ServiceFabricCluster -ConnectionEndpoint $clusterEndpoint    
                }
                catch
                {}    
                
                $clusterExists = $connection -and $connection[0]

                if($clusterExists)
                {
                    # Check if node exists in cluster
                    Write-Verbose "Service Fabric cluster already exists. Checking if '$($env:COMPUTERNAME)' already a member node."                         

                    $sfNodes = Get-ServiceFabricNode | % {$_.NodeName}
                        
                    if($sfNodes -contains $env:COMPUTERNAME)
                    {
                        Write-Verbose "Current node is already a part of the cluster. No action needed."
                        return
                    }

                    if(-not $isMasterNode)
                                                                                                                                                                                                                                                                                                                                                                                                                            {
                        # Add Node to the cluster.
                        Write-Verbose "Current node is not part of the cluster. Adding node: '$($env:COMPUTERNAME)'."                    
                    
                        # Collect Node details
                        $nodeName = $env:COMPUTERNAME
                        $nodeIpAddressLable = (Get-NetIPAddress).IPv4Address | ? {$_ -ne "" -and $_ -ne "127.0.0.1"}
                        $nodeIpAddress = [IPAddress](([String]$startNodeIpAddressLable).Trim(' '))
                        Write-Verbose "Node IPAddress: '$nodeIpAddress'"

                        $fdIndex = $scaleSetDecimalIndex + 1
                        $faultDomain = "fd:/dc$fdIndex/r0"

                        $upgradeDomain = "UD$scaleSetDecimalIndex"

                        # Download the Service fabric deployment package. Store setup files on Temp disk.
                        $setupDir = "D:\SFSetup"
				        New-Item -Path $setupDir -ItemType Directory -Force
				        cd $setupDir
                    
                        Write-Verbose "Downloading Service Fabric deployment package from: '$Using:serviceFabricUrl'"
				        Invoke-WebRequest -Uri $Using:serviceFabricUrl -OutFile (Join-Path -Path $setupDir -ChildPath ServiceFabric.zip) -UseBasicParsing
				        Expand-Archive (Join-Path -Path $setupDir -ChildPath ServiceFabric.zip) -DestinationPath (Join-Path -Path $setupDir -ChildPath ServiceFabric) -Force

                        # Get cluster health and wait for upgrade status to be completed. 

                        # Adding the Node
                        Write-Verbose "Adding node '$nodeName' to Service fabric Cluster."
				        $output = .\ServiceFabric\AddNode.ps1 -NodeName $nodeName `
                                                              -NodeType $using:vmNodeTypeName `
                                                              -NodeIPAddressorFQDN $nodeIpAddress `
                                                              -ExistingClientConnectionEndpoint $Using:clusterEndpoint `
                                                              -UpgradeDomain $upgradeDomain `
                                                              -FaultDomain $faultDomain `
                                                              -AcceptEULA

                        Write-Verbose ($output | Out-String)

                        # Validate add

                        $sfNodes = Get-ServiceFabricNode | % {$_.NodeName}
                        
                        if($sfNodes -contains $env:COMPUTERNAME)
                        {
                           Write-Verbose "Node '$nodeName' succesfully added to the Service Fabric cluster."
                        }
                        else
                        {
                            throw "Service fabric node '$nodeName' could not be added. `n Please check the detailed DSC logs and Service fabric deployment traces at: '$setupDir\ServiceFabric\DeploymentTraces' on the VM: '$nodeName'."
                        }
                    
                        # Update Configuration

                        $CofigFilePath = Join-Path -Path $setupDir -ChildPath 'ClusterConfig.json'
                        Write-Verbose "Get Service fabric configuration from Cluster."
                        $request = Get-ServiceFabricClusterConfiguration
                        $configContent = ConvertFrom-Json  $request

                        $node = New-Object PSObject 
					
					    $node | Add-Member -MemberType NoteProperty -Name "nodeName" -Value $($nodeName).ToString()
                        $node | Add-Member -MemberType NoteProperty -Name "iPAddress" -Value $nodeIpAddress
                        $node | Add-Member -MemberType NoteProperty -Name "nodeTypeRef" -Value "$using:vmNodeTypeName"
                        $node | Add-Member -MemberType NoteProperty -Name "faultDomain" -Value $faultDomain
                        $node | Add-Member -MemberType NoteProperty -Name "upgradeDomain" -Value $upgradeDomain

                        Write-Verbose "Adding Node to configuration: '$nodeName'"

                        $sfNodes = $configContent.Nodes
                        $sfnodes += $node

                        $configContent = ConvertTo-Json $configContent -Depth 99
				        Write-Verbose $configContent
                        Write-Verbose "Creating service fabric config file at: '$CofigFilePath'"
				        $configContent | Out-File $CofigFilePath
                    
                        Write-Verbose "Updating service fabric cluster configuration."
                        Start-ServiceFabricClusterConfigurationUpgrade -ClusterConfigPath $CofigFilePath

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
                    else
                    {
                        throw "Master Node '$env:COMPUTERNAME' dropped out of cluster."
                    }

                    return
                }

                # First time deployment in progress.

                if(-not $isMasterNode)
                {
                    # No cluster exists. Wait for initial deployment to complete.
                    Write-Verbose "Service Fabric deployment runs on Node with index: '$using:DeploymentNodeIndex'."
                    return
                }               

                Write-Verbose "Starting service fabric deployment on Node: '$env:COMPUTERNAME'."

                # Store setup files on Temp disk.
                $setupDir = "D:\SFSetup"
				New-Item -Path $setupDir -ItemType Directory -Force
				cd $setupDir
                $CofigFilePath = Join-Path -Path $setupDir -ChildPath 'ClusterConfig.json'
                
                Write-Verbose "Get Service fabric configuration from '$using:ConfigPath'"
				$request = Invoke-WebRequest $using:ConfigPath -UseBasicParsing
				$configContent = ConvertFrom-Json  $request.Content

                $configContent.name = "$using:ClusterName"

                $startNodeIpAddressLable = (Get-NetIPAddress).IPv4Address | ? {$_ -ne "" -and $_ -ne "127.0.0.1"}
                $startNodeIpAddress = [IPAddress](([String]$startNodeIpAddressLable).Trim(' '))                

                Write-Verbose "Start node IPAddress: '$startNodeIpAddress'"

				$i = 0
				$sfnodes = @()

				try
                {
                    Set-Item WSMan:\localhost\Client\TrustedHosts -Value * -Force

                    while($i -lt $using:InstanceCount)
                    {

					    $IpStartBytes = $startNodeIpAddress.GetAddressBytes()
					    $IpStartBytes[3] = $IpStartBytes[3] + $i
					    $ip = [IPAddress]($IpStartBytes)
                    
					    $nodeName = Invoke-Command -ScriptBlock {hostname} -ComputerName "$($ip.IPAddressToString)"
                        
                        $base36Num = $nodeName.ToString().Substring(($using:vmNodeTypeName).Length)
                        $inputarray = $base36Num.tolower().tochararray()
                        [array]::reverse($inputarray)
                
                        [long]$nodeScaleSetDecimalIndex=0
                        $pos=0

                        foreach ($c in $inputarray)
                        {
                            $nodeScaleSetDecimalIndex += $alphabet.IndexOf($c) * [long][Math]::Pow(36, $pos)
                            $pos++
                        }

                        $fdIndex = $nodeScaleSetDecimalIndex + 1

                        $node = New-Object PSObject 
					
					    $node | Add-Member -MemberType NoteProperty -Name "nodeName" -Value $($nodeName).ToString()
                        $node | Add-Member -MemberType NoteProperty -Name "iPAddress" -Value $ip.IPAddressToString
                        $node | Add-Member -MemberType NoteProperty -Name "nodeTypeRef" -Value "$using:vmNodeTypeName"
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

                Write-Verbose "Creating node type '$Using:vmNodeTypeName'"
                $nodeTypes =@()
                
                $nodeType = New-Object PSObject
                $nodeType | Add-Member -MemberType NoteProperty -Name "name" -Value "$Using:vmNodeTypeName"
                $nodeType | Add-Member -MemberType NoteProperty -Name "clientConnectionEndpointPort" -Value "$Using:clientConnectionEndpointPort"
                $nodeType | Add-Member -MemberType NoteProperty -Name "clusterConnectionEndpointPort" -Value "19001"
                $nodeType | Add-Member -MemberType NoteProperty -Name "leaseDriverEndpointPort" -Value "19002"
                $nodeType | Add-Member -MemberType NoteProperty -Name "serviceConnectionEndpointPort" -Value "19003"
                $nodeType | Add-Member -MemberType NoteProperty -Name "httpGatewayEndpointPort" -Value "$Using:httpGatewayEndpointPort"
                $nodeType | Add-Member -MemberType NoteProperty -Name "reverseProxyEndpointPort" -Value "$Using:reverseProxyEndpointPort"
                
                $applicationPorts = New-Object PSObject
                $applicationPorts | Add-Member -MemberType NoteProperty -Name "startPort" -Value "$Using:applicationStartPort"
                $applicationPorts | Add-Member -MemberType NoteProperty -Name "endPort" -Value "$Using:applicationEndPort"

                $ephemeralPorts = New-Object PSObject
                $ephemeralPorts | Add-Member -MemberType NoteProperty -Name "startPort" -Value "$Using:ephemeralStartPort"
                $ephemeralPorts | Add-Member -MemberType NoteProperty -Name "endPort" -Value "$Using:ephemeralEndPort"
                
                $nodeType | Add-Member -MemberType NoteProperty -Name "applicationPorts" -Value $applicationPorts
                $nodeType | Add-Member -MemberType NoteProperty -Name "ephemeralPorts" -Value $ephemeralPorts

                $nodeType | Add-Member -MemberType NoteProperty -Name "isPrimary" -Value $true

                Write-Verbose "Adding Node Type to configuration: '$Using:vmNodeTypeName'"
                $nodeTypes += $nodeType
                $configContent.properties.nodeTypes = $nodeTypes

                Write-Verbose "Creating diagnostics share at: '$Using:DiagStoreAccountName' blob store"

                $diagStoreConnectinString = "xstore:DefaultEndpointsProtocol=https;AccountName=$Using:DiagStoreAccountName;AccountKey=$Using:DiagStoreAccountKey;BlobEndpoint=$using:DiagStoreAccountBlobUri;TableEndpoint=$Using:DiagStoreAccountTableUri"

                Write-Verbose "Setting diagnostics store to: '$diagStoreConnectinString'"
                $configContent.properties.diagnosticsStore.connectionstring = $diagStoreConnectinString

				$configContent = ConvertTo-Json $configContent -Depth 99
				Write-Verbose $configContent
                Write-Verbose "Creating service fabric config file at: '$CofigFilePath'"
				$configContent | Out-File $CofigFilePath

                Write-Verbose "Downloading Service Fabric deployment package from: '$Using:serviceFabricUrl'"
				Invoke-WebRequest -Uri $Using:serviceFabricUrl -OutFile (Join-Path -Path $setupDir -ChildPath ServiceFabric.zip) -UseBasicParsing
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
                        $connection = Connect-ServiceFabricCluster -ConnectionEndpoint localhost:$Using:clientConnectionEndpointPort
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

            TestScript = {
               return $false
            }
            
            PsDscRunAsCredential = $Credential
        }
    }
}