# Giving an Agent Account Access to Microsoft 365

## Overview

This guide is for the Microsoft 365 administrators of an organisation whose Neologik agents work unattended: an agent that runs on a schedule, reads files from a SharePoint library, or reads or sends email from a shared mailbox.

Each such agent has an agent account in your Microsoft Entra directory, named `agent-<key>-<environment>@<your domain>`. The account of an App is named `app-<name>-<environment>@<your domain>`, or carries the prefix you chose. The account has no password and cannot sign in. The agent uses it only through the permissions your Global Administrator granted.

Up to four tasks are carried out by your administrators, in your tenant:

| Task | Who | Needed when |
|---|---|---|
| [1. Assign a Microsoft 365 licence](#task-1-assign-a-microsoft-365-licence) | Global Administrator or Licence Administrator | The agent uses a mailbox or reads a Teams channel |
| [2. Give access to a shared mailbox](#task-2-give-access-to-a-shared-mailbox) | Exchange Administrator | The agent reads the mailbox or sends from it |
| [3. Give access to a SharePoint site](#task-3-give-access-to-a-sharepoint-site) | Site owner or SharePoint Administrator | The agent reads files from a library on the site or delivers files to it |
| [4. Add the account to a Teams team](#task-4-add-the-account-to-a-teams-team) | Teams Administrator | The agent itself reads a channel |

The Neologik Context Engine shows the exact account name for each agent, and shows when each task is complete.

## Contents

1. [Before you start](#before-you-start)
2. [Task 1: Assign a Microsoft 365 licence](#task-1-assign-a-microsoft-365-licence)
3. [Task 2: Give access to a shared mailbox](#task-2-give-access-to-a-shared-mailbox)
4. [Task 3: Give access to a SharePoint site](#task-3-give-access-to-a-sharepoint-site)
5. [Task 4: Add the account to a Teams team](#task-4-add-the-account-to-a-teams-team)
6. [Check the result](#check-the-result)
7. [Questions](#questions)
8. [Help](#help)

## Before you start

Agent accounts are hidden from address lists. The user list of the Microsoft 365 admin centre and the people pickers of the Exchange admin centre, SharePoint and Teams do not find them. Every task in this guide therefore uses a command that takes the account name directly.

Run the commands in Azure Cloud Shell (PowerShell), at https://shell.azure.com, signed in to your tenant, or in PowerShell 7 on your workstation. Each command can be run again without harm.

In the commands, replace each value in angle brackets, and replace the example account and mailbox names with your own. In the Neologik Context Engine, the page of a loop shows each command with the account name filled in, and a **Copy** button.

## Task 1: Assign a Microsoft 365 licence

Any Microsoft 365 licence that includes the service is sufficient. Microsoft 365 Business Basic includes Exchange Online, SharePoint and Teams. Exchange Online Plan 1 includes mail only. The licence is one of your own; Neologik holds no licences for your accounts.

1. List the licences your tenant holds:

   ```powershell
   az rest --method GET --url 'https://graph.microsoft.com/v1.0/subscribedSkus' --query 'value[].{sku:skuPartNumber,status:capabilityStatus,purchased:prepaidUnits.enabled,used:consumedUnits}' -o table
   ```

2. Enter the `sku` value of the licence from that table, your two-letter country code and the account name, then run:

   ```powershell
   $skuPart       = '<sku from step 1>'
   $usageLocation = 'GB'
   $account       = 'agent-<key>-<environment>@contoso.com'

   $sku = (az rest --method GET --url 'https://graph.microsoft.com/v1.0/subscribedSkus' -o json | ConvertFrom-Json).value |
     Where-Object { $_.skuPartNumber -eq $skuPart -and $_.capabilityStatus -eq 'Enabled' }
   if (-not $sku) { "No enabled licence named '$skuPart'. Check step 1."; return }

   az rest --method PATCH --url "https://graph.microsoft.com/v1.0/users/$account" --headers 'Content-Type=application/json' --body ('{"usageLocation":"' + $usageLocation + '"}') -o none
   az rest --method POST  --url "https://graph.microsoft.com/v1.0/users/$account/assignLicense" --headers 'Content-Type=application/json' --body ('{"addLicenses":[{"skuId":"' + $sku.skuId + '"}],"removeLicenses":[]}') -o none
   az rest --method GET   --url "https://graph.microsoft.com/v1.0/users/$account/licenseDetails" --query 'value[].skuPartNumber' -o tsv
   ```

The last command prints the licence now held by the account.

## Task 2: Give access to a shared mailbox

Full Access lets the account read the mailbox. Send As lets it send from the address of the mailbox. The account must hold a licence that includes Exchange Online before you start (task 1).

```powershell
# Once for each workstation. Not needed in Azure Cloud Shell.
Install-Module ExchangeOnlineManagement -Scope CurrentUser

Connect-ExchangeOnline -UserPrincipalName <your administrator account>

$mailbox = 'reports@contoso.com'
$account = 'agent-<key>-<environment>@contoso.com'

Add-MailboxPermission   -Identity $mailbox -User $account -AccessRights FullAccess -InheritanceType All -AutoMapping $false
Add-RecipientPermission -Identity $mailbox -Trustee $account -AccessRights SendAs -Confirm:$false

Get-MailboxPermission   -Identity $mailbox -User $account    | Format-Table User, AccessRights
Get-RecipientPermission -Identity $mailbox -Trustee $account | Format-Table Trustee, AccessRights
```

Each of the last two commands lists the account. Both rights usually take effect within minutes and occasionally take more than an hour.

`-AutoMapping $false` prevents the mailbox from being added to an Outlook profile, which the account does not have.

## Task 3: Give access to a SharePoint site

Membership of the site lets the account read and write. For a library the agent only reads, the visitors group of the site is sufficient.

### A site that belongs to a Microsoft 365 group

This is the site of every Teams team, and every team site created with a group. Add the account to the group. Find the object id of the group in the Microsoft Entra admin centre, under **Groups**.

```powershell
$groupId = '<group object id>'
$account = 'agent-<key>-<environment>@contoso.com'
az rest --method POST --url "https://graph.microsoft.com/v1.0/groups/$groupId/members/`$ref" --headers 'Content-Type=application/json' --body ('{"@odata.id":"https://graph.microsoft.com/v1.0/users/' + $account + '"}')
```

### A site without a group

Add the account to the members group of the site, with the SharePoint Online Management Shell.

```powershell
# Once for each workstation.
Install-Module Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser

Connect-SPOService -Url https://<your tenant>-admin.sharepoint.com

$site    = 'https://<your tenant>.sharepoint.com/sites/<site>'
$account = 'agent-<key>-<environment>@contoso.com'

# Lists the groups of the site. The members group is usually named '<site name> Members'.
Get-SPOSiteGroup -Site $site | Select-Object Title

Add-SPOUser -Site $site -LoginName $account -Group '<site name> Members'
Get-SPOUser -Site $site -LoginName $account
```

## Task 4: Add the account to a Teams team

This task is needed only when the agent itself reads a channel. A message that an agent posts to a channel is sent by the agent's Teams app, which your Teams administrator installs in the team, and needs no membership for the account.

A team is a Microsoft 365 group, so the group command in task 3 adds the account to the team. Alternatively:

```powershell
# Once for each workstation.
Install-Module MicrosoftTeams -Scope CurrentUser

Connect-MicrosoftTeams
Add-TeamUser -GroupId <group object id of the team> -User agent-<key>-<environment>@contoso.com
```

The account must hold a licence that includes Teams (task 1).

## Check the result

Allow a few minutes for Microsoft 365 to apply each change, then select **Refresh** in the Neologik Context Engine.

| Where | What it shows |
|---|---|
| The **Access** tab of the agent | The **Licensed** indicator, and whether the permission grant made by your Global Administrator is confirmed. A row that reads **grant outstanding** needs that grant first; the tab gives the command |
| The page of a loop | A **Resource access** row for each mailbox and library, which reads **Access confirmed** when the account can reach it |
| The **Connections** tab of an App | **Test access** reads each resource as the account of the App, and gives the reason when a read is refused |

## Questions

**Does the account have a password, or sign in anywhere?**
No. The account has no credential. The agent uses it only through the permission grant your Global Administrator made, and only with the permissions listed on the **Access** tab.

**Can the licence be assigned through a group?**
Yes, where your tenant holds Microsoft Entra ID P1 or above. Assign the licence to a security group and add the account to the group with the group command in task 3.

**What is the least access a mailbox needs?**
Full Access and Send As on the one mailbox the agent uses. An agent account needs no mail permission for the whole tenant.

**How is access taken away?**
Remove the licence, the mailbox permissions or the membership. At the next refresh the Neologik Context Engine shows the access as absent, and the runs of the agent record the refusal.

## Help

Email support@neologik.ai with the name of the agent, the task you have reached and the error message.
