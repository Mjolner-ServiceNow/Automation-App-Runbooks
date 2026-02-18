<#
.SYNOPSIS
    Creates a new Active Directory group.

.DESCRIPTION
    This runbook creates a new Active Directory security group with the specified properties.
    It requires stored credentials in Azure Automation for the domain controller.
    It requires the ActiveDirectory PowerShell module, which is installed automatically if not present.
    It requires Environment Variables to be set for the domain, domain controller, and credentials.

.PARAMETER Name
    The name for the group (the pre-Windows 2000 group name).
    This parameter accepts a string value and cannot be empty.

.PARAMETER DisplayName
    The display name for the group. If not provided, defaults to the Name.
    This parameter is optional.

.PARAMETER Description
    The description for the group. This parameter is optional.

.PARAMETER Path
    Specifies the X.500 path of the Organizational Unit (OU) or container where the new object is created.
    Example: 'OU=Management,OU=Groups,DC=YourDomain,DC=Local'

.PARAMETER GroupScope
    The scope of the group. Valid values are "Universal", "Global", or "DomainLocal". This parameter is required.

.EXAMPLE
    .\New-Group.ps1 -Name "Marketing" -Description "Marketing department group" -path "OU=Management,OU=Groups,DC=YourDomain,DC=Local" -GroupScope "Global"

.NOTES
    Author: Mjølner Informatics AS
    Requires: ActiveDirectory module
    Requires: Azure Automation stored credentials
    Requires: Powershell 7+
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [Parameter(Mandatory = $false)]
    [string]$DisplayName,
    
    [Parameter(Mandatory = $false)]
    [string]$Description = "",
    
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Universal", "Global", "DomainLocal")]
    [string]$GroupScope
        
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
        StartTime      = Get-Date
        Name           = $Name
        Domain         = $Domain
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
    
    # Set defaults for optional parameters    
    if (-not $DisplayName) {
        $DisplayName = $Name
    }
    
    
    # Create the group
    $NewADGroupParams = @{
        Name           = $Name
        DisplayName    = $DisplayName
        Description    = $Description
        Path           = $Path
        GroupScope     = $GroupScope
        Server         = $DomainController
        Credential     = $Credentials
        PassThru       = $true
    }
    $Group = New-ADGroup @NewADGroupParams
    
    Write-Verbose "Group created successfully"
}
catch {
    $ErrorMessage = "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    Write-Error -Message $ErrorMessage -ErrorAction Continue
    throw
}
finally {
    # Calculate and output results
    if ($Group) {
        $RuntimeSeconds = (([DateTime]::Now) - $Metadata.StartTime).TotalSeconds
        Write-Verbose "Runbook completed successfully. Total runtime: $RuntimeSeconds seconds"
        
        # Output group details as JSON
        $Group | Select-Object -Property Name, Description, DistinguishedName | ConvertTo-Json -WarningAction SilentlyContinue
    }
}
#endregion
