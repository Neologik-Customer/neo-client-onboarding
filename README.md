# Neologik Onboarding Kit

## Overview

This kit prepares your Azure subscription and your Microsoft Entra tenant for a Neologik Platform environment. It is written for the administrator who runs the onboarding and for the security team who reviews it beforehand.

Neologik deploys and operates the platform through one deployment identity. That identity can deploy Azure resources into one resource group. On the subscription it holds two roles only, Reader and Cost Management Contributor, which give no control of resources. In your directory it holds two Microsoft Graph application permissions, which let it manage only the application registrations it owns and the credentials of the environment's agent identity blueprint.

Every script in the kit is supplied in full, so that it can be reviewed before anything is run. [QUICK-REFERENCE.md](QUICK-REFERENCE.md) lists every change the onboarding script makes and every permission it grants.

## Contents

1. [Terms used in this kit](#terms-used-in-this-kit)
2. [What the kit contains](#what-the-kit-contains)
3. [Onboarding at a glance](#onboarding-at-a-glance)
4. [Before you start](#before-you-start)
5. [Run the onboarding script](#run-the-onboarding-script)
6. [Questions the script asks](#questions-the-script-asks)
7. [After the script completes](#after-the-script-completes)
8. [After Neologik deploys the environment](#after-neologik-deploys-the-environment)
9. [Help](#help)

## Terms used in this kit

| Term | Meaning |
|---|---|
| Neologik Context Engine (NCE) | The platform's administration web application, at `https://<your host name>/nce`, where your operators configure agents and Apps |
| Agent | A conversational or autonomous assistant configured in the NCE. An agent may have channels such as Microsoft Teams |
| App | A business application installed on the platform alongside the agents |
| Deployment identity | The service principal that Neologik's deployment uses to create Azure resources in your resource group |
| Platform Sign-in application | The application registration through which your users sign in to the NCE and to Apps |
| Agent identity blueprint | The Microsoft Entra Agent ID object under which the platform's agent identities and agent user accounts are created |
| Short name | The organisation code, the environment type and the environment index together, for example `abcprd01`. It forms part of the name of everything the onboarding script creates |

## What the kit contains

### Scripts

| Script | When it is run | Guide |
|---|---|---|
| `Install-NeologikEnvironment.ps1` | Once, before the environment is deployed. Creates the Azure resources, the security groups, the deployment identity, the Platform Sign-in application and the agent identity blueprint | This document, [TECHNICAL-REFERENCE.md](TECHNICAL-REFERENCE.md) and [QUICK-REFERENCE.md](QUICK-REFERENCE.md) |
| `Update-NeologikEnvironmentAccess.ps1` | When Neologik asks for it: before an environment moves to Neologik Platform version 5, and when an agent or App is to work unattended in Microsoft 365. Neologik sends the complete command | [ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md](ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md) |
| `Export-NeologikCertificate.ps1` | When you prepare your TLS certificate as a PFX file. Runs on the workstation only | [PFX-CERT-GUIDE.md](PFX-CERT-GUIDE.md) |
| `Register-NeologikResourceProviders.ps1` | When the onboarding script reports Azure resource provider registrations still pending | [TECHNICAL-REFERENCE.md](TECHNICAL-REFERENCE.md#resource-provider-registration) |
| `Upgrade-TeamsAppInstallations.ps1` | After Neologik supplies an updated Teams app package. Upgrades every user's installed Neologik Teams app to the latest version in your catalogue | [TEAMS-APP-UPGRADE-GUIDE.md](TEAMS-APP-UPGRADE-GUIDE.md) |

### Documents

| Document | Purpose |
|---|---|
| [PRE-ONBOARDING-INFO-GATHERING.md](PRE-ONBOARDING-INFO-GATHERING.md) | The values to collect before the onboarding run |
| [QUICK-REFERENCE.md](QUICK-REFERENCE.md) | For your security team: every change the onboarding script makes and every permission it grants |
| [secure-overview.md](secure-overview.md) | A one-page summary of the access the onboarding script grants |
| [CREATE-SP-GUIDE.md](CREATE-SP-GUIDE.md) | Optional: creating the deployment service principal yourself |
| [PFX-CERT-GUIDE.md](PFX-CERT-GUIDE.md) | Preparing the TLS certificate |
| [FINISHING-STEPS-GUIDE.md](FINISHING-STEPS-GUIDE.md) | The steps that follow Neologik's deployment |
| [AGENT-ACCOUNT-ACCESS-GUIDE.md](AGENT-ACCOUNT-ACCESS-GUIDE.md) | Giving an agent account access to a mailbox, a site or a team |
| [ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md](ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md) | What `Update-NeologikEnvironmentAccess.ps1` checks and changes |
| [TEAMS-APP-UPGRADE-GUIDE.md](TEAMS-APP-UPGRADE-GUIDE.md) | Rolling out an updated Teams app |
| [TECHNICAL-REFERENCE.md](TECHNICAL-REFERENCE.md) | The onboarding script in detail: parameters, naming, steps and outputs |
| [VERSION_HISTORY.md](VERSION_HISTORY.md) | The versions of this kit |

### Supporting files

| File | Purpose |
|---|---|
| `NeologikGuestUsers.txt` | The Neologik support accounts the onboarding script offers to invite as guests. Review it before the run |
| `resource-providers.txt` | The Azure resource providers and preview features the platform requires |
| `inputs-example.json` | A template for the optional answer file, `inputs.json` |
| `cert\` | The folder in which `Export-NeologikCertificate.ps1` looks for your certificate files |
| `tests\` | The automated tests of the scripts |
| `LICENSE` | The licence under which the kit is supplied |

## Onboarding at a glance

| Stage | Who | What happens |
|---|---|---|
| 1. Onboarding | Your Global Administrator, who is also Owner of the subscription, runs `Install-NeologikEnvironment.ps1` | The Azure resources, the security groups, the deployment identity, the Platform Sign-in application and the agent identity blueprint are created |
| 2. Certificate | Your administrator | The TLS certificate for the environment's host name is imported into the Key Vault |
| 3. Deployment | Neologik | Every platform service is deployed to your resource group |
| 4. DNS | Your DNS administrator | The environment's host name is pointed at the deployment |
| 5. Consent | Your Global Administrator | Administrator consent is given for the sign-in applications, from the links Neologik supplies |
| 6. Teams and user access | Your Teams administrator and your Microsoft Entra administrator | The Teams app is published and users are added to the access groups |

## Before you start

| Requirement | Detail |
|---|---|
| Azure role | **Owner** on the subscription. Contributor is not sufficient, because the script assigns Azure roles |
| Microsoft Entra role | **Global Administrator**. The script creates the application registrations and the agent identity blueprint, grants Microsoft Graph application permissions, assigns groups to the Platform Sign-in application and adds the SQL managed identity to the Directory Readers role |
| Workstation | Windows 10 or Windows 11, with an internet connection |
| PowerShell | PowerShell 7.4 or later. Windows PowerShell 5.1 cannot run the script |
| Host name | The fully qualified host name of the environment, for example `neologik.contoso.com`, agreed with Neologik and with whoever manages your DNS |
| Values | The values listed in [PRE-ONBOARDING-INFO-GATHERING.md](PRE-ONBOARDING-INFO-GATHERING.md) |

The script checks both roles before it creates anything and stops if either is missing.

## Run the onboarding script

### 1. Extract the kit

Extract the kit to a folder of your choice, for example `C:\Neologik`. Keep the files together: the onboarding script reads `NeologikGuestUsers.txt`, `resource-providers.txt` and, if you create one, `inputs.json` from its own folder.

### 2. Open PowerShell 7

1. Open the **Start** menu and type `PowerShell`.
2. Select **PowerShell 7**. Do not choose Windows PowerShell.
3. Confirm the version:

```powershell
$PSVersionTable.PSVersion
```

The version must be 7.4 or later. If PowerShell 7 is not installed, install it from https://aka.ms/powershell.

### 3. Go to the kit folder

```powershell
cd C:\Neologik
```

### 4. Allow the scripts to run in this session

```powershell
Get-ChildItem .\*.ps1 | Unblock-File
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

The first command marks the scripts of the kit as trusted on this workstation. The second applies to the current PowerShell window only and is not kept.

### 5. Start the script

```powershell
.\Install-NeologikEnvironment.ps1
```

### 6. Follow the prompts

The script proceeds in this order:

| Stage | What you do |
|---|---|
| Terms | Read the Neologik Terms of Use and Privacy Policy, then type `I ACCEPT` |
| Modules | If the script offers to install the Azure and Microsoft Graph modules, press Enter to accept. They are installed for your user account only |
| Sign-in | If you are already signed in to Azure, the script shows the account and asks whether to sign in again. Press Enter to continue with that account, or type `Y` to change it. Otherwise a browser window opens for you to sign in |
| Subscription and permissions | The script shows the subscription it will use and verifies the two roles |
| Configuration | Answer the questions described in the next section |
| Summary | Review the configuration summary and confirm |
| Creation | The script creates the resources. Leave the window open until the completion summary appears |

### 7. If the run is interrupted

The script records its progress in `NeologikCheckpoint.json`, beside the script. Run the script again and accept the offer to resume: your answers are restored, and each step reuses what it has already created. The checkpoint never holds a secret and is deleted when the script completes.

## Questions the script asks

Each question shows a default or an example. Press Enter to accept a default, or type a value. The script repeats a question until the value is valid.

| Question on screen | What to enter | Default |
|---|---|---|
| Organization Code | Your three-character organisation code: letters and digits only, converted to lower case | None |
| Environment Type | `dev` for development or `prd` for production | `dev` |
| Organization Name | Your organisation's full name | None |
| Bot Hostname (full FQDN) | The environment's fully qualified host name, for example `neologik.contoso.com`. Any `https://` prefix or path is removed | None |
| Azure Region | The Azure region for the resources, for example `uksouth`. Type `list` to see every region available to the subscription | `uksouth` |
| Environment Index Number | A number from 01 to 99 that distinguishes environments of the same type | `01` |
| Resource Group Name, Key Vault Name, Deployment Storage Account Name, Script Runner Managed Identity Name, SQL Managed Identity Name | Press Enter to accept each standard name. Type a different name only if your organisation has its own naming convention | The standard name, shown on screen |
| Budget Cost-Report Email Recipient(s) | One or more addresses, separated by commas, to receive the daily Azure cost report, or `none` to disable the report | Neologik's cost-report address, shown on screen |
| Apply Azure resource tags to created resources? | `true` to tag every resource the script creates with Vendor, ApplicationName, ManagedBy, Environment, Solution and DeploymentDate. Choose `true` if your Azure Policies refuse untagged resources | `true` |
| Custom resource tags | Optional additional tags as comma-separated `key=value` pairs. A custom tag replaces a standard tag of the same name | None |
| Invite Neologik guest users into this tenant? | `Y` to invite the accounts in `NeologikGuestUsers.txt`, which are listed on screen first. You may then add further addresses, one per line. `N` if you provide accounts for the Neologik team in your own tenant | `Y` |
| Add existing accounts to the security groups? | Asked only when you decline the invitations. `Y` to add accounts you have already created, from the file or typed at the prompt. No invitation is sent. An address with no matching account is reported and passed over | `N` |
| Use a service principal you have already created for deployment? | `Y` if you created the deployment service principal yourself, as described in [CREATE-SP-GUIDE.md](CREATE-SP-GUIDE.md). Have its enterprise application object ID to hand | `N` |

You are not asked about agents. Agents and their channels are created in the NCE after the environment is deployed.

**Accounts added to the security groups.** Every account invited or added through these questions joins all four Neologik security groups, including the Admin User Group, which carries Azure administration rights on the resource group. List only the accounts that should hold Neologik administration and support access. Your own users are added to the group they need after deployment, as described in [FINISHING-STEPS-GUIDE.md](FINISHING-STEPS-GUIDE.md).

**Answer file.** Every answer can be prepared in advance. Copy `inputs-example.json` to `inputs.json` in the kit folder and complete it; each value then appears as the default for its question. See [TECHNICAL-REFERENCE.md](TECHNICAL-REFERENCE.md#answer-file).

## After the script completes

The completion summary lists everything that was created. Two files are written to the kit folder:

| File | Content |
|---|---|
| `Neologik_<org><index>_Configuration_<timestamp>.json` | The configuration Neologik needs for the deployment: names, ids and the addresses of the accounts invited or added. It contains no secret |
| `NeologikOnboarding_<timestamp>.log` | The log of the run |

### 1. Confirm that Neologik has the configuration file

The script uploads the configuration file to the deployment storage account, where Neologik reads it. If the completion summary reports that the upload failed, send the file to support@neologik.ai. Keep the log file with your change records.

### 2. Confirm any pending resource provider registrations

If the completion summary lists resource providers that are still registering, confirm them before the deployment:

```powershell
.\Register-NeologikResourceProviders.ps1
```

### 3. Import your TLS certificate

1. Prepare a `.pfx` file for the environment's host name, as described in [PFX-CERT-GUIDE.md](PFX-CERT-GUIDE.md).
2. In the Azure portal, open the Key Vault named in the completion summary.
3. Select **Certificates**, then **Generate/Import**.
4. Choose **Import**, name the certificate `keyvault-neo-ingress`, select the `.pfx` file and enter its password.
5. Select **Create**.

The password is used at import only and is not stored. Do not send the `.pfx` file or its password to Neologik.

If you cannot produce a `.pfx` file, upload the private key, the server certificate and the certificate authority bundle to the `certificate` container of the deployment storage account named in the completion summary, and tell Neologik. The deployment then assembles the certificate from those files. See [TECHNICAL-REFERENCE.md](TECHNICAL-REFERENCE.md#the-tls-certificate).

### 4. Tell Neologik that the environment is ready

Neologik deploys the platform to your resource group and confirms when the deployment is complete.

## After Neologik deploys the environment

[FINISHING-STEPS-GUIDE.md](FINISHING-STEPS-GUIDE.md) describes the remaining steps:

1. Create the DNS record for the host name.
2. Give administrator consent for the sign-in applications.
3. Publish the Teams app.
4. Give your users access.
5. Give an agent account access to your resources, where an agent works unattended.

## Help

Email support@neologik.ai and attach the log file of the run. The log contains no secret.
