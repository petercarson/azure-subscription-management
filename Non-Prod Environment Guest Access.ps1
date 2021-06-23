<#
    Non-Prod Environment Guest Access

    Prerequisites:
        Install-Module AzureAD
        Install-Module AZ
        Install-Module PnP.PowerShell

    Purpose:
    - Adds guest accounts and populates a local AAD group for administering non-prod Azure subscriptions and SharePoint site collections
    - Source user list is a group in the source tenant
    - Configuration of tenants, subscriptions, and site collections is in a SharePoint site in the source tenant
    - Users are also made global admins of the target tenants
#>



function ReadConfiguration {
    param (
        [Parameter(Mandatory = $true)][string] $listSite,         # Source site that contains the configuration lists
        [Parameter(Mandatory = $true)][string] $staffGroupName    # Source AAD group that contains the users to setup
    )

    # Retrieve the content of the lists
    Write-Host "Connecting to the prod tenant"
    Connect-PnPOnline -Url $listSite -Interactive
    $Global:Tenants = Get-PnPListItem -List "Azure AD Tenants"
    $Global:Subscriptions = Get-PnPListItem -List "Azure Subscriptions"
    $Global:ExcludedEmails = Get-PnPListItem -List "Azure AD Excluded Emails"
    $Global:GroupMappings = Get-PnPListItem -List "Azure AD Group Mapping"

    [System.Collections.Generic.List[string]]$TargetTenants = @()
    foreach ($GroupMapping in $GroupMappings) {
        $TargetTenants.Add($GroupMapping.FieldValues["TargetTenant"].LookupValue)
    }
    $TargetTenants = $TargetTenants | sort-object -Unique

    # Get the members of the source AAD group
    Write-Output "Enter credentials for the prod AzureAD"
    Connect-AzureAD
    $staffGroup = Get-AzureADGroup -Filter "DisplayName eq '$staffGroupName'"
    $Global:staffMembers = Get-AzureADGroupMember -ObjectId  $staffGroup.ObjectId
}

function UpdateTenant {
    param (
        [Parameter(Mandatory = $true)][string] $tenantTitle,         # Title of the AAD tenant
        [Parameter(Mandatory = $true)][string] $tenantId,            # ID of the AAD tenant
        [Parameter(Mandatory = $true)][string] $GroupName            # Name of the target group to populate with the guest users
    )

    Connect-AzureAD -TenantId $tenantId

    # Check if the target group exists, and if not create it
    $staffGroup = Get-AzureADGroup -Filter "DisplayName eq '$GroupName'"
    if ($staffGroup.Count -eq 0) {
        $staffGroup = New-AzureADGroup -DisplayName $GroupName -MailEnabled $false -SecurityEnabled $true -MailNickName "NotSet"
    }

    # Get the current members of the target group
    $groupMembers = Get-AzureADGroupMember -ObjectId $staffGroup.ObjectId

    # Connect-AzAccount
    
    # Get the current global admins
    $azADGlobalAdminRole = Get-AzureADDirectoryRole -Filter "DisplayName eq 'Global Administrator'"
    $azADGlobalAdminMembers = Get-AzureADDirectoryRoleMember -ObjectId $azADGlobalAdminRole.ObjectId

    # Go through each of the source group's users
    foreach ($staffMember in $staffMembers) {
        # Check and see if the user already exists. If they don't then invite them as a guest
        $user = Get-AzureADUser -Filter "startswith(UserPrincipalName, '$($staffMember.UserPrincipalName.Replace(""@"", ""_""))')"
        if ($user.Count -eq 0) {
            $user = New-AzureADMSInvitation -InvitedUserDisplayName $staffMember.DisplayName -InvitedUserEmailAddress $staffMember.UserPrincipalName -InviteRedirectURL https://myapps.microsoft.com -SendInvitationMessage $true

            $userObjectId = $user.InvitedUser.Id
        }
        else {
            $userObjectId = $user.ObjectId
        }

        # Add the user to the target group if they're not already there
        $groupMember = $groupMembers | Where-Object { $_.UserPrincipalName -like ($staffMember.UserPrincipalName.Replace("@", "_") + "*")}
        if ($groupMember.Count -eq 0) {
            Add-AzureADGroupMember -ObjectId $staffGroup.ObjectId -RefObjectId $userObjectId
        }

        # Make them a global admin if they aren't already
        $azADGlobalAdminMember = $azADGlobalAdminMembers | Where-Object { $_.UserPrincipalName -like ($staffMember.UserPrincipalName.Replace("@", "_") + "*")}
        if ($azADGlobalAdminMember.Count -eq 0) {
            Add-AzureADDirectoryRoleMember -ObjectId $azADGlobalAdminRole.ObjectId -RefObjectId $userObjectId
        }

    }

    # Go through the target group memebrs, and remove anyone who is no longer supposed to be in there
    foreach ($groupMember in $groupMembers) {
        $staffMember = $staffMembers | Where-Object { ($groupMember.UserPrincipalName.Replace("_", "@")) -like $($_.UserPrincipalName + "*")}
        if ($staffMember.Count -eq 0) {
            Remove-AzureADGroupMember -ObjectId $staffGroup.ObjectId -MemberId $groupMember.ObjectId
        }
    }

    # Go through the global admins, and remove any guest users that are not part of the source group
    foreach ($azADGlobalAdminMember in $azADGlobalAdminMembers) {
        if ($azADGlobalAdminMember.ObjectType -eq "User") {
            $staffMember = $staffMembers | Where-Object { ($azADGlobalAdminMember.UserPrincipalName.Replace("_", "@")) -like $($_.UserPrincipalName + "*")}
            if ($staffMember.Count -eq 0 -and $azADGlobalAdminMember.UserType -eq "Guest") {
                Remove-AzureADDirectoryRoleMember -ObjectId $azADGlobalAdminRole.ObjectId -MemberId $azADGlobalAdminMember.ObjectId
            }
        }
    }

    # Go through each subscription and make the target group an owner
    foreach ($Subscription in $Subscriptions) {
        if ($Subscription.FieldValues["Tenant"].LookupValue -eq $Tenant.FieldValues["Title"]) {
            $context = Get-AzSubscription -SubscriptionId $Subscription.FieldValues["SubscriptionID"]
            Set-AzContext $context

            $roleAssignment = Get-AzRoleAssignment | Where-Object { $_.DisplayName -eq $GroupName -and $_.RoleDefinitionName -eq "Owner" }
            if ($roleAssignment.Count -eq 0) {
                New-AzRoleAssignment -ObjectId $staffGroup.ObjectId -RoleDefinitionName "Owner" -Scope "/subscriptions/$($Subscription.FieldValues["SubscriptionID"])"
            }
        }
    }
}

################
# Unit-testing #
################

# Declare varaibles
$listSite       = "https://envisionit.sharepoint.com/sites/infrastructure"
$sourceGroupName = "Staff"
$targetGroupName = "Envision IT Staff"

$wshell = New-Object -ComObject Wscript.Shell

# Only prompt to run ReadConfiguration if there is already a configuration loaded. Otherwise just go ahead and load it
if ($staffMembers.Count -ne 0) {
    if ($wshell.Popup("Do you want to reload the source list data?", 0, "Alert", 32 + 4) -eq 6) {
        ReadConfiguration -listSite $listSite -staffGroupName $sourceGroupName
    }
}
else {
    ReadConfiguration -listSite $listSite -staffGroupName $sourceGroupName
}

# Go through each tenant from the SharePoint list and update it
foreach ($Tenant in $Tenants) {
    $answer = $wshell.Popup("Do you want to update the $($Tenant.FieldValues[""Title""]) tenant?", 0, "Alert", 32 + 4)
    if ($answer -eq 6) {
        UpdateTenant -tenantTitle $Tenant.FieldValues["Title"] -tenantId $Tenant.FieldValues["TenantID"] -GroupName $targetGroupName
    }
}
