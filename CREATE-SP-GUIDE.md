# Creating Your Own Deployment Service Principal

This guide is for customers who want to create the deployment service principal themselves instead of letting `Install-NeologikEnvironment.ps1` create it. This is optional - by default the script creates the service principal for you. Use this path if your organization's policy requires app registrations to be created by your own identity team or through your own process.

The service principal is the identity Neologik's deployment pipeline (GitHub Actions) uses to deploy and operate the platform inside your resource group. You only create the identity - **the onboarding script assigns every permission it needs**, and the full grant list is documented in [QUICK-REFERENCE.md](QUICK-REFERENCE.md) (section 6) and [secure-overview.md](secure-overview.md).

---

## Step 1: Create the App Registration

1. Go to **Azure Portal** (portal.azure.com) and sign in to the tenant that will host the Neologik environment
2. Navigate to **Microsoft Entra ID** > **App registrations**
3. Click **New registration**
4. Fill in:
   - **Name**: your choice - if you have no naming convention of your own, use `Neologik GitHub Service Connection - <your org code>` so it is recognisable later
   - **Supported account types**: **Accounts in this organizational directory only (Single tenant)** - this is sufficient
   - **Redirect URI**: leave empty (not needed)
5. Click **Register**

Registering through the portal also creates the matching **enterprise application** (the service principal) in your tenant automatically - you will need its ID in Step 3.

Do **not** configure anything else on the app - no API permissions, no roles, no certificates. See "What you do NOT need to do" below.

## Step 2: Create a Client Secret

1. On the app registration you just created, go to **Certificates & secrets** > **Client secrets**
2. Click **New client secret**
3. Enter a description (e.g. "Neologik deployment") and choose an expiry per your organization's policy
4. Click **Add**
5. **Copy the secret Value immediately** - it is shown only once. Store it securely until you run the onboarding script

**Secret lifecycle stays with you.** Because your organization owns this app registration, the Neologik platform cannot rotate its secret. Before the secret expires: create a new one here, update the Key Vault secret `neologik-deployment-service-principle-secret` in the environment's Key Vault with the new value, and notify Neologik (support@neologik.ai) so the deployment credential is refreshed.

## Step 3: Find the Enterprise-Application Object ID

This is the value the onboarding script asks for, and it is the step most often got wrong - **three different IDs exist and only one is correct**:

| ID | Where you see it | Is it the one? |
|----|------------------|----------------|
| Application (client) ID | App registrations > Overview | No |
| Object ID | **App registrations** > Overview | No |
| Object ID | **Enterprise applications** > Overview | **Yes - use this one** |

To find it:

1. Navigate to **Microsoft Entra ID** > **Enterprise applications**
2. If your app is not listed, set the **Application type** filter to **All applications**
3. Search for the app by the name you gave it in Step 1 and select it
4. On the **Overview** page, copy the **Object ID**

The script resolves the Application (client) ID itself from this object ID, so you do not need to supply anything else.

## Alternative: Azure CLI

If you prefer the command line, this creates the app registration, service principal and secret in one step, then prints the object ID the script needs:

```powershell
az ad sp create-for-rbac --name "Neologik GitHub Service Connection - <your org code>"
# Note the "password" value from the output - that is the client secret (shown once)

az ad sp show --id <appId from the output above> --query id -o tsv
# This prints the enterprise-application OBJECT ID - the value the onboarding script asks for
```

Ignore any role-assignment options of `create-for-rbac` - the onboarding script assigns all roles itself.

## Step 4: Provide the Values to the Onboarding Script

Any one of these ways:

- **Interactive** (default): when the script asks "Use a service principal you have already created for deployment?", answer **Y**, paste the object ID, then enter the client secret at the masked prompt (or press Enter to skip it - see below)
- **Answer file**: in `inputs.json` set `"useExistingServicePrincipal": true` and `"existingServicePrincipalObjectId": "<object id>"`. Prefer passing the secret on the command line with `-ExistingServicePrincipalSecret` rather than storing it in the file
- **Command line**: `.\Install-NeologikEnvironment.ps1 -ExistingServicePrincipalObjectId "<object id>" -ExistingServicePrincipalSecret $env:SP_CLIENT_SECRET`

**If you skip the secret**: the script completes without it, but before Neologik can run the first deployment you must add the secret to the environment's Key Vault yourself, as a secret named exactly `neologik-deployment-service-principle-secret`.

## What You Do NOT Need to Do

The operator running the onboarding script holds Subscription Owner and Global Administrator, and the script grants everything the service principal needs - identically to a script-created one:

- **No Azure role assignments** - the script assigns Reader and Cost Management Contributor at subscription scope and the resource-group role set
- **No API permissions / admin consent on the app** - the script grants the Microsoft Graph application roles directly to the service principal
- **No group setup** - the service principal is not a member of any group (project#2269)

If you pre-assign roles or permissions anyway, the script treats them as already present and continues - but they are unnecessary.

## Need Help?

Email support@neologik.ai and include a screenshot of the Enterprise applications Overview page if you are unsure which ID to send.
