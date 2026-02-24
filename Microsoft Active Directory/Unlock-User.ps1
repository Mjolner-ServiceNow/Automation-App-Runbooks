<#
.SYNOPSIS
    Unlocks a locked Active Directory user account.

.DESCRIPTION
    This runbook unlocks the specified Active Directory user account that has been locked due to
    failed login attempts. It uses stored credentials and domain settings from Azure Automation.
    Requires the ActiveDirectory module (RSAT-AD-PowerShell).

.PARAMETER Username
    The username (SAM Account Name) or UPN prefix of the user to unlock. Example: "john".

.EXAMPLE
    .\Unlock-User.ps1 -Username "john"

.NOTES
    Author: Mjølner Informatics AS
    Requires: ActiveDirectory module, Azure Automation stored credentials, PowerShell 7+
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
$Domain = Get-AutomationVariable -Name "DomainName"                   # Name of the domain to add the user to. Example: "mydomain.local"
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

    $UserPrincipalName = "$Username@$Domain"

    $User = Get-ADUser -Credential $Credentials -Server $DomainController -Filter "UserPrincipalName -eq '$UserPrincipalName'" -ErrorAction SilentlyContinue
    if (-not $User) {
        throw "The user does not exist"
    }

    $User = Unlock-ADAccount -Credential $Credentials -Identity $User -Server $DomainController -PassThru

    Write-Verbose "User unlocked successfully"
}
catch {
    $ErrorMessage = "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    Write-Error -Message $ErrorMessage -ErrorAction Continue
    throw
}
finally {
    if ($User) {
        $RuntimeSeconds = (([DateTime]::Now) - $Metadata.StartTime).TotalSeconds
        Write-Verbose "Runbook completed successfully. Total runtime: $RuntimeSeconds seconds"

        # Output user details as JSON
        $User | Select-Object -Property SamAccountName, UserPrincipalName, Enabled, LockedOut | ConvertTo-Json -WarningAction SilentlyContinue

        # Uncomment next line if metadata output is required
        # $Metadata | ConvertTo-Json -WarningAction SilentlyContinue
    }
}
#endregion