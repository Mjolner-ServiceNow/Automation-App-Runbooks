<#
.SYNOPSIS
    Creates a new Azure virtual machine.

.DESCRIPTION
    This runbook creates a new Azure virtual machine with the specified properties.
    It requires stored credentials in Azure Automation for the Azure tenant.
    It requires the Az.Compute and Az.Network PowerShell modules, which are installed automatically if not present.

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
    The size of the virtual machine. Example: "Standard_DS3_v2"

.PARAMETER NICName
    The name of the network interface card to create for the virtual machine.

.PARAMETER SubnetID
    The resource ID of the subnet to attach the network interface to.

.EXAMPLE
    .\New-VM.ps1 -VMName "MyVM" -ResourceGroupName "MyResourceGroup" -VMLocalAdminUser "adminuser" -VMLocalAdminPassword "P@ssw0rd!" -LocationName "eastus" -VMSize "Standard_DS3_v2" -NICName "MyNIC" -SubnetID "/subscriptions/.../subnets/default"

.NOTES
    Author: Mjølner Informatics AS
    Requires: Az.Compute, Az.Network PowerShell modules
    Requires: Azure Automation stored credentials
    Requires: PowerShell 7+
#>

param (
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
    [string]$LocationName = "eastus",

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$VMSize = "Standard_DS3_v2",

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
$TenantID = Get-AutomationVariable -Name "TenantID"                     # Tenant ID for the Azure tenant
$SubscriptionID = Get-AutomationVariable -Name "SubscriptionID"         # Subscription ID to target
$Credentials = Get-AutomationPSCredential -Name "AccountOperatorAzure"  # Name of stored credentials to use for authentication with Azure
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
    if ($null -eq $Credentials) {
        throw "Azure Credentials not provided in Automation Account. No Azure connection will be available"
    }

    # Connect to Azure
    try {
        Connect-AzAccount -ServicePrincipal -TenantId $TenantId -Credential $Credentials -ContextScope Process | Out-Null
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    }
    catch {
        throw "Unable to connect to Azure. Make sure the provided credentials have access to the tenant and the required permissions."
    }
    #endregion

    # Build network interface
    $NIC = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName -SubnetId $SubnetID

    # Build VM credential
    $VMLocalAdminSecurePassword = ConvertTo-SecureString $VMLocalAdminPassword -AsPlainText -Force
    $VMCredential = New-Object System.Management.Automation.PSCredential ($VMLocalAdminUser, $VMLocalAdminSecurePassword)

    # Build VM configuration
    $VirtualMachine = New-AzVMConfig -VMName $VMName -VMSize $VMSize
    $VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $VMName -Credential $VMCredential -ProvisionVMAgent -EnableAutoUpdate
    $VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id
    $VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2022-Datacenter' -Version latest

    # Create the virtual machine
    New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $VirtualMachine -ErrorAction Stop
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