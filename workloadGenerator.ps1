# Download and execute this script on WINVM1 to setup the environment and
# start some load on SQL Server

# Install DBATools
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false
Install-Module DBATools -Force -Confirm:$false

# !!!! Update this parameter with the URL of your Azure SQL DB logical server !!!!
$azSqlSrv = "azsqlsrv2148822.database.windows.net"

$sqlAdmin = "contosoadmin"
$sqlAdminPwd = ConvertTo-SecureString "Passw0rd.1" -AsPlainText -Force

$sqlCred = New-Object System.Management.Automation.PSCredential ($sqlAdmin, $sqlAdminPwd)

# Download and restore AdventureWorks2017 on SQL VM
$scriptBlock = {
    # Install DBATools
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false
    Install-Module DBATools -Force -Confirm:$false

    # Get AdventureWorks from official GitHub repo
    New-Item -Path "C:\Temp" -ItemType Directory
    [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
    Invoke-WebRequest -Uri "https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2017.bak" -OutFile "C:\Temp\AdventureWorks2017.bak"

    # Restore DB on SQL Windows VM
    Restore-DbaDatabase -SqlInstance "DEMO-SQLWINVM1" -DatabaseName "AdventureWorks" -Path "C:\Temp\AdventureWorks2017.bak"
}

Invoke-Command -ComputerName "DEMO-SQLWINVM1" -ScriptBlock $scriptBlock

# Installing Chocolatey to deploy GIT
Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
choco install -y git

# Cloning SqlWorkloadGenerator (https://github.com/Matticusau/SqlWorkloadGenerator) to generate some workload against AdventureWorks
New-Item -Path C:\Workload -ItemType Directory
New-Alias -Name git -Value "$Env:ProgramFiles\Git\bin\git.exe"
git clone https://github.com/Matticusau/SqlWorkloadGenerator.git C:\Workload

# Execute workload on SQL as a background process
Start-Job {
    while(1) {
        Invoke-DbaQuery -SqlInstance $azSqlSrv -SqlCredential $sqlCred -File C:\Workload\SqlScripts\AdventureWorksAzureBOLWorkload.sql -Database DemoDB
        Invoke-DbaQuery -SqlInstance DEMO-SQLWINVM1 -File C:\Workload\SqlScripts\AdventureWorksWorkload.sql -Database AdventureWorks
    }
    
}


# Install IIS locally and generate some requests to default web site
Install-WindowsFeature Web-Server -IncludeAllSubFeature -IncludeManagementTools
for ($i=0; $i -le 10000; $i++) {
    Invoke-webrequest -Uri http://localhost
    Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 1000)
}

# Disable IE ESC - credits to https://gist.github.com/danielscholl/bbc18540418e17c39a4292ffcdcc95f0
function Disable-ieESC {
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
    Stop-Process -Name Explorer
    Write-Host "IE Enhanced Security Configuration (ESC) has been disabled." -ForegroundColor Green
}
Disable-ieESC

# configure VM as an automation hybrid worker
Install-Script -Name New-OnPremiseHybridWorker -Force

$automationAccountName = "AutomationDemo" # Insert the name of demo automation account
$ResourceGroupName = "AzureMonitorDemo" # Insert the name of the RG which contains it
$HybridGroupName = "AzureMonitorDemo" # Assing a name to the group
$subscriptionId = "" # Insert your subs ID
$workspaceName = "" # Insert the Log Analytics workspace name

New-OnPremiseHybridWorker.ps1 -AutomationAccountName $automationAccountName -AAResourceGroupName $ResourceGroupName -HybridGroupName $HybridGroupName -SubscriptionID $subscriptionId -WorkspaceName $workspaceName

$f = New-Object System.IO.FileStream "C:\LogFiles\oldLog.txt", Create, ReadWrite
$f.SetLength(10GB)
$f.Close()
(Get-Item -Path "C:\LogFiles\oldLog.txt").CreationTime = (Get-Date).AddMonths(-2)
(Get-Item -Path "C:\LogFiles\oldLog.txt").LastAccessTime = (Get-Date).AddMonths(-2)
(Get-Item -Path "C:\LogFiles\oldLog.txt").LastWriteTime= (Get-Date).AddMonths(-2)

$f = New-Object System.IO.FileStream "C:\LogFiles\newLog.txt", Create, ReadWrite
$f.SetLength(2GB)
$f.Close()

$f = New-Object System.IO.FileStream "D:\newLog.txt", Create, ReadWrite
$f.SetLength(13GB)
$f.Close()
