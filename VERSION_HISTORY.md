# Version History

## Overview

This document lists the versions of the Neologik onboarding kit. For each version, this document states what changed for you.

| Subject | Detail |
|---|---|
| Version of the onboarding kit | The version of the onboarding kit follows the version of the Neologik Platform |
| Record on your resource group | The onboarding script and the environment access script record the version of the onboarding kit on your resource group, in the tag `NeologikOnboardingKit`. The Neologik Platform reads the tag before an upgrade |
| Versions 5.0.4 and 5.0.5 | The onboarding kit has no version 5.0.4 and no version 5.0.5 |

## Contents

1. [Scripts in this version](#scripts-in-this-version)
2. [Version 5.0.7](#version-507)
3. [Version 5.0.6](#version-506)
4. [Version 5.0.3](#version-503)
5. [Version 5.0.2](#version-502)
6. [Version 5.0.1](#version-501)
7. [Version 5.0.0](#version-500)
8. [Earlier versions](#earlier-versions)

## Scripts in this version

The table shows the version that each script reports.

| Script | Version of the script | Purpose |
|---|---|---|
| `Install-NeologikEnvironment.ps1` | v5.0.5 | Prepares the Azure subscription and the Microsoft Entra tenant for one Neologik Platform environment |
| `Update-NeologikEnvironmentAccess.ps1` | Onboarding kit version v5.0.7 | Reduces the access of the deployment identity of an existing environment to the access that version 5 of the Neologik Platform needs. Applies the grants for agents and Apps that work unattended |
| `Export-NeologikCertificate.ps1` | 1.1 | Builds the PFX file for the TLS certificate of the environment, on the workstation |
| `Register-NeologikResourceProviders.ps1` | 1.0 | Confirms the Azure resource provider registrations on the subscription |
| `Upgrade-TeamsAppInstallations.ps1` | v0.2.1 | Upgrades the Neologik Teams app that each user has installed to the latest version in the Teams app catalogue |

## Version NEXT

This version is on the line of Neologik Platform v5.1 and is not yet released.

| Item | Change |
|---|---|
| `ANALYTICS-REPORTING-GUIDE.md` | New document. What the environment reports to Neologik, what the environment never reports, the retention period and how to withdraw from reporting |
| `Install-NeologikEnvironment.ps1` | Version v5.0.4. After a failure, the onboarding script prints the closing messages: the path of the log, the permission that is missing, and how to resume. Before this version, the first error message stopped the onboarding script before the closing messages. A run that stops because a permission is missing ends with exit code 2 |
| `Install-NeologikEnvironment.ps1` | The onboarding script downloads the PowerShell installer of the latest release. Before this version, the address named one fixed version |
| `Install-NeologikEnvironment.ps1` | The configuration file records both roles of the deployment identity on the subscription: Reader and Cost Management Contributor |
| `Install-NeologikEnvironment.ps1` | A run resumed from the first checkpoint asks the questions, because the first checkpoint holds no configuration. A resumed run honours `-SkipGuestInvitation` from the command line |
| `QUICK-REFERENCE.md` | The document describes the resume from the first checkpoint and exit code 2 |
| `Install-NeologikEnvironment.ps1` | Version v5.0.5. The onboarding script creates the application registration of the deployment identity for a single tenant. The deployment signs in to your tenant only |
| Documents | The documents state why the Platform Sign-in application accepts accounts of more than one tenant: Neologik support staff can sign in with an account of the Neologik tenant, when you allow that tenant |
| `Update-NeologikEnvironmentAccess.ps1` | The environment access script signs in to Microsoft Graph, to Azure and to Exchange Online in the browser of the workstation first. A device code is the second method. Before this version, a device code was the first method. An organisation that blocks the device code with a Conditional Access policy could not complete the sign-in |
| `Update-NeologikEnvironmentAccess.ps1` | When a Conditional Access policy refuses a sign-in, the environment access script says so and tries the next method at once |
| `ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md` | The document describes the browser sign-in and the device code as the second method |

## Version 5.0.7

**Date**: 2026-09-28

| Item | Change |
|---|---|
| `Export-NeologikCertificate.ps1` | Version 1.1. The script deletes `private-clean.key`, the private key without encryption, after success and after a failure. Before this version, the file stayed on disk after a failure |
| `Install-NeologikEnvironment.ps1` | Version v5.0.3. The onboarding script records the version `v5.0.7` on the resource group |
| `Update-NeologikEnvironmentAccess.ps1` | The environment access script records the version `v5.0.7` on the resource group |

## Version 5.0.6

**Date**: 2026-09-28

| Item | Change |
|---|---|
| Documents | Every document is rewritten in plain English |
| Scripts | The comments, the help text and the messages of every script are rewritten in plain English. No script behaves differently |
| `Install-NeologikEnvironment.ps1` | Version v5.0.2. The onboarding script writes the value `NeologikPlatform` to the tag `ApplicationName` of each resource that the onboarding script creates. The deployment by Neologik writes the same value. The question about the host name now reads "Host name of the environment, fully qualified". The onboarding script records the version `v5.0.6` on the resource group |
| `Update-NeologikEnvironmentAccess.ps1` | The environment access script names each item of the summary in full, for example `Agent identity blueprint owner` instead of `Blueprint owner`. Each result reads `FAILED: <reason>` instead of `FAILED - <reason>`. The environment access script records the version `v5.0.6` on the resource group |
| `Upgrade-TeamsAppInstallations.ps1` | Version v0.2.1 |
| `TECHNICAL-REFERENCE.md` | The document lists the value of each standard tag |
| The zip of the onboarding kit | The zip holds the scripts, the documents and the supporting files only. The zip omits the repository files and the test folder |

## Version 5.0.3

**Date**: 2026-09-28

| Item | Change |
|---|---|
| `Install-NeologikEnvironment.ps1` | Version v5.0.1. The script runner managed identity holds three roles on the resource group: Reader, Key Vault Secrets Officer and Azure Bot Service Contributor Role. The script runner managed identity holds no role on the subscription. Before this version, the script runner managed identity held Contributor on the subscription. No identity that the onboarding script creates holds a role that gives control of a resource outside the resource group. The onboarding script records the version `v5.0.3` on the resource group |
| `Update-NeologikEnvironmentAccess.ps1` | The environment access script records the version `v5.0.3` on the resource group |
| Scripts | The comments, the help text and the messages of every script are revised. Plain text markers such as `[OK]` replace the symbols in the messages. `Get-Help` shows the help of every script. No script behaves differently, apart from the change of role above |
| Documents | Every guide and reference is revised. `FINISHING-STEPS-GUIDE.md` covers the DNS record for both deployment types and the administrator consent. `QUICK-REFERENCE.md` is the security reference of the onboarding script. `secure-overview.md` is the summary of `QUICK-REFERENCE.md` on one page |

## Version 5.0.2

**Date**: 2026-09-27

| Item | Change |
|---|---|
| `Install-NeologikEnvironment.ps1` | The onboarding script records the version of the onboarding kit on the resource group, in the tag `NeologikOnboardingKit`. The onboarding script keeps your other tags. An existing resource group receives the tag too |
| `Update-NeologikEnvironmentAccess.ps1` | The environment access script records the same tag as the last step of the permission reduction |

## Version 5.0.1

**Date**: 2026-09-25

| Item | Change |
|---|---|
| `NeologikGuestUsers.txt` | The list of Neologik support accounts is updated |

## Version 5.0.0

**Date**: 2026-09-25

Version 5.0.0 is the first release of the onboarding kit for version 5.0 of the Neologik Platform. The table lists what changed from version 1.10.1.

| Item | Change |
|---|---|
| Access of the deployment identity | The deployment identity holds the roles on the resource group. On the subscription the deployment identity holds Reader and Cost Management Contributor only. The deployment identity holds no Microsoft Entra directory role and is a member of no group. In Microsoft Graph the deployment identity holds `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` |
| Agent identity blueprint | The onboarding script creates the agent identity blueprint of the environment. The Neologik Platform creates the agent identities and the agent user accounts under the agent identity blueprint |
| Platform Sign-in application | The onboarding script creates the application that signs your users in to the Neologik Context Engine and to Apps. The onboarding script assigns the groups `Neologik NCE Contributors - <short name>` and `Neologik NCE Admins - <short name>` to the application |
| Security groups | Four groups: `Neologik User Group - <short name>`, `Neologik NCE Contributors - <short name>`, `Neologik NCE Admins - <short name>` and `Neologik Admin User Group - <short name>`. The Admin User Group holds the roles on the resource group and no role on the subscription |
| Resource providers | One list, `resource-providers.txt`. The onboarding script registers the whole list on every run. `Register-NeologikResourceProviders.ps1` confirms the registrations |
| Answer file | The answer file `inputs.json` can hold each value of a run. Each resource name can be a name of your choice |
| Accounts for Neologik support | Guest invitation is optional. You can create the accounts in your tenant instead |
| Deployment service principal | You can create the deployment service principal yourself, as described in `CREATE-SP-GUIDE.md` |
| Subscription | The parameter `-SubscriptionName` selects the subscription after the sign-in |
| Unattended run | The parameters `-NonInteractive` and `-AcceptTerms` run the onboarding script without questions |
| `Update-NeologikEnvironmentAccess.ps1` | New script. `ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md` describes the script |
| `Export-NeologikCertificate.ps1` | New script. `PFX-CERT-GUIDE.md` describes the script |
| `Upgrade-TeamsAppInstallations.ps1` | New script. `TEAMS-APP-UPGRADE-GUIDE.md` describes the script |
| Agents | The onboarding script asks no question about agents. A platform operator creates agents in the Neologik Context Engine after the deployment |

## Earlier versions

| Version | Date | Change |
|---|---|---|
| 1.10.1 | 2026-06-29 | The check of the virtual machine quota is corrected |
| 1.10.0 | 2026-06-25 | The deployment identity and the Admin User Group hold no Contributor role on the subscription |
| 1.9.1 | 2026-06-18 | The documents match the onboarding script |
| 1.9.0 | 2026-01-15 | The onboarding script checks the Azure region against the regions that the subscription can use |
| 1.8.0 | 2026-01-12 | The onboarding script reads the Neologik support accounts from `NeologikGuestUsers.txt`. The onboarding script asks for the host name of the environment |
| 1.7.0 to 1.7.5 | 2025-11-17 | Corrections to the resource provider registration, to the error messages and to the handling of new directory objects |
| 1.6.5 to 1.6.9 | 2025-11-17 | Corrections to the guest invitation and to the log |
| 1.4.0 to 1.4.2 | 2025-11-17 | The onboarding script asks for the acceptance of the Terms of Use and the Privacy Policy before the run |
| 1.0.0 | 2025-11-15 | The first release |
