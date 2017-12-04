Configuration InstallServiceFabricConfiguration
{
    param
    (
    [Parameter(Mandatory = $false)]
    [String] $DeploymentNodeIndex = "0",

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
    [string] $applicationStartPort,

    [Parameter(Mandatory = $true)]
    [string] $applicationEndPort,

    [Parameter(Mandatory = $true)]
    [string] $ConfigPath,

    [Parameter(Mandatory = $true)]
    [PSCredential] $Credential,

    [Parameter(Mandatory = $true)]
    [PSCredential] $DiagStoreAccountName,

    [Parameter(Mandatory = $true)]
    [PSCredential] $DiagStoreAccountKey
    )

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'

    Node localhost {
        Script InstallServiceFabric
        {
            GetScript = {
            }

            SetScript = 
            {
                # Enable File and Printer Sharing for Network Discovery
                Set-NetFirewallRule -Name 'FPS-SMB-In-TCP' -Enabled True

                # Get the index of current node and match it with the index of required deployment node.
                $scaleSetIndex = $env:COMPUTERNAME.Substring($env:COMPUTERNAME.Length-1, 1)

                $nodeNamePrefix = $env:COMPUTERNAME.Substring(0,$env:COMPUTERNAME.Length-1)

                # Return in case the current node is not the deployment node, else continue with SF deployment.
                if($scaleSetIndex -ne $using:DeploymentNodeIndex)
                {
                    Write-Verbose "Service Fabric deployment runs on Node with index: '$using:DeploymentNodeIndex'."
                    return
                }

                Write-Verbose "Starting service fabric deployment on Node: '$env:COMPUTERNAME'."

                $setupDir = "C:\SFSetup"
				New-Item -Path $setupDir -ItemType Directory -Force
				cd $setupDir
                $serviceFabricUrl = "http://go.microsoft.com/fwlink/?LinkId=730690"

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
				while($i -lt $using:InstanceCount){

					$IpStartBytes = $startNodeIpAddress.GetAddressBytes()
					$IpStartBytes[3] = $IpStartBytes[3] + $i
					$ip = [IPAddress]($IpStartBytes)
					
                    $fdIndex = $i + 1 
                    
					$nodeName = "$nodeNamePrefix" + "$i"
					$node = New-Object PSObject 
					
					$node | Add-Member -MemberType NoteProperty -Name "nodeName" -Value $nodeName
                    $node | Add-Member -MemberType NoteProperty -Name "iPAddress" -Value $ip.IPAddressToString
                    $node | Add-Member -MemberType NoteProperty -Name "nodeTypeRef" -Value "$using:vmNodeTypeName"
                    $node | Add-Member -MemberType NoteProperty -Name "faultDomain" -Value "fd:/dc$fdIndex/r0"
                    $node | Add-Member -MemberType NoteProperty -Name "upgradeDomain" -Value "UD$i"

                    Write-Verbose "Adding Node to configuration: '$nodeName'"
					$sfnodes += $node
					$i++
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
                
                $nodeType | Add-Member -MemberType NoteProperty -Name "applicationPorts" -Value $applicationPorts

                $nodeType | Add-Member -MemberType NoteProperty -Name "isPrimary" -Value $true

                Write-Verbose "Adding Node Type to configuration: '$Using:vmNodeTypeName'"
                $nodeTypes += $nodeType
                $configContent.properties.nodeTypes = $nodeTypes
                                
                $smbShareLocalPath = "C:\DiagnosticsStore"
                $smbSharePath = "\\$startNodeIpAddress\DiagnosticsStore"

                Write-Verbose "Creating diagnostics share at: '$smbShareLocalPath'"

                $diagStoreConnectinString = "xstore:DefaultEndpointsProtocol=https;AccountName=$DiagStoreAccountName;AccountKey=$DiagStoreAccountKey"

                Write-Verbose "Setting diagnostics store to: '$diagStoreConnectinString'"
                $configContent.properties.diagnosticsStore.connectionstring = $diagStoreConnectinString

				$configContent = ConvertTo-Json $configContent -Depth 99
				Write-Verbose $configContent
                Write-Verbose "Creating service fabric config file at: '$CofigFilePath'"
				$configContent | Out-File $CofigFilePath

                Write-Verbose "Downloading Service Fabric runtime from: '$serviceFabricUrl'"
				Invoke-WebRequest -Uri $serviceFabricUrl -OutFile (Join-Path -Path $setupDir -ChildPath ServiceFabric.zip) -UseBasicParsing
				Expand-Archive (Join-Path -Path $setupDir -ChildPath ServiceFabric.zip) -DestinationPath (Join-Path -Path $setupDir -ChildPath ServiceFabric) -Force
                
                Write-Verbose "Starting Service Fabric runtime deployment"
				$output = .\ServiceFabric\CreateServiceFabricCluster.ps1 -ClusterConfigFilePath $CofigFilePath -AcceptEULA
                Write-Verbose "Service Fabric runtime deployment completed."
            }

            TestScript = {
               return $false
            }
            
            PsDscRunAsCredential = $Credential
        }
    }
}