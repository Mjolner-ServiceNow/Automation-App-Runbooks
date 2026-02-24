<#
.SYNOPSIS
    Adds a user to an Active Directory group.

.DESCRIPTION
    This runbook adds a user to an Active Directory security group by username and group name.
    It requires stored credentials in Azure Automation for the domain controller.

.PARAMETER Username
    The username of the Active Directory account to add to the group.
    This parameter accepts a string value and cannot be empty.

.PARAMETER GroupName
    The name of the Active Directory group to add the user to.
    This parameter accepts a string value and cannot be empty.

.EXAMPLE
    .\New-Group-Member.ps1 -Username "john" -GroupName "Marketing"

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
$Domain = Get-AutomationVariable -Name "DomainName"                   # Name of the domain to add the user to Example: "mydomain.local"
$DomainController = Get-AutomationVariable -Name "DomainController"   # IP or FQDN of Domain Controller
$Credentials = Get-AutomationPSCredential -Name "DomainCredentials"   # Name of stored credentials to use for authentication with Domain Controller
#endregion

#region Main Script
try {
    # Initialize metadata
    $Metadata = @{
        StartTime = Get-Date
        Username  = $Username
        GroupName = $GroupName
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
    
    # Retrieve group account
    $GetADGroupParams = @{
        Filter      = "Name -eq '$GroupName'"
        Server      = $DomainController
        Credential  = $Credentials
        ErrorAction = 'SilentlyContinue'
    }
    $Group = Get-ADGroup @GetADGroupParams
    
    if (-not $Group) {
        throw "Group '$GroupName' not found in Active Directory"
    }
    
    # Add user to group
    $AddADGroupMemberParams = @{
        Identity    = $Group
        Members     = $User
        Server      = $DomainController
        Credential  = $Credentials
        Confirm     = $false
        PassThru    = $true
    }
    $GroupMember = Add-ADGroupMember @AddADGroupMemberParams
    
    Write-Verbose "User added to group successfully"
}
catch {
    $ErrorMessage = "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    Write-Error -Message $ErrorMessage -ErrorAction Continue
    throw
}
finally {
    # Calculate and output results
    if ($User -and $Group) {
        $RuntimeSeconds = (([DateTime]::Now) - $Metadata.StartTime).TotalSeconds
        Write-Verbose "Runbook completed successfully. Total runtime: $RuntimeSeconds seconds"
        
        # Output group and user details as JSON
        @{
            Group = ($Group | Select-Object -Property Name, DistinguishedName)
            User  = ($User | Select-Object -Property SamAccountName, UserPrincipalName)
        } | ConvertTo-Json -WarningAction SilentlyContinue

        # Uncomment next line if metadata output is required
        # $Metadata | ConvertTo-Json -WarningAction SilentlyContinue
    }
}
#endregion
