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
   - Format: `https://login.microsoftonline.com/common/adminconsent?client_id={bot-id}&redirect_uri=https://{hostName}/nce`
   - `{hostName}` = Your full qualified hostname
   - `{bot-id}` = Bot application ID provided by Neologik

2. **Sign in** with your Global Administrator or Privileged Role Administrator account

3. **Review the requested permissions:**
   - Read user profiles
   - Send messages on behalf of the bot
   - Other bot-specific permissions

4. **Click "Accept"** to grant tenant-wide consent

5. **Confirmation:** You should see a success message

#### B. Grant Access to NCE Admin Tool Application

1. **Open the Admin Tool consent URL** provided by Neologik in your browser
   - Format: `https://login.microsoftonline.com/common/adminconsent?client_id={nce-admin-id}&redirect_uri=https://{hostName}/nce`
   - `{hostName}` = Your full qualified hostname (same as above)
   - `{nce-admin-id}` = NCE Admin Tool application ID provided by Neologik

2. **Sign in** with your Global Administrator or Privileged Role Administrator account

3. **Review the requested permissions:**
   - Manage application settings
   - Read user and group information
   - Other admin tool permissions

4. **Click "Accept"** to grant tenant-wide consent

5. **Confirmation:** You should see a success message

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

Bot access is controlled by security groups in your Entra ID. Each bot has its own dedicated group — **only users who are members of the group can use that bot.** Users who are not in the group will be denied access even if they can see the app in Teams.

These groups are created automatically during deployment. **Your Entra ID administrator is responsible for managing membership on an ongoing basis.**

### What You Need
- **Group names** provided by Neologik — one per bot, named in the format:
  `Neologik User Group <bot name> - <environment>` (e.g., `Neologik User Group Contract Agent - kadprd`)
- **Global Administrator** or **Groups Administrator** role in Entra ID

### Instructions

#### A. Find the Bot Access Group

1. Go to **Azure Portal** (portal.azure.com)
2. Navigate to **Microsoft Entra ID** > **Groups**
3. Search for `Neologik User Group` — you will see one group per bot
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
- [ ] At least one test user has been added to each bot's access group in Entra ID
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
- **Solution:** The user is not a member of the bot's access group in Entra ID. Go to **Microsoft Entra ID** > **Groups** > find the `Neologik User Group <bot name>` group > **Members** > **Add members**. Access is granted immediately.

**Problem:** User was just added to the group but still sees "Unauthorized"
- **Solution:** Ask the user to close and reopen the bot in Teams. Group changes can take a few minutes to propagate.

### Teams App Issues
**Problem:** App not appearing in search
- **Solution:** Check app permission policies, verify app is set to "Allowed", ensure user is in the correct group

**Problem:** App won't load or shows error
- **Solution:** Verify app was uploaded correctly, check for any blocking policies, try removing and re-adding the app

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
