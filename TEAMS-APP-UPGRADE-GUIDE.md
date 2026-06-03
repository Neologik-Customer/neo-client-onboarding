# Updating Neologik Teams Apps

This guide covers the two steps required to roll out an updated Neologik Teams bot to all your users:

1. **Upload the new app package** to your tenant's Teams app catalog (a `.zip` provided by Neologik).
2. **Silently propagate the new version** to every user via the PowerShell script in this repository.

Both steps are run by your tenant administrator against your own tenant.

---

## Step 1 — Upload the New App Package to Your Tenant

Neologik will send you an updated app package (a `.zip` file containing the new manifest, icons, and configuration). To make it available in your tenant:

1. Sign in to the **Teams Admin Center** at <https://admin.teams.microsoft.com> with a **Teams Administrator** or **Global Administrator** account.
2. In the left navigation, expand **Teams apps** and click **Manage apps**.
3. Search for the existing Neologik app by name (for example, *Neologik — Your Bot Name*). Click the app to open its details.
4. Click **Actions** → **Update**.
5. Upload the new `.zip` file supplied by Neologik. Confirm the upload.
6. Teams Admin Center shows the new version with status **Published**.

If Neologik supplied multiple `.zip` files (one per bot), repeat the upload for each bot.

> **At this point the new version is in your catalog but users still have the old one installed.** Their Teams clients will show an "Update" banner over the next 24-72 hours as they sync the catalog. Step 2 below pushes the update to every user immediately.

---

## Step 2 — Silently Roll Out to All Users

The [`Upgrade-TeamsAppInstallations.ps1`](Upgrade-TeamsAppInstallations.ps1) script in this repository **silently force-upgrades every user's installed Neologik bot to the latest catalog version** in a single run — no Update prompt shown to anyone.

A single run handles **every** Neologik bot you uploaded in Step 1. You don't need to run it per bot.

Run time scales with the number of bots and users in your tenant — anywhere from a few minutes to around an hour for large tenants. Leave the PowerShell window open until you see the final summary.

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

If `Major` is `5`, install PowerShell 7 from the Microsoft Store:

1. Press the **Windows key**, type **Microsoft Store**, and open it.
2. In the search box, type **PowerShell 7** and press Enter.
3. Click the result titled **PowerShell** — with version **7.x.x** published by **Microsoft Corporation**. (The icon is a dark-blue square with a white prompt.)
4. Click **Install**.
5. Wait for the install to finish.

#### After PowerShell 7 is installed

Close all PowerShell windows and open a new **PowerShell 7** window (search Start menu for `pwsh`).

> You do **not** need to run PowerShell as Administrator. The script installs its dependencies in your user profile and writes the log and CSV report next to itself.

Verify the version:

```powershell
$PSVersionTable.PSVersion
```

`Major` should now show `7`.

### 2. Get the script

If you have already cloned this repository for onboarding, the script is already on your machine — `Upgrade-TeamsAppInstallations.ps1` next to `Install-NeologikEnvironment.ps1`.

> **Choose a folder you have read/write access to.** The script writes its log and CSV report next to itself. Good choices: `C:\Neologik`, your `Documents` folder, your `Desktop`. Avoid `C:\Program Files`, network shares, or any read-only location.

Otherwise, choose one of:

**Option A — Download the repository as a ZIP (no Git required):**

1. Open the repository in your browser: <https://github.com/Neologik-Customer/neo-client-onboarding>.
2. Click the green **Code** button, then **Download ZIP**.
3. Extract the ZIP into a writable folder of your choice (for example `C:\Neologik` or your Documents folder).
4. Open PowerShell 7 and change into that folder:

   ```powershell
   cd C:\Neologik\neo-client-onboarding-main
   ```

**Option B — Clone with Git:**

```powershell
cd C:\Neologik
git clone https://github.com/Neologik-Customer/neo-client-onboarding.git
cd neo-client-onboarding
```

---

## Running the Script

In your PowerShell 7 window, first allow scripts to run for this session only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Then run the script:

```powershell
.\Upgrade-TeamsAppInstallations.ps1 -UseDeviceAuthentication
```

> The first time you run it in your tenant, a consent screen appears in your browser — **TICK "Consent on behalf of your organization"** before clicking Accept. This grants the script's Microsoft Graph permissions tenant-wide. Future runs sign in without showing the consent screen.

The script will:

1. Sign you in silently in your default browser.
2. List every Neologik bot in your catalog with its latest version.
3. Prompt: *"Type YES to proceed"* — type `YES` and press Enter.
4. For each bot: enumerate users, identify stale installations, upgrade silently.
5. Write a CSV report and log file next to the script.

Run time scales with bot and user count — a few minutes for small tenants, up to around an hour for large tenants. Leave the window open until the final summary appears.

### Useful options

| Flag | Purpose |
|------|---------|
| `-WhatIf` | Dry run — report what would change without making any changes. |
| `-AppId <guid>` | Upgrade a specific bot by manifest GUID. Accepts multiple. |
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
  - Neologik - Bot A    v1.1.214  (...)
  - Neologik - Bot B    v1.1.146  (...)
  - Neologik - Bot C    v1.1.199  (...)

About to upgrade installations for the apps listed above.
Type YES to proceed, or anything else to abort: YES

--- Neologik - Bot A (v1.1.214) ---
  Found 47 installation(s)
...

Report written: TeamsAppUpgrade_<timestamp>.csv

Summary:

Name                                  Users Updated
----                                  -------------
Neologik - Bot A, Upgraded                       42
Neologik - Bot A, AlreadyLatest                   5
Neologik - Bot B, Upgraded                       18
...
```

The CSV next to the script lists every user × app with `FromVersion`, `ToVersion`, and `Status` so you can audit who was upgraded.

---

## Output Files

Each run drops two timestamped files in the same folder as the script:

| File | Contents |
|------|----------|
| `TeamsAppUpgrade_<timestamp>.log` | Full run log: every step, every API call result, any warnings. Useful for troubleshooting. |
| `TeamsAppUpgrade_<timestamp>.csv` | One row per (user × app): `Upn`, `App`, `ExternalId`, `FromVersion`, `ToVersion`, `Status`. Use this as the audit record of who was upgraded. |

**Keep these files** — they're the audit trail for the rollout. Neither contains secrets, only user UPNs, display names, and app version numbers.

If anything goes wrong, attach both files when contacting Neologik support — they're the fastest way to diagnose.

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
