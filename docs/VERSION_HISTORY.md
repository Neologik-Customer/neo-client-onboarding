# Version History

## Overview

This document lists the versions of the Neologik onboarding kit. For each version, this document states what changed for you.

| Subject | Detail |
|---|---|
| Version of the onboarding kit | The version of the onboarding kit follows the version of the Neologik Platform |
| Record on your resource group | The onboarding script records the version of the onboarding kit on your resource group, in the tag `NeologikOnboardingKit`. The migration script of the Neologik migration package records the version that a migration brings your environment to. The Neologik Platform reads the tag before an upgrade |
| Versions 5.0.4 and 5.0.5 | The onboarding kit has no version 5.0.4 and no version 5.0.5 |

## Contents

1. [Scripts in this version](#scripts-in-this-version)
2. [Version 5.0.23](#version-5023)
2. [Version 5.0.22](#version-5022)
2. [Version 5.0.21](#version-5021)
2. [Version 5.0.20](#version-5020)
2. [Version 5.0.19](#version-5019)
2. [Version 5.0.18](#version-5018)
2. [Version 5.0.17](#version-5017)
2. [Version 5.0.16](#version-5016)
2. [Version 5.0.15](#version-5015)
2. [Version 5.0.14](#version-5014)
2. [Version 5.0.13](#version-5013)
2. [Version 5.0.12](#version-5012)
2. [Version 5.0.11](#version-5011)
3. [Version 5.0.10](#version-5010)
3. [Version 5.0.9](#version-509)
3. [Version 5.0.8](#version-508)
4. [Version 5.0.7](#version-507)
5. [Version 5.0.6](#version-506)
6. [Version 5.0.3](#version-503)
7. [Version 5.0.2](#version-502)
8. [Version 5.0.1](#version-501)
9. [Version 5.0.0](#version-500)
10. [Earlier versions](#earlier-versions)

## Scripts in this version

The table shows the version that each script reports.

| Script | Version of the script | Purpose |
|---|---|---|
| `Install-NeologikEnvironment.ps1` | v5.0.14 | Prepares the Azure subscription and the Microsoft Entra tenant for one Neologik Platform environment |
| `Grant-NeologikAgentAccess.ps1` | Onboarding kit version v5.0.23 | Applies the grants that agents and Apps need to work unattended in Microsoft 365, from the two files that the Neologik Context Engine exports |
| `Export-NeologikCertificate.ps1` | 1.1 | Builds the PFX file for the TLS certificate of the environment, on the workstation |
| `Register-NeologikResourceProviders.ps1` | 1.0 | Confirms the Azure resource provider registrations on the subscription |
| `Upgrade-TeamsAppInstallations.ps1` | v0.2.1 | Upgrades the Neologik Teams app that each user has installed to the latest version in the Teams app catalogue |

## Version NEXT

This version is on the line of Neologik Platform v5.1 and is not yet released.

| Item | Change |
|---|---|
| `ANALYTICS-REPORTING-GUIDE.md` | New document. What the environment reports to Neologik, what the environment never reports, the retention period and how to withdraw from reporting |
| `Install-NeologikEnvironment.ps1` | Version v5.0.9. After a failure, the onboarding script prints the closing messages: the path of the log, the permission that is missing, and how to resume. Before this version, the first error message stopped the onboarding script before the closing messages. A run that stops because a permission is missing ends with exit code 2 |
| `Install-NeologikEnvironment.ps1` | The onboarding script downloads the PowerShell installer of the latest release. Before this version, the address named one fixed version |
| `Install-NeologikEnvironment.ps1` | The configuration file records both roles of the deployment identity on the subscription: Reader and Cost Management Contributor |
| `Install-NeologikEnvironment.ps1` | A run resumed from the first checkpoint asks the questions, because the first checkpoint holds no configuration. A resumed run honours `-SkipGuestInvitation` from the command line |
| `QUICK-REFERENCE.md` | The document describes the resume from the first checkpoint and exit code 2 |
| `Install-NeologikEnvironment.ps1` | The onboarding script creates the application registration of the deployment identity for a single tenant. The deployment signs in to your tenant only |
| Documents | The documents state why the Platform Sign-in application accepts accounts of more than one tenant: Neologik support staff can sign in with an account of the Neologik tenant, when you allow that tenant |
| `Grant-NeologikAgentAccess.ps1` | The grants script signs in to Microsoft Graph and to Exchange Online in the browser of the workstation first. A device code is the second method. Before this version, a device code was the first method. An organisation that blocks the device code with a Conditional Access policy could not complete the sign-in |
| `Grant-NeologikAgentAccess.ps1` | When a Conditional Access policy refuses a sign-in, the grants script says so and tries the next method at once |
| `GRANT-AGENT-ACCESS-SCRIPT-GUIDE.md` | The document describes the browser sign-in and the device code as the second method |
| `README.md` | A new requirement row under Before you start: a customer billed through a Cloud Solution Provider partner asks the partner to enable the cost visibility policy, so the platform's return on investment report can show running costs |
| `Install-NeologikEnvironment.ps1` | Version v5.0.10. The limited Role Based Access Control Administrator on the subscription lets the deployment identity assign a third role: Cost Management Reader. The deployment assigns that role on the resource group that Azure Kubernetes Service creates for the nodes of the cluster to the identity of the configuration API of the Neologik Platform, which reads the daily cost of the nodes for the return on investment report. An assignment with the old condition receives the new condition |
| Documents | The documents name the three roles the limited administrator may assign and the reason for the third |
| `Install-NeologikEnvironment.ps1` | Version v5.0.11. The rows above that name versions v5.0.9 and v5.0.10 ship as v5.0.11. Onboarding kit version 5.0.16 released a different version v5.0.9 of the onboarding script |
| `Install-NeologikEnvironment.ps1` | Version v5.0.12. The rows above that name versions v5.0.9, v5.0.10 and v5.0.11 ship as v5.0.12. Onboarding kit version 5.0.17 released a different version v5.0.10 of the onboarding script: the exact-scope role checks and the read-back of the roles of the deployment identity, which this version carries |
| `Install-NeologikEnvironment.ps1` | Version v5.0.13. The rows above that name versions v5.0.9, v5.0.10, v5.0.11 and v5.0.12 ship as v5.0.13. Onboarding kit version 5.0.18 released a different version v5.0.11 of the onboarding script: the third role, Cost Management Reader, on its own |
| `Install-NeologikEnvironment.ps1` | Version v5.0.14. The rows above that name versions v5.0.9, v5.0.10, v5.0.11, v5.0.12 and v5.0.13 ship as v5.0.14. Onboarding kit version 5.0.19 released a different version v5.0.12 of the onboarding script: the limited Role Based Access Control Administrator assignment on the subscription is removed and created again with the limit, which this version carries |
| `docs/NETWORK-GUIDE.md` | The Standard row names the container registry among the services that accept Microsoft Entra ID sign-in only. From Neologik Platform v5.1 the registry's admin user is off |
| `docs/NETWORK-GUIDE.md` | On a Private Endpoint environment the Video Indexer account is reached through a private endpoint, and the account's private DNS zone joins the table. The endpoint that collects the cluster's metrics accepts requests from the internet. On both deployment types the Log Analytics workspace, Application Insights and the storage account of the stop and start schedule accept Microsoft Entra ID sign-in only. These changes come with Neologik Platform v5.1 |

## Version 5.0.23

**Date**: 2026-10-21

| Item | Change |
|---|---|
| `.gitattributes` | Marks `docs/VERSION_HISTORY.md` `export-ignore`, so the zip of `main` leaves the version history out |
| `README.md` | The table of documents leaves out the version history |
| `Install-NeologikEnvironment.ps1` | No change to the script. The onboarding script records the version `v5.0.23` on the resource group |
| `Grant-NeologikAgentAccess.ps1` | No change to the script. The grants script reports the onboarding kit version v5.0.23 |

## Version 5.0.22

**Date**: 2026-10-21

| Item | Change |
|---|---|
| `docs/NETWORK-GUIDE.md` | Names every resource that accepts requests from the internet or an account key. On a Private Endpoint environment the monitoring resources accept requests from the internet. Where used, so do the Video Indexer account and the storage account of the cluster's stop and start schedule. On a Standard environment the schedule's storage account accepts an account key |
| `Install-NeologikEnvironment.ps1` | No change to the script. The onboarding script records the version `v5.0.22` on the resource group |
| `Grant-NeologikAgentAccess.ps1` | No change to the script. The grants script reports the onboarding kit version v5.0.22 |

## Version 5.0.21

**Date**: 2026-10-21

| Item | Change |
|---|---|
| `docs/NETWORK-GUIDE.md` | Names the two deployment types Standard and Private Endpoint. The guide lists the data services of a Private Endpoint environment, which refuse requests from the internet. The guide also names the three monitoring resources, which accept requests from the internet. The Standard row names the services that accept Microsoft Entra ID sign-in only, and the NGINX ingress controller. The reduced layout gives the workload pods a `/20`, enough to move the workload node pool to a new VM size |
| `docs/PRE-ONBOARDING-INFO-GATHERING.md` | Names the two deployment types Standard and Private Endpoint |
| `Install-NeologikEnvironment.ps1` | No change to the script. The onboarding script records the version `v5.0.21` on the resource group |
| `Grant-NeologikAgentAccess.ps1` | No change to the script. The grants script reports the onboarding kit version v5.0.21 |

## Version 5.0.20

**Date**: 2026-10-20

| Item | Change |
|---|---|
| `docs/NETWORK-GUIDE.md` | New guide, for the person who plans your networks. The guide states the address ranges that the deployment builds for each deployment type, and the private DNS zones of a `neo-secure` environment. The guide also states the two public addresses of an environment and the type of the public DNS record. The guide ends with the questions to answer before onboarding. Every range is a setting of your environment, chosen before the first deployment |
| `README.md` and `docs/PRE-ONBOARDING-INFO-GATHERING.md` | Link the network guide |
| `Install-NeologikEnvironment.ps1` | No change to the script. The onboarding script records the version `v5.0.20` on the resource group |
| `Grant-NeologikAgentAccess.ps1` | No change to the script. The grants script reports the onboarding kit version v5.0.20 |

## Version 5.0.19

**Date**: 2026-10-20

| Item | Change |
|---|---|
| `Install-NeologikEnvironment.ps1` | Version v5.0.12. The onboarding script now replaces an existing Role Based Access Control Administrator assignment on the subscription that lacks the three-role limit. The onboarding script removes the assignment and creates the assignment again with the limit. Before this version, the onboarding script updated the assignment, and Azure kept the earlier limit. The deployment identity then could not assign Cost Management Reader. A run on a new subscription is unchanged |
| `Grant-NeologikAgentAccess.ps1` | No change to the script. The grants script reports the onboarding kit version v5.0.19 |

## Version 5.0.18

**Date**: 2026-10-19

| Item | Change |
|---|---|
| `Install-NeologikEnvironment.ps1` | Version v5.0.11. The Role Based Access Control Administrator role that the deployment identity holds on the subscription is now limited to three roles instead of two: Reader, AppGw for Containers Configuration Manager and Cost Management Reader. The deployment assigns Cost Management Reader on the resource group that Azure Kubernetes Service creates for the nodes of the cluster to the identity of the configuration API of the Neologik Platform, which reads the daily cost of the nodes for the return on investment report. None of the three roles allows a change to an Azure resource. The onboarding script records the version `v5.0.18` on the resource group |
| `Grant-NeologikAgentAccess.ps1` | No change to the script. The grants script reports the onboarding kit version v5.0.18 |
| Guides | `README.md`, `docs/QUICK-REFERENCE.md`, `docs/TECHNICAL-REFERENCE.md` and `docs/secure-overview.md` describe the three roles |

## Version 5.0.17

**Date**: 2026-10-12

| Item | Change |
|---|---|
| `README.md` | The step "Confirm that Neologik has the configuration file" now matches the completion summary of the onboarding script: when the upload failed, upload the configuration file to the container `json` of the deployment storage account in the Azure portal. The earlier text asked you to send the file to support@neologik.ai |
| `Install-NeologikEnvironment.ps1` | Version v5.0.10. The onboarding script now counts a role only when the assignment is at the scope the script assigns it, with the condition the script gives it. Earlier versions also counted an assignment inherited from the subscription, so the limited Role Based Access Control Administrator on the subscription stood in for the unlimited role on the resource group, which was never assigned, and the first deployment of the environment failed. After the assignments, the onboarding script now reads the roles of the deployment identity back, records them in the configuration file and in the completion summary, and stops the run when a role is missing, naming the role and the scope. The onboarding script records the version `v5.0.17` on the resource group |
| `Grant-NeologikAgentAccess.ps1` | No change to the script. The grants script reports the onboarding kit version v5.0.17 |

## Version 5.0.16

**Date**: 2026-10-12

| Item | Change |
|---|---|
| `Install-NeologikEnvironment.ps1` | Version v5.0.9. The onboarding script submits the registrations of the five resource providers that the onboarding script needs after the check of the roles, as before. The onboarding script now submits the registrations of the other resource providers and the preview features at the end of the run, after the managed identities. The onboarding script then confirms every registration. The onboarding script records the version `v5.0.16` on the resource group |
| `Grant-NeologikAgentAccess.ps1` | No change to the script. The grants script reports the onboarding kit version v5.0.16 |
| `resource-providers.txt` | The notes at the top of the file describe the new order. The list is unchanged |
| Documents | `docs/QUICK-REFERENCE.md` and `docs/TECHNICAL-REFERENCE.md` describe the new order |

## Version 5.0.15

**Date**: 2026-10-08

| Item | Change |
|---|---|
| `Grant-NeologikAgentAccess.ps1` | New script, the grants script. The grants script applies the agent grants file and the mailbox grants file that the Neologik Context Engine exports: the grants to agent users, the Microsoft Graph application permissions of workload identities, the check of the SharePoint consent and the Exchange Online mailbox grants of the email channels. The grants script reads the tenant and the environment from the agent grants file, so the command names the files and nothing else. The grants script signs in to Microsoft Graph and, with a mailbox grants file, to Exchange Online. The grants script signs in to Azure never |
| `Grant-NeologikAgentAccess.ps1` | The sign-in to Microsoft Graph requests four delegated permissions at most: `Directory.Read.All`, `User.Read`, `AppRoleAssignment.ReadWrite.All` and, with an agent grants file, `DelegatedPermissionGrant.ReadWrite.All` |
| `Grant-NeologikAgentAccess.ps1` | The run writes the log file `NeologikAgentAccess_<date and time>.log` and the summary file `Neologik_AgentAccess_<date and time>.json`, and ends with the list `FILES TO SEND TO NEOLOGIK` |
| `Update-NeologikEnvironmentAccess.ps1` | Removed from the onboarding kit. The first run and the later run of an environment that moves to version 5 of the Neologik Platform are now the migration script, `Migrate-NeologikEnvironment.ps1`, which Neologik sends to a migrating customer as the Neologik migration package. The grants runs of the removed script are the grants script above |
| `GRANT-AGENT-ACCESS-SCRIPT-GUIDE.md` | New document. What the grants script applies, what the sign-in asks you to approve and what you receive |
| `ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md` | Removed with the script that the document described |
| `Install-NeologikEnvironment.ps1` | No change to the script. The onboarding script records the version `v5.0.15` on the resource group |
| Documents | `README.md`, `FINISHING-STEPS-GUIDE.md` and `AGENT-ACCOUNT-ACCESS-GUIDE.md` name the grants script |
| `NeologikGuestUsers.txt` | One Neologik support account that no longer works for Neologik is removed from the list |
| Documents | The preparation steps of `README.md` name the inner folder of a zip downloaded from GitHub, lift the execution policy for the window with `Bypass` in place of `RemoteSigned`, and say what to do when Group Policy enforces the policy. The other guides use `Bypass` in the same step |
| Documents | The approver document, `docs/QUICK-REFERENCE.md`, states the two commands that the administrator runs before the first run. The first command removes the download mark from the scripts. The second command lifts the execution policy for the window. The onboarding script makes neither change |

## Version 5.0.14

**Date**: 2026-10-05

| Item | Change |
|---|---|
| `Update-NeologikEnvironmentAccess.ps1` | Step 5 assigns a third role on the subscription: Role Based Access Control Administrator, limited by a condition to two roles, Reader and AppGw for Containers Configuration Manager. The deployment needs the role for the identity of the ingress controller of a secure environment. That identity needs Reader on the resource group that Azure Kubernetes Service creates for the nodes of the cluster. That resource group is outside the resource group of the environment. The deployment identity can assign those two roles and no other. Step 5 and step 8 now confirm ten roles |
| `Update-NeologikEnvironmentAccess.ps1` | The deployment identity may already hold the role on the subscription without the limit. The first run then reports the assignment and keeps it. The later run writes the limit onto the assignment |
| `Update-NeologikEnvironmentAccess.ps1` | The environment access script records the version `v5.0.14` on the resource group |
| `Install-NeologikEnvironment.ps1` | Version v5.0.8. The onboarding script assigns the same limited role on the subscription, and records the version `v5.0.14` on the resource group |
| Documents | The documents list the limited role and the reason for it |

## Version 5.0.13

**Date**: 2026-10-05

| Item | Change |
|---|---|
| `Update-NeologikEnvironmentAccess.ps1` | Every run writes a snapshot file, `Neologik_EnvironmentAccess_Snapshot_Pre_<date and time>.json` after the first run and `..._Post_...` after the later run: the state of the application registrations, the security groups and the deployment identity as the run leaves them, with every item of the summary and no secret value. Neologik compares the two snapshots to confirm the upgrade |
| `Update-NeologikEnvironmentAccess.ps1` | The run ends with the list `FILES TO SEND TO NEOLOGIK`: the log file, the summary file and the snapshot file, each with its full path. The list also appears after a run that stopped before its steps |
| `Update-NeologikEnvironmentAccess.ps1` | The environment access script uploads the three files with your Azure session: first to the storage account that the onboarding script created (`stneodeploy...`, found through the configuration file or in the resource group), into the containers `logs` and `json` beside the files of the onboarding; else to the storage account that the new parameter `-UploadStorageAccountName` names, into the container `onboarding-access`. When a storage account refuses the first upload, the environment access script assigns the role Storage Blob Data Contributor on it to your account and tries again while the role takes effect. A storage account that cannot be reached from the workstation leaves the files listed |
| `Update-NeologikEnvironmentAccess.ps1` | The environment access script records the version `v5.0.13` on the resource group |
| `Install-NeologikEnvironment.ps1` | No change to the script. The onboarding script records the version `v5.0.13` on the resource group |
| `ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md` | The document describes the snapshot file, the list of files and the upload |

## Version 5.0.12

**Date**: 2026-10-05

| Item | Change |
|---|---|
| `Update-NeologikEnvironmentAccess.ps1` | The first run removes nothing. The first run confirms the directory objects, grants the two Microsoft Graph application permissions and the nine Azure roles that the deployment identity needs, and records the version of the onboarding kit. The deployment identity keeps its wider access until the later run, so that Neologik can repair a failed first run or a failed deployment with that access |
| `Update-NeologikEnvironmentAccess.ps1` | New parameter `-LaterRun`. The later run applies the grants that the files list, when the command names a file, and then reduces the access of the deployment identity: the seven Microsoft Graph application permissions that the deployment identity no longer needs, Contributor and User Access Administrator on the subscription, the directory role Application Administrator, the membership of the Admin User Group, and every other Azure role, directory role and group membership. The later run needs `SubscriptionId` and `ResourceGroupName`, and a signed-in account with Owner or User Access Administrator on the subscription. A later command that names a grants file and not `-LaterRun` applies the file and nothing else, as before |
| `Update-NeologikEnvironmentAccess.ps1` | The sign-in of the first run no longer requests `RoleManagement.ReadWrite.Directory`. The sign-in of the later run with `-LaterRun` requests `RoleManagement.ReadWrite.Directory` and `GroupMember.ReadWrite.All` |
| `Update-NeologikEnvironmentAccess.ps1` | The environment access script writes the log file `NeologikEnvironmentAccess_<date and time>.log` beside the script from the first line of the run: every message, each failed request to Microsoft Graph with its status and request id, and the summary table. The log file holds no secret |
| `Update-NeologikEnvironmentAccess.ps1` | The summary file is written on every exit, a run that stopped before its steps included. The summary file names the version of the onboarding kit, the signed-in account, the log file and the reason a run stopped early |
| `Update-NeologikEnvironmentAccess.ps1` | The environment access script records the version `v5.0.12` on the resource group |
| `Install-NeologikEnvironment.ps1` | No change to the script. The onboarding script records the version `v5.0.12` on the resource group |
| `ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md` | The document describes the two runs as they now are, the new parameter and the two files of a run |

## Version 5.0.11

**Date**: 2026-10-03

| Item | Change |
|---|---|
| `Update-NeologikEnvironmentAccess.ps1` | When the administrator who runs the environment access script is also a Neologik support account on the guest list, the first run adds the account to each security group once and reports the account as the signed-in administrator. Before this version, the first run added the account a second time, Microsoft Graph refused the second addition, and the summary reported `FAILED` although the membership was in place |
| `Update-NeologikEnvironmentAccess.ps1` | With `-Verify`, the closing line counts every item of the summary that reports a change, and reads `A run without -Verify would change N item(s)`. Before this version, the count left out the items of step 2 |
| `Update-NeologikEnvironmentAccess.ps1` | The environment access script records the version `v5.0.11` on the resource group |
| `Install-NeologikEnvironment.ps1` | No change to the script. The onboarding script records the version `v5.0.11` on the resource group |

## Version 5.0.10

**Date**: 2026-10-03

| Item | Change |
|---|---|
| `Update-NeologikEnvironmentAccess.ps1` | The first run has a new step 2. The environment access script confirms the four security groups of version 5 in your tenant and creates a group that is absent: `Neologik User Group`, `Neologik NCE Contributors`, `Neologik NCE Admins` and `Neologik Admin User Group`, each with the short name of the environment. The environment access script renames `Neologik NCE User Group` to `Neologik NCE Contributors`; the group keeps the id and the members. The environment access script confirms that each Neologik support account in `NeologikGuestUsers.txt` is a guest of your tenant, and invites an account that is absent. The environment access script confirms that each guest and the signed-in administrator are direct members of every group, and adds a membership that is absent. Nothing is removed. Before this version, an environment set up before version 5 kept its two groups, and nobody could administer the Neologik Context Engine after the upgrade |
| `Update-NeologikEnvironmentAccess.ps1` | Step 3 assigns the group `Neologik NCE Admins` to the Platform Sign-in application, beside the user group. The summary gains the items `Security groups`, `NCE Admins group`, `Neologik guest users`, `Group memberships`, `Signed-in administrator membership` and `Admin group assignment`. The summary file names the two role groups |
| `Update-NeologikEnvironmentAccess.ps1` | New parameter `-GuestUsersFile`. Without the parameter, the environment access script reads `NeologikGuestUsers.txt` from its own folder. Run the environment access script from the folder of the onboarding kit |
| `Update-NeologikEnvironmentAccess.ps1` | The first run requests two more delegated permissions at the sign-in: `Group.ReadWrite.All` and `User.Invite.All`. The environment access script records the version `v5.0.10` on the resource group |
| `Install-NeologikEnvironment.ps1` | No change to the script. The onboarding script records the version `v5.0.10` on the resource group |
| `ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md` | The document describes the new step 2 and the permissions it needs |

## Version 5.0.9

**Date**: 2026-10-02

| Item | Change |
|---|---|
| `Update-NeologikEnvironmentAccess.ps1` | The first run now checks the sponsor of the agent identity blueprint. The sponsor is the person who is accountable for the agents of the environment. The summary names the sponsor in the item `Agent identity blueprint sponsor`. When the agent identity blueprint has no sponsor, the environment access script adds the signed-in Global Administrator as the sponsor. The environment access script records the version `v5.0.9` on the resource group |
| `Install-NeologikEnvironment.ps1` | Version v5.0.5. The agent identity blueprint can already exist with no sponsor. The onboarding script then adds the signed-in Global Administrator as the sponsor. The configuration file does not record the sponsor. Microsoft Entra ID holds the sponsor on the agent identity blueprint. The onboarding script records the version `v5.0.9` on the resource group |
| The Neologik Platform | Each agent identity that the Neologik Platform creates takes the sponsor of the agent identity blueprint. The Neologik Context Engine has no setting for the sponsor |
| `ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md` | The document describes the check of the sponsor |
| `TECHNICAL-REFERENCE.md` | The document states how the agent identities take the sponsor |

## Version 5.0.8

**Date**: 2026-10-01

| Item | Change |
|---|---|
| `Update-NeologikEnvironmentAccess.ps1` | The first run now reads the SharePoint permissions in your tenant. When an earlier SharePoint application of Neologik holds a SharePoint permission, the environment access script grants `Sites.Selected` to the SharePoint application of the environment. When the SharePoint application of the environment already holds `Sites.Selected`, the environment access script changes nothing. When no application holds a SharePoint permission, the environment access script grants nothing. The environment access script records the version `v5.0.8` on the resource group |
| `Update-NeologikEnvironmentAccess.ps1` | The environment access script creates the service principal of the agent identity blueprint with the deployment identity as an owner. The first run requests the permission `AgentIdentityBlueprintPrincipal.ReadWrite.All`. With that permission, the environment access script adds the owner to a service principal that exists with no owner. Before this version, Microsoft Graph refused the owner and the summary reported `FAILED` |
| `Install-NeologikEnvironment.ps1` | Version v5.0.4. The onboarding script creates the service principal of the agent identity blueprint with the deployment identity as an owner. The interactive sign-in requests the permission `AgentIdentityBlueprintPrincipal.ReadWrite.All`. The onboarding script records the version `v5.0.8` on the resource group |
| `ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md` | The document describes the grant of `Sites.Selected` and lists the new permission |
| `QUICK-REFERENCE.md` | The document lists the new permission of the interactive sign-in |

## Version 5.0.7

**Date**: 2026-09-28

| Item | Change |
|---|---|
| `Export-NeologikCertificate.ps1` | Version 1.1. The script deletes `private-clean.key`, the private key without encryption, after success and after a failure. Before this version, the file stayed on disk after a failure |
| `Install-NeologikEnvironment.ps1` | Version v5.0.3. The onboarding script records the version `v5.0.7` on the resource group |
| `Update-NeologikEnvironmentAccess.ps1` | The environment access script records the version `v5.0.7` on the resource group |

## Version 5.0.6

**Date**: 2026-09-28

| Item | Change |
|---|---|
| Documents | Every document is rewritten in plain English |
| Scripts | The comments, the help text and the messages of every script are rewritten in plain English. No script behaves differently |
| `Install-NeologikEnvironment.ps1` | Version v5.0.2. The onboarding script writes the value `NeologikPlatform` to the tag `ApplicationName` of each resource that the onboarding script creates. The deployment by Neologik writes the same value. The question about the host name now reads "Host name of the environment, fully qualified". The onboarding script records the version `v5.0.6` on the resource group |
| `Update-NeologikEnvironmentAccess.ps1` | The environment access script names each item of the summary in full, for example `Agent identity blueprint owner` instead of `Blueprint owner`. Each result reads `FAILED: <reason>` instead of `FAILED - <reason>`. The environment access script records the version `v5.0.6` on the resource group |
| `Upgrade-TeamsAppInstallations.ps1` | Version v0.2.1 |
| `TECHNICAL-REFERENCE.md` | The document lists the value of each standard tag |
| The zip of the onboarding kit | The zip holds the scripts, the documents and the supporting files only. The zip omits the repository files and the test folder |

## Version 5.0.3

**Date**: 2026-09-28

| Item | Change |
|---|---|
| `Install-NeologikEnvironment.ps1` | Version v5.0.1. The script runner managed identity holds three roles on the resource group: Reader, Key Vault Secrets Officer and Azure Bot Service Contributor Role. The script runner managed identity holds no role on the subscription. Before this version, the script runner managed identity held Contributor on the subscription. No identity that the onboarding script creates holds a role that gives control of a resource outside the resource group. The onboarding script records the version `v5.0.3` on the resource group |
| `Update-NeologikEnvironmentAccess.ps1` | The environment access script records the version `v5.0.3` on the resource group |
| Scripts | The comments, the help text and the messages of every script are revised. Plain text markers such as `[OK]` replace the symbols in the messages. `Get-Help` shows the help of every script. No script behaves differently, apart from the change of role above |
| Documents | Every guide and reference is revised. `FINISHING-STEPS-GUIDE.md` covers the DNS record for both deployment types and the administrator consent. `QUICK-REFERENCE.md` is the security reference of the onboarding script. `secure-overview.md` is the summary of `QUICK-REFERENCE.md` on one page |

## Version 5.0.2

**Date**: 2026-09-27

| Item | Change |
|---|---|
| `Install-NeologikEnvironment.ps1` | The onboarding script records the version of the onboarding kit on the resource group, in the tag `NeologikOnboardingKit`. The onboarding script keeps your other tags. An existing resource group receives the tag too |
| `Update-NeologikEnvironmentAccess.ps1` | The environment access script records the same tag as the last step of the permission reduction |

## Version 5.0.1

**Date**: 2026-09-25

| Item | Change |
|---|---|
| `NeologikGuestUsers.txt` | The list of Neologik support accounts is updated |

## Version 5.0.0

**Date**: 2026-09-25

Version 5.0.0 is the first release of the onboarding kit for version 5.0 of the Neologik Platform. The table lists what changed from version 1.10.1.

| Item | Change |
|---|---|
| Access of the deployment identity | The deployment identity holds the roles on the resource group. On the subscription the deployment identity holds Reader and Cost Management Contributor only. The deployment identity holds no Microsoft Entra directory role and is a member of no group. In Microsoft Graph the deployment identity holds `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` |
| Agent identity blueprint | The onboarding script creates the agent identity blueprint of the environment. The Neologik Platform creates the agent identities and the agent user accounts under the agent identity blueprint |
| Platform Sign-in application | The onboarding script creates the application that signs your users in to the Neologik Context Engine and to Apps. The onboarding script assigns the groups `Neologik NCE Contributors - <short name>` and `Neologik NCE Admins - <short name>` to the application |
| Security groups | Four groups: `Neologik User Group - <short name>`, `Neologik NCE Contributors - <short name>`, `Neologik NCE Admins - <short name>` and `Neologik Admin User Group - <short name>`. The Admin User Group holds the roles on the resource group and no role on the subscription |
| Resource providers | One list, `resource-providers.txt`. The onboarding script registers the whole list on every run. `Register-NeologikResourceProviders.ps1` confirms the registrations |
| Answer file | The answer file `inputs.json` can hold each value of a run. Each resource name can be a name of your choice |
| Accounts for Neologik support | Guest invitation is optional. You can create the accounts in your tenant instead |
| Deployment service principal | You can create the deployment service principal yourself, as described in `CREATE-SP-GUIDE.md` |
| Subscription | The parameter `-SubscriptionName` selects the subscription after the sign-in |
| Unattended run | The parameters `-NonInteractive` and `-AcceptTerms` run the onboarding script without questions |
| `Update-NeologikEnvironmentAccess.ps1` | New script. `ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md` describes the script |
| `Export-NeologikCertificate.ps1` | New script. `PFX-CERT-GUIDE.md` describes the script |
| `Upgrade-TeamsAppInstallations.ps1` | New script. `TEAMS-APP-UPGRADE-GUIDE.md` describes the script |
| Agents | The onboarding script asks no question about agents. A platform operator creates agents in the Neologik Context Engine after the deployment |

## Earlier versions

| Version | Date | Change |
|---|---|---|
| 1.10.1 | 2026-06-29 | The check of the virtual machine quota is corrected |
| 1.10.0 | 2026-06-25 | The deployment identity and the Admin User Group hold no Contributor role on the subscription |
| 1.9.1 | 2026-06-18 | The documents match the onboarding script |
| 1.9.0 | 2026-01-15 | The onboarding script checks the Azure region against the regions that the subscription can use |
| 1.8.0 | 2026-01-12 | The onboarding script reads the Neologik support accounts from `NeologikGuestUsers.txt`. The onboarding script asks for the host name of the environment |
| 1.7.0 to 1.7.5 | 2025-11-17 | Corrections to the resource provider registration, to the error messages and to the handling of new directory objects |
| 1.6.5 to 1.6.9 | 2025-11-17 | Corrections to the guest invitation and to the log |
| 1.4.0 to 1.4.2 | 2025-11-17 | The onboarding script asks for the acceptance of the Terms of Use and the Privacy Policy before the run |
| 1.0.0 | 2025-11-15 | The first release |
