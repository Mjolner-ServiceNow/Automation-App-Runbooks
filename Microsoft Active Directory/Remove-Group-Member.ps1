<#
.SYNOPSIS
    Removes a user from an Active Directory group.

.DESCRIPTION
    This runbook removes the specified user from the specified Active Directory group using stored
    credentials and domain settings from Azure Automation. It requires the ActiveDirectory module
    (RSAT-AD-PowerShell) and Azure Automation variables/credentials to be configured.

.PARAMETER Username
    The SAM account name (sAMAccountName) or UPN prefix of the user to remove. Example: "john".

.PARAMETER GroupName
    The name of the Active Directory group to remove the user from. Example: "Staff".

.EXAMPLE
    .\Remove-Group-Member.ps1 -Username "john" -GroupName "Staff"

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
    $GroupName
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

    # Get the group object. If not found an error will be thrown
    $Group = Get-ADGroup -Identity $GroupName -ErrorAction SilentlyContinue
    
    $Members = Remove-ADGroupMember -Credential $Credentials -Identity $Group -Members $User -Server $DomainController -Confirm:$false -PassThru

    Write-Verbose "Member(s) removed successfully"
}
catch {
    $ErrorMessage = "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    Write-Error -Message $ErrorMessage -ErrorAction Continue
    throw
}
finally {
    if ($Members) {
        $RuntimeSeconds = (([DateTime]::Now) - $Metadata.StartTime).TotalSeconds
        Write-Verbose "Runbook completed successfully. Total runtime: $RuntimeSeconds seconds"

        # Output results as JSON
        $Members | Select-Object -Property SamAccountName, DistinguishedName, ObjectClass | ConvertTo-Json -WarningAction SilentlyContinue

        # Uncomment next line if metadata output is required
        # $Metadata | ConvertTo-Json -WarningAction SilentlyContinue
    }
}
#endregion