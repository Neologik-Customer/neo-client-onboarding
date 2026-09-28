# Updating the Neologik Teams App

## Overview

When Neologik supplies an updated Teams app package, two steps bring every user to the new version:

| Step | Who | What happens |
|---|---|---|
| [1. Upload the new package](#step-1-upload-the-new-package) | Your Teams administrator | The new version is published in your Teams app catalogue |
| [2. Upgrade every user](#step-2-upgrade-every-user) | Your Global Administrator, with `Upgrade-TeamsAppInstallations.ps1` | Every user's installed copy is upgraded at once, with no prompt to the user |

Without step 2, Teams offers the update to each user as their client synchronises with the catalogue, which can take several days.

## Contents

1. [What you need](#what-you-need)
2. [Step 1: Upload the new package](#step-1-upload-the-new-package)
3. [Step 2: Upgrade every user](#step-2-upgrade-every-user)
4. [Options](#options)
5. [Output files](#output-files)
6. [Permissions](#permissions)
7. [Troubleshooting](#troubleshooting)
8. [Help](#help)

## What you need

| Requirement | Detail |
|---|---|
| The package | The `.zip` file, or files, supplied by Neologik |
| Teams Administrator | For step 1 |
| Global Administrator | For step 2. The first run asks for consent on behalf of your organisation |
| Workstation | Windows, macOS or Linux with PowerShell 7.4 or later. Windows PowerShell 5.1 cannot run the script. No administrator rights are needed on the workstation |
| Network | Access to Microsoft Graph and the PowerShell Gallery |

To check the PowerShell version:

```powershell
$PSVersionTable.PSVersion
```

If the major version is 5, install PowerShell 7 from the Microsoft Store or from https://aka.ms/powershell, then open **PowerShell 7** from the Start menu.

## Step 1: Upload the new package

1. Sign in to the Teams admin centre, https://admin.teams.microsoft.com, as a Teams Administrator.
2. Open **Teams apps**, then **Manage apps**.
3. Find the Neologik app by its name and open it.
4. Select **Actions**, then **Update**.
5. Select the new `.zip` file and confirm.

The Teams admin centre shows the new version as published. Repeat for each package if Neologik supplied more than one.

## Step 2: Upgrade every user

One run upgrades every Neologik app you uploaded in step 1.

1. Place the kit in a folder you can write to, for example `C:\Neologik`. The script writes its log and its report beside itself.
2. Open PowerShell 7 and go to the folder:

   ```powershell
   cd C:\Neologik
   ```

3. Allow the script to run in this session:

   ```powershell
   Unblock-File .\Upgrade-TeamsAppInstallations.ps1
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
   ```

4. Run the script:

   ```powershell
   .\Upgrade-TeamsAppInstallations.ps1
   ```

5. Sign in as a Global Administrator when the browser opens. At the first run in your tenant, a consent screen appears: select **Consent on behalf of your organization**, then **Accept**.
6. The script lists each Neologik app it found in your catalogue, with its latest version. Check the list, then type `YES` and press Enter.
7. Leave the window open until the summary appears.

The time a run takes depends on the number of users in your tenant: from a few minutes to about an hour for a large tenant.

## Options

| Option | Purpose |
|---|---|
| `-WhatIf` | A dry run. Shows on screen what would be upgraded and changes nothing. No log and no report is written |
| `-UseDeviceAuthentication` | Signs in with a device code, where a browser sign-in is not possible |
| `-TenantId <tenant id>` | Signs in to the tenant named |
| `-AppId <id>` | Upgrades the app with the manifest id given, and no other. More than one id may be given |
| `-Force` | Omits the confirmation |

## Output files

A run writes up to two files beside the script. A dry run writes neither, and the report is written only when at least one installation was found.

| File | Content |
|---|---|
| `TeamsAppUpgrade_<timestamp>.log` | The log of the run: the account and tenant, the apps found, the users passed over and any failure |
| `TeamsAppUpgrade_<timestamp>.csv` | The report: one row for each installation, that is, for each user and app, with the columns `App`, `ExternalId`, `Upn`, `DisplayName`, `FromVersion`, `ToVersion` and `Status` |

`Status` is `Upgraded`, `AlreadyLatest` or `Failed` with the reason.

The report is your record of who was upgraded. Neither file contains a secret or the content of any message. Both contain sign-in names: keep them as you would any export of user data, and delete them when you no longer need the record.

## Permissions

The sign-in requests three delegated Microsoft Graph permissions. The script acts as the signed-in administrator.

| Permission | Used for |
|---|---|
| `AppCatalog.Read.All` | Reading the apps published in your catalogue |
| `TeamsAppInstallation.ReadWriteAndConsentForUser` | Reading and upgrading the Teams apps installed for users |
| `User.Read.All` | Listing the users of the tenant |

The script stores no credential. It reads your Teams app catalogue, the users of the tenant and each user's installed copy of the app, and its only write is the upgrade of an installed copy.

## Troubleshooting

| Symptom | Cause | Action |
|---|---|---|
| The script reports the PowerShell version | Windows PowerShell was opened, or PowerShell is older than 7.4 | Open PowerShell 7 |
| The script reports that consent is needed | Consent on behalf of your organisation was not given | Run the script again as a Global Administrator and select **Consent on behalf of your organization** at sign-in |
| No Neologik app is found | The package has not been uploaded, or the app was uploaded to another tenant | Complete step 1, and check the tenant shown at sign-in |
| The report shows `Failed` for a user | Teams refused the upgrade for that user | Read the reason in the `Status` column, and run the script again |
| The run ended early | An error or a closed window | Run the script again. Users upgraded already are reported as `AlreadyLatest` |

## Help

Email support@neologik.ai and attach the log and the report of the run.
