param
(
    [String] $DeploymentNode
)

Function DeployServiceFabric
{

    if($env:COMPUTERNAME -eq $DeploymentNode)
    {
        $message = "I am the deployment node $DeploymentNode."
    }
    else
    {
        $message = "I am not the deployment node. It should be $DeploymentNode"
    }

    $message > "c:\ScriptOutput.txt"
}

DeployServiceFabric 

