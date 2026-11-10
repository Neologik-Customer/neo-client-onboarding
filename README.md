# Neologik Onboarding Kit

## Overview

The Neologik onboarding kit is the set of scripts and documents in this folder. An administrator uses the onboarding kit to prepare your Azure subscription and your Microsoft Entra tenant for one Neologik Platform environment.

This document is the place to start. This document has two readers.

| Reader | Where to read |
|---|---|
| Administrators | [Before you start](#before-you-start) and the sections that follow |
| Approvers | [QUICK-REFERENCE.md](docs/QUICK-REFERENCE.md) and [secure-overview.md](docs/secure-overview.md) |

### The access of the deployment identity

Neologik deploys and operates the Neologik Platform through one deployment identity.

| Subject | Position |
|---|---|
| Azure resources | The deployment identity deploys Azure resources into one resource group |
| Azure subscription | The deployment identity holds three roles on the subscription: Reader, Cost Management Contributor, and Role Based Access Control Administrator limited to assigning two roles, Reader and Cost Management Reader, to service principals only. These roles change no Azure resource other than cost configuration, support requests and assignments of the two assignable roles |
| Microsoft Graph | The deployment identity holds two Microsoft Graph application permissions in your directory: `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` |
| Application registrations | The permission `Application.ReadWrite.OwnedBy` lets the deployment identity manage only the application registrations that the deployment identity owns |
| Agent identity blueprint | The permission `AgentIdentityBlueprint.AddRemoveCreds.All` lets the deployment identity add and remove credentials on the agent identity blueprint of the environment |
| Sign-in | A Neologik deployment signs in as the deployment identity with the client secret, or with the federated credential `github-deployments-<environment name>`. The federated credential holds no secret, accepts only a Neologik deployment run that names this environment, and adds no permission |

The onboarding kit includes each script in full. Approvers can read each script before an administrator runs the script.

[QUICK-REFERENCE.md](docs/QUICK-REFERENCE.md) lists each change that the onboarding script makes and each permission that the onboarding script grants.

## Contents

1. [Terms used in the onboarding kit](#terms-used-in-the-onboarding-kit)
2. [What the onboarding kit contains](#what-the-onboarding-kit-contains)
3. [Onboarding at a glance](#onboarding-at-a-glance)
4. [Before you start](#before-you-start)
5. [Run the onboarding script](#run-the-onboarding-script)
6. [Questions the onboarding script asks](#questions-the-onboarding-script-asks)
7. [After the onboarding script completes](#after-the-onboarding-script-completes)
8. [After Neologik deploys the environment](#after-neologik-deploys-the-environment)
9. [Help](#help)

## Terms used in the onboarding kit

| Term | Meaning |
|---|---|
| Neologik Context Engine | The administration web application of the Neologik Platform. The web application shows the name **Neologik Admin Tool** on screen. Platform operators configure agents and Apps there. The address is `https://<your host name>/nce` |
| Agent | An assistant that a platform operator configures in the Neologik Context Engine. An agent can answer users in a channel such as Microsoft Teams. An agent can also work unattended |
| App | A business application that runs on the Neologik Platform beside the agents |
| Deployment identity | The service principal that Neologik signs in with to deploy Azure resources into your resource group |
| Platform operator | A person who works in the Neologik Context Engine. A platform operator is a member of the group `Neologik NCE Contributors - <short name>` or the group `Neologik NCE Admins - <short name>` |
| Short name | The organisation code, the environment type and the environment index, joined together. An example is `abcprd01`. The short name is part of the name of each object that the onboarding script creates |
| Onboarding script | `Install-NeologikEnvironment.ps1` |
| Grants script | `Grant-NeologikAgentAccess.ps1` |
| Platform Sign-in application | The application registration that signs your users in to the Neologik Context Engine and to Apps |
| Agent identity blueprint | The Microsoft Entra Agent ID object that is the parent of each agent identity and each agent user account. The onboarding script creates the agent identity blueprint |

## What the onboarding kit contains

### Scripts

| Script | When an administrator runs the script | What the script does | Guide |
|---|---|---|---|
| `Install-NeologikEnvironment.ps1` | Once, before Neologik deploys the environment | Creates the Azure resources, the security groups, the deployment identity, the Platform Sign-in application and the agent identity blueprint | This document, [TECHNICAL-REFERENCE.md](docs/TECHNICAL-REFERENCE.md) and [QUICK-REFERENCE.md](docs/QUICK-REFERENCE.md) |
| `Grant-NeologikAgentAccess.ps1` | When an agent or an App is to work unattended in Microsoft 365, and again whenever either grants file changes | Applies the grants that the agent grants file and the mailbox grants file list: the grants to agent users and the mailbox grants of the email channels | [GRANT-AGENT-ACCESS-SCRIPT-GUIDE.md](docs/GRANT-AGENT-ACCESS-SCRIPT-GUIDE.md) |
| `Export-NeologikCertificate.ps1` | When you prepare your TLS certificate | Builds a PFX file on the workstation. Contacts no service | [PFX-CERT-GUIDE.md](docs/PFX-CERT-GUIDE.md) |
| `Register-NeologikResourceProviders.ps1` | When the onboarding script reports that an Azure resource provider is still registering | Confirms the Azure resource provider registrations on the subscription | [TECHNICAL-REFERENCE.md](docs/TECHNICAL-REFERENCE.md#resource-provider-registration) |
| `Upgrade-TeamsAppInstallations.ps1` | After Neologik sends you a new version of the Teams app package | Upgrades the Neologik Teams app that each user has installed, to the latest version in your Teams app catalogue | [TEAMS-APP-UPGRADE-GUIDE.md](docs/TEAMS-APP-UPGRADE-GUIDE.md) |
| `Remove-NeologikDirectoryObjects.ps1` | Only when you remove the Neologik Platform, at step 7 of the uninstall guide | Deletes the directory objects of one environment from your Microsoft Entra tenant, after you confirm the list | [UNINSTALL-GUIDE.md](docs/UNINSTALL-GUIDE.md) |

### Documents

This document is in the root of the onboarding kit. Every other document is in the folder `docs`.

| Document | Purpose |
|---|---|
| [README.md](README.md) | This document. The place to start |
| [PRE-ONBOARDING-INFO-GATHERING.md](docs/PRE-ONBOARDING-INFO-GATHERING.md) | The values to collect before an administrator runs the onboarding script |
| [NETWORK-GUIDE.md](docs/NETWORK-GUIDE.md) | The address ranges and the DNS names of an environment, for the person who plans your networks |
| [QUICK-REFERENCE.md](docs/QUICK-REFERENCE.md) | For Approvers. Each change that the onboarding script makes and each permission that the onboarding script grants |
| [secure-overview.md](docs/secure-overview.md) | For Approvers. A summary on one page of the access that the onboarding script grants |
| [CREATE-SP-GUIDE.md](docs/CREATE-SP-GUIDE.md) | How to create the deployment service principal yourself. The onboarding script otherwise creates the deployment service principal |
| [PFX-CERT-GUIDE.md](docs/PFX-CERT-GUIDE.md) | How to prepare your own TLS certificate, when you do not choose a Neologik-managed certificate |
| [FINISHING-STEPS-GUIDE.md](docs/FINISHING-STEPS-GUIDE.md) | The steps that follow the deployment by Neologik |
| [AGENT-ACCOUNT-ACCESS-GUIDE.md](docs/AGENT-ACCOUNT-ACCESS-GUIDE.md) | How to give an agent account access to a mailbox, a site or a team |
| [GRANT-AGENT-ACCESS-SCRIPT-GUIDE.md](docs/GRANT-AGENT-ACCESS-SCRIPT-GUIDE.md) | What the grants script, `Grant-NeologikAgentAccess.ps1`, applies |
| [TEAMS-APP-UPGRADE-GUIDE.md](docs/TEAMS-APP-UPGRADE-GUIDE.md) | How to upgrade the Teams app for your users |
| [UNINSTALL-GUIDE.md](docs/UNINSTALL-GUIDE.md) | How to remove the Neologik Platform completely from your Azure subscription and your Microsoft Entra tenant |
| [TECHNICAL-REFERENCE.md](docs/TECHNICAL-REFERENCE.md) | The onboarding script in detail: parameters, names, steps and output files |
| [ANALYTICS-REPORTING-GUIDE.md](docs/ANALYTICS-REPORTING-GUIDE.md) | For Approvers. What the environment reports to Neologik, what the environment never reports, how long Neologik keeps the statistics and how to withdraw |

### Supporting files

| File | Purpose |
|---|---|
| `NeologikGuestUsers.txt` | The list of Neologik support accounts. The onboarding script asks whether to invite these accounts as guests. Read the list before you run the onboarding script |
| `resource-providers.txt` | The list of Azure resource providers and preview features that the Neologik Platform requires |
| `inputs-example.json` | A template for the answer file, `inputs.json`. Without an answer file, the onboarding script asks each question |
| `cert\` | The folder where `Export-NeologikCertificate.ps1` looks for your certificate files |
| `docs\` | The folder that holds every document except this one |
| `LICENSE` | The licence for the onboarding kit |

## Onboarding at a glance

| Stage | Who acts | What happens |
|---|---|---|
| 1. Onboarding | A Global Administrator who is also Owner of the subscription | The Global Administrator runs the onboarding script. The onboarding script creates the Azure resources, the security groups, the deployment identity, the Platform Sign-in application and the agent identity blueprint |
| 2. Certificate | An administrator | The administrator chooses how the environment gets its TLS certificate. With a Neologik-managed certificate, Neologik obtains a certificate for the host name from the certificate authority ZeroSSL, installs the certificate once the DNS record points at the environment, and renews the certificate every 60 days; the administrator imports nothing. With your own certificate, the administrator imports the certificate into the Key Vault. Neologik then copies the certificate, private key included, into Neologik's central Key Vault. Each deployment of the ingress reads the certificate from Neologik's central Key Vault. |
| 3. Deployment | Neologik | Neologik deploys each service of the Neologik Platform to your resource group |
| 4. DNS | The person who manages your DNS | The person creates the DNS record for the host name of the environment |
| 5. Consent | A Global Administrator | Neologik sends a consent link for each sign-in application. The Global Administrator opens each consent link and gives administrator consent |
| 6. Teams and user access | A Teams Administrator, and a Groups Administrator or Global Administrator | The Teams Administrator publishes the Teams app. The Groups Administrator or Global Administrator adds users to the security groups |

## Before you start

| Requirement | Detail |
|---|---|
| Azure role | **Owner** on the subscription. The Contributor role is not enough, because the onboarding script assigns Azure roles |
| Microsoft Entra role | **Global Administrator**. The onboarding script creates the application registrations and the agent identity blueprint. The onboarding script grants Microsoft Graph application permissions and assigns security groups to the Platform Sign-in application. The onboarding script also adds the SQL managed identity to the Directory Readers role |
| Workstation | Windows 10 or Windows 11, with an internet connection |
| PowerShell | PowerShell 7.4 or later. Windows PowerShell 5.1 cannot run the onboarding script |
| Host name | The fully qualified host name of the environment. An example is `neologik.contoso.com`. Agree the host name with Neologik and with the person who manages your DNS |
| Values | The values listed in [PRE-ONBOARDING-INFO-GATHERING.md](docs/PRE-ONBOARDING-INFO-GATHERING.md) |
| Cost data for the return on investment report | If you buy Azure through a Cloud Solution Provider partner on the Azure Plan, ask the partner to set your cost visibility policy to **Yes** in the partner tenant: **Cost Management + Billing**, the billing scope, **Customers**, your organisation, **Settings**, **Policies**, **Azure Usage**. Without it the platform's return on investment report shows running costs as unavailable. A directly billed subscription needs nothing. A Microsoft Azure Sponsorship subscription cannot report running costs |

The onboarding script checks both roles before the onboarding script creates anything. The onboarding script stops if either role is missing.

## Run the onboarding script

### 1. Extract the onboarding kit

Extract the onboarding kit to a folder, for example `C:\Neologik`. A zip downloaded from GitHub extracts to a folder inside the folder you choose, named `neo-client-onboarding-main`. The scripts are in that inner folder.

Keep the files together. The onboarding script reads `NeologikGuestUsers.txt` and `resource-providers.txt` from the folder of the onboarding script. The onboarding script also reads `inputs.json` from that folder, if you create the answer file.

### 2. Open PowerShell 7

1. Open the **Start** menu and type `PowerShell`.
2. Select **PowerShell 7**. Do not select Windows PowerShell.
3. Confirm the version:

```powershell
$PSVersionTable.PSVersion
```

The version must be 7.4 or later. If PowerShell 7 is not installed, install PowerShell 7 from https://aka.ms/powershell.

### 3. Go to the folder of the onboarding kit

Go to the folder that holds the scripts:

```powershell
cd C:\Neologik
```

For a zip downloaded from GitHub, the folder is `C:\Neologik\neo-client-onboarding-main`.

### 4. Allow the scripts to run in this session

```powershell
Get-ChildItem .\*.ps1 | Unblock-File
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

The first command removes the mark that Windows puts on a downloaded file. Without it, PowerShell refuses the scripts with the words `not digitally signed`. The second command lifts the execution policy for the current PowerShell window only. Windows does not keep the setting after you close the window.

If PowerShell still refuses a script with the words `not digitally signed`, the execution policy is set by Group Policy, which the command above cannot change. Run `Get-ExecutionPolicy -List`: a value other than `Undefined` on the `MachinePolicy` or `UserPolicy` row confirms it. An administrator of that policy allows `RemoteSigned` for the workstation, or you run the scripts from a workstation without the policy.

### 5. Start the onboarding script

```powershell
.\Install-NeologikEnvironment.ps1
```

### 6. Follow the prompts

The onboarding script works through these stages, from the first stage to the last stage.

| Stage | What you do |
|---|---|
| Terms | Read the Neologik Terms of Use and the Privacy Policy. Then type `I ACCEPT` |
| Modules | The onboarding script asks to install the Azure modules and the Microsoft Graph modules when the modules are missing. Press Enter to accept. The onboarding script installs the modules for your user account only |
| Sign-in | When you are already signed in to Azure, the onboarding script shows the account. Press Enter to continue with that account, or type `Y` to sign in with another account. When you are not signed in, a browser window opens for the sign-in |
| Subscription and permissions | The onboarding script shows the subscription and checks the two roles |
| Configuration | Answer the questions described in the next section |
| Summary | Read the configuration summary and confirm |
| Creation | The onboarding script creates the resources. Leave the window open until the completion summary appears |

### 7. If the run is interrupted

The onboarding script records progress in the file `NeologikCheckpoint.json`, in the folder of the onboarding script.

1. Run the onboarding script again.
2. The onboarding script asks "Resume from this checkpoint?". Press Enter to resume.

The onboarding script restores your answers. Each step uses the resources that the earlier run created. The file `NeologikCheckpoint.json` contains no secret. The onboarding script deletes the file when the run completes.

## Questions the onboarding script asks

Each question shows a default value or an example. Press Enter to accept a default value, or type a value. The onboarding script repeats a question until the value is valid.

| Question on screen | What to enter | Default |
|---|---|---|
| Organization Code | Your organisation code of three characters. Use letters and digits only. The onboarding script converts the code to lower case | None |
| Environment Type | `dev` for development or `prd` for production | `dev` |
| Organization Name, the full name of the organisation | The full name of your organisation | None |
| Host name of the environment, fully qualified | The fully qualified host name of the environment, for example `neologik.contoso.com`. The onboarding script removes an `https://` prefix and a path | None |
| Azure Region | The Azure region for the resources, for example `uksouth`. Type `list` to see each region that the subscription can use | `uksouth` |
| Environment Index Number | A number from 01 to 99. The number separates two environments of the same type | `01` |
| Resource Group Name, Key Vault Name, Deployment Storage Account Name, Script Runner Managed Identity Name, SQL Managed Identity Name, Directory Managed Identity Name, System Task Managed Identity Name | Press Enter to accept each standard name. Type another name when you prefer a name of your choice | The standard name, shown on screen |
| Apply Azure resource tags to created resources? | `true` to tag each resource that the onboarding script creates. The tags are Vendor, ApplicationName, ManagedBy, Environment, Solution and DeploymentDate. Choose `true` when an Azure Policy in your subscription refuses a resource without tags | `true` |
| Custom resource tags | Further tags, written as `key=value` pairs separated by commas. Press Enter for no custom tags. A custom tag replaces a standard tag of the same name | None |
| Invite Neologik guest users into this tenant? | `Y` to invite the accounts in `NeologikGuestUsers.txt`. The onboarding script shows the accounts first. You can then add further addresses, one on each line. `N` when you create accounts for Neologik support staff in your own tenant | `Y` |
| Add existing accounts to the security groups? | The onboarding script asks this question only after the answer `N` to the invitation question. `Y` to add accounts that you have already created. The onboarding script takes the accounts from `NeologikGuestUsers.txt` or from the prompt, and sends no invitation. The onboarding script reports an address that matches no account and continues | `N` |
| Use a service principal you have already created for deployment? | `Y` when you created the deployment service principal yourself, as described in [CREATE-SP-GUIDE.md](docs/CREATE-SP-GUIDE.md). Have the object ID of the enterprise application ready | `N` |

The onboarding script asks no question about agents. A platform operator creates agents and channels in the Neologik Context Engine after Neologik deploys the environment.

### Accounts added to the security groups

Each account that you invite or add through these questions joins all four Neologik security groups. One of the four is the group `Neologik Admin User Group - <short name>`, which holds Azure administration roles on the resource group.

List only the accounts that need Neologik administration and support access. Add your own users after the deployment, as described in [FINISHING-STEPS-GUIDE.md](docs/FINISHING-STEPS-GUIDE.md).

### Answer file

You can prepare every answer before the run.

1. Copy `inputs-example.json` to `inputs.json` in the folder of the onboarding kit.
2. Enter your values in `inputs.json`.

Each value then appears as the default value of the matching question. [TECHNICAL-REFERENCE.md](docs/TECHNICAL-REFERENCE.md#answer-file) describes each field.

## After the onboarding script completes

The completion summary lists each object that the onboarding script created. The onboarding script writes two files to the folder of the onboarding kit.

| File | Content |
|---|---|
| `Neologik_<org><index>_Configuration_<timestamp>.json` | The configuration that Neologik needs for the deployment: names, ids and the addresses of the accounts invited or added. The configuration file contains no secret |
| `NeologikOnboarding_<timestamp>.log` | The log of the run |

### 1. Confirm that Neologik has the configuration file

The onboarding script uploads the configuration file to the deployment storage account. Neologik reads the configuration file from the deployment storage account.

When the completion summary reports that the upload failed, upload the configuration file in the Azure portal: open the deployment storage account, then **Containers**, then `json`, then **Upload**. Keep the log file as the record of the run.

### 2. Confirm the resource provider registrations

The onboarding script reports each resource provider registration that is not yet complete. The report appears before the completion summary. When the onboarding script reports a registration, run this command before the deployment:

```powershell
.\Register-NeologikResourceProviders.ps1
```

### 3. Provide your TLS certificate

The environment needs a TLS certificate for the host name. Choose one of two ways, and tell Neologik which one you chose.

**A Neologik-managed certificate.** Neologik obtains a certificate for the host name from the certificate authority ZeroSSL, installs the certificate once the DNS record for the host name points at the environment, and renews the certificate every 60 days. You import nothing and renew nothing. One check applies: when your DNS zone publishes CAA records, which name the certificate authorities allowed to issue certificates for your domain, add a record that allows `sectigo.com`, the issuing authority behind ZeroSSL, for example `0 issue "sectigo.com"`. A zone without CAA records needs no change.

**Your own certificate.** Import the certificate into the Key Vault of the environment:

1. Prepare a `.pfx` file for the host name of the environment, as described in [PFX-CERT-GUIDE.md](docs/PFX-CERT-GUIDE.md).
2. In the Azure portal, open the Key Vault that the completion summary names.
3. Select **Certificates**, then **Generate/Import**.
4. Select **Import**.
5. Name the certificate `keyvault-neo-ingress`.
6. Select the `.pfx` file and enter the password of the `.pfx` file.
7. Select **Create**.

The Key Vault uses the password for the import only and does not store the password. Do not send the `.pfx` file or the password to Neologik.

Neologik then copies the certificate, private key included, from the Key Vault of the environment into Neologik's central Key Vault. Each deployment of the ingress reads the certificate from Neologik's central Key Vault. Azure role-based access control protects Neologik's central Key Vault.

When you cannot produce a `.pfx` file, upload three files to the container `certificate` of the deployment storage account:

- the private key
- the server certificate
- the certificate authority bundle

The completion summary names the deployment storage account. Tell Neologik after the upload. A Neologik engineer then builds a `.pfx` file from the three files. The engineer imports the `.pfx` file into Neologik's central Key Vault. The engineer records the password of the `.pfx` file in a Key Vault of Neologik.

[The TLS certificate](docs/TECHNICAL-REFERENCE.md#the-tls-certificate) in the technical reference describes the upload.

### 4. Tell Neologik that the environment is ready

Neologik deploys the Neologik Platform to your resource group. Neologik tells you when the deployment is complete.

## After Neologik deploys the environment

[FINISHING-STEPS-GUIDE.md](docs/FINISHING-STEPS-GUIDE.md) describes the five steps that remain.

1. Create the DNS record for the host name.
2. Give administrator consent for the sign-in applications.
3. Publish the Teams app.
4. Give your users access.
5. Give agent accounts access to your resources. This step applies only where an agent works unattended.

## Help

Email support@neologik.ai and attach the log file of the run. The log file contains no secret.
