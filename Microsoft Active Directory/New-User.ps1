<#
.SYNOPSIS
    Creates a new Active Directory user account.

.DESCRIPTION
    This runbook creates a new Active Directory user account with the specified properties.
    It requires stored credentials in Azure Automation for the domain controller.
    It requires the ActiveDirectory PowerShell module, which is installed automatically if not present.
    It requires Environment Variables to be set for the domain, domain controller, and credentials.

.PARAMETER Username
    The username (SAM Account Name) for the new Active Directory user account.
    This parameter accepts a string value and cannot be empty.

.PARAMETER Password
    The password for the new Active Directory user account.
    This parameter accepts a string value and cannot be empty.

.PARAMETER Firstname
    The first name of the new user.
    This parameter accepts a string value and cannot be empty.

.PARAMETER Lastname
    The last name of the new user.
    This parameter accepts a string value and cannot be empty.

.PARAMETER Path
    Specifies the X.500 path of the Organizational Unit (OU) or container where the new object is created.
    Example: 'OU=Management,OU=Groups,DC=YourDomain,DC=Local'
    If no path provided defaults to 'CN=Users,DC=YourDomain,DC=Local'

.EXAMPLE
    .\New-User.ps1 -Username "john" -Password "P@ssw0rd123" -Firstname "John" -Lastname "Hansen" -Path "CN=Users,DC=YourDomain,DC=Local"

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
    $Password,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Firstname,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Lastname,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Path
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

    # Set defaults for optional parameters    
    if (-not $Path) {
        $Path = "CN=Users,DC=$($Domain.Split('.')[0]),DC=$($Domain.Split('.')[1])"    }
    

    # Build user properties
    $DisplayName = "$Firstname $Lastname"
    $UserPrincipalName = "$Username@$Domain"
    $UserPassword = ConvertTo-SecureString -String $Password -AsPlainText -Force

    # Create new user account
    $NewADUserParams = @{
        SamAccountName             = $Username
        UserPrincipalName          = $UserPrincipalName
        DisplayName                = $DisplayName
        GivenName                  = $Firstname
        Surname                    = $Lastname
        Name                       = $DisplayName
        AccountPassword            = $UserPassword
        ChangePasswordAtLogon      = $false
        Enabled                    = $true
        Path                       = $Path
        Server                     = $DomainController
        Credential                 = $Credentials
        PassThru                   = $true
    }

    $User = New-ADUser @NewADUserParams

    Write-Verbose "User account created successfully"
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
        $User | Select-Object -Property SamAccountName, UserPrincipalName, Enabled | ConvertTo-Json -WarningAction SilentlyContinue

        # Uncomment next line if metadata output is required
        # $Metadata | ConvertTo-Json -WarningAction SilentlyContinue
    }
}
#endregion
