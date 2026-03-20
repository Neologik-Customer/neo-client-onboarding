# Neologik Manual Onboarding Guide

**Guide version:** 1.0
**Based on script version:** 1.9.0
**Last updated:** 2026-03-20

This guide covers every step performed by the automated `Install-NeologikEnvironment.ps1` script, translated into manual Azure CLI and Microsoft Graph commands.

---

## Prerequisites

### Required Access
- **Owner** role at the Azure subscription level (needed for RBAC assignments)
- **Global Administrator** role in Entra ID (needed for directory role assignments)

### Required Tools
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az`) — version 2.50+
- `jq` — for parsing JSON output in shell scripts (optional but recommended)

### Variables to set before running commands

Replace all `<placeholder>` values with your actual values before running any command. Set these in your shell session and reuse them throughout.

```bash
# Core identifiers
ORG_CODE="abc"                       # 3-char lowercase alphanumeric org code
ENV_TYPE="dev"                        # "dev" or "prd"
ORG_NAME="Contoso Ltd"               # Full organization name
REGION="uksouth"                      # Azure region (e.g. uksouth, eastus)
REGION_SHORT="uks"                   # Short region code (e.g. uks, eus, neu)
ENV_INDEX="01"                        # 2-digit index, e.g. 01

# Derived names (do not change these)
ORG_ENV="${ORG_CODE}${ENV_TYPE}"                                    # e.g. abcdev
RG_NAME="rg-neo-${ORG_ENV}-${REGION_SHORT}-${ENV_INDEX}"            # e.g. rg-neo-abcdev-uks-01
KV_NAME="kvneodeploy${ORG_ENV}${REGION_SHORT}${ENV_INDEX}"          # e.g. kvneodeployabcdevuks01 (max 24 chars)
SA_NAME="stneodeploy${ORG_ENV}${REGION_SHORT}${ENV_INDEX}"          # e.g. stneodeployabcdevuks01 (max 24 chars)
APP_NAME="Neologik GitHub Service Connection - ${ORG_CODE}-${ENV_TYPE}"
MI_RUNNER_NAME="neologik-script-runner-service-connection-${ORG_ENV}"
MI_SQL_NAME="neologik-sql-managed-identity-${ORG_ENV}"
GROUP_ADMIN="Neologik Admin User Group - ${ORG_CODE}-${ENV_TYPE}"
GROUP_NCE="Neologik NCE User Group - ${ORG_CODE}-${ENV_TYPE}"

# Bot names — extend this array if you have more than one bot
BOT_NAMES=("bot")                    # short names (1-4 chars), one per bot
BOT_AGENT_NAMES=("bot")             # full agent names, one per bot

# Neologik guest users to invite
GUEST_EMAILS=(
  "bryan.lloyd@neologik.ai"
  "rupert.fawcett@neologik.ai"
  "Jashanpreet.Magar@neologik.ai"
  "leon.simpson@neologik.ai"
  "boris.anderson@neologik.ai"
)

# Bot DNS (for the config output file)
BOT_HOSTNAME="neologik"              # e.g. neologik
BOT_DOMAIN="contoso.com"            # e.g. contoso.com
```

---

## Step 1 — Authenticate to Azure

```bash
az login
az account list --output table
```

Set the correct subscription:

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Using subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
echo "Tenant: ${TENANT_ID}"
```

If you need to select a different subscription:

```bash
az account set --subscription "<subscription-name-or-id>"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

---

## Step 2 — Verify Permissions

### 2a. Confirm Owner role at subscription level

```bash
CURRENT_USER=$(az account show --query user.name -o tsv)
az role assignment list \
  --assignee "${CURRENT_USER}" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}" \
  --query "[?roleDefinitionName=='Owner'].roleDefinitionName" \
  -o tsv
# Expected output: Owner
```

### 2b. Confirm Global Administrator in Entra ID

```bash
# Get the object ID for the Global Administrator directory role
GA_ROLE_ID=$(az rest \
  --method GET \
  --url "https://graph.microsoft.com/v1.0/directoryRoles" \
  --query "value[?displayName=='Global Administrator'].id" \
  -o tsv)

# Check if your user is a member
CURRENT_USER_OID=$(az ad signed-in-user show --query id -o tsv)
az rest \
  --method GET \
  --url "https://graph.microsoft.com/v1.0/directoryRoles/${GA_ROLE_ID}/members" \
  --query "value[?id=='${CURRENT_USER_OID}'].displayName" \
  -o tsv
# Expected output: your display name
```

---

## Step 3 — Register Resource Providers

```bash
az provider register --namespace Microsoft.Resources        --wait
az provider register --namespace Microsoft.KeyVault         --wait
az provider register --namespace Microsoft.Storage          --wait
az provider register --namespace Microsoft.Compute          --wait
az provider register --namespace Microsoft.ManagedIdentity  --wait
```

Check registration status:

```bash
az provider show --namespace Microsoft.Compute --query registrationState -o tsv
# Expected: Registered
```

---

## Step 4 — Create Resource Group

```bash
az group create \
  --name "${RG_NAME}" \
  --location "${REGION}"

RG_ID=$(az group show --name "${RG_NAME}" --query id -o tsv)
echo "Resource Group ID: ${RG_ID}"
```

---

## Step 5 — Invite Neologik Guest Users

For each guest email, check if they already exist and invite if not.

```bash
declare -A GUEST_USER_IDS

for EMAIL in "${GUEST_EMAILS[@]}"; do
  # Check if user already exists
  EXISTING_ID=$(az rest \
    --method GET \
    --url "https://graph.microsoft.com/v1.0/users?\$filter=mail eq '${EMAIL}' or userPrincipalName eq '${EMAIL}'" \
    --query "value[0].id" -o tsv 2>/dev/null)

  if [[ -n "${EXISTING_ID}" && "${EXISTING_ID}" != "None" ]]; then
    echo "User ${EMAIL} already exists: ${EXISTING_ID}"
    GUEST_USER_IDS["${EMAIL}"]="${EXISTING_ID}"
  else
    echo "Inviting ${EMAIL}..."
    INVITE_RESULT=$(az rest \
      --method POST \
      --url "https://graph.microsoft.com/v1.0/invitations" \
      --body "{
        \"invitedUserEmailAddress\": \"${EMAIL}\",
        \"inviteRedirectUrl\": \"https://portal.azure.com\",
        \"sendInvitationMessage\": true
      }")
    USER_ID=$(echo "${INVITE_RESULT}" | jq -r '.invitedUser.id')
    echo "  Invited — User ID: ${USER_ID}"
    GUEST_USER_IDS["${EMAIL}"]="${USER_ID}"
  fi
done
```

---

## Step 6 — Create Security Groups

### 6a. Bot user groups (one per bot)

```bash
declare -A BOT_GROUP_IDS

for i in "${!BOT_NAMES[@]}"; do
  BOT_SHORT="${BOT_NAMES[$i]}"
  BOT_AGENT="${BOT_AGENT_NAMES[$i]}"
  GROUP_BOT_NAME="Neologik User Group ${BOT_AGENT} - ${ORG_CODE}-${ENV_TYPE}"
  NICK=$(echo "${GROUP_BOT_NAME}" | tr -d ' ')

  # Check if it already exists
  EXISTING=$(az rest \
    --method GET \
    --url "https://graph.microsoft.com/v1.0/groups?\$filter=displayName eq '${GROUP_BOT_NAME}'" \
    --query "value[0].id" -o tsv 2>/dev/null)

  if [[ -n "${EXISTING}" && "${EXISTING}" != "None" ]]; then
    echo "Group '${GROUP_BOT_NAME}' already exists: ${EXISTING}"
    BOT_GROUP_IDS["${BOT_SHORT}"]="${EXISTING}"
  else
    GROUP_ID=$(az rest \
      --method POST \
      --url "https://graph.microsoft.com/v1.0/groups" \
      --body "{
        \"displayName\": \"${GROUP_BOT_NAME}\",
        \"description\": \"Neologik users for Teams app access - ${BOT_AGENT} bot\",
        \"mailEnabled\": false,
        \"securityEnabled\": true,
        \"mailNickname\": \"${NICK}\"
      }" --query id -o tsv)
    echo "Created group '${GROUP_BOT_NAME}': ${GROUP_ID}"
    BOT_GROUP_IDS["${BOT_SHORT}"]="${GROUP_ID}"
  fi
done
```

### 6b. NCE user group

```bash
NCE_NICK=$(echo "${GROUP_NCE}" | tr -d ' ')
GROUP_NCE_ID=$(az rest \
  --method POST \
  --url "https://graph.microsoft.com/v1.0/groups" \
  --body "{
    \"displayName\": \"${GROUP_NCE}\",
    \"description\": \"Users who need access to NCE web tool\",
    \"mailEnabled\": false,
    \"securityEnabled\": true,
    \"mailNickname\": \"${NCE_NICK}\"
  }" --query id -o tsv)
echo "NCE Group ID: ${GROUP_NCE_ID}"
```

### 6c. Admin user group

```bash
ADMIN_NICK=$(echo "${GROUP_ADMIN}" | tr -d ' ')
GROUP_ADMIN_ID=$(az rest \
  --method POST \
  --url "https://graph.microsoft.com/v1.0/groups" \
  --body "{
    \"displayName\": \"${GROUP_ADMIN}\",
    \"description\": \"Users who will administer and support the resources\",
    \"mailEnabled\": false,
    \"securityEnabled\": true,
    \"mailNickname\": \"${ADMIN_NICK}\"
  }" --query id -o tsv)
echo "Admin Group ID: ${GROUP_ADMIN_ID}"
```

### 6d. Add all guest users to all groups

Collect all group IDs into one array first:

```bash
ALL_GROUP_IDS=("${GROUP_ADMIN_ID}" "${GROUP_NCE_ID}" "${BOT_GROUP_IDS[@]}")
```

Add each guest to each group:

```bash
for GID in "${ALL_GROUP_IDS[@]}"; do
  for EMAIL in "${GUEST_EMAILS[@]}"; do
    USER_OID="${GUEST_USER_IDS[${EMAIL}]}"
    if [[ -z "${USER_OID}" ]]; then
      echo "Skipping ${EMAIL} — no user ID found"
      continue
    fi
    echo "Adding ${EMAIL} to group ${GID}..."
    az rest \
      --method POST \
      --url "https://graph.microsoft.com/v1.0/groups/${GID}/members/\$ref" \
      --body "{\"@odata.id\": \"https://graph.microsoft.com/v1.0/directoryObjects/${USER_OID}\"}" \
      2>/dev/null || echo "  (already a member or error — continuing)"
  done
done
```

### 6e. Add yourself to all groups

```bash
for GID in "${ALL_GROUP_IDS[@]}"; do
  az rest \
    --method POST \
    --url "https://graph.microsoft.com/v1.0/groups/${GID}/members/\$ref" \
    --body "{\"@odata.id\": \"https://graph.microsoft.com/v1.0/directoryObjects/${CURRENT_USER_OID}\"}" \
    2>/dev/null || echo "(already a member)"
done
```

---

## Step 7 — Assign Roles to the Admin Group

### 7a. Contributor at subscription level

```bash
az role assignment create \
  --assignee-object-id "${GROUP_ADMIN_ID}" \
  --assignee-principal-type Group \
  --role "Contributor" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}"
```

### 7b. Key Vault Secrets Officer at resource group level

```bash
az role assignment create \
  --assignee-object-id "${GROUP_ADMIN_ID}" \
  --assignee-principal-type Group \
  --role "Key Vault Secrets Officer" \
  --scope "${RG_ID}"
```

### 7c. Storage Blob Data Contributor at resource group level

```bash
az role assignment create \
  --assignee-object-id "${GROUP_ADMIN_ID}" \
  --assignee-principal-type Group \
  --role "Storage Blob Data Contributor" \
  --scope "${RG_ID}"
```

---

## Step 8 — Create App Registration (GitHub Service Connection)

### 8a. Create the application

```bash
APP_RESULT=$(az rest \
  --method POST \
  --url "https://graph.microsoft.com/v1.0/applications" \
  --body "{
    \"displayName\": \"${APP_NAME}\",
    \"signInAudience\": \"AzureADMultipleOrgs\"
  }")

APP_CLIENT_ID=$(echo "${APP_RESULT}" | jq -r '.appId')
APP_OBJECT_ID=$(echo "${APP_RESULT}" | jq -r '.id')
echo "App Client ID: ${APP_CLIENT_ID}"
echo "App Object ID: ${APP_OBJECT_ID}"
```

### 8b. Create the Service Principal

```bash
SP_RESULT=$(az rest \
  --method POST \
  --url "https://graph.microsoft.com/v1.0/servicePrincipals" \
  --body "{\"appId\": \"${APP_CLIENT_ID}\"}")

SP_OBJECT_ID=$(echo "${SP_RESULT}" | jq -r '.id')
echo "Service Principal Object ID: ${SP_OBJECT_ID}"
```

### 8c. Create the client secret

```bash
SECRET_EXPIRY_DAYS=30
SECRET_END_DATE=$(date -u -d "+${SECRET_EXPIRY_DAYS} days" +"%Y-%m-%dT%H:%M:%SZ")

SECRET_RESULT=$(az rest \
  --method POST \
  --url "https://graph.microsoft.com/v1.0/applications/${APP_OBJECT_ID}/addPassword" \
  --body "{
    \"passwordCredential\": {
      \"displayName\": \"auth\",
      \"endDateTime\": \"${SECRET_END_DATE}\"
    }
  }")

CLIENT_SECRET=$(echo "${SECRET_RESULT}" | jq -r '.secretText')
SECRET_EXPIRY=$(echo "${SECRET_RESULT}" | jq -r '.endDateTime')

# Store secret securely — do NOT log it
echo "Secret expires: ${SECRET_EXPIRY}"
echo "Secret value: (captured in CLIENT_SECRET variable — do not print)"
```

---

## Step 9 — Assign Roles to the App Registration / Service Principal

### 9a. Add service principal to Admin group

```bash
az rest \
  --method POST \
  --url "https://graph.microsoft.com/v1.0/groups/${GROUP_ADMIN_ID}/members/\$ref" \
  --body "{\"@odata.id\": \"https://graph.microsoft.com/v1.0/directoryObjects/${SP_OBJECT_ID}\"}"
```

### 9b. Contributor at subscription level

```bash
az role assignment create \
  --assignee-object-id "${SP_OBJECT_ID}" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}"
```

### 9c. User Access Administrator at subscription level

```bash
az role assignment create \
  --assignee-object-id "${SP_OBJECT_ID}" \
  --assignee-principal-type ServicePrincipal \
  --role "User Access Administrator" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}"
```

### 9d. Application Administrator directory role

```bash
# Get or activate the Application Administrator role
APP_ADMIN_ROLE_ID=$(az rest \
  --method GET \
  --url "https://graph.microsoft.com/v1.0/directoryRoles" \
  --query "value[?displayName=='Application Administrator'].id" -o tsv)

if [[ -z "${APP_ADMIN_ROLE_ID}" ]]; then
  # Role not yet activated — activate it from template
  TEMPLATE_ID=$(az rest \
    --method GET \
    --url "https://graph.microsoft.com/v1.0/directoryRoleTemplates" \
    --query "value[?displayName=='Application Administrator'].id" -o tsv)

  APP_ADMIN_ROLE_ID=$(az rest \
    --method POST \
    --url "https://graph.microsoft.com/v1.0/directoryRoles" \
    --body "{\"roleTemplateId\": \"${TEMPLATE_ID}\"}" \
    --query id -o tsv)
fi

echo "Application Administrator role ID: ${APP_ADMIN_ROLE_ID}"

# Assign the service principal to the role
az rest \
  --method POST \
  --url "https://graph.microsoft.com/v1.0/directoryRoles/${APP_ADMIN_ROLE_ID}/members/\$ref" \
  --body "{\"@odata.id\": \"https://graph.microsoft.com/v1.0/directoryObjects/${SP_OBJECT_ID}\"}"
```

---

## Step 10 — Create Key Vault

### 10a. Create the vault

```bash
az keyvault create \
  --name "${KV_NAME}" \
  --resource-group "${RG_NAME}" \
  --location "${REGION}" \
  --enable-rbac-authorization true \
  --sku standard

KV_URI="https://${KV_NAME}.vault.azure.net/"
KV_ID=$(az keyvault show --name "${KV_NAME}" --resource-group "${RG_NAME}" --query id -o tsv)
echo "Key Vault URI: ${KV_URI}"
```

### 10b. Grant yourself and the Admin group Key Vault Secrets Officer

```bash
az role assignment create \
  --assignee-object-id "${CURRENT_USER_OID}" \
  --assignee-principal-type User \
  --role "Key Vault Secrets Officer" \
  --scope "${RG_ID}"

az role assignment create \
  --assignee-object-id "${GROUP_ADMIN_ID}" \
  --assignee-principal-type Group \
  --role "Key Vault Secrets Officer" \
  --scope "${RG_ID}"

echo "Waiting 15 seconds for RBAC to propagate..."
sleep 15
```

### 10c. Store the service principal secret in Key Vault

```bash
SECRET_NAME="neologik-deployment-service-principle-secret"

# Retry loop to handle RBAC propagation delay
for attempt in {1..10}; do
  az keyvault secret set \
    --vault-name "${KV_NAME}" \
    --name "${SECRET_NAME}" \
    --value "${CLIENT_SECRET}" && break
  echo "Attempt ${attempt} failed — retrying in 10 seconds..."
  sleep 10
done

echo "Secret stored: ${KV_URI}secrets/${SECRET_NAME}"

# Clear the secret from the shell variable after storing
unset CLIENT_SECRET
```

---

## Step 11 — Create Storage Account

### 11a. Create the account

```bash
az storage account create \
  --name "${SA_NAME}" \
  --resource-group "${RG_NAME}" \
  --location "${REGION}" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access false \
  --allow-shared-key-access false

SA_BLOB_ENDPOINT=$(az storage account show \
  --name "${SA_NAME}" \
  --resource-group "${RG_NAME}" \
  --query primaryEndpoints.blob -o tsv)
SA_ID=$(az storage account show \
  --name "${SA_NAME}" \
  --resource-group "${RG_NAME}" \
  --query id -o tsv)

echo "Blob endpoint: ${SA_BLOB_ENDPOINT}"
```

### 11b. Grant yourself and the Admin group Storage Blob Data Contributor

```bash
az role assignment create \
  --assignee-object-id "${CURRENT_USER_OID}" \
  --assignee-principal-type User \
  --role "Storage Blob Data Contributor" \
  --scope "${RG_ID}"

az role assignment create \
  --assignee-object-id "${GROUP_ADMIN_ID}" \
  --assignee-principal-type Group \
  --role "Storage Blob Data Contributor" \
  --scope "${RG_ID}"

echo "Waiting 15 seconds for RBAC to propagate..."
sleep 15
```

### 11c. Create blob containers

```bash
for CONTAINER in certificate json logs; do
  az storage container create \
    --name "${CONTAINER}" \
    --account-name "${SA_NAME}" \
    --auth-mode login \
    --public-access off
  echo "Container created: ${CONTAINER}"
done
```

---

## Step 12 — Create Managed Identities

### 12a. Script Runner Service Connection identity

```bash
MI_RUNNER_RESULT=$(az identity create \
  --name "${MI_RUNNER_NAME}" \
  --resource-group "${RG_NAME}" \
  --location "${REGION}")

MI_RUNNER_PRINCIPAL_ID=$(echo "${MI_RUNNER_RESULT}" | jq -r '.principalId')
MI_RUNNER_CLIENT_ID=$(echo "${MI_RUNNER_RESULT}" | jq -r '.clientId')
MI_RUNNER_ID=$(echo "${MI_RUNNER_RESULT}" | jq -r '.id')

echo "Script Runner Principal ID: ${MI_RUNNER_PRINCIPAL_ID}"
echo "Script Runner Client ID:    ${MI_RUNNER_CLIENT_ID}"
```

**Assign Contributor at subscription level:**

```bash
# Wait for identity to replicate before assigning
sleep 15

for attempt in {1..10}; do
  az role assignment create \
    --assignee-object-id "${MI_RUNNER_PRINCIPAL_ID}" \
    --assignee-principal-type ServicePrincipal \
    --role "Contributor" \
    --scope "/subscriptions/${SUBSCRIPTION_ID}" && break
  echo "Attempt ${attempt} failed — retrying in 10 seconds..."
  sleep 10
done
```

**Assign Application Administrator directory role:**

```bash
for attempt in {1..10}; do
  az rest \
    --method POST \
    --url "https://graph.microsoft.com/v1.0/directoryRoles/${APP_ADMIN_ROLE_ID}/members/\$ref" \
    --body "{\"@odata.id\": \"https://graph.microsoft.com/v1.0/directoryObjects/${MI_RUNNER_PRINCIPAL_ID}\"}" && break
  echo "Attempt ${attempt} failed — retrying in 10 seconds..."
  sleep 10
done
```

### 12b. SQL Managed Identity

```bash
MI_SQL_RESULT=$(az identity create \
  --name "${MI_SQL_NAME}" \
  --resource-group "${RG_NAME}" \
  --location "${REGION}")

MI_SQL_PRINCIPAL_ID=$(echo "${MI_SQL_RESULT}" | jq -r '.principalId')
MI_SQL_CLIENT_ID=$(echo "${MI_SQL_RESULT}" | jq -r '.clientId')
MI_SQL_ID=$(echo "${MI_SQL_RESULT}" | jq -r '.id')

echo "SQL MI Principal ID: ${MI_SQL_PRINCIPAL_ID}"
echo "SQL MI Client ID:    ${MI_SQL_CLIENT_ID}"
```

**Assign Directory Readers directory role:**

```bash
# Get or activate Directory Readers role
DIR_READERS_ROLE_ID=$(az rest \
  --method GET \
  --url "https://graph.microsoft.com/v1.0/directoryRoles" \
  --query "value[?displayName=='Directory Readers'].id" -o tsv)

if [[ -z "${DIR_READERS_ROLE_ID}" ]]; then
  DR_TEMPLATE_ID=$(az rest \
    --method GET \
    --url "https://graph.microsoft.com/v1.0/directoryRoleTemplates" \
    --query "value[?displayName=='Directory Readers'].id" -o tsv)

  DIR_READERS_ROLE_ID=$(az rest \
    --method POST \
    --url "https://graph.microsoft.com/v1.0/directoryRoles" \
    --body "{\"roleTemplateId\": \"${DR_TEMPLATE_ID}\"}" \
    --query id -o tsv)
fi

sleep 15

for attempt in {1..10}; do
  az rest \
    --method POST \
    --url "https://graph.microsoft.com/v1.0/directoryRoles/${DIR_READERS_ROLE_ID}/members/\$ref" \
    --body "{\"@odata.id\": \"https://graph.microsoft.com/v1.0/directoryObjects/${MI_SQL_PRINCIPAL_ID}\"}" && break
  echo "Attempt ${attempt} failed — retrying in 10 seconds..."
  sleep 10
done
```

---

## Step 13 — Export Configuration File

Generate the configuration JSON and upload it to the storage account. Share this file with Neologik (support@neologik.ai) to proceed with deployment.

```bash
TIMESTAMP=$(date -u +"%Y%m%d_%H%M%S")
CONFIG_FILE="NeologikConfiguration_${TIMESTAMP}.json"
SOLUTION_NAME="neo-${ORG_ENV}-${REGION_SHORT}-${ENV_INDEX}"
SOLUTION_SHORT="neo${ORG_ENV}${REGION_SHORT}${ENV_INDEX}"

# Build bot array
BOTS_JSON="["
for i in "${!BOT_NAMES[@]}"; do
  [[ $i -gt 0 ]] && BOTS_JSON+=","
  BOTS_JSON+="{\"shortName\": \"${BOT_NAMES[$i]}\", \"agentName\": \"${BOT_AGENT_NAMES[$i]}\"}"
done
BOTS_JSON+="]"

# Build invited guest array
GUESTS_JSON="["
FIRST=true
for EMAIL in "${GUEST_EMAILS[@]}"; do
  [[ "${FIRST}" == "false" ]] && GUESTS_JSON+=","
  GUESTS_JSON+="{\"email\": \"${EMAIL}\", \"objectId\": \"${GUEST_USER_IDS[${EMAIL}]}\"}"
  FIRST=false
done
GUESTS_JSON+="]"

cat > "${CONFIG_FILE}" <<EOF
{
  "ScriptVersion": "manual-1.0",
  "GeneratedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "OrganizationName": "${ORG_NAME}",
  "OrganizationCode": "${ORG_CODE}",
  "TenantId": "${TENANT_ID}",
  "SubscriptionName": "${SUBSCRIPTION_NAME}",
  "SubscriptionId": "${SUBSCRIPTION_ID}",
  "ResourceGroupName": "${RG_NAME}",
  "SolutionName": "${SOLUTION_NAME}",
  "SolutionShortName": "${SOLUTION_SHORT}",
  "AzureRegion": "${REGION}",
  "Hostname": "${BOT_HOSTNAME}",
  "DomainName": "${BOT_DOMAIN}",
  "BotCount": ${#BOT_NAMES[@]},
  "Bots": ${BOTS_JSON},
  "InvitedGuestUsers": ${GUESTS_JSON},
  "SecurityGroups": [
    { "Name": "${GROUP_ADMIN}", "Id": "${GROUP_ADMIN_ID}", "Description": "Users who will administer and support the resources" },
    { "Name": "${GROUP_NCE}", "Id": "${GROUP_NCE_ID}", "Description": "Users who need access to NCE web tool" }
  ],
  "AppRegistration": {
    "Name": "${APP_NAME}",
    "ClientId": "${APP_CLIENT_ID}",
    "ObjectId": "${APP_OBJECT_ID}",
    "ServicePrincipalId": "${SP_OBJECT_ID}",
    "SecretExpiry": "${SECRET_EXPIRY}",
    "SubscriptionRoles": ["Contributor", "User Access Administrator"],
    "EntraRole": "Application Administrator"
  },
  "KeyVault": {
    "Name": "${KV_NAME}",
    "ResourceId": "${KV_ID}",
    "VaultUri": "${KV_URI}",
    "SecretName": "${SECRET_NAME}"
  },
  "StorageAccount": {
    "Name": "${SA_NAME}",
    "ResourceId": "${SA_ID}",
    "BlobEndpoint": "${SA_BLOB_ENDPOINT}",
    "CertificateContainerName": "certificate",
    "JsonContainerName": "json",
    "LogsContainerName": "logs"
  },
  "ManagedIdentities": [
    {
      "Name": "${MI_RUNNER_NAME}",
      "PrincipalId": "${MI_RUNNER_PRINCIPAL_ID}",
      "ClientId": "${MI_RUNNER_CLIENT_ID}",
      "ResourceId": "${MI_RUNNER_ID}",
      "SubscriptionRoles": ["Contributor"],
      "EntraRole": "Application Administrator"
    },
    {
      "Name": "${MI_SQL_NAME}",
      "PrincipalId": "${MI_SQL_PRINCIPAL_ID}",
      "ClientId": "${MI_SQL_CLIENT_ID}",
      "ResourceId": "${MI_SQL_ID}",
      "SubscriptionRoles": [],
      "EntraRole": "Directory Readers"
    }
  ]
}
EOF

echo "Config written: ${CONFIG_FILE}"
```

Upload to storage:

```bash
az storage blob upload \
  --account-name "${SA_NAME}" \
  --container-name "json" \
  --name "${CONFIG_FILE}" \
  --file "${CONFIG_FILE}" \
  --auth-mode login

echo "Uploaded to: ${SA_BLOB_ENDPOINT}json/${CONFIG_FILE}"
```

---

## Post-Onboarding Steps

After completing the steps above, the following actions are still required before Neologik can deploy your environment:

### 1. Share the configuration file
Send `NeologikConfiguration_[timestamp].json` to **support@neologik.ai**.

### 2. Decide on a hostname
Confirm your fully qualified bot domain name (FQDN), e.g. `app.yourcompany.com`, with Neologik before creating the TLS certificate.

### 3. Create a TLS certificate
Follow the **PFX-CERT-GUIDE.md** to obtain a `.pfx` certificate file (self-signed or from a CA).

### 4. Upload the certificate

```bash
az storage blob upload \
  --account-name "${SA_NAME}" \
  --container-name "certificate" \
  --name "certificate.pfx" \
  --file "/path/to/your/certificate.pfx" \
  --auth-mode login
```

### 5. Store the certificate password in Key Vault

```bash
az keyvault secret set \
  --vault-name "${KV_NAME}" \
  --name "neologik-deployment-certificate-pfx-secret" \
  --value "<your-pfx-password>"
```

### 6. Notify Neologik
Once all five steps above are complete, contact Neologik to begin the deployment.

---

## Troubleshooting

**Role assignments fail with "PrincipalNotFound"**
Entra ID group/identity replication can lag by 30–60 seconds. Wait and retry:
```bash
sleep 30 && az role assignment create ...
```

**Key Vault secret set fails with "403 Forbidden"**
RBAC propagation takes up to 15–30 seconds after `az role assignment create`. Wait and retry:
```bash
sleep 30 && az keyvault secret set ...
```

**Storage container creation fails with "AuthorizationPermissionMismatch"**
Storage Blob Data Contributor role has not propagated. Wait and retry:
```bash
sleep 30 && az storage container create ...
```

**Guest invitation fails**
The user may already exist in your tenant under a different UPN. Check:
```bash
az rest --method GET \
  --url "https://graph.microsoft.com/v1.0/users?\$filter=mail eq '${EMAIL}'" \
  --query "value[].{id:id, upn:userPrincipalName}"
```
