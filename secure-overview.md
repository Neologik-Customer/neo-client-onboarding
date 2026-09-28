# Install-NeologikEnvironment.ps1: Access Summary

## Overview

This page summarises the access that `Install-NeologikEnvironment.ps1` grants. It is for a reader who needs the position on one page. [QUICK-REFERENCE.md](QUICK-REFERENCE.md) gives the full description, with every call the script makes.

The script is run once, by a Global Administrator who is also Owner of the subscription. It prepares one resource group and the directory objects of one Neologik Platform environment. Access is granted on the resource group. The only roles on the subscription are Reader and Cost Management Contributor, held by the deployment identity; neither gives control of a resource.

## What the script creates

| Object | Name | Purpose |
|---|---|---|
| Resource group | `rg-<solution name>` | Holds every Azure resource of the environment |
| Security groups | `Neologik User Group - <short name>`, `Neologik NCE Contributors - <short name>`, `Neologik NCE Admins - <short name>`, `Neologik Admin User Group - <short name>` | Access to the agents, to the Neologik Context Engine and to the Azure resources |
| Guest invitations | The accounts in `NeologikGuestUsers.txt` | The Neologik support accounts. Invitation is optional: you can create the accounts in your own tenant instead |
| Deployment identity | `Neologik GitHub Service Connection - <short name>` | The service principal under which Neologik deploys the platform. You can supply a service principal of your own instead |
| Platform Sign-in application | `Neologik Platform Sign-in - <short name>` | Signs your users in to the Neologik Context Engine and to Apps |
| Agent identity blueprint | `Neologik Agent Blueprint - default - <short name>` | The parent of the agent identities and agent user accounts the platform creates |
| Key Vault | `kv<short name>`, or the name you give | Holds the two client secrets |
| Storage account | Three private containers: `certificate`, `json` and `logs` | Holds the TLS certificate, the configuration file and the log |
| Managed identities | `neologik-script-runner-service-connection-<short name>`, `neologik-sql-managed-identity-<short name>` | Used by the deployment and by Azure SQL |
| Resource provider registrations | The list in `resource-providers.txt` | The Azure services the platform uses |
| Configuration file | `Neologik_<org><index>_Configuration_<timestamp>.json` | The names and ids of what was created. It contains no secret |

## What the script grants

| Principal | Scope | Access |
|---|---|---|
| Deployment identity | Subscription | Reader; Cost Management Contributor |
| Deployment identity | Resource group | Contributor; Key Vault Certificates Officer; Key Vault Secrets Officer; Storage Blob Data Contributor; Azure Kubernetes Service RBAC Cluster Admin; Monitoring Contributor; Role Based Access Control Administrator |
| Deployment identity | Microsoft Graph application permissions | `Application.ReadWrite.OwnedBy`; `AgentIdentityBlueprint.AddRemoveCreds.All` |
| Deployment identity | Ownership | The Platform Sign-in application, the agent identity blueprint and the service principal of each |
| Agent identity blueprint principal | Microsoft Graph application permissions | `AgentIdUser.ReadWrite.IdentityParentedBy` |
| Neologik Admin User Group | Resource group | Contributor; Azure Kubernetes Service Cluster Admin Role; Azure Kubernetes Service RBAC Cluster Admin; Key Vault Administrator; Key Vault Secrets Officer; Key Vault Certificates Officer; Storage Blob Data Owner; Storage Blob Data Contributor; Storage Table Data Contributor; Cognitive Services Data Reader; Cognitive Services OpenAI Contributor; Search Index Data Reader; Azure AI Developer |
| Script runner managed identity | Resource group | Reader; Key Vault Secrets Officer; Azure Bot Service Contributor Role |
| SQL managed identity | Microsoft Entra directory role | Directory Readers |
| The signed-in operator | Resource group | Key Vault Secrets Officer; Storage Blob Data Contributor |

## Why each wider permission is held

| Permission | Reason |
|---|---|
| Reader on the subscription | The deployment reads the sizes and quotas available in the region before it deploys |
| Cost Management Contributor on the subscription | The deployment creates and maintains the scheduled cost report of the subscription. The role covers cost configuration only |
| Role Based Access Control Administrator on the resource group | The deployment assigns roles to the identities of the workloads it creates, inside the resource group |
| `Application.ReadWrite.OwnedBy` | The deployment manages the application registrations it owns, and no others |
| `AgentIdentityBlueprint.AddRemoveCreds.All` | The deployment adds and removes the credentials of the agent identity blueprint |
| `AgentIdUser.ReadWrite.IdentityParentedBy` | The blueprint creates the agent user accounts of its own agent identities, and no others |
| Directory Readers | Azure SQL resolves Microsoft Entra sign-ins through the SQL managed identity |

## What the script does not grant

- No Microsoft Entra directory role to the deployment identity.
- No role on the subscription to a group or to a managed identity.
- No group membership to the deployment identity or to a managed identity.
- No administrator consent and no permission grant. Your Global Administrator gives consent after deployment, as described in [FINISHING-STEPS-GUIDE.md](FINISHING-STEPS-GUIDE.md).

## Secrets

The script creates two client secrets, each valid for 365 days, and stores both in your Key Vault: `neologik-deployment-service-principle-secret` and `sp-admin-<solution name>-auth-secret`. Neither is printed, logged or written to a file.
