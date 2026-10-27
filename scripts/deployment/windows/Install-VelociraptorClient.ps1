#Requires -RunAsAdministrator
param(
    [string]$Msi,
    [string]$ExpectedSha256,
    [string]$Server = "10.30.0.22",
    [int]$Port = 8000,
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"

function Show-Status {
    $svc = Get-Service Velociraptor -ErrorAction SilentlyContinue
    if ($svc) {
        "Service: {0}, {1}" -f $svc.Status, $svc.StartType
        $exe = "C:\Program Files\Velociraptor\Velociraptor.exe"
        if (Test-Path $exe) {
            $sig = Get-AuthenticodeSignature $exe
            "Velociraptor.exe signature: {0} ({1})" -f $sig.Status, $sig.SignerCertificate.Subject
        }
        Get-NetTCPConnection -RemoteAddress $Server -RemotePort $Port -ErrorAction SilentlyContinue |
            Select-Object -First 1 | ForEach-Object { "Connection to ${Server}:${Port}: $($_.State)" }
    } else {
        "Service: not installed"
    }
}

"== Path to the frontend =="
$tcp = Test-NetConnection $Server -Port $Port -WarningAction SilentlyContinue
"${Server}:${Port} reachable: $($tcp.TcpTestSucceeded)"

if ($CheckOnly) {
    ""
    "== Client =="
    Show-Status
    return
}

if (-not $tcp.TcpTestSucceeded) {
    throw "Port $Port on $Server is not reachable; check the firewall between this network and the SOC VLAN before installing"
}
if (-not $Msi -or -not (Test-Path $Msi)) { throw "Pass -Msi with the path to the repacked MSI" }

""
"== MSI hash =="
$hash = (Get-FileHash $Msi -Algorithm SHA256).Hash
$hash
if ($ExpectedSha256) {
    if ($hash -ne $ExpectedSha256.ToUpper()) { throw "Hash does not match the one printed on velo01; do not install" }
    "Matches the hash from velo01"
} else {
    Write-Warning "No -ExpectedSha256 given; compare the hash above with velo01 by eye"
}

""
"== Install =="
$p = Start-Process msiexec -ArgumentList '/i', "`"$Msi`"", '/qn' -Wait -PassThru
"msiexec exit code: $($p.ExitCode)"
Start-Sleep -Seconds 10
Show-Status
""
"Next: in the GUI (https://${Server}:8889) search with an empty bar; this host should show a green dot."
