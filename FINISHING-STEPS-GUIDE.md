# Neologik Post-Deployment Steps

## Overview

After Neologik has deployed the environment to your Azure resource group, you need to complete these final configuration steps to make the application accessible to your users.

⏱️ **Estimated time:** 30-45 minutes

---

## Prerequisites

Before starting these steps, ensure:
- ✅ Neologik has completed the deployment to your resource group
- ✅ You have received from Neologik:
  - Public IP address for your deployment
  - Two URLs for tenant access consent (Bot and Admin Tool)
  - Microsoft Teams app package file (.zip)
- ✅ You have the necessary permissions:
  - DNS management access for your domain
  - Global Administrator or Privileged Role Administrator role in Azure AD (Entra ID)
  - Teams Administrator role in Microsoft 365 Admin Center

---

## Step 1: Create DNS A Record

Configure your domain's DNS to point to the Neologik deployment.

### What You Need
- **Hostname:** The fully qualified domain name (FQDN) you agreed with Neologik (e.g., `app.yourcompany.com`)
- **IP Address:** Provided by Neologik after deployment

### Instructions

1. **Access your DNS provider** (e.g., GoDaddy, Cloudflare, Azure DNS, etc.)

2. **Navigate to DNS management** for your domain

3. **Create a new A record:**
   - **Type:** A
   - **Name/Host:** `app` (or the subdomain you chose)
   - **Value/Points to:** [IP address provided by Neologik]
   - **TTL:** 3600 (or your preferred value)

4. **Save the record**

5. **Verify DNS propagation** (may take 5-60 minutes):
   ```powershell
   # In PowerShell, run:
   nslookup app.yourcompany.com
   ```
   You should see the IP address you configured.

**Example A Record:**
```
Type: A
Name: app
Value: 203.0.113.45
TTL: 3600
```

⚠️ **Note:** DNS changes can take up to 48 hours to fully propagate globally, though typically it's much faster.

---

## Step 2: Grant Tenant Access to Applications

Allow the Bot and Admin Tool applications to access your Azure AD (Entra ID) tenant.

### What You Need
- **Two URLs** provided by Neologik for:
  1. Bot application consent
  2. Admin Tool application consent
- **Required Entra ID Roles** (any one of the following):
  - ✅ **Global Administrator** (recommended)
  - ✅ **Privileged Role Administrator**

> **Note**: Global Administrator has the broadest permissions and is recommended for initial setup.

### Instructions

#### A. Grant Access to Bot Application

1. **Open the Bot consent URL** provided by Neologik in your browser
   - Format: `https://login.microsoftonline.com/common/adminconsent?client_id={bot-id}&redirect_uri=https://{hostName}/nce/consent-complete`
   - `{hostName}` = Your full qualified hostname
   - `{bot-id}` = Bot application ID provided by Neologik

2. **Sign in** with your Global Administrator or Privileged Role Administrator account

3. **Review the requested permissions:**
   - Read user profiles
   - Send messages on behalf of the bot
   - Other bot-specific permissions

4. **Click "Accept"** to grant tenant-wide consent

5. **Confirmation:** the browser lands on the consent confirmation page
   (`https://{hostName}/nce/consent-complete`), which reports success or the
   Microsoft error message

#### B. Grant Access to NCE Admin Tool Application

1. **Open the Admin Tool consent URL** provided by Neologik in your browser
   - Format: `https://login.microsoftonline.com/common/adminconsent?client_id={nce-admin-id}&redirect_uri=https://{hostName}/nce/consent-complete`
   - `{hostName}` = Your full qualified hostname (same as above)
   - `{nce-admin-id}` = NCE Admin Tool application ID provided by Neologik

2. **Sign in** with your Global Administrator or Privileged Role Administrator account

3. **Review the requested permissions:**
   - Manage application settings
   - Read user and group information
   - Other admin tool permissions

4. **Click "Accept"** to grant tenant-wide consent

5. **Confirmation:** the browser lands on the consent confirmation page
   (`https://{hostName}/nce/consent-complete`), which reports success or the
   Microsoft error message

### Verify Consent

To verify the applications have been granted consent:

1. Go to **Azure Portal** (portal.azure.com)
2. Navigate to **Azure Active Directory** > **Enterprise applications**
3. Search for the application names provided by Neologik
4. Check that **Admin consent** shows as "Granted"

---

## Step 3: Upload and Deploy Teams App

Make the Neologik application available to your users in Microsoft Teams.

### What You Need
- **Teams app package file** (.zip) provided by Neologik
- **Teams Administrator** role in Microsoft 365 Admin Center

### Instructions

#### A. Upload the Teams App

1. **Open Microsoft Teams Admin Center**
   - Go to [https://admin.teams.microsoft.com](https://admin.teams.microsoft.com)
   - Sign in with your Teams Administrator account

2. **Navigate to Teams apps:**
   - Click **Teams apps** in the left navigation
   - Click **Manage apps**

3. **Upload the custom app:**
   - Click **Upload** or **Upload new app**
   - Select the Teams app package file (.zip) provided by Neologik
   - Wait for the upload to complete

4. **Review app details:**
   - Verify the app name, description, and permissions
   - Note the app status (should be "Allowed")

#### B. Configure App Availability

1. **Set up app permissions policy:**
   - Go to **Teams apps** > **Permission policies**
   - Either edit the **Global (Org-wide default)** policy or create a new policy
   - Under **Custom apps**, ensure "Allow specific apps and block all others" or "Allow all apps" is selected
   - If using specific apps, add the Neologik app to the allowed list

2. **Assign to Neologik User Group:**
   - If you created a custom permission policy, assign it to users:
     - Go to **Users** > **Manage users**
     - Select users or groups (e.g., Neologik User Group)
     - Click **Edit settings** > **Policies**
     - Assign your Teams app permission policy

#### C. Make App Available to Users

**Option 1: Add to org-wide app catalog (Recommended)**
1. In **Manage apps**, find the Neologik app
2. Click on the app name
3. Under **Available to**, select **Everyone in your organization** or **Specific users/groups**
4. If selecting specific groups, choose the **Neologik User Group** (created during setup)
5. Click **Save**

**Option 2: Pre-install for users (Optional)**
1. Go to **Teams apps** > **Setup policies**
2. Edit or create a policy
3. Under **Installed apps**, click **Add apps**
4. Search for and select the Neologik app
5. Click **Add** > **Save**
6. Assign this policy to the Neologik User Group

#### D. Notify Users

After deployment, inform your users:
- The app is available in Microsoft Teams
- How to find it: **Apps** > Search for "[Your Neologik App Name]"
- How to add it to their Teams sidebar

### Verify Deployment

1. **Test as a user:**
   - Open Microsoft Teams as a user in the Neologik User Group
   - Click **Apps** in the left sidebar
   - Search for the Neologik app
   - The app should appear in the search results
   - Click to open and verify it loads correctly

2. **Check usage analytics** (after a few days):
   - Teams Admin Center > **Teams apps** > **Manage apps**
   - Click on the Neologik app
   - View **Analytics** tab for usage statistics

---

## Step 4: Grant Users Access to the Bot

Bot access is controlled by security groups in your Entra ID. Each bot (agent) is attached to an access group — **only users who are members of that group can use it.** Users who are not in the group will be denied access even if they can see the app in Teams.

By default every agent uses the group created during onboarding, named `Neologik User Group - <short name>` (e.g., `Neologik User Group - neokad01`). If you want a different or per-agent group, tell Neologik which existing Entra group to attach — the platform never creates groups itself. **Your Entra ID administrator is responsible for managing membership on an ongoing basis.**

### What You Need
- **Group name(s)** confirmed with Neologik — the default `Neologik User Group - <short name>`, or the group(s) you chose per agent
- **Global Administrator** or **Groups Administrator** role in Entra ID

### Instructions

#### A. Find the Bot Access Group

1. Go to **Azure Portal** (portal.azure.com)
2. Navigate to **Microsoft Entra ID** > **Groups**
3. Search for `Neologik User Group` — you will see the default access group (and any other groups you chose per agent)
4. Click the group for the bot you want to manage

#### B. Add Users to the Group

1. In the group, click **Members** in the left sidebar
2. Click **Add members**
3. Search for the user by name or email address
4. Select the user and click **Select**

Repeat for each user who needs access. Users are granted access immediately — no restart or redeployment is required.

#### C. Remove Users from the Group

To revoke access, follow the same steps and use **Remove** on the Members page.

> **Note:** If a user was recently added and is still seeing "Unauthorized", ask them to close and reopen the bot in Teams. Group membership changes can occasionally take a few minutes to reflect.

### Ongoing Responsibility

Managing group membership is an **ongoing administrative task**. When new employees join or roles change, your Entra ID administrator should update group membership accordingly. Neologik does not manage this on your behalf.

---

## Verification Checklist

Before considering the deployment complete, verify:

- [ ] DNS A record is created and resolving to the correct IP address
- [ ] Bot application has tenant-wide admin consent granted
- [ ] Admin Tool application has tenant-wide admin consent granted
- [ ] Both applications appear in Enterprise applications with "Admin consent granted"
- [ ] Teams app is uploaded to Teams Admin Center
- [ ] Teams app is available to the Neologik User Group
- [ ] At least one test user has been added to each agent's access group in Entra ID
- [ ] Test user can find and open the app in Microsoft Teams
- [ ] Test user can send a message and receive a response (confirms group access is working)
- [ ] Application loads correctly when accessed via the FQDN (https://app.yourcompany.com)

---

## Troubleshooting

### DNS Issues
**Problem:** DNS not resolving
- **Solution:** Check TTL settings, verify with DNS provider, wait for propagation (up to 48 hours)

**Problem:** Wrong IP address returned
- **Solution:** Verify A record value, clear DNS cache: `ipconfig /flushdns` (Windows) or `sudo dscacheutil -flushcache` (Mac)

### Consent Issues
**Problem:** "Need admin approval" error when users try to access
- **Solution:** Ensure admin consent was granted by a Global Admin, check Enterprise Applications in Azure Portal

**Problem:** Consent URLs not working
- **Solution:** Verify you're using the correct tenant ID and client IDs, contact Neologik support

### Bot Access Issues
**Problem:** User sees "You do not have permission to use this bot" or "Unauthorized"
- **Solution:** The user is not a member of the bot's access group in Entra ID. Go to **Microsoft Entra ID** > **Groups** > find the agent's access group (default `Neologik User Group - <short name>`) > **Members** > **Add members**. Access is granted immediately.

**Problem:** User was just added to the group but still sees "Unauthorized"
- **Solution:** Ask the user to close and reopen the bot in Teams. Group changes can take a few minutes to propagate.

### Teams App Issues
**Problem:** App not appearing in search
- **Solution:** Check app permission policies, verify app is set to "Allowed", ensure user is in the correct group

**Problem:** App won't load or shows error
- **Solution:** Verify app was uploaded correctly, check for any blocking policies, try removing and re-adding the app

---

## Later changes and migration windows

After onboarding, the one script a Global Administrator ever runs again is
`Update-NeologikEnvironmentAccess.ps1` (in this repository). It verifies
before it writes, changes nothing on a compliant environment and is safe
to re-run; with `-Verify` it only reports what it would change (as
`WOULD ...` items in its summary) and writes nothing, exiting 1 when
anything would change. Neologik supplies the files it reads, and the files
you give it select the run:

- **Pre-window run** - the command line Neologik sends you, with no grants
  file. What the script checks and changes, and why, is explained step by
  step in [ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md](ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md). Neologik fills in every value, so you type nothing but your
  sign-in, and the configuration file from your original onboarding is not
  needed. Download the latest `Update-NeologikEnvironmentAccess.ps1` from
  this repository, run the command exactly as sent, and return the summary
  JSON it writes. Every customer has this one run, any time before the
  migration window. It verifies or applies everything only a Global
  Administrator can change: the agent identity blueprint and its principal
  role, the deployment identity's two retained Microsoft Graph roles (its
  retired tenant-wide roles are removed once those are in place), the NCE
  user group assignment on the sign-in application, the sign-in
  application's tenant-wide admin consent, the SharePoint `Sites.Selected`
  consent where SharePoint ingestion is in use, ownership of your Neologik
  application registrations by the deployment identity (exactly the ones
  named on the command line; any other registration whose name starts
  with "Neologik" is only reported, never changed), and then the
  permission reduction: the deployment identity receives the narrow
  resource-group role set and the two retained subscription roles (Reader,
  Cost Management Contributor) BEFORE its broad subscription roles
  (Contributor, User Access Administrator) and its Application
  Administrator directory role are removed. If any narrow role could not
  be applied, nothing is removed. The account you sign in with needs
  Global Administrator in Entra ID and Owner (or User Access
  Administrator) on the subscription.

  The values Neologik fills in:

  | Parameter | What it is |
  |---|---|
  | `-TenantId` | your Entra ID tenant |
  | `-SubscriptionId`, `-ResourceGroupName` | the subscription and resource group Neologik deploys into |
  | `-DeploySpClientId` | the deployment identity (the "Neologik GitHub Service Connection" application) |
  | `-SolutionName`, `-SolutionShortName` | the names Neologik's deployment uses for your environment |
  | `-SignInAppClientId` | the "Neologik Platform Sign-in" application that controls who can open the Neologik Context Engine |
  | `-SharePointAppClientId` | the "Neologik SharePoint Access" application, only where you ingest from SharePoint |
  | `-BotAppClientIds` | the application registration of each Neologik bot in your tenant |
  | `-NceUserGroupId`, `-AdminGroupId` | your Neologik NCE User Group and Admin User Group |
- **Post-window run** - the same script with `-AgentGrantsFile <json>`
  and/or `-MailboxGrantsFile <json>`, files Neologik exports from the
  platform. Needed only once an agent or App works unattended on your
  organisation's behalf in Microsoft 365 - an autonomy-adoption event, not
  a migration step; a customer with no unattended work never has this
  run. It applies exactly what the files list and nothing else: the
  agent-user delegated grants for the agents and Apps with enabled
  permission packs, and/or the Exchange Online mailbox grants for email
  channels. `-RemoveLegacyGrantAppIds` (with `-MailboxGrantsFile`) removes
  a retired identity's mailbox assignments; an identity the file lists as
  adopted by the v5 email channel keeps its assignment.

Every run prints any consent URL you still need to open, writes a JSON
summary beside itself (or in the current folder when that location is
read-only) for Neologik's ticket, never stops on the first problem, lists
anything that needs you in the summary with the reason, and exits 0 only
when everything is in the expected state. Full parameter help:
`Get-Help ./Update-NeologikEnvironmentAccess.ps1 -Detailed`.

### What the sign-in asks you to approve

The script signs in to Microsoft Graph under your own account (device
code). On first use Microsoft shows a consent screen listing the
delegated permissions the script requests. All of them are delegated:
they let the script act as you for this session only and grant nothing
to any application.

| Permission | Why the script needs it |
|---|---|
| `Application.ReadWrite.All` | Read and adopt the agent identity blueprint and its principal; add the pipeline's federated credentials |
| `AppRoleAssignment.ReadWrite.All` | Grant and remove the deployment identity's Microsoft Graph application roles; assign the NCE user group to the sign-in application |
| `Directory.Read.All` | Read the service principals, groups and directory roles the checks compare against (read-only) |
| `User.Read` | Resolve your own account as the sponsor when the agent identity blueprint has to be created (read-only) |
| `DelegatedPermissionGrant.Read.All` | Read the sign-in application's tenant-wide admin consent |
| `AgentIdentityBlueprint.Create`, `AgentIdentityBlueprint.AddRemoveCreds.All`, `AgentIdentityBlueprintPrincipal.Create` | Create the agent identity blueprint, its principal and its credentials when they do not exist yet |
| `RoleManagement.ReadWrite.Directory` (pre-window run only) | Remove the deployment identity's Application Administrator directory role membership |
| `DelegatedPermissionGrant.ReadWrite.All` (post-window run with `-AgentGrantsFile` only) | Create the agent-user delegated grants the file lists |

`Directory.Read.All` and `User.Read` are read-only: the script can change
nothing with them, and without them the group, consent and directory-role
checks fail on a tenant where no earlier consent exists. The Azure sign-in
(pre-window run) and the Exchange Online sign-in (post-window run with
`-MailboxGrantsFile`) use the same account. A `-Verify` run signs in the
same way and shows the same screen.

---

## Need Help?

If you encounter any issues during these steps, contact Neologik support:
- 📧 Email: support@neologik.ai
- 📱 Include in your message:
  - Step where you're experiencing issues
  - Error messages or screenshots
  - Your organization name and deployment details

---

## Next Steps

Once all steps are complete:
1. ✅ Inform Neologik that post-deployment configuration is complete
2. ✅ Conduct user acceptance testing (UAT) with a small group
3. ✅ Provide feedback to Neologik on the deployment
4. ✅ Plan broader rollout to all users
5. ✅ Schedule training sessions for end users (if needed)

Congratulations! Your Neologik environment is now fully deployed and ready for use! 🎉
