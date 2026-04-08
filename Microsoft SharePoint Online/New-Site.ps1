<#
.SYNOPSIS
    Creates a new SharePoint Online communication site.

.DESCRIPTION
    This runbook creates a new SharePoint Online communication site with the specified name, title, and owner.
    It requires stored Automation variables in Azure Automation for the client ID, certificate, certificate password,
    tenant name, and base SharePoint URL.
    It requires the PnP.PowerShell module, which is installed automatically if not present.

.PARAMETER SiteName
    The name of the SharePoint site to create. Used as the URL slug, e.g. "my-site" results in
    https://<tenant>.sharepoint.com/sites/my-site.

.PARAMETER SiteTitle
    The display title of the SharePoint site.

.PARAMETER Owner
    The UPN (email address) of the user to set as the primary site owner.

.EXAMPLE
    .\New-Site.ps1 -SiteName "my-site" -SiteTitle "My Site" -Owner "john.doe@contoso.com"

.NOTES
    Author: Mjølner Informatics AS
    Requires: PnP.PowerShell module
    Requires: Azure Automation variables for client ID, certificate, certificate password, tenant name, and SharePoint URL
    Requires: PowerShell 7+
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SiteName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SiteTitle,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Owner
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
$ClientIdVariableName      = ""  # Name of the Automation variable containing the app registration client ID
$CertificateVariableName   = ""  # Name of the Automation variable containing the base64-encoded PFX certificate
$CertificatePWVariableName = ""  # Name of the Automation variable containing the PFX certificate password
$TenantVariableName        = ""  # Name of the Automation variable containing the tenant name, e.g. "contoso.onmicrosoft.com"
$SharePointURLVariableName = ""  # Name of the Automation variable containing the base SharePoint URL, e.g. "https://contoso.sharepoint.com"
#endregion

Write-Verbose "Loaded Automation variables for SharePoint authentication"

#region Main Script
try {
    # Initialize metadata
    $Metadata = @{
        StartTime  = Get-Date
        SiteName   = $SiteName
        SiteTitle  = $SiteTitle
    }

    Write-Verbose "Runbook started - $($Metadata.StartTime)"

    # Verify and install required PowerShell modules
    $PowershellModules = @(
        @{
            Name        = "PnP.PowerShell"
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

    # Retrieve Automation variables
    $ClientId        = Get-AutomationVariable -Name $ClientIdVariableName
    $EncodedPfx      = Get-AutomationVariable -Name $CertificateVariableName
    $CertificatePW   = ConvertTo-SecureString -String (Get-AutomationVariable -Name $CertificatePWVariableName) -AsPlainText -Force
    $Tenant          = Get-AutomationVariable -Name $TenantVariableName
    $SharePointUrl   = Get-AutomationVariable -Name $SharePointURLVariableName
    $NewSiteUrl      = "$SharePointUrl/sites/$SiteName"

    # Connect to SharePoint Online
    try {
        Connect-PnPOnline -Url $SharePointUrl -ClientId $ClientId -Tenant $Tenant -CertificateBase64Encoded $EncodedPfx -CertificatePassword $CertificatePW -ErrorAction Stop
    }
    catch {
        throw "Unable to connect to SharePoint Online. Make sure the provided credentials have access to the tenant and the required permissions."
    }

    Write-Verbose "Creating new communication site with URL: $NewSiteUrl"

    # Create the SharePoint communication site
    $NewSite = New-PnPSite -Type CommunicationSite -Title $SiteTitle -Url $NewSiteUrl -Lcid 1033 -Owner $Owner -Wait -ErrorAction Stop

    Write-Verbose "SharePoint site created successfully: $NewSite"

    Disconnect-PnPOnline
}
catch {
    $ErrorMessage = "Exception at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    Write-Error -Message $ErrorMessage -ErrorAction Continue
    throw
}
finally {
    # Calculate and output results
    if ($NewSite) {
        $RuntimeSeconds = (([DateTime]::Now) - $Metadata.StartTime).TotalSeconds
        Write-Verbose "Runbook completed successfully. Total runtime: $RuntimeSeconds seconds"

        # Output site details as JSON
        [PSCustomObject]@{
            SiteName  = $SiteName
            SiteTitle = $SiteTitle
            SiteUrl   = $NewSite
            Owner     = $Owner
        } | ConvertTo-Json -WarningAction SilentlyContinue

        # Uncomment next line if metadata output is required
        # $Metadata | ConvertTo-Json -WarningAction SilentlyContinue
    }
}
#endregion