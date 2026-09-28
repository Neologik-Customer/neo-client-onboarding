# Values to Collect Before Onboarding

## Overview

Collect the values and make the decisions below before you run `Install-NeologikEnvironment.ps1`. The script asks for the values in sections 2 to 5, except the subscription, which it takes from your sign-in. The items in section 1 are agreed with Neologik beforehand; of these, the script asks for the host name only.

## Contents

1. [Agreed with Neologik](#1-agreed-with-neologik)
2. [Organisation](#2-organisation)
3. [Environment](#3-environment)
4. [Azure](#4-azure)
5. [Decisions](#5-decisions)

## 1. Agreed with Neologik

| Item | Detail |
|---|---|
| Deployment type | `neo-small`: public endpoints, protected by Microsoft Entra ID authorisation. `neo-secure`: private endpoints and a private network. The deployment that follows onboarding applies the network settings of the chosen type |
| Host name | The fully qualified host name users will use to reach the environment, for example `neologik.contoso.com`. Confirm it with whoever manages your DNS. Your TLS certificate must be issued for this name |
| vCPU quota | The deployment needs sufficient vCPU quota in the target subscription and region. Ask Neologik for the number of cores your deployment type needs, then check it as described below |

**Checking the vCPU quota.** In the Azure portal, open **Subscriptions**, select the subscription and select **Usage + quotas**. Filter by the target region and search for **Dsv6** (the Standard Dsv6 Family vCPUs line) to see the usage against the limit. To raise the limit, select the quota line and select **New Quota Request**. The onboarding script does not check the quota.

## 2. Organisation

| Value | Detail | Default |
|---|---|---|
| Organisation name | Your organisation's full name, for example `Contoso Ltd` | None; required |
| Organisation code | Exactly three characters, letters and digits only, for example `abc`. Converted to lower case. It forms part of every resource name | None; required |

## 3. Environment

| Value | Detail | Default |
|---|---|---|
| Environment type | `dev` for development or `prd` for production | `dev` |
| Environment index | A number from 01 to 99. Use `01` for the first environment of a type | `01` |
| Host name | The name agreed in section 1. Any `https://` prefix or path is removed and the name is converted to lower case | None; required |

## 4. Azure

| Value | Detail | Default |
|---|---|---|
| Subscription | The subscription that will hold the environment. The script uses the subscription of your sign-in, or the one you name with `-SubscriptionName` | The subscription of your sign-in |
| Azure region | A valid Azure region name, for example `uksouth`, `ukwest`, `northeurope`, `westeurope`, `switzerlandnorth`, `eastus` or `westus`. Agree the region with Neologik: not every Azure service is available in every region | `uksouth` |

## 5. Decisions

| Decision | Detail | Default |
|---|---|---|
| Resource naming | The script computes a standard name for everything it creates (resource group, Key Vault, storage account, managed identities) and offers each as a default. If your organisation has its own Azure naming convention, prepare the names in advance and share the convention with Neologik, so that the deployment applies it to the resources it creates | The standard names |
| Resource tags | Whether the script tags the resources it creates, and any tags of your own to add. Choose tagging if your Azure Policies refuse untagged resources | Tagged |
| Cost report recipients | The addresses that receive the daily Azure cost report, or none | Neologik's cost-report address |
| Neologik guest users | Whether the Neologik support accounts listed in `NeologikGuestUsers.txt` are invited as guests. If you provide accounts for the Neologik team in your own tenant instead, decline the invitations and have the exact addresses of those accounts to hand: each must match the account's mail address or user principal name | Invited |
| Deployment service principal | Whether the script creates the deployment service principal or you create it yourself. If you create it, follow [CREATE-SP-GUIDE.md](CREATE-SP-GUIDE.md) and have ready its enterprise application object ID and, optionally, its client secret | Created by the script |

The script does not ask about agents. Agents and their channels are created in the Neologik Context Engine after the environment is deployed.

Every value can be prepared in an answer file: copy `inputs-example.json` to `inputs.json` in the kit folder and complete it.
