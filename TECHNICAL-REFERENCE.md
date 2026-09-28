# Install-NeologikEnvironment.ps1: Technical Reference

## Overview

This document describes the onboarding script in detail: what it requires, the parameters and answer file it accepts, the names it gives to what it creates, what it creates, and the files it writes. It is for the administrator who runs the script and wants more than the step-by-step instructions in [README.md](README.md).

The security description of the script, with every change it makes and every permission it grants, is [QUICK-REFERENCE.md](QUICK-REFERENCE.md).

| Item | Value |
|---|---|
| Script version | v5.0.1 |
| Kit version | v5.0.3 |

The kit and each script carry their own version. The kit version follows the Neologik Platform version the kit is issued for; a script version changes when that script changes.

## Contents

1. [Requirements](#requirements)
2. [Parameters](#parameters)
3. [Answer file](#answer-file)
4. [Unattended runs](#unattended-runs)
5. [Examples](#examples)
6. [Naming](#naming)
7. [Input validation](#input-validation)
8. [What the script creates](#what-the-script-creates)
9. [Resource provider registration](#resource-provider-registration)
10. [Output files](#output-files)
11. [The TLS certificate](#the-tls-certificate)
12. [Troubleshooting](#troubleshooting)
13. [Help](#help)

## Requirements

| Requirement | Detail |
|---|---|
| Azure role | Owner on the subscription. Contributor is not sufficient, because the script assigns Azure roles |
| Microsoft Entra role | Global Administrator, to create the application registrations and the agent identity blueprint, grant the Microsoft Graph application permissions, assign the groups to the Platform Sign-in application and add the SQL managed identity to the Directory Readers role |
| Workstation | Windows 10 or Windows 11 |
| PowerShell | 7.4 or later. The script offers to update an older version |
| PowerShell modules | Installed for the current user if missing, with your agreement: `Az.Accounts` 5.2.0, `Az.Resources` 7.0.0, `Az.Compute` 7.0.0, `Az.KeyVault` 5.0.0, `Az.Storage` 6.0.0, `Az.ManagedServiceIdentity` 1.0.0 and `Microsoft.Graph` 2.0.0, or later versions |
| Network | Access to Azure, Microsoft Graph and the PowerShell Gallery |
| Files | `NeologikGuestUsers.txt` and `resource-providers.txt`, beside the script |

## Parameters

Every parameter is optional. A value that is not given is asked for at a prompt or taken from the answer file.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-OrganizationCode` | String | Asked | The three-character organisation code |
| `-EnvironmentType` | String | `dev` | `dev` or `prd` |
| `-AzureRegion` | String | `uksouth` | The Azure region for the resources |
| `-TenantId` | String | The tenant of the sign-in | The tenant to sign in to |
| `-SubscriptionName` | String | The subscription of the sign-in | The name of the subscription to use. The script selects it after sign-in and stops if the account cannot see it. On a resumed run the subscription held in the checkpoint is used |
| `-KeyVaultName` | String | `kv<short name>` | A Key Vault name of your own |
| `-ExistingServicePrincipalObjectId` | String | None | The enterprise application object ID of a deployment service principal you created. The script assigns the Azure roles and the Microsoft Graph application permissions to it and creates none of its own |
| `-ExistingServicePrincipalSecret` | String | None | The client secret of that service principal, to be stored in the Key Vault. If omitted, add the secret to the Key Vault yourself before the first deployment |
| `-AnswerFile` | String | `inputs.json` beside the script | The path of the answer file |
| `-SkipGuestInvitation` | Switch | Off | Invites no guest. The security groups are still created, with the signed-in user as their member |
| `-SkipPowerShellUpdate` | Switch | Off | Omits the PowerShell version check |
| `-SkipModuleInstall` | Switch | Off | Omits the module check |
| `-NonInteractive` | Switch | Off | Runs unattended. See [Unattended runs](#unattended-runs) |
| `-AcceptTerms` | Switch | Off | Accepts the Terms of Use and Privacy Policy. Required with `-NonInteractive` |
| `-FreshRun` | Switch | Off | Discards the checkpoint of an earlier run without asking |

## Answer file

Every answer can be prepared in advance. Copy `inputs-example.json` to `inputs.json` beside the script, or name another file with `-AnswerFile`, and complete it. Each value then appears as the default of its question: press Enter to accept it, or type another value.

When the file supplies the organisation code, the organisation name and the host name, the script goes straight to the configuration summary. Type `N` at the summary to review the questions one by one.

| Key | Value |
|---|---|
| `organizationCode` | The three-character organisation code. Required for a complete file |
| `organizationName` | The organisation's full name. Required for a complete file |
| `fqdn` | The environment's fully qualified host name. Required for a complete file |
| `environmentType` | `dev` or `prd` |
| `azureRegion` | The Azure region |
| `environmentIndex` | `01` to `99` |
| `budgetCostReportEmailRecipients` | A list of addresses for the daily cost report, or `none` to disable the report |
| `applyResourceTags` | `true` or `false` |
| `resourceTagsCustom` | Additional tags, as an object or as a string of `key=value` pairs |
| `solutionName`, `solutionShortName` | The two naming tokens. See [Naming](#naming) |
| `resourceGroupName`, `keyVaultName`, `storageAccountName`, `scriptRunnerIdentityName`, `sqlIdentityName` | Names of your own for the resources |
| `skipGuestInvitation` | `true` to invite no guest |
| `addExistingAccountsToGroups` | `true` to add existing accounts to the security groups. Read only when `skipGuestInvitation` is `true` |
| `existingAccountEmails` | The addresses of those accounts. When omitted, the addresses in `NeologikGuestUsers.txt` are used |
| `useExistingServicePrincipal` | `true` to reuse a deployment service principal you created |
| `existingServicePrincipalObjectId` | Its enterprise application object ID |
| `existingServicePrincipalSecret` | Its client secret. The command-line parameter is preferable, because it keeps the secret out of the file |

Acceptance of the terms, module installation and sign-in are always asked at the prompt and are never read from the file.

## Unattended runs

`-NonInteractive` runs the script without prompts, for automation.

| Condition | Detail |
|---|---|
| Answer file | Must supply `organizationCode`, `organizationName` and `fqdn`. The script checks this before it does anything else |
| Terms | Accepted with `-AcceptTerms`. The acceptance is logged |
| Sign-in | The caller signs in to Azure and to Microsoft Graph before it starts the script. The script reuses both sessions. Access tokens last about an hour and cannot be renewed during the run |
| Checkpoint | A checkpoint left by an earlier run is an error unless `-FreshRun` is given |
| Switches | Give `-SkipPowerShellUpdate` and `-SkipModuleInstall`, and state the service principal decision in the answer file, so that no prompt can arise |
| Checks | A check that would ask a question in an interactive run stops the script instead |
| Upload | The upload of the configuration file and the log is attempted once |

```powershell
Connect-AzAccount -AccessToken $armToken -AccountId $accountName -TenantId $tenantId -SubscriptionId $subscriptionId
Connect-MgGraph -AccessToken (ConvertTo-SecureString $graphToken -AsPlainText -Force)

.\Install-NeologikEnvironment.ps1 -NonInteractive -AcceptTerms -FreshRun `
    -AnswerFile .\inputs.json -SkipPowerShellUpdate -SkipModuleInstall
```

Run the three commands in the same PowerShell session, so that the script finds both sign-ins.

The account signed in must hold Owner on the subscription and Global Administrator, as for an interactive run.

## Examples

Interactive run, the usual form:

```powershell
.\Install-NeologikEnvironment.ps1
```

Production environment in UK West:

```powershell
.\Install-NeologikEnvironment.ps1 -OrganizationCode "abc" -EnvironmentType "prd" -AzureRegion "ukwest"
```

A deployment service principal you created yourself (see [CREATE-SP-GUIDE.md](CREATE-SP-GUIDE.md)):

```powershell
.\Install-NeologikEnvironment.ps1 `
    -ExistingServicePrincipalObjectId "00000000-0000-0000-0000-000000000000" `
    -ExistingServicePrincipalSecret $env:SP_CLIENT_SECRET
```

A Key Vault name of your own:

```powershell
.\Install-NeologikEnvironment.ps1 -KeyVaultName "kv-abc-neologik"
```

## Naming

Two naming tokens determine every standard name. The examples are for organisation code `abc`, environment type `prd`, region UK South and index `01`.

| Token | Pattern | Example |
|---|---|---|
| Solution name | `neo-<org><env>-<region>-<index>` | `neo-abcprd-uks-01` |
| Short name | `<org><env><index>` | `abcprd01` |

`<region>` is the short form of the region, which the script shows on screen when the region is chosen.

| Object | Standard name | Example |
|---|---|---|
| Resource group | `rg-<solution name>` | `rg-neo-abcprd-uks-01` |
| Key Vault | `kv<short name>` | `kvabcprd01` |
| Deployment storage account | `stneodeploy<org><env><region><index>`, shortened to 24 characters | `stneodeployabcprduks01` |
| Script runner managed identity | `neologik-script-runner-service-connection-<short name>` | `neologik-script-runner-service-connection-abcprd01` |
| SQL managed identity | `neologik-sql-managed-identity-<short name>` | `neologik-sql-managed-identity-abcprd01` |
| Security groups | `Neologik User Group - <short name>`, `Neologik NCE Contributors - <short name>`, `Neologik NCE Admins - <short name>`, `Neologik Admin User Group - <short name>` | `Neologik User Group - abcprd01` |
| Deployment identity | `Neologik GitHub Service Connection - <short name>` | `Neologik GitHub Service Connection - abcprd01` |
| Platform Sign-in application | `Neologik Platform Sign-in - <short name>` | `Neologik Platform Sign-in - abcprd01` |

### Your own naming convention

The five resource names are offered as defaults at the prompts and can be replaced there or in the answer file. The two tokens can be replaced in the answer file only; the short name also forms the suffix of the group, application and identity names.

Tell Neologik about your convention as well, so that the deployment applies it to the resources it creates inside the resource group.

## Input validation

The script repeats a question until the value is valid.

| Value | Rule |
|---|---|
| Organisation code | Exactly three letters or digits; converted to lower case |
| Organisation name | Required |
| Host name | A fully qualified host name. A scheme and a path are removed; converted to lower case |
| Environment type | `dev` or `prd`. The script also accepts `dmo`, `test` and `stg`, which are reserved for environments operated by Neologik |
| Azure region | A region available to the subscription |
| Environment index | 01 to 99 |
| Resource group name | 1 to 90 characters; letters, digits, underscores, hyphens, full stops and parentheses; no full stop at the end |
| Key Vault name | 3 to 24 characters; letters, digits and hyphens; begins with a letter; ends with a letter or digit; no two hyphens together |
| Storage account name | 3 to 24 characters; lower-case letters and digits |
| Managed identity names | 3 to 128 characters; letters, digits, hyphens and underscores; begins with a letter or digit |
| Email addresses | A valid address form |
| Custom tags | Keys of letters, digits, full stops, underscores and hyphens; values without commas or equals signs |

The two naming tokens in the answer file are converted to lower case and are not otherwise checked. Make sure they suit every name they form.

## What the script creates

### Resource group

The resource group is created in the chosen region. When tagging is chosen, it and every other resource the script creates carry the tags Vendor, ApplicationName, ManagedBy, Environment, Solution and DeploymentDate, together with any tags of your own.

The resource group also carries the tag `NeologikOnboardingKit`, which records the version of the kit, `v5.0.3`. The platform reads it before an upgrade.

### Guest users

When invitation is chosen, the script invites each address in `NeologikGuestUsers.txt`, and each address you add at the prompt, for which no account exists in the tenant. An account that already exists, as a guest or as a member, is used as it is.

| Format of `NeologikGuestUsers.txt` |
|---|
| One address on each line |
| Blank lines are ignored |
| A line that begins with `#` is a comment |

When invitation is declined, the script offers to add existing accounts to the security groups instead, with no invitation sent. Each address must match the account's mail address or user principal name exactly. An address with no matching account is reported and passed over.

Every account invited or added joins all four security groups, including the Admin User Group. List only the accounts that should hold Neologik administration and support access.

### Security groups

| Group | Purpose |
|---|---|
| `Neologik User Group - <short name>` | The default access group for agents. Its members can use the agents it is attached to |
| `Neologik NCE Contributors - <short name>` | Its members configure agents and Apps in the Neologik Context Engine (NCE) |
| `Neologik NCE Admins - <short name>` | Its members administer the NCE, including the installation of use cases |
| `Neologik Admin User Group - <short name>` | Its members administer the Azure resources in the resource group |

The signed-in user, and every account invited or added, is made a member of each group. The NCE Contributors group and the NCE Admins group are assigned to the Platform Sign-in application, so that their members' sign-ins carry the groups claim from which the NCE authorises. The platform does not create groups.

### Deployment identity

The script creates the application `Neologik GitHub Service Connection - <short name>` with its service principal and a client secret valid for 365 days, or reuses the service principal you name. The secret is stored in the Key Vault as `neologik-deployment-service-principle-secret`.

| Scope | Roles |
|---|---|
| Subscription | Reader, Cost Management Contributor |
| Resource group | Contributor, Key Vault Certificates Officer, Key Vault Secrets Officer, Storage Blob Data Contributor, Azure Kubernetes Service RBAC Cluster Admin, Monitoring Contributor, Role Based Access Control Administrator |
| Microsoft Graph application permissions | `Application.ReadWrite.OwnedBy`, which lets the identity manage only the application registrations it owns, and `AgentIdentityBlueprint.AddRemoveCreds.All`, which lets it add and remove credentials on the agent identity blueprint |
| Group membership | None |

### Key Vault

The Key Vault is created with Azure role-based access control. The Admin User Group receives Key Vault Secrets Officer and Key Vault Certificates Officer on the resource group.

### Platform Sign-in application

The script creates the application `Neologik Platform Sign-in - <short name>`, through which users sign in to the NCE and to Apps. It makes the deployment identity an owner of the application and of its service principal, and assigns the NCE Contributors group and the NCE Admins group to it.

| Property | Value |
|---|---|
| Sign-in audience | Multi-tenant |
| Redirect address | `https://<host>/nce` |
| Group claims | Groups assigned to the application |
| Client secret | Created when the Key Vault holds none; valid for 365 days; stored in the Key Vault as `sp-admin-<solution name>-auth-secret` |

The script declares no permission on the application and gives no consent. Your Global Administrator gives the consent after deployment, as described in [FINISHING-STEPS-GUIDE.md](FINISHING-STEPS-GUIDE.md). The platform deployment maintains the registration thereafter.

### Agent identity blueprint

The script creates the agent identity blueprint of the environment, `Neologik Agent Blueprint - default - <short name>`, and its principal, under the Global Administrator's sign-in. The platform creates the agent identities and agent user accounts of the environment under it.

| Item | Value |
|---|---|
| Sponsor | The signed-in administrator. The sponsor can be changed in the Microsoft Entra admin centre |
| Owner | The deployment identity, of the blueprint and of its principal |
| Microsoft Graph application permission of the principal | `AgentIdUser.ReadWrite.IdentityParentedBy`, which is limited to the agent users of this blueprint |
| Federated credentials | Three, named `github-oidc-neo-infrastructure`, `github-oidc-neo-bot-service` and `github-oidc-neo-env-config`. Each trusts one repository of the Neologik deployment, named by its repository id, and is issued by `https://token.actions.githubusercontent.com`. No secret is stored |

### Storage account

| Property | Value |
|---|---|
| Authentication | Microsoft Entra ID only. Shared key access is disabled |
| Public blob access | Disabled |
| Containers | `certificate`, `json` and `logs` |
| Role | The Admin User Group receives Storage Blob Data Contributor on the resource group |

### Managed identities

| Identity | Roles |
|---|---|
| `neologik-script-runner-service-connection-<short name>`, which the deployment uses to run its scripts within Azure | Reader, Key Vault Secrets Officer and Azure Bot Service Contributor Role on the resource group. No role on the subscription |
| `neologik-sql-managed-identity-<short name>` | Directory Readers in Microsoft Entra ID, which Azure SQL requires in order to resolve Microsoft Entra sign-ins |

### Roles of the Admin User Group

The Admin User Group holds thirteen roles on the resource group and none on the subscription: Contributor, Azure Kubernetes Service Cluster Admin Role, Azure Kubernetes Service RBAC Cluster Admin, Key Vault Administrator, Key Vault Secrets Officer, Key Vault Certificates Officer, Storage Blob Data Owner, Storage Blob Data Contributor, Storage Table Data Contributor, Cognitive Services Data Reader, Cognitive Services OpenAI Contributor, Search Index Data Reader and Azure AI Developer.

## Resource provider registration

The platform requires the Azure resource providers and preview features listed in `resource-providers.txt`. The deployment identity cannot register a provider, so the registrations are made at onboarding, under your sign-in.

Registration takes Azure some minutes. The script submits every registration as soon as the permissions have been checked and carries on. It confirms the provider of each resource before it creates that resource, and confirms the whole list before it writes the configuration file.

A registration that is still in progress when the script ends is listed in the completion summary and in the configuration file, as `ResourceProvidersPending`. Confirm it before the deployment:

```powershell
.\Register-NeologikResourceProviders.ps1
```

| Parameter | Purpose |
|---|---|
| `-SubscriptionId` | The subscription, when it is not the one of the current Azure session |
| `-TenantId` | The tenant to sign in to, when no Azure session exists |
| `-TimeoutSeconds` | How long to wait for the registrations. The default is 900 |
| `-ListOnly` | Prints the list and makes no contact with Azure |

The script needs Contributor or Owner on the subscription. It exits with code 1 if a registration is still in progress at the end of the wait; Azure completes the registration in the background, and a later run confirms it.

## Output files

| File | Content |
|---|---|
| `Neologik_<org><index>_Configuration_<timestamp>.json` | The configuration Neologik needs for the deployment |
| `NeologikOnboarding_<timestamp>.log` | The log of the run |

Both files are written beside the script and uploaded to the `json` and `logs` containers of the storage account. If the upload of the configuration file fails, the completion summary says so; send the file to Neologik by email.

The configuration file holds:

| Section | Content |
|---|---|
| Environment | The tenant, subscription, resource group, region, organisation, host name and the two naming tokens |
| `SecurityGroups` | The names and ids of the four groups |
| `AppRegistration` | The deployment identity: its name, client id, roles, and whether the script created it |
| `NceAuthApp` | The Platform Sign-in application: its name and client id |
| `AgentBlueprint` | The agent identity blueprint: its name, ids and credentials |
| `KeyVault`, `StorageAccount`, `ManagedIdentities` | The names and ids of the resources |
| Accounts | The operator's sign-in name, the addresses of the accounts invited or added, and the cost report recipients |
| `ResourceProvidersPending` | The registrations still in progress, if any |

Neither file contains a secret. Both contain sign-in names and email addresses.

## The TLS certificate

Provide the certificate for the environment's host name in one of two ways. [PFX-CERT-GUIDE.md](PFX-CERT-GUIDE.md) explains how to prepare the file.

| Method | Steps |
|---|---|
| Import into the Key Vault. Recommended | In the Azure portal, open the Key Vault, select **Certificates**, then **Generate/Import**. Choose **Import**, name the certificate `keyvault-neo-ingress`, select the `.pfx` file and enter its password. The password is used at import only |
| Upload to the storage account | Upload the `.pfx` file, or the private key, server certificate and certificate authority bundle, to the `certificate` container, signing in with Microsoft Entra ID. If you upload a `.pfx` file, store its password in the Key Vault as a secret named `neologik-deployment-certificate-pfx-secret`. Tell Neologik which you have uploaded |

The certificate must contain the server certificate, the intermediate certificates and the private key.

## Troubleshooting

| Symptom | Cause | Action |
|---|---|---|
| The script reports the PowerShell version | PowerShell is older than 7.4, or Windows PowerShell was opened | Install PowerShell 7 from https://aka.ms/powershell and open PowerShell 7 |
| The modules cannot be installed | The PowerShell Gallery cannot be reached, or policy prevents installation | Install the modules listed under [Requirements](#requirements) with `Install-Module <name> -Scope CurrentUser`, then run the script with `-SkipModuleInstall` |
| The sign-in fails | The wrong account or tenant, or a cached session | Run the script again and type `Y` when asked whether to sign in again |
| "Insufficient permissions" | The account lacks Owner on the subscription or Global Administrator | Obtain the role, then run the script again |
| A guest cannot be invited | External collaboration settings prevent invitations | Allow guest invitations in Microsoft Entra ID, or create the accounts yourself and choose to add existing accounts |
| A role assignment reports "BadRequest" | A newly created principal has not yet replicated | None. The script retries |
| The script reports that a resource already exists | An earlier run created it | None. The script reuses what exists |
| The run stopped part way | An error, a closed window or a lost connection | Run the script again and accept the offer to resume. Your answers are restored and each step reuses what it has already created |
| "Resource providers still registering" | Azure has not completed a registration | Wait a few minutes. If the run stopped, run it again and resume. If the registration is listed in the completion summary, run `Register-NeologikResourceProviders.ps1` |
| "Resource provider list not found" | `resource-providers.txt` is not beside the script | Restore the file from the kit |

## Help

Email support@neologik.ai and attach the log of the run.
