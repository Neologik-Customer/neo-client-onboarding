# Upgrading the Neologik Teams App

## Overview

Neologik sends you a new Teams app package when a new version of the Neologik Teams app is ready. Two steps then move every user to the new version.

| Step | Who acts | What happens |
|---|---|---|
| [1. Upload the new Teams app package](#step-1-upload-the-new-teams-app-package) | A Teams Administrator | The Teams app catalogue of your organisation holds the new version |
| [2. Upgrade every user](#step-2-upgrade-every-user) | A Global Administrator, with the script `Upgrade-TeamsAppInstallations.ps1` | The script upgrades the Teams app that each user has installed. Microsoft Teams asks the user nothing |

Step 2 saves time. Without step 2, Microsoft Teams upgrades each user only when the Teams client of the user next reads the Teams app catalogue. The wait can last several days.

## Contents

1. [What you need](#what-you-need)
2. [Step 1: Upload the new Teams app package](#step-1-upload-the-new-teams-app-package)
3. [Step 2: Upgrade every user](#step-2-upgrade-every-user)
4. [Options](#options)
5. [Output files](#output-files)
6. [Permissions](#permissions)
7. [Troubleshooting](#troubleshooting)
8. [Help](#help)

## What you need

| Requirement | Detail |
|---|---|
| Teams app package | The `.zip` file that Neologik sent. Neologik sends one `.zip` file for each agent with a Teams channel |
| Teams Administrator | For step 1 |
| Global Administrator | For step 2. The first run asks the Global Administrator to consent for the organisation |
| Workstation | Windows, macOS or Linux, with PowerShell 7.4 or later. Windows PowerShell 5.1 cannot run the script. The script needs no administrator rights on the workstation |
| Network | The workstation must reach Microsoft Graph and the PowerShell Gallery |

To check the PowerShell version:

```powershell
$PSVersionTable.PSVersion
```

When the major version is 5, install PowerShell 7 from the Microsoft Store or from https://aka.ms/powershell. Then open **PowerShell 7** from the Start menu.

## Step 1: Upload the new Teams app package

1. Sign in to the Teams admin centre, https://admin.teams.microsoft.com, as a Teams Administrator.
2. Open **Teams apps**, then **Manage apps**.
3. Find the Neologik Teams app by name and open the Teams app.
4. Select **Actions**, then **Update**.
5. Select the new `.zip` file and confirm.

The Teams admin centre shows the new version as published. Repeat these steps for each `.zip` file that Neologik sent.

## Step 2: Upgrade every user

One run of the script upgrades every Neologik Teams app that you uploaded in step 1.

1. Save the onboarding kit in a folder that you can write to, for example `C:\Neologik`. The script writes the log and the report to the folder of the script.
2. Open PowerShell 7 and go to the folder:

   ```powershell
   cd C:\Neologik
   ```

3. Allow the script to run in this session:

   ```powershell
   Unblock-File .\Upgrade-TeamsAppInstallations.ps1
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   ```

4. Run the script:

   ```powershell
   .\Upgrade-TeamsAppInstallations.ps1
   ```

5. A browser window opens. Sign in as a Global Administrator.
6. At the first run in your tenant, Microsoft shows a consent page. Select **Consent on behalf of your organization**, then **Accept**.
7. The script lists each Neologik Teams app in your Teams app catalogue, with the latest version of each. Check the list. Then type `YES` and press Enter.
8. Leave the window open until the summary appears.

The length of a run depends on the number of users in your tenant. A run takes a few minutes for a small tenant and about an hour for a large tenant.

## Options

| Option | Purpose |
|---|---|
| `-WhatIf` | Shows on screen what a run would upgrade. The script changes nothing and writes no log and no report |
| `-UseDeviceAuthentication` | Signs in with a device code. Use this option when a browser sign-in is not possible |
| `-TenantId <tenant id>` | Signs in to the tenant that you name |
| `-AppId <id>` | Upgrades only the Teams app with the manifest id that you give. You can give more than one manifest id |
| `-Force` | Starts the upgrade without the question that asks you to type `YES` |

## Output files

A run writes up to two files to the folder of the script.

| File | Content | When the script writes the file |
|---|---|---|
| `TeamsAppUpgrade_<timestamp>.log` | The log of the run. The log names the account, the tenant, each Teams app that the script found, each user that the script skipped and each failure | Every run, except a run with `-WhatIf` |
| `TeamsAppUpgrade_<timestamp>.csv` | The report, with one row for each user and Teams app. The columns are `App`, `ExternalId`, `Upn`, `DisplayName`, `FromVersion`, `ToVersion` and `Status` | Every run that finds at least one installed Teams app, except a run with `-WhatIf` |

The column `Status` holds one of three values.

| Value | Meaning |
|---|---|
| `Upgraded` | The script upgraded the Teams app of the user |
| `AlreadyLatest` | The user already had the latest version |
| `Failed` | Microsoft Teams refused the upgrade. The value includes the reason |

The report is your record of the users that the script upgraded.

Neither file contains a secret or the content of a message. Both files contain the sign-in names of users. Treat both files as an export of user data. Delete both files when you have no further need of the record.

## Permissions

The sign-in requests three delegated Microsoft Graph permissions. A delegated permission works as the Global Administrator who signed in.

| Permission | What the script uses the permission for |
|---|---|
| `AppCatalog.Read.All` | To read the Teams apps in your Teams app catalogue |
| `TeamsAppInstallation.ReadWriteAndConsentForUser` | To read and upgrade the Teams app that each user has installed |
| `User.Read.All` | To list the users of the tenant |

The script stores no credential.

The script reads three things:

- your Teams app catalogue
- the users of the tenant
- the Teams app that each user has installed

The script makes one change only. The script upgrades the Teams app that a user has installed.

## Troubleshooting

| Symptom | Cause | Action |
|---|---|---|
| The script reports the PowerShell version and stops | You opened Windows PowerShell, or the PowerShell version is older than 7.4 | Open PowerShell 7 |
| The script reports that consent is needed | Nobody has consented for the organisation | Run the script again as a Global Administrator. Select **Consent on behalf of your organization** at the sign-in |
| The script finds no Neologik Teams app | Nobody has uploaded the Teams app package, or the Teams app package is in another tenant | Complete step 1. Check the tenant that the sign-in shows |
| The report shows `Failed` for a user | Microsoft Teams refused the upgrade for that user | Read the reason in the column `Status`. Run the script again |
| The run ended early | An error occurred, or somebody closed the window | Run the script again. The report shows `AlreadyLatest` for each user that the earlier run upgraded |

## Help

Email support@neologik.ai and attach the log and the report of the run.
