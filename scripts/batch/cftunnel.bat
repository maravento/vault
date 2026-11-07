@echo off
:: maravento.com
:: Cloudflare Tunnel Service Manager (cftunnel)
:: FILE: cftunnel.bat
:: For Windows 10/11 only
:: Creates, starts, stops, checks and deletes locally managed Cloudflare Tunnels.
:: Usage: cftunnel.bat [--create|--start|--startall|--stop|--status|--delete]
:: Dependencies: Windows PowerShell 5.1 and cloudflared.exe in PATH.
:: Run as the normal user. Administrator privileges are not required.
:: Autostart: current user's HKCU Run entry, executed at sign-in.
:: Configuration, credentials and logs: %USERPROFILE%\.cloudflared
:: Log: preflight.log, cleared at startup; one cloudflared log per tunnel.
:: Uses embedded PowerShell, like other vault batch scripts. No external PS1 file.

setlocal DisableDelayedExpansion
set "CFTUNNEL_SELF=%~f0"
set "CFTUNNEL_ACTION=%~1"
if not "%~2"=="" (
    echo ERROR: Expected a single action -abort 1>&2
    exit /b 1
)
set "CFTUNNEL_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%CFTUNNEL_PS%" (
    echo ERROR: Windows PowerShell is not installed -abort 1>&2
    exit /b 1
)
"%CFTUNNEL_PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$text=[IO.File]::ReadAllText($env:CFTUNNEL_SELF); $marker='# CFTUNNEL_POWERSHELL'; $offset=$text.LastIndexOf($marker); if($offset -lt 0){exit 1}; & ([scriptblock]::Create($text.Substring($offset+$marker.Length)))"
exit /b %errorlevel%

# CFTUNNEL_POWERSHELL
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# ------------------------------------------------------------------------------
# CONFIG
# ------------------------------------------------------------------------------

# Optional API token: Zone:Read and DNS:Edit, restricted to the relevant zones.
# Leave empty to remove DNS records manually from the Cloudflare dashboard.
$token_cloudflare = ''

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

function Log([string]$Message) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    if ($script:log_file) { Add-Content -LiteralPath $script:log_file -Value $line -Encoding UTF8 }
    if ($Message.StartsWith('ERROR:')) { [Console]::Error.WriteLine($line) }
    else { Write-Host $line }
}

function Ask([string]$Prompt, [string]$Default = '') {
    $answer = Read-Host "$Prompt [$Default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}

function Confirm([string]$Prompt, [string]$Hint = '(y/n)') { return (Read-Host "$Prompt $Hint").Trim() -ieq 'y' }

function Run-Cloudflared([string[]]$Arguments) {
    & $script:cloudflared @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "cloudflared failed (exit $LASTEXITCODE)" }
}

function Get-Tunnels {
    return @(Get-ChildItem -LiteralPath $script:config_dir -Filter '*.yml' -File |
        Sort-Object Name | Select-Object -ExpandProperty BaseName)
}

function Require-Tunnels {
    $names = @(Get-Tunnels)
    if ($names.Count -eq 0) { throw "No tunnel configurations found in $script:config_dir" }
    return $names
}

function Config-Path([string]$Name) { return Join-Path $script:config_dir "$Name.yml" }
function Pid-Path([string]$Name) { return Join-Path $script:config_dir "$Name.pid" }

function Get-TunnelId([string]$Name) {
    $line = Get-Content -LiteralPath (Config-Path $Name) |
        Where-Object { $_ -match '^tunnel:\s*' } | Select-Object -First 1
    if (!$line -or $line -notmatch '^tunnel:\s*["'']?([0-9a-fA-F-]{36})["'']?\s*$') {
        throw "Missing or invalid tunnel ID in $(Config-Path $Name)"
    }
    $id = [guid]::Parse($Matches[1]).ToString()
    return $id
}

function Get-TunnelProcess([string]$Name) {
    $file = Pid-Path $Name
    if (!(Test-Path -LiteralPath $file)) { return $null }
    try { $record = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json }
    catch { throw "Invalid process record: $file" }
    $process_id = 0
    if (![int]::TryParse([string]$record.ProcessId, [ref]$process_id) -or $process_id -le 0) {
        throw "Invalid process ID in $file"
    }
    $process = Get-CimInstance Win32_Process -Filter "ProcessId=$process_id"
    if (!$process) { return $null }
    $config = Config-Path $Name
    $pattern = '(?i)(?:^|\s)--config\s+"' + [regex]::Escape($config) + '"(?:\s|$)'
    if ($process.ExecutablePath -ine $script:cloudflared -or
        $process.CommandLine -notmatch $pattern -or
        $process.CreationDate.ToUniversalTime().Ticks.ToString() -ne [string]$record.Created) {
        return $null
    }
    return $process
}

function Stop-Tunnel([string]$Name) {
    $process = Get-TunnelProcess $Name
    if ($process) {
        # Recheck executable, config and creation time immediately before termination.
        $verified = Get-TunnelProcess $Name
        if ($verified) {
            $result = Invoke-CimMethod -InputObject $verified -MethodName Terminate
            if ($result.ReturnValue -ne 0) { throw "Cannot stop tunnel '$Name': $($result.ReturnValue)" }
            for ($i=0; $i -lt 10; $i++) {
                if (!(Get-TunnelProcess $Name)) { break }
                Start-Sleep -Seconds 1
            }
            if (Get-TunnelProcess $Name) { throw "Tunnel '$Name' did not stop" }
        }
    }
    if (Test-Path -LiteralPath (Pid-Path $Name)) { Remove-Item -LiteralPath (Pid-Path $Name) }
    Log "INFO: tunnel '$Name' stopped"
}

function Start-Tunnel([string]$Name, [bool]$Interactive = $true) {
    $existing = Get-TunnelProcess $Name
    if ($existing) {
        if (!$Interactive) { return }
        if (!(Confirm "Restart tunnel '$Name'?")) { return }
        Stop-Tunnel $Name
    }
    $id = Get-TunnelId $Name
    $config = Config-Path $Name
    $credentials = Join-Path $script:config_dir "$id.json"
    if (!(Test-Path -LiteralPath $credentials -PathType Leaf)) { throw "Missing credentials: $credentials" }
    $log = Join-Path $script:config_dir "$Name.log"
    $arguments = '--config "{0}" --logfile "{1}" tunnel run {2}' -f $config, $log, $id
    $child = Start-Process -FilePath $script:cloudflared -ArgumentList $arguments -WindowStyle Hidden -PassThru
    try {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($child.Id)"
        if (!$process) { throw "Tunnel '$Name' exited; inspect $log" }
        $record = @{ ProcessId=$child.Id; Created=$process.CreationDate.ToUniversalTime().Ticks.ToString() }
        $record | ConvertTo-Json -Compress | Set-Content -LiteralPath (Pid-Path $Name) -Encoding UTF8
    } catch {
        if (!$child.HasExited) { $child.Kill() }
        throw
    }
    Start-Sleep -Seconds 2
    if (!(Get-TunnelProcess $Name)) {
        Remove-Item -LiteralPath (Pid-Path $Name) -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 20 | Out-Host }
        throw "Tunnel '$Name' exited; inspect $log"
    }
    Log "INFO: tunnel '$Name' process started (PID $($child.Id))"
}

function Preflight {
    $ready = $false
    for ($i=1; $i -le 24; $i++) {
        $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' })
        if ($addresses.Count -gt 0) { $ready=$true; break }
        if ($i -eq 1) { Log 'INFO: waiting for an interface with IPv4...' }
        Start-Sleep -Seconds 5
    }
    if (!$ready) { throw 'No interface with IPv4' }
    for ($i=1; $i -le 10; $i++) {
        try {
            $null = [Net.Dns]::GetHostAddresses('cloudflare.com')
            foreach ($uri in @('https://www.cloudflare.com/cdn-cgi/trace','https://api.cloudflare.com/cdn-cgi/trace')) {
                $null = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 5
            }
            return
        } catch {
            Log "WARNING: preflight $i/10 failed: $($_.Exception.Message) -alert"
            if ($i -lt 10) { Start-Sleep -Seconds 5 }
        }
    }
    throw 'Preflight failed after 10 attempts'
}

function Create-Tunnel {
    Preflight
    if (!(Test-Path -LiteralPath (Join-Path $script:config_dir 'cert.pem'))) {
        if (!(Confirm "Run 'cloudflared tunnel login' now?")) { return }
        Run-Cloudflared @('tunnel','login')
        if (!(Test-Path -LiteralPath (Join-Path $script:config_dir 'cert.pem'))) { throw 'Login did not create cert.pem' }
    }
    $name = Ask 'Tunnel name (empty cancels)'
    if (!$name) { return }
    # Use a single Windows filename component; reject reserved device names.
    if ($name -match '[<>:"/\\|?*\x00-\x1f]' -or $name.EndsWith('.') -or
        $name -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' -or $name.StartsWith('-')) {
        throw 'Invalid tunnel name for Windows'
    }
    $config = Config-Path $name
    if (Test-Path -LiteralPath $config) { throw "Configuration already exists: $config" }
    $hostname = Ask 'Public hostname (e.g. sub.domain.com)'
    if (!$hostname) { return }
    if ($hostname -notmatch '^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$') {
        throw 'Invalid public hostname'
    }
    $type = Ask 'Service type (e.g. http, https or tcp)' 'http'
    if ($type -cnotin @('http','https','tcp')) { throw 'Invalid service type' }
    $ip = Ask 'Local service IPv4 (e.g. 127.0.0.1)' '127.0.0.1'
    $octet = '(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])'
    if ($ip -notmatch "^$octet\.$octet\.$octet\.$octet`$") { throw 'Invalid IPv4 address' }
    $port_text = Ask 'Local service port (e.g. 8080)'
    if (!$port_text) { return }
    if ($port_text -notmatch '^[1-9][0-9]{0,4}$' -or [int]$port_text -gt 65535) { throw 'Invalid port' }
    $skip_tls = $false
    if ($type -eq 'https') { $skip_tls = Confirm 'Origin uses a self-signed certificate?' '[y/N]' }
    Run-Cloudflared @('tunnel','create',$name)
    $json = & $script:cloudflared tunnel list --output json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot list tunnels after creation' }
    $tunnels = @(($json -join "`n" | ConvertFrom-Json) | Where-Object { $_.name -ceq $name })
    if ($tunnels.Count -ne 1) { throw 'Cannot identify created tunnel; inspect cloudflared tunnel list' }
    $id = [guid]::Parse($tunnels[0].id).ToString()
    $credentials = Join-Path $script:config_dir "$id.json"
    if (!(Test-Path -LiteralPath $credentials)) { throw "Missing credentials: $credentials" }
    $yaml = @("tunnel: $id", "credentials-file: '$($credentials.Replace("'","''"))'", '', 'ingress:',
        "  - hostname: $hostname", "    service: ${type}://${ip}:$port_text")
    if ($skip_tls) { $yaml += @('    originRequest:', '      noTLSVerify: true') }
    $yaml += '  - service: http_status:404'
    [IO.File]::WriteAllLines($config, $yaml, (New-Object Text.UTF8Encoding($false)))
    if (Confirm "Route DNS '$hostname' to this tunnel now?") { Run-Cloudflared @('tunnel','route','dns',$name,$hostname) }
    if (Confirm "Start tunnel '$name' now?") { Start-Tunnel $name }
}

function Remove-Dns([string]$Name) {
    $line = Get-Content -LiteralPath (Config-Path $Name) |
        Where-Object { $_ -match '^\s*-\s*hostname:' } | Select-Object -First 1
    if (!$line) { Log 'WARNING: no hostname found; remove DNS manually -alert'; return }
    $hostname = ($line -replace '^\s*-\s*hostname:\s*','').Trim().Trim([char[]]@('"', "'"))
    if (!$script:token_cloudflare) { Log "WARNING: remove DNS for '$hostname' manually; token_cloudflare is empty -alert"; return }
    try {
        $base = 'https://api.cloudflare.com/client/v4'
        $headers = @{ Authorization="Bearer $script:token_cloudflare" }
        $zones = @()
        $page = 1
        do {
            $response = Invoke-RestMethod -Uri "$base/zones?per_page=50&page=$page" -Headers $headers -TimeoutSec 15
            if (!$response.success) { throw 'Cloudflare rejected zone lookup' }
            $zones += @($response.result)
            $page++
        } while ($page -le $response.result_info.total_pages)
        $zone = $zones | Where-Object { $hostname -ieq $_.name -or $hostname.EndsWith('.'+$_.name, [StringComparison]::OrdinalIgnoreCase) } |
            Sort-Object { $_.name.Length } -Descending | Select-Object -First 1
        if (!$zone) { throw 'No matching accessible zone' }
        $id = Get-TunnelId $Name
        $uri = "$base/zones/$($zone.id)/dns_records?type=CNAME&name=$([uri]::EscapeDataString($hostname))"
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 15
        if (!$response.success) { throw 'Cloudflare rejected DNS lookup' }
        foreach ($record in @($response.result)) {
            if ($record.content.TrimEnd('.') -ine "$id.cfargotunnel.com") { continue }
            $response = Invoke-RestMethod -Method Delete -Uri "$base/zones/$($zone.id)/dns_records/$($record.id)" -Headers $headers -TimeoutSec 15
            if (!$response.success) { throw 'Cloudflare rejected DNS deletion' }
        }
    } catch { Log "WARNING: DNS deletion incomplete; remove '$hostname' manually: $($_.Exception.Message) -alert" }
}

function Delete-Tunnel {
    Preflight
    $names = @(Require-Tunnels)
    for ($i=0; $i -lt $names.Count; $i++) { Write-Host ('{0}. {1}' -f ($i+1), $names[$i]) }
    $selection = Ask 'Tunnel name or number (empty cancels)'
    if (!$selection) { return }
    $number = 0
    if ([int]::TryParse($selection, [ref]$number)) {
        if ($number -lt 1 -or $number -gt $names.Count) { throw 'Invalid selection' }
        $selection = $names[$number-1]
    }
    if ($names -cnotcontains $selection) { throw 'Unknown tunnel' }
    if (!(Confirm "Permanently delete tunnel '$selection' from Cloudflare and this computer?")) { return }
    $id = Get-TunnelId $selection
    Stop-Tunnel $selection
    & $script:cloudflared tunnel delete $id | Out-Host
    if ($LASTEXITCODE -ne 0) { Run-Cloudflared @('tunnel','delete','-f',$id) }
    Remove-Dns $selection
    foreach ($file in @((Config-Path $selection), (Pid-Path $selection),
        (Join-Path $script:config_dir "$selection.log"), (Join-Path $script:config_dir "$id.json"))) {
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
    }
    Log "INFO: tunnel '$selection' deleted"
}

function Set-Autostart([bool]$Enable) {
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $name = 'cftunnel'
    $command = '"{0}" /d /v:off /c ""{1}" --startall"' -f $env:ComSpec, $env:CFTUNNEL_SELF
    $property = Get-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue
    if ($property -and $property.$name -cne $command) { throw 'Another cftunnel autostart entry exists; keep the original script path' }
    if ($Enable) {
        # Windows limits Run command lines to 260 characters.
        if ($command.Length -gt 260 -or $env:CFTUNNEL_SELF.Contains('%')) { throw 'Script path is unsuitable for HKCU Run autostart' }
        $null = New-Item -Path $key -Force
        $null = New-ItemProperty -LiteralPath $key -Name $name -Value $command -PropertyType String -Force
    } elseif ($property) { Remove-ItemProperty -LiteralPath $key -Name $name }
}

# ------------------------------------------------------------------------------
# REQUIREMENTS AND ACTIONS
# ------------------------------------------------------------------------------

$script:log_file = $null
$lock = $null
$exit_code = 0
try {
    if ($PSVersionTable.PSVersion -lt [version]'5.1') { throw 'Windows PowerShell 5.1 or later is required' }
    $os = Get-CimInstance Win32_OperatingSystem
    if ($os.ProductType -ne 1 -or ([version]$os.Version).Major -ne 10 -or [int]$os.BuildNumber -lt 10240) {
        throw 'Only Windows 10/11 client editions are supported'
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run as a normal user, without administrator privileges' }
    foreach ($dependency in @('Get-CimInstance','Invoke-CimMethod','Get-NetIPAddress','Invoke-WebRequest','Invoke-RestMethod','ConvertFrom-Json','Start-Process')) {
        $null = Get-Command $dependency -ErrorAction Stop
    }
    $script:cloudflared = (Get-Command cloudflared.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    & $script:cloudflared --version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'cloudflared.exe is not executable' }
    $script:config_dir = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.cloudflared'
    $null = New-Item -ItemType Directory -Path $script:config_dir -Force
    # Serialize actions before clearing the shared preflight log.
    $lock = [IO.File]::Open((Join-Path $script:config_dir 'cftunnel.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $script:log_file = Join-Path $script:config_dir 'preflight.log'
    [IO.File]::WriteAllText($script:log_file, '')
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Log 'EVENT: cftunnel start...'
    $action = $env:CFTUNNEL_ACTION
    if (!$action) {
        Write-Host '1. create  2. start  3. startall  4. stop  5. status  6. delete  0. exit'
        $choice = Ask 'Select an option' '0'
        $menu = @{ '1'='--create'; '2'='--start'; '3'='--startall'; '4'='--stop'; '5'='--status'; '6'='--delete'; '0'='--exit' }
        if (!$menu.ContainsKey($choice)) { throw 'Invalid menu option' }
        $action = $menu[$choice]
    }
    switch -Exact ($action) {
        '--create' { Create-Tunnel }
        '--start' {
            Preflight
            foreach ($name in @(Require-Tunnels)) { if (Confirm "Start tunnel '$name'?") { Start-Tunnel $name } }
        }
        '--startall' {
            Preflight
            foreach ($name in @(Require-Tunnels)) { Start-Tunnel $name $false; Start-Sleep -Seconds 5 }
            Set-Autostart $true
        }
        '--stop' {
            Set-Autostart $false
            foreach ($name in @(Get-Tunnels)) { Stop-Tunnel $name }
        }
        '--status' {
            foreach ($name in @(Require-Tunnels)) {
                $process = Get-TunnelProcess $name
                if ($process) { Write-Host "[UP] $name (PID $($process.ProcessId))" }
                else { Write-Host "[DOWN] $name" }
            }
        }
        '--delete' { Delete-Tunnel }
        '--exit' { }
        default { throw 'invalid option' }
    }
    Log 'EVENT: cftunnel done'
} catch {
    $exit_code = 1
    $message = "ERROR: $($_.Exception.Message) -abort"
    try { Log $message } catch { [Console]::Error.WriteLine($message) }
    if ($message -eq 'ERROR: invalid option -abort') { Write-Host 'Usage: cftunnel.bat [--create|--start|--startall|--stop|--status|--delete]' }
} finally {
    if ($lock) { $lock.Dispose() }
}
exit $exit_code
