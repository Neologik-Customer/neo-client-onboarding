# Install-NeologikEnvironment.ps1: Security Reference

## Overview

This document is for the security team reviewing `Install-NeologikEnvironment.ps1` before it is run. It lists every sign-in, permission, directory write, Azure write, secret and file the script makes, and what the script never does.

The script prepares your Azure subscription and your Microsoft Entra tenant for one Neologik Platform environment. A Global Administrator who is also Owner of the subscription runs it once. It creates four security groups, the deployment identity, the Platform Sign-in application, the agent identity blueprint, the resource group, a Key Vault, a deployment storage account and two managed identities. It registers the Azure resource providers the platform uses and writes a configuration file for Neologik that contains no secret.

The deployment identity can deploy Azure resources into one resource group. On the subscription it holds two roles, Reader and Cost Management Contributor, which give no control of resources. In the directory it holds two Microsoft Graph application permissions. No other identity the script creates holds a role on the subscription.

## Contents

1. [Sign-ins and permissions](#sign-ins-and-permissions)
2. [Inputs](#inputs)
3. [Steps in order](#steps-in-order)
4. [Directory writes](#directory-writes)
5. [Azure writes](#azure-writes)
6. [What the deployment identity holds](#what-the-deployment-identity-holds)
7. [Secrets](#secrets)
8. [Files](#files)
9. [Changes to the workstation](#changes-to-the-workstation)
10. [What the script never does](#what-the-script-never-does)
11. [What is logged](#what-is-logged)
12. [Repeat runs, checkpoints and failure](#repeat-runs-checkpoints-and-failure)
13. [Summary of permissions by scope](#summary-of-permissions-by-scope)

## Sign-ins and permissions

Both sign-ins are made with the operator's own account. The script never signs in as a service principal.

| Sign-in | How | Used for |
|---|---|---|
| Azure Resource Manager | Az PowerShell (`Connect-AzAccount`), a browser sign-in that requests the multi-factor authentication claim Azure requires for writes, with a device code as the fallback. An Azure session already present on the workstation is offered for reuse | The resource group, role assignments, Key Vault, storage account, managed identities and resource providers |
| Microsoft Graph | In this order: a Microsoft Graph session already present for the same tenant; otherwise a Microsoft Graph token issued to the Azure session, so that no second prompt appears; otherwise an interactive `Connect-MgGraph` sign-in | The groups, the invitations, the application registrations, the agent identity blueprint, the application permissions, ownership, group assignment and one directory role membership |

The interactive Microsoft Graph sign-in requests these delegated scopes: `User.ReadWrite.All`, `User.Invite.All`, `Group.ReadWrite.All`, `Application.ReadWrite.All`, `Directory.ReadWrite.All`, `RoleManagement.ReadWrite.Directory`, `AppRoleAssignment.ReadWrite.All`, `AgentIdentityBlueprint.Create`, `AgentIdentityBlueprint.AddRemoveCreds.All` and `AgentIdentityBlueprintPrincipal.Create`. They act as the signed-in administrator and only while the administrator is signed in.

Before it creates anything, the script verifies that the account holds Owner on the subscription and Global Administrator in the tenant, and stops if either is missing. If the Global Administrator check cannot be carried out, the script says so and asks whether to proceed; an unattended run stops.

When a reused Azure session lacks the multi-factor authentication claim, the script signs in again, because Azure refuses writes without it.

## Inputs

| Input | Content |
|---|---|
| The answer file `inputs.json`, beside the script or named with `-AnswerFile` | The organisation code and name, the host name, the environment type, region and index, the resource names, the cost report recipients, the tags, the guest and existing-account choices, and a deployment service principal to reuse |
| Command-line parameters | The organisation code, environment type, region, tenant, subscription and Key Vault name, the service principal to reuse, and the switches `-NonInteractive`, `-AcceptTerms`, `-FreshRun`, `-SkipModuleInstall`, `-SkipGuestInvitation` and `-SkipPowerShellUpdate` |
| `NeologikGuestUsers.txt` | The Neologik support accounts to invite as guests, when invitation is chosen |
| `resource-providers.txt` | The list of resource providers and preview features |
| Prompts | Acceptance of the terms, module installation, sign-in, every configuration value that is not in the answer file, and the confirmation before anything is created |

## Steps in order

The numbers are those used in the comments of the script. The rows without a number are its steps 1 to 6, and it has no step 13.

| Step | What happens |
|---|---|
| Preparation | The terms are accepted; PowerShell 7.4 and the modules are checked; an earlier checkpoint is offered for resumption |
| Sign-in | Azure and Microsoft Graph, as above. The subscription is that of the session, or the one named with `-SubscriptionName` |
| Permission check | Owner and Global Administrator are verified |
| Providers submitted | The resource provider registrations are submitted, so that they complete while the script runs |
| Configuration | The values are gathered from the answer file or the prompts, and confirmed |
| 7. Resource group | Created with the standard tags and with the tag `NeologikOnboardingKit`. An existing resource group receives that tag too |
| 8. Accounts | The Neologik support accounts are invited as guests, or existing accounts are looked up, as you chose |
| 9. Security groups | Four groups are created: `Neologik User Group - <short name>`, `Neologik NCE Contributors - <short name>`, `Neologik NCE Admins - <short name>` and `Neologik Admin User Group - <short name>` |
| 10. Group roles | The Admin User Group receives ten of its thirteen Azure roles on the resource group. Steps 12 and 14 assign the other three |
| 11. Deployment identity | The application `Neologik GitHub Service Connection - <short name>`, its service principal and a client secret are created, or a service principal you name is reused. Its Azure roles and its two Microsoft Graph application permissions are assigned |
| 12. Key Vault | Created with Azure role-based access control. The deployment identity's secret is stored in it. The Admin User Group receives two Key Vault roles |
| 12b. Platform Sign-in application | Created, with its client secret, its owners and its group assignments |
| 12c. Agent identity blueprint | Created, with its principal, its owners, the application permission of the principal and three federated credentials |
| 14. Storage account | Created with public blob access and shared key access disabled, and three containers. The Admin User Group receives one storage role |
| 15. Managed identities | The script runner identity and the SQL identity are created, with their roles |
| 15b. Providers confirmed | Every registration is confirmed |
| 16. Export | The configuration file is written, and uploaded to the storage account with the log. The checkpoint is deleted |

## Directory writes

The script reads each object before it writes, and writes only when the object or the property is absent.

| Object | Call | Properties | Condition |
|---|---|---|---|
| Guest invitations | `New-MgInvitation` | The address; redirect to the Azure portal; invitation email sent | Invitation chosen, and no account with that mail address or user principal name exists |
| Security groups | `New-MgGroup` | Display name, description, security enabled, not mail enabled | The group is absent |
| Rename of a group | `Update-MgGroup` | Display name and description | Only where the tenant already holds the NCE Contributors group under one of the two alternative names the script recognises. The group keeps its id and members. This does not arise in a new environment |
| Group members | `New-MgGroupMember` | The invited or existing accounts and the signed-in operator, in all four groups | The account is not already a member |
| Deployment application | `New-MgApplication` | Display name `Neologik GitHub Service Connection - <short name>`; multi-tenant sign-in audience | The script manages the deployment identity and the application is absent |
| Deployment service principal | `New-MgServicePrincipal` | From the application | Absent |
| Deployment identity client secret | `Add-MgApplicationPassword` | Display name `auth`; valid for 365 days | Every run in which the script manages the deployment identity. See [Secrets](#secrets) |
| Microsoft Graph application permissions of the deployment identity | `POST /servicePrincipals/{id}/appRoleAssignments` | `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` | Not already assigned |
| Platform Sign-in application | `New-MgApplication` | Display name `Neologik Platform Sign-in - <short name>`; unique name `sp-admin-<solution name>`; multi-tenant sign-in audience; group claims for assigned groups; redirect address `https://<host>/nce`; access token version 2 | Absent by unique name |
| Platform Sign-in application, display name | `Update-MgApplication` | Display name | The existing name differs |
| Platform Sign-in service principal | `New-MgServicePrincipal` | From the application | Absent |
| Platform Sign-in client secret | `Add-MgApplicationPassword` | Display name `auth`; valid for 365 days | The application is new, or the Key Vault holds no secret for it |
| Ownership of the Platform Sign-in application and its service principal | `New-MgApplicationOwnerByRef`, `New-MgServicePrincipalOwnerByRef` | The deployment identity as owner | Not already an owner |
| Group assignments to the Platform Sign-in application | `New-MgGroupAppRoleAssignment`, with the default access role | The NCE Contributors group and the NCE Admins group, so that their members' sign-ins carry the groups claim | Absent |
| Agent identity blueprint | `POST /applications/microsoft.graph.agentIdentityBlueprint` | Display name `Neologik Agent Blueprint - default - <short name>`; sponsor: the signed-in operator; owner: the deployment identity | No application holds the display name |
| Blueprint principal | `POST /servicePrincipals/microsoft.graph.agentIdentityBlueprintPrincipal` | From the blueprint | Absent |
| Ownership of the blueprint and its principal | Owner reference | The deployment identity as owner | Not already an owner |
| Microsoft Graph application permission of the blueprint principal | `POST /servicePrincipals/{id}/appRoleAssignments` | `AgentIdUser.ReadWrite.IdentityParentedBy`, which is limited to the agent users of this blueprint | Not already assigned |
| Federated credentials on the blueprint | `POST /beta/applications/{id}/federatedIdentityCredentials` | Three, described below | Absent by name |
| Directory Readers role | `New-MgDirectoryRole` from its template, then `New-MgDirectoryRoleMemberByRef` | Membership for the SQL managed identity, which Azure SQL requires in order to resolve Microsoft Entra sign-ins | The role is activated only if it has never been activated; the membership is added only when absent |

The script gives no administrator consent and creates no permission grant. Your Global Administrator gives the consent after deployment, as described in [FINISHING-STEPS-GUIDE.md](FINISHING-STEPS-GUIDE.md).

### The federated credentials on the blueprint

The platform deployment creates agent identities and agent users as the blueprint. It obtains a token of the blueprint by exchanging the token its own deployment service issues, so that no secret is stored.

| Property | Value |
|---|---|
| Names | `github-oidc-neo-infrastructure`, `github-oidc-neo-bot-service`, `github-oidc-neo-env-config` |
| Issuer | `https://token.actions.githubusercontent.com` |
| Audience | `api://AzureADTokenExchange` |
| Trust | One repository of the Neologik deployment for each credential, named by its repository id, which does not change. A repository that is renamed or copied gains nothing |

## Azure writes

| Object | Cmdlet | Scope | Roles or properties |
|---|---|---|---|
| Resource providers and preview features | `Register-AzResourceProvider`, `Register-AzProviderFeature` | Subscription | The list in `resource-providers.txt`: 35 providers and 2 preview features |
| Resource group | `New-AzResourceGroup`, `Update-AzTag` | Subscription | `rg-<solution name>` in the chosen region, tagged. The tag `NeologikOnboardingKit` records the kit version and is merged with the existing tags |
| Admin User Group roles | `New-AzRoleAssignment` | Resource group | `Contributor`, `Azure Kubernetes Service Cluster Admin Role`, `Azure Kubernetes Service RBAC Cluster Admin`, `Key Vault Administrator`, `Key Vault Secrets Officer`, `Key Vault Certificates Officer`, `Storage Blob Data Owner`, `Storage Blob Data Contributor`, `Storage Table Data Contributor`, `Cognitive Services Data Reader`, `Cognitive Services OpenAI Contributor`, `Search Index Data Reader` and `Azure AI Developer`. None at subscription scope |
| Deployment identity roles | `New-AzRoleAssignment` | Subscription | `Reader` and `Cost Management Contributor` |
| Deployment identity roles | `New-AzRoleAssignment` | Resource group | `Contributor`, `Key Vault Certificates Officer`, `Key Vault Secrets Officer`, `Storage Blob Data Contributor`, `Azure Kubernetes Service RBAC Cluster Admin`, `Monitoring Contributor` and `Role Based Access Control Administrator` |
| Key Vault | `New-AzKeyVault`, `Update-AzKeyVault` | Resource group | `kv<short name>` or the name given; Azure role-based access control enabled at creation; tagged. An existing Key Vault is used as it is |
| Operator role for the secret | `New-AzRoleAssignment` | Resource group | `Key Vault Secrets Officer` for the signed-in operator, so that the script can store the secrets |
| Key Vault secrets | `Set-AzKeyVaultSecret` | Key Vault | `neologik-deployment-service-principle-secret` and `sp-admin-<solution name>-auth-secret` |
| Storage account | `New-AzStorageAccount`, `Set-AzStorageAccount`, `New-AzRmStorageContainer` | Resource group | Standard LRS, StorageV2, public blob access disabled at creation, shared key access disabled on every run; private containers `certificate`, `json` and `logs` |
| Operator role for the upload | `New-AzRoleAssignment` | Resource group | `Storage Blob Data Contributor` for the signed-in operator |
| Managed identities | `New-AzUserAssignedIdentity`, `New-AzRoleAssignment` | Resource group | `neologik-script-runner-service-connection-<short name>`: `Reader`, `Key Vault Secrets Officer` and `Azure Bot Service Contributor Role` on the resource group, and no role on the subscription. `neologik-sql-managed-identity-<short name>`: no Azure role |
| Uploads | `Set-AzStorageBlobContent` | The `json` and `logs` containers | The configuration file and the log, with Microsoft Entra authentication |

Role assignments are retried, up to ten times at intervals of ten seconds, while a newly created principal replicates.

The two roles assigned to the signed-in operator remain after the run. Remove them when onboarding is complete if your policy requires it.

The script sets no network restriction on the Key Vault or the storage account. The platform deployment that follows applies the network settings of your deployment type.

## What the deployment identity holds

| Kind | Held |
|---|---|
| Azure roles | `Reader` and `Cost Management Contributor` on the subscription; the seven resource group roles listed above |
| Microsoft Graph application permissions | `Application.ReadWrite.OwnedBy`: manage only the application registrations it owns. `AgentIdentityBlueprint.AddRemoveCreds.All`: add and remove credentials on agent identity blueprints |
| Microsoft Entra directory roles | None |
| Group membership | None |
| Ownership | Owner of the Platform Sign-in application, the agent identity blueprint and the service principal of each |
| Credential | One client secret, stored in your Key Vault |

After deployment the platform grants the deployment identity one further role, `Cognitive Services Content Understanding Contributor`, on one Azure AI resource inside the resource group.

## Secrets

| Secret | Created by | Stored | Printed, logged or exported |
|---|---|---|---|
| Deployment identity client secret | The script; valid for 365 days | Key Vault secret `neologik-deployment-service-principle-secret` | Never. Only its expiry date is exported |
| The secret of a service principal you supply | You | The same Key Vault secret | Never, and it is not written to the checkpoint. If you place it in the answer file, it is on disk in that file; the masked prompt avoids this |
| Platform Sign-in client secret | The script; valid for 365 days | Key Vault secret `sp-admin-<solution name>-auth-secret` | Never |

Neologik's support accounts read the deployment identity's secret from your Key Vault, as members of the Admin User Group, in order to configure the deployment. If no Neologik account has access to the Key Vault, agree with Neologik how the secret is to be passed. It is never placed in the configuration file or sent by email.

Each run in which the script manages the deployment identity adds a new client secret to the application and stores it as a new version of the Key Vault secret. Earlier secrets on the application are not removed and remain valid until they expire. After a repeat run, remove the earlier secrets from the application in the Microsoft Entra admin centre.

## Files

| File | Location | Content |
|---|---|---|
| `NeologikOnboarding_<timestamp>.log` | Beside the script; uploaded to the `logs` container | The log of the run |
| `Neologik_<org><index>_Configuration_<timestamp>.json` | Beside the script; uploaded to the `json` container | The names and ids of everything created, roles assigned, the host name, the operator's sign-in name, the addresses of the accounts invited or added, the cost report recipients and the expiry date of the client secret |
| `NeologikCheckpoint.json` | Beside the script, while a run is incomplete | The configuration gathered so far, in the same form. Deleted when the run completes |

None of the three files contains a secret. All three contain personal data: sign-in names and email addresses. Handle them accordingly.

## Changes to the workstation

| Change | Condition |
|---|---|
| The PowerShell Gallery is marked as a trusted repository for the user. The setting persists | Modules are installed |
| The Az and Microsoft Graph modules are installed for the current user | Missing, and you accept |
| PowerShell is updated | Older than 7.4, and you accept |
| The cached Azure and Microsoft Graph sessions of the user are cleared | You choose to sign in again |

## What the script never does

- It never grants a Microsoft Graph application permission other than the three named in this document.
- It never gives an administrator consent or creates a permission grant.
- It never creates a subscription.
- It never adds the deployment identity or a managed identity to a security group.
- It never assigns a role on the subscription to a managed identity or to a group.
- It never prints, logs, exports or checkpoints the value of a secret.
- It never deletes a directory object, an Azure resource, a role assignment or a credential.

## What is logged

The log records the account and tenant signed in, the subscription, each object created or found with its id, each role assignment, the name of each secret stored, the addresses of the accounts invited or added, the progress of the provider registrations and the path of the configuration file.

The prompts, the configuration summary and the completion summary appear on screen only. No secret and no token is logged.

## Repeat runs, checkpoints and failure

Every creation reads first and reuses what exists, so a repeat run on a completed environment creates nothing new. There are two exceptions: the client secret of the deployment identity, described under [Secrets](#secrets), and the shared key setting of the storage account, applied on every run.

The script writes a checkpoint when the resource provider registrations have been submitted, and again when the configuration has been confirmed. A run that stops after the configuration has been confirmed can be resumed: the terms and the questions are skipped, and each step runs again and reuses what it has already created. If a run stops before that point, start again with `-FreshRun`.

A failure to add an account to a group is reported as a warning and the run continues. A resource provider that is still registering when the script ends is listed on screen and in the configuration file; confirm it with `Register-NeologikResourceProviders.ps1`.

| Exit code | Meaning |
|---|---|
| 0 | Completed, or the terms were declined |
| 1 | Failed. The error is shown and the run stops |

## Summary of permissions by scope

| Scope | Principal | Roles or permissions |
|---|---|---|
| Subscription | Deployment identity | Reader, Cost Management Contributor |
| Resource group | Deployment identity | Contributor, Key Vault Certificates Officer, Key Vault Secrets Officer, Storage Blob Data Contributor, Azure Kubernetes Service RBAC Cluster Admin, Monitoring Contributor, Role Based Access Control Administrator |
| Resource group | Script runner managed identity, under which the deployment runs its scripts within Azure | Reader, Key Vault Secrets Officer, Azure Bot Service Contributor Role |
| Resource group | Neologik Admin User Group | The thirteen roles listed under [Azure writes](#azure-writes) |
| Resource group | The signed-in operator | Key Vault Secrets Officer, Storage Blob Data Contributor |
| Microsoft Graph application permissions | Deployment identity | Application.ReadWrite.OwnedBy, AgentIdentityBlueprint.AddRemoveCreds.All |
| Microsoft Graph application permissions | Agent identity blueprint principal | AgentIdUser.ReadWrite.IdentityParentedBy |
| Microsoft Entra directory roles | SQL managed identity | Directory Readers |
| Microsoft Entra directory roles | Deployment identity | None |
| Group membership | Deployment identity and managed identities | None |
