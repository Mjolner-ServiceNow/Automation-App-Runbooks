<#
.SYNOPSIS
    Sets the password for a Microsoft Entra ID user.

.DESCRIPTION
    This runbook sets a new password for an existing Microsoft Entra ID user account.
    It requires stored credentials in Azure Automation for the Microsoft Entra ID tenant.
    It requires the Microsoft Graph PowerShell modules for managing users and groups, which is installed automatically if not present.

.PARAMETER UserPrincipalName
    The user principal name (UPN) of the user whose password will be changed. Example: "user@contoso.com"

.PARAMETER Password
    The new password to set for the user account.

.PARAMETER ForceChangePasswordNextSignIn
    If set to $true, the user will be required to change the password on next sign-in. Defaults to $false.

.EXAMPLE
    .\Set-EntraUserPassword.ps1 -UserPrincipalName "jane.doe@contoso.com" -Password "NewP@ssw0rd!" -ForceChangePasswordNextSignIn $true

.NOTES
    Author: Mjølner Informatics AS
    Requires: Microsoft Graph PowerShell modules
    Requires: Azure Automation stored credentials
    Requires: Powershell 7+
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$UserPrincipalName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Password,

    [Parameter(Mandatory = $false)]
    [bool]$ForceChangePasswordNextSignIn = $false
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
    $User = Get-MgUser -Filter "userPrincipalName eq '$UserPrincipalName'" -Property Id, DisplayName, UserPrincipalName
    if ($null -eq $User) {
        throw "Cannot find user. The user '$UserPrincipalName' does not exist."
    }

    # Set the new password
    Write-Verbose "Changing password"
    $userPassword = ConvertTo-SecureString $password -AsPlainText -Force
    Update-MgUser -UserId $User.Id -PasswordProfile @{
        Password                      = $userPassword
        ForceChangePasswordNextSignIn = $ForceChangePasswordNextSignIn
    } -ErrorAction Stop
    Write-Verbose "Password changed successfully"
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
