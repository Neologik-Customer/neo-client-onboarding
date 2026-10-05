# Install-NeologikEnvironment.ps1: Technical Reference

## Overview

This document describes the onboarding script, `Install-NeologikEnvironment.ps1`, in detail. The reader is the administrator who runs the onboarding script and needs more detail than [README.md](../README.md) gives.

| Subject | Section |
|---|---|
| What the onboarding script requires | [Requirements](#requirements) |
| The parameters and the answer file | [Parameters](#parameters) and [Answer file](#answer-file) |
| The names of the objects that the onboarding script creates | [Naming](#naming) |
| The objects that the onboarding script creates | [What the onboarding script creates](#what-the-onboarding-script-creates) |
| The files that the onboarding script writes | [Output files](#output-files) |

[QUICK-REFERENCE.md](QUICK-REFERENCE.md) is the security description of the onboarding script. `QUICK-REFERENCE.md` lists each change that the onboarding script makes and each permission that the onboarding script grants.

| Item | Value |
|---|---|
| Version of the onboarding script | v5.0.8 |
| Version of the onboarding kit | v5.0.14 |

The onboarding kit has a version, and each script has a separate version. The version of the onboarding kit follows the version of the Neologik Platform. The version of a script changes when the script changes.

## Contents

1. [Requirements](#requirements)
2. [Parameters](#parameters)
3. [Answer file](#answer-file)
4. [Unattended runs](#unattended-runs)
5. [Examples](#examples)
6. [Naming](#naming)
7. [Input validation](#input-validation)
8. [What the onboarding script creates](#what-the-onboarding-script-creates)
9. [Resource provider registration](#resource-provider-registration)
10. [Output files](#output-files)
11. [The TLS certificate](#the-tls-certificate)
12. [Troubleshooting](#troubleshooting)
13. [Help](#help)

## Requirements

| Requirement | Detail |
|---|---|
| Azure role | Owner on the subscription. The Contributor role is not enough, because the onboarding script assigns Azure roles |
| Microsoft Entra role | Global Administrator. See [Actions that need the Global Administrator role](#actions-that-need-the-global-administrator-role) |
| Workstation | Windows 10 or Windows 11 |
| PowerShell | PowerShell 7.4 or later. When the version is older, the onboarding script asks whether to update PowerShell |
| PowerShell modules | The modules listed under [PowerShell modules](#powershell-modules). When a module is missing, the onboarding script asks whether to install the module for the current user |
| Network | The workstation must reach Azure, Microsoft Graph and the PowerShell Gallery |
| Files | `NeologikGuestUsers.txt` and `resource-providers.txt`, in the folder of the onboarding script |

### Actions that need the Global Administrator role

| Action of the onboarding script |
|---|
| The onboarding script creates the application registrations |
| The onboarding script creates the agent identity blueprint |
| The onboarding script grants the Microsoft Graph application permissions |
| The onboarding script assigns the security groups to the Platform Sign-in application |
| The onboarding script adds the SQL managed identity to the Directory Readers role |

### PowerShell modules

| PowerShell module | Lowest version |
|---|---|
| `Az.Accounts` | 5.2.0 |
| `Az.Resources` | 7.0.0 |
| `Az.Compute` | 7.0.0 |
| `Az.KeyVault` | 5.0.0 |
| `Az.Storage` | 6.0.0 |
| `Az.ManagedServiceIdentity` | 1.0.0 |
| `Microsoft.Graph` | 2.0.0 |

## Parameters

Every parameter is optional. When you give no value for a parameter, the onboarding script takes the value from the answer file or asks a question.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-OrganizationCode` | String | The onboarding script asks | The organisation code of three characters |
| `-EnvironmentType` | String | `dev` | The environment type: `dev` or `prd` |
| `-AzureRegion` | String | `uksouth` | The Azure region for the resources |
| `-TenantId` | String | The tenant of the sign-in | The tenant to sign in to |
| `-SubscriptionName` | String | The subscription of the sign-in | The name of the subscription to use. The onboarding script selects the subscription after the sign-in. The onboarding script stops when the account cannot see the subscription. A resumed run uses the subscription from the checkpoint |
| `-KeyVaultName` | String | `kv<short name>` | A name of your choice for the Key Vault |
| `-ExistingServicePrincipalObjectId` | String | None | The object ID of the enterprise application of a deployment service principal that you created. The onboarding script assigns the Azure roles and the Microsoft Graph application permissions to that deployment service principal. The onboarding script creates no deployment service principal |
| `-ExistingServicePrincipalSecret` | String | None | The client secret of the deployment service principal that you created. The onboarding script stores the client secret in the Key Vault. Without this parameter, add the client secret to the Key Vault yourself before the first deployment |
| `-AnswerFile` | String | `inputs.json` in the folder of the onboarding script | The path of the answer file |
| `-SkipGuestInvitation` | Switch | Off | The onboarding script invites no guest. The onboarding script still creates the security groups, with the signed-in user as a member |
| `-SkipPowerShellUpdate` | Switch | Off | The onboarding script does not check the PowerShell version |
| `-SkipModuleInstall` | Switch | Off | The onboarding script does not check the PowerShell modules |
| `-NonInteractive` | Switch | Off | The onboarding script runs without questions. See [Unattended runs](#unattended-runs) |
| `-AcceptTerms` | Switch | Off | Accepts the Terms of Use and the Privacy Policy. Required with `-NonInteractive` |
| `-FreshRun` | Switch | Off | The onboarding script deletes the checkpoint of an earlier run without a question |

## Answer file

You can prepare every answer before the run.

1. Copy `inputs-example.json` to `inputs.json` in the folder of the onboarding script. To use another file name, name the file with the parameter `-AnswerFile`.
2. Enter your values in the answer file.

Each value then appears as the default value of the matching question. Press Enter to accept the value, or type another value.

When the answer file holds the organisation code, the organisation name and the host name, the onboarding script shows the configuration summary first. Type `N` at the configuration summary to go through the questions one at a time.

| Key | Value |
|---|---|
| `organizationCode` | The organisation code of three characters. A complete answer file holds this key |
| `organizationName` | The full name of the organisation. A complete answer file holds this key |
| `fqdn` | The fully qualified host name of the environment. A complete answer file holds this key |
| `environmentType` | `dev` or `prd` |
| `azureRegion` | The Azure region |
| `environmentIndex` | `01` to `99` |
| `budgetCostReportEmailRecipients` | A list of email addresses for the daily cost report. The value `none` turns the report off |
| `applyResourceTags` | `true` or `false` |
| `resourceTagsCustom` | Further tags, written as an object or as a string of `key=value` pairs |
| `solutionName`, `solutionShortName` | The solution name and the short name. See [Naming](#naming) |
| `resourceGroupName`<br>`keyVaultName`<br>`storageAccountName`<br>`scriptRunnerIdentityName`<br>`sqlIdentityName` | Names of your choice for the five resources |
| `skipGuestInvitation` | `true` to invite no guest |
| `addExistingAccountsToGroups` | `true` to add existing accounts to the security groups. The onboarding script reads this key only when `skipGuestInvitation` is `true` |
| `existingAccountEmails` | The email addresses of the existing accounts. Without this key, the onboarding script uses the addresses in `NeologikGuestUsers.txt` |
| `useExistingServicePrincipal` | `true` to use a deployment service principal that you created |
| `existingServicePrincipalObjectId` | The object ID of the enterprise application of that deployment service principal |
| `existingServicePrincipalSecret` | The client secret of that deployment service principal. Prefer the parameter `-ExistingServicePrincipalSecret`, which keeps the client secret out of the answer file |

The onboarding script never reads three answers from the answer file. The onboarding script always asks you to accept the terms, to agree to the installation of modules and to sign in.

## Unattended runs

The parameter `-NonInteractive` runs the onboarding script without questions. Use an unattended run for automation.

| Condition | Detail |
|---|---|
| Answer file | The answer file must hold `organizationCode`, `organizationName` and `fqdn`. The onboarding script checks the three keys before any other action |
| Terms | Give the parameter `-AcceptTerms`. The onboarding script writes the acceptance to the log |
| Sign-in | The caller signs in to Azure and to Microsoft Graph before the caller starts the onboarding script. The onboarding script uses both sessions. An access token lasts about one hour. The onboarding script cannot renew an access token during the run |
| Checkpoint | When an earlier run left a checkpoint, the onboarding script stops with an error. Give the parameter `-FreshRun` to delete the checkpoint |
| Switches | Give `-SkipPowerShellUpdate` and `-SkipModuleInstall`. State in the answer file whether you created the deployment service principal. The onboarding script then has no question to ask |
| Checks | When a check would ask a question in an interactive run, the onboarding script stops |
| Upload | The onboarding script tries the upload of the configuration file and the log once |

```powershell
Connect-AzAccount -AccessToken $armToken -AccountId $accountName -TenantId $tenantId -SubscriptionId $subscriptionId
Connect-MgGraph -AccessToken (ConvertTo-SecureString $graphToken -AsPlainText -Force)

.\Install-NeologikEnvironment.ps1 -NonInteractive -AcceptTerms -FreshRun `
    -AnswerFile .\inputs.json -SkipPowerShellUpdate -SkipModuleInstall
```

Run the three commands in the same PowerShell session. The onboarding script then finds both sign-ins.

The signed-in account must hold Owner on the subscription and Global Administrator, as for an interactive run.

## Examples

An interactive run:

```powershell
.\Install-NeologikEnvironment.ps1
```

A production environment in the Azure region UK West:

```powershell
.\Install-NeologikEnvironment.ps1 -OrganizationCode "abc" -EnvironmentType "prd" -AzureRegion "ukwest"
```

A deployment service principal that you created, as described in [CREATE-SP-GUIDE.md](CREATE-SP-GUIDE.md):

```powershell
.\Install-NeologikEnvironment.ps1 `
    -ExistingServicePrincipalObjectId "00000000-0000-0000-0000-000000000000" `
    -ExistingServicePrincipalSecret $env:SP_CLIENT_SECRET
```

A Key Vault name of your choice:

```powershell
.\Install-NeologikEnvironment.ps1 -KeyVaultName "kv-abc-neologik"
```

## Naming

The onboarding script builds every standard name from two values: the solution name and the short name. The examples use the organisation code `abc`, the environment type `prd`, the Azure region UK South and the environment index `01`.

| Value | Pattern | Example |
|---|---|---|
| Solution name | `neo-<org><env>-<region>-<index>` | `neo-abcprd-uks-01` |
| Short name | `<org><env><index>` | `abcprd01` |

`<region>` stands for the short form of the Azure region. The onboarding script shows the short form on screen when you choose the Azure region.

| Object | Standard name | Example |
|---|---|---|
| Resource group | `rg-<solution name>` | `rg-neo-abcprd-uks-01` |
| Key Vault | `kv<short name>` | `kvabcprd01` |
| Deployment storage account | `stneodeploy<org><env><region><index>`, cut to 24 characters | `stneodeployabcprduks01` |
| Script runner managed identity | `neologik-script-runner-service-connection-<short name>` | `neologik-script-runner-service-connection-abcprd01` |
| SQL managed identity | `neologik-sql-managed-identity-<short name>` | `neologik-sql-managed-identity-abcprd01` |
| Security groups | `Neologik User Group - <short name>`<br>`Neologik NCE Contributors - <short name>`<br>`Neologik NCE Admins - <short name>`<br>`Neologik Admin User Group - <short name>` | `Neologik User Group - abcprd01` |
| Deployment identity | `Neologik GitHub Service Connection - <short name>` | `Neologik GitHub Service Connection - abcprd01` |
| Platform Sign-in application | `Neologik Platform Sign-in - <short name>` | `Neologik Platform Sign-in - abcprd01` |
| Agent identity blueprint | `Neologik Agent Blueprint - default - <short name>` | `Neologik Agent Blueprint - default - abcprd01` |

### Names of your choice

| Name | Where you can change the name |
|---|---|
| The names of the resource group, the Key Vault, the deployment storage account and the two managed identities | At the question on screen, or in the answer file |
| The solution name and the short name | In the answer file only |

The short name is also the last part of the name of each security group, each application and each managed identity.

When you have a naming standard, send the naming standard to Neologik. The deployment then names the resources that the deployment creates inside the resource group to the same naming standard.

## Input validation

The onboarding script repeats a question until the value is valid.

| Value | Rule |
|---|---|
| Organisation code | Exactly three letters or digits. The onboarding script converts the code to lower case |
| Organisation name | Required |
| Host name | A fully qualified host name. The onboarding script removes a prefix such as `https://` and removes a path. The onboarding script converts the host name to lower case |
| Environment type | `dev` or `prd`. The onboarding script also accepts `dmo`, `test` and `stg`. Neologik reserves those three values for environments that Neologik operates |
| Azure region | An Azure region that the subscription can use |
| Environment index | 01 to 99 |
| Resource group name | 1 to 90 characters. Letters, digits, underscores, hyphens, full stops and round brackets. No full stop at the end |
| Key Vault name | 3 to 24 characters. Letters, digits and hyphens. The first character is a letter. The last character is a letter or a digit. No two hyphens together |
| Storage account name | 3 to 24 characters. Lower-case letters and digits |
| Managed identity name | 3 to 128 characters. Letters, digits, hyphens and underscores. The first character is a letter or a digit |
| Email address | The form of a valid email address |
| Custom tag | The key holds letters, digits, full stops, underscores and hyphens. The value holds no comma and no equals sign |

The onboarding script converts the solution name and the short name from the answer file to lower case. The onboarding script makes no other check on those two values. Check that each name built from the two values is valid.

## What the onboarding script creates

### Resource group

The onboarding script creates the resource group in the Azure region that you chose.

When you choose tags, the onboarding script tags the resource group and each other resource that the onboarding script creates. The table lists the standard tags. The onboarding script adds your custom tags to the standard tags. A custom tag replaces a standard tag of the same name.

| Tag | Value |
|---|---|
| `Vendor` | `Neologik` |
| `ApplicationName` | `NeologikPlatform` |
| `ManagedBy` | `NeologikOnboarding` |
| `Environment` | The organisation code and the environment type, for example `abcprd` |
| `Solution` | The short name, for example `abcprd01` |
| `DeploymentDate` | The date of the run |

The onboarding script also adds the tag `NeologikOnboardingKit` to the resource group. The tag records the version of the onboarding kit, `v5.0.9`. The onboarding script adds the tag `NeologikOnboardingKit` even when you choose no tags. The Neologik Platform reads the tag before an upgrade.

### Guest users

When you choose invitation, the onboarding script invites each address in `NeologikGuestUsers.txt` and each address that you add at the question. The onboarding script sends no invitation to an address that already has an account in the tenant. The onboarding script uses the existing account, whether the account is a guest or a member.

`NeologikGuestUsers.txt` has this format:

| Rule |
|---|
| One address on each line |
| The onboarding script ignores a blank line |
| A line that begins with `#` is a comment |

When you decline invitation, the onboarding script asks whether to add existing accounts to the security groups. The onboarding script sends no invitation. Each address must match the mail address or the user principal name of an account exactly. The onboarding script reports an address that matches no account and continues.

Each account that you invite or add joins all four security groups. One of the four is the group `Neologik Admin User Group - <short name>`. List only the accounts that need Neologik administration and support access.

### Security groups

| Group | Purpose |
|---|---|
| `Neologik User Group - <short name>` | The standard security group for access to agents. A member can use each agent that uses this security group |
| `Neologik NCE Contributors - <short name>` | A member configures agents and Apps in the Neologik Context Engine |
| `Neologik NCE Admins - <short name>` | A member administers the Neologik Context Engine and installs use cases |
| `Neologik Admin User Group - <short name>` | A member administers the Azure resources in the resource group |

The onboarding script makes the signed-in user a member of each security group. The onboarding script also makes each invited account and each added account a member of each security group.

The onboarding script assigns two security groups to the Platform Sign-in application. The two security groups are `Neologik NCE Contributors - <short name>` and `Neologik NCE Admins - <short name>`. The sign-in token of a member then names the security groups of the member. The Neologik Context Engine reads the security groups from the sign-in token to decide what the member can do.

The Neologik Platform creates no security group.

### Deployment identity

The onboarding script creates the application `Neologik GitHub Service Connection - <short name>`, with a service principal and a client secret. The client secret is valid for 365 days. Alternatively, the onboarding script uses the deployment service principal that you name.

The onboarding script stores the client secret in the Key Vault, as the secret `neologik-deployment-service-principle-secret`.

| Scope | What the deployment identity holds |
|---|---|
| Subscription | Reader, Cost Management Contributor, and Role Based Access Control Administrator limited to assigning two roles: Reader and AppGw for Containers Configuration Manager |
| Resource group | Contributor<br>Key Vault Certificates Officer<br>Key Vault Secrets Officer<br>Storage Blob Data Contributor<br>Azure Kubernetes Service RBAC Cluster Admin<br>Monitoring Contributor<br>Role Based Access Control Administrator |
| Microsoft Graph application permissions | `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` |
| Security groups | No membership |

| Microsoft Graph application permission | What the permission allows |
|---|---|
| `Application.ReadWrite.OwnedBy` | The deployment identity manages only the application registrations that the deployment identity owns |
| `AgentIdentityBlueprint.AddRemoveCreds.All` | The deployment identity adds and removes credentials on the agent identity blueprint |

### Key Vault

The onboarding script creates the Key Vault with Azure role-based access control. The group `Neologik Admin User Group - <short name>` receives two roles on the resource group: Key Vault Secrets Officer and Key Vault Certificates Officer.

### Platform Sign-in application

The onboarding script creates the application `Neologik Platform Sign-in - <short name>`. The Platform Sign-in application signs users in to the Neologik Context Engine and to Apps.

| Subject | Detail |
|---|---|
| Owner | The onboarding script makes the deployment identity an owner of the Platform Sign-in application and of the service principal of the Platform Sign-in application |
| Security groups | The onboarding script assigns the groups `Neologik NCE Contributors - <short name>` and `Neologik NCE Admins - <short name>` to the Platform Sign-in application |
| Sign-in audience | Multi-tenant |
| Redirect address | `https://<host>/nce` |
| Group claims | The security groups assigned to the Platform Sign-in application |
| Client secret | The onboarding script creates a client secret when the Key Vault holds no client secret for the Platform Sign-in application. The client secret is valid for 365 days. The onboarding script stores the client secret in the Key Vault, as the secret `sp-admin-<solution name>-auth-secret` |

The onboarding script declares no permission on the Platform Sign-in application and gives no consent. A Global Administrator gives the consent after the deployment, as described in [FINISHING-STEPS-GUIDE.md](FINISHING-STEPS-GUIDE.md).

After onboarding, the deployment by Neologik maintains the application registration of the Platform Sign-in application.

### Agent identity blueprint

The onboarding script creates the agent identity blueprint of the environment, `Neologik Agent Blueprint - default - <short name>`. The onboarding script also creates the service principal of the agent identity blueprint. The onboarding script creates both objects under the sign-in of the Global Administrator.

The Neologik Platform creates the agent identities and the agent user accounts of the environment under the agent identity blueprint.

| Item | Value |
|---|---|
| Sponsor | The signed-in administrator. The sponsor is the person who is accountable for the agents of the environment. Each agent identity that the Neologik Platform creates takes the sponsor of the agent identity blueprint. The agent identity blueprint can already exist with no sponsor. The onboarding script then adds the signed-in administrator. A Global Administrator can change the sponsor in the Microsoft Entra admin centre |
| Owner | The deployment identity owns the agent identity blueprint and the service principal of the agent identity blueprint |
| Microsoft Graph application permission of the principal | `AgentIdUser.ReadWrite.IdentityParentedBy`. The permission applies only to the agent users of this agent identity blueprint |
| Federated credentials | Three. The next table lists the three federated credentials |

| Federated credential |
|---|
| `github-oidc-neo-infrastructure` |
| `github-oidc-neo-bot-service` |
| `github-oidc-neo-env-config` |

Each federated credential trusts one repository of the Neologik deployment. Each federated credential names the repository by the repository id. The issuer of each federated credential is `https://token.actions.githubusercontent.com`. The onboarding script stores no secret for the agent identity blueprint.

### Storage account

| Property | Value |
|---|---|
| Authentication | Microsoft Entra ID only. Shared key access is turned off |
| Public blob access | Turned off |
| Containers | `certificate`, `json` and `logs` |
| Role | The group `Neologik Admin User Group - <short name>` receives Storage Blob Data Contributor on the resource group |

### Managed identities

| Managed identity | Purpose | Roles |
|---|---|---|
| `neologik-script-runner-service-connection-<short name>` | The deployment runs scripts inside Azure as this managed identity | Reader, Key Vault Secrets Officer and Azure Bot Service Contributor Role on the resource group. No role on the subscription |
| `neologik-sql-managed-identity-<short name>` | Azure SQL uses this managed identity to look up Microsoft Entra accounts at sign-in | Directory Readers in Microsoft Entra ID |

### Roles of the Admin User Group

The group `Neologik Admin User Group - <short name>` holds thirteen roles on the resource group and no role on the subscription.

| Roles on the resource group |
|---|
| Contributor |
| Azure Kubernetes Service Cluster Admin Role |
| Azure Kubernetes Service RBAC Cluster Admin |
| Key Vault Administrator |
| Key Vault Secrets Officer |
| Key Vault Certificates Officer |
| Storage Blob Data Owner |
| Storage Blob Data Contributor |
| Storage Table Data Contributor |
| Cognitive Services Data Reader |
| Cognitive Services OpenAI Contributor |
| Search Index Data Reader |
| Azure AI Developer |

## Resource provider registration

The Neologik Platform requires the Azure resource providers and the preview features in `resource-providers.txt`. The deployment identity cannot register a resource provider. The onboarding script registers the resource providers, under your sign-in.

Azure takes some minutes to register a resource provider. The onboarding script works in this order:

1. The onboarding script checks your roles.
2. The onboarding script submits every registration and continues with the other steps.
3. Before the onboarding script creates a resource, the onboarding script confirms the resource provider of that resource.
4. Before the onboarding script writes the configuration file, the onboarding script confirms every registration.

When a registration is still in progress at the end of the run, the completion summary lists the resource provider. The configuration file lists the resource provider under `ResourceProvidersPending`. Run this command before the deployment:

```powershell
.\Register-NeologikResourceProviders.ps1
```

| Parameter | Purpose |
|---|---|
| `-SubscriptionId` | The subscription, when the subscription differs from the subscription of the current Azure session |
| `-TenantId` | The tenant to sign in to, when no Azure session exists |
| `-TimeoutSeconds` | The number of seconds to wait for the registrations. The default is 900 |
| `-ListOnly` | Prints the list of resource providers and contacts no Azure service |

The account that runs `Register-NeologikResourceProviders.ps1` needs Contributor or Owner on the subscription.

`Register-NeologikResourceProviders.ps1` ends with exit code 1 when a registration is still in progress at the end of the wait. Azure completes the registration without further action. Run `Register-NeologikResourceProviders.ps1` again later to confirm the registration.

## Output files

| File | Content |
|---|---|
| `Neologik_<org><index>_Configuration_<timestamp>.json` | The configuration that Neologik needs for the deployment |
| `NeologikOnboarding_<timestamp>.log` | The log of the run |

The onboarding script writes both files to the folder of the onboarding script. The onboarding script then uploads the configuration file to the container `json` and the log to the container `logs` of the deployment storage account.

When the upload of the configuration file fails, the completion summary reports the failure. Send the configuration file to Neologik by email.

The configuration file holds these sections:

| Section | Content |
|---|---|
| Environment | The tenant, the subscription, the resource group, the Azure region, the organisation, the host name, the solution name and the short name |
| `SecurityGroups` | The name and the id of each of the four security groups |
| `AppRegistration` | The deployment identity: the name, the client id and the roles. The section also records whether the onboarding script created the deployment identity |
| `NceAuthApp` | The Platform Sign-in application: the name and the client id |
| `AgentBlueprint` | The agent identity blueprint: the name, the ids and the names of the federated credentials |
| `KeyVault`, `StorageAccount`, `ManagedIdentities` | The name and the id of each resource |
| Accounts | The sign-in name of the administrator who ran the onboarding script, the addresses of the accounts invited or added, and the cost report recipients |
| `ResourceProvidersPending` | Each registration that is still in progress |

Neither file contains a secret. Both files contain sign-in names and email addresses.

## The TLS certificate

Provide the TLS certificate for the host name of the environment by one of two methods. [PFX-CERT-GUIDE.md](PFX-CERT-GUIDE.md) explains how to prepare the PFX file.

The TLS certificate must contain the server certificate, the intermediate certificates and the private key.

### Method 1: Import the PFX file into the Key Vault

Neologik recommends this method.

1. In the Azure portal, open the Key Vault of the environment.
2. Select **Certificates**, then **Generate/Import**.
3. Select **Import**.
4. Name the certificate `keyvault-neo-ingress`.
5. Select the `.pfx` file and enter the password of the `.pfx` file.
6. Select **Create**.

The Key Vault uses the password for the import only. Do not send the password to Neologik.

### Method 2: Upload the files to the deployment storage account

1. Sign in with Microsoft Entra ID.
2. Upload the files to the container `certificate` of the deployment storage account. Upload either the `.pfx` file, or the private key, the server certificate and the certificate authority bundle.
3. When you upload a `.pfx` file, store the password of the `.pfx` file in the Key Vault. Name the secret `neologik-deployment-certificate-pfx-secret`.
4. Tell Neologik which files you uploaded.

## Troubleshooting

| Symptom | Cause | Action |
|---|---|---|
| "The script requires PowerShell 7.4 or later." | The PowerShell version is older than 7.4, or you opened Windows PowerShell | Install PowerShell 7 from https://aka.ms/powershell and open PowerShell 7 |
| The onboarding script cannot install the modules | The workstation cannot reach the PowerShell Gallery, or a policy prevents the installation | Install each module listed under [PowerShell modules](#powershell-modules) with `Install-Module <name> -Scope CurrentUser`. Then run the onboarding script with `-SkipModuleInstall` |
| The sign-in fails | The account or the tenant is wrong, or the workstation holds an old session | Run the onboarding script again. Type `Y` at the question `Sign in to Azure again? (default: N)` |
| "Insufficient permissions" | The account lacks Owner on the subscription or lacks Global Administrator | Obtain the role. Then run the onboarding script again |
| The onboarding script cannot invite a guest | The external collaboration settings of your tenant prevent invitations | Allow guest invitations in Microsoft Entra ID. Alternatively, create the accounts yourself and choose to add existing accounts |
| A role assignment reports "BadRequest" | Microsoft Entra ID has not yet copied a new service principal or managed identity to every server | No action. The onboarding script tries again |
| The onboarding script reports that a resource already exists | An earlier run created the resource | No action. The onboarding script uses the existing resource |
| The run stopped before the end | An error occurred, somebody closed the window, or the connection failed | Run the onboarding script again. Type `Y` at the question `Resume from this checkpoint? (Y/N, default: Y)`. The onboarding script restores your answers. Each step uses the resources that the earlier run created |
| "Resource providers still registering" | Azure has not completed a registration | Wait a few minutes. When the run stopped, run the onboarding script again and resume. When the completion summary lists the resource provider, run `Register-NeologikResourceProviders.ps1` |
| "Resource provider list not found" | `resource-providers.txt` is not in the folder of the onboarding script | Copy `resource-providers.txt` from the onboarding kit to the folder of the onboarding script |

## Help

Email support@neologik.ai and attach the log of the run.
