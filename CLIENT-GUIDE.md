# Neologik Setup Guide for Customers

## What You Need Before Starting

✅ **Your Azure account** with these permissions:
   - Subscription Owner
   - Global Administrator

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

### 6. Answer the Configuration Questions

The script will ask you several questions. For each one:
- You'll see a **default value** in yellow
- **Press Enter** to accept the default (easiest option)
- **Or type a new value** and press Enter

Questions you'll be asked:

1. **Organization Name**: Your full company name (e.g., "Contoso Ltd", "Acme Corporation")
   - This is required and cannot be empty
   - Used for documentation and identification

2. **Organization Code**: Your 3-letter company code (e.g., "ABC")
   - Must be **exactly 3 characters**
   - Only letters and numbers allowed
   - The script will keep asking until you enter a valid code

3. **Environment Type**: `dev` for development or `prd` for production
   - Must be either `dev` or `prd`
   - The script will keep asking until you enter a valid type

4. **Azure Region**: Where to create resources (e.g., "uksouth", "eastus")
   - Must be a valid Azure region name
   - Common options: uksouth, ukwest, eastus, westus, northeurope, westeurope
   - The script will keep asking until you enter a valid region

5. **Environment Index**: Number for this environment (01, 02, etc.)
   - Use default "01" for first setup
   - Must be a number between 01 and 99
   - The script will keep asking until you enter a valid number

6. **Resource Group Name**: Where resources will be organized
   - Default follows Azure naming conventions
   - Can contain letters, numbers, underscores, hyphens, periods, and parentheses
   - Cannot end with a period

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
- `NeologikConfiguration_[date].json` - Configuration details
- `NeologikOnboarding_[date].log` - Detailed log file

---

## Next Steps After Script Completion

The script will display your next steps. You need to:

### 1. Review and Share Configuration
✉️ Send the **JSON configuration file** (`NeologikConfiguration_[date].json`) to Neologik at support@neologik.ai

### 2. Upload Your TLS Certificate
📁 Upload your TLS certificate (.pfx file) to the Azure Storage Account:
   - **Storage Account**: `stneodeploy[your-org][env][region][index]`
   - **Container**: `certificate`
   - **Authentication**: Use Microsoft Entra ID (your Azure account)

**To upload:**
1. Open Azure Portal (portal.azure.com)
2. Navigate to the storage account
3. Click on "Containers"
4. Click on "certificate" container
5. Click "Upload" and select your .pfx file

### 3. Store Certificate Password
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

## What Gets Created

The script automatically creates resources with names that include your organization code and environment type for easy identification:

✅ **Security Groups** (3 groups)
   - Neologik User Group - abc-dev
   - Neologik NCE User Group - abc-dev
   - Neologik Admin User Group - abc-dev

✅ **App Registration** for GitHub deployments
   - Name: Neologik GitHub Service Connection - abc-dev
   - Client secret stored in Key Vault automatically
   - Subscription roles: Contributor, User Access Administrator
   - Entra ID role: Application Administrator

✅ **Key Vault** for storing secrets
   - Name: kvneodeployabcdevuks01
   - Uses Microsoft Entra ID RBAC authorization
   - Service principal secret stored automatically
   - Permissions: Key Vault Secrets Officer role assigned

✅ **Storage Account** for certificates
   - Name: stneodeployabcdevuks01
   - Uses Microsoft Entra ID authentication (no access keys)
   - Blob container named "certificate"
   - Permissions: Storage Blob Data Contributor role assigned

✅ **Managed Identities** (2 identities)
   - **Script Runner Service Connection**: neologik-script-runner-service-connection-abc-dev
     - Subscription role: Contributor
     - Entra ID role: Application Administrator
   - **SQL Managed Identity**: neologik-sql-managed-identity-abc-dev
     - Subscription roles: None
     - Entra ID role: Directory Readers

---

## Need Help?

📧 Email: support@neologik.ai  
📞 Include the log file when contacting support
