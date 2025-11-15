# Azure Environment Changes - Quick Reference

## Overview
This script creates resources and assigns permissions for Neologik deployment in a customer's Azure tenant.

**Run:** `.\Install-NeologikEnvironment.ps1` in PowerShell 7 as Administrator

---

## Required Permissions to Run Script

**User must have:**
- ✅ **Owner** role at subscription level
- ✅ **Global Administrator** role in Entra ID

**Reason:** Script assigns Azure RBAC roles (requires Owner) and Entra ID directory roles (requires Global Administrator)

---

## Variables Used

- `{org}` = Organization code (3 characters, lowercase)
- `{env}` = Environment type (`dev` or `prd`)
- `{region}` = Azure region abbreviation (e.g., `uks`, `eus`)
- `{index}` = Environment index (e.g., `01`, `02`)

**Example:** Organization "ABC", dev environment, UK South, index 01
- Resource Group: `rg-neo-abc-dev-uks-01`
- Key Vault: `kvneodeployabcdevuks01`
- Storage Account: `stneodeployabcdevuks01`

---

## Changes Applied by Script

## 1. Guest User Invitations (Entra ID)

**Action:** Invite 5 Neologik users as B2B guests (if not already invited)

| Email | Role |
|-------|------|
| bryan.lloyd@neologik.ai | Guest |
| rupert.fawcett@neologik.ai | Guest |
| Jashanpreet.Magar@neologik.ai | Guest |
| leon.simpson@neologik.ai | Guest |
| gael.abruzzese@neologik.ai | Guest |

---

## 2. Security Groups (Entra ID)

**Action:** Create 3 security groups

| Group Name | Members |
|------------|---------|
| `Neologik User Group - {org}-{env}` | Current user + 5 Neologik guests |
| `Neologik NCE User Group - {org}-{env}` | Current user + 5 Neologik guests |
| `Neologik Admin User Group - {org}-{env}` | Current user + 5 Neologik guests |

**Scope:** Entra ID tenant level

---

## 3. Resource Group

**Action:** Create resource group

| Name | Location |
|------|----------|
| `rg-neo-{org}-{env}-{region}-{index}` | Customer specified (e.g., uksouth) |

**Scope:** Subscription

---

## 4. Role Assignments - Security Groups

**Action:** Assign roles to Neologik Admin User Group

| Role | Scope | Principal |
|------|-------|-----------|
| **Contributor** | Resource Group | Neologik Admin User Group |

---

## 5. App Registration & Service Principal (Entra ID)

**Action:** Create app registration for GitHub deployments

| Property | Value |
|----------|-------|
| **Name** | `Neologik GitHub Service Connection - {org}-{env}` |
| **Type** | Multi-tenant (AzureADMultipleOrgs) |
| **Client Secret** | Created (365-day expiration) |
| **Secret Storage** | Stored in Key Vault |

### Group Membership
- Added to: `Neologik Admin User Group - {org}-{env}`

### API Permissions (Entra ID)
| API | Permission | Type |
|-----|------------|------|
| Microsoft Graph | User.Read | Delegated |

**Note:** No admin consent granted by script (standard delegated permission)

---

## 6. Role Assignments - Service Principal

**Action:** Assign roles to service principal

| Role | Scope | Principal |
|------|-------|-----------|
| **Contributor** | Subscription | Service Principal |
| **User Access Administrator** | Subscription | Service Principal |
| **Application Administrator** | Entra ID (Directory Role) | Service Principal |

---

## 7. Key Vault

**Action:** Create Key Vault with RBAC authorization

| Property | Value |
|----------|-------|
| **Name** | `kvneodeploy{org}{env}{region}{index}` |
| **Authorization** | Microsoft Entra ID RBAC (no access policies) |
| **Public Access** | Enabled |
| **Soft Delete** | Enabled (Azure default) |

### Secrets Stored
| Secret Name | Content |
|-------------|---------|
| `neologik-github-service-connection-secret` | Service Principal client secret |

### Role Assignments
| Role | Scope | Principal |
|------|-------|-----------|
| **Key Vault Secrets Officer** | Resource Group | Neologik Admin User Group |

**Note:** Allows group members to read/write secrets in Key Vault

---

## 8. Storage Account

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

## 9. Managed Identities (User-Assigned)

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
| **Application Administrator** | Entra ID (Directory Role) |

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
| Service Principal (GitHub) | User Access Administrator |
| Managed Identity (Script Runner) | Contributor |

### Resource Group Level
| Principal | Role |
|-----------|------|
| Neologik Admin User Group | Contributor |
| Neologik Admin User Group | Key Vault Secrets Officer |
| Neologik Admin User Group | Storage Blob Data Contributor |

### Entra ID (Directory Roles)
| Principal | Role |
|-----------|------|
| Service Principal (GitHub) | Application Administrator |
| Managed Identity (Script Runner) | Application Administrator |
| Managed Identity (SQL) | Directory Readers |
