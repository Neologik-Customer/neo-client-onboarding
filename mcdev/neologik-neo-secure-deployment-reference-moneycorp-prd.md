# Neologik neo-secure Deployment Reference — Moneycorp Production

Complete documentation for the **neo-secure** deployment in the **Moneycorp Production** environment.

## Table of Contents

- [Environment Identity](#environment-identity)
- [Overview](#overview)
- [Deployment Characteristics](#deployment-characteristics)
- [Azure Resources](#azure-resources)
  - [Networking Resources](#networking-resources)
  - [Compute Resources](#compute-resources)
  - [Storage Resources](#storage-resources)
  - [Database Resources](#database-resources)
  - [AI and Cognitive Services](#ai-and-cognitive-services)
  - [Security and Identity](#security-and-identity)
  - [Monitoring and Logging](#monitoring-and-logging)
  - [Automation Resources](#automation-resources)
- [Microsoft Entra ID Resources](#microsoft-entra-id-resources)
- [Role-Based Access Control (RBAC)](#role-based-access-control-rbac)
- [Private Endpoints and DNS](#private-endpoints-and-dns)
- [Naming Standards](#naming-standards)
- [Deployment Sequence](#deployment-sequence)
- [Cost Estimate](#cost-estimate)

---

## Environment Identity

| Field | Value |
|-------|-------|
| **Tenant Name** | moneycorp |
| **Tenant ID** | `234b7362-627a-4a31-9a1f-d340c11da1e0` |
| **Tenant Domain** | `moneycorp.local` |
| **Subscription Name** | Moneycorp UK Neologik-Production-1 *(TBD)* |
| **Subscription ID** | *(TBD — dedicated production subscription)* |
| **Resource Group** | `rg-neo-mcprd-uks-1` |
| **Location** | UK South (`uksouth`) |
| **Solution Name** | `neo-mcprd-uks-1` |
| **Solution Short Name** | `neomcprduks1` |

---

## Overview

The **neo-secure** deployment template is designed for:
- **Production environments** requiring network isolation
- **Security-focused deployments** with private endpoints
- **Compliance requirements** (data residency, network segmentation)
- **Enterprise-grade infrastructure** with management VMs and Bastion

This document reflects the **Moneycorp Production** instantiation of the neo-secure template, deployed in UK South.

**File**: `bicep/neo-secure.bicep`

---

## Deployment Characteristics

| Feature | Configuration |
|---------|---------------|
| **Network Access** | Private (via Private Endpoints) |
| **Private Endpoints** | ✅ Yes (~24 endpoints for all PaaS services) |
| **Azure Bastion** | ✅ Yes (Basic SKU) |
| **Jumpbox VM** | ✅ Yes (Windows Server) |
| **GitHub Runner VM** | ✅ Yes (Ubuntu) |
| **AKS Cluster Type** | Private |
| **AKS SKU Tier** | **Standard** |
| **Ingress** | **Application Gateway for Containers (AGC) with WAF v2** |
| **Container Registry SKU** | Premium (supports private endpoints) |
| **Log Retention** | 90 days |
| **Cosmos DB Failover** | Enabled |
| **Key Vault Public Access** | Disabled (after deployment) |
| **SQL Database Access** | Private Endpoint only |
| **SQL Authentication** | Microsoft Entra ID only |
| **Storage Account Access** | Private (Network Deny default) |
| **Monitoring Stack** | ✅ Fully enabled (alerts, action groups, cost budgets) |
| **AKS Start/Stop Automation** | ❌ No (always-on) |

---

## Azure Resources

### Networking Resources

#### Virtual Network (VNet)
- **Resource Type**: `Microsoft.Network/virtualNetworks`
- **Name**: `vnet-neo-mcprd-uks-1`
- **Address Space**: `10.0.0.0/8`
- **Module**: `modVnet.bicep`

##### Subnets

| Subnet Name | Address Prefix | Purpose | Delegations | NAT Gateway |
|-------------|----------------|---------|-------------|-------------|
| `systempoolnodesubnet` | `10.200.0.0/16` | AKS system nodes | None | ✅ Yes |
| `systempoolpodsubnet` | `10.201.0.0/16` | AKS system pods | Microsoft.ContainerService/managedClusters | ✅ Yes |
| `userpool1nodesubnet` | `10.202.0.0/16` | AKS user nodes | None | ✅ Yes |
| `userpool1podsubnet` | `10.203.0.0/16` | AKS user pods | Microsoft.ContainerService/managedClusters | ✅ Yes |
| `AzureBastionSubnet` | `10.253.0.0/16` | Azure Bastion | None | ❌ No |
| `PrivateEndpointSubnet` | `10.220.0.0/16` | Private Endpoints | None | ❌ No |
| `AppSubnet` | `10.205.0.0/16` | Container Apps | Microsoft.App/environments | ✅ Yes |
| `VmSubnet` | `10.252.0.0/16` | Virtual Machines | None | ✅ Yes |
| `AiServiceSubnet` | `10.206.0.0/16` | AI Services (VNet integration) | None | ✅ Yes |
| `ApplicationGatewayForContainersSubnet` | `10.254.0.0/16` | AGC Traffic Controller | Microsoft.ServiceNetworking/trafficControllers | ❌ No |

#### NAT Gateway
- **Resource Type**: `Microsoft.Network/natGateways`
- **Name**: `natgw-neo-mcprd-uks-1`
- **SKU**: Standard
- **Public IP**: `natgw-neo-mcprd-uks-1-pip`
- **Settings**:
  - Idle Timeout: 4 minutes
  - Public IP SKU: Standard
  - Public IP Allocation: Static
- **Purpose**: Outbound internet connectivity for AKS nodes and VMs
- **Diagnostic Settings**: Enabled (sends logs to Log Analytics)

#### Network Security Groups

##### Bastion NSG
- **Resource Type**: `Microsoft.Network/networkSecurityGroups`
- **Name**: `bastion-neo-mcprd-uks-1-nsg`
- **Module**: `modBastionNsg.bicep`
- **Applied To**: `AzureBastionSubnet`

##### Bastion NSG Rules (Inbound)
| Priority | Name | Source | Destination | Protocol | Port | Action |
|----------|------|--------|-------------|----------|------|--------|
| 100 | Allow-HTTPS-Inbound | Internet | * | TCP | 443 | Allow |
| 110 | Allow-GatewayManager | GatewayManager | * | TCP | 443 | Allow |
| 120 | Allow-AzureLoadBalancer | AzureLoadBalancer | * | TCP | 443 | Allow |
| 130 | Allow-BastionHostCommunication | VirtualNetwork | VirtualNetwork | * | 8080, 5701 | Allow |

##### Bastion NSG Rules (Outbound)
| Priority | Name | Destination | Protocol | Port | Action |
|----------|------|-------------|----------|------|--------|
| 100 | Allow-RDP-SSH-Outbound | VirtualNetwork | TCP | 22, 3389 | Allow |
| 110 | Allow-AzureCloud | AzureCloud | TCP | 443 | Allow |
| 120 | Allow-BastionHostCommunication | VirtualNetwork | * | 8080, 5701 | Allow |
| 130 | Allow-GetSessionInformation | Internet | * | 80, 443 | Allow |

#### Private DNS Zones
- **Resource Type**: `Microsoft.Network/privateDnsZones`
- **Location**: Global
- **VNet Links**: All zones linked to `vnet-neo-mcprd-uks-1`

| DNS Zone | Purpose | Resource Type |
|----------|---------|---------------|
| `privatelink.vaultcore.azure.net` | Key Vault | Microsoft.KeyVault/vaults |
| `privatelink.blob.core.windows.net` | Storage (Blob) | Microsoft.Storage/storageAccounts |
| `privatelink.file.core.windows.net` | Storage (File) | Microsoft.Storage/storageAccounts |
| `privatelink.table.core.windows.net` | Storage (Table) | Microsoft.Storage/storageAccounts |
| `privatelink.queue.core.windows.net` | Storage (Queue) | Microsoft.Storage/storageAccounts |
| `privatelink.cognitiveservices.azure.com` | AI Services | Microsoft.CognitiveServices/accounts |
| `privatelink.openai.azure.com` | Azure OpenAI | Microsoft.CognitiveServices/accounts (OpenAI) |
| `privatelink.documents.azure.com` | Cosmos DB | Microsoft.DocumentDB/databaseAccounts |
| `privatelink.azurecr.io` | Container Registry | Microsoft.ContainerRegistry/registries |
| `privatelink.search.windows.net` | AI Search | Microsoft.Search/searchServices |
| `privatelink.azurewebsites.net` | Web Apps | Microsoft.Web/sites |
| `privatelink.database.windows.net` | SQL Server | Microsoft.Sql/servers |

**DNS Resolution Flow**:
```
VM/AKS Pod → Private DNS Zone → Private Endpoint IP → Azure Service
```

---

### Compute Resources

#### Azure Kubernetes Service (AKS)
- **Resource Type**: `Microsoft.ContainerService/managedClusters`
- **Name**: `aksneomcprduks1`
- **Module**: `modAks.bicep`

##### AKS Configuration
| Setting | Value |
|---------|-------|
| **Cluster Type** | **Private** |
| **SKU Tier** | **Standard** |
| **Kubernetes Version** | Configurable (param) |
| **Network Plugin** | Azure CNI |
| **Network Policy** | Azure |
| **Service CIDR** | `10.210.0.0/16` |
| **DNS Service IP** | `10.210.0.10` |
| **Private Cluster** | ✅ **Yes** |
| **Private DNS Zone** | System (auto-created by Azure) |
| **MC Resource Group** | `MC_rg-neo-mcprd-uks-1_aksneomcprduks1_uksouth` |

##### Node Pools

1. **System Pool** (`systempool`)
   - VM Size: `Standard_D2s_v5`
   - Autoscaler: Min **2**, Max **5**
   - Node Subnet: `systempoolnodesubnet`
   - Pod Subnet: `systempoolpodsubnet`
   - Node Taints: `CriticalAddonsOnly=true:NoSchedule`
   - Purpose: System workloads (CoreDNS, metrics-server, etc.)

2. **User Pool 1** (`userpool1`)
   - VM Size: `Standard_E2s_v6`
   - Autoscaler: Min **2**, Max **6**
   - Node Subnet: `userpool1nodesubnet`
   - Pod Subnet: `userpool1podsubnet`
   - Spot Instances: Optional (param: `paramEnableSpotUserPool1`)
   - Purpose: Application workloads

##### Private Cluster Access
- **API Server**: Only accessible from VNet (private IP)
- **Management**: Requires Jumpbox VM or Azure Bastion connection
- **kubectl Access**: Must be from within VNet or via VPN/ExpressRoute

##### AKS Add-ons and Features
- ✅ **Azure Key Vault Secrets Provider**: Enabled
- ✅ **Azure Monitor**: Enabled (Container Insights) → `log-neo-mcprd-uks-1`
- ✅ **Web Application Routing**: Enabled (nginx-based ingress)
- ✅ **Workload Identity**: Enabled (for pod-to-Azure auth)
- ✅ **OIDC Issuer**: Enabled
- ⚙️ **Azure Policy**: Configurable
- ✅ **Defender for Containers**: Optional

##### AKS Logging Configuration
- **Syslog Levels**: Debug, Info, Notice, Warning, Error, Critical, Alert, Emergency
- **Data Collection Interval**: 5 minutes
- **Container Logs**: ContainerLogV2 enabled
- **Streams**: Container logs, Kube events, pod/node/PV inventory, services, metrics, perf

##### AKS SSH Access
- **SSH Key Generation**: Automated via deployment script
- **Key Storage**: Key Vault secrets (`aksneomcprduks1-ssh-private-key`, `aksneomcprduks1-ssh-public-key`)
- **Module**: `modAksSshKeyGeneration.bicep`

#### Jumpbox VM (Windows Server)
- **Resource Type**: `Microsoft.Compute/virtualMachines`
- **Name**: `vmjneomcprduks1`
- **Module**: `modVmJumpbox.bicep`

##### Configuration
| Setting | Value |
|---------|-------|
| **OS** | Windows Server (latest) |
| **VM Size** | `Standard_D2s_v5` |
| **Public IP** | **No** |
| **Spot Instance** | Optional (param: `paramEnableSpotVmJumpbox`) |
| **Subnet** | `VmSubnet` |
| **Access** | Via Azure Bastion only |

##### VM Extensions
1. **Azure Monitor Agent**: Collects logs and metrics
2. **Custom Script Extension**:
   - Generates random admin password
   - Stores password in Key Vault
   - Key Vault secret: `vmjneomcprduks1-admin-password`

##### Software Pre-installed
- Windows Remote Desktop enabled
- Azure CLI
- PowerShell 7
- kubectl (for AKS management)

#### GitHub Runner VM (Ubuntu)
- **Resource Type**: `Microsoft.Compute/virtualMachines`
- **Name**: `vmrunnerneomcprduks1`
- **Module**: `modVmGitHubRunner.bicep`

##### Configuration
| Setting | Value |
|---------|-------|
| **OS** | Ubuntu 22.04 LTS (Jammy) |
| **VM Size** | `Standard_D2s_v5` |
| **Spot Instance** | Optional (param: `paramEnableSpotVmGitHubRunner`) |
| **Subnet** | `VmSubnet` |
| **Public IP** | **No** |
| **Identity** | User-Assigned Managed Identity |

##### VM Extensions
1. **Azure Monitor Agent**: Metrics and logs collection
2. **Custom Script Extension**: Installs and registers GitHub Actions Runner

##### GitHub Runner Configuration
- **Organization**: `Neologik-AI`
- **Runner Name**: Configurable (param: `paramGitHubRunnerName`)
- **Labels**: Configurable (param: `paramGitHubRunnerLabels`)
- **Registration Token**: Secure parameter (param: `paramGitHubToken`)

**Purpose**: Self-hosted runner for GitHub Actions workflows requiring private AKS/Azure access

#### Azure Bastion
- **Resource Type**: `Microsoft.Network/bastionHosts`
- **Name**: `bas-neo-mcprd-uks-1`
- **Public IP**: `bastion-neo-mcprd-uks-1-pip`
- **Module**: `modBastion.bicep`

##### Configuration
| Setting | Value |
|---------|-------|
| **SKU** | Basic |
| **Subnet** | `AzureBastionSubnet` (dedicated) |
| **Public IP** | `bastion-neo-mcprd-uks-1-pip` |
| **Concurrent Sessions** | 25 |
| **Features** | RDP and SSH tunneling via Azure Portal |

**Access Pattern**:
```
User → Azure Portal/CLI → Bastion (Public IP) → VM (Private IP)
```

#### Ingress Controller — Application Gateway for Containers (AGC)

##### Application Gateway for Containers
- **Resource Type**: `Microsoft.ServiceNetworking/trafficControllers`
- **Name**: `agc-neo-mcprd-uks-1`
- **Deployment**: Via application repository workflow
- **Repository**: `Neologik-AI/neo-aks-ingress`
- **Workflow**: `.github/workflows/neo-ingress-deployment.yml`

> **Note**: AGC is **not** deployed via the infrastructure Bicep template. The `ApplicationGatewayForContainersSubnet` is provisioned by infrastructure, and the AGC resource itself is deployed from the `neo-aks-ingress` application repository.

##### AGC Configuration
| Setting | Value |
|---------|-------|
| **Subnet** | `ApplicationGatewayForContainersSubnet` (`10.254.0.0/16`) |
| **Subnet Delegation** | `Microsoft.ServiceNetworking/trafficControllers` |
| **Association** | AGC subnet association |
| **ALB Controller Version** | 1.8.12 (Helm) |
| **ALB Controller Namespace** | `azure-alb-system` |

##### WAF Policy
- **Resource Type**: `Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies`
- **Name**: `waf-agc-neo-mcprd-uks-1`
- **Managed Rules**: Microsoft_DefaultRuleSet 2.1
- **Mode**: Prevention
- **Location**: UK South

##### AGC Components

1. **AGC Resource**
   - Created in `rg-neo-mcprd-uks-1`
   - Associated with `ApplicationGatewayForContainersSubnet`
   - Managed by ALB Controller (installed via Helm in AKS)

2. **ALB Controller Identity**
   - **Name**: `azure-alb-identity`
   - **Type**: User-Assigned Managed Identity
   - **Federated Credential**: Linked to `aksneomcprduks1` OIDC issuer
   - **Kubernetes Service Account**: `alb-controller-sa` (azure-alb-system namespace)

3. **Gateway API CRDs**
   - Version: v1.0.0
   - Standard CRDs installed in AKS cluster
   - Enables Gateway and HTTPRoute Kubernetes resources

##### ALB Controller Identity RBAC

| Role | Role ID | Scope | Purpose |
|------|---------|-------|---------|
| **Reader** | acdd72a7-3385-48ef-bd42-f606fba81ae7 | Subscription | Read subscription resources |
| **AppGw for Containers Configuration Manager** | fbc52c3f-28ad-4303-a892-8a056630b8f1 | `rg-neo-mcprd-uks-1` | Manage AGC configuration |
| **AppGw for Containers Configuration Manager** | fbc52c3f-28ad-4303-a892-8a056630b8f1 | MC Resource Group | Manage AGC in node resource group |
| **Network Contributor** | 4d97b98b-1d4f-4787-a291-c67834d212e7 | AGC Subnet | Manage network resources in AGC subnet |

##### Federated Credential
- **Issuer**: `aksneomcprduks1` OIDC issuer URL
- **Subject**: `system:serviceaccount:azure-alb-system:alb-controller-sa`
- **Namespace**: `azure-alb-system`
- **Service Account**: `alb-controller-sa`

---

### Storage Resources

#### Container Registry
- **Resource Type**: `Microsoft.ContainerRegistry/registries`
- **Name**: `crneomcprduks1`
- **Module**: `modContainerRegistry.bicep`
- **SKU**: **Premium** (required for private endpoints)
- **Admin User**: **Disabled**
- **Public Network Access**: **Disabled**
- **Private Endpoint**: ✅ Yes
- **Diagnostic Settings**: Enabled

#### Storage Accounts

All storage accounts use Zone-Redundant Storage (ZRS) and private endpoints.

##### Common Settings
| Setting | Value |
|---------|-------|
| **SKU** | Standard_ZRS |
| **Public Network Access** | **Disabled** |
| **Network Default Action** | **Deny** |
| **Azure Services Bypass** | Enabled |
| **Private Endpoints** | blob, file, table, queue (4 per account) |
| **Connection String Storage** | Key Vault secrets |

##### 1. RAG Storage Account
- **Name**: `stfilesneomcprduks1`
- **Container**: `files`
- **Purpose**: RAG document storage
- **Private Endpoints**: 4 (blob, file, table, queue)

##### 2. Template Storage Account
- **Name**: `sttemplateneomcprduks1`
- **Container**: `templates`
- **Purpose**: Document template storage
- **Private Endpoints**: 4 (blob, file, table, queue)

##### 3. Output Storage Account
- **Name**: `stoutputneomcprduks1`
- **Container**: `output`
- **Purpose**: Processing output storage
- **Private Endpoints**: 4 (blob, file, table, queue)

**Total Storage Private Endpoints**: 12

---

### Database Resources

#### Cosmos DB (Chat History)
- **Resource Type**: `Microsoft.DocumentDB/databaseAccounts`
- **Name**: `cosmos-chat-history-neo-mcprd-uks-1`
- **Module**: `modCosmosDB.bicep`

##### Configuration
| Setting | Value |
|---------|-------|
| **Account Kind** | GlobalDocumentDB (SQL API) |
| **Consistency Level** | Session |
| **Capabilities** | EnableServerless |
| **Zone Redundancy** | ❌ Disabled |
| **Automatic Failover** | ✅ **Enabled** |
| **Public Network Access** | **Disabled** |
| **Private Endpoint** | ✅ Yes |
| **Verbose Logging** | ✅ Enabled (for security monitoring) |
| **Database Name** | `chathistorydb` |
| **Container Name** | `chat_history` |
| **Partition Key** | `/userId` |

#### Azure SQL Database
- **SQL Server**: `sql-main-neo-mcprd-uks-1`
- **SQL Database**: `sqldb-main-neo-mcprd-uks-1`
- **Module**: `modAzureSqlServerDatabase.bicep`

##### SQL Server Configuration
| Setting | Value |
|---------|-------|
| **Authentication** | **Microsoft Entra ID only** |
| **Admin Group** | Configurable (param: `paramSupportGroupUid`) |
| **Public Network Access** | **Disabled** |
| **Private Endpoint** | ✅ Yes |
| **TLS Version** | 1.2 minimum |
| **Identity** | User-Assigned Managed Identity |

##### SQL Database Configuration
| Setting | Value |
|---------|-------|
| **SKU** | GP_S_Gen5 (Serverless) |
| **Min Capacity** | 0.5 vCores |
| **Max Capacity** | 2 vCores |
| **Auto-pause Delay** | 60 minutes |
| **Backup Retention** | 7 days |

---

### AI and Cognitive Services

#### Azure OpenAI Service
- **Resource Type**: `Microsoft.CognitiveServices/accounts`
- **Kind**: OpenAI
- **Name**: `oai-neo-mcprd-uks-1`
- **Module**: `modOpenAi.bicep`
- **Identity**: System-Assigned Managed Identity
- **Public Network Access**: **Disabled**
- **Private Endpoint**: ✅ Yes

##### Model Deployments
All models are configurable via parameters:

1. **Language Model 1** (e.g., GPT-4.1)
   - Name: `paramGptLangModelName`
   - SKU: `paramGptLangModelSkuName`
   - Version: `paramGptLangModelVersion`
   - Capacity (TPM): `paramGptLangModelCapacity`

2. **Language Model 2** (e.g., GPT-4.1-mini)
   - Name: `paramGptLangModel2Name`
   - SKU: `paramGptLangModel2SkuName`
   - Version: `paramGptLangModel2Version`
   - Capacity (TPM): `paramGptLangModel2Capacity`

3. **Language Model 3** (e.g., GPT-4.1-nano)
   - Name: `paramGptLangModel3Name`
   - SKU: `paramGptLangModel3SkuName`
   - Version: `paramGptLangModel3Version`
   - Capacity (TPM): `paramGptLangModel3Capacity`

4. **Embedding Model** (e.g., text-embedding-3-large)
   - Name: `paramGptEmbeddingModelName`
   - SKU: `paramGptEmbeddingModelSkuName`
   - Version: `paramGptEmbeddingModelVersion`
   - Capacity (TPM): `paramGptEmbeddingModelCapacity`

**API Key**: Stored in Key Vault as `oai-neo-mcprd-uks-1-api-key`

#### Azure AI Search (Cognitive Search)
- **Resource Type**: `Microsoft.Search/searchServices`
- **Name**: `srch-neo-mcprd-uks-1`
- **Module**: `modAiSearchService.bicep`
- **Identity**: System-Assigned Managed Identity

##### Configuration
| Setting | Value |
|---------|-------|
| **SKU** | Standard |
| **Partition Count** | 1 (configurable) |
| **Replica Count** | 1 (configurable) |
| **Public Network Access** | **Disabled** |
| **Private Endpoint** | ✅ Yes |

**API Key**: Stored in Key Vault as `aisearch-api-key`

#### Azure AI Services (Multiservice)
- **Resource Type**: `Microsoft.CognitiveServices/accounts`
- **Kind**: AIServices
- **Name**: `ais-neo-mcprd-uks-1`
- **Module**: `modAiService.bicep`
- **Public Network Access**: **Disabled**
- **VNet Integration**: ✅ Yes (service endpoint on `AiServiceSubnet`)
- **Private Endpoint**: ✅ Yes

##### Network Configuration (Hybrid Approach)
- **Service Endpoint**: Attached to `AiServiceSubnet` (for VNet-level access)
- **Private Endpoint**: In `PrivateEndpointSubnet` (for DNS resolution)
- **Network ACLs**:
  - Default Action: **Deny**
  - VNet Rules: Allow `AiServiceSubnet`

#### Azure AI Foundry Project
- **Resource Type**: `Microsoft.CognitiveServices/accounts/projects`
- **Name**: `proj-neo-mcprd-uks-1`
- **Parent**: `ais-neo-mcprd-uks-1` (child resource — no separate private endpoint required)
- **Module**: `modFoundryProject.bicep`
- **Identity**: System-Assigned Managed Identity
- **Endpoint**: `https://ais-neo-mcprd-uks-1.services.ai.azure.com/api/projects/proj-neo-mcprd-uks-1`

> **New Foundry model**: The project is a lightweight child of the existing AIServices account — no hub, no dedicated storage, no `MachineLearningServices/workspaces`. There is no separate private endpoint; the project inherits network isolation from `ais-neo-mcprd-uks-1`.

##### Account-Level Connections (shared across all projects)
| Connection | Type | Auth | Module |
|------------|------|------|--------|
| `ais-neo-mcprd-uks-1-connection-AISearch` | CognitiveSearch | AAD | `modFoundryConnections.bicep` |

##### Environment Variables
| Variable | Value |
|----------|-------|
| `AZURE_AI_INFERENCE_ENDPOINT` | `https://ais-neo-mcprd-uks-1.services.ai.azure.com/api/projects/proj-neo-mcprd-uks-1` |
| `AZURE_OPENAI_ENDPOINT` | `https://oai-neo-mcprd-uks-1.openai.azure.com/` |

---

### Security and Identity

#### Key Vault (Two-Phase Deployment)
- **Resource Type**: `Microsoft.KeyVault/vaults`
- **Name**: `kvneomcprduks1`
- **Module**: `modKeyVault.bicep`

##### Phase 1: Initial Deployment (Public Access)
Deployed early in template with public access enabled for deployment scripts.

| Setting | Value |
|---------|-------|
| **SKU** | Standard |
| **RBAC Authorization** | ✅ Enabled |
| **Soft Delete Retention** | 90 days |
| **Public Network Access** | ✅ **Enabled** (temporarily) |
| **Network ACLs Default** | Allow |
| **Network ACLs Bypass** | AzureServices |
| **Private Endpoint** | ✅ Yes |

##### Phase 2: Security Update (Private Only)
Re-deployed at end of template (`modKeyVaultSecurityUpdate`) to lock down access.

| Setting | Value |
|---------|-------|
| **Public Network Access** | **Disabled** |
| **Network ACLs Default** | **Deny** |

**Deployment Sequence**:
```
1. Deploy Key Vault with public access
2. Run deployment scripts (SSH keys, service principals)
3. Deploy all other resources
4. Update Key Vault to disable public access
```

##### Secrets Stored
- Storage account connection strings (3 accounts: RAG, Template, Output)
- OpenAI API key (`oai-neo-mcprd-uks-1-api-key`)
- AI Search API key (`aisearch-api-key`)
- Bot service principal secrets (per bot)
- SharePoint service principal secret
- Admin authentication service principal secret
- AKS SSH keys (`aksneomcprduks1-ssh-private-key`, `aksneomcprduks1-ssh-public-key`)
- Jumpbox VM admin password (`vmjneomcprduks1-admin-password`)

#### User-Assigned Managed Identities

##### 1. Deployment Script UAMI
- **Name**: Configurable (param: `paramDeploymentScriptUamiName`)
- **Module**: `modUserAssignedManagedIdentity.bicep` (external, pre-deployment)
- **Purpose**: Execute deployment scripts (SSH key generation, Entra ID operations)

**Required Pre-deployment Permissions**:
- **Microsoft Graph**: Application.ReadWrite.All, Directory.ReadWrite.All
- **Key Vault**: Key Vault Secrets Officer

##### 2. AKS Cluster Identity
- **Name**: `idaksclusterneomcprduks1`
- **Purpose**: AKS control plane identity

##### 3. AKS Kubelet Identity
- **Name**: `idakskubeletneomcprduks1`
- **Purpose**: AKS node and pod identity

##### 4. SQL Server UAMI
- **Name**: Configurable (param: `paramSqlMainUamiName`)
- **Purpose**: SQL Server identity for Entra ID authentication
- **Required Pre-deployment Role**: Directory Reader (in `moneycorp.local` Entra ID)

##### 5. ALB Controller Identity (AGC)
- **Name**: `azure-alb-identity`
- **Purpose**: ALB Controller pod identity for AGC management
- **Deployed from**: `neo-aks-ingress` application repository

---

### Monitoring and Logging

#### Log Analytics Workspace
- **Resource Type**: `Microsoft.OperationalInsights/workspaces`
- **Name**: `log-neo-mcprd-uks-1`
- **Module**: `modLogAnalyticsWorksapce.bicep`
- **SKU**: PerGB2018
- **Retention**: **90 days** (extended for compliance)
- **Public Network Access**: ✅ Enabled (for ingestion and queries)

#### Application Insights
- **Resource Type**: `Microsoft.Insights/components`
- **Name**: `appi-aih-neo-mcprd-uks-1`
- **Module**: `modApplicationInsights.bicep`
- **Retention**: 90 days
- **Note**: Name retains `aih` prefix as a legacy label; this is the shared Application Insights instance used across the deployment (not hub-specific)

#### Azure Monitor Workspace (Prometheus)
- **Resource Type**: `Microsoft.Monitor/accounts`
- **Name**: `aksneomcprduks1-prometheus`
- **Module**: `modAksPrometheus.bicep`
- **Public Network Access**: **Disabled**

#### Full Monitoring Stack
**Module**: `modMonitoring.bicep`  
**Enabled**: ✅ **Yes**

##### 1. Action Groups (Notifications)
- **Critical**: `ag-critical-oncall` — Email + SMS for critical alerts
- **Team**: `ag-team-alerts` — Email + webhook for team notifications
- **Warning**: `ag-warning-digest` — Email for warning-level alerts

##### 2. Alert Rules
- Node health alerts (CPU, memory, disk, not ready)
- Pod health alerts (restarts, evictions, failed scheduling)
- AKS component alerts (CoreDNS, networking)
- Application log alerts (error count thresholds)
- OpenAI service alerts (token errors, throttling)

##### 3. Cost Budgets
- Monthly budget with threshold alerts (50%, 80%, 90%, 100%)
- Email notifications to configured addresses

---

### Automation Resources

#### Bot Service Resources

##### Bot Service Configuration
- **Resource Type**: `Microsoft.BotService/botServices`
- **Naming**: `bot{botShortName}neomcprduks1`
- **SKU**: S1 (Standard)
- **Messaging Endpoint**: `https://{paramHostName}/api/{botApiVersion}/{botShortName}/messages`

##### Multi-Bot Configuration
Up to 3 bots can be deployed per environment:

| Bot | Short Name Param | Long Name Param | Anonymous Web Param |
|-----|------------------|-----------------|---------------------|
| Bot 1 | `paramBotShortName` | `paramBotLongName` | `paramEnableAnonymousWebChannel` |
| Bot 2 | `paramBot2ShortName` | `paramBot2LongName` | `paramEnableAnonymousWebChannel2` |
| Bot 3 | `paramBot3ShortName` | `paramBot3LongName` | `paramEnableAnonymousWebChannel3` |

---

## Microsoft Entra ID Resources

### Service Principals (App Registrations)

All service principals are created via deployment scripts using the Deployment Script UAMI, operating against the `moneycorp.local` tenant.

#### 1. Admin Authentication Service Principal
- **Display Name**: `Neologik Admin Auth - neomcprduks1`
- **Unique Name**: `sp-admin-neo-mcprd-uks-1`
- **Module**: `modAdminAuthServicePrincipal.bicep`
- **Purpose**: Admin portal OAuth authentication

##### Configuration
- **Redirect URI**: `https://{paramHostName}/nce/`
- **Supported Account Types**: `moneycorp.local` tenant only
- **ID Tokens**: ✅ Enabled

##### API Permissions
- **Microsoft Graph**: User.Read (Delegated)

##### Secrets
- Key Vault secret: `sp-admin-neo-mcprd-uks-1-auth-secret`

#### 2. Bot Service Principals
- **Display Name**: `Neologik - {botLongName} - neomcprduks1`
- **Unique Name**: `sp-neologik-{botShortName}-neomcprduks1`
- **Purpose**: Bot Framework authentication

##### API Permissions
- **Microsoft Graph**: User.Read (Delegated)

##### Secrets
- Key Vault secret: `{botShortName}-app-registration-secret`

#### 3. SharePoint Service Principal
- **Display Name**: `Neologik SharePoint - neomcprduks1`
- **Unique Name**: `sp-sharepoint-neomcprduks1`
- **Purpose**: SharePoint REST API access

##### API Permissions
- **SharePoint**: Sites.Read.All (Application)

**Post-Deployment Required**: Run `Setup-SharePointAPIv4.ps1` to grant SharePoint site permissions

##### Secrets
- Key Vault secret: `sharepoint-app-registration-secret`

---

## Role-Based Access Control (RBAC)

### AKS Cluster Identity RBAC
**Identity**: `idaksclusterneomcprduks1`

| Role | Scope | Purpose |
|------|-------|---------|
| **Network Contributor** | Subscription | Manage network resources (load balancers, public IPs, NSGs) for AKS |

### AKS Kubelet Identity RBAC
**Identity**: `idakskubeletneomcprduks1`

| Role | Scope | Resource | Purpose |
|------|-------|----------|---------|
| **AcrPull** | Cross-subscription | Dev Container Registry | Pull container images from development registry |
| **AcrPull** | Current subscription | `crneomcprduks1` | Pull container images from environment-specific registry |

### AKS Web App Routing Identity RBAC
**Identity**: System-assigned (auto-created by AKS Web App Routing add-on)

| Role | Scope | Purpose |
|------|-------|---------|
| **Network Contributor** | Resource Group | Manage DNS zones and network resources for ingress |
| **Key Vault Secrets User** | Resource Group | Read TLS certificates from Key Vault |
| **Key Vault Crypto User** | Resource Group | Perform cryptographic operations with Key Vault keys |
| **Key Vault Certificate User** | Resource Group | Read certificates from Key Vault for HTTPS |

### AKS Key Vault Secrets Provider Identity RBAC
**Identity**: System-assigned (auto-created by AKS CSI driver add-on)

| Role | Scope | Purpose |
|------|-------|---------|
| **Key Vault Secrets User** | Resource Group | Read secrets from Key Vault and mount as volumes in pods |

### AGC ALB Controller Identity RBAC
**Identity**: `azure-alb-identity`

| Role | Role ID | Scope | Purpose |
|------|---------|-------|---------|
| **Reader** | acdd72a7-3385-48ef-bd42-f606fba81ae7 | Subscription | Read subscription resources |
| **AppGw for Containers Configuration Manager** | fbc52c3f-28ad-4303-a892-8a056630b8f1 | Resource Group | Manage AGC configuration |
| **AppGw for Containers Configuration Manager** | fbc52c3f-28ad-4303-a892-8a056630b8f1 | MC Resource Group | Manage AGC in node resource group |
| **Network Contributor** | 4d97b98b-1d4f-4787-a291-c67834d212e7 | AGC Subnet | Manage network resources in AGC subnet |

### Azure OpenAI Identity RBAC
**Identity**: `oai-neo-mcprd-uks-1` system-assigned managed identity

| Role | Scope | Purpose |
|------|-------|---------|
| **Cognitive Services OpenAI Contributor** | Resource Group | Self-management and monitoring of OpenAI resource |

### Azure AI Search Identity RBAC
**Identity**: `srch-neo-mcprd-uks-1` system-assigned managed identity

| Role | Scope | Purpose |
|------|-------|---------|
| **Search Service Contributor** | Resource Group | Self-management and indexing operations |

### Azure AI Foundry Project Identity RBAC
**Identity**: `proj-neo-mcprd-uks-1` system-assigned managed identity  
**Module**: `modFoundryProjectRbac.bicep`

| Role | Scope | Purpose |
|------|-------|---------|
| **Reader** | Resource Group | Read subscription and resource group resources |
| **Cognitive Services OpenAI Contributor** | Resource Group | Use Azure OpenAI models via Foundry project |

### Application Workload Identities (Deployed from Application Repos)

#### File Service Workload Identity
**Identity Name**: `idaksworkloadidfileneomcprduks1`

| Role | Role ID | Scope | Purpose |
|------|---------|-------|---------|
| **Key Vault Secrets User** | 4633458b-17de-408a-b874-0445c86b69e6 | Resource Group | Read secrets for file processing |
| **Storage Blob Data Contributor** | ba92f5b4-2d11-453d-a403-e96b0029c9fe | Resource Group | Read/write file storage |
| **Search Service Contributor** | 7ca78c08-252a-4471-8644-bb5ff32d4ba0 | Resource Group | Manage search service |
| **Search Index Data Contributor** | 8ebe5a00-799e-43f5-93ac-243d3dce84a7 | Resource Group | Read/write search indexes |
| **SQL Permissions** | (via script) | SQL Database | Database table access for file metadata |

#### NCE API Workload Identity
**Identity Name**: `idaksworkloadidnce-apineomcprduks1`

| Role | Role ID | Scope | Purpose |
|------|---------|-------|---------|
| **Key Vault Secrets Officer** | b86a8fe4-44ce-4948-aee5-eccb2c155cd7 | Resource Group | Manage secrets |
| **Storage Blob Data Contributor** | ba92f5b4-2d11-453d-a403-e96b0029c9fe | Resource Group | Read/write blob storage |
| **SQL Permissions** | (via script) | SQL Database | Database table access |

#### Ingest API Workload Identity
**Identity Name**: `idaksworkloadidingest-apineomcprduks1`

| Role | Role ID | Scope | Purpose |
|------|---------|-------|---------|
| **Key Vault Secrets User** | 4633458b-17de-408a-b874-0445c86b69e6 | Resource Group | Read secrets |
| **Storage Blob Data Contributor** | ba92f5b4-2d11-453d-a403-e96b0029c9fe | Resource Group | Read/write blob storage for ingestion |
| **SQL Permissions** | (via script) | SQL Database | Database table access |

#### Bot Service Workload Identities
**Identity Name**: `idaksworkloadid{botName}neomcprduks1` (per bot)

| Role | Role ID | Scope | Purpose |
|------|---------|-------|---------|
| **Contributor** | b24988ac-6180-42a0-ab88-20f7382dd24c | Resource Group | Full resource management |
| **Cosmos DB SQL Role** | (custom) | Cosmos DB Account | Data plane access to chat history |
| **SQL Permissions** | (via script) | SQL Database | Database table access for bot data |

#### NCE UI Workload Identity
**Identity Name**: `idaksworkloadidnce-uineomcprduks1`

| Role | Role ID | Scope | Purpose |
|------|---------|-------|---------|
| **AcrPull** | 7f951dda-4ed3-4680-a7ca-43fe172d538d | Resource Group | Pull container images |
| **AcrPush** | 8311e382-0749-4cb8-b61a-304f252e45ec | Resource Group | Push built container images |

##### Federated Credentials
All application workload identities use **Federated Identity Credentials** with:
- **Issuer**: `aksneomcprduks1` OIDC issuer URL
- **Subject**: `system:serviceaccount:{namespace}:{serviceAccountName}`
- **Kubernetes Service Account**: Created in application namespace with annotation `azure.workload.identity/client-id`

---

## Private Endpoints and DNS

### Private Endpoint Architecture

All PaaS services use private endpoints for network isolation.

#### Private Endpoint Naming Pattern
`pe-{serviceName}-{subresource}`

#### Private Endpoint Components
Each private endpoint creates:
1. **Private Endpoint Resource**: Network interface in `PrivateEndpointSubnet`
2. **Network Interface**: With private IP from subnet
3. **Private DNS Zone Group**: Links endpoint to DNS zone
4. **DNS A Record**: Service FQDN → Private IP

### Services with Private Endpoints

| Service | Private DNS Zone | Endpoint Count | Sub-resource |
|---------|-----------------|----------------|--------------|
| **Key Vault** | privatelink.vaultcore.azure.net | 1 | vault |
| **Container Registry** | privatelink.azurecr.io | 1 | registry |
| **Cosmos DB** | privatelink.documents.azure.com | 1 | Sql |
| **SQL Server** | privatelink.database.windows.net | 1 | sqlServer |
| **Storage (Foundry)** | blob, file, table, queue | 4 | blob, file, table, queue |
| **Storage (RAG)** | blob, file, table, queue | 4 | blob, file, table, queue |
| **Storage (Template)** | blob, file, table, queue | 4 | blob, file, table, queue |
| **Storage (Output)** | blob, file, table, queue | 4 | blob, file, table, queue |
| **Azure OpenAI** | privatelink.openai.azure.com | 1 | account |
| **AI Search** | privatelink.search.windows.net | 1 | searchService |
| **AI Services** | privatelink.cognitiveservices.azure.com | 1 | account |

**Total Private Endpoints**: ~20

### DNS Resolution Flow

```
VM/Pod → Query for service.azure.com →
Private DNS Zone → Resolves to private IP →
Private Endpoint → Azure Service
```

Example for Key Vault:
```
kubectl exec pod → kvneomcprduks1.vault.azure.net →
Private DNS (privatelink.vaultcore.azure.net) →
10.220.0.x (private IP) →
Key Vault (private traffic only)
```

### Special Network Considerations

1. **Key Vault Deployment Sequence**:
   - Phase 1: Public access enabled (for deployment scripts)
   - Phase 2: Public access disabled (final security hardening)

2. **AI Services Hybrid Networking**:
   - Private Endpoint: For DNS resolution and access from VNet
   - Service Endpoint: For VNet-level network rules
   - Network ACL: Deny default, allow `AiServiceSubnet`

3. **Storage Account Network Isolation**:
   - Default action: Deny
   - Azure Services bypass: Enabled (for trusted Microsoft services)

4. **Sequential Private Endpoint Deployment**:
   - Services deploy one at a time (using `dependsOn`)
   - Prevents DNS zone conflicts

5. **AGC Subnet**:
   - Dedicated subnet `ApplicationGatewayForContainersSubnet` (`10.254.0.0/16`)
   - Delegated to `Microsoft.ServiceNetworking/trafficControllers`
   - AGC resource is deployed from `neo-aks-ingress` repository, not infrastructure Bicep

---

## Naming Standards

### Resource Naming

| Resource Type | Pattern | Planned Name |
|---------------|---------|--------------|
| **Resource Group** | `rg-{solutionName}` | `rg-neo-mcprd-uks-1` |
| **Virtual Network** | `vnet-{solutionName}` | `vnet-neo-mcprd-uks-1` |
| **NAT Gateway** | `natgw-{solutionName}` | `natgw-neo-mcprd-uks-1` |
| **NAT Gateway Public IP** | `natgw-{solutionName}-pip` | `natgw-neo-mcprd-uks-1-pip` |
| **AKS Cluster** | `aks{solutionShortName}` | `aksneomcprduks1` |
| **Log Analytics Workspace** | `log-{solutionName}` | `log-neo-mcprd-uks-1` |
| **Application Insights** | `appi-aih-{solutionName}` | `appi-aih-neo-mcprd-uks-1` |
| **Azure Monitor (Prometheus)** | `{aksName}-prometheus` | `aksneomcprduks1-prometheus` |
| **Key Vault** | Configurable | `kvneomcprduks1` |
| **Container Registry** | Configurable (globally unique) | `crneomcprduks1` |
| **Storage Account (RAG)** | `stfiles{solutionShortName}` | `stfilesneomcprduks1` |
| **Storage Account (Template)** | `sttemplate{solutionShortName}` | `sttemplateneomcprduks1` |
| **Storage Account (Output)** | `stoutput{solutionShortName}` | `stoutputneomcprduks1` |
| **Cosmos DB** | `cosmos-chat-history-{solutionName}` | `cosmos-chat-history-neo-mcprd-uks-1` |
| **SQL Server** | `sql-main-{solutionName}` | `sql-main-neo-mcprd-uks-1` |
| **SQL Database** | `sqldb-main-{solutionName}` | `sqldb-main-neo-mcprd-uks-1` |
| **Azure OpenAI** | `oai-{solutionName}` | `oai-neo-mcprd-uks-1` |
| **AI Search** | `srch-{solutionName}` | `srch-neo-mcprd-uks-1` |
| **AI Services** | `ais-{solutionName}` | `ais-neo-mcprd-uks-1` |
| **AI Foundry Project** | `proj-{solutionName}` (child of `ais-*`) | `proj-neo-mcprd-uks-1` |
| **Automation Account** | `aa-{solutionName}-aks-startstop` | `aa-neo-mcprd-uks-1-aks-startstop` |
| **Bot Service** | `bot{botShortName}{solutionShortName}` | `bot{botShortName}neomcprduks1` |
| **AGC** | `agc-{solutionName}` | `agc-neo-mcprd-uks-1` |
| **WAF Policy (AGC)** | `waf-agc-{solutionName}` | `waf-agc-neo-mcprd-uks-1` |
| **Azure Bastion** | `bas-{solutionName}` | `bas-neo-mcprd-uks-1` |
| **Bastion Public IP** | `bastion-{solutionName}-pip` | `bastion-neo-mcprd-uks-1-pip` |
| **Bastion NSG** | `bastion-{solutionName}-nsg` | `bastion-neo-mcprd-uks-1-nsg` |
| **Jumpbox VM** | `vmj{solutionShortName}` | `vmjneomcprduks1` |
| **GitHub Runner VM** | `vmrunner{solutionShortName}` | `vmrunnerneomcprduks1` |
| **Private Endpoint** | `pe-{serviceName}-{subresource}` | e.g. `pe-kvneomcprduks1-vault` |

### Managed Identity Naming

| Identity Type | Pattern | Planned Name |
|---------------|---------|--------------|
| **AKS Cluster Identity** | `idakscluster{solutionShortName}` | `idaksclusterneomcprduks1` |
| **AKS Kubelet Identity** | `idakskubelet{solutionShortName}` | `idakskubeletneomcprduks1` |
| **ALB Controller Identity** | `azure-alb-identity` | `azure-alb-identity` |
| **File Workload Identity** | `idaksworkloadidfile{solutionShortName}` | `idaksworkloadidfileneomcprduks1` |
| **NCE API Workload Identity** | `idaksworkloadidnce-api{solutionShortName}` | `idaksworkloadidnce-apineomcprduks1` |
| **Ingest API Workload Identity** | `idaksworkloadidingest-api{solutionShortName}` | `idaksworkloadidingest-apineomcprduks1` |
| **Bot Workload Identity** | `idaksworkloadid{botName}{solutionShortName}` | `idaksworkloadid{bot}neomcprduks1` |
| **NCE UI Workload Identity** | `idaksworkloadidnce-ui{solutionShortName}` | `idaksworkloadidnce-uineomcprduks1` |

### Service Principal Naming

| Type | Pattern | Planned Name |
|------|---------|--------------|
| **Admin Auth** | `sp-admin-{solutionName}` | `sp-admin-neo-mcprd-uks-1` |
| **Bot Service** | `sp-neologik-{botShortName}-{solutionShortName}` | `sp-neologik-{bot}-neomcprduks1` |
| **SharePoint** | `sp-sharepoint-{solutionShortName}` | `sp-sharepoint-neomcprduks1` |

### Key Vault Secret Naming

| Secret Type | Pattern | Example |
|-------------|---------|---------|
| **Storage Connection String** | `{storageAccountName}-conn-string` | `stfilesneomcprduks1-conn-string` |
| **OpenAI API Key** | `{openAIName}-api-key` | `oai-neo-mcprd-uks-1-api-key` |
| **AI Search API Key** | `aisearch-api-key` | `aisearch-api-key` |
| **Service Principal Secret** | `{spName}-auth-secret` | `sp-admin-neo-mcprd-uks-1-auth-secret` |
| **Bot Service Secret** | `{botShortName}-app-registration-secret` | `{bot}-app-registration-secret` |
| **AKS SSH Private Key** | `{aksName}-ssh-private-key` | `aksneomcprduks1-ssh-private-key` |
| **AKS SSH Public Key** | `{aksName}-ssh-public-key` | `aksneomcprduks1-ssh-public-key` |
| **Jumpbox Password** | `{vmName}-admin-password` | `vmjneomcprduks1-admin-password` |

## Deployment Sequence

The neo-secure template enforces **sequential deployment** for services with private endpoints.

### Deployment Order

```
1. Virtual Network + DNS Zones
   ↓
2. Bastion NSG
   ↓
3. Log Analytics Workspace
   ↓
4. Key Vault (Phase 1: Public access)
   ↓
5. Container Registry (with private endpoint)
   ↓
6. Cosmos DB (with private endpoint)
   ↓
7. SQL Database (with private endpoint)
   ↓
8. RAG Storage (with 4 private endpoints)
   ↓
9. Template Storage (with 4 private endpoints)
   ↓
10. Output Storage (with 4 private endpoints)
   ↓
11. Azure OpenAI (with private endpoint)
   ↓
12. AI Search (with private endpoint)
   ↓
13. AI Services (with private endpoint + service endpoint)
   ↓
14. AI Foundry Project (child of ais-*, no private endpoint) + Account Connections
   ↓
15. AKS Cluster (private)
   ↓
16. Azure Monitor (Prometheus)
   ↓
17. Bastion
   ↓
18. Jumpbox VM
   ↓
19. GitHub Runner VM
   ↓
20. Key Vault (Phase 2: Private only)
   ↓
21. [Post-infra] Deploy AGC via neo-aks-ingress repository
```

### Deployment Time

- **Sequential deployment**: ~45–60 minutes
- **Post-infra AGC deployment**: ~10–15 minutes additional (from `neo-aks-ingress`)

---

## Security Highlights

### Network Isolation
- ✅ All PaaS services on private endpoints (~24 endpoints)
- ✅ No public internet access to any data plane
- ✅ VNet-integrated AI Services (service endpoint)
- ✅ Private AKS cluster (API server not publicly accessible)
- ✅ No public IPs on VMs (Bastion access only)
- ✅ AGC subnet delegated — traffic controller isolated to dedicated subnet

### Access Control
- ✅ Key Vault with RBAC (no access policies)
- ✅ Microsoft Entra ID only authentication for SQL
- ✅ Managed identities for all service-to-service communication
- ✅ Storage account network deny by default
- ✅ Container Registry admin user disabled

### Logging and Monitoring
- ✅ 90-day log retention (compliance)
- ✅ Diagnostic settings on all resources
- ✅ Centralized Log Analytics (`log-neo-mcprd-uks-1`)
- ✅ Full alert stack (action groups, metric alerts, cost budgets)
- ✅ Prometheus metrics via `aksneomcprduks1-prometheus`

### Data Protection
- ✅ Cosmos DB automatic failover enabled
- ✅ Key Vault soft delete (90 days)
- ✅ Storage account redundancy (ZRS)
- ✅ SQL Database backups (7 days)

### Management Access
- ✅ Azure Bastion for VM access (no public IPs)
- ✅ Private AKS cluster (requires VNet access)
- ✅ Jumpbox VM for administrative tasks
- ✅ GitHub Runner VM with private access to AKS/Azure

---

## Summary

The **Moneycorp Production** neo-secure deployment provides:
- ✅ **Enterprise-grade security** with private endpoints and full network isolation
- ✅ **Compliance-ready** infrastructure (90-day retention, audit logging, Entra-ID auth)
- ✅ **Private AKS cluster** (`aksneomcprduks1`) with Bastion and Jumpbox management
- ✅ **Application Gateway for Containers** (AGC) with WAF v2 — modern Gateway API standard
- ✅ **All AI capabilities** (OpenAI, AI Search, AI Foundry Project) on private network
- ✅ **~20 private endpoints** eliminating all public internet exposure
- ✅ **Full monitoring stack** with alerting, action groups, and cost budgets

**Tenant**: `moneycorp.local` (ID: `234b7362-627a-4a31-9a1f-d340c11da1e0`)  
**Subscription**: Moneycorp UK Neologik-Production-1 *(TBD)*  
**Resource Group**: `rg-neo-mcprd-uks-1` | **Location**: UK South

---

**Document Version**: 1.0  
**Last Updated**: April 15, 2026  