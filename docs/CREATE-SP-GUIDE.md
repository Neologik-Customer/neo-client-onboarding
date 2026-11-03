# Creating the Deployment Service Principal Yourself

## Overview

The deployment service principal is the identity that Neologik signs in with to deploy and operate the Neologik Platform inside your resource group. The onboarding script, `Install-NeologikEnvironment.ps1`, normally creates the deployment service principal.

The other documents of the onboarding kit use the name deployment identity for the deployment service principal.

This guide is for a customer who chooses to create the deployment service principal.

| Subject | Position |
|---|---|
| What you create | The application registration, the service principal and a client secret |
| Azure roles | The onboarding script assigns each Azure role that the deployment service principal needs. You assign no role |
| Microsoft Graph | The onboarding script grants the two Microsoft Graph application permissions that the deployment service principal needs. You grant no permission |
| Federated credential | The onboarding script adds one federated credential, `github-deployments-<environment name>`, to your application registration. The federated credential lets a Neologik deployment run that names this environment sign in with no stored secret, and adds no permission |

[QUICK-REFERENCE.md](QUICK-REFERENCE.md#summary-of-permissions-by-scope) lists each role and each permission.

## Contents

1. [Step 1: Create the application registration](#step-1-create-the-application-registration)
2. [Step 2: Create a client secret](#step-2-create-a-client-secret)
3. [Step 3: Find the object ID of the enterprise application](#step-3-find-the-object-id-of-the-enterprise-application)
4. [Step 4: Give the values to the onboarding script](#step-4-give-the-values-to-the-onboarding-script)
5. [Alternative: Azure CLI](#alternative-azure-cli)
6. [What you do not need to do](#what-you-do-not-need-to-do)
7. [Renewing the client secret](#renewing-the-client-secret)

## Step 1: Create the application registration

1. Sign in to the Azure portal, https://portal.azure.com, in the tenant of the environment.
2. Open **Microsoft Entra ID**, then **App registrations**.
3. Select **New registration** and enter these values:

   | Field | Value |
   |---|---|
   | Name | A name of your choice. The standard name is `Neologik GitHub Service Connection - <short name>`, for example `Neologik GitHub Service Connection - abcprd01` |
   | Supported account types | **Accounts in this organizational directory only (Single tenant)**. An application registration for a single tenant is enough |
   | Redirect URI | Leave the field empty |

4. Select **Register**.

`<short name>` stands for the organisation code, the environment type and the environment index, joined together.

The Azure portal also creates the enterprise application that matches the application registration. The enterprise application is the service principal.

Configure nothing else on the application registration. Add no API permission, no role and no certificate.

The onboarding script makes the deployment service principal an owner of each application registration that the deployment service principal manages.

## Step 2: Create a client secret

1. On the application registration, open **Certificates & secrets**, then **Client secrets**.
2. Select **New client secret**.
3. Enter a description and choose an expiry date.
4. Select **Add**.
5. Copy the **Value** of the client secret immediately. The Azure portal shows the value once only.
6. Store the value securely until you run the onboarding script.

## Step 3: Find the object ID of the enterprise application

The onboarding script asks for one id. The Azure portal shows three ids, and only one of the three is correct.

| Id | Where the Azure portal shows the id | Is this the id to use? |
|---|---|---|
| Application (client) ID | **App registrations**, **Overview** | No |
| Object ID | **App registrations**, **Overview** | No |
| Object ID | **Enterprise applications**, **Overview** | **Yes** |

To find the correct id:

1. Open **Microsoft Entra ID**, then **Enterprise applications**.
2. When the list does not show the application, set the filter **Application type** to **All applications**.
3. Search for the name from step 1 and select the application.
4. On the **Overview** page, copy the **Object ID**.

The onboarding script finds the client ID of the application from the object ID. The object ID is not a secret.

## Step 4: Give the values to the onboarding script

Use one of the three methods.

| Method | What you do |
|---|---|
| At the prompt | The onboarding script asks "Use a service principal you have already created for deployment?". Answer `Y` and paste the object ID. The onboarding script then asks for the client secret and hides the characters that you type. Enter the client secret, or press Enter to give no client secret |
| Answer file | In `inputs.json`, set `"useExistingServicePrincipal": true` and `"existingServicePrincipalObjectId": "<object id>"`. Give the client secret on the command line, with `-ExistingServicePrincipalSecret`. Do not store the client secret in `inputs.json` |
| Command line | `.\Install-NeologikEnvironment.ps1 -ExistingServicePrincipalObjectId "<object id>" -ExistingServicePrincipalSecret $env:SP_CLIENT_SECRET` |

### When you give no client secret

The onboarding script completes without the client secret. Add the client secret to the Key Vault of the environment before Neologik starts the first deployment. The name of the Key Vault secret must be exactly `neologik-deployment-service-principle-secret`.

## Alternative: Azure CLI

The two commands create the application registration, the service principal and the client secret. The second command prints the object ID that the onboarding script needs.

```powershell
az ad sp create-for-rbac --name "Neologik GitHub Service Connection - <short name>"
# The "password" value in the output is the client secret. It is shown only once.

az ad sp show --id <appId from the output above> --query id -o tsv
# Prints the enterprise application object ID.
```

Do not use the role assignment options of `create-for-rbac`. The onboarding script assigns each role.

## What you do not need to do

The onboarding script treats your deployment service principal exactly as a deployment service principal that the onboarding script creates. The onboarding script assigns the same roles and grants the same permissions.

| Item | Reason |
|---|---|
| Azure role assignments | The onboarding script assigns Reader, Cost Management Contributor and the limited Role Based Access Control Administrator on the subscription. The onboarding script also assigns the roles on the resource group |
| API permissions and administrator consent | The onboarding script grants the two Microsoft Graph application permissions: `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` |
| Federated credential | The onboarding script adds the federated credential `github-deployments-<environment name>` to your application registration |
| Group membership | The deployment service principal is a member of no group |

When a role is already assigned, the onboarding script finds the role assignment and makes no change.

## Renewing the client secret

You own the application registration, so you renew the client secret. Before the client secret expires:

1. Create a new client secret on the application registration.
2. In the Key Vault of the environment, update the secret `neologik-deployment-service-principle-secret` with the new value.
3. Tell Neologik at support@neologik.ai. Neologik then updates the credential that the deployment uses.
