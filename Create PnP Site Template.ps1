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

$listSite         = "https://envisionit.sharepoint.com/sites/infrastructure"
$TemplateFilename = "$PSScriptRoot\Environments.xml"

Connect-PnPOnline -Url $listSite -Interactive

Get-PnPSiteTemplate -out $TemplateFilename -Handlers Lists -ListsToExtract "Azure Excluded Emails", "Azure AD Group Mapping", "Azure AD Tenants", "Azure Subscriptions"
