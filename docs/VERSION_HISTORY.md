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
2. [Version 5.2.0](#version-520)
2. [Version 5.1.9](#version-519)
2. [Version 5.1.8](#version-518)
2. [Version 5.1.7](#version-517)
2. [Version 5.1.6](#version-516)
2. [Version 5.1.5](#version-515)
2. [Version 5.1.4](#version-514)
2. [Version 5.1.3](#version-513)
2. [Version 5.1.2](#version-512)
2. [Version 5.1.1](#version-511)
2. [Version 5.1.0](#version-510)
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
| `Install-NeologikEnvironment.ps1` | v5.2.0 | Prepares the Azure subscription and the Microsoft Entra tenant for one Neologik Platform environment |
| `Grant-NeologikAgentAccess.ps1` | Onboarding kit version v5.2.0 | Applies the grants that agents and Apps need to work unattended in Microsoft 365, from the agent grants file and the mailbox grants file |
| `Export-NeologikCertificate.ps1` | 1.1 | Builds the PFX file for the TLS certificate of the environment, on the workstation |
| `Register-NeologikResourceProviders.ps1` | 1.0 | Confirms the Azure resource provider registrations on the subscription |
| `Upgrade-TeamsAppInstallations.ps1` | v0.2.1 | Upgrades the Neologik Teams app that each user has installed to the latest version in the Teams app catalogue |
| `Remove-NeologikDirectoryObjects.ps1` | 1.0 | Deletes the directory objects of one environment, after the administrator confirms the list |

## Version 5.2.0

**Date**: 2026-11-10

This version is on the line of Neologik Platform v5.2. This version limits the roles that the identities of the Neologik Platform can assign.

| Item | Change |
|---|---|
| `Install-NeologikEnvironment.ps1` | The deployment identity holds Role Based Access Control Administrator on the resource group with a condition. The deployment identity cannot assign or remove Owner, User Access Administrator or Role Based Access Control Administrator, and can assign or remove every other role for service principals only |
| `Install-NeologikEnvironment.ps1` | Role Based Access Control Administrator on the subscription is limited to Reader and Cost Management Reader, for service principals only |
| `Install-NeologikEnvironment.ps1` | Step 15 creates the system task managed identity, and gives the managed identity Role Based Access Control Administrator on the resource group with the same condition |
| `inputs-example.json` | One new answer: `systemTaskIdentityName` |

## Version 5.1.9

**Date**: 2026-11-11

This version is on the line of Neologik Platform v5.1. The limited role of the deployment identity on the subscription now assigns two roles, and only to service principals.

| Item | Change |
|---|---|
| `Install-NeologikEnvironment.ps1` | The condition on Role Based Access Control Administrator on the subscription lets the deployment identity assign or remove two roles, Reader and Cost Management Reader, for service principals only. AppGw for Containers Configuration Manager leaves the list, because the deployment assigns that role inside the resource group of the environment. The version of the onboarding kit is v5.1.9 |
| `Grant-NeologikAgentAccess.ps1` | The version of the onboarding kit is v5.1.9 |
| The documents | `README.md`, `docs/QUICK-REFERENCE.md`, `docs/TECHNICAL-REFERENCE.md` and `docs/secure-overview.md` describe the two roles |

## Version 5.1.8

**Date**: 2026-11-10

This version is on the line of Neologik Platform v5.1. This version names the administration web application the Neologik Admin Tool, the name the application shows on screen. No step of any script changes.

| Item | Change |
|---|---|
| The documents | Each document names the Neologik Admin Tool |
| `Install-NeologikEnvironment.ps1` and `Grant-NeologikAgentAccess.ps1` | The messages name the Neologik Admin Tool. The version of the onboarding kit is v5.1.8 |

## Version 5.1.7

**Date**: 2026-11-10

This version is on the line of Neologik Platform v5.1. This version adds a guide to uninstalling the Neologik Platform, adds the script that the guide uses, and moves the version number. No step of the onboarding script changes.

| Item | Change |
|---|---|
| `docs/UNINSTALL-GUIDE.md` | New guide. An administrator removes the Neologik Platform completely from the Azure subscription and the Microsoft Entra tenant |
| `README.md` | Lists the new guide and the new script |
| `Remove-NeologikDirectoryObjects.ps1` | New script, version 1.0. Deletes the directory objects of one environment, after the administrator confirms the list |
| `Install-NeologikEnvironment.ps1` and `Grant-NeologikAgentAccess.ps1` | The version of the onboarding kit is v5.1.7 |

## Version 5.1.6

**Date**: 2026-11-05

This version is on the line of Neologik Platform v5.1. This version corrects one helper of the grants script and moves the version number. No step of the onboarding script changes.

| Item | Change |
|---|---|
| `Grant-NeologikAgentAccess.ps1` | The helper that reads a property of a Microsoft Graph response also reads a Microsoft Graph PowerShell dictionary, such as the additional properties of a directory object. Before this version, such a read failed with the message "Cannot find an overload for Contains". The version of the onboarding kit is v5.1.6 |
| `Install-NeologikEnvironment.ps1` | The version of the onboarding kit is v5.1.6 |

## Version 5.1.5

**Date**: 2026-11-03

This version is on the line of Neologik Platform v5.1. This version adds the choice of a Neologik-managed TLS certificate to the documents and to the next steps that the onboarding script prints. No step of the onboarding script changes.

| Item | Change |
|---|---|
| `README.md` | Step 3 offers two ways to provide the TLS certificate: a Neologik-managed certificate, which Neologik obtains from the certificate authority ZeroSSL and renews every 60 days, or your own certificate, imported as before. The onboarding overview and the document list say the same |
| `PFX-CERT-GUIDE.md` | The guide states that the guide applies to your own certificate only |
| `TECHNICAL-REFERENCE.md` | The TLS certificate section describes both sources, the HTTP proof of the host name and the CAA record a Neologik-managed certificate needs where a zone publishes CAA records |
| `PRE-ONBOARDING-INFO-GATHERING.md` | The information to gather includes the choice of certificate |
| `QUICK-REFERENCE.md` | The note on secrets describes both sources |
| `Install-NeologikEnvironment.ps1` | The next steps name the two ways to provide the TLS certificate. The version of the onboarding kit is v5.1.5 |
| `Grant-NeologikAgentAccess.ps1` | The version of the onboarding kit is v5.1.5 |

## Version 5.1.4

**Date**: 2026-11-03

This version is on the line of Neologik Platform v5.1. This version changes three documents and the version number of the onboarding kit.

| Item | Change |
|---|---|
| `README.md` | The section on the access of the deployment identity describes the federated credential that step 12d adds |
| `secure-overview.md` | The overview lists the federated credential of the deployment identity, and states that the federated credential holds no secret |
| `CREATE-SP-GUIDE.md` | The guide states that the onboarding script adds the federated credential to an application registration that you create |

## Version 5.1.3

**Date**: 2026-11-02

This version is on the line of Neologik Platform v5.1. This version prepares your environment for version 5.2 of the Neologik Platform, so the move to version 5.2 needs no further step from your administrator.

| Item | Change |
|---|---|
| `Install-NeologikEnvironment.ps1` | Step 15 creates a third managed identity, the directory managed identity. The managed identity holds no Azure role and one Microsoft Graph application permission, `Application.ReadWrite.OwnedBy` |
| `Install-NeologikEnvironment.ps1` | Step 12d adds one federated credential to the application registration of the deployment identity. The federated credential adds no permission |
| `Install-NeologikEnvironment.ps1` | Step 15c records this version of the onboarding kit on the resource group. A resource group that an earlier version prepared keeps the earlier version until step 15c |
| `inputs-example.json` | Two new answers: `directoryIdentityName` and `environmentName` |
| `README.md`, `QUICK-REFERENCE.md`, `TECHNICAL-REFERENCE.md` and `secure-overview.md` | The documents describe the new items |

## Version 5.1.2

**Date**: 2026-11-02

This version is on the line of Neologik Platform v5.1. This version changes one document and the version number of the onboarding kit.

| Item | Change |
|---|---|
| `docs/FINISHING-STEPS-GUIDE.md` | A new section gives the default update windows, and says that Neologik Support can change or disable a window |

## Version 5.1.1

**Date**: 2026-10-30

This version is on the line of Neologik Platform v5.1. This version changes the onboarding script and documents.

| Item | Change |
|---|---|
| `docs/AGENT-ACCOUNT-ACCESS-GUIDE.md` | Task 5 gives the steps that give the SharePoint application access to a SharePoint site |
| `docs/PRE-ONBOARDING-INFO-GATHERING.md` | The vCPU quota row and the quota check name the Dsv7 family. The deployment service principal row says how to give the client secret |
| `docs/AGENT-ACCOUNT-ACCESS-GUIDE.md` | The name of an agent account holds the account prefix and the short name of the environment. The labels of the **Access** tab match the screen |
| `docs/GRANT-AGENT-ACCESS-SCRIPT-GUIDE.md`, `docs/FINISHING-STEPS-GUIDE.md`, `README.md` | The documents say where each grants file comes from. The **Admin** page exports the agent grants file, and Neologik sends the mailbox grants file |
| `docs/QUICK-REFERENCE.md`, `docs/secure-overview.md`, `README.md` | The documents state what the three roles on the subscription change. The documents write Private Endpoint environment. The condition on the limited role names three roles |
| `docs/QUICK-REFERENCE.md` | The list in `resource-providers.txt` holds 34 resource providers. The log records the stack trace after a failure |
| `docs/TECHNICAL-REFERENCE.md` | After a failed upload of the configuration file, an administrator uploads the file in the Azure portal. The onboarding script lists a pending resource provider before the completion summary |
| `docs/NETWORK-GUIDE.md` | The deployment storage account is a data service of a Private Endpoint environment from the first deployment. You allocate an address block only when a default range must change |
| `README.md`, `docs/FINISHING-STEPS-GUIDE.md` | The documents give the on-screen name Neologik Admin Tool. The finishing steps name the **Outstanding tasks** section of the home page |
| `README.md`, `docs/GRANT-AGENT-ACCESS-SCRIPT-GUIDE.md`, `docs/PRE-ONBOARDING-INFO-GATHERING.md`, `docs/TECHNICAL-REFERENCE.md`, `docs/secure-overview.md` | The documents say what happens when you leave a step or a value out |
| `README.md`, `docs/PFX-CERT-GUIDE.md`, `docs/TECHNICAL-REFERENCE.md` | The documents state that Neologik copies the TLS certificate, with the private key, into Neologik's central Key Vault. The documents say who builds and imports a certificate from uploaded files |
| `docs/ANALYTICS-REPORTING-GUIDE.md` | The guide lists the operator account of a configuration change and the outstanding tasks. The guide also lists the automatic updates and the names in a fault. The guide states what an agreed log query does. The guide states the retention period and what the masking of message patterns replaces |
| `docs/GRANT-AGENT-ACCESS-SCRIPT-GUIDE.md`, `docs/AGENT-ACCOUNT-ACCESS-GUIDE.md`, `docs/NETWORK-GUIDE.md` | The documents state each fact at this version, with no comparison with an earlier version |
| `README.md`, `docs/secure-overview.md`, `docs/QUICK-REFERENCE.md` | The documents for Approvers state that Neologik copies the TLS certificate into Neologik's central Key Vault |
| `Install-NeologikEnvironment.ps1` | Version v5.0.15. Comments and on-screen text state each fact at this version. The onboarding script no longer asks for cost report recipients, and the answer file no longer takes the key `budgetCostReportEmailRecipients`. The onboarding script ignores that key in an older answer file. Nothing in the platform read the addresses, and the deployment sends no cost report. The configuration file no longer holds the two fields for the recipients. The onboarding script records the version `v5.1.1` on the resource group |
| `README.md`, `docs/PRE-ONBOARDING-INFO-GATHERING.md`, `docs/QUICK-REFERENCE.md`, `docs/TECHNICAL-REFERENCE.md`, `docs/secure-overview.md`, `inputs-example.json` | The documents no longer describe a cost report. The documents state what Cost Management Contributor does |
| `Grant-NeologikAgentAccess.ps1` | Comments, help text and on-screen messages state each fact at this version. `Compare-Code.ps1` proves the code unchanged. The grants script reports the onboarding kit version v5.1.1 |

## Version 5.1.0

**Date**: 2026-10-27

This version is on the line of Neologik Platform v5.1.

| Item | Change |
|---|---|
| `resource-providers.txt` | The list no longer holds `Microsoft.Automation`. The Neologik Platform no longer creates an Azure Automation account |
| `resource-providers.txt` | The comments name the infrastructure type Private Endpoint, as the guides do, where they said neo-secure |
| `ANALYTICS-REPORTING-GUIDE.md` | New document. What the environment reports to Neologik, what the environment never reports, the retention period and how to withdraw from reporting |
| `Install-NeologikEnvironment.ps1` | Version v5.0.14. After a failure, the onboarding script prints the closing messages: the path of the log, the permission that is missing, and how to resume. Before this version, the first error message stopped the onboarding script before the closing messages. A run that stops because a permission is missing ends with exit code 2 |
| `Install-NeologikEnvironment.ps1` | The stack trace of a failure goes to the log file only |
| `Install-NeologikEnvironment.ps1` | The onboarding script downloads the PowerShell installer of the latest release. Before this version, the address named one fixed version |
| `Install-NeologikEnvironment.ps1` | The configuration file records both roles of the deployment identity on the subscription: Reader and Cost Management Contributor |
| `Install-NeologikEnvironment.ps1` | A run resumed from the first checkpoint asks the questions, because the first checkpoint holds no configuration. A resumed run honours `-SkipGuestInvitation` from the command line |
| `Install-NeologikEnvironment.ps1` | The onboarding script creates the application registration of the deployment identity for a single tenant. The deployment signs in to your tenant only |
| `Install-NeologikEnvironment.ps1` | The help block of the onboarding script states no version. The onboarding script prints the version when a run starts. Version v5.0.13 of the onboarding script was not released |
| `Grant-NeologikAgentAccess.ps1` | The grants script signs in to Microsoft Graph and to Exchange Online in the browser of the workstation first. A device code is the second method. Before this version, a device code was the first method. An organisation that blocks the device code with a Conditional Access policy could not complete the sign-in |
| `Grant-NeologikAgentAccess.ps1` | When a Conditional Access policy refuses a sign-in, the grants script says so and tries the next method at once. The grants script reports the onboarding kit version v5.1.0 |
| `GRANT-AGENT-ACCESS-SCRIPT-GUIDE.md` | The document describes the browser sign-in, and the device code as the second method |
| `QUICK-REFERENCE.md` | The document describes the resume from the first checkpoint and exit code 2 |
| `TECHNICAL-REFERENCE.md` | The document says where to read the version of the onboarding script and the version of the onboarding kit, instead of stating a number |
| `PRE-ONBOARDING-INFO-GATHERING.md` | The vCPU quota row names the node sizes and the vCPU total of the family |
| Documents | The documents state why the Platform Sign-in application accepts accounts of more than one tenant: Neologik support staff can sign in with an account of the Neologik tenant, when you allow that tenant |
| `README.md` | A new requirement row under Before you start: a customer billed through a Cloud Solution Provider partner asks the partner to enable the cost visibility policy, so the platform's return on investment report can show running costs |
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
