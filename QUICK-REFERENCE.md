# Neologik Onboarding - Quick Reference

## Overview
This script creates resources and assigns permissions for Neologik deployment in a customer's Azure tenant.

**Run:** `.\Install-NeologikEnvironment.ps1` in PowerShell 7 as Administrator

---

## Prerequisites

### Required Permissions to Run Script

**User must have:**
- ✅ **Owner** role at subscription level
- ✅ **Global Administrator** role in Entra ID

**Reason:** Script assigns Azure RBAC roles (requires Owner) and Entra ID directory roles (requires Global Administrator)

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
- `{env}` = Environment type (`dev` or `prd`, lowercase)
- `{region}` = Azure region abbreviation (e.g., `uks`, `eus`, lowercase)
- `{index}` = Environment index (e.g., `01`, `02`)
- `{agent-name}` = Full bot name (letters, numbers, spaces, dashes and underscores; no length limit). Each bot also has a short name (lowercase, 1–4 characters, must start with a letter, letters/numbers/dashes only)

**Example:** Organization "ABC", dev environment, UK South, index 01, bot agent name "support"
- Resource Group: `rg-neo-abc-dev-uks-01`
- Key Vault: `kvneoabcdev01`
- Storage Account: `stneodeployabcdevuks01`
- User Group: `Neologik User Group support - abc-dev`

---

## Changes Applied by Script

### 1. Guest User Invitations (Entra ID)

**Action:** Invite Neologik users as B2B guests (if not already invited)

**Source:** Email addresses loaded from `NeologikGuestUsers.txt` file

**Note:** Guest users will only be invited if they don't already exist in the tenant

---

### 2. Security Groups (Entra ID)

**Action:** Create security groups (3+ groups depending on bot count)

**Bot User Groups** (one per bot):
| Group Name | Members |
|------------|----------|
| `Neologik User Group {agent-name} - {org}-{env}` | Current user + Neologik guests |

**Note:** If you configure 2 bots with agent names "bot" and "support", you'll get:
- `Neologik User Group bot - {org}-{env}`
- `Neologik User Group support - {org}-{env}`

**Standard Groups** (always created):
| Group Name | Members |
|------------|----------|
| `Neologik NCE User Group - {org}-{env}` | Current user + Neologik guests |
| `Neologik Admin User Group - {org}-{env}` | Current user + Neologik guests |

**Scope:** Entra ID tenant level

---

### 3. Resource Group

**Action:** Create resource group

| Name | Location |
|------|----------|
| `rg-neo-{org}-{env}-{region}-{index}` | Customer specified (e.g., uksouth) |

**Scope:** Subscription

---

### 4. Role Assignments - Security Groups

**Action:** Assign roles to Neologik Admin User Group

| Role | Scope | Principal |
|------|-------|-----------|
| **Contributor** | Resource Group | Neologik Admin User Group |

---

### 5. App Registration & Service Principal (Entra ID)

**Action:** Create app registration for GitHub deployments

| Property | Value |
|----------|-------|
| **Name** | `Neologik GitHub Service Connection - {org}-{env}` |
| **Type** | Multi-tenant (AzureADMultipleOrgs) |
| **Client Secret** | Created (365-day expiration) |
| **Secret Storage** | Stored in Key Vault |

### Group Membership
- Added to: `Neologik Admin User Group - {org}-{env}`

---

### 6. Role Assignments - Service Principal

**Action:** Assign roles to service principal

| Role | Scope | Principal |
|------|-------|-----------|
| **Contributor** | Subscription | Service Principal |
| **Cost Management Contributor** | Subscription | Service Principal |
| **Key Vault Certificates Officer** | Resource Group | Service Principal |
| **Key Vault Secrets Officer** | Resource Group | Service Principal |
| **Storage Blob Data Contributor** | Resource Group | Service Principal |
| **Azure Kubernetes Service RBAC Cluster Admin** | Resource Group | Service Principal |
| **Monitoring Contributor** | Resource Group | Service Principal |
| **Role Based Access Control Administrator** | Resource Group | Service Principal |
| **Application.Read.All** | Microsoft Graph (app role) | Service Principal |
| **Application.ReadWrite.OwnedBy** | Microsoft Graph (app role) | Service Principal |

---

### 7. Key Vault

**Action:** Create Key Vault with RBAC authorization

| Property | Value |
|----------|-------|
| **Name** | `kvneo{org}{env}{index}` |
| **Authorization** | Microsoft Entra ID RBAC (no access policies) |
| **Public Access** | Enabled |
| **Soft Delete** | Enabled (Azure default) |

### Secrets Stored
| Secret Name | Content |
|-------------|---------|
| `neologik-deployment-service-principle-secret` | Service Principal client secret |

### Role Assignments
| Role | Scope | Principal |
|------|-------|-----------|
| **Key Vault Secrets Officer** | Resource Group | Neologik Admin User Group |

**Note:** Allows group members to read/write secrets in Key Vault

---

### 8. Storage Account

**Action:** Create storage account for certificate storage

| Property | Value |
|----------|-------|
| **Name** | `stneodeploy{org}{env}{region}{index}` |
| **Authentication** | Microsoft Entra ID only |
| **Shared Key Access** | Disabled |
| **Public Access** | Enabled |
| **Blob Container** | `certificate` |

### Role Assignments
| Role | Scope | Principal |
|------|-------|-----------|
| **Storage Blob Data Contributor** | Resource Group | Neologik Admin User Group |

**Note:** Allows group members to upload/manage certificates

---

### 9. Managed Identities (User-Assigned)

**Action:** Create 2 managed identities

### Identity 1: Script Runner Service Connection
| Property | Value |
|----------|-------|
| **Name** | `neologik-script-runner-service-connection-{org}-{env}` |
| **Display Name** | `Neologik Script Runner Service Connection - {org}-{env}` |

**Role Assignments:**
| Role | Scope |
|------|-------|
| **Contributor** | Subscription |
| **Key Vault Secrets Officer** | Resource Group |
| **Azure Bot Service Contributor Role** | Resource Group |

### Identity 2: SQL Managed Identity
| Property | Value |
|----------|-------|
| **Name** | `neologik-sql-managed-identity-{org}-{env}` |
| **Display Name** | `Neologik SQL Managed Identity - {org}-{env}` |

**Role Assignments:**
| Role | Scope |
|------|-------|
| **Directory Readers** | Entra ID (Directory Role) |

---

## Summary of Permissions by Scope

### Subscription Level
| Principal | Role |
|-----------|------|
| Service Principal (GitHub) | Contributor |
| Service Principal (GitHub) | Cost Management Contributor |
| Managed Identity (Script Runner) | Contributor |

### Resource Group Level
| Principal | Role |
|-----------|------|
| Service Principal (GitHub) | Key Vault Certificates Officer |
| Service Principal (GitHub) | Key Vault Secrets Officer |
| Service Principal (GitHub) | Storage Blob Data Contributor |
| Service Principal (GitHub) | Azure Kubernetes Service RBAC Cluster Admin |
| Service Principal (GitHub) | Monitoring Contributor |
| Service Principal (GitHub) | Role Based Access Control Administrator |
| Managed Identity (Script Runner) | Key Vault Secrets Officer |
| Managed Identity (Script Runner) | Azure Bot Service Contributor Role |
| Neologik Admin User Group | Contributor |
| Neologik Admin User Group | Key Vault Secrets Officer |
| Neologik Admin User Group | Storage Blob Data Contributor |

### Microsoft Graph (App Roles)
| Principal | Role |
|-----------|------|
| Service Principal (GitHub) | Application.Read.All |
| Service Principal (GitHub) | Application.ReadWrite.OwnedBy |

### Entra ID (Directory Roles)
| Principal | Role |
|-----------|------|
| Managed Identity (SQL) | Directory Readers |
