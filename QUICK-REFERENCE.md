# Neologik Onboarding - Quick Reference

## Overview
This script creates resources and assigns permissions for Neologik deployment in a customer's Azure tenant.

**Run:** `.\Install-NeologikEnvironment.ps1` in PowerShell 7 as Administrator

---

## Prerequisites

### Required Permissions to Run Script

**User must have:**
- **Owner** role at subscription level
- **Global Administrator** role in Entra ID

**Reason:** Script assigns Azure RBAC roles (requires Owner) and Microsoft Graph app-role assignments plus enterprise-application group assignments (require Global Administrator)

---

### vCPU Quota

Neologik requires sufficient vCPU quota in the target subscription and region before deployment can proceed. Check and request increases **before** running the onboarding script.

#### Checking current quota

1. Azure Portal → **Subscriptions** → select your subscription → **Usage + quotas**
2. Filter by your target region and search for **`Standard D2ds v6`** or **`Standard DC2ds v6`** to see current usage vs. limit

#### Requesting an increase

Azure Portal → **Usage + quotas** → select the quota line → **New Quota Request**

---

### Azure OpenAI Quota

Neologik requires sufficient Azure OpenAI token quota in the target region before deployment can proceed. Check and request increases **before** running the onboarding script.

#### Checking current quota

1. Sign in to [Azure AI Foundry](https://ai.azure.com)
2. Navigate to **Operate** → **Quota** in the left pane
3. Find **gpt-5.4-mini** in the list and confirm you have sufficient tokens-per-minute (TPM) available in your target region

#### Requesting an increase

Use the [Azure OpenAI quota request form](https://aka.ms/oai/stuquotarequest). Requests typically take up to 10 business days to approve.

---

## Variables Used

- `{org}` = Organization code (3 characters, lowercase)
- `{region}` = Azure region abbreviation (e.g., `uks`, `eus`, lowercase)
- `{index}` = Environment index (e.g., `01`, `02`)
- `{short}` = Solution short name: `neo{org}{index}` (e.g., `neoabc01`)

The environment type (`dev`/`prd`) is collected for classification but never appears in resource names. Every computed name below can be overridden from the answer file (`inputs.json`) to match a client-mandated naming convention.

**Example:** Organization "ABC", UK South, index 01
- Resource Group: `rg-neo-neoabc-uks-01`
- Key Vault: `kvneoabc01`
- Storage Account: `stneodeployneoabcuks01`
- Default User Group: `Neologik User Group - neoabc01`

---

## Changes Applied by Script

### 1. Guest User Invitations (Entra ID) - optional

**Action:** Invite Neologik users as B2B guests (if no account with that email already exists)

**Source:** Email addresses loaded from `NeologikGuestUsers.txt` file

**Notes:**
- Accounts you have pre-created (B2B guests or full member accounts whose mail or UPN matches a listed address) are detected and used as-is - no duplicate invitation
- Interactive runs list the file's addresses and offer to **add more to invite**, typed one per line (blank line finishes, commas accepted within a line); with an empty or missing file the whole invite list can be typed in
- Skip invitations entirely with `-SkipGuestInvitation` (or `skipGuestInvitation` in `inputs.json`) when you provision accounts in your own tenant; groups are then seeded with the signed-in user only
- Declining invitations offers a follow-up: **add existing pre-created accounts to the security groups** with no invitation sent - addresses from `NeologikGuestUsers.txt`, typed interactively, or `existingAccountEmails` in `inputs.json` (with `addExistingAccountsToGroups: true`). Addresses with no matching account are reported and skipped; the run continues
- All accounts processed by this step (invited or pre-existing) join **all four groups**, including the Admin User Group and its Azure RBAC - Neologik admin/support accounts only

---

### 2. Security Groups (Entra ID)

**Action:** Create four security groups

| Group Name | Purpose | Members |
|------------|---------|---------|
| `Neologik User Group - {short}` | Default users group - assigned to agent channels created post-deployment in the Neologik admin tool (NCE). The platform never creates groups; channels reuse this group or another existing group you supply | Current user + Neologik users |
| `Neologik NCE Contributors - {short}` | NCE contributor role (create and change platform configuration). Renamed in place from the pre-v5 `Neologik NCE User Group` where one exists | Current user + Neologik users |
| `Neologik NCE Admins - {short}` | NCE admin role (Blueprints, Audit, Admin page) | Current user + Neologik users |
| `Neologik Admin User Group - {short}` | Azure resource administration | Current user + Neologik users |

**Note:** No per-bot groups are created - agents and their channels are created after deployment in the NCE.

**Scope:** Entra ID tenant level

---

### 3. Resource Group

**Action:** Create resource group

| Name | Location |
|------|----------|
| `rg-neo-neo{org}-{region}-{index}` | Customer specified (e.g., uksouth) |

**Scope:** Subscription

---

### 4. Role Assignments - Security Groups

**Action:** Assign roles to Neologik Admin User Group (all at **resource group** scope; no subscription-scoped roles)

| Role | Scope | Principal |
|------|-------|-----------|
| **Contributor** | Resource Group | Neologik Admin User Group |
| **Azure Kubernetes Service Cluster Admin Role** | Resource Group | Neologik Admin User Group |
| **Azure Kubernetes Service RBAC Cluster Admin** | Resource Group | Neologik Admin User Group |
| **Key Vault Administrator** | Resource Group | Neologik Admin User Group |
| **Storage Blob Data Owner** | Resource Group | Neologik Admin User Group |
| **Storage Table Data Contributor** | Resource Group | Neologik Admin User Group |
| **Cognitive Services Data Reader** | Resource Group | Neologik Admin User Group |
| **Cognitive Services OpenAI Contributor** | Resource Group | Neologik Admin User Group |
| **Search Index Data Reader** | Resource Group | Neologik Admin User Group |
| **Azure AI Developer** | Resource Group | Neologik Admin User Group |

---

### 5. App Registration & Service Principal (Entra ID)

**Action:** Create app registration for GitHub deployments - or reuse a service principal you have already created (`-ExistingServicePrincipalObjectId` / `useExistingServicePrincipal` in `inputs.json`; roles below are assigned either way; creation steps in [CREATE-SP-GUIDE.md](CREATE-SP-GUIDE.md))

| Property | Value |
|----------|-------|
| **Name** | `Neologik GitHub Service Connection - {short}` |
| **Type** | Multi-tenant (AzureADMultipleOrgs) |
| **Client Secret** | Created (365-day expiration); with a client-provided SP the secret is optional and client-managed |
| **Secret Storage** | Stored in Key Vault (`neologik-deployment-service-principle-secret`) |

### Group Membership
- Added to: `Neologik Admin User Group - {short}`

---

### 6. Role Assignments - Service Principal

**Action:** Assign roles to the deployment service principal

| Role | Scope | Principal |
|------|-------|-----------|
| **Reader** | Subscription | Service Principal |
| **Cost Management Contributor** | Subscription | Service Principal |
| **Contributor** | Resource Group | Service Principal |
| **Key Vault Certificates Officer** | Resource Group | Service Principal |
| **Key Vault Secrets Officer** | Resource Group | Service Principal |
| **Storage Blob Data Contributor** | Resource Group | Service Principal |
| **Azure Kubernetes Service RBAC Cluster Admin** | Resource Group | Service Principal |
| **Monitoring Contributor** | Resource Group | Service Principal |
| **Role Based Access Control Administrator** | Resource Group | Service Principal |
| **Application.Read.All** | Microsoft Graph (app role) | Service Principal |
| **Application.ReadWrite.OwnedBy** | Microsoft Graph (app role) | Service Principal |
| **AgentIdentityBlueprint.Create** | Microsoft Graph (app role) | Service Principal |
| **AgentIdentityBlueprint.AddRemoveCreds.All** | Microsoft Graph (app role) | Service Principal |
| **AgentIdentityBlueprint.UpdateAuthProperties.All** | Microsoft Graph (app role) | Service Principal |
| **AgentIdentityBlueprintPrincipal.Create** | Microsoft Graph (app role) | Service Principal |
| **AgentIdentity.Create.All** | Microsoft Graph (app role) | Service Principal |
| **AgentIdUser.ReadWrite.All** | Microsoft Graph (app role) | Service Principal |

> The subscription-scoped roles are read-only (**Reader**, for SKU/quota pre-flight checks) and cost-configuration-only (**Cost Management Contributor**, for the scheduled cost-report emails) - all resource writes are resource-group-scoped. The six **AgentIdentity\*/AgentIdUser** roles let the deployment service principal provision **Microsoft Entra Agent ID** blueprints, principals, and agent users for autonomous agents - scoped to agent-id only, rather than granting the broad "Agent ID Administrator" directory role. No group-management permission is granted: the platform never creates Entra groups.

---

### 7. Platform Sign-in App Registration (Entra ID)

**Action:** Create the sign-in app used by the Neologik admin tool (NCE) and App portal login

| Property | Value |
|----------|-------|
| **Name** | `Neologik Platform Sign-in - {short}` |
| **Type** | Multi-tenant (AzureADMultipleOrgs), web redirect URI on your hostname |
| **Client Secret** | Created (365-day expiration), stored in Key Vault |
| **Owner** | Deployment service principal (so the pipeline can manage/rotate it) |
| **Group Assignments** | `Neologik NCE Contributors - {short}` and `Neologik NCE Admins - {short}` assigned to the enterprise application, so members' tokens carry the groups claim NCE authorizes from |

---

### 8. Key Vault

**Action:** Create Key Vault with RBAC authorization

| Property | Value |
|----------|-------|
| **Name** | `kvneo{org}{index}` (override with `-KeyVaultName` or `keyVaultName` in `inputs.json`) |
| **Authorization** | Microsoft Entra ID RBAC (no access policies) |
| **Public Access** | Enabled |
| **Soft Delete** | Enabled (Azure default) |

### Secrets Stored
| Secret Name | Content |
|-------------|---------|
| `neologik-deployment-service-principle-secret` | Deployment service principal client secret |
| `sp-admin-{solution-name}-auth-secret` | Platform Sign-in app client secret |

### Role Assignments
| Role | Scope | Principal |
|------|-------|-----------|
| **Key Vault Secrets Officer** | Resource Group | Neologik Admin User Group |

**Note:** Allows group members to read/write secrets in Key Vault

---

### 9. Storage Account

**Action:** Create storage account for the certificate and configuration handoff

| Property | Value |
|----------|-------|
| **Name** | `stneodeployneo{org}{region}{index}` (truncated to 24 characters; override with `storageAccountName` in `inputs.json`) |
| **Authentication** | Microsoft Entra ID only |
| **Shared Key Access** | Disabled |
| **Public Access** | Enabled |
| **Blob Containers** | `certificate` (TLS certificate), `json` (configuration JSON handoff), `logs` |

### Role Assignments
| Role | Scope | Principal |
|------|-------|-----------|
| **Storage Blob Data Contributor** | Resource Group | Neologik Admin User Group |

**Note:** Allows group members to upload/manage certificates

---

### 10. Managed Identities (User-Assigned)

**Action:** Create 2 managed identities

### Identity 1: Script Runner Service Connection
| Property | Value |
|----------|-------|
| **Name** | `neologik-script-runner-service-connection-{short}` (override with `scriptRunnerIdentityName`) |
| **Display Name** | `Neologik Script Runner Service Connection - {short}` |

**Role Assignments:**
| Role | Scope |
|------|-------|
| **Contributor** | Subscription |
| **Key Vault Secrets Officer** | Resource Group |
| **Azure Bot Service Contributor Role** | Resource Group |

### Identity 2: SQL Managed Identity
| Property | Value |
|----------|-------|
| **Name** | `neologik-sql-managed-identity-{short}` (override with `sqlIdentityName`) |
| **Display Name** | `Neologik SQL Managed Identity - {short}` |

**Role Assignments:**
| Role | Scope |
|------|-------|
| **Directory Readers** | Entra ID (Directory Role) |

---

## Summary of Permissions by Scope

### Subscription Level
| Principal | Role |
|-----------|------|
| Service Principal (GitHub) | Reader |
| Service Principal (GitHub) | Cost Management Contributor |
| Managed Identity (Script Runner) | Contributor |

### Resource Group Level
| Principal | Role |
|-----------|------|
| Service Principal (GitHub) | Contributor |
| Service Principal (GitHub) | Key Vault Certificates Officer |
| Service Principal (GitHub) | Key Vault Secrets Officer |
| Service Principal (GitHub) | Storage Blob Data Contributor |
| Service Principal (GitHub) | Azure Kubernetes Service RBAC Cluster Admin |
| Service Principal (GitHub) | Monitoring Contributor |
| Service Principal (GitHub) | Role Based Access Control Administrator |
| Managed Identity (Script Runner) | Key Vault Secrets Officer |
| Managed Identity (Script Runner) | Azure Bot Service Contributor Role |
| Neologik Admin User Group | Contributor + the administration role set in section 4 |

### Microsoft Graph (App Roles)
| Principal | Role |
|-----------|------|
| Service Principal (GitHub) | Application.Read.All |
| Service Principal (GitHub) | Application.ReadWrite.OwnedBy |
| Service Principal (GitHub) | AgentIdentityBlueprint.Create |
| Service Principal (GitHub) | AgentIdentityBlueprint.AddRemoveCreds.All |
| Service Principal (GitHub) | AgentIdentityBlueprint.UpdateAuthProperties.All |
| Service Principal (GitHub) | AgentIdentityBlueprintPrincipal.Create |
| Service Principal (GitHub) | AgentIdentity.Create.All |
| Service Principal (GitHub) | AgentIdUser.ReadWrite.All |

### Entra ID (Directory Roles)
| Principal | Role |
|-----------|------|
| Managed Identity (SQL) | Directory Readers |
