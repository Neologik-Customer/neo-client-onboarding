# Update-NeologikEnvironmentAccess.ps1 - What It Does and Why

## Summary

`Update-NeologikEnvironmentAccess.ps1` is the script your Global Administrator runs once before a Neologik v5 migration. It tightens the access the Neologik deployment identity holds in your tenant and subscription, so that identity keeps only what it needs to deploy and operate your Neologik environment, and nothing more.

The script works in one direction: it narrows access. It never widens Neologik's reach, never grants anything to a person, and never touches anything that is not part of your Neologik environment. It checks before every change, changes nothing that is already in order, and reports everything it did or would do. You can run it in report-only mode first and see exactly what it will change before it changes anything.

Neologik sends you the complete command to run. Every value is filled in by Neologik from the records it holds for your environment. You type nothing but your sign-in.

## Contents

- [The security benefit in one paragraph](#the-security-benefit-in-one-paragraph)
- [What you need](#what-you-need)
- [How to run it](#how-to-run-it)
- [What the script checks and changes](#what-the-script-checks-and-changes)
- [What the script never does](#what-the-script-never-does)
- [What the sign-in asks you to approve](#what-the-sign-in-asks-you-to-approve)
- [What you get back](#what-you-get-back)
- [Questions administrators ask](#questions-administrators-ask)

## The security benefit in one paragraph

When your environment was first set up, the Neologik deployment identity was given broad rights so that it could create everything: Contributor and User Access Administrator on the whole subscription, the Application Administrator role in your directory, and several tenant-wide Microsoft Graph permissions. The v5 platform no longer needs any of that. After this script has run, the deployment identity holds a fixed set of roles on your Neologik resource group only, two narrow read-only roles on the subscription, two narrow Microsoft Graph permissions, and ownership of the handful of application registrations that belong to your Neologik environment. Everything broader is removed. This is the least-privilege model the v5 platform is built on.

## What you need

| Requirement | Why |
|---|---|
| Windows PowerShell 7.4 or later | the script is a PowerShell 7 script |
| A browser on any device | the script signs you in with a device code; it prints a web address and a short code, and you complete the sign-in in the browser |
| A Global Administrator account in your tenant | only a Global Administrator can grant and remove Microsoft Graph application permissions and directory roles |
| Owner or User Access Administrator on the subscription | the same account changes the deployment identity's Azure role assignments |
| The command line Neologik sent you | it names your tenant, subscription, resource group and the Neologik application registrations, so the script acts only on those |
| The latest copy of the script from this repository | download `Update-NeologikEnvironmentAccess.ps1` from the repository page, as you did for the onboarding script |

The script needs nothing else on your machine. It installs the Microsoft Graph PowerShell modules for your user account if they are missing, and it checks that it can reach Microsoft before it starts.

## How to run it

1. Download the latest `Update-NeologikEnvironmentAccess.ps1` from this repository into a folder on your computer.
2. Open PowerShell 7 in that folder.
3. Paste the command line Neologik sent you and press Enter.
4. When the script prints a web address and a code, open the address in a browser, enter the code, and sign in with your Global Administrator account. The script waits up to 15 minutes.
5. The script signs in a second time, to Azure, for the role assignment step. Enter the second code the same way.
6. Read the summary the script prints, and send Neologik the summary file it writes beside itself.

To see what the script would change without changing anything, add `-Verify` to the end of the command line. A report-only run signs in the same way and prints every pending change as `WOULD ...`. Neologik can send you the command in report-only form on request.

The script is safe to run more than once. A second run finds everything in order and changes nothing.

## What the script checks and changes

The script works through seven steps. Each step reads the current state first, changes only what differs from the expected state, and records the result.

| Step | What it does | What it changes |
|---|---|---|
| 1. Agent identity blueprint | Confirms the blueprint that the platform uses to create agent identities exists, is owned by the deployment identity, holds one narrow Microsoft Graph permission, and carries the three credentials the deployment pipeline uses to act through it | Creates the blueprint only if it is missing; adds the owner, permission or credentials only if they are missing |
| 2. Deployment identity permissions | Confirms the deployment identity holds exactly two Microsoft Graph application permissions: `Application.ReadWrite.OwnedBy` (manage only the applications it owns) and `AgentIdentityBlueprint.AddRemoveCreds.All` (manage the blueprint's credentials) | Grants those two if missing; removes the seven retired tenant-wide permissions the identity was given at onboarding |
| 3. Sign-in application | Confirms your Neologik user group is assigned to the "Neologik Platform Sign-in" application, so that only members of that group can open the Neologik Context Engine, and that the application has tenant-wide admin consent. Where you ingest documents from SharePoint, confirms the SharePoint application's `Sites.Selected` consent | Adds the group assignment if missing; prints a consent link for you to open if consent is missing |
| 4. Application registration ownership | Makes the deployment identity an owner of exactly the application registrations Neologik named on the command line: the sign-in application, the SharePoint application, and each Neologik bot. The deployment identity can then manage those registrations, and only those, under its narrow permission. Any other application in your directory whose name starts with "Neologik" is listed in the summary for your review and is not changed | Adds the owner if missing; sets the registration's uniqueName so the deployment pipeline can find it; lists any password credential the pipeline did not create |
| 5. Permission reduction | First confirms the deployment identity holds the narrow role set it needs: seven roles on your Neologik resource group only, plus Reader and Cost Management Contributor on the subscription. Only then removes the broad grants: Contributor and User Access Administrator on the subscription, the Application Administrator directory role, and membership of the Neologik Admin User Group. Removes any other role, directory role or group membership the identity holds outside that declared set | If any narrow role could not be applied, nothing is removed. Deployments never lose access part way through |
| 6. Kit version | Once every step above is in place, records the version of this kit on your Neologik resource group as the tag `NeologikOnboardingKit`. The Neologik platform reads it before an upgrade and refuses an environment whose kit is older than the release needs, naming this script | Sets the tag when it is missing or older, merged with your other tags; nothing else |
| 7. Summary | Prints a table of every item and its result, and writes the same table to a file beside the script | Nothing |

The seven resource-group roles are Contributor, Key Vault Certificates Officer, Key Vault Secrets Officer, Storage Blob Data Contributor, Azure Kubernetes Service RBAC Cluster Admin, Monitoring Contributor, and Role Based Access Control Administrator. Each is scoped to your Neologik resource group and to nothing else in the subscription.

## What the script never does

- It never grants a Neologik person any access. Every grant is to the deployment identity, and every grant narrows what that identity held before.
- It never reads, moves or deletes your data. It reads directory objects and role assignments only.
- It never changes an application registration Neologik did not name on the command line. Applications with a Neologik-style name that are not on the list are reported for your review and left alone.
- It never creates a user, a group or a secret.
- It never sends anything to Neologik. You choose what to send back.
- It never keeps your sign-in. The sign-in is a delegated session under your account for the duration of the run, and it is not stored.
- It never removes a broad role before the narrow replacement is in place.

## What the sign-in asks you to approve

The script signs in to Microsoft Graph under your own account. On first use, Microsoft shows a consent screen listing the permissions the script requests. All of them are delegated: they let the script act as you for this session only, and they grant nothing to any application.

| Permission | Why the script needs it |
|---|---|
| `Application.ReadWrite.All` | read and adopt the agent identity blueprint and the Neologik application registrations, and add the pipeline's credentials to the blueprint |
| `AppRoleAssignment.ReadWrite.All` | grant and remove the deployment identity's Microsoft Graph permissions, and assign your user group to the sign-in application |
| `Directory.Read.All` | read the service principals, groups and directory roles the checks compare against (read-only) |
| `User.Read` | identify your own account (read-only) |
| `DelegatedPermissionGrant.Read.All` | read the sign-in application's admin consent (read-only) |
| `AgentIdentityBlueprint.Create`, `AgentIdentityBlueprint.AddRemoveCreds.All`, `AgentIdentityBlueprintPrincipal.Create` | create the agent identity blueprint, its principal and its credentials only when they do not exist yet |
| `RoleManagement.ReadWrite.Directory` | remove the deployment identity's Application Administrator directory role |
| `GroupMember.ReadWrite.All` | remove the deployment identity from the Neologik Admin User Group |

The Azure sign-in uses the same account and needs no additional consent. A report-only run signs in the same way and shows the same screen.

## What you get back

The script prints a summary table and writes it to `Neologik_EnvironmentAccess_PreWindow_<date and time>.json` beside itself. Each row names an item and its result: `Already in place`, `Added`, `Removed`, `Present`, `Review ...` for something you may want to look at, or `WOULD ...` in a report-only run. The script exits with code 0 when everything is in the expected state, and with code 1 when any item needs attention. Send the file to Neologik: it is the evidence that your side of the migration is complete.

## Questions administrators ask

**Does this give Neologik more access?**
No. Every change narrows what the deployment identity already held. The identity ends the run with fewer rights than it started with.

**Why does my own account need such broad permissions to run it?**
Removing a directory role and granting Microsoft Graph application permissions are actions only a Global Administrator may perform. The script borrows your rights for the duration of the run to reduce the deployment identity's rights. Nothing is granted to your account, and nothing is stored.

**Can I see what it will do before it does it?**
Yes. Run the command with `-Verify` at the end. The script signs in, checks everything, prints every pending change as `WOULD ...`, and writes nothing.

**What if something is already in order?**
The script reports `Already in place` and moves on. A second run on a compliant environment changes nothing.

**What if a step fails?**
The script does not stop at the first problem. It records the failure with the reason, continues with the other steps, and exits with code 1. The permission reduction never removes anything unless every narrow role is in place first. Send Neologik the summary file and Neologik will tell you what, if anything, to do.

**Why does it list applications it did not change?**
The deployment identity may only manage the applications it owns, so the script adopts exactly the ones Neologik named. Listing the others with a Neologik-style name lets you and Neologik confirm that nothing was missed, without the script ever touching an application on its own initiative.

**Is there a second run later?**
Only if your organisation later has a Neologik agent or App working unattended on your behalf in Microsoft 365. Neologik will send you the files for that run when the time comes. Most customers never need it.
