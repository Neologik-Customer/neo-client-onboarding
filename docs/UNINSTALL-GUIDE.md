# Uninstalling the Neologik Platform

## Overview

This guide removes one Neologik Platform environment completely from your Azure subscription and your Microsoft Entra tenant. This guide is for the Administrators who carry out the removal.

The work runs in four stages:

1. In the Neologik Admin Tool, you remove every agent and App. The platform removes what it created for each one.
2. In Microsoft 365, if your agents and apps used Teams and/or mailboxes, you delete the Teams apps and any Send As permission.
3. In Azure, you delete the resource group of the environment and the role assignments on your subscription.
4. In Microsoft Entra, you delete the remaining Neologik objects.

**The removal cannot be undone.** Step 5 permanently deletes the conversations, uploaded documents, search indexes, databases and logs of the environment. Complete step 1 before you do anything else.

Your own data stays where it is. The Neologik Platform reads your SharePoint sites, mailboxes and databases, and this guide deletes nothing from them.

| Step | Who acts | What the step achieves |
|---|---|---|
| [1. Back up your data](#step-1-back-up-your-data) | An Administrator | Keeps the data that you need |
| [2. Remove the agents](#step-2-remove-the-agents) | A member of `Neologik NCE Admins - <short name>` | Removes each agent, its channels and its access |
| [3. Uninstall the Apps](#step-3-uninstall-the-apps) | A member of `Neologik NCE Admins - <short name>` | Removes each App and its access |
| [4. Clear Microsoft 365](#step-4-clear-microsoft-365) | A Teams Administrator, and an Exchange Administrator when an email channel replied as another address | Removes the Teams apps and any Send As permission |
| [5. Delete the Azure resources](#step-5-delete-the-azure-resources) | An Owner of the subscription | Deletes the environment and its data |
| [6. Remove the roles on your subscription](#step-6-remove-the-roles-on-your-subscription) | An Owner of the subscription | Ends the access of our deployment identity |
| [7. Delete the directory objects](#step-7-delete-the-directory-objects) | A Global Administrator | Deletes the applications, agent accounts, security groups and guest accounts |
| [8. Disconnect your own systems](#step-8-disconnect-your-own-systems) | The person who manages your DNS, and the owner of each connected system | Removes the DNS record and the access you gave the platform |
| [9. Tell us you have finished](#step-9-tell-us-you-have-finished) | An Administrator | We remove our records of the environment and confirm in writing |

`<short name>` stands for the short name of the environment, for example `abcprd01`. The short name is the last part of the name of each Neologik security group, such as `Neologik User Group - abcprd01`. When your tenant holds more than one Neologik environment, work through this guide once for each environment. The script in step 7 acts only on the short name that you give it.

## Contents

1. [What you need](#what-you-need)
2. [Step 1: Back up your data](#step-1-back-up-your-data)
3. [Step 2: Remove the agents](#step-2-remove-the-agents)
4. [Step 3: Uninstall the Apps](#step-3-uninstall-the-apps)
5. [Step 4: Clear Microsoft 365](#step-4-clear-microsoft-365)
6. [Step 5: Delete the Azure resources](#step-5-delete-the-azure-resources)
7. [Step 6: Remove the roles on your subscription](#step-6-remove-the-roles-on-your-subscription)
8. [Step 7: Delete the directory objects](#step-7-delete-the-directory-objects)
9. [Step 8: Disconnect your own systems](#step-8-disconnect-your-own-systems)
10. [Step 9: Tell us you have finished](#step-9-tell-us-you-have-finished)
11. [What Microsoft keeps for a time](#what-microsoft-keeps-for-a-time)
12. [Checklist](#checklist)
13. [Troubleshooting](#troubleshooting)
14. [Help](#help)

## What you need

| Requirement | Used in |
|---|---|
| Membership of the group `Neologik NCE Admins - <short name>` | Steps 2 and 3. Only an administrator of the Neologik Admin Tool sees the buttons that remove an agent or an App |
| Teams Administrator | Step 4 |
| Exchange Administrator or Global Administrator | Step 4, when an email channel replied as another address |
| Owner of the subscription | Steps 5 and 6. Purging a deleted AI account needs a role on the subscription, so a role on the resource group alone is not enough |
| Global Administrator | Step 7 |
| PowerShell 7.4 or later, on a workstation with a browser | Step 7 |

The order of the steps matters. The Neologik Admin Tool needs the Azure resources and our deployment identity to remove each agent and App, so steps 2 and 3 come before steps 5, 6 and 7.

## Step 1: Back up your data

Back up any data from custom storage accounts and custom databases in the resource group of the environment.

## Step 2: Remove the agents

For each agent, the platform removes the workload, the managed identity, the role assignments, the database access, the agent identity and the agent account. When the agent account goes, its access to mailboxes, sites and teams ends, and any Microsoft 365 licence that it held returns to your pool.

1. Open the Neologik Admin Tool at `https://<your host name>/nce` and sign in.
2. Select **Agents** and open an agent. An agent that has subagents cannot be removed until its subagents have gone, so start with the subagents.
3. Open the **Channels** tab. For each channel, select **Detach**, then **Detach channel**. Wait until the channel has left the tab.
4. Select **Delete agent** at the top of the page, then **Delete agent** in the confirmation.
5. The page reads "Uninstall is in progress" and returns to the list of agents when the removal is complete.

Repeat these steps until the list of agents is empty.

## Step 3: Uninstall the Apps

For each App, the platform removes the workloads, the managed identities, the role assignments, the database access, the agent identity and the agent account.

1. Select **Apps & MCP** and open an App.
2. Select **Uninstall app**, then **Uninstall app** in the confirmation. An App that was registered and never deployed shows **Delete app** instead.
3. The page reads "Uninstall is in progress" and returns to the list when the removal is complete.

Repeat these steps for every App and every deployed MCP server on the page. An external MCP server is a record of an address only, and step 5 removes the record.

The uninstall deliberately leaves the database tables and storage containers of the App in place. Step 5 deletes them.

## Step 4: Clear Microsoft 365

### Delete the Teams apps

1. Sign in to the Teams admin centre, https://admin.teams.microsoft.com, as a Teams Administrator.
2. Open **Teams apps**, then **Manage apps**, and open the Neologik Teams app.
3. Select **More commands**, then **Actions**, then **Delete**.

Repeat for each Neologik Teams app. Once you delete a Teams app, nobody in your organisation can use the Teams app. When you created a permission policy or a setup policy only for Neologik, delete that policy too.

### Remove any Send As permission

Exchange Online removes the mailbox grants of each email channel by itself when step 5 deletes the identity of the channel, so the mailbox grants need nothing from you.

When an email channel replied as another address, the shared mailbox holds the Send As permission on that address. Remove the permission:

1. Sign in to the Exchange admin centre, https://admin.exchange.microsoft.com, as an Exchange Administrator.
2. Select **Recipients**, then **Mailboxes**, and open the mailbox of the reply-as address.
3. Under **Delegation**, open **Send as** and remove the shared mailbox.

The shared mailboxes are yours and stay in place.

## Step 5: Delete the Azure resources

Deleting the resource group removes every Azure resource of the environment. The two resource groups that Azure manages for the environment, whose names start with `MC_` and `MA_`, go with it.

Sign in to the Azure portal, https://portal.azure.com, as an Owner of the subscription, and open the resource group of the environment. The standard name is `rg-<solution name>`, for example `rg-neo-abcprd-uks-01`.

### Delete the shared private links

A Private Endpoint environment has shared private links on the search service. A Standard environment usually has none. Azure stops the deletion of the resource group if the target of a link goes before the search service.

1. Open the search service in the resource group.
2. Select **Networking** under **Settings**, then **Shared Private Access**.
3. Delete each link. Wait until the list is empty, which takes a few minutes.

### Delete the Log Analytics workspace permanently

Azure otherwise keeps the workspace and its logs for 14 days, and a workspace in that state cannot be deleted permanently until it is first recovered.

1. Open the Log Analytics workspace in the resource group.
2. Select **Delete**.
3. Select **Delete the workspace permanently**, enter the name of the workspace and confirm.

### Release any telephone number

When an agent used a voice channel, open the Communication Services resource in the resource group, select **Phone numbers** and release the number. Detaching the channel leaves the number in place.

### Delete the resource group

1. Open the resource group and select **Delete resource group**.
2. Enter the name of the resource group and select **Delete**.
3. Wait until the resource group has left the list of resource groups. A typical environment takes 20 minutes or more.

### Purge the AI accounts

Azure keeps a deleted AI account for 48 hours, and any provisioned model deployment on the account continues to cost money until the purge. A purge deletes the account, its data and its keys for good.

1. In the search bar of the Azure portal, search for `Foundry` and select the service.
2. Select **Manage deleted resources** and choose your subscription.
3. Select each account that came from the resource group of the environment, then select **Purge**.

## Step 6: Remove the roles on your subscription

Our deployment identity holds three roles on your subscription. Deleting the resource group does not remove them.

1. In the Azure portal, open **Subscriptions** and open your subscription.
2. Select **Access control (IAM)**, then **Role assignments**.
3. Search for `Neologik GitHub Service Connection - <short name>`. Three rows appear: Reader, Cost Management Contributor and Role Based Access Control Administrator.
4. Select the three rows, then select **Delete** and confirm.
5. Clear the search. A row that reads **Identity not found** belongs to an identity that no longer exists, so you can delete that row too.

When you created the deployment service principal yourself, as described in [CREATE-SP-GUIDE.md](CREATE-SP-GUIDE.md), search for the name you gave it.

The registrations of the Azure resource providers stay on the subscription. They cost nothing, and other workloads on the subscription may rely on them.

## Step 7: Delete the directory objects

The script `Remove-NeologikDirectoryObjects.ps1` in the onboarding kit deletes every remaining directory object of the environment. The step uses a script because Microsoft offers no screen that can delete an agent identity or an agent identity blueprint. The script finds each object by name, shows you the list, and deletes only after you confirm.

| Objects | Example |
|---|---|
| Agent accounts and agent identities that remain | `Neologik Agent Identity - <name> - abcprd01` |
| Applications | `Neologik Platform Sign-in - abcprd01`, `Neologik GitHub Service Connection - abcprd01`, `Neologik SharePoint Access - abcprd01`, `Neologik Agent Sign-in - <name> - abcprd01`, `Neologik Agent Blueprint - default - abcprd01` |
| Security groups | `Neologik User Group - abcprd01`, and the three other groups |
| Identities that Microsoft Foundry created for the AI account | Names that start with `ais-` and contain `AgentIdentity` |

The managed identities of the environment went with the resource group in step 5, and so did the Directory Readers role of the SQL managed identity.

1. Open PowerShell 7 and go to the folder of the onboarding kit. Allow the scripts to run, as [step 4 of the README](../README.md#4-allow-the-scripts-to-run-in-this-session) describes.
2. Run this command with the short name of the environment:

   ```powershell
   .\Remove-NeologikDirectoryObjects.ps1 -ShortName <short name>
   ```

3. Sign in as a Global Administrator. At the first use, Microsoft lists the permissions that the script requests. Each is a delegated permission, which works only as the signed-in administrator.
4. Read the list that the script prints. Type `DELETE` to go ahead.
5. Run the command again. When the script prints `Nothing is left to remove`, the step is complete. Microsoft Entra can take a few minutes to catch up, so a second run soon after the first may list an object that has already gone.

### Delete the guest accounts

1. In the Microsoft Entra admin centre, https://entra.microsoft.com, open **Users**, then **All users**.
2. Delete each account listed in `NeologikGuestUsers.txt`, and each other account that you invited for Neologik support.

### Check the result

In the Microsoft Entra admin centre, search for `Neologik` under **App registrations**, with **All applications** selected, then under **Enterprise applications** and **Groups**. Delete anything that remains for this environment. When you created the deployment service principal yourself, delete it now under **App registrations**.

## Step 8: Disconnect your own systems

Work through each row that applies to your environment.

| Item | Action |
|---|---|
| DNS | Delete the DNS record for the host name of the environment, so that the name no longer points at an address that Azure may give to someone else |
| CAA record | Delete the record that allows `sectigo.com` when you added the record only for a Neologik-managed certificate |
| Peered networks | Delete the peering on your side of any network you peered with the environment, and the DNS forwarding of the private DNS zones |
| Credentials | Revoke each database login, API key and other credential that you issued for a connection in the Neologik Admin Tool |
| Confluence | A Confluence administrator deletes the webhooks `Neologik Upsert Webhook - <space>` and `Neologik Delete Webhook - <space>` |
| TLS certificate | Revoke your own certificate when nothing else uses it |
| Azure reservations and savings plans | Any that you bought for the environment continue until the end of their term. Manage them under **Reservations** or **Savings plans** in the Azure portal |

## Step 9: Tell us you have finished

Email support@neologik.ai to confirm that you have finished. We then:

- remove the environment and its deployment credential from our deployment service
- delete any copy of your TLS certificate that we hold
- erase every statistic that we hold for the environment, within 30 days, and confirm the erasure in writing

[ANALYTICS-REPORTING-GUIDE.md](ANALYTICS-REPORTING-GUIDE.md) describes those statistics.

## What Microsoft keeps for a time

Azure and Microsoft Entra keep some deleted items for a fixed period, which is a Microsoft safeguard. You need to take no further action on these items.

| Item | How long | What you should know |
|---|---|---|
| Key Vault | 90 days | Your Key Vault has purge protection, so nobody can purge the vault sooner. Azure then removes the vault for good. The name of the vault stays reserved until then |
| Objects deleted from Microsoft Entra | 30 days | The objects cannot sign in or be used. Microsoft Entra then removes them for good |
| AI accounts | None, after the purge in step 5 | Without the purge, Azure keeps a deleted AI account for 48 hours |
| Log Analytics workspace | None, after the permanent deletion in step 5 | Without the permanent deletion, Azure keeps the workspace and its logs for 14 days |

## Checklist

| Check | Done |
|---|---|
| Your data is backed up | |
| The list of agents is empty | |
| Every App and deployed MCP server is uninstalled | |
| The Teams apps are deleted | |
| Any Send As permission is removed | |
| The resource group has gone, with the resource groups that start with `MC_` and `MA_` | |
| The AI accounts are purged | |
| The roles of the deployment identity on the subscription are removed | |
| The script prints `Nothing is left to remove` | |
| The guest accounts are deleted | |
| The DNS record is deleted, and your own systems are disconnected | |
| You have told us that you have finished | |

## Troubleshooting

| Symptom | Cause | Action |
|---|---|---|
| The buttons **Delete agent** and **Uninstall app** do not appear | Your account is not a member of `Neologik NCE Admins - <short name>` | Add your account to the group, sign out and sign in again |
| **Delete agent** shows a note about attached channels | The agent still has a channel | Detach each channel on the **Channels** tab |
| The removal of an agent is refused and the message names subagents or a reply reviewer | A subagent remains, or an email channel names the agent as its reviewer | Remove the subagent first, or detach the email channel first |
| The Neologik Admin Tool does not open | The cluster is stopped, or your Neologik service has ended | Email us and we will help. When your Neologik service has ended, continue from step 4. Steps 5 and 7 remove what the Neologik Admin Tool would have removed |
| The deletion of the resource group stops with `LockedSPLResourceFound` | A shared private link remains on the search service | Delete the links as step 5 describes, then delete the resource group again |
| The deletion of the resource group is refused because of a lock | Your organisation has placed a resource lock on the resource group or on a resource | Remove the lock, then delete the resource group again |
| Azure refuses to purge the Key Vault | The Key Vault has purge protection | No action. Azure removes the vault after 90 days |
| The script reports `Authorization_RequestDenied` | The account is not a Global Administrator, or the consent was declined | Sign in as a Global Administrator and accept the permissions |

## Help

Email support@neologik.ai with the name of your organisation, the host name of the environment, the step you have reached and the error message.
