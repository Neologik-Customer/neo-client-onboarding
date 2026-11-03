# Values to Collect Before Onboarding

## Overview

This document lists the values to collect and the decisions to make before you run the onboarding script, `Install-NeologikEnvironment.ps1`.

| Section | Who provides the values | Does the onboarding script ask for the values? |
|---|---|---|
| [1. Agreed with Neologik](#1-agreed-with-neologik) | You and Neologik agree the values together | The onboarding script asks for the host name only |
| [2. Organisation](#2-organisation) | You | Yes |
| [3. Environment](#3-environment) | You | Yes |
| [4. Azure](#4-azure) | You | The onboarding script asks for the Azure region. The onboarding script takes the subscription from your sign-in, or from the parameter `-SubscriptionName` |
| [5. Decisions](#5-decisions) | You | Yes |

## Contents

1. [Agreed with Neologik](#1-agreed-with-neologik)
2. [Organisation](#2-organisation)
3. [Environment](#3-environment)
4. [Azure](#4-azure)
5. [Decisions](#5-decisions)
6. [Answer file](#answer-file)

## 1. Agreed with Neologik

| Item | Detail |
|---|---|
| Deployment type | Standard or Private Endpoint. A Standard environment has public endpoints, protected by Microsoft Entra ID authorisation. A Private Endpoint environment has private endpoints and a private network. The deployment by Neologik applies the network settings of the deployment type. [NETWORK-GUIDE.md](NETWORK-GUIDE.md) states the address ranges and the DNS names of each deployment type |
| Host name | The fully qualified host name that your users enter to reach the environment, for example `neologik.contoso.com`. Confirm the host name with the person who manages your DNS. The TLS certificate is issued for the host name |
| TLS certificate | Choose a Neologik-managed certificate, which Neologik obtains from the certificate authority ZeroSSL for the host name and renews every 60 days, or your own certificate, which an administrator imports into the Key Vault after the onboarding script runs. With a Neologik-managed certificate, a DNS zone that publishes CAA records needs a record that allows `sectigo.com` |
| vCPU quota | The deployment needs enough vCPU quota in the subscription and the Azure region. The standard environment runs two-vCPU nodes in its system pool and four-vCPU nodes in its user pool, both in the Dsv7 family: with the standard pool maximums of 5 system nodes and 10 user nodes that is 50 vCPU of the family. When the Azure region or the quota does not allow Dsv7, Neologik chooses Dsv6, then Dasv7. Ask Neologik for the number for your environment |

### Check the vCPU quota

The onboarding script does not check the vCPU quota. Check the vCPU quota in the Azure portal.

1. Open **Subscriptions** and select the subscription.
2. Select **Usage + quotas**.
3. Filter by the Azure region of the environment.
4. Search for **Dsv7**. The line **Standard Dsv7 Family vCPUs** shows the usage and the limit.

To raise the limit, select the quota line and select **New Quota Request**.

## 2. Organisation

| Value | Detail | Default |
|---|---|---|
| Organisation name | The full name of your organisation, for example `Contoso Ltd` | None. The value is required |
| Organisation code | Exactly three characters. Use letters and digits only, for example `abc`. The onboarding script converts the code to lower case. The organisation code is part of the name of each resource | None. The value is required |

## 3. Environment

| Value | Detail | Default |
|---|---|---|
| Environment type | `dev` for development or `prd` for production | `dev` |
| Environment index | A number from 01 to 99. Use `01` for the first environment of each environment type | `01` |
| Host name | The host name agreed in section 1. The onboarding script removes an `https://` prefix and a path, and converts the host name to lower case | None. The value is required |

## 4. Azure

| Value | Detail | Default |
|---|---|---|
| Subscription | The subscription that holds the environment. The onboarding script uses the subscription of your sign-in. To use another subscription, name the subscription with the parameter `-SubscriptionName` | The subscription of your sign-in |
| Azure region | The name of an Azure region, for example `uksouth`, `ukwest`, `northeurope`, `westeurope`, `switzerlandnorth`, `eastus` or `westus`. Agree the Azure region with Neologik, because some Azure services are not available in every Azure region | `uksouth` |

## 5. Decisions

| Decision | Detail | Default |
|---|---|---|
| Resource names | The onboarding script proposes a standard name for the resource group, the Key Vault, the storage account and the three managed identities. When you have a naming standard for Azure, prepare the six names before the run. Send the naming standard to Neologik, so that the deployment names the other resources to the same standard | The standard names |
| Resource tags | Decide whether the onboarding script tags the resources that the onboarding script creates. Decide which further tags to add. Choose tags when an Azure Policy in your subscription refuses a resource without tags | The onboarding script tags the resources |
| Neologik guest users | Decide whether the onboarding script invites the Neologik support accounts in `NeologikGuestUsers.txt` as guests. The alternative is to create accounts for Neologik support staff in your own tenant. For the alternative, have the exact address of each account ready. Each address must match the mail address or the user principal name of the account | The onboarding script invites the accounts |
| Deployment service principal | Decide whether the onboarding script creates the deployment service principal, or you create the deployment service principal. To create the deployment service principal yourself, follow [CREATE-SP-GUIDE.md](CREATE-SP-GUIDE.md). Have the object ID of the enterprise application ready. Give the client secret to the onboarding script. Alternatively, add the client secret to the Key Vault before the first deployment | The onboarding script creates the deployment service principal |

The onboarding script asks no question about agents. A platform operator creates agents and channels in the Neologik Context Engine after Neologik deploys the environment.

## Answer file

You can prepare every value in an answer file before the run.

1. Copy `inputs-example.json` to `inputs.json` in the folder of the onboarding kit.
2. Enter your values in `inputs.json`.
