# Install-NeologikEnvironment.ps1: Access Summary

## Overview

This page summarises the access that the onboarding script, `Install-NeologikEnvironment.ps1`, grants. This page is for approvers who need the security position on one page. [QUICK-REFERENCE.md](QUICK-REFERENCE.md) gives the full description, with each call that the onboarding script makes.

A Global Administrator who is also Owner of the subscription runs the onboarding script once. The onboarding script prepares one resource group and the directory objects of one Neologik Platform environment.

The onboarding script grants access on the resource group. The onboarding script grants three roles on the subscription: Reader, Cost Management Contributor, and Role Based Access Control Administrator limited to assigning three roles. The deployment identity holds the three roles. These roles change no Azure resource other than cost configuration, support requests and assignments of the three assignable roles.

## Contents

1. [What the onboarding script creates](#what-the-onboarding-script-creates)
2. [What the onboarding script grants](#what-the-onboarding-script-grants)
3. [Why the onboarding script grants each wider permission](#why-the-onboarding-script-grants-each-wider-permission)
4. [What the onboarding script does not grant](#what-the-onboarding-script-does-not-grant)
5. [Secrets](#secrets)

## What the onboarding script creates

| Object | Name | Purpose |
|---|---|---|
| Resource group | `rg-<solution name>` | Holds every Azure resource of the environment |
| Security groups | `Neologik User Group - <short name>`<br>`Neologik NCE Contributors - <short name>`<br>`Neologik NCE Admins - <short name>`<br>`Neologik Admin User Group - <short name>` | Give access to the agents, to the Neologik Context Engine and to the Azure resources |
| Guest invitations | The accounts in `NeologikGuestUsers.txt` | The Neologik support accounts. You choose invitation at a question on screen. You can create the accounts in your tenant instead |
| Deployment identity | `Neologik GitHub Service Connection - <short name>` | Neologik deploys the Neologik Platform as this service principal. You can create the service principal yourself instead |
| Platform Sign-in application | `Neologik Platform Sign-in - <short name>` | Signs users in to the Neologik Context Engine and to Apps |
| Agent identity blueprint | `Neologik Agent Blueprint - default - <short name>` | The parent of the agent identities and the agent user accounts that the Neologik Platform creates |
| Key Vault | `kv<short name>`, or the name that you give | Holds the two client secrets |
| Deployment storage account | `stneodeploy<org><env><region><index>`, cut to 24 characters | Holds the configuration file and the log. The container `certificate` holds the TLS certificate files only when you upload them instead of importing a `.pfx` file. Three private containers: `certificate`, `json` and `logs` |
| Managed identities | `neologik-script-runner-service-connection-<short name>` and `neologik-sql-managed-identity-<short name>` | The deployment uses the script runner managed identity. Azure SQL uses the SQL managed identity |
| Resource provider registrations | The list in `resource-providers.txt` | The Azure services that the Neologik Platform uses |
| Configuration file | `Neologik_<org><index>_Configuration_<timestamp>.json` | The name and the id of each object that the onboarding script created. The configuration file contains no secret |

## What the onboarding script grants

| Who receives the access | Scope | Access |
|---|---|---|
| Deployment identity | Subscription | Reader<br>Cost Management Contributor<br>Role Based Access Control Administrator, limited to assigning three roles: Reader, AppGw for Containers Configuration Manager and Cost Management Reader |
| Deployment identity | Resource group | Contributor<br>Key Vault Certificates Officer<br>Key Vault Secrets Officer<br>Storage Blob Data Contributor<br>Azure Kubernetes Service RBAC Cluster Admin<br>Monitoring Contributor<br>Role Based Access Control Administrator |
| Deployment identity | Microsoft Graph application permissions | `Application.ReadWrite.OwnedBy`<br>`AgentIdentityBlueprint.AddRemoveCreds.All` |
| Deployment identity | Ownership | The Platform Sign-in application<br>The service principal of the Platform Sign-in application<br>The agent identity blueprint<br>The service principal of the agent identity blueprint |
| Service principal of the agent identity blueprint | Microsoft Graph application permissions | `AgentIdUser.ReadWrite.IdentityParentedBy` |
| The group `Neologik Admin User Group - <short name>` | Resource group | Contributor<br>Azure Kubernetes Service Cluster Admin Role<br>Azure Kubernetes Service RBAC Cluster Admin<br>Key Vault Administrator<br>Key Vault Secrets Officer<br>Key Vault Certificates Officer<br>Storage Blob Data Owner<br>Storage Blob Data Contributor<br>Storage Table Data Contributor<br>Cognitive Services Data Reader<br>Cognitive Services OpenAI Contributor<br>Search Index Data Reader<br>Azure AI Developer |
| Script runner managed identity | Resource group | Reader<br>Key Vault Secrets Officer<br>Azure Bot Service Contributor Role |
| SQL managed identity | Microsoft Entra directory role | Directory Readers |
| The signed-in administrator | Resource group | Key Vault Secrets Officer<br>Storage Blob Data Contributor |

## Why the onboarding script grants each wider permission

| Permission | Reason |
|---|---|
| Reader on the subscription | Before a deployment, the deployment by Neologik reads the sizes and the quotas that are available in the Azure region |
| Cost Management Contributor on the subscription | The deployment by Neologik creates and maintains the scheduled cost report of the subscription. The role covers cost configuration and support requests only |
| Role Based Access Control Administrator on the resource group | The deployment by Neologik creates workloads inside the resource group. The deployment by Neologik assigns roles to the identities of those workloads, inside the resource group |
| Role Based Access Control Administrator on the subscription, limited to three roles | The deployment runs the ingress controller of a Private Endpoint environment with Application Gateway for Containers. Microsoft requires the identity of that controller to hold two roles. The first is Reader on the resource group that Azure Kubernetes Service creates for the nodes of the cluster. That resource group is outside the resource group of the environment. The second is AppGw for Containers Configuration Manager on the resource group of the environment. The third role is Cost Management Reader on the resource group that Azure Kubernetes Service creates for the nodes of the cluster: the identity of the configuration API of the Neologik Platform holds it and reads the daily cost of the nodes for the return on investment report. The condition on the role lets the deployment identity assign those three roles and no other role, and remove only those three |
| `Application.ReadWrite.OwnedBy` | The deployment by Neologik manages the application registrations that the deployment identity owns. The permission covers no other application registration |
| `AgentIdentityBlueprint.AddRemoveCreds.All` | The deployment by Neologik adds and removes the credentials of the agent identity blueprint |
| `AgentIdUser.ReadWrite.IdentityParentedBy` | The agent identity blueprint creates the agent user accounts of the agent identities of that agent identity blueprint. The permission covers no other agent user account |
| Directory Readers | Azure SQL looks up Microsoft Entra accounts at sign-in through the SQL managed identity |

## What the onboarding script does not grant

- The onboarding script grants no Microsoft Entra directory role to the deployment identity.
- The onboarding script grants no role on the subscription to a security group or to a managed identity.
- The onboarding script adds neither the deployment identity nor a managed identity to a security group.
- The onboarding script gives no administrator consent and creates no permission grant.

A Global Administrator gives the consent after the deployment, as described in [FINISHING-STEPS-GUIDE.md](FINISHING-STEPS-GUIDE.md).

## Secrets

The onboarding script creates two client secrets. Each client secret is valid for 365 days. The onboarding script stores both client secrets in your Key Vault.

| Client secret | Name of the secret in the Key Vault |
|---|---|
| Client secret of the deployment identity | `neologik-deployment-service-principle-secret` |
| Client secret of the Platform Sign-in application | `sp-admin-<solution name>-auth-secret` |

The onboarding script never prints a client secret. The onboarding script never writes a client secret to the log or to a file.

The TLS certificate is separate from the client secrets. An administrator imports the certificate into your Key Vault. Neologik then copies the certificate, private key included, into Neologik's central Key Vault. Each deployment of the ingress reads the certificate from Neologik's central Key Vault.
