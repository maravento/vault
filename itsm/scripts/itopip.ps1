<#

iTop - IT Service Management & CMDB - Config
by maravento.com

Description:
This script adds an IP address to the iTop configuration.
To run it, download the script, right click, run with PowerShell

#>

# Request elevation of privileges
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
        Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        Exit
    }
}

Write-Host "iTop Add IP"

# Request IP address
Write-Host ""
$ipAddress = Read-Host "Enter the IP address of the PC"

# Stack Menu
Write-Host ""
Write-Host "Select the stack you are using:"
Write-Host "1. WAMP"
Write-Host "2. XAMPP"
Write-Host "3. UZero"

# Capture stack selection
$stackSelection = Read-Host "Enter the stack number (1/2/3)"

# Determine path of config-itop.php file based on stack
switch ($stackSelection) {
    "1" { $configPath = "C:\wamp64\www\itop\web\conf\production\config-itop.php" }
    "2" { $configPath = "C:\xampp\htdocs\itop\web\conf\production\config-itop.php" }
    "3" { $configPath = "C:\UniServer\www\itop\web\conf\production\config-itop.php" }
    default { 
        Write-Host "Invalid option"
        pause
        exit 
    }
}

# Verify that the file exists
if (-not (Test-Path $configPath)) {
    Write-Host "Error: The file config-itop.php could not be found at the specified path."
    pause
    exit
}

# Save original permissions
$originalAttributes = (Get-Item $configPath).Attributes

# Remove read-only attribute
Set-ItemProperty $configPath -Name Attributes -Value ((Get-ItemProperty $configPath).Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly))

# Leer contenido del archivo
$configContent = Get-Content $configPath

# Read file content
$newConfigContent = $configContent | ForEach-Object {
    if ($_ -match "'app_root_url' =>") {
        return "'app_root_url' => (isset(`$_SERVER['REMOTE_ADDR']) && `$_SERVER['REMOTE_ADDR'] == '127.0.0.1') " +
               "? 'http://localhost/itop/web/' " +
               ": 'http://$ipAddress/itop/web/',"
    }
    return $_
}

# Save changes
$newConfigContent | Set-Content $configPath

# restore original attributes (return to read-only)
Set-ItemProperty $configPath -Name Attributes -Value $originalAttributes

# confirmation message
Write-Host ""
Write-Host "Configuration modified successfully."
Write-Host "File path: $configPath"
Write-Host "New IP configured: $ipAddress"
Write-Host ""
Read-Host "Press any key to finish"
