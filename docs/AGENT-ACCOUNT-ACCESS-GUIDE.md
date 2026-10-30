# Giving an Agent Account Access to Microsoft 365

## Overview

This guide is for Administrators of Microsoft 365. The tasks in this guide give an agent account access to Microsoft 365.

An agent that works unattended has an agent account in your Microsoft Entra directory. An App that works unattended also has an agent account. An agent works unattended when the agent does one of these things:

- runs on a schedule
- reads files from a SharePoint library
- reads or sends email from a shared mailbox

The name of an agent account has one of two forms.

| Owner of the agent account | Name of the agent account |
|---|---|
| An agent | `neologik-agent-<key>-<short name>@<your domain>`, or a name with the **Account prefix** that you chose instead of `neologik` |
| An App | `neologik-app-<name>-<short name>@<your domain>`, or a name with the **Account prefix** that you chose instead of `neologik` |

`<short name>` stands for the short name of the environment, for example `abcprd01`.

The agent account has no password. The agent account cannot sign in. The agent uses the agent account only through the permissions that a Global Administrator granted.

A Global Administrator grants the permissions with the grants script, `Grant-NeologikAgentAccess.ps1`, and the agent grants file that the Neologik Context Engine exports. [GRANT-AGENT-ACCESS-SCRIPT-GUIDE.md](GRANT-AGENT-ACCESS-SCRIPT-GUIDE.md) describes the grants script.

An administrator completes up to five tasks in your tenant.

| Task | Who acts | When the task applies |
|---|---|---|
| [1. Assign a Microsoft 365 licence](#task-1-assign-a-microsoft-365-licence) | A Global Administrator or a License Administrator | The agent uses a mailbox or reads a Teams channel |
| [2. Give access to a shared mailbox](#task-2-give-access-to-a-shared-mailbox) | An Exchange Administrator | The agent reads the shared mailbox or sends email from the shared mailbox |
| [3. Give access to a SharePoint site](#task-3-give-access-to-a-sharepoint-site) | An owner of the site or a SharePoint Administrator | The agent reads files from a library on the site, or delivers files to the site |
| [4. Add the agent account to a Teams team](#task-4-add-the-agent-account-to-a-teams-team) | A Teams Administrator | The agent reads a channel of the team |
| [5. Give the SharePoint application access to a SharePoint site](#task-5-give-the-sharepoint-application-access-to-a-sharepoint-site) | A Global Administrator | The Neologik Platform reads files from the site through a SharePoint connection |

The Neologik Context Engine shows the exact name of the agent account of each agent. The Neologik Context Engine also shows when each task is complete.

## Contents

1. [Before you start](#before-you-start)
2. [Task 1: Assign a Microsoft 365 licence](#task-1-assign-a-microsoft-365-licence)
3. [Task 2: Give access to a shared mailbox](#task-2-give-access-to-a-shared-mailbox)
4. [Task 3: Give access to a SharePoint site](#task-3-give-access-to-a-sharepoint-site)
5. [Task 4: Add the agent account to a Teams team](#task-4-add-the-agent-account-to-a-teams-team)
6. [Task 5: Give the SharePoint application access to a SharePoint site](#task-5-give-the-sharepoint-application-access-to-a-sharepoint-site)
7. [Check the result](#check-the-result)
8. [Questions](#questions)
9. [Help](#help)

## Before you start

Address lists do not show an agent account. A search in each of these places does not find an agent account:

- the user list of the Microsoft 365 admin centre
- the people picker of the Exchange admin centre
- the people picker of SharePoint
- the people picker of Microsoft Teams

Each task in this guide uses a command, because a command takes the name of the agent account directly.

Run the commands in one of two places.

| Place | Detail |
|---|---|
| Azure Cloud Shell | Open https://shell.azure.com and sign in to your tenant. Use the PowerShell mode of Azure Cloud Shell |
| PowerShell 7 | On your workstation |

You can run each command again without harm.

In each command, replace each value in angle brackets with your value. Replace the example name of the agent account and the example name of the mailbox with the names in your tenant.

A loop is a scheduled run of an agent. The **Loops** tab of the agent in the Neologik Context Engine lists each loop. The page of a loop shows each command with the name of the agent account filled in. The page of a loop also shows a **Copy** button.

## Task 1: Assign a Microsoft 365 licence

The agent account needs a Microsoft 365 licence that includes the service that the agent uses. Any Microsoft 365 licence that includes the service is sufficient.

| Licence | Services that the licence includes |
|---|---|
| Microsoft 365 Business Basic | Exchange Online, SharePoint and Teams |
| Exchange Online Plan 1 | Mail only |

Assign a licence that your organisation holds. Neologik holds no licence for an account in your tenant.

1. List the licences that your tenant holds:

   ```powershell
   az rest --method GET --url 'https://graph.microsoft.com/v1.0/subscribedSkus' --query 'value[].{sku:skuPartNumber,status:capabilityStatus,purchased:prepaidUnits.enabled,used:consumedUnits}' -o table
   ```

2. Set three values in the first three lines of the commands in step 3:

   | Variable | Value |
   |---|---|
   | `$skuPart` | The `sku` value of the licence, from the table that step 1 printed |
   | `$usageLocation` | Your two-letter country code |
   | `$account` | The name of the agent account |

3. Run the commands:

   ```powershell
   $skuPart       = '<sku from step 1>'
   $usageLocation = 'GB'
   $account       = 'neologik-agent-<key>-<short name>@contoso.com'

   $sku = (az rest --method GET --url 'https://graph.microsoft.com/v1.0/subscribedSkus' -o json | ConvertFrom-Json).value |
     Where-Object { $_.skuPartNumber -eq $skuPart -and $_.capabilityStatus -eq 'Enabled' }
   if (-not $sku) { "No enabled licence named '$skuPart'. Check step 1."; return }

   az rest --method PATCH --url "https://graph.microsoft.com/v1.0/users/$account" --headers 'Content-Type=application/json' --body ('{"usageLocation":"' + $usageLocation + '"}') -o none
   az rest --method POST  --url "https://graph.microsoft.com/v1.0/users/$account/assignLicense" --headers 'Content-Type=application/json' --body ('{"addLicenses":[{"skuId":"' + $sku.skuId + '"}],"removeLicenses":[]}') -o none
   az rest --method GET   --url "https://graph.microsoft.com/v1.0/users/$account/licenseDetails" --query 'value[].skuPartNumber' -o tsv
   ```

   The last command prints the licence that the agent account holds.

## Task 2: Give access to a shared mailbox

The commands in task 2 give the agent account two permissions on the shared mailbox.

| Permission | What the permission allows |
|---|---|
| Full Access | The agent account reads the shared mailbox |
| Send As | The agent account sends email from the address of the shared mailbox |

Before you start task 2, the agent account must hold a licence that includes Exchange Online. [Task 1](#task-1-assign-a-microsoft-365-licence) assigns the licence.

Run these commands:

```powershell
# Once for each workstation. Not needed in Azure Cloud Shell.
Install-Module ExchangeOnlineManagement -Scope CurrentUser

Connect-ExchangeOnline -UserPrincipalName <your administrator account>

$mailbox = 'reports@contoso.com'
$account = 'neologik-agent-<key>-<short name>@contoso.com'

Add-MailboxPermission   -Identity $mailbox -User $account -AccessRights FullAccess -InheritanceType All -AutoMapping $false
Add-RecipientPermission -Identity $mailbox -Trustee $account -AccessRights SendAs -Confirm:$false

Get-MailboxPermission   -Identity $mailbox -User $account    | Format-Table User, AccessRights
Get-RecipientPermission -Identity $mailbox -Trustee $account | Format-Table Trustee, AccessRights
```

Each of the last two commands lists the agent account. Full Access and Send As usually take effect within minutes. Full Access and Send As occasionally take more than an hour to take effect.

The parameter `-AutoMapping $false` keeps the shared mailbox out of an Outlook profile. The agent account has no Outlook profile.

## Task 3: Give access to a SharePoint site

Membership of the site allows the agent account to read and to write. When the agent only reads a library, the visitors group of the site is sufficient.

### A site that belongs to a Microsoft 365 group

Two kinds of site belong to a Microsoft 365 group:

- the site of each Teams team
- each team site that a person created with a Microsoft 365 group

Add the agent account to the Microsoft 365 group.

1. In the Microsoft Entra admin centre, select **Groups**.
2. Find the object id of the Microsoft 365 group.
3. Run these commands with the object id and the name of the agent account:

   ```powershell
   $groupId = '<group object id>'
   $account = 'neologik-agent-<key>-<short name>@contoso.com'
   az rest --method POST --url "https://graph.microsoft.com/v1.0/groups/$groupId/members/`$ref" --headers 'Content-Type=application/json' --body ('{"@odata.id":"https://graph.microsoft.com/v1.0/users/' + $account + '"}')
   ```

### A site without a group

Add the agent account to the members group of the site. The commands use the SharePoint Online Management Shell.

Run these commands:

```powershell
# Once for each workstation.
Install-Module Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser

Connect-SPOService -Url https://<your tenant>-admin.sharepoint.com

$site    = 'https://<your tenant>.sharepoint.com/sites/<site>'
$account = 'neologik-agent-<key>-<short name>@contoso.com'

# Lists the groups of the site. The members group is usually named '<site name> Members'.
Get-SPOSiteGroup -Site $site | Select-Object Title

Add-SPOUser -Site $site -LoginName $account -Group '<site name> Members'
Get-SPOUser -Site $site -LoginName $account
```

## Task 4: Add the agent account to a Teams team

Task 4 applies only when the agent reads a channel.

A message that the agent posts to a channel needs no membership for the agent account. The Teams app of the agent sends the message. A Teams Administrator installs the Teams app of the agent in the team.

Before you start task 4, the agent account must hold a licence that includes Teams. [Task 1](#task-1-assign-a-microsoft-365-licence) assigns the licence.

A team is a Microsoft 365 group. The group command in [A site that belongs to a Microsoft 365 group](#a-site-that-belongs-to-a-microsoft-365-group) adds the agent account to the team.

Alternatively, run these commands:

```powershell
# Once for each workstation.
Install-Module MicrosoftTeams -Scope CurrentUser

Connect-MicrosoftTeams
Add-TeamUser -GroupId <group object id of the team> -User neologik-agent-<key>-<short name>@contoso.com
```

## Task 5: Give the SharePoint application access to a SharePoint site

The SharePoint application of the environment is `Neologik SharePoint Access - <short name>`. The application holds the Microsoft Graph application permission `Sites.Selected`. `Sites.Selected` reaches no SharePoint site until an administrator grants the application access to that site.

Run task 5 once for each site that the Neologik Platform reads. A Global Administrator runs the commands, because the sign-in needs the delegated permission `Sites.FullControl.All`. The commands grant one site. The application gains no access to any other site.

1. In the Microsoft Entra admin centre, select **App registrations**, then **All applications**.
2. Find `Neologik SharePoint Access - <short name>`, and copy the **Application (client) ID**.
3. Run these commands with your values:

   ```powershell
   # Once for each workstation.
   Install-Module Microsoft.Graph.Sites -Scope CurrentUser

   Connect-MgGraph -Scopes 'Sites.FullControl.All'

   $hostName = '<your tenant>.sharepoint.com'
   $siteName = '<site>'
   $appId    = '<application (client) id>'
   $appName  = 'Neologik SharePoint Access - <short name>'

   $site = Get-MgSite -SiteId "${hostName}:/sites/$siteName"
   $body = @{ roles = @('read'); grantedToIdentities = @(@{ application = @{ id = $appId; displayName = $appName } }) }
   $permission = New-MgSitePermission -SiteId $site.Id -BodyParameter $body
   Get-MgSitePermission -SiteId $site.Id -PermissionId $permission.Id | Format-List Id, Roles
   ```

   The last command prints the role `read`.

## Check the result

1. Wait a few minutes while Microsoft 365 applies each change.
2. In the Neologik Context Engine, select **Refresh**.

The Neologik Context Engine shows the result in three places.

| Place | What the place shows |
|---|---|
| The **Access** tab of the agent | The label **Microsoft 365 licence assigned** or **Microsoft 365 licence required** on each permission pack that needs a licence. The **Access** tab also shows whether the permission grant from a Global Administrator is confirmed |
| The page of a loop | A **Resource access** row for each mailbox and each library. The row reads **Access confirmed** when the agent account can reach the mailbox or the library |
| The **Connections** tab of an App | **Test access** reads each resource as the agent account of the App. **Test access** gives the reason when Microsoft 365 refuses a read |

A row on the **Access** tab that reads **Consent outstanding** needs the permission grant from a Global Administrator first. The **Access** tab gives the command for the permission grant.

## Questions

**Does the agent account have a password, or sign in anywhere?**

No. The agent account has no credential. The agent uses the agent account only through the permission grant that a Global Administrator made. The agent uses only the permissions that the **Access** tab lists.

**Can an administrator assign the licence through a group?**

Yes, when your tenant holds Microsoft Entra ID P1 or a higher plan. Assign the licence to a security group. Then add the agent account to the security group with the group command in task 3.

**What is the least access that the agent account needs to a mailbox?**

The agent account needs Full Access and Send As on the one mailbox that the agent uses. The agent account needs no mail permission for the whole tenant.

**How does an administrator take the access away?**

Remove the licence, the mailbox permissions or the membership. At the next refresh, the Neologik Context Engine shows the access as absent. The runs of the agent then record the refusal.

## Help

Email support@neologik.ai with these details:

- the name of the agent
- the task that you have reached
- the error message
