<#
.SYNOPSIS
    Removes an Azure virtual machine.

.DESCRIPTION
    This runbook removes an Azure virtual machine in the specified resource group,
    along with its associated managed disks (OS and data disks), network interfaces,
    Network Security Groups attached to those interfaces, and public IP addresses.
    It requires stored credentials in Azure Automation for the Azure tenant.
    It requires the Az.Compute and Az.Network PowerShell modules, which are installed automatically if not present.

.PARAMETER SubscriptionId
    The subscription ID to use for the Azure virtual machine.

.PARAMETER VMName
    The name of the virtual machine to remove.

.PARAMETER ResourceGroupName
    The name of the resource group containing the virtual machine.

.PARAMETER RemoveAssociatedResources
    Optional switch to indicate whether associated resources (managed disks and network interfaces) should also be removed. Default is $true.

.EXAMPLE
    .\Remove-VM.ps1 -VMName "MyVM" -ResourceGroupName "MyResourceGroup"

.NOTES
    Author: Mjølner Informatics AS
    Requires: Az.Compute PowerShell module
    Requires: Az.Network PowerShell module
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

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [bool]$RemoveAssociatedResources = $true
    
)

# Set error handling
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Set output rendering to plain text if PSStyle is available (PS 7.2+)
if ($PSVersionTable.PSVersion.Minor -ge 2) {
    $PSStyle.OutputRendering = 'PlainText'
}

#region Variables
# Set variables in Azure Automation if required for your environment. The below variables are examples and may not be required depending on your authentication method.
#$Credentials = Get-AutomationPSCredential -Name "AccountOperatorAzure"  # Name of stored credentials to use for authentication with Azure
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

    # Get Credential Object from Automation Account. The below section are examples and may not be required depending on your authentication method.
    #if ($null -eq $Credentials) {
    #    throw "Azure Credentials not provided in Automation Account. No Azure connection will be available"
    #}

    # Connect to Azure
    try {
        Connect-AzAccount -Identity | Out-Null
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    }
    catch {
        throw "Unable to connect to Azure. Make sure the provided credentials have access to the tenant and the required permissions."
    }
    #endregion

    # Get VM object to collect associated resources before removal
    $VM = Get-AzVM -Name $VMName -ResourceGroupName $ResourceGroupName -ErrorAction Stop

    # Collect disk information
    $OsDisk   = $VM.StorageProfile.OsDisk
    $DataDisks = $VM.StorageProfile.DataDisks

    # Collect NIC IDs and resolve associated NSG IDs from each NIC object
    $NicIds = $VM.NetworkProfile.NetworkInterfaces | Select-Object -ExpandProperty Id
    $NsgIds = @()
    $PublicIpIds = @()
    foreach ($NicId in $NicIds) {
        $NicName   = $NicId.Split('/')[-1]
        $NicRg     = ($NicId -split '/resourceGroups/')[1].Split('/')[0]
        $NicObject = Get-AzNetworkInterface -Name $NicName -ResourceGroupName $NicRg -ErrorAction SilentlyContinue
        if ($NicObject -and $NicObject.NetworkSecurityGroup) {
            $NsgIds += $NicObject.NetworkSecurityGroup.Id
        }
        foreach ($IpConfig in $NicObject.IpConfigurations) {
            if ($IpConfig.PublicIpAddress) {
                $PublicIpIds += $IpConfig.PublicIpAddress.Id
            }
        }
    }

    Write-Verbose "Found OS disk: $($OsDisk.Name)"
    Write-Verbose "Found $($DataDisks.Count) data disk(s)"
    Write-Verbose "Found $($NicIds.Count) network interface(s)"
    Write-Verbose "Found $($NsgIds.Count) network security group(s)"
    Write-Verbose "Found $($PublicIpIds.Count) public IP address(es)"

    # Remove the virtual machine
    $OperationResult = Remove-AzVM -Name $VMName -ResourceGroupName $ResourceGroupName -Force -ErrorAction Stop

    Write-Verbose "Virtual machine removed successfully"

    if ($RemoveAssociatedResources) {
        # Remove network interfaces
        foreach ($NicId in $NicIds) {
            $NicName = $NicId.Split('/')[-1]
            $NicRg   = ($NicId -split '/resourceGroups/')[1].Split('/')[0]
            Write-Verbose "Removing network interface: $NicName"
            Remove-AzNetworkInterface -ResourceGroupName $NicRg -Name $NicName -Force -ErrorAction Stop
            Write-Verbose "Network interface removed: $NicName"
        }

        # Remove public IP addresses
        foreach ($PublicIpId in $PublicIpIds) {
            $PublicIpName = $PublicIpId.Split('/')[-1]
            $PublicIpRg   = ($PublicIpId -split '/resourceGroups/')[1].Split('/')[0]
            Write-Verbose "Removing public IP address: $PublicIpName"
            Remove-AzPublicIpAddress -ResourceGroupName $PublicIpRg -Name $PublicIpName -Force -ErrorAction Stop
            Write-Verbose "Public IP address removed: $PublicIpName"
        }

        # Remove network security groups
        foreach ($NsgId in $NsgIds) {
            $NsgName = $NsgId.Split('/')[-1]
            $NsgRg   = ($NsgId -split '/resourceGroups/')[1].Split('/')[0]
            Write-Verbose "Removing network security group: $NsgName"
            Remove-AzNetworkSecurityGroup -ResourceGroupName $NsgRg -Name $NsgName -Force -ErrorAction Stop
            Write-Verbose "Network security group removed: $NsgName"
        }

        # Remove OS disk
        if ($OsDisk.ManagedDisk) {
            $OsDiskName = $OsDisk.Name
            $OsDiskRg   = ($OsDisk.ManagedDisk.Id -split '/resourceGroups/')[1].Split('/')[0]
            Write-Verbose "Removing OS disk: $OsDiskName"
            Remove-AzDisk -ResourceGroupName $OsDiskRg -DiskName $OsDiskName -Force -ErrorAction Stop
            Write-Verbose "OS disk removed: $OsDiskName"
        }

        # Remove data disks
        foreach ($Disk in $DataDisks) {
            if ($Disk.ManagedDisk) {
                $DiskName = $Disk.Name
                $DiskRg   = ($Disk.ManagedDisk.Id -split '/resourceGroups/')[1].Split('/')[0]
                Write-Verbose "Removing data disk: $DiskName"
                Remove-AzDisk -ResourceGroupName $DiskRg -DiskName $DiskName -Force -ErrorAction Stop
                Write-Verbose "Data disk removed: $DiskName"
            }
        }
    }

} catch {
    $ErrorMessage = "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    Write-Error -Message $ErrorMessage -ErrorAction Continue
    throw

} finally {
    # Calculate and output results
    if ($OperationResult) {
        $RuntimeSeconds = (([DateTime]::Now) - $Metadata.StartTime).TotalSeconds
        Write-Verbose "Runbook completed successfully. Total runtime: $RuntimeSeconds seconds"

        # Output operation result as JSON
        $OperationResult | Select-Object -Property Status, StartTime, EndTime, VMName, ResourceGroupName | ConvertTo-Json -WarningAction SilentlyContinue

        # Uncomment next line if metadata output is required
        # $Metadata | ConvertTo-Json -WarningAction SilentlyContinue
    }
}
#endregion