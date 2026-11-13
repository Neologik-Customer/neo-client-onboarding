# Install-NeologikEnvironment.ps1: Security Reference

## Overview

This document is for approvers of the onboarding script, `Install-NeologikEnvironment.ps1`. An approver is a person who reviews a script before an administrator runs the script.

This document lists each sign-in, each permission, each write to the directory, each write to Azure, each secret and each file. This document also lists what the onboarding script never does.

In this document, the Admin User Group is the group `Neologik Admin User Group - <short name>`.

### What the onboarding script does

The onboarding script prepares your Azure subscription and your Microsoft Entra tenant for one Neologik Platform environment. A Global Administrator who is also Owner of the subscription runs the onboarding script once.

| The onboarding script creates | Number |
|---|---|
| Security groups | Four |
| Deployment identity, with Azure roles and Microsoft Graph application permissions | One |
| Platform Sign-in application | One |
| Agent identity blueprint | One |
| Resource group | One |
| Key Vault | One |
| Deployment storage account | One |
| Managed identities | Four |

The onboarding script also registers the Azure resource providers that the Neologik Platform uses. The onboarding script writes a configuration file for Neologik. The configuration file contains no secret.

### What the deployment identity can do

| Subject | Position |
|---|---|
| Resource group | The deployment identity can deploy Azure resources into one resource group |
| Subscription | The deployment identity holds three roles: Reader, Cost Management Contributor, and Role Based Access Control Administrator limited to assigning two roles. These roles change no Azure resource other than cost configuration, support requests and assignments of the two assignable roles. The limited role lets the deployment identity assign exactly two roles, to service principals only: Reader and Cost Management Reader. The deployment assigns Reader to the identity of the ingress controller of a Private Endpoint environment, and Cost Management Reader to the identity of the configuration API of the Neologik Platform on the resource group that Azure Kubernetes Service creates for the nodes of the cluster |
| Microsoft Graph | The deployment identity holds two Microsoft Graph application permissions: `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` |
| Microsoft Entra ID | The deployment identity receives no directory role |

No other identity that the onboarding script creates holds a role on the subscription.

## Contents

1. [Sign-ins and permissions](#sign-ins-and-permissions)
2. [Inputs](#inputs)
3. [Steps of the onboarding script](#steps-of-the-onboarding-script)
4. [Directory writes](#directory-writes)
5. [Azure writes](#azure-writes)
6. [What the deployment identity holds](#what-the-deployment-identity-holds)
7. [Secrets](#secrets)
8. [Files](#files)
9. [Changes to the workstation](#changes-to-the-workstation)
10. [What the onboarding script never does](#what-the-onboarding-script-never-does)
11. [What the log records](#what-the-log-records)
12. [Repeat runs, checkpoints and failure](#repeat-runs-checkpoints-and-failure)
13. [Summary of permissions by scope](#summary-of-permissions-by-scope)

## Sign-ins and permissions

The onboarding script makes two sign-ins. Both sign-ins use the account of the administrator who runs the onboarding script. The onboarding script never signs in as a service principal.

### The sign-in to Azure Resource Manager

| Subject | Detail |
|---|---|
| Method | Az PowerShell, with the command `Connect-AzAccount`. The sign-in opens a browser |
| Multi-factor authentication | The sign-in requests the multi-factor authentication claim, because Azure requires the claim for each write |
| Alternative method | A device code, when the browser sign-in fails |
| Existing session | When the workstation already holds an Azure session, the onboarding script asks whether to use the session |
| Purpose | To write the resource group, the role assignments, the Key Vault, the storage account, the managed identities and the resource provider registrations |

When an existing Azure session lacks the multi-factor authentication claim, the onboarding script signs in again. Azure refuses a write without the claim. An unattended run shows a warning and does not sign in again.

### The sign-in to Microsoft Graph

The onboarding script tries three methods, in this order:

1. The onboarding script uses a Microsoft Graph session for the same tenant, when the workstation holds one.
2. The onboarding script requests a Microsoft Graph token from the Azure session. The administrator sees no second sign-in.
3. The onboarding script makes an interactive sign-in with the command `Connect-MgGraph`.

The onboarding script uses the sign-in to Microsoft Graph for eight kinds of write:

- the security groups
- the invitations
- the application registrations
- the agent identity blueprint
- the Microsoft Graph application permissions
- the owners
- the group assignments
- one membership of a directory role

The interactive sign-in requests eleven permission scopes of Microsoft Graph:

| Permission scope |
|---|
| `User.ReadWrite.All` |
| `User.Invite.All` |
| `Group.ReadWrite.All` |
| `Application.ReadWrite.All` |
| `Directory.ReadWrite.All` |
| `RoleManagement.ReadWrite.Directory` |
| `AppRoleAssignment.ReadWrite.All` |
| `AgentIdentityBlueprint.Create` |
| `AgentIdentityBlueprint.AddRemoveCreds.All` |
| `AgentIdentityBlueprintPrincipal.Create` |
| `AgentIdentityBlueprintPrincipal.ReadWrite.All` |

A permission scope works only while the administrator is signed in. With a permission scope, the onboarding script works as the signed-in administrator.

### The check of the roles

Before the onboarding script creates anything, the onboarding script checks two roles of the account: Owner on the subscription and Global Administrator in the tenant. The onboarding script stops when either role is missing.

Sometimes the onboarding script cannot make the check for Global Administrator. An interactive run then reports the fact and asks whether to continue. An unattended run stops.

## Inputs

| Input | Content |
|---|---|
| The answer file, `inputs.json`. The answer file is in the folder of the onboarding script, or the parameter `-AnswerFile` names the answer file | The organisation code, the organisation name and the host name. The environment type, the Azure region, the Azure region for document analysis and the environment index. The resource names and the tags. The choices about guests and existing accounts. The deployment service principal that you created |
| Command-line parameters | The organisation code, the environment type and the Azure region. The tenant, the subscription and the name of the Key Vault. The deployment service principal that you created. The switches `-NonInteractive`, `-AcceptTerms`, `-FreshRun`, `-SkipModuleInstall`, `-SkipGuestInvitation` and `-SkipPowerShellUpdate` |
| `NeologikGuestUsers.txt` | The Neologik support accounts that the onboarding script invites as guests, when you choose invitation |
| `resource-providers.txt` | The list of resource providers and preview features |
| Questions on screen | The acceptance of the terms, the installation of modules and the sign-in. Each configuration value that the answer file does not hold. The confirmation before the onboarding script creates anything |

## Steps of the onboarding script

The step numbers match the comments in the onboarding script. The first five rows have no number. The first five rows are steps 0 to 6 of the onboarding script. The onboarding script has no step 13.

| Step | What the onboarding script does |
|---|---|
| Preparation | Asks whether to resume, when an earlier run left a checkpoint. Asks the administrator to accept the terms. Checks PowerShell 7.4 and the modules |
| Sign-in | Signs in to Azure and to Microsoft Graph. Takes the subscription from the Azure session, or selects the subscription that the parameter `-SubscriptionName` names |
| Check of the roles | Checks Owner and Global Administrator |
| Resource providers, first part | Submits the registrations of the five resource providers that the onboarding script needs for the resources that the onboarding script creates. Azure completes the registrations while the onboarding script continues |
| Configuration | Collects the values from the answer file or from the questions. Asks the administrator to confirm |
| 7. Resource group | Creates the resource group with the standard tags and the tag `NeologikOnboardingKit`. Adds the tag `NeologikOnboardingKit` to an existing resource group that has no such tag |
| 8. Accounts | Invites the Neologik support accounts as guests, or looks up existing accounts, as you chose |
| 9. Security groups | Creates four security groups:<br>`Neologik User Group - <short name>`<br>`Neologik NCE Contributors - <short name>`<br>`Neologik NCE Admins - <short name>`<br>`Neologik Admin User Group - <short name>` |
| 10. Roles of the Admin User Group | Assigns ten of the thirteen Azure roles of the Admin User Group on the resource group. Steps 12 and 14 assign the other three roles |
| 11. Deployment identity | Creates the application `Neologik GitHub Service Connection - <short name>`, the service principal and a client secret. Alternatively, uses the deployment service principal that you name. Assigns the Azure roles and the two Microsoft Graph application permissions |
| 12. Key Vault | Creates the Key Vault with Azure role-based access control. Stores the client secret of the deployment identity. Assigns two Key Vault roles to the Admin User Group |
| 12b. Platform Sign-in application | Creates the Platform Sign-in application. Creates the client secret, the owners and the group assignments of the Platform Sign-in application |
| 12c. Agent identity blueprint | Creates the agent identity blueprint and the service principal of the agent identity blueprint. Creates the owners, the Microsoft Graph application permission of the principal and three federated credentials |
| 14. Storage account | Creates the storage account and three containers. Turns off public blob access and shared key access. Assigns one storage role to the Admin User Group |
| 15. Managed identities | Creates the script runner managed identity, the SQL managed identity, the agent registration identity and the system task managed identity, and assigns the roles of each. Grants the agent registration identity one Microsoft Graph application permission |
| 15b. Resource providers, second part | Submits the registrations of the other resource providers and the preview features that the Neologik Platform requires. Confirms each registration |
| 15c. Version of the onboarding kit | Records this version of the onboarding kit in the tag `NeologikOnboardingKit`. A resource group that an earlier version prepared keeps the earlier version until this step |
| 16. Export | Writes the configuration file. Uploads the configuration file and the log to the storage account. Deletes the checkpoint |

## Directory writes

The onboarding script reads each directory object before a write. The onboarding script writes only when the directory object or the property is absent.

| Directory object | Call | Properties | When the onboarding script writes |
|---|---|---|---|
| Guest invitation | `New-MgInvitation` | The address. A redirect to the Azure portal. An invitation email | You chose invitation, and no account holds the address as the mail address, the user principal name or another mail address |
| Security group | `New-MgGroup` | Display name and description. Security enabled. Not mail enabled | The security group is absent |
| Name of a security group | `Update-MgGroup` | Display name and description | The tenant holds the group `Neologik NCE Contributors - <short name>` under one of two other names that the onboarding script recognises. The security group keeps the id and the members. A new environment holds no security group with either name |
| Description of a security group | `Update-MgGroup` | Description. See [The descriptions that the onboarding script writes](#the-descriptions-that-the-onboarding-script-writes) | The security group exists with another description. When the update fails, the onboarding script reports a warning and continues |
| Member of a security group | `New-MgGroupMember` | The invited accounts, the existing accounts and the signed-in administrator. Each account joins all four security groups | The account is not already a member |
| Deployment application | `New-MgApplication` | Display name `Neologik GitHub Service Connection - <short name>`. Single-tenant sign-in audience | The onboarding script creates the deployment identity, and the application is absent |
| Deployment service principal | `New-MgServicePrincipal` | Created from the deployment application | The service principal is absent |
| Client secret of the deployment identity | `Add-MgApplicationPassword` | Display name `auth`. Valid for 365 days | Each run in which the onboarding script creates or manages the deployment identity. See [Secrets](#secrets) |
| Microsoft Graph application permissions of the deployment identity | `POST /servicePrincipals/{id}/appRoleAssignments` | `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` | The deployment identity does not already hold the permission |
| Platform Sign-in application | `New-MgApplication` | Display name `Neologik Platform Sign-in - <short name>`. Unique name `sp-admin-<solution name>`. Multi-tenant sign-in audience, so that Neologik support staff can sign in with an account of the Neologik tenant when you allow that tenant. Group claims for assigned groups. Redirect address `https://<host>/nce`. Access token version 2 | No application has the unique name |
| Display name of the Platform Sign-in application | `Update-MgApplication` | Display name | The existing display name differs |
| Service principal of the Platform Sign-in application | `New-MgServicePrincipal` | Created from the Platform Sign-in application | The service principal is absent |
| Client secret of the Platform Sign-in application | `Add-MgApplicationPassword` | Display name `auth`. Valid for 365 days | The Key Vault holds no secret with the name `sp-admin-<solution name>-auth-secret` |
| Owner of the Platform Sign-in application and of the service principal | `New-MgApplicationOwnerByRef`, `New-MgServicePrincipalOwnerByRef` | The deployment identity as owner | The deployment identity is not already an owner |
| Assignment of security groups to the Platform Sign-in application | `New-MgGroupAppRoleAssignment`, with the default access role | The groups `Neologik NCE Contributors - <short name>` and `Neologik NCE Admins - <short name>`. The sign-in token of a member then names the security groups of the member | The assignment is absent |
| Agent identity blueprint | `POST /applications/microsoft.graph.agentIdentityBlueprint` | Display name `Neologik Agent Blueprint - default - <short name>`. The signed-in administrator as sponsor. The deployment identity as owner | No application has the display name |
| Service principal of the agent identity blueprint | `POST /servicePrincipals/microsoft.graph.agentIdentityBlueprintPrincipal` | Created from the agent identity blueprint | The principal is absent |
| Owner of the agent identity blueprint and of the principal | `POST /applications/{id}/owners/$ref`, `POST /servicePrincipals/{id}/owners/$ref` | The deployment identity as owner | The deployment identity is not already an owner |
| Microsoft Graph application permission of the service principal of the agent identity blueprint | `POST /servicePrincipals/{id}/appRoleAssignments` | `AgentIdUser.ReadWrite.IdentityParentedBy`. The permission applies only to the agent users of this agent identity blueprint | The principal does not already hold the permission |
| Federated credentials on the agent identity blueprint | `POST /beta/applications/{id}/federatedIdentityCredentials` | Three federated credentials. See the next section | No federated credential has the name |
| Microsoft Graph application permission of the agent registration identity | `POST /servicePrincipals/{id}/appRoleAssignments` | `Application.ReadWrite.OwnedBy`. The permission changes only the application registrations that the agent registration identity owns | The agent registration identity does not hold the permission |
| Directory Readers role | `New-MgDirectoryRole` from the role template, then `New-MgDirectoryRoleMemberByRef` | The SQL managed identity becomes a member. Azure SQL requires the membership to look up Microsoft Entra accounts at sign-in | The onboarding script activates the role only when the role was never activated. The onboarding script adds the membership only when the membership is absent |

The onboarding script gives no administrator consent and creates no permission grant. A Global Administrator gives the consent after the deployment, as described in [FINISHING-STEPS-GUIDE.md](FINISHING-STEPS-GUIDE.md).

### The federated credentials on the agent identity blueprint

The deployment by Neologik creates agent identities and agent users as the agent identity blueprint. The deployment by Neologik exchanges the token of the Neologik deployment service for a token of the agent identity blueprint. The onboarding script stores no secret for the agent identity blueprint.

| Property | Value |
|---|---|
| Names | `github-oidc-neo-infrastructure`<br>`github-oidc-neo-bot-service`<br>`github-oidc-neo-env-config` |
| Issuer | `https://token.actions.githubusercontent.com` |
| Audience | `api://AzureADTokenExchange` |
| Trust | Each federated credential trusts one repository of the Neologik deployment. Each federated credential names the repository by the repository id, which never changes. A repository that is renamed or copied gains no access through the federated credential |

### The descriptions that the onboarding script writes

The onboarding script writes a description on each security group and on each federated credential that the onboarding script creates. The Microsoft Entra admin center shows each description.

| Directory object | Description |
|---|---|
| `Neologik User Group - <short name>` | This security group holds the people who use the Neologik agents of this environment. In the Neologik Admin Tool, each channel of a Neologik agent names the security group whose members can use the Neologik agent. |
| `Neologik NCE Contributors - <short name>` | Members of this security group hold the contributor role in the Neologik Admin Tool. A member can create and change the configuration of the Neologik Platform. |
| `Neologik NCE Admins - <short name>` | Members of this security group hold the administrator role in the Neologik Admin Tool. A member has full access to the Neologik Admin Tool, including the Blueprints, Audit and Admin pages. |
| `Neologik Admin User Group - <short name>` | Members of this security group administer and support the Azure resources of this Neologik Platform environment. This security group holds Azure roles on the resource group of the environment. |
| Each federated credential on the agent identity blueprint, `github-oidc-<repository>` | This federated credential lets a Neologik deployment run in the Neologik GitHub repository `<repository>` sign in as this agent identity blueprint with no stored secret. The Neologik deployment then creates the agent identities and the agent users of this environment. |

## Azure writes

| Object | Command | Scope | Roles or properties |
|---|---|---|---|
| Resource providers and preview features | `Register-AzResourceProvider`, `Register-AzProviderFeature` | Subscription | The list in `resource-providers.txt`: 34 resource providers and 2 preview features |
| Resource group | `New-AzResourceGroup`, `Update-AzTag` | Subscription | The name `rg-<solution name>`, in the Azure region that you chose, with tags. The tag `NeologikOnboardingKit` records the version of the onboarding kit. The onboarding script adds the tag and keeps your existing tags |
| Roles of the Admin User Group | `New-AzRoleAssignment` | Resource group | The thirteen roles in the table below. No role on the subscription |
| Roles of the deployment identity | `New-AzRoleAssignment` | Subscription | `Reader`, `Cost Management Contributor`, and `Role Based Access Control Administrator` with a condition that limits the roles the deployment identity may assign to `Reader` and `Cost Management Reader`, for service principals only |
| Roles of the deployment identity | `New-AzRoleAssignment` | Resource group | `Contributor`<br>`Key Vault Certificates Officer`<br>`Key Vault Secrets Officer`<br>`Storage Blob Data Contributor`<br>`Azure Kubernetes Service RBAC Cluster Admin`<br>`Monitoring Contributor`<br>`Role Based Access Control Administrator` |
| Key Vault | `New-AzKeyVault`, `Update-AzKeyVault` | Resource group | The name `kv<short name>`, or the name that you give. Azure role-based access control, set at creation. Tags. The onboarding script does not change the settings of an existing Key Vault |
| Role of the administrator for the secrets | `New-AzRoleAssignment` | Resource group | `Key Vault Secrets Officer` for the signed-in administrator. The onboarding script needs the role to store the client secrets |
| Key Vault secrets | `Set-AzKeyVaultSecret` | Key Vault | The secrets `neologik-deployment-service-principle-secret` and `sp-admin-<solution name>-auth-secret`. The onboarding script stores no client secret of the deployment identity when you name a deployment service principal and give no client secret |
| Storage account | `New-AzStorageAccount`, `Set-AzStorageAccount`, `New-AzRmStorageContainer` | Resource group | Standard LRS, StorageV2. Public blob access is turned off at creation. Shared key access is turned off on each run. Three private containers: `certificate`, `json` and `logs` |
| Role of the administrator for the upload | `New-AzRoleAssignment` | Resource group | `Storage Blob Data Contributor` for the signed-in administrator |
| Script runner managed identity | `New-AzUserAssignedIdentity`, `New-AzRoleAssignment` | Resource group | The name `neologik-script-runner-service-connection-<short name>`. The roles `Reader` and `Key Vault Secrets Officer` on the resource group. No role on the subscription |
| SQL managed identity | `New-AzUserAssignedIdentity` | Resource group | The name `neologik-sql-managed-identity-<short name>`. No Azure role |
| Agent registration identity | `New-AzUserAssignedIdentity` | Resource group | The name `neologik-directory-managed-identity-<short name>`. No Azure role. The Microsoft Graph application permission `Application.ReadWrite.OwnedBy` |
| System task managed identity | `New-AzUserAssignedIdentity`, `New-AzRoleAssignment` | Resource group | The name `neologik-system-task-managed-identity-<short name>`. `Role Based Access Control Administrator` on the resource group with a condition that stops the managed identity assigning `Owner`, `User Access Administrator` or `Role Based Access Control Administrator`, and limits every other assignment to service principals |
| Uploads | `Set-AzStorageBlobContent` | The containers `json` and `logs` | The configuration file and the log. The upload uses Microsoft Entra authentication |

| The thirteen roles of the Admin User Group on the resource group |
|---|
| `Contributor` |
| `Azure Kubernetes Service Cluster Admin Role` |
| `Azure Kubernetes Service RBAC Cluster Admin` |
| `Key Vault Administrator` |
| `Key Vault Secrets Officer` |
| `Key Vault Certificates Officer` |
| `Storage Blob Data Owner` |
| `Storage Blob Data Contributor` |
| `Storage Table Data Contributor` |
| `Cognitive Services Data Reader` |
| `Cognitive Services OpenAI Contributor` |
| `Search Index Data Reader` |
| `Azure AI Developer` |

Three further points apply to the Azure writes.

| Subject | Detail |
|---|---|
| Repeated attempts | A new service principal or managed identity takes time to reach every server of Microsoft Entra ID. The onboarding script tries each role assignment up to ten times, ten seconds apart |
| Roles of the signed-in administrator | The two roles of the signed-in administrator remain after the run. You can remove the two roles after onboarding |
| Network | The onboarding script sets no network restriction on the Key Vault or on the storage account. The deployment by Neologik applies the network settings of your deployment type |

## What the deployment identity holds

| Kind | What the deployment identity holds |
|---|---|
| Azure roles | `Reader`, `Cost Management Contributor` and the limited `Role Based Access Control Administrator` on the subscription. The seven roles on the resource group listed under [Azure writes](#azure-writes) |
| Microsoft Graph application permissions | `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All`. The next table describes each permission |
| Microsoft Entra directory roles | None |
| Membership of security groups | None |
| Ownership | Owner of the Platform Sign-in application and of the service principal of the Platform Sign-in application. Owner of the agent identity blueprint and of the service principal of the agent identity blueprint |
| Credential | One client secret, stored in your Key Vault |

| Microsoft Graph application permission | What the permission allows |
|---|---|
| `Application.ReadWrite.OwnedBy` | The deployment identity manages only the application registrations that the deployment identity owns |
| `AgentIdentityBlueprint.AddRemoveCreds.All` | The deployment identity adds and removes credentials on agent identity blueprints |

After the deployment, the Neologik Platform grants the deployment identity one further role. The role is `Cognitive Services Content Understanding Contributor`, on one Azure AI resource inside the resource group.

## Secrets

| Secret | Who creates the secret | Where the secret is stored | Is the value printed, logged or exported? |
|---|---|---|---|
| Client secret of the deployment identity | The onboarding script. The client secret is valid for 365 days | The Key Vault secret `neologik-deployment-service-principle-secret` | Never. The configuration file holds the expiry date only |
| Client secret of a deployment service principal that you created | You | The same Key Vault secret | Never. The checkpoint does not hold the value |
| Client secret of the Platform Sign-in application | The onboarding script. The client secret is valid for 365 days | The Key Vault secret `sp-admin-<solution name>-auth-secret` | Never |

The TLS certificate is separate from these secrets. With a Neologik-managed certificate, Neologik obtains the certificate for the host name and renews the certificate; your Key Vault holds nothing for the certificate. With your own certificate, an administrator imports the certificate into your Key Vault. Neologik then copies the certificate, private key included, into Neologik's central Key Vault. Each deployment of the ingress reads the certificate from Neologik's central Key Vault.

### A client secret in the answer file

When you put the client secret in the answer file, the answer file holds the value on disk. To avoid that, give the client secret on the command line or at the question on screen. The question on screen hides the characters that you type.

### How Neologik obtains the client secret of the deployment identity

The Neologik support accounts are members of the group `Neologik Admin User Group - <short name>`. A Neologik support account reads the client secret of the deployment identity from your Key Vault to configure the deployment.

When no Neologik account can read the Key Vault, agree with Neologik how to pass the client secret. Never put the client secret in the configuration file or in an email.

### A second run adds a second client secret

Each run in which the onboarding script manages the deployment identity adds a new client secret to the application. The onboarding script stores the new client secret as a new version of the Key Vault secret.

The onboarding script does not remove the earlier client secret. The earlier client secret remains valid until the expiry date. After a second run, remove the earlier client secret from the application in the Microsoft Entra admin centre.

A second run adds no client secret to the Platform Sign-in application while the Key Vault holds the secret `sp-admin-<solution name>-auth-secret`.

## Files

| File | Location | Content |
|---|---|---|
| `NeologikOnboarding_<timestamp>.log` | The folder of the onboarding script. The onboarding script uploads a copy to the container `logs` | The log of the run |
| `Neologik_<org><index>_Configuration_<timestamp>.json` | The folder of the onboarding script. The onboarding script uploads a copy to the container `json` | The version of the onboarding script and the version of the onboarding kit. The name and the id of each object created. The roles assigned. The host name. The Azure region for document analysis. The sign-in name of the administrator. The addresses of the accounts invited or added. The expiry date of the client secret |
| `NeologikCheckpoint.json` | The folder of the onboarding script, while a run is incomplete | The configuration collected so far, in the same form as the configuration file. The onboarding script deletes the checkpoint when the run completes |

None of the three files contains a secret. All three files contain personal data, namely sign-in names and email addresses. Handle the three files as personal data.

## Changes to the workstation

Before the first run, you make two changes in the PowerShell window. The preparation steps of `README.md` give both commands. The onboarding script makes neither change.

| Change | What the change does | What remains after the window closes |
|---|---|---|
| `Get-ChildItem .\*.ps1 \| Unblock-File` | Removes the mark that Windows puts on each file extracted from a downloaded zip. Without it, PowerShell refuses the scripts with the words `not digitally signed` | The scripts stay unblocked |
| `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` | Lifts the execution policy for the current PowerShell window only | Nothing. Windows does not keep the setting |

The onboarding script makes these changes:

| Change | When the onboarding script makes the change |
|---|---|
| The onboarding script marks the PowerShell Gallery as a trusted repository for the user. The setting remains after the run | The onboarding script installs a module |
| The onboarding script installs the Az modules and the Microsoft Graph modules for the current user | A module is missing, and you accept |
| The onboarding script updates PowerShell | The PowerShell version is older than 7.4, and you accept |
| The onboarding script removes each module that the onboarding script installed in the run | A file of an installed module fails the signature check. See [TECHNICAL-REFERENCE.md](TECHNICAL-REFERENCE.md#signature-checks) |
| The onboarding script deletes the PowerShell installer that the onboarding script downloaded | The installer fails the signature check |
| The onboarding script clears the stored Azure session and the stored Microsoft Graph session of the user | You choose to sign in again |

## What the onboarding script never does

- The onboarding script never grants a Microsoft Graph application permission other than the three permissions in [Summary of permissions by scope](#summary-of-permissions-by-scope).
- The onboarding script never gives administrator consent and never creates a permission grant.
- The onboarding script never creates a subscription.
- The onboarding script never adds the deployment identity or a managed identity to a security group.
- The onboarding script never assigns a role on the subscription to a managed identity or to a security group.
- The onboarding script never prints the value of a secret. The onboarding script never writes the value of a secret to the log, to the configuration file or to the checkpoint.
- The onboarding script never runs a downloaded PowerShell installer and never imports a downloaded module before the signature of the file passes the check.
- The onboarding script never deletes a directory object, an Azure resource, a role assignment or a credential.

## What the log records

| The log records |
|---|
| The account and the tenant of the sign-in |
| The subscription |
| Each object created or found, with the id |
| Each role assignment |
| The name of each secret stored |
| The addresses of the accounts invited or added |
| The progress of the resource provider registrations |
| The path of the configuration file |
| After a failure, the error and the stack trace of the onboarding script |

The log contains no secret and no token.

The questions, the configuration summary and the completion summary appear on screen only.

## Repeat runs, checkpoints and failure

### Repeat runs

The onboarding script reads before each creation and uses the object that exists. A second run on a complete environment creates nothing, with two exceptions.

| Exception | What a second run does |
|---|---|
| Client secret of the deployment identity | Adds a new client secret, as described under [Secrets](#secrets) |
| Shared key access of the storage account | Turns shared key access off again |

### Checkpoints

The onboarding script writes a checkpoint at these points:

- after the onboarding script submits the resource provider registrations
- after the administrator confirms the configuration
- after the onboarding script confirms a resource provider registration

| Where the run stopped | What to do |
|---|---|
| After the administrator confirmed the configuration | Run the onboarding script again and resume. The onboarding script skips the terms and the questions. Each step runs again and uses the objects that the earlier run created |
| Before the administrator confirmed the configuration | Run the onboarding script again and resume. The checkpoint holds no configuration, so the onboarding script asks the questions again |

### Failure

| Event | What the onboarding script does |
|---|---|
| The onboarding script cannot add an account to a security group | Reports a warning and continues |
| A resource provider is still registering at the end of the run | Lists the resource provider on screen and in the configuration file. Run `Register-NeologikResourceProviders.ps1` to confirm the registration |

| Exit code | Meaning |
|---|---|
| 0 | The run completed, or the administrator declined the terms. The onboarding script also ends with exit code 0 after an update of PowerShell |
| 1 | The run failed. The onboarding script shows the error and stops |
| 2 | The run stopped because the account lacks a permission. The onboarding script names the permission and keeps the checkpoint. Obtain the permission, then run the onboarding script again and resume |

## Summary of permissions by scope

| Scope | Who holds the roles or the permissions | Roles or permissions |
|---|---|---|
| Subscription | Deployment identity | Reader, Cost Management Contributor, and Role Based Access Control Administrator limited to assigning two roles, Reader and Cost Management Reader, to service principals only |
| Resource group | Deployment identity | Contributor<br>Key Vault Certificates Officer<br>Key Vault Secrets Officer<br>Storage Blob Data Contributor<br>Azure Kubernetes Service RBAC Cluster Admin<br>Monitoring Contributor<br>Role Based Access Control Administrator |
| Resource group | Script runner managed identity. The deployment runs scripts inside Azure as this managed identity | Reader<br>Key Vault Secrets Officer |
| Resource group | The group `Neologik Admin User Group - <short name>` | The thirteen roles listed under [Azure writes](#azure-writes) |
| Resource group | The signed-in administrator | Key Vault Secrets Officer and Storage Blob Data Contributor |
| Microsoft Graph application permissions | Deployment identity | `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` |
| Microsoft Graph application permissions | Service principal of the agent identity blueprint | `AgentIdUser.ReadWrite.IdentityParentedBy` |
| Microsoft Graph application permissions | Agent registration identity | `Application.ReadWrite.OwnedBy` |
| Microsoft Entra directory roles | SQL managed identity | Directory Readers |
| Microsoft Entra directory roles | Deployment identity | None |
| Membership of security groups | Deployment identity and managed identities | None |
