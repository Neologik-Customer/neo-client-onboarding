# Neologik Setup Guide for Customers

> **For IT/Security Review:** See [QUICK-REFERENCE.md](QUICK-REFERENCE.md) for a concise list of all Azure changes and permissions.

> **Contributors - no customer data, ever.** This repository is
> customer-facing: treat it as **public regardless of its visibility
> setting**. Never commit, log, or attach anything containing customer data:
> configuration JSONs, deployment references, workshop inputs, run logs - and
> no GitHub Actions workflows that take customer details as inputs (run logs,
> summaries and download links here are world-readable). The onboarding kit
> zip is built by an internal Neologik workflow that checks this repository
> out - not by an action in this repository.

## 📁 Repository Contents

Welcome! This repository contains everything you need to set up your Neologik environment on Azure.

**Main Files:**
- **Install-NeologikEnvironment.ps1** - The PowerShell script that creates your Azure resources
- **PFX-CERT-GUIDE.md** - Instructions for creating your TLS/SSL certificate
- **CREATE-SP-GUIDE.md** - Optional: how to create the deployment service principal yourself instead of letting the script create it
- **FINISHING-STEPS-GUIDE.md** - Final steps after Neologik completes the deployment
- **Upgrade-TeamsAppInstallations.ps1** + **TEAMS-APP-UPGRADE-GUIDE.md** - Bulk-upgrade every user's installed Neologik Teams bot to the latest version (run periodically, after onboarding)
- **Update-NeologikEnvironmentAccess.ps1** - The Global Administrator's script for a Neologik v5 migration: a pre-window run (checks, grants and the guarded permission reduction; once per customer) and, only where agents or Apps work unattended in Microsoft 365, a post-window run that applies the grants files Neologik supplies. `-Verify` reports without writing. The script prints its own sign-in address and code and waits at most 15 minutes; it needs only a browser on any device and a Global Administrator account. Without the configuration file, pass `-SolutionShortName` (the environment's solution short name). See FINISHING-STEPS-GUIDE.md, "Later changes and migration windows"

**How to Use This Repository:**

**Option 1: Download the Script (Easiest)**
1. Click on `Install-NeologikEnvironment.ps1` above
2. Click the **Download** button (or right-click **Raw** → **Save link as**)
3. Save to your computer (e.g., Downloads folder)
4. Follow the instructions below to run the script

**Option 2: Clone the Repository (If you're familiar with Git)**
```powershell
git clone https://github.com/Neologik-Customer/neo-client-onboarding.git
cd neo-client-onboarding
```

---

## What You Need Before Starting

✅ **Your Azure account** with these permissions:
   - **Owner** role at the subscription level (not just "Contributor")
   - **Global Administrator** role in Azure AD (Entra ID)

✅ **NeologikGuestUsers.txt file** (included in repository):
   - Contains email addresses of Neologik team members to invite as guests
   - Must be in the same folder as the script
   - You can review the file before running the script

⚠️ **CRITICAL - Both Permissions Required:**
- The **Owner** role is required to assign role-based access control (RBAC) permissions. "Subscription Owner" or "Contributor" roles alone are insufficient.
- The **Global Administrator** role is required to assign Entra ID directory roles.
- **The script will stop with an error if you don't have both permissions.** You cannot proceed without them.

✅ **Administrator access** on your Windows computer

✅ **Internet connection**

---

## Step-by-Step Instructions

### 1. Download the Script

Download the `Install-NeologikEnvironment.ps1` file from this repository to your computer.

### 2. Open PowerShell 7 as Administrator

⚠️ **CRITICAL**: You MUST use **PowerShell 7** (not Windows PowerShell 5.1) and run as Administrator.

**Finding PowerShell 7:**
- Click the **Start menu**
- Type **"PowerShell"** 
- Look for **"PowerShell 7"** or just **"PowerShell"** (with the modern icon)
- **DO NOT** use "Windows PowerShell" (the old version 5.1 will cause errors)

**If PowerShell 7 is not installed:**
- The script will offer to install it automatically
- Or download it manually from: https://aka.ms/powershell

**To run as Administrator:**
- Right-click on **"PowerShell 7"**
- Click **"Run as administrator"**
- Click **"Yes"** when prompted

You should see "Administrator: PowerShell 7" in the window title if done correctly.

**Verify you're using PowerShell 7:**
```powershell
$PSVersionTable.PSVersion
```
You should see version 7.4 or higher. If you see 5.1, you opened the wrong PowerShell!

### 3. Navigate to the Script Location

In the PowerShell window, type:
```powershell
cd C:\Downloads
```
(Change the path if you saved the file somewhere else)

### 4. Allow Script Execution

Before running the script, you need to allow PowerShell to execute it. Type this command:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Press **Enter**

This allows the script to run in the current PowerShell session only and is safe.

### 5. Run the Script

Type this command:
```powershell
.\Install-NeologikEnvironment.ps1
```

Press **Enter**

> **Resuming after an interruption:** As it runs, the script saves its progress to a `NeologikCheckpoint.json` file in the same folder. If the script stops before finishing (for example, due to an error), simply run it again — it will offer to resume from where it left off and skip the steps already completed. The checkpoint file is deleted automatically once the script finishes successfully.

### 6. Answer the Configuration Questions

The script will ask you several questions. For each one:
- You'll see a **default value** in yellow
- **Press Enter** to accept the default (easiest option)
- **Or type a new value** and press Enter

Questions you'll be asked:

1. **Organization Name**: Your full company name (e.g., "Contoso Ltd", "Acme Corporation")
   - This is required and cannot be empty
   - Used for documentation and identification

2. **Bot Hostname (full FQDN)**: The bot's complete public hostname (e.g., "neologik.contoso.com")
   - This is required and cannot be empty
   - Any `https://` prefix or trailing path is stripped; converted to lowercase
   - Must be a valid fully-qualified domain name (host and domain together)

3. **Organization Code**: Your 3-letter company code (e.g., "ABC")
   - Must be **exactly 3 characters**
   - Only letters and numbers allowed
   - Automatically converted to lowercase
   - The script will keep asking until you enter a valid code

4. **Environment Type**: `dev` for development or `prd` for production
   - Must be either `dev` or `prd`
   - Automatically converted to lowercase
   - The script will keep asking until you enter a valid type

5. **Azure Region**: Where to create resources (e.g., "uksouth", "eastus")
   - Must be a valid Azure region name
   - Common options: uksouth, ukwest, eastus, westus, northeurope, westeurope
   - Automatically converted to lowercase
   - The script will keep asking until you enter a valid region

6. **Environment Index**: Number for this environment (01, 02, etc.)
   - Use default "01" for first setup
   - Must be a number between 01 and 99
   - The script will keep asking until you enter a valid number

7. **Resource Group Name**: Where resources will be organized
   - Default follows Azure naming conventions
   - Can contain letters, numbers, underscores, hyphens, periods, and parentheses
   - Cannot end with a period

8. **Apply Azure Resource Tags**: "Apply Azure resource tags to created resources? (true/false)"
   - Default is true
   - When true, every resource the script creates (resource group, Key Vault, storage account, managed identities) is tagged at creation with Vendor, ApplicationName, ManagedBy, Environment, Solution and DeploymentDate - required by tenants whose Azure Policies deny creation of untagged resources
   - When true, you can optionally add custom tags as comma-separated key=value pairs (keys use letters, digits, '.', '_' and '-'; custom tags override the defaults)
   - When false, no tags are applied

9. **Resource Names**: Key Vault, Storage Account and Managed Identity names
   - Each prompt shows the computed standard name as the default - just press Enter to accept
   - Type a different name only if your organisation mandates its own naming convention
   - (You will not be asked about bots or agents - those are created after deployment in the Neologik admin tool)

10. **Budget Cost-Report Email Recipient(s)**: Where the daily Azure cost report is sent
    - Press Enter for the default, enter one or more addresses separated by commas, or type "none" to disable

11. **Invite Neologik guest users?**: Whether to invite the Neologik team members listed in `NeologikGuestUsers.txt` as guests
    - The addresses in the file are listed on screen first; default is Yes. Choose No if you provision accounts for the Neologik team in your own tenant instead
    - If you choose Yes, you are asked whether to **add any more addresses to invite** - type them one per line, Enter on an empty line to finish (a line may hold several, comma-separated). This also works when the file is empty or missing: choose Yes and type the whole list
    - If you choose No, a follow-up question asks: **"Add existing accounts to the security groups?"** - answer Yes to add accounts you have already created (guests or full members) with no invitation sent. The addresses come from `NeologikGuestUsers.txt`, or you can type them in one per line - press Enter after each address and press Enter on an empty line when you have finished (a line may also hold several addresses separated by commas). An address with no matching account is reported and skipped - the script carries on
    - Note: accounts added here go into ALL Neologik groups, including the Admin User Group (Azure admin access) - only list accounts that should hold Neologik admin/support access

12. **Use a service principal you have already created?**: Whether to reuse your own deployment service principal
    - Default is No (the script creates one for you)
    - If Yes, have its **object ID** (the enterprise-application object ID, not the client/app ID) ready, plus optionally its client secret
    - See **[CREATE-SP-GUIDE.md](CREATE-SP-GUIDE.md)** for step-by-step instructions on creating the service principal and finding the correct ID

### 7. Confirm and Continue

After answering the questions, you'll see a summary. Press **Enter** to continue.

The script will then:
- **PowerShell Update**: If needed, press **Enter** to update
- **Module Installation**: If needed, press **Enter** to install
- **Re-authentication Prompt**: If you're already logged in, you'll be asked if you want to re-authenticate
  - Press **N** to continue with your current login (recommended)
   - Press **Y** to login again (useful if you need to switch accounts)
- **Azure Login**: A browser window will open - sign in with your Azure account (if re-authenticating or not logged in)

### 8. Wait for Completion

The script will automatically create all required Azure resources. This may take 5-10 minutes.

You'll see messages like:
- ✓ Creating resource groups
- ✓ Setting up security groups
- ✓ Creating Key Vault (for storing secrets)
- ✓ Creating Storage Account (for certificates)
- ✓ Configuring permissions

### 9. Review the ResultsWhen complete, you'll see a green success message and a summary of what was created.

Two files will be saved in the same folder:
- `Neologik_[org][index]_Configuration_[date].json` - Configuration details
- `NeologikOnboarding_[date].log` - Detailed log file

---

## Next Steps After Script Completion

The script will display your next steps. You need to:

### 1. Review and Share Configuration
✉️ Send the **JSON configuration file** (`Neologik_[org][index]_Configuration_[date].json`) to Neologik at support@neologik.ai

### 2. Decide on Your Fully Qualified Domain Name (FQDN)
🌐 **Choose your hostname and coordinate with Neologik:**
   - A Fully Qualified Domain Name (FQDN) is the complete web address users will type to reach your Neologik deployment — for example, `neologik.yourcompany.com`. It combines a subdomain you choose (e.g. `neologik`) with your organisation's existing domain (e.g. `yourcompany.com`).
   - Decide on the FQDN for your deployment and confirm it with whoever manages your company's DNS
   - Share this with Neologik at support@neologik.ai
   - ⚠️ **Important:** Complete this step before creating your TLS certificate, as the certificate must match your chosen hostname

### 3. Create and Upload Your TLS Certificate

📋 **First, create your certificate:**
   - Follow the detailed instructions in **[PFX-CERT-GUIDE.md](PFX-CERT-GUIDE.md)**
   - This guide explains how to create a self-signed certificate or convert an existing certificate to .pfx format
   - **Important:** Use the hostname from Step 2 when creating the certificate
   - You'll need the .pfx file and its password for the next steps

📁 **Then, upload the .pfx file** to the Azure Storage Account:
   - **Storage Account**: `stneodeployneo[your-org][region][index]` (shown in the script's completion summary)
   - **Container**: `certificate`
   - **Authentication**: Use Microsoft Entra ID (your Azure account)

**To upload:**
1. Open Azure Portal (portal.azure.com)
2. Navigate to the storage account
3. Click on "Containers"
4. Click on "certificate" container
5. Click "Upload" and select your .pfx file

### 4. Store Certificate Password
🔐 Store your certificate PFX password in Key Vault:
   - **Key Vault**: Same as above
   - **Secret Name**: `neologik-deployment-certificate-pfx-secret`

**To store:**
1. Open Azure Portal (portal.azure.com)
2. Navigate to the Key Vault
3. Click on "Secrets"
4. Click "+ Generate/Import"
5. Name: `neologik-deployment-certificate-pfx-secret`
6. Value: Your certificate password
7. Click "Create"

---

## After Neologik Deployment

Once you've completed the steps above and Neologik has deployed the environment to your resource group, you'll need to complete the final configuration steps.

📋 **See: [FINISHING-STEPS-GUIDE.md](FINISHING-STEPS-GUIDE.md)** for detailed instructions on:
- Creating DNS A records for your hostname
- Granting tenant access to the Bot and Admin Tool
- Uploading and deploying the Teams app to your organization
- Running the Global Administrator script at a Neologik v5 migration window ("Later changes and migration windows")

These final steps will make the application accessible to your users.

---

## Need Help?

📧 Email: support@neologik.ai  
📞 Include the log file when contacting support
