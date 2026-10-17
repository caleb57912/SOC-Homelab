#Requires -RunAsAdministrator
param(
    [string]$ToolsPath = "C:\Tools\Sysmon",
    [string]$ConfigUrl = "https://github.com/olafhartong/sysmon-modular/releases/latest/download/sysmonconfig.xml",
    [string]$ForwarderMsi,
    [string]$Indexer = "10.30.0.10:9997",
    [string]$DeploymentServer = "10.30.0.10:8089",
    [string]$WazuhManager,
    [string]$WazuhVersion = "4.14.9-1"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

New-Item -ItemType Directory -Path $ToolsPath -Force | Out-Null
$zip    = Join-Path $ToolsPath "Sysmon.zip"
$config = Join-Path $ToolsPath "sysmonconfig.xml"
$exe    = Join-Path $ToolsPath "Sysmon64.exe"

Write-Host "[Sysmon] Downloading binaries and config"
Invoke-WebRequest -Uri "https://download.sysinternals.com/files/Sysmon.zip" -OutFile $zip -UseBasicParsing
Expand-Archive -Path $zip -DestinationPath $ToolsPath -Force
Invoke-WebRequest -Uri $ConfigUrl -OutFile $config -UseBasicParsing
if (-not (Select-String -Path $config -Pattern "schemaversion" -Quiet)) {
    throw "Config download is not a Sysmon config: $config"
}

Write-Host "[Sysmon] Installing or updating"
if (Get-Service -Name Sysmon64 -ErrorAction SilentlyContinue) {
    & $exe -c $config | Out-Null
} else {
    & $exe -accepteula -i $config | Out-Null
}

Write-Host "[Audit] Enabling PowerShell script block logging and logon auditing"
$sbl = "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
New-Item -Path $sbl -Force | Out-Null
Set-ItemProperty -Path $sbl -Name EnableScriptBlockLogging -Value 1 -Type DWord
auditpol /set /subcategory:"Logon" /success:enable /failure:enable | Out-Null

if ($ForwarderMsi) {
    $ufHome = "C:\Program Files\SplunkUniversalForwarder"

    if (-not (Get-Service -Name SplunkForwarder -ErrorAction SilentlyContinue)) {
        Write-Host "[Forwarder] Installing"
        if (-not (Test-Path $ForwarderMsi)) { throw "MSI not found: $ForwarderMsi" }
        $msiArgs = @(
            "/i", "`"$ForwarderMsi`"",
            "RECEIVING_INDEXER=$Indexer",
            "AGREETOLICENSE=Yes",
            "GENRANDOMPASSWORD=1",
            "/quiet", "/norestart"
        )
        $p = Start-Process -FilePath msiexec.exe -ArgumentList $msiArgs -Wait -PassThru
        if ($p.ExitCode -ne 0) { throw "Forwarder install failed, msiexec exit code $($p.ExitCode)" }
    } else {
        Write-Host "[Forwarder] Already installed"
    }

    Write-Host "[Forwarder] Pointing at deployment server $DeploymentServer"
    $sysLocal = Join-Path $ufHome "etc\system\local"
    New-Item -ItemType Directory -Path $sysLocal -Force | Out-Null
    $dc = "[deployment-client]`r`n`r`n[target-broker:deploymentServer]`r`ntargetUri = $DeploymentServer`r`n"
    Set-Content -Path (Join-Path $sysLocal "deploymentclient.conf") -Value $dc -Encoding ASCII

    Write-Host "[Forwarder] Granting read access to event logs (Event Log Readers)"
    $readers = Get-LocalGroupMember -SID "S-1-5-32-573" | Where-Object { $_.Name -eq "NT SERVICE\SplunkForwarder" }
    if (-not $readers) {
        Add-LocalGroupMember -SID "S-1-5-32-573" -Member "NT SERVICE\SplunkForwarder"
    }

    Restart-Service -Name SplunkForwarder
    Start-Sleep -Seconds 20
}

if ($WazuhManager) {
    if (-not (Get-Service -Name WazuhSvc -ErrorAction SilentlyContinue)) {
        Write-Host "[Wazuh] Installing agent $WazuhVersion"
        $wazuhMsi = Join-Path $env:TEMP "wazuh-agent-$WazuhVersion.msi"
        Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-$WazuhVersion.msi" -OutFile $wazuhMsi -UseBasicParsing
        $secure = Read-Host "Wazuh enrollment password" -AsSecureString
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
        $wArgs = @(
            "/i", "`"$wazuhMsi`"", "/q",
            "WAZUH_MANAGER=$WazuhManager",
            "WAZUH_REGISTRATION_PASSWORD=$plain",
            "WAZUH_AGENT_NAME=$env:COMPUTERNAME"
        )
        $p = Start-Process -FilePath msiexec.exe -ArgumentList $wArgs -Wait -PassThru
        $plain = $null
        Remove-Item $wazuhMsi -Force
        if ($p.ExitCode -ne 0) { throw "Wazuh agent install failed, msiexec exit code $($p.ExitCode)" }
        Start-Service -Name WazuhSvc
        Start-Sleep -Seconds 15
    } else {
        Write-Host "[Wazuh] Agent already installed"
    }
}

Write-Host "[Verify]"
Get-Service Sysmon64, SplunkForwarder, WazuhSvc -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType | Format-Table -AutoSize
Get-WinEvent -LogName "Microsoft-Windows-Sysmon/Operational" -MaxEvents 5 | Select-Object TimeCreated, Id | Format-Table -AutoSize
auditpol /get /subcategory:"Logon"
if ($ForwarderMsi) {
    $hostPart = $Indexer.Split(":")[0]
    $portPart = [int]$Indexer.Split(":")[1]
    $conn = Get-NetTCPConnection -RemoteAddress $hostPart -RemotePort $portPart -State Established -ErrorAction SilentlyContinue
    if ($conn) { Write-Host "Forwarder connected to $Indexer" -ForegroundColor Green }
    else { Write-Host "No connection to $Indexer yet" -ForegroundColor Yellow }
}
