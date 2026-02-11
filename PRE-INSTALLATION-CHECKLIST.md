# Pre-Installation Checklist

**Before running** `Install-NeologikEnvironment.ps1`, ensure you have gathered all the required information listed below.

---

## ⚠️ Critical Requirements

### Azure Permissions (MANDATORY)

You **must** have **both** of the following permissions. The script will fail if you don't have them:

- [ ] **Owner** role at the subscription level
  - Not just "Contributor" - you need "Owner" to assign RBAC permissions
  - Required for role assignments and access control
  
- [ ] **Global Administrator** role in Azure AD (Entra ID)
  - Required to assign Entra ID directory roles
  - Required for creating security groups and managing guest users

⚠️ **The script cannot proceed without both permissions.**

### System Requirements

- [ ] **PowerShell 7** (version 7.4 or higher)
  - Not Windows PowerShell 5.1
  - Download from: https://aka.ms/powershell
  - The script can install this for you if needed

- [ ] **Administrator privileges** on your Windows computer
  - Required to run the script

- [ ] **Internet connection**
  - Required for Azure authentication and resource creation

### Required Files

- [ ] **NeologikGuestUsers.txt** file
  - Must be in the same folder as the script
  - Contains email addresses of Neologik team members to invite as guests
  - Included in the repository
  - Review and verify the guest user emails before running

---

## 📋 Information to Gather

Before running the script, prepare the following information. You will be prompted for these during script execution:

### 1. Organization Information

- [ ] **Organization Name** (full company name)
  - Example: "Contoso Ltd", "Acme Corporation", "South Eastern Carpentry Ltd"
  - Used for documentation and identification
  - **Required** - cannot be empty

- [ ] **Organization Code** (3-character identifier)
  - Example: "ABC", "sec", "xyz"
  - Must be **exactly 3 characters**
  - Only letters and numbers allowed
  - Will be automatically converted to lowercase
  - Default: "abc"

### 2. Environment Configuration

- [ ] **Environment Type**
  - Options: `dev` (development) or `prd` (production)
  - Will be automatically converted to lowercase
  - Default: "dev"

- [ ] **Environment Index**
  - Number for this environment: 01, 02, 03, etc.
  - Use "01" for first setup
  - Must be between 01 and 99
  - Default: "01"

### 3. Network Information

- [ ] **Hostname** (server/computer name)
  - Example: "server01", "web-server", "app-host"
  - Will be automatically converted to lowercase
  - **Required** - cannot be empty

- [ ] **Domain Name**
  - Example: "contoso.com", "example.local", "yourcompany.com"
  - Will be automatically converted to lowercase
  - **Required** - cannot be empty

### 4. Azure Configuration

- [ ] **Azure Subscription Name**
  - Name of the Azure subscription to use
  - Default: "Neologik-Development-01"
  - Can be changed during script execution

- [ ] **Azure Region** (where resources will be created)
  - Must be a valid Azure region name
  - Common options:
    - UK: `uksouth`, `ukwest`
    - Europe: `northeurope`, `westeurope`, `switzerlandnorth`
    - US: `eastus`, `eastus2`, `westus`, `westus2`
    - Other: `australiaeast`, `southeastasia`, `japaneast`
  - Default: "uksouth"
  - Will be automatically converted to lowercase

- [ ] **Tenant ID** (optional)
  - If not provided, will use current Azure context
  - Format: GUID (e.g., "d4003661-f87e-4237-9a9b-8b9c31ba2467")

- [ ] **Resource Group Name** (optional)
  - Default follows Azure naming conventions: `rg-neo-{orgcode}-{env}-{region}-{index}`
  - Can contain: letters, numbers, underscores, hyphens, periods, parentheses
  - Cannot end with a period

### 5. Bot Configuration

- [ ] **Bot Count**
  - How many bots will be deployed? (1-10)
  - Default: 1
  - Used to create separate user groups for each bot

For **each bot**, prepare:

- [ ] **Agent Name** (descriptive name)
  - Example: "bot", "RAMS Agent", "support"
  - Lowercase only
  - Maximum 7 characters
  - Letters and dashes only
  - Used in security group names

- [ ] **Short Name** (short identifier)
  - Example: "bot", "sup", "rams"
  - Lowercase only
  - Maximum 7 characters
  - Letters and dashes only
  - Used internally for identification

---

## 📝 Optional Parameters

These parameters can be passed to the script on the command line to skip interactive prompts:

```powershell
# Example with all parameters
.\Install-NeologikEnvironment.ps1 `
    -OrganizationCode "sec" `
    -EnvironmentType "dev" `
    -AzureRegion "switzerlandnorth" `
    -TenantId "your-tenant-id" `
    -SubscriptionName "Your Subscription Name" `
    -SkipPowerShellUpdate `
    -SkipModuleInstall
```

**Available parameters:**
- `-OrganizationCode` - 3-character organization code
- `-EnvironmentType` - "dev" or "prd"
- `-AzureRegion` - Azure region name
- `-TenantId` - Azure Tenant ID (optional)
- `-SubscriptionName` - Name for the subscription
- `-SkipPowerShellUpdate` - Skip PowerShell version check
- `-SkipModuleInstall` - Skip Azure module installation check

---

## ✅ Pre-Flight Checklist

Before running the script, verify:

- [ ] I have **Owner** role at the subscription level
- [ ] I have **Global Administrator** role in Azure AD (Entra ID)
- [ ] I'm using **PowerShell 7** (not Windows PowerShell 5.1)
- [ ] I'm running PowerShell **as Administrator**
- [ ] The **NeologikGuestUsers.txt** file is in the same folder as the script
- [ ] I have reviewed the guest user email addresses
- [ ] I have gathered all required information listed above
- [ ] I have an active **internet connection**
- [ ] I have read and accept the **Neologik Terms of Use** and **Privacy Policy**
  - Terms: https://www.neologik.ai/terms-of-use
  - Privacy: https://www.neologik.ai/privacy-policy

---

## 📂 Files Generated by Script

After successful execution, the script will create:

- `NeologikConfiguration_{date}.json` - Configuration details to share with Neologik
- `NeologikOnboarding_{date}.log` - Detailed execution log

⚠️ **Important:** These files contain sensitive information and should not be committed to source control. The `.gitignore` file is configured to exclude them automatically.

---

## 🔄 Next Steps After Script Completion

After the script completes successfully, you will need to:

1. **Share Configuration** - Send the JSON file to support@neologik.ai
2. **Choose FQDN** - Decide on your fully qualified domain name and coordinate with Neologik
3. **Create TLS Certificate** - Follow [PFX-CERT-GUIDE.md](PFX-CERT-GUIDE.md)
4. **Upload Certificate** - Upload .pfx file to Azure Storage Account
5. **Store Password** - Save certificate password in Azure Key Vault
6. **Complete Deployment** - Follow [FINISHING-STEPS-GUIDE.md](FINISHING-STEPS-GUIDE.md)

---

## 📧 Support

If you have questions or need assistance:

- Email: support@neologik.ai
- Include the log file when contacting support

---

## 📚 Additional Resources

- [README.md](README.md) - Complete setup guide
- [QUICK-REFERENCE.md](QUICK-REFERENCE.md) - Quick reference for IT/security review
- [PFX-CERT-GUIDE.md](PFX-CERT-GUIDE.md) - TLS certificate creation guide
- [FINISHING-STEPS-GUIDE.md](FINISHING-STEPS-GUIDE.md) - Post-deployment steps
- [TECHNICAL-REFERENCE.md](TECHNICAL-REFERENCE.md) - Technical details and architecture
