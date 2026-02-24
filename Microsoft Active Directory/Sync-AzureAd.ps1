<#
.SYNOPSIS
    Syncs Active Directory with Azure AD using Azure AD Connect.

.DESCRIPTION
    This runbook triggers a delta sync cycle on the Azure AD Connect server to synchronize
    on-premises Active Directory with Azure Active Directory. It uses stored credentials and
    server information from Azure Automation.

.EXAMPLE
    .\Sync-AzureAd.ps1

.NOTES
    Author: Mjølner Informatics AS
    Requires: Azure Automation stored credentials, PowerShell 7+, Azure AD Connect on sync server, SyncServerName variable configured in Azure Automation
#>

# Set error handling
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Set output rendering to plain text if PSStyle is available (PS 7.2+)
if ($PSVersionTable.PSVersion.Minor -ge 2) {
    $PSStyle.OutputRendering = 'PlainText'
}

#region Variables
# Set variables in Azure Automation for the below values to match your environment
$SyncServerName = Get-AutomationVariable -Name "SyncServerName"       # Name of variable that stores the IP or FQDN of Sync Server with Azure AD Connect
$Credentials = Get-AutomationPSCredential -Name "DomainCredentials"   # Name of stored credentials to use for authentication with Sync Server
#endregion

#region Main Script
try {
    # Initialize metadata
    $Metadata = @{
        StartTime = Get-Date
    }

    Write-Verbose "Runbook started - $($Metadata.StartTime)"

    Invoke-Command -ComputerName $SyncServerName -Credential $Credentials -ScriptBlock {
        Import-Module ADSync
        Start-ADSyncSyncCycle -PolicyType Delta
    } -ErrorVariable errmsg

    if ($errmsg) {
        throw $errmsg
    }

    Write-Verbose "Delta sync cycle completed successfully"
}
catch {
    $ErrorMessage = "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    Write-Error -Message $ErrorMessage -ErrorAction Continue
    throw
}
finally {
    $RuntimeSeconds = (([DateTime]::Now) - $Metadata.StartTime).TotalSeconds
    Write-Verbose "Runbook completed. Total runtime: $RuntimeSeconds seconds"

    # Output metadata as JSON
    $Metadata | ConvertTo-Json -WarningAction SilentlyContinue
}
#endregion