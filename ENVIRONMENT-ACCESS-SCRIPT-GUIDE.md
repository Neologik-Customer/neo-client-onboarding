# Update-NeologikEnvironmentAccess.ps1: What It Does

## Overview

`Update-NeologikEnvironmentAccess.ps1` is run by your Global Administrator, under their own sign-in, on one of two occasions:

| Run | When | What it does |
|---|---|---|
| The first run | Before an existing environment moves to Neologik Platform version 5 | Confirms the directory objects the platform uses, then reduces the access of the Neologik deployment identity to the roles it needs |
| The later run | When an agent or App is to work unattended in Microsoft 365 | Applies the grants listed in the files Neologik supplies, and nothing else |

An environment onboarded with this version of the kit already has the access the first run produces, so it needs the first run only if Neologik asks for it.

Neologik sends the complete command, with every value filled in. You supply your sign-in.

The script reads before it writes. It changes only what differs from the expected state, and it can be run as often as needed. With `-Verify` it reports what it would change and writes nothing.

## Contents

1. [What you need](#what-you-need)
2. [How to run the script](#how-to-run-the-script)
3. [The first run](#the-first-run)
4. [The later run](#the-later-run)
5. [What the script never does](#what-the-script-never-does)
6. [What the sign-in asks you to approve](#what-the-sign-in-asks-you-to-approve)
7. [What you receive](#what-you-receive)
8. [Questions](#questions)
9. [Help](#help)

## What you need

| Requirement | Reason |
|---|---|
| PowerShell 7.4 or later | The script does not run on an earlier version |
| A browser, on any device | The script signs in with a device code: it prints a web address and a code, and you complete the sign-in in the browser |
| A Global Administrator account in your tenant | Microsoft Graph application permissions and directory roles are granted and removed by a Global Administrator |
| Owner or User Access Administrator on the subscription, for the first run | The same account changes the Azure role assignments of the deployment identity |
| Exchange Administrator or Global Administrator, for a later run with mailbox grants | The mailbox grants are made in Exchange Online |
| The command Neologik sent | It names your tenant, your subscription, your resource group and the application registrations of the environment |
| The files Neologik sent, for the later run | They list the grants to apply |

The script installs the PowerShell modules it needs for your user account if they are missing: the Microsoft Graph modules, the Az modules for the first run, and the Exchange Online module for mailbox grants. Before it changes anything it confirms that the workstation can reach the Microsoft addresses it uses and that the account signed in holds the roles above.

## How to run the script

1. Place `Update-NeologikEnvironmentAccess.ps1` in a folder on your workstation.
2. Open PowerShell 7 in that folder.
3. Paste the command Neologik sent and press Enter.
4. The script prints a web address and a code. Open the address in a browser, enter the code and sign in as a Global Administrator. The script waits for up to 15 minutes.
5. In the first run the script signs in a second time, to Azure. Enter the second code in the same way. In a later run with mailbox grants it signs in to Exchange Online in the same way.
6. Read the summary the script prints, and send Neologik the summary file it writes.

To see what the script would change, add `-Verify` to the end of the command. The sign-ins are the same; every pending change is reported as `WOULD ...` and nothing is written.

## The first run

The first run is selected when the command names no grants file. It has four steps. Each item within a step is checked on its own, and an item that fails is recorded in the summary with the reason while the run continues.

### Step 1: The agent identity blueprint and the permissions of the deployment identity

| Item | Checked | Changed when |
|---|---|---|
| Agent identity blueprint, `Neologik Agent Blueprint - default - <short name>`, and its principal | Both exist | Created when absent |
| Owner | The deployment identity owns the blueprint and its principal | Added when absent |
| Permission of the principal | It holds `AgentIdUser.ReadWrite.IdentityParentedBy`, which is limited to the agent users of this blueprint | Granted when absent |
| Federated credentials | The three credentials through which the Neologik deployment acts as the blueprint are present | Added when absent |
| Permissions the deployment identity keeps | `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` | Granted when absent |
| Permissions the deployment identity no longer needs | `Application.Read.All`, `AgentIdentityBlueprint.Create`, `AgentIdentityBlueprint.UpdateAuthProperties.All`, `AgentIdentityBlueprintPrincipal.Create`, `AgentIdentity.Create.All`, `AgentIdUser.ReadWrite.All` and `Group.Create` | Removed when held, after the two it keeps are confirmed |

### Step 2: The group assignment of the sign-in application

The Neologik Context Engine authorises from the groups claim of the sign-in token, and the claim carries only the groups assigned to the application. The script assigns the group named in the command to the application `Neologik Platform Sign-in` when the assignment is absent.

Users must be direct members of the group. Membership through a nested group does not count. The script reports the number of direct members.

### Step 3: Consent and ownership

| Item | Checked | Changed when |
|---|---|---|
| Administrator consent for the sign-in application | Consent for the whole tenant is present | Never. When consent is absent the script prints the consent address for you to open. Run the script again afterwards to confirm |
| Consent for the SharePoint application | Checked when the configuration file records that the environment ingests from SharePoint | Never. The consent address is printed when consent is absent |
| Ownership of the application registrations | The deployment identity owns each registration the command names by client id, and its service principal: the sign-in application, the SharePoint application and the agent registrations | The owner is added when absent |
| Unique name | The sign-in application and the SharePoint application carry the unique name by which the deployment finds them | Set when empty. A different value is reported and left unchanged |
| Client secrets | Each named registration is read for client secrets that the deployment did not create | Never. They are listed in the summary. See below |
| Other registrations | Every other registration whose name begins `Neologik` | Never. Each is listed in the summary as `Review`, for you and Neologik to confirm that none was missed |

The deployment replaces the client secrets of the sign-in application and of the agent registrations. When one of these carries a secret the deployment did not create, the summary lists it as `PENDING`. Confirm with Neologik that nothing else uses the secret before the environment is upgraded.

### Step 4: Permission reduction

The script first confirms the roles the deployment identity needs, and assigns any that is absent:

| Scope | Roles |
|---|---|
| Resource group | Contributor, Key Vault Certificates Officer, Key Vault Secrets Officer, Storage Blob Data Contributor, Azure Kubernetes Service RBAC Cluster Admin, Monitoring Contributor, Role Based Access Control Administrator |
| Subscription | Reader, Cost Management Contributor |

Only when all nine are in place does the script remove the wider access. If one of the nine could not be assigned, nothing is removed, so that the deployment never loses access part way through.

| Removed | Condition |
|---|---|
| Contributor and User Access Administrator on the subscription | Held |
| The Application Administrator directory role | Held |
| Membership of the Neologik Admin User Group | Held, and every SQL server in the resource group names the deployment identity as its Microsoft Entra administrator. Until then the membership is kept, because it is the identity's access to SQL, and the summary says so |
| Any other Azure role in the subscription | Outside the nine roles above and the role `Cognitive Services Content Understanding Contributor` on a resource in the resource group |
| Any other directory role | Held |
| Any other group membership | Held |

Last, the script records the version of the kit on the resource group, as the tag `NeologikOnboardingKit`. The tag is merged with your other tags and written only when its value differs. The platform reads it before an upgrade.

The first run changes nothing on a managed identity, a security group or a user.

## The later run

The later run is selected when the command names a grants file. It applies what the files list and makes none of the checks of the first run.

### Step 5: Grants to agent users (`-AgentGrantsFile`)

An agent or App that works unattended has an agent identity and an agent user account in your directory. For each agent and App in the file, the script creates the delegated permission grant that lets the agent identity act as its own agent user, with exactly the permissions the file lists. The grant names one agent user; it is not a grant for the whole tenant.

The file may also list Microsoft Graph application permissions for named workload identities, which the script grants. When the file records that the environment ingests from SharePoint, the script checks the consent of the SharePoint application and prints the consent address when consent is absent.

An entry whose identity the platform has not yet created is reported as `SKIPPED`. Neologik supplies a new file when it is ready.

### Step 6: Mailbox grants (`-MailboxGrantsFile`)

For each email channel in the file, the script grants the identity of the channel three Exchange Online roles, `Application Mail.Read`, `Application Mail.ReadWrite` and `Application Mail.Send`, each limited to the one mailbox the file names. To do so it registers the identity in Exchange Online as a service principal and creates a management scope that contains that mailbox alone, where these are absent. The identity receives no access to any other mailbox.

With `-RemoveLegacyGrantAppIds` the script also removes the Exchange Online assignments of an identity that is no longer used. An identity the file records as still in use keeps its assignments.

If your Exchange Online organisation has never been customised, the script enables organisation customisation, which Exchange Online requires before the roles can be assigned. This is a setting of Exchange Online that is made once.

## What the script never does

- It never reads, moves or deletes your data. It reads directory objects, role assignments and Exchange Online role assignments.
- It never changes an application registration that the command does not name.
- It never creates a user, a group or a secret.
- It never gives administrator consent. It prints the address and you decide.
- It never removes a wider role before the roles that replace it are in place.
- It never sends anything to Neologik. You send the summary file.
- It never stores your sign-in.

## What the sign-in asks you to approve

The script signs in to Microsoft Graph under your own account. At first use, Microsoft lists the permissions the script requests. All of them are delegated: the script acts as you, for the run only, and nothing is granted to an application.

| Permission | Requested in | Used to |
|---|---|---|
| `Application.ReadWrite.All` | Every run | Read the application registrations, add the owner, set the unique name and add the credentials of the blueprint |
| `AppRoleAssignment.ReadWrite.All` | Every run | Grant and remove Microsoft Graph application permissions, and assign the group to the sign-in application |
| `Directory.Read.All` | Every run | Read the service principals, groups and directory roles |
| `User.Read` | Every run | Identify your own account |
| `DelegatedPermissionGrant.Read.All` | Every run | Read the consent of the sign-in application |
| `AgentIdentityBlueprint.Create`, `AgentIdentityBlueprint.AddRemoveCreds.All`, `AgentIdentityBlueprintPrincipal.Create` | Every run | Create the agent identity blueprint, its principal and its credentials when they are absent |
| `RoleManagement.ReadWrite.Directory` | The first run | Remove directory roles from the deployment identity |
| `GroupMember.ReadWrite.All` | The first run | Remove the deployment identity from groups |
| `DelegatedPermissionGrant.ReadWrite.All` | A later run with `-AgentGrantsFile` | Create the grants to agent users |

The sign-ins to Azure and to Exchange Online use the same account and show no list of permissions.

## What you receive

The script prints a summary table and writes the same table to a file beside the script:

| Run | File |
|---|---|
| The first run | `Neologik_EnvironmentAccess_PreWindow_<date and time>.json` |
| The later run | `Neologik_EnvironmentAccess_PostWindow_<date and time>.json` |

When the folder of the script cannot be written, the file is written to the current folder or to the temporary folder, and the script reports the path.

The file holds the tenant id, the client id of the deployment identity, the time of the run, the Microsoft Graph application permissions the deployment identity holds, and every item of the summary. It contains no secret. Send it to Neologik as the record of the run.

| Result | Meaning |
|---|---|
| `Already in place`, `Already granted`, `Already assigned`, `Present`, `None`, `Not held` | Nothing to change |
| `Added`, `Granted`, `Assigned`, `Set`, `Removed` | Changed in this run |
| `Review ...` | Listed for you to look at. Nothing was changed |
| `Not checked`, `Not needed` | The item did not apply to this run |
| `WOULD ...` | A change that a run without `-Verify` would make |
| `MISSING`, `SKIPPED`, `NOT FOUND`, `PENDING`, `UNKNOWN`, `FAILED` | Needs attention. The row gives the reason |

| Exit code | Meaning |
|---|---|
| 0 | Everything is in the expected state |
| 1 | An item needs attention, or, with `-Verify`, a change is pending |

## Questions

**Does the first run give Neologik more access?**
The first run removes access from the deployment identity and adds only what is absent from the set listed in this document. On an environment onboarded before version 5 the deployment identity ends the run with less access than it began with.

**Why does my account need such wide permissions to run it?**
Removing a directory role and granting a Microsoft Graph application permission are actions reserved to a Global Administrator. The script uses your sign-in for the run. Nothing is granted to your account and nothing is stored.

**What happens if something is already in order?**
The script reports it and moves on. A second run on an environment that is in order changes nothing.

**What happens if an item fails?**
The script records the failure with its reason, continues with the other items and ends with exit code 1. Send Neologik the summary file.

**Why does the summary list applications that were not changed?**
The deployment identity manages only the registrations it owns, and the script adds it as owner of exactly those the command names. Listing the others whose name begins `Neologik` lets you and Neologik confirm that none was missed.

## Help

Email support@neologik.ai with the summary file, your organisation name and the environment's host name.
