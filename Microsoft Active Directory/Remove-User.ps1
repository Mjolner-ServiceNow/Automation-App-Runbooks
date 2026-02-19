<#
.SYNOPSIS
    Removes an Active Directory user account.

.DESCRIPTION
    This runbook removes an Active Directory user account by username.
    It requires stored credentials in Azure Automation for the domain controller.
    It requires the ActiveDirectory PowerShell module, which is installed automatically if not present.
    It requires Environment Variables to be set for the domain, domain controller, and credentials.

.PARAMETER Username
    The username of the Active Directory account to remove.
    This parameter accepts a string value and cannot be empty.

.EXAMPLE
    .\Remove-User.ps1 -Username "john"

.NOTES
    Author: Mjølner Informatics AS
    Requires: ActiveDirectory module
    Requires: Azure Automation stored credentials
    Requires: Powershell 7+
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Username
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
$Domain = Get-AutomationVariable -Name "DomainName"                   # Name of the domain to remove the user from. Example: "mydomain.local"
$DomainController = Get-AutomationVariable -Name "DomainController"   # IP or FQDN of Domain Controller
$Credentials = Get-AutomationPSCredential -Name "DomainCredentials"   # Name of stored credentials to use for authentication with Domain Controller
#endregion

#region Main Script
try {
    # Initialize metadata
    $Metadata = @{
        StartTime = Get-Date
        Username  = $Username
        Domain    = $Domain
    }

    Write-Verbose "Runbook started - $($Metadata.StartTime)"

    # Verify ActiveDirectory module availability
    if (-not (Get-Module -ListAvailable -Name "ActiveDirectory")) {
        Write-Verbose "ActiveDirectory module not found. Installing RSAT-AD-PowerShell..."
        Install-WindowsFeature -Name RSAT-AD-PowerShell -WarningAction SilentlyContinue | Out-Null
    }
    else {
        Write-Verbose "ActiveDirectory module found"
    }

    # Build user principal name
    $UserPrincipalName = "$Username@$Domain"

    # Retrieve user account
    $GetADUserParams = @{
        Filter      = "UserPrincipalName -eq '$UserPrincipalName'"
        Server      = $DomainController
        Credential  = $Credentials
        ErrorAction = 'SilentlyContinue'
    }
    $User = Get-ADUser @GetADUserParams

    if (-not $User) {
        throw "User '$UserPrincipalName' not found in Active Directory"
    }

    # Remove the user account
    $RemoveADUserParams = @{
        Identity    = $User
        Server      = $DomainController
        Credential  = $Credentials
        Confirm     = $false
    }
    Remove-ADUser @RemoveADUserParams

    Write-Verbose "User account removed successfully"
}
catch {
    $ErrorMessage = "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    Write-Error -Message $ErrorMessage -ErrorAction Continue
    throw
}
finally {
    # Calculate and output results
    $RuntimeSeconds = (([DateTime]::Now) - $Metadata.StartTime).TotalSeconds
    Write-Verbose "Runbook completed successfully. Total runtime: $RuntimeSeconds seconds"

    # Output metadata as JSON
    $Metadata | ConvertTo-Json -WarningAction SilentlyContinue
}
#endregion