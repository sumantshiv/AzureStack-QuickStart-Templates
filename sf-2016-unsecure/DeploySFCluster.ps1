param
(
    [String] $DeploymentNodeIndex
)

Function DeployServiceFabric
{
    $scaleSetIndex = $env:COMPUTERNAME.Substring($env:COMPUTERNAME.Length-1, 1)

    if($scaleSetIndex -eq $DeploymentNodeIndex)
    {
        $message = "I am the deployment node $env:COMPUTERNAME."
    }
    else
    {
        $message = "I am not the deployment node."
    }

    $message > "c:\ScriptOutput.txt"
}

DeployServiceFabric 

