# Version History

This document lists the versions of the Neologik onboarding kit and what each version changed for you. From version 5.0.0 the version of the kit follows the version of the Neologik Platform it is issued for.

The onboarding script records the kit version on your resource group, as the tag `NeologikOnboardingKit`. The platform reads the tag before an upgrade.

## Contents

1. [Scripts in this version](#scripts-in-this-version)
2. [Version 5.0.3](#version-503)
3. [Version 5.0.2](#version-502)
4. [Version 5.0.1](#version-501)
5. [Version 5.0.0](#version-500)
6. [Earlier versions](#earlier-versions)

## Scripts in this version

Each script version is shown as the script reports it.

| Script | Script version | Purpose |
|---|---|---|
| `Install-NeologikEnvironment.ps1` | v5.0.1 | Prepares the Azure subscription and the Microsoft Entra tenant for one Neologik Platform environment |
| `Update-NeologikEnvironmentAccess.ps1` | Kit version v5.0.3 | Brings the access of the deployment identity of an existing environment to the model of version 5, and applies the grants for agents and Apps that work unattended |
| `Export-NeologikCertificate.ps1` | 1.0 | Builds the PFX file for the environment's TLS certificate on the workstation |
| `Register-NeologikResourceProviders.ps1` | 1.0 | Confirms the Azure resource provider registrations on the subscription |
| `Upgrade-TeamsAppInstallations.ps1` | v0.2.0 | Upgrades every user's installed Neologik Teams app to the latest version in the catalogue |

## Version 5.0.3

**Date**: 2026-09-28

| Item | Change |
|---|---|
| `Install-NeologikEnvironment.ps1` | Version v5.0.1. The script runner managed identity holds Reader, Key Vault Secrets Officer and Azure Bot Service Contributor Role on the resource group, and no role on the subscription. It held Contributor on the subscription. No identity the script creates holds a role that gives control of resources outside the resource group. Records kit version `v5.0.3` on the resource group |
| `Update-NeologikEnvironmentAccess.ps1` | Records kit version `v5.0.3` on the resource group |
| Scripts | The comments, the help and the messages of every script revised, and the symbols in the messages replaced by plain text markers such as `[OK]`. The help of every script is shown by `Get-Help`. No script changes what it does, other than the change of role above |
| Documents | Every guide and reference revised. `FINISHING-STEPS-GUIDE.md` covers the DNS record for both deployment types and the administrator consent. `QUICK-REFERENCE.md` is the security reference of the onboarding script, and `secure-overview.md` its one-page summary |

## Version 5.0.2

**Date**: 2026-09-27

| Item | Change |
|---|---|
| `Install-NeologikEnvironment.ps1` | Records the kit version on the resource group as the tag `NeologikOnboardingKit`. Your other tags are kept, and an existing resource group receives the tag too |
| `Update-NeologikEnvironmentAccess.ps1` | Records the same tag as the last step of the permission reduction |

## Version 5.0.1

**Date**: 2026-09-25

| Item | Change |
|---|---|
| `NeologikGuestUsers.txt` | The list of Neologik support accounts updated |

## Version 5.0.0

**Date**: 2026-09-25

The first release of the kit for the Neologik Platform version 5.0. The table lists what changed from version 1.10.1.

| Item | Change |
|---|---|
| Access of the deployment identity | Held on the resource group. On the subscription the identity holds Reader and Cost Management Contributor only. It holds no Microsoft Entra directory role and is a member of no group. In Microsoft Graph it holds `Application.ReadWrite.OwnedBy` and `AgentIdentityBlueprint.AddRemoveCreds.All` |
| Agent identity blueprint | The onboarding script creates the agent identity blueprint of the environment, under which the platform creates agent identities and agent user accounts |
| Platform Sign-in application | The onboarding script creates the application that signs your users in to the Neologik Context Engine and to Apps, and assigns the NCE Contributors and NCE Admins groups to it |
| Security groups | Four groups: the User Group, the NCE Contributors group, the NCE Admins group and the Admin User Group. The Admin User Group holds its roles on the resource group and none on the subscription |
| Resource providers | One list, `resource-providers.txt`, registered in full on every run. `Register-NeologikResourceProviders.ps1` confirms the registrations on their own |
| Answer file | The values of a run can be supplied in `inputs.json`, and every resource name can be set to a name of your own |
| Accounts for Neologik support | Guest invitation is optional. You can create the accounts in your own tenant instead |
| Deployment service principal | You can supply a service principal of your own, as described in `CREATE-SP-GUIDE.md` |
| Subscription | `-SubscriptionName` selects the subscription after sign-in |
| Unattended run | `-NonInteractive` and `-AcceptTerms` run the script without prompts |
| `Update-NeologikEnvironmentAccess.ps1` | New. Described in `ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md` |
| `Export-NeologikCertificate.ps1` | New. Described in `PFX-CERT-GUIDE.md` |
| `Upgrade-TeamsAppInstallations.ps1` | New. Described in `TEAMS-APP-UPGRADE-GUIDE.md` |
| Agents | The onboarding script no longer asks for the agents of the environment. Agents are created in the Neologik Context Engine after deployment |

## Earlier versions

| Version | Date | Change |
|---|---|---|
| 1.10.1 | 2026-06-29 | The check of the virtual machine quota corrected |
| 1.10.0 | 2026-06-25 | The deployment identity and the Admin User Group no longer hold Contributor on the subscription |
| 1.9.1 | 2026-06-18 | Documents brought into line with the script |
| 1.9.0 | 2026-01-15 | The Azure region is validated against the regions available to the subscription |
| 1.8.0 | 2026-01-12 | The Neologik support accounts are read from `NeologikGuestUsers.txt`. The host name of the environment is collected |
| 1.7.0 to 1.7.5 | 2025-11-17 | Corrections to resource provider registration, error messages and the handling of newly created directory objects |
| 1.6.5 to 1.6.9 | 2025-11-17 | Corrections to guest invitation and logging |
| 1.4.0 to 1.4.2 | 2025-11-17 | Acceptance of the Terms of Use and the Privacy Policy before the script runs |
| 1.0.0 | 2025-11-15 | The first release |
