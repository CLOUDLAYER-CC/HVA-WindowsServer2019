[CmdletBinding()]
param(

    [string]$uid,

    [int64]$CPU,

    [int64]$Memory,

    [uint64]$Storage,

    [ValidateSet('Ext1', 'Internal Switch', 'Private Switch')]
    [string]$SwitchName,

    [string]$WindowsISO,

    [ValidateSet('Windows Server 2019 Datacenter Evaluation', 'Windows Server 2019 Datacenter Evaluation (Desktop Experience)')]
    [string]$WindowsEdition,

    [string]$AdminPassword,

    [string]$DstDrive,
    
    [string]$uid

)

# AutoBuild Properties

## Check we have Convert-WindowsImage.ps1
If (-not (Test-Path -Path .\Convert-WindowsImage.ps1 -PathType Leaf)) {
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/MicrosoftDocs/Virtualization-Documentation/master/hyperv-tools/Convert-WindowsImage/Convert-WindowsImage.ps1' -OutFile .\Convert-WindowsImage.ps1
}

## Random ID
$BuildID = (Get-Random)

## Base Keys
## Install with KMS, Activate with AMVA
$WindowsKMS = 'WMDGN-G9PQG-XVVXX-R3X43-63DFG'
$WindowsAMVA = 'H3RNG-8C32Q-Q8FRX-6TDXV-WMBMW'


## Quick Check for inflight and duplicate builds
if (Test-Path -Path "C:\Temp\HVA\$uid") {
    $uid = $uid + $BuildID
}
elseif (Get-VM | Where-Object Name -EQ $uid) {
    $uid = $uid + $BuildID
}

## Trim and clean name
$uid = $uid -replace '\s', '' -replace '^(.{0,14}).*', '$1'

## Setup Working Directories for build
$TempDirectory = "D:\Temp\HVA\$uid"
$UnattendDirectory = "$DstDrive\Temp\HVA\$uid\Unattend"
New-Item -Path $TempDirectory -ItemType Directory -Force | Out-Null
New-Item -Path $UnattendDirectory -ItemType Directory -Force | Out-Null
## Set VHD Path
$VHDPath = (Get-WmiObject -Namespace root\virtualization\v2 Msvm_VirtualSystemManagementServiceSettingData).DefaultVirtualHardDiskPath + "\$uid.vhdx"

# User Details
## Administrator
$UserName = 'Administrator'
if (-not $AdminPassword) {
    $AdminPassword = -join (33..126 | ForEach-Object { [char]$_ } | Get-Random -C 24)
}
## Secure String and Credential
$Password = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential($UserName, $Password)

# START BUILD

## Start Time
$StartTime = Get-Date

Write-Host "[$BuildID] - $(Get-date) - Build Start" -ForegroundColor Green
Write-Host "[$BuildID] - $(Get-date) - Finding Answers" -ForegroundColor Yellow

## Create Answer File
$UnattendTemplate = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="specialize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <ProductKey></ProductKey>
            <ComputerName></ComputerName>
        </component>
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <InputLocale>ko-KR</InputLocale>
            <SystemLocale>ko-KR</SystemLocale>
            <UserLocale>ko-KR</UserLocale>
        </component>
        <component name="Microsoft-Windows-Security-SPP-UX" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <SkipAutoActivation>true</SkipAutoActivation>
        </component>
        <component name="Microsoft-Windows-SQMApi" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <CEIPEnabled>0</CEIPEnabled>
        </component>
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Path>net user administrator /active:yes</Path>
                </RunSynchronousCommand>
            </RunSynchronous>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideLocalAccountScreen>true</HideLocalAccountScreen>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <SkipMachineOOBE>true</SkipMachineOOBE>
                <SkipUserOOBE>true</SkipUserOOBE>
            </OOBE>
            <UserAccounts>
                <AdministratorPassword>
                    <Value></Value>
                    <PlainText>true</PlainText>
                </AdministratorPassword>
            </UserAccounts>
        </component>
    </settings>
</unattend>
'@

## Template Set
$xml = [xml]$UnattendTemplate
## Answer destination
$UnattendPath = "$UnattendDirectory\unattend.xml"
## Define unattended settings
$xml.unattend.settings[0].component[0].ComputerName = $uid
$xml.unattend.settings[0].component[0].ProductKey = $WindowsKMS
$xml.unattend.settings[1].component.UserAccounts.AdministratorPassword.Value = $AdminPassword
## Save and Write answers
$writer = New-Object System.XMl.XmlTextWriter($UnattendPath, [System.Text.Encoding]::UTF8)
$writer.Formatting = [System.Xml.Formatting]::Indented
$xml.Save($writer)
$writer.Dispose()

## Create VHDX from ISO
Write-Host "[$BuildID] - $(Get-date) - Mixing $uid with $WindowsEdition" -ForegroundColor Yellow

## Import Convert-WindowsImage.ps1 function for use
. .\Convert-WindowsImage.ps1

## Compile Image
Convert-WindowsImage -SourcePath $WindowsISO -Edition $WindowsEdition -TempDirectory $TempDirectory -UnattendPath $UnattendPath -SizeBytes $Storage -DiskLayout UEFI -VHDPath $VHDPath -VHDFormat VHDX

## Setup new VM
$SetupVM = New-VM -Name $uid -Generation 2 -MemoryStartupBytes $Memory -VHDPath $VHDPath -SwitchName $SwitchName
$SetupVM | Set-VMProcessor -Count $CPU
$SetupVM | Get-VMIntegrationService -Name "Guest Service Interface" | Enable-VMIntegrationService -Passthru
$SetupVM | Set-VMMemory -DynamicMemoryEnabled $true
$SetupVM | Set-VM -AutomaticCheckpointsEnabled $false
$SetupVM | Start-VM

## Wait for installation complete
Wait-VM -Name $uid -For Heartbeat

## START CONFIG ##

do {
    Start-Sleep -Seconds 60
    $StartSession = New-PSSession -VMName $uid -Credential $Credential -ErrorAction SilentlyContinue
} until ($StartSession.State -eq "Opened")

## Connect to New VM and enable Remote Management
Write-Host "[$BuildID] - $(Get-date) - Setting up $uid" -ForegroundColor Yellow

## Setup Ansible for Host Management
Write-Host "[$BuildID] - $(Get-date) - Enabling Ansible Management on $uid" -ForegroundColor Yellow
Invoke-Command -Session $StartSession -ScriptBlock {
    Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1'))
}
 
## Install Chocolatey
Write-Host "[$BuildID] - $(Get-date) - Installing Chocolatey on $uid" -ForegroundColor Yellow
Invoke-Command -Session $StartSession -ScriptBlock {
    Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
}

## Setup RDP for Host Management if Desktop
if ($WindowsEdition -match "Desktop") {
    Write-Host "[$BuildID] - $(Get-date) - Enabling RDP on $uid" -ForegroundColor Yellow
    Invoke-Command -Session $StartSession -ScriptBlock {
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    }

    ## Upgrade OS from Eval to Full using KMS Key
    ## https://docs.microsoft.com/en-us/windows-server/get-started/kmsclientkeys
    Write-Host "[$BuildID] - $(Get-date) - Converting Windows Server Evaluation to Full" -ForegroundColor Yellow
    Invoke-Command -Session $StartSession -ScriptBlock {
        dism /online /Set-Edition:ServerDatacenter /ProductKey:WMDGN-G9PQG-XVVXX-R3X43-63DFG /AcceptEula /NoRestart /Quiet
    }
    
}
else {
 
    ## Upgrade OS from Eval to Full using KMS Key
    ## https://docs.microsoft.com/en-us/windows-server/get-started/kmsclientkeys
    Write-Host "[$BuildID] - $(Get-date) - Converting Windows Server Evaluation to Full" -ForegroundColor Yellow
    Invoke-Command -Session $StartSession -ScriptBlock {
        dism /online /Set-Edition:ServerDatacenterCor /ProductKey:WMDGN-G9PQG-XVVXX-R3X43-63DFG /AcceptEula /NoRestart /Quiet
    }
    
}

## Reboot
Write-Host "[$BuildID] - $(Get-date) - Restarting $uid" -ForegroundColor Yellow
Invoke-Command -Session $StartSession -ScriptBlock {
    shutdown /r
}

## Create new session after reboot and continue
Wait-VM -Name $uid -For Heartbeat
do {
    Start-Sleep -Seconds 60
    $StartSession2 = New-PSSession -VMName $uid -Credential $Credential -ErrorAction SilentlyContinue
} until ($StartSession2.State -eq "Opened")

## Set AVMA Key for Windows Server 2019
## https://docs.microsoft.com/en-us/windows-server/get-started-19/vm-activation-19
Write-Host "[$BuildID] - $(Get-date) - Setting AVMA Key on $uid" -ForegroundColor Yellow
Invoke-Command -Session $StartSession2 -ScriptBlock {
    cscript.exe $env:SystemRoot\System32\slmgr.vbs /ipk H3RNG-8C32Q-Q8FRX-6TDXV-WMBMW
    # Activate Windows
    cscript.exe $env:SystemRoot\System32\slmgr.vbs /ato
    # Return activation state
    cscript.exe $env:SystemRoot\System32\slmgr.vbs /dli
}

## Disable Realtime Antivirus monitoring, Clean install
Write-Host "[$BuildID] - $(Get-date) - Cleaning up $uid" -ForegroundColor Yellow
Invoke-Command -Session $StartSession2 -ScriptBlock {
    # Disable realtime monitoring
    Set-MpPreference -DisableRealtimeMonitoring $true

    # Clean up OS
    dism /online /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet
}

## Reboot
Write-Host "[$BuildID] - $(Get-date) - Restarting $uid" -ForegroundColor Yellow
Invoke-Command -Session $StartSession2 -ScriptBlock {
    shutdown /r
}

# Waiting for Heartbeat prior to finish
Wait-VM -Name $uid -For Heartbeat

# END CONFIG

## End Time
$EndTime = Get-Date
$TotalTime = (New-TimeSpan -Start $StartTime -End $EndTime).Minutes

# END BUILD

## Wrap it up
Write-Host "[$BuildID] - $(Get-date) - $uid is now ready"
Write-Host "[$BuildID] - $(Get-date) - Credentials: $UserName\$AdminPassword" -ForegroundColor Yellow
Write-Host "[$BuildID] - $(Get-date) - Build End" -ForegroundColor Yellow
Write-Host "[$BuildID] - $(Get-date) - Completed in $TotalTime Minutes" -ForegroundColor Green