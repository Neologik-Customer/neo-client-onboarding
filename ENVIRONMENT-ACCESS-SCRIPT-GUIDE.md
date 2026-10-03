# Update-NeologikEnvironmentAccess.ps1: What the Script Does

## Overview

`Update-NeologikEnvironmentAccess.ps1` is the environment access script. A Global Administrator runs the environment access script, signed in with the account of the Global Administrator. Neologik asks for a run on one of two occasions.

| Run | When Neologik asks for the run | What the environment access script does |
|---|---|---|
| The first run | Before an existing environment moves to version 5 of the Neologik Platform | Confirms the directory objects that the Neologik Platform uses. Reduces the access of the deployment identity to the roles that the deployment identity needs |
| The later run | When an agent or an App is to work unattended in Microsoft 365 | Applies the grants that the files from Neologik list. Makes no other change |

An environment that this version of the onboarding kit onboarded already holds the access that the first run produces. Such an environment needs the first run only when Neologik asks for the first run.

Neologik sends the complete command, with every value filled in. You supply the sign-in.

The environment access script reads the current state before each change. The environment access script changes only what differs from the expected state. A Global Administrator can run the environment access script again at any time. With `-Verify` the environment access script reports each change that a run would make, and writes nothing.

## Contents

1. [What you need](#what-you-need)
2. [How to run the environment access script](#how-to-run-the-environment-access-script)
3. [The first run](#the-first-run)
4. [The later run](#the-later-run)
5. [What the environment access script never does](#what-the-environment-access-script-never-does)
6. [What the sign-in asks you to approve](#what-the-sign-in-asks-you-to-approve)
7. [What you receive](#what-you-receive)
8. [Questions](#questions)
9. [Help](#help)

## What you need

| Requirement | Reason |
|---|---|
| PowerShell 7.4 or later | The environment access script stops on an earlier version |
| A workstation with a desktop and a browser | The environment access script opens the sign-in page in the browser of the workstation. You complete the sign-in in the browser |
| A Global Administrator account in your tenant | Only a Global Administrator can grant and remove Microsoft Graph application permissions and directory roles |
| Owner or User Access Administrator on the subscription, for the first run | The same account changes the Azure role assignments of the deployment identity |
| Exchange Administrator or Global Administrator, for a later run with mailbox grants | The mailbox grants are made in Exchange Online |
| The command from Neologik | The command names your tenant, your subscription, your resource group and the application registrations of the environment |
| The files from Neologik, for the later run | The files list the grants to apply |

The environment access script installs the PowerShell modules that the run needs, for your user account, when the modules are missing.

| Modules | Run |
|---|---|
| The Microsoft Graph modules | Every run |
| The Az modules | The first run |
| The Exchange Online module | A later run with mailbox grants |

Before the environment access script changes anything, the environment access script confirms three facts.

1. The workstation can reach each Microsoft address that the environment access script uses.
2. The PowerShell modules load.
3. The signed-in account holds an active Global Administrator role.

The first run makes one more check before the first run changes an Azure role. The signed-in account must hold Owner or User Access Administrator on the subscription.

## How to run the environment access script

1. Place the onboarding kit in a folder on your workstation. The first run reads `NeologikGuestUsers.txt` from the folder of `Update-NeologikEnvironmentAccess.ps1`.
2. Open PowerShell 7 in that folder.
3. Paste the command from Neologik and press Enter.
4. The environment access script opens the sign-in page in your browser. Sign in as a Global Administrator. The environment access script waits for up to 5 minutes.
5. In the first run, the environment access script signs in a second time, to Azure. The browser uses the same account and does not usually ask again. In a later run with mailbox grants, the environment access script signs in to Exchange Online in the same way.
6. Read the summary table on screen. Send the summary file to Neologik.

When the browser sign-in does not complete, the environment access script prints a web address and a code. Open the web address in a browser on any device, enter the code and sign in. The environment access script waits for up to 15 minutes. Some organisations block this sign-in with a Conditional Access policy. The environment access script then says so and tries the next method.

To see what a run would change, add `-Verify` to the end of the command. The sign-ins are the same. The environment access script reports each pending change as `WOULD` and writes nothing.

## The first run

The command selects the first run when the command names no grants file. The first run has five steps. The environment access script checks each item of a step separately. When an item fails, the environment access script records the item and the reason in the summary and continues.

### Step 1: The agent identity blueprint and the permissions of the deployment identity

| Item | What the environment access script checks | When the environment access script changes the item |
|---|---|---|
| The agent identity blueprint, `Neologik Agent Blueprint - default - <short name>` | The agent identity blueprint exists | The environment access script creates the agent identity blueprint when the agent identity blueprint is absent |
| The service principal of the agent identity blueprint | The service principal exists | The environment access script creates the service principal when the service principal is absent |
| Owner | The deployment identity owns the agent identity blueprint and the service principal | The environment access script adds the deployment identity as an owner when the deployment identity is not an owner |
| Sponsor | The agent identity blueprint has a sponsor. The sponsor is the person who is accountable for the agents of the environment. The summary names the sponsor | The environment access script adds the signed-in Global Administrator as the sponsor when the agent identity blueprint has no sponsor |
| The permission of the service principal | The service principal holds `AgentIdUser.ReadWrite.IdentityParentedBy`. The permission covers only the agent users of this agent identity blueprint | The environment access script grants the permission when the permission is absent |
| The federated credentials | The agent identity blueprint holds the three federated credentials through which the Neologik deployment signs in as the agent identity blueprint | The environment access script adds a federated credential when the federated credential is absent |
| The permissions that the deployment identity keeps | The deployment identity holds `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` | The environment access script grants a permission when the permission is absent |
| The permissions that the deployment identity does not need | The deployment identity holds none of these seven permissions:<br>`Application.Read.All`<br>`AgentIdentityBlueprint.Create`<br>`AgentIdentityBlueprint.UpdateAuthProperties.All`<br>`AgentIdentityBlueprintPrincipal.Create`<br>`AgentIdentity.Create.All`<br>`AgentIdUser.ReadWrite.All`<br>`Group.Create` | The environment access script removes a permission that the deployment identity holds. The environment access script removes a permission only after the environment access script has confirmed the two permissions that the deployment identity keeps |

The deployment identity can already own one agent identity blueprint with another short name. The environment access script then uses that agent identity blueprint and creates no second one. The summary then names the agent identity blueprint that the environment access script used.

### Step 2: The security groups, the Neologik guest users and the memberships

Version 5 of the Neologik Platform uses four security groups in your tenant. The onboarding script creates them for a new environment. An environment set up before version 5 has two of them. The environment access script completes the set.

| Item | What the environment access script checks | When the environment access script changes the item |
|---|---|---|
| `Neologik User Group - <short name>` | The group exists | The environment access script creates the group when the group is absent |
| `Neologik NCE Contributors - <short name>` | The group exists under this name. The group is the user group of the Neologik Context Engine | The environment access script renames `Neologik NCE User Group - <short name>` to this name. The group keeps the id and the members. The environment access script creates the group when no group exists under either name |
| `Neologik NCE Admins - <short name>` | The group exists. Members of the group administer the Neologik Context Engine | The environment access script creates the group when the group is absent |
| `Neologik Admin User Group - <short name>` | The group exists | The environment access script creates the group when the group is absent |
| The Neologik support accounts | Each mail address in `NeologikGuestUsers.txt` is a guest of your tenant | The environment access script invites an account that is absent. Microsoft sends the invitation |
| The memberships | Each guest and the signed-in administrator are direct members of every one of the four groups | The environment access script adds a membership that is absent. The environment access script removes no member |

When the command names a group by id, the id decides, whatever the name of the group. When the command names no id, the environment access script finds the group by name.

The summary item `NCE Admins group` states the id of the group. Neologik records the id for the environment, so that members of the group hold the administrator role in the Neologik Context Engine.

When `NeologikGuestUsers.txt` is not beside the environment access script, the summary reports the item `Neologik guest users` as `SKIPPED`. Run the environment access script from the folder of the onboarding kit, or add `-GuestUsersFile <path>` to the command.

### Step 3: The role groups of the Neologik Context Engine

The Neologik Context Engine reads the groups claim of the sign-in token to authorise a user. The groups claim lists only the security groups that are assigned to the Platform Sign-in application. The environment access script assigns the user group that the command names, and the group `Neologik NCE Admins - <short name>`, to the application `Neologik Platform Sign-in - <short name>`, when an assignment is absent.

A user must be a direct member of the security group. A member of a nested group cannot sign in. The environment access script reports the number of direct members.

### Step 4: Consent and ownership

| Item | What the environment access script checks | When the environment access script changes the item |
|---|---|---|
| Administrator consent for the Platform Sign-in application | The consent for the whole tenant exists | Never. When the consent is absent, the environment access script prints the consent address. A Global Administrator opens the consent address and gives the consent. Run the environment access script again afterwards to confirm the consent |
| Consent for the SharePoint application | The SharePoint application of the environment holds the Microsoft Graph application permission `Sites.Selected` | When an earlier SharePoint application of Neologik in your tenant holds a SharePoint permission. A consent belongs to one application, so the environment access script grants `Sites.Selected` to the SharePoint application of the environment. When no application holds a SharePoint permission, the environment access script grants nothing. When the configuration file records SharePoint ingestion, the environment access script then prints the consent address |
| Ownership of the application registrations | The deployment identity owns each application registration that the command names by client id, and the service principal of each. The command names the Platform Sign-in application, the SharePoint application and the application registration of each agent | The environment access script adds the deployment identity as an owner when the deployment identity is not an owner |
| Unique name | The Platform Sign-in application and the SharePoint application hold the unique name by which the deployment finds each application | The environment access script sets the unique name when the unique name is empty. The environment access script reports another value and changes nothing |
| Client secrets | Each named application registration is read for client secrets that the deployment did not create | Never. The summary lists each such client secret. See below |
| Other application registrations | Every other application registration whose name begins `Neologik` | Never. The summary lists each such application registration as `Review`, so that you and Neologik can confirm that the command missed none |

The deployment replaces the client secrets of the Platform Sign-in application and of the application registration of each agent. When one of these application registrations holds a client secret that the deployment did not create, the summary lists the client secret as `PENDING`. Confirm with Neologik that nothing else uses the client secret before the upgrade.

### Step 5: Permission reduction

The environment access script first confirms that the deployment identity holds nine Azure roles. The environment access script assigns a role that is absent.

| Scope | Roles |
|---|---|
| Resource group | Contributor<br>Key Vault Certificates Officer<br>Key Vault Secrets Officer<br>Storage Blob Data Contributor<br>Azure Kubernetes Service RBAC Cluster Admin<br>Monitoring Contributor<br>Role Based Access Control Administrator |
| Subscription | Reader<br>Cost Management Contributor |

The environment access script removes the wider access only when the deployment identity holds all nine roles. When the environment access script cannot assign one of the nine roles, the environment access script removes nothing. The deployment never loses access part way through the run.

| What the environment access script removes | Condition |
|---|---|
| Contributor and User Access Administrator on the subscription | The deployment identity holds the role |
| The directory role Application Administrator | The deployment identity holds the role |
| The membership of the group `Neologik Admin User Group - <short name>` | The deployment identity is a member, and each SQL server in the resource group names the deployment identity as the Microsoft Entra administrator. Until then the environment access script keeps the membership, because the membership is the only access of the deployment identity to SQL. The summary then reads `HELD` |
| Every other Azure role in the subscription | The role is outside the nine roles above. The environment access script keeps the role `Cognitive Services Content Understanding Contributor` on a resource in the resource group |
| Every other directory role | The deployment identity holds the role |
| Every other group membership | The deployment identity is a member |

Last, the environment access script records the version of the onboarding kit on the resource group, in the tag `NeologikOnboardingKit`. The environment access script keeps your other tags and writes the tag only when the value differs. The Neologik Platform reads the tag before an upgrade.

The first run changes nothing on a managed identity, on a security group or on a user.

## The later run

The command selects the later run when the command names a grants file. The later run applies what the files list. The later run makes none of the checks of the first run.

### Step 6: Grants to agent users, with `-AgentGrantsFile`

An agent or an App that works unattended has an agent identity and an agent user account in your directory. For each agent and each App in the file, the environment access script creates one delegated permission grant. The grant lets the agent identity act as the agent user of that agent identity. The grant holds exactly the permissions that the file lists. The grant names one agent user. The grant is not a grant for the whole tenant.

The file can also list Microsoft Graph application permissions for named workload identities. The environment access script grants those permissions. The file records whether the environment uses SharePoint ingestion. When the environment uses SharePoint ingestion, the environment access script checks the consent of the SharePoint application. An earlier SharePoint application of Neologik in your tenant can hold a SharePoint permission. The environment access script then grants `Sites.Selected` to the SharePoint application of the environment. Otherwise the environment access script prints the consent address when the consent is absent.

When the file marks an entry as not ready, the summary reads `SKIPPED` for the entry. Neologik sends a new file when the entry is ready.

### Step 7: Mailbox grants, with `-MailboxGrantsFile`

For each email channel in the file, the environment access script grants three Exchange Online roles to the identity of the email channel.

| Role | Limit |
|---|---|
| `Application Mail.Read` | The one mailbox that the file names |
| `Application Mail.ReadWrite` | The one mailbox that the file names |
| `Application Mail.Send` | The one mailbox that the file names |

The grant needs two objects in Exchange Online: a service principal for the identity, and a management scope that holds that one mailbox. The environment access script creates each object when the object is absent. The identity receives no access to any other mailbox.

With `-RemoveLegacyGrantAppIds` the environment access script also removes the Exchange Online role assignments of an identity that the environment has stopped using. An identity that the file records as still in use keeps the role assignments.

When your Exchange Online organisation has never been customised, the environment access script enables organisation customisation. Exchange Online requires the setting before a role assignment. Exchange Online needs the setting once.

## What the environment access script never does

- The environment access script never reads, moves or deletes your data. The environment access script reads directory objects, Azure role assignments and Exchange Online role assignments.
- The environment access script never changes an application registration that the command does not name.
- The environment access script never creates a user, a group or a secret.
- The environment access script never gives administrator consent. The environment access script prints the consent address. You decide.
- The environment access script never removes a wider role before the deployment identity holds the roles that replace the wider role.
- The environment access script never sends anything to Neologik. You send the summary file.
- The environment access script never stores your sign-in.

## What the sign-in asks you to approve

The environment access script signs in to Microsoft Graph with your account. At the first use, Microsoft lists the permissions that the environment access script requests. Each permission is a delegated permission. A delegated permission works as you, for the run only. The sign-in grants nothing to an application.

| Permission | Requested in | What the environment access script uses the permission for |
|---|---|---|
| `Application.ReadWrite.All` | Every run | To read the application registrations. To add the owner and the unique name. To add the federated credentials of the agent identity blueprint. To read and to add the sponsor of the agent identity blueprint |
| `AppRoleAssignment.ReadWrite.All` | Every run | To grant and remove Microsoft Graph application permissions, and to assign the security group to the Platform Sign-in application |
| `Directory.Read.All` | Every run | To read the service principals, the groups and the directory roles |
| `User.Read` | Every run | To identify your account |
| `DelegatedPermissionGrant.Read.All` | Every run | To read the consent of the Platform Sign-in application |
| `AgentIdentityBlueprint.Create`<br>`AgentIdentityBlueprint.AddRemoveCreds.All`<br>`AgentIdentityBlueprintPrincipal.Create` | Every run | To create the agent identity blueprint, the service principal and the federated credentials when each is absent |
| `RoleManagement.ReadWrite.Directory` | The first run | To remove directory roles from the deployment identity |
| `GroupMember.ReadWrite.All` | The first run | To add the Neologik guest users and the signed-in administrator to the security groups, and to remove the deployment identity from groups |
| `Group.ReadWrite.All` | The first run | To create a security group of version 5 that is absent, and to rename the user group of the Neologik Context Engine |
| `User.Invite.All` | The first run | To invite a Neologik support account that is not yet a guest of your tenant |
| `AgentIdentityBlueprintPrincipal.ReadWrite.All` | The first run | To add the deployment identity as an owner of the service principal of the agent identity blueprint. The environment access script adds the owner when that service principal has none |
| `DelegatedPermissionGrant.ReadWrite.All` | A later run with `-AgentGrantsFile` | To create the grants to agent users |

The sign-in to Azure and the sign-in to Exchange Online use the same account and show no list of permissions.

## What you receive

The environment access script prints a summary table. The environment access script writes the same table to a summary file in the folder of the environment access script.

| Run | Summary file |
|---|---|
| The first run | `Neologik_EnvironmentAccess_PreWindow_<date and time>.json` |
| The later run | `Neologik_EnvironmentAccess_PostWindow_<date and time>.json` |

The environment access script writes to the current folder when the folder of the environment access script is not writable. The environment access script writes to the temporary folder when the current folder is not writable. The environment access script reports the path.

The summary file holds six things:

- the tenant id
- the client id of the deployment identity
- the time of the run
- the Microsoft Graph application permissions that the deployment identity holds
- the ids of the two role groups of the Neologik Context Engine, after the first run
- every item of the summary

The summary file holds no secret. Send the summary file to Neologik as the record of the run.

| Result | Meaning |
|---|---|
| `Present`, `Already granted`, `Already assigned`, `Already an owner`, `Already set`, `None`, `Not held`, `None from another source` | Nothing to change |
| `Created`, `Added`, `Granted`, `Assigned`, `Updated`, `Set`, `Removed` | Changed in this run |
| `Review` | Listed for you to read. The environment access script changed nothing |
| `Not checked`, `Not needed`, `Not listed`, `Not required`, `Not present`, `Kept`, `HELD` | The item did not apply to this run, or the environment access script keeps the item on purpose. The row gives the reason |
| `WOULD` | A change that a run without `-Verify` would make |
| `MISSING`, `SKIPPED`, `NOT FOUND`, `PENDING`, `UNKNOWN`, `FAILED` | Needs attention. The row gives the reason |

| Exit code | Meaning |
|---|---|
| 0 | Every item is in the expected state |
| 1 | An item needs attention. With `-Verify`, a change is pending |

## Questions

**Does the first run give Neologik more access?**

No. The first run removes access from the deployment identity. The first run adds only a role or a permission that is absent from the set listed in this document. On an environment onboarded before version 5, the deployment identity ends the run with less access than the deployment identity held before the run.

**Why does my account need such wide permissions?**

Only a Global Administrator can remove a directory role or grant a Microsoft Graph application permission. The environment access script uses your sign-in for the run. The sign-in grants nothing to your account and stores nothing.

**What happens when an item is already in the expected state?**

The environment access script reports the item and moves to the next item. A second run on an environment in the expected state changes nothing.

**What happens when an item fails?**

The environment access script records the failure with the reason, continues with the other items and ends with exit code 1. Send the summary file to Neologik.

**Why does the summary list application registrations that the environment access script did not change?**

The deployment identity manages only the application registrations that the deployment identity owns. The environment access script adds the deployment identity as an owner of exactly the application registrations that the command names. The summary lists every other application registration whose name begins `Neologik`, so that you and Neologik can confirm that the command missed none.

## Help

Email support@neologik.ai with the summary file, the name of your organisation and the host name of the environment.
