<#
.SYNOPSIS
    Sets the password for an Active Directory user account.

.DESCRIPTION
    This runbook sets the password for the specified Active Directory user account using stored
    credentials and domain settings from Azure Automation. It optionally forces the user to change
    the password at next logon. Requires the ActiveDirectory module (RSAT-AD-PowerShell).

.PARAMETER Username
    The username (SAM Account Name) or UPN prefix of the user. Example: "john".

.PARAMETER Password
    The new password for the user account. This parameter accepts a string value and cannot be empty.

.PARAMETER ChangePasswordAtLogon
    Optional flag to force the user to change the password at next logon. Default is $false.

.EXAMPLE
    .\Set-User-Password.ps1 -Username "john" -Password "NewP@ssw0rd123" -ChangePasswordAtLogon $true

.NOTES
    Author: Mjølner Informatics AS
    Requires: ActiveDirectory module, Azure Automation stored credentials, PowerShell 7+
#>
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Username,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Password,

    [Parameter(Mandatory = $false)]
    [bool]
    $ChangePasswordAtLogon = $false
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
    $UserPassword = ConvertTo-SecureString -String $Password -AsPlainText -Force

    $User = Get-ADUser -Credential $Credentials -Server $DomainController -Filter "UserPrincipalName -eq '$UserPrincipalName'" -Properties PasswordNeverExpires -ErrorAction SilentlyContinue
    if (-not $User) {
        throw "The user does not exist"
    }

    if ($ChangePasswordAtLogon) {
        # Check if PasswordNeverExpires is enabled, as it will prevent the user from being prompted to change the password at logon
        if ($User.PasswordNeverExpires) {
            Write-Verbose "PasswordNeverExpires is enabled for this user. Disabling it to allow password change at logon."
            $User = Set-ADUser -Credential $Credentials -Identity $User -PasswordNeverExpires $false -Server $DomainController -PassThru
        }
        $User = Set-ADUser -Credential $Credentials -Identity $User -ChangePasswordAtLogon $true -Server $DomainController -PassThru
    }
    else {
      # Set the new password without forcing change at logon
       $User = Set-ADAccountPassword -Credential $Credentials -Identity $User -NewPassword $UserPassword -Server $DomainController -Reset -PassThru
    }

    Write-Verbose "Password changed successfully"
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
        $User | Select-Object -Property SamAccountName, UserPrincipalName, Enabled | ConvertTo-Json -WarningAction SilentlyContinue

        # Uncomment next line if metadata output is required
        # $Metadata | ConvertTo-Json -WarningAction SilentlyContinue
    }
}
#endregion