# Install-NeologikEnvironment.ps1: Access Summary

## Overview

This page summarises the access that the onboarding script, `Install-NeologikEnvironment.ps1`, grants. This page is for approvers who need the security position on one page. [QUICK-REFERENCE.md](QUICK-REFERENCE.md) gives the full description, with each call that the onboarding script makes.

A Global Administrator who is also Owner of the subscription runs the onboarding script once. The onboarding script prepares one resource group and the directory objects of one Neologik Platform environment.

The onboarding script grants access on the resource group. The onboarding script grants three roles on the subscription: Reader, Cost Management Contributor, and Role Based Access Control Administrator limited to assigning two roles. The deployment identity holds the three roles. These roles change no Azure resource other than cost configuration, support requests and assignments of the two assignable roles.

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
| Security groups | `Neologik User Group - <short name>`<br>`Neologik NCE Contributors - <short name>`<br>`Neologik NCE Admins - <short name>`<br>`Neologik Admin User Group - <short name>` | Give access to the agents, to the Neologik Admin Tool and to the Azure resources |
| Guest invitations | The accounts in `NeologikGuestUsers.txt` | The Neologik support accounts. You choose invitation at a question on screen. You can create the accounts in your tenant instead |
| Deployment identity | `Neologik GitHub Service Connection - <short name>` | Neologik deploys the Neologik Platform as this service principal. You can create the service principal yourself instead |
| Federated credential of the deployment identity | `github-deployments-<environment name>` | Lets a Neologik deployment run that names this environment sign in as the deployment identity with no stored secret. The federated credential adds no permission |
| Platform Sign-in application | `Neologik Platform Sign-in - <short name>` | Signs users in to the Neologik Admin Tool and to Apps |
| Agent identity blueprint | `Neologik Agent Blueprint - default - <short name>` | The parent of the agent identities and the agent user accounts that the Neologik Platform creates |
| Key Vault | `kv<short name>`, or the name that you give | Holds the two client secrets |
| Deployment storage account | `stneodeploy<org><env><region><index>`, cut to 24 characters | Holds the configuration file and the log. The container `certificate` holds the TLS certificate files only when you upload them instead of importing a `.pfx` file. Three private containers: `certificate`, `json` and `logs` |
| Managed identities | `neologik-script-runner-service-connection-<short name>`, `neologik-sql-managed-identity-<short name>`, `neologik-directory-managed-identity-<short name>` and `neologik-system-task-managed-identity-<short name>` | The deployment uses the script runner managed identity. Azure SQL uses the SQL managed identity. From version 5.2 of the Neologik Platform, the agent registration identity creates and changes the application registrations of Neologik agents, and records each Neologik agent in the agent registry of the Microsoft 365 admin center. The system task managed identity creates the identities and role assignments of Neologik agents |
| Resource provider registrations | The list in `resource-providers.txt` | The Azure services that the Neologik Platform uses |
| Configuration file | `Neologik_<org><index>_Configuration_<timestamp>.json` | The name and the id of each object that the onboarding script created. The configuration file contains no secret |

## What the onboarding script grants

| Who receives the access | Scope | Access |
|---|---|---|
| Deployment identity | Subscription | Reader<br>Cost Management Contributor<br>Role Based Access Control Administrator, limited to assigning two roles, Reader and Cost Management Reader, to service principals only |
| Deployment identity | Resource group | Contributor<br>Key Vault Certificates Officer<br>Key Vault Secrets Officer<br>Storage Blob Data Contributor<br>Azure Kubernetes Service RBAC Cluster Admin<br>Monitoring Contributor<br>Role Based Access Control Administrator |
| Deployment identity | Microsoft Graph application permissions | `Application.ReadWrite.OwnedBy`<br>`AgentIdentityBlueprint.AddRemoveCreds.All` |
| Deployment identity | Ownership | The Platform Sign-in application<br>The service principal of the Platform Sign-in application<br>The agent identity blueprint<br>The service principal of the agent identity blueprint |
| Service principal of the agent identity blueprint | Microsoft Graph application permissions | `AgentIdUser.ReadWrite.IdentityParentedBy` |
| Agent registration identity | Microsoft Graph application permissions | `Application.ReadWrite.OwnedBy`<br>`AgentRegistration.ReadWrite.All` |
| The group `Neologik Admin User Group - <short name>` | Resource group | Contributor<br>Azure Kubernetes Service Cluster Admin Role<br>Azure Kubernetes Service RBAC Cluster Admin<br>Key Vault Administrator<br>Key Vault Secrets Officer<br>Key Vault Certificates Officer<br>Storage Blob Data Owner<br>Storage Blob Data Contributor<br>Storage Table Data Contributor<br>Cognitive Services Data Reader<br>Cognitive Services OpenAI Contributor<br>Search Index Data Reader<br>Azure AI Developer |
| Script runner managed identity | Resource group | Reader<br>Key Vault Secrets Officer |
| System task managed identity | Resource group | Role Based Access Control Administrator, which cannot assign Owner, User Access Administrator or Role Based Access Control Administrator, and assigns every other role to service principals only |
| SQL managed identity | Microsoft Entra directory role | Directory Readers |
| The signed-in administrator | Resource group | Key Vault Secrets Officer<br>Storage Blob Data Contributor |

## Why the onboarding script grants each wider permission

| Permission | Reason |
|---|---|
| Reader on the subscription | Before a deployment, the deployment by Neologik reads the sizes and the quotas that are available in the Azure region |
| Cost Management Contributor on the subscription | The deployment by Neologik deletes any retired budget, cost view and scheduled cost email of the subscription. The role covers cost configuration and support requests only |
| Role Based Access Control Administrator on the resource group | The deployment by Neologik creates workloads inside the resource group. The deployment by Neologik assigns roles to the identities of those workloads, inside the resource group |
| Role Based Access Control Administrator on the subscription, limited to two roles | The deployment runs the ingress controller of a Private Endpoint environment with Application Gateway for Containers. Microsoft requires the identity of that controller to hold Reader on the resource group that Azure Kubernetes Service creates for the nodes of the cluster. That resource group is outside the resource group of the environment. The second role is Cost Management Reader on that resource group: the identity of the configuration API of the Neologik Platform holds the role and reads the daily cost of the nodes for the return on investment report. The condition on the role lets the deployment identity assign those two roles to service principals and no other role, and remove only those two |
| `Application.ReadWrite.OwnedBy` of the deployment identity | The deployment by Neologik manages the application registrations that the deployment identity owns. The permission covers no other application registration |
| `Application.ReadWrite.OwnedBy` of the agent registration identity | From version 5.2 of the Neologik Platform, the agent registration identity creates the application registrations of Neologik agents from inside your environment, and changes only the application registrations that the agent registration identity owns. Nothing can sign in as the agent registration identity until a deployment by Neologik adds the sign-in credential |
| `AgentRegistration.ReadWrite.All` of the agent registration identity | From version 5.2 of the Neologik Platform, the agent registration identity writes an entry for each Neologik agent in the agent registry of the Microsoft 365 admin center, with a named owner. Your administrators then see who is accountable for each Neologik agent. The permission covers every entry of the agent registry in your tenant, and the Neologik Platform writes only the entries of Neologik agents |
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

The federated credential of the deployment identity holds no secret. Microsoft Entra ID accepts the federated credential only from a Neologik deployment run that names this environment.

The TLS certificate is separate from the client secrets. An administrator imports the certificate into your Key Vault. Neologik then copies the certificate, private key included, into Neologik's central Key Vault. Each deployment of the ingress reads the certificate from Neologik's central Key Vault.
