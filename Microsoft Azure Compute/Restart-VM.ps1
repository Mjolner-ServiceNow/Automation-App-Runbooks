<#
.SYNOPSIS
    Restarts an Azure virtual machine.

.DESCRIPTION
    This runbook restarts an Azure virtual machine in the specified resource group.
    It requires stored credentials in Azure Automation for the Azure tenant.
    It requires the Az.Compute PowerShell module, which is installed automatically if not present.

.PARAMETER SubscriptionId
    The subscription ID to use for the Azure virtual machine.

.PARAMETER VMName
    The name of the virtual machine to restart.

.PARAMETER ResourceGroupName
    The name of the resource group containing the virtual machine.

.EXAMPLE
    .\Restart-VM.ps1 -VMName "MyVM" -ResourceGroupName "MyResourceGroup"

.NOTES
    Author: Mjølner Informatics AS
    Requires: Az.Compute PowerShell module
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
    [string]$ResourceGroupName
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
#$TenantID = Get-AutomationVariable -Name "TenantID"                     # Tenant ID for the Azure tenant
#$SubscriptionID = Get-AutomationVariable -Name "SubscriptionID"         # Subscription ID to target
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

    # Restart the virtual machine
    $OperationResult = Restart-AzVM -Name $VMName -ResourceGroupName $ResourceGroupName -ErrorAction Stop

    Write-Verbose "Virtual machine restarted successfully"
}
catch {
    $ErrorMessage = "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    Write-Error -Message $ErrorMessage -ErrorAction Continue
    throw
}
finally {
    # Calculate and output results
    if ($OperationResult) {
        $RuntimeSeconds = (([DateTime]::Now) - $Metadata.StartTime).TotalSeconds
        Write-Verbose "Runbook completed successfully. Total runtime: $RuntimeSeconds seconds"

        # Output operation result as JSON
        $OperationResult | Select-Object -Property Status, StartTime, EndTime | ConvertTo-Json -WarningAction SilentlyContinue

        # Uncomment next line if metadata output is required
        # $Metadata | ConvertTo-Json -WarningAction SilentlyContinue
    }
}
#endregion