<#
.SYNOPSIS
    Add an account to Microsoft Entra ID group.

.DESCRIPTION
    This runbook adds an account to a Microsoft Entra ID security group with the specified properties.
    It requires stored credentials in Azure Automation for the Microsoft Entra ID tenant.
    It requires the Microsoft Graph PowerShell modules for managing users and groups, which is installed automatically if not present.
    
.PARAMETER UserName
    The user name to add to the group.

.PARAMETER GroupName
    The name of the group to add the user to.

.EXAMPLE
    .\New-EntraGroup.ps1 -Name "Marketing" -Description "Marketing department group"

.NOTES
    Author: Mjølner Informatics AS
    Requires: Microsoft Graph PowerShell modules
    Requires: Azure Automation stored credentials
    Requires: Powershell 7+
#>

param (
    [Parameter(Mandatory = $false)]
    [string]$UserName,
    
    [Parameter(Mandatory = $false)]
    [string]$GroupName
    
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
$TenantID = Get-AutomationVariable -Name "TenantID"                   # Name of the domain to add the user to Example: "mydomain.local"
$Credentials = Get-AutomationPSCredential -Name "AccountOperatorEntraID"   # Name of stored credentials to use for authentication with Microsoft Graph
#endregion

Write-Output $TenantID
Write-Output $Credentials.UserName

#region Main Script
try {
    # Initialize metadata
    $Metadata = @{
        StartTime = Get-Date
        Name      = $Name
        Domain    = $Domain
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
        Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $Credentials -ContextScope CurrentUser -NoWelcome 
    }
    catch { 
        throw "Unable to connect to Microsoft Graph. Make sure the provided user credential has access to the tenant and the required permissions."
    }
    #endregion


    # Get the user
    $User = Get-MgUser -Filter "userPrincipalName eq '$UserName'"

    # Get the group
    $Group = Get-MgGroup -Filter "displayName eq '$GroupName'"


    # Add the user to the group
    New-MgGroupMember -GroupId $Group.Id -UserId $User.Id

    Write-Verbose "User added to Group"
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
        
        # Output group details as JSON
        $User | ConvertTo-Json -WarningAction SilentlyContinue

        # Uncomment next line if metadata output is required
        # $Metadata | ConvertTo-Json -WarningAction SilentlyContinue
    }
}
#endregion
