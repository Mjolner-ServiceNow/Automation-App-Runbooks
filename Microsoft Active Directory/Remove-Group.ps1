<#
.SYNOPSIS
    Removes an Active Directory group.

.DESCRIPTION
    This runbook removes the specified Active Directory group using stored credentials and domain
    settings from Azure Automation. It requires the ActiveDirectory module (RSAT-AD-PowerShell)
    and proper Azure Automation variables/credentials to be configured.

.PARAMETER GroupName
    The sAMAccountName (group name) or distinguished name of the group to remove. Example: "Staff".

.EXAMPLE
    .\Remove-Group.ps1 -GroupName "Staff"

.NOTES
    Author: Mjølner Informatics AS
    Requires: ActiveDirectory module, Azure Automation stored credentials, PowerShell 7+
#>
param (
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
$Domain = Get-AutomationVariable -Name "DomainName"                   # Name of the domain. Example: "mydomain.local"
$DomainController = Get-AutomationVariable -Name "DomainController"   # IP or FQDN of Domain Controller
$Credentials = Get-AutomationPSCredential -Name "DomainCredentials"   # Stored credentials for Domain Controller
#endregion

#region Main Script
try {
    # Initialize metadata
    $Metadata = @{
        StartTime     = Get-Date
        GroupName     = $GroupName
        Domain        = $Domain
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

    # Confirm group exists
    $Group = Get-ADGroup -Identity $GroupName -Server $DomainController -Credential $Credentials -ErrorAction SilentlyContinue
    if (-not $Group) {
        throw "The group does not exist or was not found"
    }

    # Remove the group
    Remove-ADGroup -Credential $Credentials -Identity $Group -Server $DomainController -Confirm:$false

    Write-Verbose "Group removed successfully"
}
catch {
    $ErrorMessage = "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    Write-Error -Message $ErrorMessage -ErrorAction Continue
    throw
}
finally {
  if ($Group) {
        $RuntimeSeconds = (([DateTime]::Now) - $Metadata.StartTime).TotalSeconds
        Write-Verbose "Runbook completed successfully. Total runtime: $RuntimeSeconds seconds"

        # Output results as JSON
        $Group | Select-Object -Property SamAccountName, DistinguishedName, ObjectClass | ConvertTo-Json -WarningAction SilentlyContinue
    }

    # Uncomment next line if metadata output is required
    # $Metadata | ConvertTo-Json -WarningAction SilentlyContinue
}
#endregion