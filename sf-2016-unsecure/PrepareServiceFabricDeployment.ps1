
# Enable File and Printer Sharing for Network Discovery (Port 445)
Set-NetFirewallRule -Name 'FPS-SMB-In-TCP' -Enabled True