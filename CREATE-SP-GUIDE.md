# Creating the Deployment Service Principal Yourself

## Overview

The deployment service principal is the identity Neologik's deployment uses to deploy and operate the platform inside your resource group. By default `Install-NeologikEnvironment.ps1` creates it. This guide is for organisations whose policy requires application registrations to be created by their own identity team.

You create the identity only. The onboarding script assigns every Azure role and the two Microsoft Graph application permissions the identity needs. The full list is in [QUICK-REFERENCE.md](QUICK-REFERENCE.md#summary-of-permissions-by-scope).

## Contents

1. [Step 1: Create the application registration](#step-1-create-the-application-registration)
2. [Step 2: Create a client secret](#step-2-create-a-client-secret)
3. [Step 3: Find the enterprise application object ID](#step-3-find-the-enterprise-application-object-id)
4. [Step 4: Give the values to the onboarding script](#step-4-give-the-values-to-the-onboarding-script)
5. [Alternative: Azure CLI](#alternative-azure-cli)
6. [What you do not need to do](#what-you-do-not-need-to-do)
7. [Renewing the secret](#renewing-the-secret)

## Step 1: Create the application registration

1. Sign in to the Azure portal (portal.azure.com) in the tenant that will host the environment.
2. Open **Microsoft Entra ID**, then **App registrations**.
3. Select **New registration** and enter:

   | Field | Value |
   |---|---|
   | Name | Your choice. If you have no convention of your own, use the name the script would give it: `Neologik GitHub Service Connection - <short name>`, for example `Neologik GitHub Service Connection - abcprd01`. `<short name>` is the organisation code, the environment type and the environment index together |
   | Supported account types | **Accounts in this organizational directory only (Single tenant)**. A single-tenant registration is sufficient |
   | Redirect URI | Leave empty |

4. Select **Register**.

Registering through the portal also creates the matching enterprise application (the service principal). Configure nothing else on the registration: no API permissions, no roles and no certificates. The onboarding script makes the identity an owner of the application registrations it is to manage.

## Step 2: Create a client secret

1. On the registration, open **Certificates & secrets**, then **Client secrets**.
2. Select **New client secret**.
3. Enter a description and choose an expiry that meets your organisation's policy.
4. Select **Add**.
5. Copy the secret **Value** at once: it is shown only once. Store it securely until you run the onboarding script.

## Step 3: Find the enterprise application object ID

The onboarding script asks for one id. Three ids exist, and only one is correct:

| Id | Where it is shown | Use it? |
|---|---|---|
| Application (client) ID | App registrations, Overview | No |
| Object ID | App registrations, Overview | No |
| Object ID | **Enterprise applications**, Overview | **Yes** |

To find it:

1. Open **Microsoft Entra ID**, then **Enterprise applications**.
2. If the application is not listed, set the **Application type** filter to **All applications**.
3. Search for the name you chose and select the application.
4. On the **Overview** page, copy the **Object ID**.

The script resolves the application (client) ID from this object ID. The object ID is not a secret.

## Step 4: Give the values to the onboarding script

Use any one of these methods:

| Method | How |
|---|---|
| At the prompt | When the script asks "Use a service principal you have already created for deployment?", answer `Y` and paste the object ID. Enter the client secret at the masked prompt, or press Enter to skip it |
| Answer file | In `inputs.json`, set `"useExistingServicePrincipal": true` and `"existingServicePrincipalObjectId": "<object id>"`. Pass the secret on the command line with `-ExistingServicePrincipalSecret` in preference to storing it in the file |
| Command line | `.\Install-NeologikEnvironment.ps1 -ExistingServicePrincipalObjectId "<object id>" -ExistingServicePrincipalSecret $env:SP_CLIENT_SECRET` |

If you skip the secret, the script completes without it. Before Neologik runs the first deployment, add the secret to the environment's Key Vault yourself, as a secret named exactly `neologik-deployment-service-principle-secret`.

## Alternative: Azure CLI

These commands create the application registration, the service principal and the secret, then print the object ID the script needs:

```powershell
az ad sp create-for-rbac --name "Neologik GitHub Service Connection - <short name>"
# The "password" value in the output is the client secret. It is shown only once.

az ad sp show --id <appId from the output above> --query id -o tsv
# Prints the enterprise application object ID.
```

Do not use the role assignment options of `create-for-rbac`. The onboarding script assigns every role itself.

## What you do not need to do

The onboarding script assigns to a service principal you supply the same roles as to one it creates:

| Item | Reason |
|---|---|
| Azure role assignments | The script assigns Reader and Cost Management Contributor on the subscription, and the resource group roles |
| API permissions and admin consent | The script grants the two Microsoft Graph application permissions: `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` |
| Group membership | The service principal is not a member of any group |

A role that is already assigned is found by the script and left in place.

## Renewing the secret

Your organisation owns this registration, so the secret is yours to renew. Before it expires:

1. Create a new client secret on the registration.
2. Update the secret `neologik-deployment-service-principle-secret` in the environment's Key Vault with the new value.
3. Tell Neologik at support@neologik.ai, so that the deployment credential is refreshed.
