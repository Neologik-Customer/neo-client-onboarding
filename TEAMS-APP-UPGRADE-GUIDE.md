# Teams App Bulk Upgrade Guide

## Overview

When Neologik publishes a new version of a Teams bot to your tenant's app catalog, each user normally has to click an **Update** banner inside Teams to accept the new version. For tenants with many users, the prompts trickle out over hours or days and users frequently ignore them.

The [`Upgrade-TeamsAppInstallations.ps1`](Upgrade-TeamsAppInstallations.ps1) script in this repository **silently force-upgrades every user's installed Neologik bot to the latest catalog version** in a single run — no Update prompt shown to anyone.

This guide is written for your tenant administrator to run against your own tenant.

---

## When to Run This

Run after Neologik notifies you of a new bot version, or whenever you want to confirm every user is on the latest version.

A single run handles **every** Neologik bot in your catalog. You don't need to run it per bot.

Typical cadence: once a quarter, or after major bot updates.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Entra role | **Global Administrator** in your tenant (required to grant admin consent on the first run) |
| Windows machine | macOS and Linux also work; this guide is Windows-first |
| PowerShell 7.4+ | Windows ships with PowerShell 5.1 — that will not work |
| Internet access | Microsoft Graph and PowerShell Gallery |

---

## One-Time Setup (per machine)

You only need to do this once on whichever machine you'll run the script from.

### 1. Install PowerShell 7

Check your version:

```powershell
$PSVersionTable.PSVersion
```

If `Major` is `5`, install PowerShell 7 via the Microsoft Store, or:

```powershell
winget install --id Microsoft.PowerShell --source winget
```

Then close all PowerShell windows and open a new **PowerShell 7** window (search Start menu for `pwsh`).

### 2. Get the script

If you have already cloned this repository for onboarding, the script is already on your machine — `Upgrade-TeamsAppInstallations.ps1` next to `Install-NeologikEnvironment.ps1`.

Otherwise, clone the repository:

```powershell
git clone https://github.com/Neologik-Customer/neo-client-onboarding.git
cd neo-client-onboarding
```

---

## First Run — Grant Admin Consent

The very first time you run the script in your tenant, you need to grant **admin consent on behalf of your organisation** for the Microsoft Graph permissions the script uses. This is a one-time action.

Run with the device-code flag — it surfaces the consent screen reliably:

```powershell
pwsh -ExecutionPolicy Bypass -File .\Upgrade-TeamsAppInstallations.ps1 -UseDeviceAuthentication -WhatIf
```

The script will:

1. Display a device code and a URL.
2. You open the URL in any browser, paste the code, and sign in as a Global Administrator.
3. A consent screen lists the required permissions.

> **On the consent screen, TICK the box "Consent on behalf of your organization" before clicking Accept.**
>
> Without that tick, consent applies only to your account and the script will fail for everyone else.

After consent is granted, the script will list the Neologik apps in your catalog and exit (because of `-WhatIf`).

You only need to do this once. Future runs sign in silently using your machine's normal browser auth.

---

## Running the Upgrade

After the one-time setup, run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\Upgrade-TeamsAppInstallations.ps1
```

The script will:

1. Sign you in silently in your default browser.
2. List every Neologik bot in your catalog with its latest version.
3. Prompt: *"Type YES to proceed"* — type `YES` and press Enter.
4. For each bot: enumerate users, identify stale installations, upgrade silently.
5. Write a CSV report and log file next to the script.

A typical tenant takes 2–10 minutes depending on user count.

### Useful options

| Flag | Purpose |
|------|---------|
| `-WhatIf` | Dry run — report what would change without making any changes. |
| `-NamePrefix "..."` | Narrow to specific apps (e.g. `-NamePrefix "Neologik - Sales"`). |
| `-AppId <guid>` | Upgrade a specific bot by manifest GUID. Accepts multiple. |
| `-UseDeviceAuthentication` | Use device-code sign-in instead of browser (corporate locked-down machines). |
| `-Force` | Skip the YES/NO confirmation prompt. |

---

## What Success Looks Like

```
===============================================================
   NEOLOGIK TEAMS APP BULK UPGRADE
===============================================================

PowerShell 7.6.0 OK
Microsoft.Graph modules ready
Signed in as admin@yourtenant.com on tenant aaaa1111-...
Searching org catalog for Neologik apps...
Matched 3 Neologik app(s) in catalog:
  - Neologik - Claire Chalmers  v1.1.214  (...)
  - Booking Assistant           v1.1.146  (...)
  - Contract Agent              v1.1.199  (...)

About to upgrade installations for the apps listed above.
Type YES to proceed, or anything else to abort: YES

--- Neologik - Claire Chalmers (v1.1.214) ---
  Found 47 installation(s)
...

Report written: TeamsAppUpgrade_<timestamp>.csv

Summary:
App                            Status         Count
---                            ------         -----
Neologik - Claire Chalmers     Upgraded         42
Neologik - Claire Chalmers     AlreadyLatest     5
Booking Assistant              Upgraded         18
...
```

The CSV next to the script lists every user × app with `FromVersion`, `ToVersion`, and `Status` so you can audit who was upgraded.

---

## Troubleshooting

### `cannot be loaded because running scripts is disabled on this system`

Re-run with `-ExecutionPolicy Bypass`:

```powershell
pwsh -ExecutionPolicy Bypass -File .\Upgrade-TeamsAppInstallations.ps1
```

### Browser sign-in window is blocked or hangs

Use device-code instead:

```powershell
pwsh -ExecutionPolicy Bypass -File .\Upgrade-TeamsAppInstallations.ps1 -UseDeviceAuthentication
```

### `403 Forbidden reading other users' installed apps`

Admin consent was not fully granted. Re-run with `-UseDeviceAuthentication -WhatIf`, and when the consent screen appears, **tick "Consent on behalf of your organization"** before clicking Accept.

### `No Neologik apps found in org catalog`

You're either signed in to the wrong tenant or Neologik hasn't published any bots to your tenant yet. Check Teams Admin Center → Manage apps and confirm.

### Some specific users show `Failed: 403` in the CSV

Their installation may be subject to a per-user app permission policy in your tenant. Review Teams Admin Center → App permission policies.

---

## Required Permissions (Reference)

The script asks Microsoft Graph for these delegated permissions:

- `AppCatalog.Read.All` — read the apps published in your tenant catalog
- `TeamsAppInstallation.ReadWriteAndConsentForUser` — read and upgrade Teams app installations for any user
- `User.Read.All` — enumerate users in the tenant

All three are admin-consent permissions. Granting them is the purpose of the first-run consent step above.

---

## What the Script Does Under the Hood

For audit and compliance review:

1. **Sign in** — signs the admin in to Microsoft Graph using the standard Microsoft Graph PowerShell SDK.
2. **Discover Neologik apps** — queries the app catalog for LOB (custom-uploaded) apps and filters to those whose manifest contains `Neologik`, `neologik.ai`, or Neologik's MPN id (`6560934`) — these signals are present in every Neologik bot manifest and survive customer-side display-name customisation.
3. **Confirm** — prints the matched apps and waits for the admin to type `YES` before making any changes.
4. **Enumerate users** — for each bot, queries enabled users in the tenant and checks who has the app installed via `GET /users/{id}/teamwork/installedApps`.
5. **Upgrade** — for each stale installation, calls `POST /users/{id}/teamwork/installedApps/{installId}/upgrade` with admin-on-behalf-of-user consent — this is the Microsoft Graph endpoint that performs the silent upgrade with no end-user prompt.
6. **Report** — writes a CSV next to the script (`Upn`, `App`, `FromVersion`, `ToVersion`, `Status`) and a matching log file.
7. **Disconnect** — discards the access token at the end of the run.

The script does not store credentials. The admin's access token lives in memory for the duration of the run and is discarded on exit.

The script never reads, writes, or transmits any data outside of:
- The signed-in admin's tenant (Microsoft Graph in their own tenant)
- Two files next to the script: a `.log` and a `.csv`, both containing only user UPNs, display names, and bot version numbers — no message content, no secrets.
