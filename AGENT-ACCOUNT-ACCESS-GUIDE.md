# Giving a Neologik agent account access to your Microsoft 365 resources

## Overview

Some Neologik agents work on their own: they run a report on a schedule, read files from a SharePoint library, and email the result from one of your shared mailboxes. To do that, each such agent has an **agent account** in your Microsoft Entra directory, named like `agent-<key>-<env>@yourdomain.com` (an App's account is named `app-<name>-<env>@yourdomain.com` or carries the prefix you chose). The account has no password and no sign-in of its own; the agent uses it only through the permissions your administrator granted.

Three things about that account are yours to do, because Neologik cannot do them in your tenant:

| # | Task | Who | Needed when |
|---|---|---|---|
| 1 | Assign a Microsoft 365 licence | Global Administrator or Licence Administrator | the agent uses its own mailbox or reads a shared mailbox (Exchange Online), or reads a Teams channel (Teams) |
| 2 | Give the account Full Access and Send As on a shared mailbox | Exchange Administrator | the agent emails from that mailbox or reads it |
| 3 | Make the account a member of a SharePoint site (or a Teams team) | Site owner, SharePoint Administrator or Teams Administrator | the agent reads files from a library on that site or delivers files to it |

The Neologik Context Engine (the admin tool) shows you when each is done: the agent's **Access tab** carries a **Licensed** chip, and a loop's page carries a **Resource access** row per mailbox and library with a chip that turns green once the account can reach it. Beside a red chip the page shows the exact command with the account filled in, with a Copy button.

**Why the portals cannot do it:** agent accounts are hidden from address lists, so the Microsoft 365 admin centre's user list, the Exchange admin centre's delegation picker, the SharePoint "Share site" picker and the Teams "Add member" picker never find them. Every step below takes the account name directly. Run the commands in **Azure Cloud Shell (PowerShell)** at https://shell.azure.com, signed in to your tenant, or in a PowerShell 7 session on your own machine. Each command is safe to run again.

## Contents

1. [Assign a Microsoft 365 licence](#1-assign-a-microsoft-365-licence)
2. [Give the account Full Access and Send As on a shared mailbox](#2-give-the-account-full-access-and-send-as-on-a-shared-mailbox)
3. [Make the account a member of a SharePoint site](#3-make-the-account-a-member-of-a-sharepoint-site)
4. [Add the account to a Teams team](#4-add-the-account-to-a-teams-team)
5. [Check the result](#5-check-the-result)
6. [Frequently asked questions](#6-frequently-asked-questions)

## 1. Assign a Microsoft 365 licence

Any Microsoft 365 licence that includes the service works (Business Basic covers Exchange Online, SharePoint and OneDrive; Exchange Online Plan 1 covers mail only). The licence is yours, on your bill; Neologik never buys or holds licences for your accounts.

Step 1 - see which licences your tenant holds (every tenant differs):

```powershell
az rest --method GET --url 'https://graph.microsoft.com/v1.0/subscribedSkus' --query 'value[].{sku:skuPartNumber,status:capabilityStatus,purchased:prepaidUnits.enabled,used:consumedUnits}' -o table
```

Step 2 - fill in the licence's `skuPartNumber` from that table, your country code and the account name shown in the Neologik admin tool, then run:

```powershell
$skuPart       = '<skuPartNumber from step 1>'
$usageLocation = 'GB'
$account       = 'agent-<key>-<env>@yourdomain.com'

$sku = (az rest --method GET --url 'https://graph.microsoft.com/v1.0/subscribedSkus' -o json | ConvertFrom-Json).value |
  Where-Object { $_.skuPartNumber -eq $skuPart -and $_.capabilityStatus -eq 'Enabled' }
if (-not $sku) { "No enabled subscription named '$skuPart' - check step 1."; return }

az rest --method PATCH --url "https://graph.microsoft.com/v1.0/users/$account" --headers 'Content-Type=application/json' --body ('{"usageLocation":"' + $usageLocation + '"}') -o none
az rest --method POST  --url "https://graph.microsoft.com/v1.0/users/$account/assignLicense" --headers 'Content-Type=application/json' --body ('{"addLicenses":[{"skuId":"' + $sku.skuId + '"}],"removeLicenses":[]}') -o none
az rest --method GET   --url "https://graph.microsoft.com/v1.0/users/$account/licenseDetails" --query 'value[].skuPartNumber' -o tsv
```

The last line prints the licence now on the account. The admin tool's **Licensed** chip turns green within a few minutes (use Refresh).

## 2. Give the account Full Access and Send As on a shared mailbox

Needed when an agent emails from one of your shared mailboxes, or reads it. Full Access lets the account read the mailbox; Send As lets it send from the mailbox's address. The account must hold an Exchange Online licence first (task 1).

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser   # once per machine; not needed in Cloud Shell
Connect-ExchangeOnline -UserPrincipalName <your admin account>

$mailbox = 'reports@yourdomain.com'                 # the shared mailbox
$account = 'agent-<key>-<env>@yourdomain.com'       # the account shown in the admin tool

Add-MailboxPermission   -Identity $mailbox -User $account -AccessRights FullAccess -InheritanceType All -AutoMapping $false
Add-RecipientPermission -Identity $mailbox -Trustee $account -AccessRights SendAs -Confirm:$false

Get-MailboxPermission   -Identity $mailbox -User $account    | Format-Table User, AccessRights
Get-RecipientPermission -Identity $mailbox -Trustee $account | Format-Table Trustee, AccessRights
```

The two Get commands should each list the account. Both rights take effect within a few minutes. `-AutoMapping $false` keeps the mailbox out of any Outlook profile, which the account never has.

## 3. Make the account a member of a SharePoint site

Needed when an agent reads files from a library (its inputs) or delivers files to one. Members can read and write; for a read-only inputs library the site's Visitors group is enough.

**If the site belongs to a Microsoft 365 group** (every Teams team's site, and any team site created with a group): add the account to the group. Membership carries the site, and the team if there is one. Find the group's id in the Microsoft Entra admin centre under Groups, then:

```powershell
$groupId = '<the group id>'
$account = 'agent-<key>-<env>@yourdomain.com'
az rest --method POST --url "https://graph.microsoft.com/v1.0/groups/$groupId/members/`$ref" --headers 'Content-Type=application/json' --body ('{"@odata.id":"https://graph.microsoft.com/v1.0/users/' + $account + '"}')
```

**If the site stands alone** (no group behind it): add the account to the site's members group with the SharePoint Online Management Shell.

```powershell
Install-Module Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser   # once per machine
Connect-SPOService -Url https://<yourtenant>-admin.sharepoint.com

$site    = 'https://<yourtenant>.sharepoint.com/sites/<site>'
$account = 'agent-<key>-<env>@yourdomain.com'
Get-SPOSiteGroup -Site $site | Select-Object Title             # the members group is usually '<site name> Members'
Add-SPOUser -Site $site -LoginName $account -Group '<site name> Members'
Get-SPOUser -Site $site -LoginName $account
```

## 4. Add the account to a Teams team

Needed only when the agent itself reads a channel (an App's declared channel). A scheduled report's post in a channel is made by the agent's Teams app, which your Teams administrator installs in the team from the package Neologik provides; that needs no membership for the account. Where membership is needed, a team is a Microsoft 365 group, so the group command in task 3 adds the account, or:

```powershell
Install-Module MicrosoftTeams -Scope CurrentUser   # once per machine
Connect-MicrosoftTeams
Add-TeamUser -GroupId <the team's group id> -User agent-<key>-<env>@yourdomain.com
```

Reading a channel also needs the account licensed with Teams (task 1).

## 5. Check the result

- In the Neologik admin tool, open the agent, then the loop: the **Resource access** rows show **Access confirmed** once the account can reach each mailbox and library. Press **Refresh** after granting; allow a few minutes for Microsoft 365 to apply the change.
- The agent's **Access tab** shows the account's licence state and whether the permission grant your Global Administrator ran is confirmed. A row that reads **grant outstanding** needs that grant first; the tab gives the command.
- For an App, the App's **Connections** tab has **Test access**, which reads each declared resource as the App's account and names the reason when a read is refused.

## 6. Frequently asked questions

**Does the account get a password or sign in anywhere?** No. It has no credentials. The agent uses it only through the permission grant your administrator confirmed, and only for the permissions listed on the Access tab.

**Can I use a group instead of assigning the licence directly?** Yes, where your tenant has Microsoft Entra ID P1 or above: attach the licence to a security group and add the account to the group with the group command in task 3.

**Which mailbox permission is the minimum?** Full Access and Send As on the one mailbox the agent uses. Neologik never asks for tenant-wide mail permissions for an agent account.

**How do I take access away?** Remove the licence, the mailbox permissions or the site membership the same way; the chips in the admin tool turn red at the next Refresh and the agent's runs record the refusal instead of failing silently.
