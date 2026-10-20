# Network Guide: Address Ranges and DNS Names

## Overview

The deployment by Neologik builds one virtual network inside your subscription. Every address range in the virtual network is a setting of your environment, chosen before the deployment. You allocate no addresses yourself. This document states the default ranges and the DNS names that the deployment creates. Check them against your existing networks before onboarding.

Read this document when you are considering a `neo-secure` environment, or when you plan to connect a Neologik Platform environment to your own network.

| Reader | What to do |
|---|---|
| The person who plans your networks | Check that the default ranges do not overlap a network that you will peer with the environment. Tell Neologik the ranges that you want changed, before onboarding |
| The person who manages your DNS | Create the public DNS record for the host name after the deployment, as described in [FINISHING-STEPS-GUIDE.md](FINISHING-STEPS-GUIDE.md). Forward the private DNS zones to Azure when you peer the environment with your own network |
| Approvers | Note that the environment has one public entry point, the host name, and one public outbound address |

## Contents

1. [The two deployment types](#the-two-deployment-types)
2. [The virtual network of a `neo-secure` environment](#the-virtual-network-of-a-neo-secure-environment)
3. [The virtual network of a `neo-small` environment](#the-virtual-network-of-a-neo-small-environment)
4. [Changing a range](#changing-a-range)
5. [Private DNS zones](#private-dns-zones)
6. [Public addresses and the public DNS record](#public-addresses-and-the-public-dns-record)
7. [What to confirm before onboarding](#what-to-confirm-before-onboarding)

## The two deployment types

| Deployment type | Network position | Entry point for users |
|---|---|---|
| `neo-secure` | The Azure services of the environment are reached through private endpoints inside the virtual network. The firewall of each service refuses a request from the internet | Application Gateway for Containers, with a web application firewall |
| `neo-small` | The Azure services of the environment have public endpoints. Microsoft Entra ID authorisation and the firewall of each service protect them | A load balancer with a public IP address, in front of the ingress controller of the cluster |

Both deployment types use the same default address space. A `neo-secure` environment uses more subnets, because the private endpoints, the deployment VM and Azure Bastion each need one.

## The virtual network of a `neo-secure` environment

The virtual network has the address space `10.0.0.0/8` by default. The deployment creates these subnets inside the address space.

| Subnet | Default range | Purpose |
|---|---|---|
| `systempoolnodesubnet` | `10.200.0.0/16` | The nodes of the system node pool of the Kubernetes cluster |
| `systempoolpodsubnet` | `10.201.0.0/16` | The pods of the system node pool |
| `userpool1nodesubnet` | `10.202.0.0/16` | The nodes of the workload node pool |
| `userpool1podsubnet` | `10.203.0.0/16` | The pods of the workload node pool. Every Neologik Platform service runs here |
| `AppSubnet` | `10.205.0.0/16` | Reserved for Azure Container Apps |
| `AiServiceSubnet` | `10.206.0.0/16` | Network integration of the Azure AI services |
| `PrivateEndpointSubnet` | `10.220.0.0/16` | The private endpoint of every Azure service of the environment |
| `VmSubnet` | `10.252.0.0/16` | The deployment VM, which runs the deployments by Neologik |
| `AzureBastionSubnet` | `10.253.0.0/16` | Azure Bastion, which gives Neologik support access to the deployment VM. Azure fixes the name of this subnet |
| `ApplicationGatewayForContainersSubnet` | `10.254.0.0/16` | Application Gateway for Containers, the entry point for users |

The Kubernetes cluster also uses an internal service range. The range is not a subnet of the virtual network. The range must not overlap the virtual network or any network peered with the virtual network.

| Internal range | Default value | Purpose |
|---|---|---|
| Kubernetes service range | `10.210.0.0/16` | The internal addresses of the services inside the cluster |
| Kubernetes DNS address | `10.210.0.10` | The DNS service of the cluster, inside the service range |

**Example.** Contoso peers the environment with a hub network at `10.100.0.0/16`. The hub network overlaps the address space `10.0.0.0/8` but no subnet and no internal range. Azure refuses a peering between overlapping address spaces, so Contoso asks Neologik to set the address space to `10.192.0.0/10` before onboarding. Every default subnet and the internal service range fit inside `10.192.0.0/10`, so nothing else changes.

## The virtual network of a `neo-small` environment

The virtual network has the address space `10.0.0.0/8` by default. The deployment creates the four subnets of the Kubernetes cluster and the subnet of the entry point. No private endpoint subnet, management VM subnet or Azure Bastion subnet exists, because the Azure services of the environment have public endpoints.

| Subnet | Default range | Purpose |
|---|---|---|
| `systempoolnodesubnet` | `10.200.0.0/16` | The nodes of the system node pool of the Kubernetes cluster |
| `systempoolpodsubnet` | `10.201.0.0/16` | The pods of the system node pool |
| `userpool1nodesubnet` | `10.202.0.0/16` | The nodes of the workload node pool |
| `userpool1podsubnet` | `10.203.0.0/16` | The pods of the workload node pool. Every Neologik Platform service runs here |
| `ApplicationGatewayForContainersSubnet` | `10.254.0.0/16` | Application Gateway for Containers, when the environment uses that entry point instead of the load balancer |

The Kubernetes service range and the Kubernetes DNS address are the same as for a `neo-secure` environment.

## Changing a range

Every range in this document is a setting of your environment. Neologik sets the ranges before the first deployment. Tell Neologik the ranges that you need before onboarding, with the reason, such as a peering with an existing network.

A range cannot change after the environment is built. The Kubernetes cluster binds to the ranges at creation. A change to a range means a new environment.

Keep each subnet at `/16` unless you have a reason to reduce a subnet. The pod subnets need the most addresses, because every pod takes one address. A smaller pod subnet limits how far the cluster can scale.

## Private DNS zones

A `neo-secure` environment reaches each Azure service through a private endpoint. The deployment creates one private DNS zone for each kind of Azure service. The deployment links each private DNS zone to the virtual network and records the private address of each endpoint in the matching zone. Inside the virtual network, the public name of each service answers with the private address.

| Private DNS zone | Azure service |
|---|---|
| `privatelink.vaultcore.azure.net` | Key Vault |
| `privatelink.blob.core.windows.net` | Storage, blob |
| `privatelink.file.core.windows.net` | Storage, file |
| `privatelink.table.core.windows.net` | Storage, table |
| `privatelink.queue.core.windows.net` | Storage, queue |
| `privatelink.cognitiveservices.azure.com` | Azure AI services |
| `privatelink.services.ai.azure.com` | Azure AI Foundry |
| `privatelink.openai.azure.com` | Azure OpenAI |
| `privatelink.documents.azure.com` | Azure Cosmos DB |
| `privatelink.azurecr.io` | Container registry |
| `privatelink.search.windows.net` | Azure AI Search |
| `privatelink.azurewebsites.net` | App Service and Functions |
| `privatelink.api.azureml.ms` | Azure AI hub |
| `privatelink.database.windows.net` | Azure SQL |
| `neologik.internal` | Internal names of the environment. Neologik can set another name before onboarding |

You need to do nothing with the private DNS zones while the environment stands alone. Your users reach the environment through the host name, over the public entry point.

When you peer the environment with your own network, your DNS resolvers must answer for these zones with the private addresses. Link each private DNS zone to your own virtual network. Or forward each zone from your resolvers to an Azure DNS Private Resolver in a network linked to the zones. Without this, a request from your network receives the public address of the service. The service refuses the request, because the firewall of the service refuses a request from the internet.

A `neo-small` environment creates no private DNS zone.

## Public addresses and the public DNS record

An environment has two public addresses.

| Public address | Purpose | What you do |
|---|---|---|
| The entry point for users | Your users reach the host name of the environment, for example `neologik.contoso.com`, through this address | Create the public DNS record for the host name, as described in [FINISHING-STEPS-GUIDE.md](FINISHING-STEPS-GUIDE.md) |
| The outbound address | Every call from the environment to a service outside the virtual network leaves through one static public IP address, through a NAT gateway | Add the address to an allow list when a service that the environment calls restricts callers by address |

The type of the public DNS record depends on the entry point. Application Gateway for Containers has no static IP address, so the host name needs a CNAME record to the name of the entry point. A load balancer has a static public IP address, so the host name needs an A record. Neologik sends you the target after the deployment, and the finishing-steps guide gives the steps for both types.

**Example.** Contoso chose a `neo-secure` environment with the host name `neologik.contoso.com`. After the deployment, Neologik sends the name of the entry point. The person who manages the DNS of `contoso.com` creates a CNAME record for `neologik` with that name as the value. Users open `https://neologik.contoso.com` and reach the environment.

## What to confirm before onboarding

Send Neologik the answers to these questions with the values in [PRE-ONBOARDING-INFO-GATHERING.md](PRE-ONBOARDING-INFO-GATHERING.md).

| Question | Why Neologik asks |
|---|---|
| Will you peer the environment with one of your networks, now or later? | A peering needs an address space with no overlap, and needs your resolvers to forward the private DNS zones |
| Which of your networks must the address space avoid? | Neologik sets the address space and the subnets before the first deployment. A range cannot change after the environment is built |
| Do you need a different internal DNS zone name? | The default is `neologik.internal` |
| Which services that the environment calls restrict callers by IP address? | Neologik sends you the outbound address after the deployment, for your allow lists |
| Who manages the DNS zone of the host name? | That person creates the public DNS record after the deployment |
