<#
    Non-Prod Environment Guest Access

    Prerequisites:
        Install-Module AzureAD
        Install-Module AZ
        Install-Module CredentialManager

    Purpose:
    - Adds guest accounts and populates a local AAD group for administering non-prod Azure subscriptions and SharePoint site collections
    - Source user list is a group in the source tenant
    - Configuration of tenants, subscriptions, and site collections is in a SharePoint site in the source tenant
    - Users are also made global admins of the target tenants
#>

$TemplateFilename = "$PSScriptRoot\Environments.xml"

[string]$listSite = Read-Host "Enter the URL of the site to apply the template to"

Connect-PnPOnline -Url $listSite -Interactive

Invoke-PnPSiteTemplate -Path $TemplateFilename
