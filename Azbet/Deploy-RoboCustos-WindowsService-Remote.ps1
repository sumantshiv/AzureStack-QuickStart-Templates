# Script to run locally on a machine given the uri to the zip package
# containing the RoboCustosWindows service package.
# This script is intended to be run via powershell remoting on an AWS VM
# initiated from dev machine via other scripts.

Param (     
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $PackageUrl,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $AzBetTargetUrl,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $DeploymentEnvironmentName
)

$ErrorActionPreference = "Stop"

Function Ensure-ServiceCreated($serviceName, $commandLine) {
    Write-Host -NoNewline "Checking for service... "
    if (-Not (Get-Service $serviceName -ErrorAction SilentlyContinue))
    {
        Write-Host -NoNewline "Does not exist, creating... "
        New-Service -Name $serviceName -BinaryPathName $commandLine -StartupType Automatic
        Write-Host "Created."
    }
    Write-Host "Already exists."
}

Function Stop-ServiceIfRunning($serviceName) {
    $svc = Get-Service "$serviceName"
    if ($svc.Status -ne "Stopped")
    {
        Write-Host -NoNewline "Stopping service $serviceName... "
        # service is either running or stopping or whatever
        # so stop it and wait for it to stop up to a limit of 10 mins

	try
	{
        	$svc.Stop()
	        $svc.WaitForStatus('Stopped', '00:2:00')
	}
	catch
	{
		Write-Host $_
	}
        if ($svc.Status -ne 'Stopped')
        {
            Write-Host "Stop timed out, killing process... "
            # We have to stop it so let's try killing the process...
            $id = gwmi Win32_Service | ?{$_.Name -eq "$serviceName"} | select -ExpandProperty ProcessId
            Stop-Process -Id $id -Force
        }
    }
    Write-Host "Stopped."
}

Function Start-RoboService($serviceName) {
    Write-Host -NoNewline "Starting service $serviceName ... "
    Start-Service "$serviceName"
    Write-Host "Started."
}

Function Remove-OldInstallation($installDirectory) {
    if (Test-Path $installDirectory)
    {
        $retryCount = 0
        $done = $false

        Write-Host -NoNewline "Removing old installation... "
        while (-not $done)
        {
            try
            {
                Remove-Item -Recurse -Force $installDirectory
                $done = $true;
            }
            catch
            {
                if ($retryCount++ -le 10)
                {
                    Write-Host -ForegroundColor Yellow "error deleting directory, trying again after 5 seconds"
                    Sleep 5
                }
                else
                {
                    throw
                }
            }
        }
        Write-Host "Done."
    }
}

Function Ensure-DirectoryExists($directory) {
    New-Item -Type directory $directory -Force
}

Function Fetch-NewVersion($PackageUrl, $DestinationDirectory, $TargetUrl, $DeploymentEnvironmentName) {
    Write-Host -NoNewline "Fetching package ($PackageUrl)... "
    $LocalDirName = ((Get-Date).ToUniversalTime()).ToString("yyyy-MM-dd-hh-mm-ss")
    $TempDir = "$env:tmp\$LocalDirName"
    New-Item -Type directory $TempDir
    pushd $TempDir
    $Filename = "package.zip"
    Invoke-WebRequest $PackageUrl -OutFile package.zip
    Write-Host "Fetched."
    Write-Host -NoNewline "Extracting... "
    # Decompress the zip file to the target directory
    Add-Type -Assembly System.IO.Compression.FileSystem
    $Archive = [System.IO.Compression.ZipFile]::ExtractToDirectory((Get-Location).Path + "\$Filename", $DestinationDirectory )
    [xml]$configXml = [Xml] (Get-Content $DestinationDirectory\RoboCustosWindowsService.exe.config)
    $urlNode = $configXml.configuration.appSettings.ChildNodes | Where { $_.key -eq "TargetAzBetUrl"}
    $urlNode.SetAttribute("value", $TargetUrl)
    $environmentNode = $configXml.configuration.appSettings.ChildNodes | Where { $_.key -eq "TargetEnvironment"}
    $environmentNode.SetAttribute("value", $DeploymentEnvironmentName)
    $configXml.Save("$DestinationDirectory\RoboCustosWindowsService.exe.config")
    Write-Host "Extracted."
}

$ServiceDirectory = "$env:SystemDrive\RoboCustos"
$ServiceName = 'RoboCustos'
Ensure-ServiceCreated $ServiceName "$ServiceDirectory\RoboCustosWindowsService.exe"
Stop-ServiceIfRunning $ServiceName
Remove-OldInstallation $ServiceDirectory
Ensure-DirectoryExists  $ServiceDirectory
Fetch-NewVersion $PackageUrl $ServiceDirectory $AzBetTargetUrl $DeploymentEnvironmentName
Start-RoboService $ServiceName
