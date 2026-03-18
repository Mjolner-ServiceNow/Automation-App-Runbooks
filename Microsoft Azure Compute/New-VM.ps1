<#
.SYNOPSIS
    Creates a new Azure virtual machine.

.DESCRIPTION
    This runbook creates a new Azure virtual machine with the specified properties.
    It requires stored credentials in Azure Automation for the Azure tenant.
    It requires the Az.Compute and Az.Network PowerShell modules, which are installed automatically if not present.

.PARAMETER SubscriptionId
    The subscription ID to use for the Azure virtual machine.

.PARAMETER VMName
    The name of the virtual machine to create.

.PARAMETER ResourceGroupName
    The name of the resource group to create the virtual machine in.

.PARAMETER VMLocalAdminUser
    The local administrator username for the virtual machine.

.PARAMETER VMLocalAdminPassword
    The local administrator password for the virtual machine.

.PARAMETER LocationName
    The Azure region to deploy the virtual machine to. Example: "eastus"

.PARAMETER VMSize
    The size of the virtual machine. Example: "Standard_D2s_v6"

.PARAMETER NICName
    The name of the network interface card to create for the virtual machine.

.PARAMETER SubnetID
    The resource ID of the subnet to attach the network interface to.

.EXAMPLE
    .\New-VM.ps1 -VMName "MyVM" -ResourceGroupName "MyResourceGroup" -VMLocalAdminUser "adminuser" -VMLocalAdminPassword "P@ssw0rd!" -LocationName "swedencentral" -VMSize "Standard_DS3_v2" -NICName "MyNIC" -SubnetID "/subscriptions/.../subnets/default"

.NOTES
    Author: Mjølner Informatics AS
    Requires: Az.Compute, Az.Network PowerShell modules
    Requires: Azure Automation stored credentials
    Requires: PowerShell 7+
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VMName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VMLocalAdminUser,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VMLocalAdminPassword,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$LocationName = "westeurope",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$VMSize = "Standard_D2s_v6",

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$NICName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SubnetID
)

# Set error handling
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Set output rendering to plain text if PSStyle is available (PS 7.2+)
if ($PSVersionTable.PSVersion.Minor -ge 2) {
    $PSStyle.OutputRendering = 'PlainText'
}

#region Variables
# Set variables in Azure Automation for the below values to match your environment
#$Credentials = Get-AutomationPSCredential -Name "AccountOperatorAzure"  # Name of stored credentials to use for authentication with Azure
### The managed identity for the Automation Account can also be used for authentication, but requires additional setup and permissions in Azure. Uncomment the next line and comment out the Get-AutomationPSCredential line if you want to use managed identity authentication instead.
#endregion

Write-Verbose "Loaded Automation variables for Azure authentication"

#region Main Script
try {
    # Initialize metadata
    $Metadata = @{
        StartTime         = Get-Date
        VMName            = $VMName
        ResourceGroupName = $ResourceGroupName
    }

    Write-Verbose "Runbook started - $($Metadata.StartTime)"

    # Verify and install required PowerShell modules
    $PowershellModules = @(
        @{
            Name        = "Az.Accounts"
            Type        = "PowershellModule"
            FeatureName = $null
        }
        @{
            Name        = "Az.Compute"
            Type        = "PowershellModule"
            FeatureName = $null
        }
        @{
            Name        = "Az.Network"
            Type        = "PowershellModule"
            FeatureName = $null
        }
        @{
            Name        = "Az.Resources"
            Type        = "PowershellModule"
            FeatureName = $null
        }
    )
    foreach ($Module in $PowershellModules) {
        if (-not (Get-Module -ListAvailable -Name $Module.Name)) {
            Write-Verbose "Module $($Module.Name) not found. Installing..."
            Install-Module -Name $Module.Name -Force -AllowClobber -WarningAction SilentlyContinue
        }
        else {
            Write-Verbose "Module $($Module.Name) found"
        }
    }

    # Get Credential Object from Automation Account
    # Comment out if using managed identity authentication instead
    #if ($null -eq $Credentials) {
    #    throw "Azure Credentials not provided in Automation Account. No Azure connection will be available"
    #}

    # Connect to Azure
    try {
        # This example uses service principal authentication with stored credentials. If using managed identity authentication, the Connect-AzAccount -Identity command above will handle authentication and context setup, so this block can be skipped.
        #Connect-AzAccount -ServicePrincipal -TenantId $TenantId -Credential $Credentials -ContextScope Process | Out-Null
        Connect-AzAccount -Identity | Out-Null
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    }
    catch {
        throw "Unable to connect to Azure. Make sure the provided credentials have access to the tenant and the required permissions."
    }
    #endregion

    # Does Resource Group exist?
    if (-not (Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue)) {
        Write-Verbose "Resource group $ResourceGroupName does not exist. Creating..."
        New-AzResourceGroup -Name $ResourceGroupName -Location $LocationName | Out-Null
    }
    else {
        Write-Verbose "Resource group $ResourceGroupName already exists"
    }

    # disable breaking change warning for output rendering to avoid confusion in runbook output
    Update-AzConfig -DisplayBreakingChangeWarning $false | Out-Null

    # Build public IP address
    $PublicIP = New-AzPublicIpAddress -Name "$($VMName)-ip" -ResourceGroupName $ResourceGroupName -Location $LocationName -AllocationMethod Static -Sku Standard -ErrorAction Stop
    Write-Verbose "Public IP address created: $($PublicIP.Name)"

    # NSG rule to allow RDP
    $allowRDPParams = @{
        Name                       = "RDP"
        Description                = "Allow RDP from Internet"
        Access                     = "Allow"
        Protocol                   = "Tcp"
        Direction                  = "Inbound"
        Priority                   = 300
        SourceAddressPrefix       = "Internet"
        SourcePortRange           = "*"
        DestinationAddressPrefix  = "*"
        DestinationPortRange      = 3389
    }
    $RdpRule = New-AzNetworkSecurityRuleConfig @allowRDPParams

    # Build Network Security Group
    $NSG = New-AzNetworkSecurityGroup -Name "$($VMName)-nsg" -ResourceGroupName $ResourceGroupName -Location $LocationName -SecurityRules $RdpRule -ErrorAction Stop
    Write-Verbose "Network Security Group created: $($NSG.Name)"    

    # Build network interface (with public IP and NSG)
    $NIC = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName -SubnetId $SubnetID -PublicIpAddressId $PublicIP.Id -NetworkSecurityGroupId $NSG.Id -ErrorAction Stop

    # Build VM credential
    $VMLocalAdminSecurePassword = ConvertTo-SecureString $VMLocalAdminPassword -AsPlainText -Force
    $VMCredential = New-Object System.Management.Automation.PSCredential ($VMLocalAdminUser, $VMLocalAdminSecurePassword)

    # Build VM configuration
    $VirtualMachine = New-AzVMConfig -VMName $VMName -VMSize $VMSize -securityType Standard
    $VirtualMachine = Set-AzVMBootDiagnostic -VM $VirtualMachine -Disable
    $VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $VMName -Credential $VMCredential -ProvisionVMAgent -EnableAutoUpdate
    $VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id
    $VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2022-datacenter-g2' -Version latest

    # Create the virtual machine
    New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $VirtualMachine -ErrorAction Stop | Out-Null
    $VM = Get-AzVM -Name $VMName -ResourceGroupName $ResourceGroupName

    Write-Verbose "Virtual machine created successfully"
}
catch {
    $ErrorMessage = "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    Write-Error -Message $ErrorMessage -ErrorAction Continue
    throw
}
finally {
    # Calculate and output results
    if ($VM) {
        $RuntimeSeconds = (([DateTime]::Now) - $Metadata.StartTime).TotalSeconds
        Write-Verbose "Runbook completed successfully. Total runtime: $RuntimeSeconds seconds"

        # Output VM details as JSON
        $VM | Select-Object -Property Name, ResourceGroupName, Location, Id | ConvertTo-Json -WarningAction SilentlyContinue

        # Uncomment next line if metadata output is required
        # $Metadata | ConvertTo-Json -WarningAction SilentlyContinue
    }
}
#endregion