param (
  [Parameter(Mandatory=$true)]
	[string] $username
)

# Use the following verbose setting to enable verbose output
#$VerbosePreference = "Continue"
$PSStyle.OutputRendering = 'PlainText'

# * Environment variabels * #
# Set the below to match your environment #
$domain = "" #Name of the domain to add the user to
$domainController = "" #IP or FQDN of Domain Controller
$credentialsName = "" #Name of stored credentials to use for authentication with Domain Controller

### Script ###
try 
{
  $metadata = @{
    startTime = Get-Date
    username = $username
    domain = $domain
  }
  
  Write-Verbose "Runbook started - $($metadata.startTime)"
  
  if (Get-Module -ListAvailable -Name "ActiveDirectory") 
  {
    Write-Verbose "Found ActiveDirectory module"
  } 
  else 
  {
    Write-Verbose "Did not find Active Directory module. Trying to install the RSAT-AD-PowerShell Windows Feature"
    Install-WindowsFeature RSAT-AD-PowerShell
  }

  $credentials = Get-AutomationPSCredential -Name $credentialsName
  $userPrincipalName = $username + "@" + $domain

  $user = Get-ADUser -Filter "UserPrincipalName -eq '$userPrincipalName'" -ErrorAction SilentlyContinue
  if([String]::IsNullOrEmpty($user)) 
  {
      throw "User '$($UserPrincipalName)' not found"
  }
  
  $user = Enable-ADAccount -Credential $credentials -Identity $user -Server $domainController -PassThru
} 
catch 
{  
  $errorMessage = "Exception caught at line $($_.InvocationInfo.ScriptLineNumber), $($_.Exception.Message)"
} 
finally 
{
  if([String]::IsNullOrEmpty($errorMessage))
  {
    Write-Verbose "Runbook has completed. Total runtime $((([DateTime]::Now) - $($metadata.startTime)).TotalSeconds) Seconds"
    # Uncomment next line if metadata output is required
    #Write-Output $metadata | ConvertTo-Json -WarningAction SilentlyContinue
    Write-Output $user | Select-Object Enabled,SamAccountName,UserPrincipalName | ConvertTo-Json -WarningAction SilentlyContinue
  }
  else 
  {
    Write-Output $errorMessage
    throw
  }
}