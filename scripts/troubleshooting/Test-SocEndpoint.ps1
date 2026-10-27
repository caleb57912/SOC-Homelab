#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$SplunkServer = '10.30.0.10',
    [string]$WazuhManager = '10.30.0.11'
)

$ufHome = 'C:\Program Files\SplunkUniversalForwarder'
$wazuhHome = 'C:\Program Files (x86)\ossec-agent'

function Write-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $mark = if ($Ok) { '[ OK ]' } else { '[FAIL]' }
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("{0} {1} {2}" -f $mark, $Name, $Detail) -ForegroundColor $color
}

Write-Host "`n== Services ==" -ForegroundColor Cyan
foreach ($svc in 'Sysmon64', 'SplunkForwarder', 'WazuhSvc') {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) { Write-Check $svc ($s.Status -eq 'Running') "$($s.Status) / $($s.StartType)" }
    else { Write-Check $svc $false 'not installed' }
}

Write-Host "`n== Network paths ==" -ForegroundColor Cyan
$targets = @(
    @{ Host = $SplunkServer; Port = 9997; Name = 'Splunk receiving' },
    @{ Host = $SplunkServer; Port = 8089; Name = 'Splunk deployment server' },
    @{ Host = $WazuhManager; Port = 1514; Name = 'Wazuh events' },
    @{ Host = $WazuhManager; Port = 1515; Name = 'Wazuh enrollment' }
)
foreach ($t in $targets) {
    $ok = Test-NetConnection -ComputerName $t.Host -Port $t.Port -InformationLevel Quiet -WarningAction SilentlyContinue
    Write-Check $t.Name $ok "$($t.Host):$($t.Port)"
}

Write-Host "`n== Forwarder config ==" -ForegroundColor Cyan
$dc = Join-Path $ufHome 'etc\system\local\deploymentclient.conf'
if (Test-Path $dc) {
    $uri = (Select-String -Path $dc -Pattern 'targetUri').Line
    Write-Check 'deploymentclient.conf' ($uri -match $SplunkServer) $uri
} else {
    Write-Check 'deploymentclient.conf' $false 'missing'
}
$apps = Get-ChildItem (Join-Path $ufHome 'etc\apps') -Directory -Filter 'soc_*' -ErrorAction SilentlyContinue
Write-Check 'Deployed apps' ([bool]$apps) (($apps.Name) -join ', ')

Write-Host "`n== Sysmon channel access ==" -ForegroundColor Cyan
$acl = (wevtutil gl Microsoft-Windows-Sysmon/Operational | Select-String 'channelAccess').Line
Write-Check 'Event Log Readers on channel ACL' ($acl -match 'S-1-5-32-573') ''
$members = net localgroup 'Event Log Readers' 2>$null
Write-Check 'SplunkForwarder in Event Log Readers' ([bool]($members -match 'SplunkForwarder')) ''

Write-Host "`n== Recent forwarder errors ==" -ForegroundColor Cyan
$log = Join-Path $ufHome 'var\log\splunk\splunkd.log'
if (Test-Path $log) {
    $errs = Get-Content $log -Tail 3000 | Select-String -Pattern ' ERROR ' | Select-Object -Last 5
    if ($errs) { $errs | ForEach-Object { Write-Host $_.Line -ForegroundColor Yellow } }
    else { Write-Check 'splunkd.log' $true 'no ERROR lines in the last 3000' }
}

Write-Host "`n== Recent Wazuh agent errors ==" -ForegroundColor Cyan
$wlog = Join-Path $wazuhHome 'ossec.log'
if (Test-Path $wlog) {
    $werrs = Get-Content $wlog -Tail 500 | Select-String -Pattern 'ERROR|WARNING' | Select-Object -Last 5
    if ($werrs) { $werrs | ForEach-Object { Write-Host $_.Line -ForegroundColor Yellow } }
    else { Write-Check 'ossec.log' $true 'no errors in the last 500 lines' }
}

Write-Host "`n== Latest Sysmon event ==" -ForegroundColor Cyan
$last = Get-WinEvent -LogName 'Microsoft-Windows-Sysmon/Operational' -MaxEvents 1 -ErrorAction SilentlyContinue
if ($last) { Write-Check 'Sysmon writing' $true "Id $($last.Id) at $($last.TimeCreated)" }
else { Write-Check 'Sysmon writing' $false 'no events' }
