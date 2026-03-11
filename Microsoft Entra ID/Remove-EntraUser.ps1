<#
.SYNOPSIS
    Removes a Microsoft Entra ID user.

.DESCRIPTION
    This runbook removes a Microsoft Entra ID user account with the specified user principal name.
    It requires stored credentials in Azure Automation for the Microsoft Entra ID tenant.
    It requires the Microsoft Graph PowerShell modules for managing users and groups, which is installed automatically if not present.

.PARAMETER UserPrincipalName
    The user principal name (UPN) of the user to remove. Example: "user@contoso.com"

.EXAMPLE
    .\Remove-EntraUser.ps1 -UserPrincipalName "jane.doe@contoso.com"

.NOTES
    Author: Mjølner Informatics AS
    Requires: Microsoft Graph PowerShell modules
    Requires: Azure Automation stored credentials
    Requires: Powershell 7+
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$UserPrincipalName
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
$TenantID = Get-AutomationVariable -Name "TenantID"                        # Tenant ID for the Microsoft Entra ID tenant
$Credentials = Get-AutomationPSCredential -Name "AccountOperatorEntraID"   # Name of stored credentials to use for authentication with Microsoft Graph
#endregion

Write-Verbose "Loaded Automation variables for Entra authentication"

#region Main Script
try {
    # Initialize metadata
    $Metadata = @{
        StartTime         = Get-Date
        UserPrincipalName = $UserPrincipalName
    }

    Write-Verbose "Runbook started - $($Metadata.StartTime)"

    # Verify Validate Requried Powershell Modules
    $PowershellModules = @(
        @{
            Name        = "Microsoft.Graph.Authentication"
            Type        = "PowershellModule"
            FeatureName = $null
        }
        @{
            Name        = "Microsoft.Graph.Users"
            Type        = "PowershellModule"
            FeatureName = $null
        }
        @{
            Name        = "Microsoft.Graph.Identity.DirectoryManagement"
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
        throw "Entra Credentials not provided in Automation Account. No Entra connection will be available"
    }

    # Connect to Microsoft Graph
    try {
        Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $Credentials -ContextScope Process -NoWelcome
    }
    catch {
        throw "Unable to connect to Microsoft Graph. Make sure the provided user credential has access to the tenant and the required permissions."
    }
    #endregion

    # Get the user
    $User = Get-MgUser -Filter "userPrincipalName eq '$UserPrincipalName'"
    if ($null -eq $User) {
        throw "User '$UserPrincipalName' not found in Entra ID"
    }

    # Remove the user
    Remove-MgUser -UserId $User.Id -ErrorAction Stop

    Write-Verbose "User removed successfully"
}
catch {
    $ErrorMessage = "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    Write-Error -Message $ErrorMessage -ErrorAction Continue
    throw
}
finally {
    # Calculate and output results
    if ($User) {
        $RuntimeSeconds = (([DateTime]::Now) - $Metadata.StartTime).TotalSeconds
        Write-Verbose "Runbook completed successfully. Total runtime: $RuntimeSeconds seconds"

        # Output user details as JSON
        $User | Select-Object -Property DisplayName, UserPrincipalName | ConvertTo-Json -WarningAction SilentlyContinue

        # Uncomment next line if metadata output is required
        # $Metadata | ConvertTo-Json -WarningAction SilentlyContinue
    }
}
#endregion
