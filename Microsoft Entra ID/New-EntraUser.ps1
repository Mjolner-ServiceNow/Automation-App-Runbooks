<#
.SYNOPSIS
    Creates a new Microsoft Entra ID user.

.DESCRIPTION
    This runbook creates a new Microsoft Entra ID user account with the specified properties.
    It requires stored credentials in Azure Automation for the Microsoft Entra ID tenant.
    It requires the Microsoft Graph PowerShell modules for managing users and groups, which is installed automatically if not present.

.PARAMETER DisplayName
    The display name for the user.

.PARAMETER UserPrincipalName
    The user principal name (UPN) for the user. Example: "user@contoso.com"

.PARAMETER GivenName
    The given (first) name of the user. This parameter is optional.

.PARAMETER Surname
    The surname (last name) of the user. This parameter is optional.

.PARAMETER Password
    The initial password for the user account. The user will be required to change the password on first sign-in.

.PARAMETER Department
    The department the user belongs to. This parameter is optional.

.PARAMETER JobTitle
    The job title of the user. This parameter is optional.

.EXAMPLE
    .\New-EntraUser.ps1 -DisplayName "Jane Doe" -UserPrincipalName "jane.doe@contoso.com" -Password "TempP@ssw0rd!"

.NOTES
    Author: Mjølner Informatics AS
    Requires: Microsoft Graph PowerShell modules
    Requires: Azure Automation stored credentials
    Requires: Powershell 7+
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DisplayName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$UserPrincipalName,

    [Parameter(Mandatory = $true)]
    [string]$GivenName = "",

    [Parameter(Mandatory = $true)]
    [string]$Surname = "",

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Password,

    [Parameter(Mandatory = $false)]
    [string]$Department = "",

    [Parameter(Mandatory = $false)]
    [string]$JobTitle = ""
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
$TenantID = Get-AutomationVariable -Name "TenantID"                        # Tenant ID for the Microsoft Entra ID tenant
$Credentials = Get-AutomationPSCredential -Name "AccountOperatorEntraID"   # Name of stored credentials to use for authentication with Microsoft Graph
#endregion

Write-Verbose "Loaded Automation variables for Entra authentication"

#region Main Script
try {
    # Initialize metadata
    $Metadata = @{
        StartTime         = Get-Date
        UserPrincipalName = $UserPrincipalName
        DisplayName       = $DisplayName
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
        Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $Credentials -ContextScope Process -NoWelcome
    }
    catch {
        throw "Unable to connect to Microsoft Graph. Make sure the provided user credential has access to the tenant and the required permissions."
    }
    #endregion

    # Check if user already exists
    $ExistingUser = Get-MgUser -Filter "userPrincipalName eq '$UserPrincipalName'" -ErrorAction SilentlyContinue
    if ($null -ne $ExistingUser) {
        throw "Cannot create user. A user with UserPrincipalName '$UserPrincipalName' already exists."
    }

    # Derive mail nickname from the local part of the UPN
    $MailNickname = $UserPrincipalName.Split("@")[0]

    # Create the user
    $NewEntraUser = @{
        DisplayName       = $DisplayName
        UserPrincipalName = $UserPrincipalName
        GivenName         = $GivenName
        Surname           = $Surname
        MailNickname      = $MailNickname
        AccountEnabled    = $true
        PasswordProfile   = @{
            Password                      = $Password
            ForceChangePasswordNextSignIn = $true
        }
    }

    if (-not [string]::IsNullOrEmpty($Department)) {
        $NewEntraUser['Department'] = $Department
    }
    if (-not [string]::IsNullOrEmpty($JobTitle)) {
        $NewEntraUser['JobTitle'] = $JobTitle
    }
    
    $User = New-MgUser @NewEntraUser -ErrorAction Stop

    Write-Verbose "User created successfully"
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
        $User | Select-Object -Property DisplayName, UserPrincipalName, GivenName, Surname, Department, JobTitle, Id | ConvertTo-Json -WarningAction SilentlyContinue

        # Uncomment next line if metadata output is required
        # $Metadata | ConvertTo-Json -WarningAction SilentlyContinue
    }
}
#endregion
