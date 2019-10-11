Add-AzAccount

$RgName = "AzureMonitorDemo"
$Location = "West Europe"
$domain = "contoso.local"
$domainAdmin = "contosoadmin"
$domainAdminPwd = (ConvertTo-SecureString "Passw0rd.1" -AsPlainText -Force)

# Get or create resource group
try {
    $Rg = Get-AzResourceGroup -Name $RgName -ErrorAction Stop
} catch {
    $Rg = New-AzResourceGroup -Name $RgName -Location $Location
}

# Create an AD forest with 2 DC by using a quickstart gallery template
New-AzResourceGroupDeployment -TemplateUri https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/active-directory-new-domain-ha-2-dc/azuredeploy.json `
    -ResourceGroupName $Rg.ResourceGroupName `
    -domainName $domain `
    -adminUsername $domainAdmin `
    -adminPassword $domainAdminPwd `
    -dnsPrefix ("azuremonitordemo-" + (Get-Random -Maximum 99999)) `
    -pdcRDPPort 59990 `
    -bdcRDPPort 59991 `
    -location $Rg.Location

# To reduce lab costs, deallocate VMs created before and reduce their size and tier of disks
$adVm = Get-AzVm -ResourceGroupName $Rg.ResourceGroupName |
            ? Name -like 'ad*'

$adVmJob = $adVm | Stop-AzVm -Force -asJob

While (($adVmJob | Get-Job).State -ne "Completed") {
    Start-Sleep -Seconds 1
}

$adVm | % { $_.HardwareProfile = "Standard_B2s"}
$adVm | % {
    $diskUpdate = New-AzDiskUpdateConfig -SkuName "StandardSSD_LRS" 
    Update-AzDisk -ResourceGroupName $rg.ResourceGroupName -DiskName $_.StorageProfile.OsDisk.Name -DiskUpdate $diskUpdate
    $_.StorageProfile.DataDisks | % { Update-AzDisk -ResourceGroupName $rg.ResourceGroupName -DiskName $_.Name -DiskUpdate $diskUpdate }
}

$adVm | Update-AzVM
$adVm | Start-AzVm -AsJob

# Create a new subnet for member server
$vnet = Get-AzVirtualNetwork -Name "adVnet" `
            -ResourceGroupName $Rg.ResourceGroupName

$subnet = Add-AzVirtualNetworkSubnetConfig -Name "ServerSubnet" -VirtualNetwork $vnet -AddressPrefix "10.0.1.0/24" | Set-AzVirtualNetwork

# Deploy a couple of domain joined member servers from my lab templates gallery
# Windows VM
New-AzResourceGroupDeployment -TemplateUri https://raw.githubusercontent.com/OmegaMadLab/LabTemplates/master/WinVm-domainJoin.json `
    -envPrefix "Demo" `
    -vmName "WINVM1" `
    -vnetName "adVnet" `
    -subnetName "ServerSubnet" `
    -domainName $domain `
    -adminUserName $domainAdmin `
    -adminPassword $domainAdminPwd `
    -ResourceGroupName $Rg.ResourceGroupName `
    -AsJob

# SQL on Windows VM
New-AzResourceGroupDeployment -TemplateUri https://raw.githubusercontent.com/OmegaMadLab/LabTemplates/master/WinSqlVm-domainJoin.json `
    -envPrefix "Demo" `
    -vmName "SQLWINVM1" `
    -vnetName "adVnet" `
    -subnetName "ServerSubnet" `
    -domainName $domain `
    -adminUserName $domainAdmin `
    -adminPassword $domainAdminPwd `
    -genericVmSize "Standard_B4s" `
    -ResourceGroupName $Rg.ResourceGroupName `
    -AsJob

# Linux VM
New-AzResourceGroupDeployment -TemplateUri https://raw.githubusercontent.com/OmegaMadLab/LabTemplates/master/LinuxVm.json `
    -envPrefix "Demo" `
    -vmName "LINUXVM1" `
    -vnetName "adVnet" `
    -subnetName "ServerSubnet" `
    -adminUserName $domainAdmin `
    -authenticationType "password" `
    -adminPasswordOrKey $domainAdminPwd `
    -ResourceGroupName $Rg.ResourceGroupName `
    -AsJob

# Deploy a NSG associated to server subnet, and create rules to:
# 1. allow traffic on SQL port between SQL on Windows VM and simple Windows VM
# 2. block all other traffic between them.
$sqlIp = (Get-AzNetworkInterface -ResourceGroupName $rg.ResourceGroupName |
            ? Name -Like 'Demo-SQLWINVM1*').IpConfigurations[0].PrivateIpAddress

$serverIp = (Get-AzNetworkInterface -ResourceGroupName $rg.ResourceGroupName |
                ? Name -Like 'Demo-WINVM1*').IpConfigurations[0].PrivateIpAddress

$rule1 = New-AzNetworkSecurityRuleConfig -Name "AllowSQL" `
            -Protocol Tcp `
            -Direction Inbound `
            -SourceAddressPrefix $serverIp `
            -SourcePortRange * `
            -DestinationAddressPrefix $sqlIp `
            -DestinationPortRange 1433 `
            -Priority 100 `
            -Access Allow

$rule2 = New-AzNetworkSecurityRuleConfig -Name "BlockTraffic" `
            -Protocol * `
            -Direction Inbound `
            -SourceAddressPrefix $serverIp `
            -SourcePortRange * `
            -DestinationAddressPrefix $sqlIp `
            -DestinationPortRange * `
            -Priority 110 `
            -Access Deny

$rule3 = New-AzNetworkSecurityRuleConfig -Name "AllowRDP" `
            -Protocol Tcp `
            -Direction Inbound `
            -SourceAddressPrefix * `
            -SourcePortRange * `
            -DestinationAddressPrefix $serverIp `
            -DestinationPortRange 3389 `
            -Priority 120 `
            -Access Allow

$rule4 = New-AzNetworkSecurityRuleConfig -Name "AllowWinRM" `
            -Protocol Tcp `
            -Direction Inbound `
            -SourceAddressPrefix $serverIp `
            -SourcePortRange * `
            -DestinationAddressPrefix $sqlIp `
            -DestinationPortRange 5985, 5986 `
            -Priority 105 `
            -Access Allow

$nsg = New-AzNetworkSecurityGroup -Name "ServerSubnet-NSG" `
        -Location $Location `
        -ResourceGroupName $Rg.ResourceGroupName `
        -SecurityRules $rule1,$rule2,$rule3,$rule4
        
$subnet.NetworkSecurityGroup = $nsg
$vnet | Set-AzVirtualNetwork


# Deploy an App Service and an Azure SQL Database
$AppServicePlan = New-AzAppServicePlan -ResourceGroupName $Rg.ResourceGroupName `
                    -Name "AppServiceDemo" `
                    -Location $Location `
                    -Tier Standard `
                    -WorkerSize Small

$webApp = New-AzWebApp -Name ("webappdemo" + (Get-Random -Maximum 9999999)) `
            -ResourceGroupName $Rg.ResourceGroupName `
            -Location $Location `
            -AppServicePlan $AppServicePlan.Name

$sqlSrv = New-AzSqlServer -ServerName ("azsqlsrv" + (Get-Random -Maximum 9999999)) `
            -Location $Location `
            -ResourceGroupName $Rg.ResourceGroupName `
            -SqlAdministratorCredentials (New-Object System.Management.Automation.PSCredential ($domainAdmin, $domainAdminPwd))

New-AzSqlServerFirewallRule -ServerName $sqlSrv.ServerName -AllowAllAzureIPs -ResourceGroupName $rg.ResourceGroupName

New-AzSqlDatabase -DatabaseName "DemoDB" `
    -ServerName $sqlSrv.ServerName `
    -Edition Free `
    -ResourceGroupName $Rg.ResourceGroupName `
    -SampleName AdventureWorksLT

# Deploy a sample webapp
$PropertiesObject = @{
    repoUrl = "https://github.com/Azure-Samples/app-service-web-html-get-started.git";
    branch = "master";
    isManualIntegration = "true";
}

Set-AzResource -PropertyObject $PropertiesObject `
    -ResourceGroupName $Rg.ResourceGroupName `
    -ResourceType Microsoft.Web/sites/sourcecontrols `
    -ResourceName "$($webApp.Name)/web" `
    -ApiVersion 2015-08-01 `
    -Force

# Create new Log Analytics Workspace
$WorkspaceName = "log-analytics-demo-" + (Get-Random -Maximum 99999)
New-AzOperationalInsightsWorkspace -Name $WorkspaceName `
    -Sku Standard `
    -Location $Location `
    -ResourceGroupName $Rg.ResourceGroupName 

# List all solutions and their installation status
Get-AzOperationalInsightsIntelligencePack -ResourceGroupName $Rg.ResourceGroupName -WorkspaceName $WorkspaceName

# Create new AppInsight
$appInsightName = "appInsight-demo-" + (Get-Random -Maximum 99999)
$appInsight = New-AzApplicationInsights -Name $appInsightName `
                -ResourceGroupName $rg.ResourceGroupName `
                -Location $Location

# Create a new automation account
$automation = New-AzAutomationAccount -Name "AutomationDemo" `
                -ResourceGroupName $Rg.ResourceGroupName `
                -Location $Location

New-AzAutomationCredential -Name VmLocalAdmin `
    -AutomationAccountName $automation.AutomationAccountName `
    -ResourceGroupName $rg.ResourceGroupName `
    -Value (New-Object -TypeName pscredential -ArgumentList ($domainAdmin, $domainAdminPwd))



# Create an additional VM after enabling Azure Policy (as seen in session recording) to automatically deploy Log Analytics agent
New-AzResourceGroupDeployment -TemplateUri https://raw.githubusercontent.com/OmegaMadLab/LabTemplates/master/WinVm-domainJoin.json `
    -envPrefix "Demo" `
    -vmName "WINVM2" `
    -vnetName "adVnet" `
    -subnetName "ServerSubnet" `
    -domainName $domain `
    -adminUserName $domainAdmin `
    -adminPassword $domainAdminPwd `
    -ResourceGroupName $Rg.ResourceGroupName `
    -AsJob

