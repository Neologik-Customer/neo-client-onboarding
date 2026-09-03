# Neologik Onboarding Script — `Install-NeologikEnvironment.ps1`

**Version:** v5.0.0 · **Requires:** PowerShell 7.4+, operator with **Subscription Owner** + **Entra Global Administrator**

An idempotent, checkpoint-resumable PowerShell script that provisions a customer's Azure environment as stage one of onboarding. It authenticates the operator, validates permissions and quota, creates all foundational Azure/Entra resources, then exports a config JSON (`Neologik_<org><index>_Configuration_<timestamp>.json`) consumed by the deployment pipelines. Central design principle: **least-privilege, resource-group-scoped grants** — nothing the pipeline runs afterward needs standing subscription-level resource-write rights.

## Flow

Runs ordered steps (`Start-NeologikOnboarding`), checkpointing to `NeologikCheckpoint.json` after each. A failure exits `2` (permissions) or `1` (other) and preserves the checkpoint; re-running offers resume. On success the checkpoint is deleted. A pre-flight step also warns (non-fatally) on insufficient vCPU or Azure OpenAI `gpt-5.4-mini` quota in the target region. Prompts can be pre-filled from an answer file (`inputs.json`), and `-NonInteractive` runs fully unattended for CI (caller pre-establishes the Az/Graph contexts; Terms acknowledged with `-AcceptTerms`).

## Permission validation

Up-front, before any prompts (`Test-RequiredPermissions`):

- **Subscription Owner** — verified via `Get-AzRoleAssignment`. Missing → hard fail.
- **Global Administrator** — verified via Graph directory-role membership. If the *check itself* can't run (e.g. Graph token error), membership is unknown and the operator is prompted to proceed at their own risk. Graph app-role grants additionally need Privileged Role Administrator or Global Administrator.

## What it creates

| Resource | Notes |
|---|---|
| Resource group | Pre-created here so the pipeline never needs subscription scope |
| Security groups | Four: *Neologik User Group* (default agent-channel access), *Neologik NCE Contributors*, *Neologik NCE Admins*, *Neologik Admin User Group* — each suffixed `- <short name>`, seeded with operator + invited guests |
| Guest user invitations | From `NeologikGuestUsers.txt`; skippable (`-SkipGuestInvitation`) when the client provisions accounts in its own tenant; pre-existing accounts with matching mail/UPN are reused |
| App registration + SP | Deployment identity (`Neologik GitHub Service Connection - <short name>`); added to Admin group. Alternatively reuses a **client-provided** SP (object ID supplied) and just assigns the roles |
| Platform Sign-in app | `Neologik Platform Sign-in - <short name>` (NCE/App portal login); secret in Key Vault, deployment SP as owner, NCE Contributors + Admins groups assigned for the groups claim |
| Key Vault | `kvneo<org><index>` by default (overridable); stores the SP and Sign-in client secrets |
| Storage account + blob containers | `certificate` (TLS cert), `json` (config handoff), `logs` |
| Managed identities | Script Runner Service Connection; SQL Managed Identity (names suffixed `-<short name>`, overridable) |
| Azure resource providers | Registered subscription-wide |
| Config export | `Neologik_<org><index>_Configuration_<timestamp>.json` handoff artifact (also uploaded to the `json` container in interactive runs) |

Naming: all names derive from two tokens — solution name `neo-<org><env>-<region>-<index>` and short name `<org><env><index>`. Every computed name is overridable from `inputs.json` for client-mandated naming conventions.

## Azure access it grants

All grants are **resource-group-scoped** unless noted. The pipeline SP holds two subscription-scoped roles — read-only **Reader** and cost-configuration-only **Cost Management Contributor** — and no subscription-scoped resource-write roles; the admin group holds none.

| Principal | Scope | Roles |
|---|---|---|
| **Deployment SP** (app reg) | Subscription | Reader (SKU/quota pre-flight reads) · Cost Management Contributor (the deployment pipeline creates and maintains the subscription-scoped cost report emails — cost configuration only, no resource control) |
| **Deployment SP** (app reg) | Resource group | Contributor · Key Vault Certificates Officer · Key Vault Secrets Officer · Storage Blob Data Contributor · AKS RBAC Cluster Admin · Monitoring Contributor · **Role Based Access Control Administrator** |
| **Deployment SP** | Entra / Graph | `Application.ReadWrite.OwnedBy` (manage only the app registrations it owns; replaces tenant-wide *Application Administrator*) · `AgentIdentityBlueprint.AddRemoveCreds.All` (add the per-agent Kubernetes credentials to the agent identity blueprint - the one residual tenant-wide Agent ID role, no ownership-scoped variant exists). No other Agent ID role: the blueprint itself mints agent identities and users (its principal holds `AgentIdUser.ReadWrite.IdentityParentedBy`; the pipeline acts as the blueprint via GitHub OIDC). No group-management permission — the platform never creates Entra groups |
| **Admin User Group** | Resource group | Contributor · AKS Cluster Admin Role · AKS RBAC Cluster Admin · Key Vault Administrator · Storage Blob Data Owner · Storage Table Data Contributor · Cognitive Services Data Reader · Cognitive Services OpenAI Contributor · Search Index Data Reader · Azure AI Developer |
| **Script Runner MI** | Subscription | Contributor |
| **Script Runner MI** | Resource group | Key Vault Secrets Officer · Azure Bot Service Contributor Role |
| **SQL MI** | Entra | Directory Readers (directory role) |

Notes:

- `Role Based Access Control Administrator` replaces legacy sub-scoped *User Access Administrator* — it grants `roleAssignments/write` so deployment Bicep can create in-template assignments (kubelet Managed Identity Operator, workload-identity, kubelet AcrPull) without deny-assignment powers.
- `Application.ReadWrite.OwnedBy` only manages apps the SP **owns**, so secret-rotation flows must first register the identity as owner (the script registers the deployment SP as owner of the Platform Sign-in app).
- If the environment uses a **shared** container-registry RG, the kubelet AcrPull assignment lands there and needs a separate one-time RBAC Administrator grant on that RG.

## Key parameters

`OrganizationCode` (3 chars) · `EnvironmentType` (`dev`/`prd`; `dmo`/`test`/`stg` accepted but undocumented; never used in names) · `AzureRegion` (`uksouth`) · `TenantId` · `SubscriptionName` · `KeyVaultName` · `SkipPowerShellUpdate` · `SkipModuleInstall` · `SkipGuestInvitation` · `ExistingServicePrincipalObjectId` / `ExistingServicePrincipalSecret` · `AnswerFile` · `NonInteractive` · `AcceptTerms` · `FreshRun`
