<#

iTop - IT Service Management & CMDB - Config
by maravento.com

Description:
This script will allow access to iTop, by IP/Port.
It is intended for use with Wampserver, Xampp, and Uniserver Zero only.

How To Run:
- For Windows 10/11: Right-click on the script and select **"Run with PowerShell"**.
- In case it fail do the following:
    1. Open **Windows PowerShell** as **Administrator**.
    2. Run the following command to allow script execution:
       ```powershell
       Set-ExecutionPolicy Unrestricted -Scope CurrentUser -Force
       ```
    3. Now run the script `itopconf.ps1`.
    4. Once the script has finished, restore the execution policy to a more secure setting by running:
       ```powershell
       Set-ExecutionPolicy Restricted -Scope CurrentUser -Force
       ```
#>

# Request elevation of privileges
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
        Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        Exit
    }
}

# Function to create backup
function Create-Backup {
    param (
        [string]$configPath
    )
    
    $backupPath = $configPath + ".backup"
    Copy-Item -Path $configPath -Destination $backupPath -Force
    Write-Host "Backup created at: $backupPath"
}

# Paths to check for the config file
$configPaths = @(
    "$env:HOMEDRIVE\wamp64\www\itop\web\conf\production\config-itop.php",
    "$env:HOMEDRIVE\xampp\htdocs\itop\web\conf\production\config-itop.php",
    "$env:HOMEDRIVE\UniServer\www\itop\web\conf\production\config-itop.php"
)

# Iterate through paths and create backup if the file exists
foreach ($path in $configPaths) {
    if (Test-Path $path) {
        Create-Backup -configPath $path
        break # Exit the loop after the first valid backup
    }
}

# Function to get the configuration path based on stack selection
function Get-ConfigPath {
    param (
        [string]$stackSelection
    )

    switch ($stackSelection) {
        "1" { return "$env:HOMEDRIVE\wamp64\www\itop\web\conf\production\config-itop.php" }
        "2" { return "$env:HOMEDRIVE\xampp\htdocs\itop\web\conf\production\config-itop.php" }
        "3" { return "$env:HOMEDRIVE\UniServer\www\itop\web\conf\production\config-itop.php" }
        default { 
            Write-Host "Invalid option"
            pause
            exit
        }
    }
}

Clear-Host
Write-Host
Write-Host "iTop Config Manager"

# Main Menu
Write-Host ""
Write-Host "1. Enable Auto-Detection of Host (localhost/IP/Port)"
Write-Host "2. Restore from Backup"
Write-Host "3. Exit"
$choice = Read-Host "`nSelect an option (1-3)"

switch ($choice) {
	"1" {
		Write-Host ""
		Write-Host "Select the stack you are using:"
		Write-Host "1. WAMP"
		Write-Host "2. XAMPP"
		Write-Host "3. UZero"
		$stackSelection = Read-Host "Enter the stack number (1/2/3)"

		# Get the configuration path
		$configPath = Get-ConfigPath -stackSelection $stackSelection

		if (-not (Test-Path $configPath)) {
			Write-Host "Error: The file config-itop.php could not be found at the specified path."
			pause
			exit
		}

		$originalAttributes = (Get-Item $configPath).Attributes
		Set-ItemProperty $configPath -Name Attributes -Value ((Get-ItemProperty $configPath).Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly))

		# insert and replace lines
		$configContent = Get-Content $configPath
		$newLine = '$base_url = $_SERVER["REQUEST_SCHEME"] . "://" . $_SERVER["SERVER_NAME"] . (($_SERVER["SERVER_PORT"] ?? "80") != "80" ? ":" . $_SERVER["SERVER_PORT"] : "");'
		$configContent = $configContent[0], $newLine, $configContent[1..($configContent.Count - 1)]
		$configContent | Set-Content $configPath

		$configContent = Get-Content $configPath
		$newConfigContent = $configContent | ForEach-Object {
			if ($_ -match "'app_root_url' =>") {
				# Construye la cadena de forma explícita
				$newLine = "'app_root_url' => " + "`$base_url" + " . '/itop/web/',"
				return $newLine
			}
			return $_
		}
		$newConfigContent | Set-Content $configPath
		
		# Restored attributes 
		Set-ItemProperty -Path $configPath -Name Attributes -Value $originalAttributes

		Write-Host ""
		Write-Host "Configuration modified successfully."
		Write-Host "File path: $configPath"

		# Modifying httpd-vhosts.conf for the selected stack
		if ($stackSelection -eq 1) {
			# Detectar la versión de Apache en WAMP con mejor logging
			$wampPath = Join-Path $env:HOMEDRIVE "wamp64"
			$apachePath = Join-Path $wampPath "bin\apache"
			
			Write-Host "Checking WAMP path: $wampPath"
			Write-Host "Checking Apache path: $apachePath"
			
			if (Test-Path $apachePath) {
				Write-Host "Apache directory found. Searching for Apache versions..."
				
				# List all directories in Apache path
				$apacheDirs = Get-ChildItem -Path $apachePath -Directory
				Write-Host "Found directories: $($apacheDirs.Name -join ', ')"
				
				# Find folders that match the pattern apache2.x.x
				$apacheVersions = $apacheDirs | 
					Where-Object { $_.Name -match "apache2\.(\d+\.\d+)" } |
					ForEach-Object {
						Write-Host "Processing directory: $($_.Name)"
						$version = if ($_.Name -match "apache2\.(\d+\.\d+)") {
							$matches[1]
						} else {
							"0.0"
						}
						[PSCustomObject]@{
							Folder = $_.Name
							Version = [version]$version
						}
					} | Sort-Object Version -Descending
				
				if ($apacheVersions.Count -gt 0) {
					$latestApache = $apacheVersions[0]
					$vhostsPath = Join-Path $apachePath ($latestApache.Folder + "\conf\extra\httpd-vhosts.conf")
					Write-Host "Latest Apache version found: $($latestApache.Version)"
					Write-Host "Using vhosts path: $vhostsPath"
				} else {
					# If it can't find it using the above method, try searching directly
					$possibleApacheDirs = Get-ChildItem -Path $apachePath -Directory -Filter "apache*"
					if ($possibleApacheDirs.Count -gt 0) {
						$latestApache = $possibleApacheDirs | Sort-Object Name -Descending | Select-Object -First 1
						$vhostsPath = Join-Path $apachePath ($latestApache.Name + "\conf\extra\httpd-vhosts.conf")
						Write-Host "Found Apache directory using alternative method: $($latestApache.Name)"
						Write-Host "Using vhosts path: $vhostsPath"
					} else {
						Write-Host "Error: No Apache directories found in $apachePath"
						Write-Host "Directories Found: $((Get-ChildItem -Path $apachePath).Name -join ', ')"
						pause
						exit
					}
				}
			} else {
				Write-Host "Error: Apache directory not found at $apachePath"
				Write-Host "Checking if it exists WAMP64: $(Test-Path $wampPath)"
				pause
				exit
			}
		} elseif ($stackSelection -eq 2) {
			$vhostsPath = Join-Path $env:HOMEDRIVE "xampp\apache\conf\extra\httpd-vhosts.conf"
		} elseif ($stackSelection -eq 3) {
			$vhostsPath = Join-Path $env:HOMEDRIVE "UniServerZ\core\apache2\conf\extra\httpd-vhosts.conf"
		}

		# Modify the corresponding vhosts file
		if (Test-Path $vhostsPath) {
			$vhostsContent = Get-Content $vhostsPath
			$vhostsContentModified = $vhostsContent | ForEach-Object {
				if ($_ -match "Require local") {
					return $_ -replace "Require local", "Require all granted"
				}
				return $_
			}
			$vhostsContentModified | Set-Content $vhostsPath
			Write-Host "File modified: $vhostsPath"
		} else {
			Write-Host "File not found: $vhostsPath"
		}
	Write-Host "vhosts updated successfully."
	}
    
    "2" {
        # Restore from Backup
        Write-Host ""
        Write-Host "Select the stack you are using:"
        Write-Host "1. WAMP"
        Write-Host "2. XAMPP"
        Write-Host "3. UZero"

        $stackSelection = Read-Host "Enter the stack number (1/2/3)"

		# Get the configuration path
		$configPath = Get-ConfigPath -stackSelection $stackSelection

        $backupPath = $configPath + ".backup"
        
        if (-not (Test-Path $backupPath)) {
            Write-Host "Error: No backup file found at: $backupPath"
            pause
            exit
        }

        $originalAttributes = (Get-Item $configPath).Attributes
        Set-ItemProperty $configPath -Name Attributes -Value ((Get-ItemProperty $configPath).Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly))

        Copy-Item -Path $backupPath -Destination $configPath -Force
        Set-ItemProperty $configPath -Name Attributes -Value $originalAttributes

        Write-Host "`nConfiguration restored from backup successfully"
    }
    
    "3" {
        Write-Host "`nExiting..."
        exit
    }
    
    default {
        Write-Host "`nInvalid option. Please try again."
        pause
        exit
    }
}

Write-Host ""
Read-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
