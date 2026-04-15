# Neologik neo-secure Deployment Reference — Moneycorp Dev

Complete documentation for the **neo-secure** deployment in the **Moneycorp Development** environment (subscription: *Moneycorp UK Neologik-Development-1*).

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

---

## Environment Identity

| Field | Value |
|-------|-------|
| **Tenant Name** | moneycorp |
| **Tenant ID** | `234b7362-627a-4a31-9a1f-d340c11da1e0` |
| **Tenant Domain** | `moneycorp.local` |
| **Subscription Name** | Moneycorp UK Neologik-Development-1 |
| **Subscription ID** | `3ed8c3f5-61bf-43b7-af55-b62ebaa53064` |
| **Resource Group** | `rg-neo-mcdev-uks-1` |
| **Location** | UK South (`uksouth`) |
| **Solution Name** | `neo-mcdev-uks-1` |
| **Solution Short Name** | `neomcdevuks1` |

---

## Overview

The **neo-secure** deployment template is designed for:
- **Production environments** requiring network isolation
- **Security-focused deployments** with private endpoints
- **Compliance requirements** (data residency, network segmentation)
- **Enterprise-grade infrastructure** with management VMs and Bastion

This document reflects the **Moneycorp Development** instantiation of the neo-secure template, deployed in UK South.

**File**: `bicep/neo-secure.bicep`

---

## Deployment Characteristics

| Feature | Configuration |
|---------|---------------|
| **Network Access** | Private (via Private Endpoints) |
| **Private Endpoints** | ✅ Yes (~24+ endpoints for all PaaS services) |
| **Azure Bastion** | ✅ Yes |
| **Jumpbox VM** | ✅ Yes (Windows Server) |
| **GitHub Runner VM** | ✅ Yes (Ubuntu) |
| **AKS Cluster Type** | Private |
| **AKS SKU Tier** | **Standard** |
| **Ingress** | Application Gateway Ingress Controller (AGIC) |
| **Container Registry SKU** | Premium (supports private endpoints) |
| **Log Retention** | 90 days |
| **Key Vault Public Access** | Disabled |
| **SQL Database Access** | Private Endpoint only |
| **Storage Account Access** | Private (Network Deny default) |
| **Custom Private DNS** | ✅ Yes (`neologik.internal`) |
| **AKS Outbound Type** | Load Balancer |

---

## Azure Resources

### Networking Resources

#### Virtual Network (VNet)
- **Resource Type**: `Microsoft.Network/virtualNetworks`
- **Name**: `vnet-neo-mcdev-uks-1`
- **Address Space**: `10.0.0.0/8`

##### Subnets

| Subnet Name | Address Prefix | Purpose | Delegations | NAT Gateway |
|-------------|----------------|---------|-------------|-------------|
| `systempoolnodesubnet` | `10.200.0.0/16` | AKS system nodes | None | ❌ No |
| `systempoolpodsubnet` | `10.201.0.0/16` | AKS system pods | Microsoft.ContainerService/managedClusters | ❌ No |
| `userpool1nodesubnet` | `10.202.0.0/16` | AKS user nodes | None | ❌ No |
| `userpool1podsubnet` | `10.203.0.0/16` | AKS user pods | Microsoft.ContainerService/managedClusters | ❌ No |
| `AzureBastionSubnet` | `10.253.0.0/16` | Azure Bastion | None | ❌ No |
| `PrivateEndpointSubnet` | `10.220.0.0/16` | Private Endpoints | None | ❌ No |
| `AppSubnet` | `10.205.0.0/16` | Container Apps | Microsoft.App/environments | ❌ No |
| `VmSubnet` | `10.252.0.0/16` | Virtual Machines | None | ❌ No |
| `AiServiceSubnet` | `10.206.0.0/16` | AI Services (VNet integration) | None | ❌ No |
| `ApplicationGatewaySubnet` | `10.254.0.0/16` | Application Gateway | None | ❌ No |

> **Note**: AKS uses `loadBalancer` outbound type in this deployment (not NAT gateway). The NAT gateway is deployed but used for VM subnet outbound connectivity.

#### NAT Gateway
- **Resource Type**: `Microsoft.Network/natGateways`
- **Name**: `natgw-neo-mcdev-uks-1`
- **SKU**: Standard
- **Public IP**: `natgw-neo-mcdev-uks-1-pip`
- **Settings**:
  - Idle Timeout: 4 minutes
  - Public IP SKU: Standard
  - Public IP Allocation: Static
- **Purpose**: Outbound internet connectivity for VMs
- **Diagnostic Settings**: Enabled (sends logs to Log Analytics)

#### Network Security Groups

##### Bastion NSG
- **Resource Type**: `Microsoft.Network/networkSecurityGroups`
- **Name**: `bastion-neo-mcdev-uks-1-nsg`
- **Applied To**: AzureBastionSubnet

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

##### Application Gateway NSG
- **Resource Type**: `Microsoft.Network/networkSecurityGroups`
- **Name**: `appgw-neo-mcdev-uks-1-nsg`
- **Applied To**: ApplicationGatewaySubnet

#### Private DNS Zones
- **Resource Type**: `Microsoft.Network/privateDnsZones`
- **Location**: Global
- **VNet Links**: All zones linked to `vnet-neo-mcdev-uks-1`

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
| `privatelink.api.azureml.ms` | AI Hub/Project | Microsoft.MachineLearningServices/workspaces |
| `privatelink.grafana.azure.com` | Managed Grafana | Microsoft.Dashboard/grafana |
| `neologik.internal` | Custom A records | User-managed |

**DNS Resolution Flow**:
```
VM/AKS Pod → Private DNS Zone → Private Endpoint IP → Azure Service
```

#### Custom Private DNS Zone
- **Zone Name**: `neologik.internal`
- **Purpose**: System owner can add custom A records for internal services
- **VNet Link**: `neologik.internal-vnet-link` → `vnet-neo-mcdev-uks-1`
- **Usage**: Manual management via Azure Portal or Azure CLI

---

### Compute Resources

#### Azure Kubernetes Service (AKS)
- **Resource Type**: `Microsoft.ContainerService/managedClusters`
- **Name**: `aksneomcdevuks1`

##### AKS Configuration
| Setting | Value |
|---------|-------|
| **Cluster Type** | **Private** |
| **SKU Tier** | **Standard** |
| **Kubernetes Version** | `1.33.2` |
| **Network Plugin** | Azure CNI |
| **Network Policy** | None |
| **Outbound Type** | loadBalancer |
| **Service CIDR** | `10.210.0.0/16` |
| **DNS Service IP** | `10.210.0.10` |
| **Private Cluster** | ✅ **Yes** |
| **Private DNS Zone** | System (auto-created by Azure) |
| **MC Resource Group** | `MC_rg-neo-mcdev-uks-1_aksneomcdevuks1_uksouth` |

##### Node Pools

1. **System Pool** (`systempool`)
   - VM Size: `Standard_D2s_v5`
   - Autoscaler: Min **3**, Max **5**
   - Node Subnet: `systempoolnodesubnet`
   - Pod Subnet: `systempoolpodsubnet`
   - Node Taints: `CriticalAddonsOnly=true:NoSchedule`
   - Purpose: System workloads (CoreDNS, metrics-server, etc.)

2. **User Pool 1** (`userpool1`)
   - VM Size: `Standard_E2s_v6`
   - Autoscaler: Min **2**, Max **5**
   - Node Subnet: `userpool1nodesubnet`
   - Pod Subnet: `userpool1podsubnet`
   - Purpose: Application workloads

##### Private Cluster Access
- **API Server**: Only accessible from VNet (private IP)
- **Management**: Requires Jumpbox VM or Azure Bastion connection
- **kubectl Access**: Must be from within VNet or via VPN/ExpressRoute

##### AKS Add-ons and Features
- ✅ **Azure Key Vault Secrets Provider**: Enabled (secret rotation: 2m interval)
- ✅ **Azure Monitor (OMS Agent)**: Enabled → `log-neo-mcdev-uks-1`
- ✅ **Ingress Application Gateway (AGIC)**: Enabled → `appgw-neo-mcdev-uks-1`
- ✅ **Azure Policy**: Enabled
- ✅ **Workload Identity**: Enabled (for pod-to-Azure auth)
- ✅ **OIDC Issuer**: Enabled

##### AKS SSH Access
- **SSH Key Generation**: Automated via deployment script (for new clusters)
- **Key Storage**: Key Vault secrets (private and public keys)

#### Jumpbox VM (Windows Server)
- **Resource Type**: `Microsoft.Compute/virtualMachines`
- **Name**: `vmjneomcdevuks1`
- **NIC**: `vmjneomcdevuks1-nic`

##### Configuration
| Setting | Value |
|---------|-------|
| **OS** | Windows Server (latest) |
| **VM Size** | Configurable (default: `Standard_D2s_v5`) |
| **Public IP** | **No** |
| **Subnet** | VmSubnet |
| **Access** | Via Azure Bastion only |
| **Scheduled Shutdown** | `shutdown-computevm-vmjneomcdevuks1` |

##### VM Extensions
1. **Azure Monitor Agent** (`AzureMonitorWindowsAgent`): Collects logs and metrics
2. **enablevmAccess**: VM access extension

##### Software Pre-installed
- Windows Remote Desktop enabled
- Azure CLI
- PowerShell 7
- kubectl (for AKS management)

#### GitHub Runner VM (Ubuntu)
- **Resource Type**: `Microsoft.Compute/virtualMachines`
- **Name**: `vmrunnerneomcdevuks1`
- **NIC**: `vmrunnerneomcdevuks1-nic`

##### Configuration
| Setting | Value |
|---------|-------|
| **OS** | Ubuntu 22.04 LTS (Jammy) |
| **VM Size** | Configurable (default: `Standard_D2s_v3`) |
| **Subnet** | VmSubnet |
| **Public IP** | **No** |
| **Scheduled Shutdown** | `shutdown-computevm-vmrunnerneomcdevuks1` |

##### VM Extensions
1. **GitHubRunnerInstall**: Installs and registers GitHub Actions Runner

##### GitHub Runner Configuration
- **Organization**: `Neologik-AI`
- **Purpose**: Self-hosted runner for GitHub Actions workflows requiring private AKS/Azure access

#### Azure Bastion
- **Resource Type**: `Microsoft.Network/bastionHosts`
- **Name**: `bas-neo-mcdev-uks-1`
- **Public IP**: `bastion-neo-mcdev-uks-1-pip`

##### Configuration
| Setting | Value |
|---------|-------|
| **Subnet** | AzureBastionSubnet (dedicated) |
| **Public IP** | `bastion-neo-mcdev-uks-1-pip` (dedicated) |
| **Features** | RDP and SSH tunneling |

**Access Pattern**:
```
User → Azure Portal/CLI → Bastion (Public IP) → VM (Private IP)
```

#### Ingress Controller — Application Gateway Ingress Controller (AGIC)

##### Application Gateway
- **Resource Type**: `Microsoft.Network/applicationGateways`
- **Name**: `appgw-neo-mcdev-uks-1`
- **Public IP**: `appgw-neo-mcdev-uks-1-pip`
- **WAF Policy**: `appgw-neo-mcdev-uks-1-waf-policy`

##### AGIC Configuration
| Setting | Value |
|---------|-------|
| **SKU** | WAF_v2 |
| **Tier** | WAF_v2 |
| **Generation** | Generation_2 |
| **Subnet** | `ApplicationGatewaySubnet` (`10.254.0.0/16`) |
| **Public IP** | `appgw-neo-mcdev-uks-1-pip` |
| **Integration Method** | AGIC add-on (configured in AKS) |

##### WAF Policy
- **Resource Type**: `Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies`
- **Name**: `appgw-neo-mcdev-uks-1-waf-policy`
- **Managed Rules**: OWASP ModSecurity Core Rule Set

---

### Storage Resources

#### Container Registry
- **Resource Type**: `Microsoft.ContainerRegistry/registries`
- **Name**: `crneomcdevuks1`
- **SKU**: **Premium** (required for private endpoints)
- **Admin User**: **Disabled**
- **Public Network Access**: **Disabled**
- **Private Endpoint**: `crneomcdevuks1-pe` ✅

#### Storage Accounts

All storage accounts use Geo-Zone-Redundant Storage (GZRS) and private endpoints.

##### Common Settings
| Setting | Value |
|---------|-------|
| **SKU** | Standard_GZRS |
| **Public Network Access** | **Disabled** |
| **Network Default Action** | **Deny** |
| **Azure Services Bypass** | Enabled |
| **Private Endpoints** | blob, file, table, queue (4 per account) |
| **Connection String Storage** | Key Vault secrets |

##### 1. AI Foundry Storage Account
- **Name**: `stfoundryneomcdevuks1`
- **Container**: `foundry`
- **Purpose**: AI Hub workspace storage
- **Private Endpoints**: `stfoundryneomcdevuks1-blob-pe`, `-table-pe`, `-queue-pe`, `-file-pe`

##### 2. RAG Storage Account
- **Name**: `stfilesneomcdevuks1`
- **Container**: `files`
- **Purpose**: RAG document storage
- **Private Endpoints**: `stfilesneomcdevuks1-blob-pe`, `-table-pe`, `-queue-pe`, `-file-pe`

##### 3. Template Storage Account
- **Name**: `sttemplateneomcdevuks1`
- **Container**: `templates`
- **Purpose**: Document template storage
- **Private Endpoints**: `sttemplateneomcdevuks1-blob-pe`, `-table-pe`, `-queue-pe`, `-file-pe`

##### 4. Output Storage Account
- **Name**: `stoutputneomcdevuks1`
- **Container**: `output`
- **Purpose**: Processing output storage
- **Private Endpoints**: `stoutputneomcdevuks1-blob-pe`, `-table-pe`, `-queue-pe`, `-file-pe`

##### 5. Deployment Scripts Storage Account
- **Name**: `sagenneomcdevuks1`
- **Purpose**: ARM/Bicep deployment script execution storage

**Total Application Storage Private Endpoints**: 16

---

### Database Resources

#### Cosmos DB (Chat History)
- **Resource Type**: `Microsoft.DocumentDB/databaseAccounts`
- **Name**: `cosmos-chat-history-neo-mcdev-uks-1`
- **Private Endpoint**: `cosmos-chat-history-neo-mcdev-uks-1-pe` ✅

##### Configuration
| Setting | Value |
|---------|-------|
| **Account Kind** | GlobalDocumentDB (SQL API) |
| **Consistency Level** | Session |
| **Capabilities** | EnableServerless |
| **Automatic Failover** | ✅ Enabled |
| **Private Endpoint** | ✅ Yes |
| **Database Name** | `chathistorydb` |
| **Container Name** | `chat_history` |
| **Partition Key** | `/userId` |

#### Cosmos DB (Main)
- **Resource Type**: `Microsoft.DocumentDB/databaseAccounts`
- **Name**: `cosmos-main-neo-mcdev-uks-1`
- **Private Endpoint**: `cosmos-main-neo-mcdev-uks-1-pe` ✅
- **Account Kind**: GlobalDocumentDB
- **Purpose**: General application data storage

#### Azure SQL Database
- **SQL Server**: `sqlsrvneomcdevuks2`
- **SQL Database**: `sqldbneomcdevuks2`

> **Note**: SQL Server public network access is **Disabled**. Access is via private endpoint only.

##### SQL Server Configuration
| Setting | Value |
|---------|-------|
| **Admin Login** | `neoadmin` |
| **Public Network Access** | **Disabled** |
| **TLS Version** | 1.2 minimum |
| **Authentication** | SQL + Microsoft Entra ID |

##### SQL Database Configuration
| Setting | Value |
|---------|-------|
| **SKU** | GP_S_Gen5 (Serverless) |
| **Min Capacity** | 0.5 vCores |
| **Max Capacity** | 1 vCore |
| **Auto-pause Delay** | 60 minutes |
| **Max Size** | 32 GB |

---

### AI and Cognitive Services

#### Azure OpenAI Service
- **Resource Type**: `Microsoft.CognitiveServices/accounts`
- **Kind**: OpenAI
- **Name**: `oai-neo-mcdev-uks-1`
- **SKU**: S0
- **Private Endpoint**: `oai-neo-mcdev-uks-1-pe` ✅

##### Model Deployments

| Deployment Name | Model | Version | Capacity (TPM×1000) |
|----------------|-------|---------|---------------------|
| `gpt-35-turbo` | gpt-4.1-mini | 2025-04-14 | 500 |
| `gpt-4.1-mini` | gpt-4.1-mini | 2025-04-14 | 5,000 |
| `gpt-4.1-nano` | gpt-4.1-nano | 2025-04-14 | 5,000 |
| `gpt-5-mini` | gpt-5-mini | 2025-08-07 | 1,000 |
| `gpt-5.2` | gpt-5.2 | 2025-12-11 | 1,102 |
| `text-embedding-3-large` | text-embedding-3-large | 1 | 350 |

**API Key**: Stored in Key Vault as `oai-neo-mcdev-uks-1-api-key`

#### Azure AI Search (Cognitive Search)
- **Resource Type**: `Microsoft.Search/searchServices`
- **Name**: `srch-neo-mcdev-uks-1`
- **Private Endpoint**: `srch-neo-mcdev-uks-1-pe` ✅

##### Configuration
| Setting | Value |
|---------|-------|
| **SKU** | Standard |
| **Partition Count** | 1 |
| **Replica Count** | 1 |
| **Public Network Access** | Disabled |

**API Key**: Stored in Key Vault as `aisearch-api-key`

#### Azure AI Services (Multiservice)
- **Resource Type**: `Microsoft.CognitiveServices/accounts`
- **Kind**: AIServices
- **Name**: `ais-neo-mcdev-uks-1`
- **Private Endpoint**: `ais-neo-mcdev-uks-1-pe` ✅

##### Network Configuration (Hybrid Approach)
- **Service Endpoint**: Attached to `AiServiceSubnet` (for VNet-level access)
- **Private Endpoint**: In `PrivateEndpointSubnet` (for DNS resolution)
- **Network ACLs**:
  - Default Action: **Deny**
  - VNet Rules: Allow AiServiceSubnet

#### Azure AI Hub (AI Foundry)
- **Resource Type**: `Microsoft.MachineLearningServices/workspaces`
- **Kind**: Hub
- **Name**: `hub-neo-mcdev-uks-1`
- **Private Endpoint**: `hub-neo-mcdev-uks-1-pe` ✅

##### Linked Services
- **Azure OpenAI**: `oai-neo-mcdev-uks-1`
- **AI Search**: `srch-neo-mcdev-uks-1`
- **Application Insights**: `appi-aih-neo-mcdev-uks-1`
- **Container Registry**: `crneomcdevuks1`
- **Key Vault**: `kvneomcdevuks1`
- **Storage Account**: `stfoundryneomcdevuks1`

#### Azure AI Project
- **Resource Type**: `Microsoft.MachineLearningServices/workspaces`
- **Kind**: Project
- **Name**: `proj-neo-mcdev-uks-1`
- **Hub Association**: `hub-neo-mcdev-uks-1`

#### Document Intelligence
- **Resource Type**: `Microsoft.CognitiveServices/accounts`
- **Name**: `di-neo-mcdev-uks-1`
- **Private Endpoint**: `di-neo-mcdev-uks-1-pe` ✅
- **Purpose**: Document analysis and form recognition

#### Bing Search
- **Resource Type**: `Microsoft.Bing/accounts`
- **Name**: `bingneomcdevuks1`
- **Location**: Global
- **Purpose**: Web search grounding for AI workloads

---

### Security and Identity

#### Key Vault (Main — Two-Phase Deployment)
- **Resource Type**: `Microsoft.KeyVault/vaults`
- **Name**: `kvneomcdevuks1`
- **Private Endpoint**: `kvneomcdevuks1-pe` ✅

##### Current Configuration
| Setting | Value |
|---------|-------|
| **SKU** | Standard |
| **RBAC Authorization** | ✅ Enabled |
| **Soft Delete Retention** | 90 days |
| **Public Network Access** | **Disabled** |
| **Network ACLs Default** | **Deny** |
| **Network ACLs Bypass** | AzureServices |

##### Deployment Sequence
```
1. Deploy Key Vault with public access
2. Run deployment scripts (SSH keys, service principals)
3. Deploy all other resources
4. Update Key Vault to disable public access
```

##### Secrets Stored
- Storage account connection strings (4 accounts)
- OpenAI API key (`oai-neo-mcdev-uks-1-api-key`)
- AI Search API key (`aisearch-api-key`)
- Bot service principal secrets
- SharePoint service principal secret
- Admin authentication service principal secret
- AKS SSH keys (public and private)
- Jumpbox VM admin password

#### Key Vault (Deployment Scripts)
- **Resource Type**: `Microsoft.KeyVault/vaults`
- **Name**: `NeologikKeyVault`
- **SKU**: Standard
- **RBAC Authorization**: ✅ Enabled
- **Public Network Access**: Disabled
- **Purpose**: Secrets for Neologik deployment script runner

#### User-Assigned Managed Identities

##### 1. Deployment Script UAMI
- **Name**: `NeologikScriptRunnerServiceConnection`
- **Purpose**: Execute deployment scripts (SSH key generation, Entra ID operations)

**Required Pre-deployment Permissions**:
- **Microsoft Graph**:
  - Application.ReadWrite.All (for creating service principals)
  - Directory.ReadWrite.All (for Entra ID operations)
- **Key Vault**:
  - Key Vault Secrets Officer (for storing secrets)

##### 2. AKS Cluster Identity
- **Name**: `idaksclusterneomcdevuks1`
- **Purpose**: AKS control plane identity
- **Permissions**: See [RBAC section](#aks-cluster-identity-rbac)

##### 3. AKS Kubelet Identity
- **Name**: `idakskubeletneomcdevuks1`
- **Purpose**: AKS node and pod identity
- **Permissions**: See [RBAC section](#aks-kubelet-identity-rbac)

---

### Monitoring and Logging

#### Log Analytics Workspace
- **Resource Type**: `Microsoft.OperationalInsights/workspaces`
- **Name**: `log-neo-mcdev-uks-1`
- **SKU**: PerGB2018
- **Retention**: **90 days**
- **Public Network Access**: ✅ Enabled (for ingestion and queries)

#### Application Insights (AI Hub)
- **Resource Type**: `Microsoft.Insights/components`
- **Name**: `appi-aih-neo-mcdev-uks-1`
- **Retention**: 90 days (inherited from Log Analytics)

#### Azure Monitor Workspace (Prometheus)
- **Resource Type**: `Microsoft.Monitor/accounts`
- **Name**: `aksneomcdevuks1-prometheus`
- **Data Collection Endpoint**: `MSProm-uksouth-aksneomcdevuks1`

#### Data Collection Rules (DCR)
| DCR Name | Purpose |
|----------|---------|
| `MSCI-uksouth-aksneomcdevuks1` | AKS Container Insights |
| `MSProm-uksouth-aksneomcdevuks1` | AKS Prometheus metrics |
| `vmjneomcdevuks1-windows-basic-dcr` | Jumpbox VM logs |
| `vmrunnerneomcdevuks1-logs-dcr` | GitHub Runner VM logs |

#### Prometheus Rule Groups
| Rule Group | Purpose |
|------------|---------|
| `CommunityCIAlerts-aksneomcdevuks1` | Community CI alert rules |
| `NodeRecordingRulesRuleGroup-aksneomcdevuks1` | Node recording rules |
| `KubernetesRecordingRulesRuleGroup-aksneomcdevuks1` | Kubernetes recording rules |
| `UXRecordingRulesRuleGroup-aksneomcdevuks1` | UX recording rules |

---

### Automation Resources

#### AKS Start/Stop Automation
> **Not deployed** in this environment. AKS cluster runs continuously in the Moneycorp Dev environment.

#### Bot Service Resources

##### Bot Service Configuration
- **Resource Type**: `Microsoft.BotService/botServices`
- **Name**: `botneomcdevuks1`
- **SKU**: S1 (Standard)
- **Location**: Global

---

## Microsoft Entra ID Resources

### Service Principals (App Registrations)

All service principals are created via deployment scripts using `NeologikScriptRunnerServiceConnection`.

#### 1. Admin Authentication Service Principal
- **Display Name**: `Neologik Admin Auth - neomcdevuks1`
- **Unique Name**: `sp-admin-neo-mcdev-uks-1`
- **Purpose**: Admin portal OAuth authentication

##### Configuration
- **Redirect URI**: `https://{paramHostName}/nce/`
- **Supported Account Types**: `moneycorp.local` tenant only
- **ID Tokens**: ✅ Enabled

##### API Permissions
- **Microsoft Graph**: User.Read (Delegated)

##### Secrets
- Key Vault secret: `sp-admin-neo-mcdev-uks-1-auth-secret`

#### 2. Bot Service Principal
- **Display Name**: `Neologik - {botLongName} - neomcdevuks1`
- **Unique Name**: `sp-neologik-{botShortName}-neomcdevuks1`
- **Purpose**: Bot Framework authentication for `botneomcdevuks1`

##### API Permissions
- **Microsoft Graph**: User.Read (Delegated)

##### Secrets
- Key Vault secret: `{botShortName}-app-registration-secret`

#### 3. SharePoint Service Principal
- **Display Name**: `Neologik SharePoint - neomcdevuks1`
- **Unique Name**: `sp-sharepoint-neomcdevuks1`
- **Purpose**: SharePoint REST API access

##### API Permissions
- **SharePoint**: Sites.Read.All (Application)

##### Secrets
- Key Vault secret: `sharepoint-app-registration-secret`

---

## Role-Based Access Control (RBAC)

### AKS Cluster Identity RBAC
**Identity**: `idaksclusterneomcdevuks1`

| Role | Scope | Purpose |
|------|-------|---------|
| **Network Contributor** | Subscription | Manage network resources (load balancers, public IPs, NSGs) for AKS |

### AKS Kubelet Identity RBAC
**Identity**: `idakskubeletneomcdevuks1`

| Role | Scope | Resource | Purpose |
|------|-------|----------|---------|
| **AcrPull** | Cross-subscription | Dev Container Registry | Pull container images from development registry |
| **AcrPull** | Current subscription | `crneomcdevuks1` | Pull container images from environment-specific registry |

### AKS Web App Routing Identity RBAC
**Identity**: System-assigned (auto-created by AKS Web App Routing add-on)

| Role | Scope | Purpose |
|------|-------|---------|
| **Network Contributor** | Resource Group | Manage DNS zones and network resources for ingress |
| **Key Vault Secrets User** | Resource Group | Read TLS certificates from Key Vault |
| **Key Vault Crypto User** | Resource Group | Perform cryptographic operations with Key Vault keys |
| **Key Vault Certificate User** | Resource Group | Read certificates from Key Vault for HTTPS |

### AKS Key Vault Secrets Provider Identity RBAC
**Identity**: System-assigned (auto-created by AKS CSI driver add-on — `azurekeyvaultsecretsprovider-aksneomcdevuks1`)

| Role | Scope | Purpose |
|------|-------|---------|
| **Key Vault Secrets User** | Resource Group | Read secrets from Key Vault and mount as volumes in pods |

### Azure OpenAI Identity RBAC
**Identity**: Azure OpenAI system-assigned managed identity

| Role | Scope | Purpose |
|------|-------|---------|
| **Cognitive Services OpenAI Contributor** | Resource Group | Self-management and monitoring of OpenAI resource |

### Azure AI Search Identity RBAC
**Identity**: AI Search system-assigned managed identity

| Role | Scope | Purpose |
|------|-------|---------|
| **Search Service Contributor** | Resource Group | Self-management and indexing operations |

### Azure AI Project Identity RBAC
**Identity**: AI Project system-assigned managed identity

| Role | Scope | Purpose |
|------|-------|---------|
| **Azure AI Developer** | Resource Group | Access AI Hub and associated services |
| **Cognitive Services OpenAI Contributor** | Resource Group | Use Azure OpenAI models in AI Project |

### Application Workload Identities (Deployed from Application Repos)

#### File Service Workload Identity
**Identity Name**: `idaksworkloadidfileneomcdevuks1`

| Role | Role ID | Scope | Purpose |
|------|---------|-------|---------|
| **Key Vault Secrets User** | 4633458b-17de-408a-b874-0445c86b69e6 | Resource Group | Read secrets for file processing |
| **Storage Blob Data Contributor** | ba92f5b4-2d11-453d-a403-e96b0029c9fe | Resource Group | Read/write file storage |
| **Search Service Contributor** | 7ca78c08-252a-4471-8644-bb5ff32d4ba0 | Resource Group | Manage search service |
| **Search Index Data Contributor** | 8ebe5a00-799e-43f5-93ac-243d3dce84a7 | Resource Group | Read/write search indexes |
| **SQL Permissions** | (via script) | SQL Database | Database table access for file metadata |

#### NCE API Workload Identity
**Identity Name**: `idaksworkloadidnce-apineomcdevuks1`

| Role | Role ID | Scope | Purpose |
|------|---------|-------|---------|
| **Key Vault Secrets Officer** | b86a8fe4-44ce-4948-aee5-eccb2c155cd7 | Resource Group | Manage secrets |
| **Storage Blob Data Contributor** | ba92f5b4-2d11-453d-a403-e96b0029c9fe | Resource Group | Read/write blob storage |
| **SQL Permissions** | (via script) | SQL Database | Database table access |

#### Ingest API Workload Identity
**Identity Name**: `idaksworkloadidingestneomcdevuks1`

| Role | Role ID | Scope | Purpose |
|------|---------|-------|---------|
| **Key Vault Secrets User** | 4633458b-17de-408a-b874-0445c86b69e6 | Resource Group | Read secrets |
| **Storage Blob Data Contributor** | ba92f5b4-2d11-453d-a403-e96b0029c9fe | Resource Group | Read/write blob storage for ingestion |
| **SQL Permissions** | (via script) | SQL Database | Database table access |

#### Bot Service Workload Identity
**Identity Name**: `idaksworkloadidbotneomcdevuks1`

| Role | Role ID | Scope | Purpose |
|------|---------|-------|---------|
| **Contributor** | b24988ac-6180-42a0-ab88-20f7382dd24c | Resource Group | Full resource management |
| **Cosmos DB SQL Role** | (custom) | Cosmos DB Account | Data plane access to chat history |
| **SQL Permissions** | (via script) | SQL Database | Database table access for bot data |

#### Additional Workload Identities

| Identity Name | Purpose |
|---------------|---------|
| `idaksworkloadidclassifyneomcdevuks1` | Classification service workload |
| `idaksworkloadidnl2sqlneomcdevuks1` | NL-to-SQL service workload |
| `idaksworkloadidnceneomcdevuks1` | NCE UI workload |

##### Federated Credentials
All application workload identities use **Federated Identity Credentials** with:
- **Issuer**: AKS OIDC issuer URL (`aksneomcdevuks1`)
- **Subject**: `system:serviceaccount:{namespace}:{serviceAccountName}`
- **Kubernetes Service Account**: Created in application namespace with annotation `azure.workload.identity/client-id`

---

## Private Endpoints and DNS

### Private Endpoint Architecture

All PaaS services use private endpoints for network isolation.

#### Private Endpoint Naming Pattern
`{serviceName}-pe` or `{serviceName}-{subresource}-pe`

#### Private Endpoint Components
Each private endpoint creates:
1. **Private Endpoint Resource**: Network interface in `PrivateEndpointSubnet`
2. **Network Interface**: With private IP from subnet
3. **Private DNS Zone Group**: Links endpoint to DNS zone
4. **DNS A Record**: Service FQDN → Private IP

### Services with Private Endpoints

| Service | Name | Private DNS Zone | Endpoint Name |
|---------|------|-----------------|---------------|
| **Key Vault (main)** | `kvneomcdevuks1` | privatelink.vaultcore.azure.net | `kvneomcdevuks1-pe` |
| **Container Registry** | `crneomcdevuks1` | privatelink.azurecr.io | `crneomcdevuks1-pe` |
| **Cosmos DB (Chat History)** | `cosmos-chat-history-neo-mcdev-uks-1` | privatelink.documents.azure.com | `cosmos-chat-history-neo-mcdev-uks-1-pe` |
| **Cosmos DB (Main)** | `cosmos-main-neo-mcdev-uks-1` | privatelink.documents.azure.com | `cosmos-main-neo-mcdev-uks-1-pe` |
| **Storage (Foundry)** | `stfoundryneomcdevuks1` | blob, file, table, queue | `stfoundryneomcdevuks1-{blob\|file\|table\|queue}-pe` |
| **Storage (RAG)** | `stfilesneomcdevuks1` | blob, file, table, queue | `stfilesneomcdevuks1-{blob\|file\|table\|queue}-pe` |
| **Storage (Template)** | `sttemplateneomcdevuks1` | blob, file, table, queue | `sttemplateneomcdevuks1-{blob\|file\|table\|queue}-pe` |
| **Storage (Output)** | `stoutputneomcdevuks1` | blob, file, table, queue | `stoutputneomcdevuks1-{blob\|file\|table\|queue}-pe` |
| **Azure OpenAI** | `oai-neo-mcdev-uks-1` | privatelink.openai.azure.com | `oai-neo-mcdev-uks-1-pe` |
| **AI Search** | `srch-neo-mcdev-uks-1` | privatelink.search.windows.net | `srch-neo-mcdev-uks-1-pe` |
| **AI Services** | `ais-neo-mcdev-uks-1` | privatelink.cognitiveservices.azure.com | `ais-neo-mcdev-uks-1-pe` |
| **AI Hub** | `hub-neo-mcdev-uks-1` | privatelink.api.azureml.ms | `hub-neo-mcdev-uks-1-pe` |
| **Document Intelligence** | `di-neo-mcdev-uks-1` | privatelink.cognitiveservices.azure.com | `di-neo-mcdev-uks-1-pe` |

**Total Private Endpoints**: ~25+

### DNS Resolution Flow

```
VM/Pod → Query for service.azure.com →
Private DNS Zone → Resolves to private IP →
Private Endpoint → Azure Service
```

Example for Key Vault:
```
kubectl exec pod → kvneomcdevuks1.vault.azure.net →
Private DNS (privatelink.vaultcore.azure.net) →
10.220.x.x (private IP) →
Key Vault (private traffic only)
```

### Network Access Patterns

#### Public Internet
```
Internet -X-> Azure Service (Blocked by default deny)
```

#### VNet Access
```
VM/AKS → Private Endpoint (10.220.x.x) → Azure Service
```

### Special Network Considerations

1. **Key Vault Deployment Sequence**:
   - Phase 1: Public access enabled (for deployment scripts)
   - Phase 2: Public access disabled (final security hardening)

2. **AI Services Hybrid Networking**:
   - Private Endpoint: For DNS resolution and access from VNet
   - Service Endpoint: For VNet-level network rules
   - Network ACL: Deny default, allow AiServiceSubnet

3. **Storage Account Network Isolation**:
   - Default action: Deny
   - Azure Services bypass: Enabled (for trusted Microsoft services)

4. **AKS Outbound**:
   - AKS uses `loadBalancer` outbound type (not NAT gateway)
   - NAT gateway deployed for VM subnet outbound

5. **SQL Public Access**:
   - Currently **Enabled** for development convenience
   - Should be restricted to private endpoint only before production promotion

---

## Naming Standards

### Resource Naming — Deployed Names

| Resource Type | Pattern | Actual Name |
|---------------|---------|-------------|
| **Resource Group** | `rg-{solutionName}` | `rg-neo-mcdev-uks-1` |
| **Virtual Network** | `vnet-{solutionName}` | `vnet-neo-mcdev-uks-1` |
| **NAT Gateway** | `natgw-{solutionName}` | `natgw-neo-mcdev-uks-1` |
| **NAT Gateway Public IP** | `natgw-{solutionName}-pip` | `natgw-neo-mcdev-uks-1-pip` |
| **AKS Cluster** | `aks{solutionShortName}` | `aksneomcdevuks1` |
| **Log Analytics Workspace** | `log-{solutionName}` | `log-neo-mcdev-uks-1` |
| **Application Insights (AI Hub)** | `appi-aih-{solutionName}` | `appi-aih-neo-mcdev-uks-1` |
| **Azure Monitor (Prometheus)** | `{aksName}-prometheus` | `aksneomcdevuks1-prometheus` |
| **Key Vault (main)** | Configurable | `kvneomcdevuks1` |
| **Key Vault (scripts)** | Configurable | `NeologikKeyVault` |
| **Container Registry** | Configurable (globally unique) | `crneomcdevuks1` |
| **Storage Account (Foundry)** | `stfoundry{solutionShortName}` | `stfoundryneomcdevuks1` |
| **Storage Account (RAG)** | `stfiles{solutionShortName}` | `stfilesneomcdevuks1` |
| **Storage Account (Template)** | `sttemplate{solutionShortName}` | `sttemplateneomcdevuks1` |
| **Storage Account (Output)** | `stoutput{solutionShortName}` | `stoutputneomcdevuks1` |
| **Cosmos DB (Chat History)** | `cosmos-chat-history-{solutionName}` | `cosmos-chat-history-neo-mcdev-uks-1` |
| **Cosmos DB (Main)** | `cosmos-main-{solutionName}` | `cosmos-main-neo-mcdev-uks-1` |
| **SQL Server** | (custom) | `sqlsrvneomcdevuks2` |
| **SQL Database** | (custom) | `sqldbneomcdevuks2` |
| **Azure OpenAI** | `oai-{solutionName}` | `oai-neo-mcdev-uks-1` |
| **AI Search** | `srch-{solutionName}` | `srch-neo-mcdev-uks-1` |
| **AI Services** | `ais-{solutionName}` | `ais-neo-mcdev-uks-1` |
| **AI Hub** | `hub-{solutionName}` | `hub-neo-mcdev-uks-1` |
| **AI Project** | `proj-{solutionName}` | `proj-neo-mcdev-uks-1` |
| **Document Intelligence** | `di-{solutionName}` | `di-neo-mcdev-uks-1` |
| **Bing Search** | `bing{solutionShortName}` | `bingneomcdevuks1` |
| **Bot Service** | `bot{solutionShortName}` | `botneomcdevuks1` |
| **Azure Bastion** | `bas-{solutionName}` | `bas-neo-mcdev-uks-1` |
| **Bastion Public IP** | `bastion-{solutionName}-pip` | `bastion-neo-mcdev-uks-1-pip` |
| **Bastion NSG** | `bastion-{solutionName}-nsg` | `bastion-neo-mcdev-uks-1-nsg` |
| **Jumpbox VM** | `vmj{solutionShortName}` | `vmjneomcdevuks1` |
| **GitHub Runner VM** | `vmrunner{solutionShortName}` | `vmrunnerneomcdevuks1` |
| **Application Gateway (AGIC)** | `appgw-{solutionName}` | `appgw-neo-mcdev-uks-1` |
| **App GW Public IP** | `appgw-{solutionName}-pip` | `appgw-neo-mcdev-uks-1-pip` |
| **WAF Policy (AGIC)** | `appgw-{solutionName}-waf-policy` | `appgw-neo-mcdev-uks-1-waf-policy` |
| **Private Endpoint** | `{serviceName}-pe` | e.g. `kvneomcdevuks1-pe` |
| **Custom DNS Zone** | Configurable | `neologik.internal` |

### Managed Identity Naming

| Identity Type | Actual Name |
|---------------|-------------|
| **AKS Cluster Identity** | `idaksclusterneomcdevuks1` |
| **AKS Kubelet Identity** | `idakskubeletneomcdevuks1` |
| **Deployment Script Identity** | `NeologikScriptRunnerServiceConnection` |
| **File Workload Identity** | `idaksworkloadidfileneomcdevuks1` |
| **Classify Workload Identity** | `idaksworkloadidclassifyneomcdevuks1` |
| **NCE API Workload Identity** | `idaksworkloadidnce-apineomcdevuks1` |
| **Ingest Workload Identity** | `idaksworkloadidingestneomcdevuks1` |
| **NL2SQL Workload Identity** | `idaksworkloadidnl2sqlneomcdevuks1` |
| **Bot Workload Identity** | `idaksworkloadidbotneomcdevuks1` |
| **NCE UI Workload Identity** | `idaksworkloadidnceneomcdevuks1` |

### Service Principal Naming

| Service Principal Type | Pattern | Example |
|------------------------|---------|---------|
| **Admin Auth** | `sp-admin-{solutionName}` | `sp-admin-neo-mcdev-uks-1` |
| **Bot Service** | `sp-neologik-{botShortName}-{solutionShortName}` | `sp-neologik-{bot}-neomcdevuks1` |
| **SharePoint** | `sp-sharepoint-{solutionShortName}` | `sp-sharepoint-neomcdevuks1` |

### Key Vault Secret Naming

| Secret Type | Pattern | Example |
|-------------|---------|---------|
| **Storage Connection String** | `{storageAccountName}-conn-string` | `stfoundryneomcdevuks1-conn-string` |
| **OpenAI API Key** | `{openAIName}-api-key` | `oai-neo-mcdev-uks-1-api-key` |
| **AI Search API Key** | `aisearch-api-key` | `aisearch-api-key` |
| **Service Principal Secret** | `{spName}-auth-secret` | `sp-admin-neo-mcdev-uks-1-auth-secret` |
| **Bot Service Secret** | `{botShortName}-app-registration-secret` | `{bot}-app-registration-secret` |
| **AKS SSH Private Key** | `{aksName}-ssh-private-key` | `aksneomcdevuks1-ssh-private-key` |
| **AKS SSH Public Key** | `{aksName}-ssh-public-key` | `aksneomcdevuks1-ssh-public-key` |

## Deployment Sequence

The neo-secure template enforces **sequential deployment** for services with private endpoints to prevent DNS conflicts and ensure stable deployment.

### Deployment Order

```
1. Virtual Network + DNS Zones
   ↓
2. Bastion NSG + App GW NSG
   ↓
3. Log Analytics Workspace
   ↓
4. Key Vault (Phase 1: Public access)
   ↓
5. Container Registry (with private endpoint)
   ↓
6. Cosmos DB Chat History (with private endpoint)
   ↓
7. Cosmos DB Main (with private endpoint)
   ↓
8. SQL Database (with private endpoint)
   ↓
9. AI Foundry Storage (with 4 private endpoints)
   ↓
10. RAG Storage (with 4 private endpoints)
   ↓
11. Template Storage (with 4 private endpoints)
   ↓
12. Output Storage (with 4 private endpoints)
   ↓
13. Azure OpenAI (with private endpoint)
   ↓
14. AI Search (with private endpoint)
   ↓
15. AI Services (with private endpoint + service endpoint)
   ↓
16. Document Intelligence (with private endpoint)
   ↓
17. AI Hub (with private endpoint)
   ↓
18. AI Project
   ↓
19. AKS Cluster (private)
   ↓
20. Azure Monitor (Prometheus)
   ↓
21. Bastion
   ↓
22. Jumpbox VM
   ↓
23. GitHub Runner VM
   ↓
24. Key Vault (Phase 2: Private only)
```

### Why Sequential Deployment?

1. **Prevents DNS Conflicts**: Private endpoints update DNS zones — sequential deployment avoids race conditions
2. **Dependency Management**: Later resources may need to access earlier ones via private endpoint
3. **Stable Private Endpoint Creation**: Azure sometimes struggles with concurrent private endpoint operations
4. **Key Vault Access**: Deployment scripts need Key Vault access before it's locked down

### Deployment Time

- **Sequential deployment**: ~45-60 minutes (due to private endpoint creation delays)
- **Comparison**: Public deployments typically take ~20-30 minutes

---

## Security Highlights

### Network Isolation
- ✅ All PaaS services on private endpoints (25+ endpoints)
- ✅ No public internet access to data plane (except SQL in dev)
- ✅ VNet-integrated AI Services (service endpoint)
- ✅ Private AKS cluster (API server not publicly accessible)
- ✅ No public IPs on VMs (Bastion access only)

### Access Control
- ✅ Key Vault with RBAC (no access policies)
- ✅ Managed identities for service-to-service
- ✅ Storage account network deny by default
- ✅ Container Registry admin user disabled

### Logging and Monitoring
- ✅ 90-day log retention
- ✅ Diagnostic settings on all resources
- ✅ Centralized Log Analytics (`log-neo-mcdev-uks-1`)
- ✅ Prometheus metrics via `aksneomcdevuks1-prometheus`

### Data Protection
- ✅ Key Vault soft delete (90 days)
- ✅ Storage account redundancy (GZRS)
- ✅ SQL Database auto-pause and backups

### Management Access
- ✅ Azure Bastion for VM access (no public IPs)
- ✅ Private AKS cluster (requires VNet access)
- ✅ Jumpbox VM (`vmjneomcdevuks1`) for administrative tasks
- ✅ GitHub Runner VM (`vmrunnerneomcdevuks1`) with private access to AKS/Azure

### Dev Environment Notes
- ✅ SQL Server public access **Disabled**

---

## Summary

The **Moneycorp Dev** neo-secure deployment provides:
- ✅ **Enterprise-grade security** with private endpoints and network isolation
- ✅ **Private AKS cluster** (`aksneomcdevuks1`) with Bastion and Jumpbox management
- ✅ **Standard AKS tier** with autoscaling node pools (Standard_D2s_v5 system, Standard_E2s_v6 user)
- ✅ **All AI capabilities** (OpenAI, AI Search, AI Hub/Project, Document Intelligence) on private network
- ✅ **6 OpenAI model deployments** (GPT-4.1-mini, GPT-4.1-nano, GPT-5-mini, GPT-5.2, embedding)
- ✅ **25+ private endpoints** eliminating public internet exposure
- ✅ **Custom DNS zone** (`neologik.internal`) for internal service discovery
- ✅ **Management VMs** (Jumpbox, GitHub Runner) for secure administration

**Tenant**: `moneycorp.local` (ID: `234b7362-627a-4a31-9a1f-d340c11da1e0`)  
**Subscription**: Moneycorp UK Neologik-Development-1 (`3ed8c3f5-61bf-43b7-af55-b62ebaa53064`)  
**Resource Group**: `rg-neo-mcdev-uks-1` | **Location**: UK South

---

**Document Version**: 1.0  
**Last Updated**: April 15, 2026  
**Template File**: `bicep/neo-secure.bicep`  
**Based On**: neo-secure-deployment-reference.md v1.0
