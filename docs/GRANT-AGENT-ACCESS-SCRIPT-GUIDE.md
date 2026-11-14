# Grant-NeologikAgentAccess.ps1: What the Script Does

## Overview

`Grant-NeologikAgentAccess.ps1` is the grants script. A Global Administrator runs the grants script when an agent or an App of the Neologik Platform is to work unattended in Microsoft 365. The grants script applies two files.

| File | What the file lists | What the grants script applies |
|---|---|---|
| The agent grants file, `agent-grants-<environment>.json` | Each agent and each App that works unattended, with the permissions that the agent or the App needs | One grant to the agent user account of each agent and each App, the Microsoft Graph application permissions of workload identities, and the check of the SharePoint consent |
| The mailbox grants file, `mailbox-grants-<environment>.json` | Each email channel, with the mailbox that the email channel reads | The three Exchange Online roles that let the identity of the email channel read and send from that one mailbox |

Neologik sends the two files. A platform operator can also download the agent grants file. In the Neologik Admin Tool, open **Admin**, then select **Download** under **Grants file**. An email channel that shows **Awaiting mailbox grant** also shows **Download grant script** on the **Channels** tab. An Exchange Administrator can run that script instead of the mailbox grants file. The command of the grants script names one file or both.

The grants script reads the current state before each change. The grants script changes only what differs from the file. A Global Administrator can run the grants script again at any time, and runs the grants script again whenever either file changes. With `-Verify` the grants script reports each change that a run would make, and writes nothing.

The grants script is the same for every customer and every environment. The two files are the part that belongs to your environment.

## Contents

1. [What you need](#what-you-need)
2. [How to run the grants script](#how-to-run-the-grants-script)
3. [Step 1: Grants to agent users](#step-1-grants-to-agent-users)
4. [Step 2: Mailbox grants](#step-2-mailbox-grants)
5. [What the grants script never does](#what-the-grants-script-never-does)
6. [What the sign-in asks you to approve](#what-the-sign-in-asks-you-to-approve)
7. [What you receive](#what-you-receive)
8. [Questions](#questions)
9. [Help](#help)

## What you need

| Requirement | Reason |
|---|---|
| PowerShell 7.4 or later | The grants script stops on an earlier version |
| A workstation with a desktop and a browser | The grants script opens the sign-in page in the browser of the workstation. You complete the sign-in in the browser |
| A Global Administrator account in your tenant | Only a Global Administrator can create a grant to an agent user account and grant a Microsoft Graph application permission |
| Exchange Administrator or Global Administrator, for a run with a mailbox grants file | The mailbox grants are made in Exchange Online |
| The agent grants file, the mailbox grants file or both | The files list the grants to apply. Each file names your tenant |

The grants script installs the PowerShell modules that the run needs, for your user account, when the modules are missing.

| Modules | Run |
|---|---|
| Two Microsoft Graph modules, `Microsoft.Graph.Authentication` and `Microsoft.Graph.Applications` | Every run |
| The Exchange Online module, `ExchangeOnlineManagement` | A run with a mailbox grants file |

Before the grants script loads a module that the grants script installed, the grants script checks the Authenticode signature of each file of the module. The grants script uses the rules of the onboarding script, which [TECHNICAL-REFERENCE.md](TECHNICAL-REFERENCE.md#signature-checks) describes. When a file fails the check, the grants script removes each module that the grants script installed for the step, and loads none of those modules. The grants script then prints what to do.

Before the grants script changes anything, the grants script confirms three facts.

1. The workstation can reach each Microsoft address that the grants script uses.
2. The PowerShell modules load. A module that the grants script installs passes the signature check first.
3. The signed-in account holds an active Global Administrator role.

## How to run the grants script

1. Place the onboarding kit in a folder on your workstation, and the two files beside the grants script.
2. Open PowerShell 7 in that folder.
3. Run the command.

```powershell
.\Grant-NeologikAgentAccess.ps1 -AgentGrantsFile .\agent-grants-<environment>.json -MailboxGrantsFile .\mailbox-grants-<environment>.json
```

   Leave out the parameter of a file that you do not have.

4. The grants script opens the sign-in page in your browser. Sign in as a Global Administrator. The grants script waits for up to 5 minutes and reports every 30 seconds that the grants script still waits.
5. In a run with a mailbox grants file, the grants script signs in to Exchange Online in the same way. The browser uses the same account and does not usually ask again. Sign in as an Exchange Administrator or as a Global Administrator.
6. Read the summary table on screen and the list `FILES TO SEND TO NEOLOGIK` under it. Send the files to Neologik.

The grants script takes your tenant and the short name of your environment from the agent grants file. The command needs no other value. Three further parameters cover the exceptions.

| Parameter | When to add the parameter |
|---|---|
| `-TenantId <tenant id>` | The command names a mailbox grants file alone, and the mailbox grants file does not name the tenant |
| `-SolutionShortName <short name>` | The command names a mailbox grants file alone, or the agent grants file does not name the environment, and your tenant holds more than one Neologik environment |
| `-SharePointAppClientId <client id>` | Neologik asks for the parameter. The grants script then finds the SharePoint application of the environment by the client id |

When the browser sign-in does not complete, the grants script prints a web address and a code. Open the web address in a browser on any device, enter the code and sign in. The grants script waits for up to 15 minutes. Some organisations block this sign-in with a Conditional Access policy. The grants script then says so and tries the next method.

To see what a run would change, add `-Verify` to the end of the command. The sign-ins are the same. The grants script reports each pending change as `WOULD` and writes nothing.

## Step 1: Grants to agent users

An agent or an App that works unattended has an agent identity and an agent user account in your directory. For each agent and each App in the agent grants file, the grants script creates one delegated permission grant. The grant lets the agent identity act as the agent user account of that agent identity. The grant holds exactly the permissions that the file lists. The grant names one agent user account. The grant is not a grant for the whole tenant. When the grant exists with other permissions, the grants script changes the grant to the permissions that the file lists.

The file can also list Microsoft Graph application permissions for named workload identities. The grants script grants those permissions. The grants script grants only a permission with no limit to one mailbox or one site. The summary reports a permission with such a limit as `SKIPPED`, and an Exchange Administrator or a SharePoint Administrator grants the permission.

The file records whether the environment uses SharePoint ingestion. When the environment uses SharePoint ingestion, the grants script checks the SharePoint application of the environment. That application must hold the Microsoft Graph application permission `Sites.Selected`. A consent belongs to one application. Another SharePoint application of Neologik in your tenant may hold a SharePoint permission. In that case, the grants script grants `Sites.Selected` to the SharePoint application of the environment. Otherwise the grants script prints the consent address when the consent is absent. A Global Administrator opens the consent address and gives the consent. A site administrator then grants access to each SharePoint site separately.

When the file marks an entry as not ready, the summary reads `SKIPPED` for the entry. The Neologik Admin Tool exports a new file when the entry is ready.

## Step 2: Mailbox grants

For each email channel in the mailbox grants file, the grants script grants three Exchange Online roles to the identity of the email channel.

| Role | Limit |
|---|---|
| `Application Mail.Read` | The one mailbox that the file names |
| `Application Mail.ReadWrite` | The one mailbox that the file names |
| `Application Mail.Send` | The one mailbox that the file names |

The grant needs two objects in Exchange Online: a service principal for the identity, and a management scope that holds that one mailbox. The grants script creates each object when the object is absent. The identity receives no access to any other mailbox.

With `-RemoveLegacyGrantAppIds` the grants script also removes the Exchange Online role assignments of each identity that the command names. An identity that the file records as in use keeps the role assignments.

When your Exchange Online organisation has never been customised, the grants script enables organisation customisation. Exchange Online requires the setting before a role assignment. Exchange Online needs the setting once.

Exchange Online can take up to two hours to apply a role. The summary then reads `PENDING`. Run the grants script again later to confirm the mailbox grant.

## What the grants script never does

- The grants script never reads, moves or deletes your data. The grants script reads directory objects and Exchange Online role assignments.
- The grants script never creates a user, a group, an application registration or a secret.
- The grants script never changes an Azure resource or an Azure role. The grants script does not sign in to Azure.
- The grants script never gives administrator consent. The grants script prints the consent address. You decide.
- The grants script never removes a grant that a file lists. The grants script never removes the role assignments of an identity that a file records as in use.
- The grants script never sends anything to Neologik. You send the files of the run.
- The grants script never stores your sign-in.
- The grants script never loads a module that the grants script installed before the signature check of the module passes.

## What the sign-in asks you to approve

The grants script signs in to Microsoft Graph with your account. At the first use, Microsoft lists the permissions that the grants script requests. Each permission is a delegated permission. A delegated permission works as you, for the run only. The sign-in grants nothing to an application.

| Permission | Requested in | What the grants script uses the permission for |
|---|---|---|
| `Directory.Read.All` | Every run | To read the service principals, the agent identities and the directory roles of your account |
| `User.Read` | Every run | To identify your account |
| `AppRoleAssignment.ReadWrite.All` | Every run | To grant the Microsoft Graph application permissions of workload identities and `Sites.Selected` |
| `DelegatedPermissionGrant.ReadWrite.All` | A run with an agent grants file | To create the grants to agent user accounts |

The sign-in to Exchange Online uses the same account and shows no list of permissions.

## What you receive

The grants script prints a summary table. The grants script writes two files in the folder of the grants script.

| File | Name | Content |
|---|---|---|
| The log file | `NeologikAgentAccess_<date and time>.log` | Every message of the run, from the first line. Each failed request to Microsoft Graph, with its status and the request id by which Microsoft can find the request. The summary table |
| The summary file | `Neologik_AgentAccess_<date and time>.json` | The version of the onboarding kit, the tenant, the short name of the environment, the signed-in account, the time of the run, the two files, every item of the summary, and the path of the log file |

The grants script writes the summary file on every exit, a run that stopped before its steps included. The grants script writes to the current folder when the folder of the grants script is not writable. The grants script writes to the temporary folder when the current folder is not writable.

The run ends with the list `FILES TO SEND TO NEOLOGIK`, which names each file with its full path. No file holds a secret. Send the two files to Neologik as the record of the run.

| Result | Meaning |
|---|---|
| `Present`, `Already granted`, `Not present`, `Not needed`, `Kept` | Nothing to change |
| `Granted`, `Updated`, `Removed` | Changed in this run |
| `WOULD` | A change that a run without `-Verify` would make |
| `MISSING`, `SKIPPED`, `PENDING`, `UNKNOWN`, `FAILED`, `NOT FOUND` | Needs attention. The row gives the reason |

| Exit code | Meaning |
|---|---|
| 0 | Every grant is in the expected state |
| 1 | An item needs attention. With `-Verify`, a change is pending |

## Questions

**Why does my account need a Global Administrator role?**

Only a Global Administrator can create a grant to an agent user account and grant a Microsoft Graph application permission. The grants script uses your sign-in for the run. The sign-in grants nothing to your account and stores nothing.

**What happens when a grant is already in place?**

The grants script reports the grant and moves to the next item. A second run with the same files changes nothing.

**What happens when the agent grants file names an agent identity that my tenant does not hold?**

The summary reads `MISSING` for the entry. Tell Neologik. The Neologik Platform creates the agent identity, and you run the grants script again.

**Why does the grants script print a consent address?**

The SharePoint application of the environment needs the permission `Sites.Selected`. No other application of Neologik in your tenant holds a SharePoint permission. A Global Administrator gives the consent at the address. The grants script never gives consent.

## Help

Email support@neologik.ai with the files that the list at the end of the run names. Give the name of your organisation and the host name of the environment.
