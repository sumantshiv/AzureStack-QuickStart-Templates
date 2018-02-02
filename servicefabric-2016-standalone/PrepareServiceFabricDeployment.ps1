
# Enable File and Printer Sharing for Network Discovery (Port 445)
Write-Verbose "Opening TCP firewall port 445 for networking."
Set-NetFirewallRule -Name 'FPS-SMB-In-TCP' -Enabled True
Get-NetFirewallRule -DisplayGroup 'Network Discovery' | Set-NetFirewallRule -Profile 'Private, Public' -Enabled true