# Neologik Customer Onboarding Scripts

**Version:** v1.2.4

Automated PowerShell scripts for onboarding customers to Neologik AI solution on Azure.

## Overview

This repository contains a robust PowerShell script that automates the complete Azure environment setup for Neologik customers, including:

- ✅ PowerShell version validation and automatic updates
- ✅ Azure module dependency management
- ✅ Resource provider registration with retry logic
- ✅ Azure authentication with re-authentication option
- ✅ Input validation for all configuration parameters
- ✅ Guest user invitations
- ✅ Subscription and resource group setup
- ✅ Security group creation and configuration
- ✅ App Registration (Service Principal) creation with secure secret storage
- ✅ Key Vault setup with RBAC authorization
- ✅ Storage Account for certificate storage with Entra ID authentication
- ✅ Managed Identity setup with role assignments and retry logic
- ✅ Role-based access control (RBAC) assignments with retry logic for replication delays
- ✅ Comprehensive logging and error handling
- ✅ Configuration export with script version tracking

## What's New in v1.2.4

### Enhanced User Experience
- ✅ **Organization Name**: Added organization name input for better documentation
- ✅ **Guest User Support**: Fixed guest user detection and group membership
- ✅ **Current User ID**: Proper retrieval of current user ID from Microsoft Graph context
- ✅ **Key Vault Permissions**: Reordered operations to assign permissions before storing secrets

### Improved Reliability
- ✅ **Retry Logic**: Enhanced retry logic for Key Vault secret storage with permission propagation
- ✅ **Current User Roles**: Assign Key Vault Secrets Officer role to current user first
- ✅ **Permission Propagation**: Added wait times for role assignment propagation
- ✅ **Multi-tenant Support**: Better handling of guest users in multi-tenant scenarios

### JSON Output Improvements
- ✅ **Ordered Fields**: Structured JSON output with logical field ordering
- ✅ **Organization Info**: Organization name and code at the top
- ✅ **Better Organization**: Tenant, subscription, and resource information grouped logically

## Prerequisites

### System Requirements

- **Operating System**: Windows 11 (or Windows 10 with latest updates)
- **PowerShell**: 7.4 or higher (script will offer to install/update if needed)
- **Administrator Access**: Required for module installation and system updates

### Azure Requirements

- **Azure Tenant**: Active Azure AD (Entra ID) tenant
- **Subscription**: Azure subscription with appropriate billing setup
- **User Permissions**: 
  - **Owner** role at the subscription level (required for RBAC assignments)
  - **Global Administrator** role in Azure AD (Entra ID)
  - Note: "Contributor" or "Co-Administrator" roles are insufficient for role assignments

### Network Requirements

- Internet connectivity for:
  - Azure portal access
  - PowerShell module downloads from PSGallery
  - Guest user invitation emails

## Installation

### Quick Start

1. **Clone or download this repository:**

   ```powershell
   git clone https://github.com/Neologik-AI/neo-client-onboarding-scripts.git
   cd neo-client-onboarding-scripts
   ```

2. **Open PowerShell as Administrator:**

   Right-click PowerShell and select "Run as Administrator"

3. **Run the script:**

   ```powershell
   .\Install-NeologikEnvironment.ps1
   ```

   The script will prompt you for all configuration values with sensible defaults. Simply press Enter to accept defaults, or type your own values.

### Command-Line Parameters (Optional)

You can also provide parameters directly to skip some prompts:

```powershell
.\Install-NeologikEnvironment.ps1 -OrganizationCode "ABC"
```

Or specify all parameters:

```powershell
.\Install-NeologikEnvironment.ps1 `
    -OrganizationCode "XYZ" `
    -EnvironmentType "prd" `
    -AzureRegion "ukwest" `
    -SubscriptionName "Neologik-Production-01"
```

## Script Parameters

| Parameter | Type | Default | Description | Validation |
|-----------|------|---------|-------------|------------|
| `OrganizationCode` | String | `"ORG"` | 3-character organization code for resource naming | Must be exactly 3 alphanumeric characters |
| `EnvironmentType` | String | `"dev"` | Environment type: `dev` or `prd` | Must be `dev` or `prd` |
| `AzureRegion` | String | `"uksouth"` | Azure region for resource deployment | Must be a valid Azure region name |
| `TenantId` | String | (current) | Azure Tenant ID (optional, uses current context) | - |
| `SubscriptionName` | String | `"Neologik-Development-01"` | Name for the Azure subscription |
| `SkipPowerShellUpdate` | Switch | `false` | Skip PowerShell version check and update |
| `SkipModuleInstall` | Switch | `false` | Skip Azure module installation check |

## Usage Examples

### Example 1: Interactive Setup (Recommended)

```powershell
.\Install-NeologikEnvironment.ps1
```

The script will prompt for all values with defaults:
```
Organization Code (3 characters max):
  Default: ORG
  Press Enter to use default, or type new value: ABC
  ✓ Using: ABC

Environment Type:
  Default: dev
  Valid options: dev, prd
  Press Enter to use default, or type new value: 
  ✓ Using default: dev
```

### Example 2: With Organization Code Parameter

```powershell
.\Install-NeologikEnvironment.ps1 -OrganizationCode "ABC"
```

This sets the organization code to "ABC" and prompts for other values.

### Example 3: Production Environment Setup

```powershell
.\Install-NeologikEnvironment.ps1 `
    -OrganizationCode "XYZ" `
    -EnvironmentType "prd" `
    -AzureRegion "ukwest"
```

This pre-fills several values and prompts for the rest.

### Example 4: Skip Updates (Already Configured System)

```powershell
.\Install-NeologikEnvironment.ps1 `
    -OrganizationCode "ABC" `
    -SkipPowerShellUpdate `
    -SkipModuleInstall
```

## Interactive Configuration Flow

When you run the script, you'll see a configuration setup screen that prompts for each value:

```
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║                   CONFIGURATION SETUP                         ║
║      Please review and confirm the following settings         ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

Organization Code (3 characters max):
  Default: ORG
  Press Enter to use default, or type new value: 
```

**Pro Tip**: Just press **Enter** to accept all defaults for a quick development setup!

## Input Validation

The script includes comprehensive validation for all inputs:

- **Organization Code**: Must be exactly 3 alphanumeric characters
- **Environment Type**: Must be either 'dev' or 'prd'
- **Azure Region**: Must be a valid Azure region name (e.g., uksouth, eastus, westus)
- **Environment Index**: Must be a number between 01 and 99
- **Resource Group Name**: Must follow Azure naming conventions (1-90 characters, alphanumerics, underscores, hyphens, periods, parentheses, cannot end with period)

The script will keep prompting until valid input is provided, ensuring all resources are created with proper names.

## Resource Naming Convention

All resources are named to include your organization code and environment type for easy identification:

- **Security Groups**: `Neologik [Type] Group - abc-dev`
- **App Registration**: `Neologik GitHub Service Connection - abc-dev`
- **Managed Identities**: `neologik-[type]-abc-dev`
- **Key Vault**: `kvneodeploy<org><env><region><index>` (e.g., kvneodeployabcdevuks01)
- **Storage Account**: `stneodeploy<org><env><region><index>` (e.g., stneodeployabcdevuks01)
- **Resource Group**: `rg-neo-<org>-<env>-<region>-<index>` (e.g., rg-neo-abc-dev-uks-01)

This naming convention makes it easy to identify which customer and environment each resource belongs to.

## What the Script Does

### 1. Pre-Flight Checks

- ✅ Validates PowerShell version (7.4+)
- ✅ Offers to install/update PowerShell if needed
- ✅ Checks for required Azure modules
- ✅ Installs missing modules automatically

### 2. Azure Authentication

- ✅ Detects existing Azure login
- ✅ Prompts to re-authenticate or continue with current login
- ✅ Connects to Azure with user credentials (if needed)
- ✅ Connects to Microsoft Graph API
- ✅ Verifies Subscription Owner role
- ✅ Verifies Global Administrator role

### 3. Guest User Management

Invites the following Neologik team members as guests:
- bryan.lloyd@neologik.ai
- rupert.fawcett@neologik.ai
- Jashanpreet.Magar@neologik.ai
- leon.simpson@neologik.ai
- gael.abruzzese@neologik.ai

### 4. Resource Creation

Creates or validates:
- **Subscription**: Uses your current Azure subscription
- **Resource Group**: `rg-neo-<org>-<env>-<region>-<index>`
- **Security Groups** (with current user and Neologik guests):
  - Neologik User Group - abc-dev
  - Neologik NCE User Group - abc-dev
  - Neologik Admin User Group - abc-dev

### 5. App Registration

Creates:
- **App Registration**: "Neologik GitHub Service Connection - abc-dev"
- **Type**: Multi-tenant (AzureADMultipleOrgs)
- **Client Secret**: 365-day expiration, **automatically stored in Key Vault**
- **Roles**:
  - Contributor (Subscription) - with retry logic
  - User Access Administrator (Subscription) - with retry logic
  - Application Administrator (Entra ID) - with retry logic
- **Added to**: Neologik Admin User Group - abc-dev
- **Note**: Includes organization code and environment type in lowercase

### 6. Key Vault

Creates:
- **Key Vault**: `kvneodeploy<org><env><region><index>` (e.g., kvneodeployabcdevuks01)
- **RBAC Authorization**: Enabled (no access policies)
- **Secrets Stored**:
  - Service principal client secret (automatic)
  - Certificate PFX password (manual step)
- **Permissions**: Key Vault Secrets Officer role assigned to Neologik Admin User Group at resource group level

### 7. Storage Account

Creates:
- **Storage Account**: `stneodeploy<org><env><region><index>`
- **Authentication**: Microsoft Entra ID only (shared key access disabled)
- **Blob Container**: `certificate` (for TLS certificate storage)
- **Permissions**: Storage Blob Data Contributor role assigned to Neologik Admin User Group at resource group level

### 8. Managed Identities

Creates two User Assigned Managed Identities with retry logic for replication delays:

1. **neologik-script-runner-service-connection-abc-dev**
   - Display Name: Neologik Script Runner Service Connection - abc-dev
   - Contributor role (Subscription)
   - Application Administrator role (Entra ID)
   - Includes organization code and environment type

2. **neologik-sql-managed-identity-abc-dev**
   - Display Name: Neologik SQL Managed Identity - abc-dev
   - Directory Readers role (Entra ID)
   - Includes organization code and environment type

### 9. Role Assignments

- Adds Neologik guest users to all security groups
- Adds current logged-in user to all security groups
- Assigns Contributor role to Neologik Admin User Group (Subscription level)
- Assigns Key Vault Secrets Officer to Neologik Admin User Group (Resource Group level)
- Assigns Storage Blob Data Contributor to Neologik Admin User Group (Resource Group level)
- All managed identities receive appropriate subscription and Entra ID roles with retry logic
- Retry logic handles Azure AD/Entra ID replication delays for new principals

### 10. Output Generation

Creates two files:
- **Configuration JSON**: `NeologikConfiguration_<timestamp>.json` (includes script version, excludes secret values)
- **Log File**: `NeologikOnboarding_<timestamp>.log`

## Output Files

### Configuration File

The configuration file contains all necessary information to share with Neologik (secrets are NOT included):

```json
{
  "TenantId": "...",
  "TenantName": "...",
  "SubscriptionId": "...",
  "SubscriptionName": "...",
  "ResourceGroupName": "...",
  "AzureRegion": "...",
  "ScriptVersion": "v1.2.1",
  "UserAccount": "user@domain.com",
  "SecurityGroups": [...],
  "AppRegistration": {
    "Name": "Neologik GitHub Service Connection - abc-dev",
    "ClientId": "...",
    "SecretExpiry": "...",
    "SubscriptionRoles": ["Contributor", "User Access Administrator"],
    "EntraRole": "Application Administrator",
    "GroupMemberships": ["Neologik Admin User Group - abc-dev"]
  },
  "KeyVault": {
    "Name": "kvneodeployabcdevuks01",
    "VaultUri": "...",
    "SecretName": "neologik-deployment-service-principle-secret"
  },
  "StorageAccount": {
    "Name": "stneodeployabcdevuks01",
    "BlobEndpoint": "...",
    "ContainerName": "certificate"
  },
  "ManagedIdentities": [
    {
      "Name": "neologik-script-runner-service-connection-abc-dev",
      "PrincipalId": "...",
      "ClientId": "...",
      "SubscriptionRoles": ["Contributor"],
      "EntraRole": "Application Administrator",
      "GroupMemberships": []
    },
    {
      "Name": "neologik-sql-managed-identity-abc-dev",
      "PrincipalId": "...",
      "ClientId": "...",
      "SubscriptionRoles": [],
      "EntraRole": "Directory Readers",
      "GroupMemberships": []
    }
  ],
  "RoleAssignments": [
    {
      "Principal": "Neologik Admin User Group - abc-dev",
      "PrincipalType": "Security Group",
      "Role": "Contributor",
      "Scope": "Subscription"
    }
  ],
  "InvitedGuestUsers": [...]
}
```

**Note**: Client secrets are stored securely in Key Vault and NOT included in the JSON output.

### Log File

The log file contains detailed execution information:
- Timestamps for all operations
- Success/warning/error messages
- Troubleshooting information

## Security Considerations

### Client Secret Storage

✅ **AUTOMATED**: The App Registration client secret is automatically stored in Azure Key Vault:
- **Key Vault Name**: `kvneodeploy<org><env><region><index>`
- **Secret Name**: `neologik-deployment-service-principle-secret`
- **Access**: Available to Neologik Admin User Group members via RBAC

You do NOT need to manually copy or store the secret. It's displayed during script execution for informational purposes only.

### Certificate Storage

The Storage Account uses **Microsoft Entra ID authentication only**:
- ✅ Shared key access is **disabled**
- ✅ Access controlled via RBAC (Storage Blob Data Contributor)
- ✅ All operations require Entra ID authentication

### Permissions Required

The script requires elevated permissions:
- **Administrator** access on local machine (for module installation)
- **Subscription Owner** role (for resource creation and RBAC)
- **Global Administrator** role (for Entra ID operations)

### Best Practices

- ✅ Run the script from a secure, trusted machine
- ✅ Review all prompts before confirming
- ✅ Store output files securely
- ✅ Audit the log file for any issues
- ✅ All secrets are stored in Key Vault, not in local files

## Troubleshooting

### PowerShell Version Issues

**Problem**: Script fails with version error

**Solution**: 
```powershell
# Let script update automatically, or manually install:
winget install Microsoft.PowerShell
```

### Module Installation Fails

**Problem**: Cannot install required modules

**Solution**:
```powershell
# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Manually install modules
Install-Module -Name Az -Scope CurrentUser -Force
Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force
```

### Authentication Fails

**Problem**: Cannot connect to Azure

**Solution**:
1. Ensure you have an active internet connection
2. Verify your Azure credentials
3. Check that your account has required permissions
4. Try clearing Azure credential cache:
   ```powershell
   Clear-AzContext -Force
   ```

### Permission Errors

**Problem**: "Insufficient privileges" or "Access denied"

**Solution**:
1. Verify you have **Subscription Owner** role
2. Verify you have **Global Administrator** role in Entra ID
3. Check role assignments in Azure Portal
4. Contact your Azure administrator if needed

### Guest User Invitation Fails

**Problem**: Cannot invite external users

**Solution**:
1. Check External Collaboration Settings in Entra ID
2. Ensure guest invitations are allowed
3. Verify email addresses are correct
4. Check spam folder for invitation emails

### Role Assignment Fails with "BadRequest"

**Problem**: Script shows "BadRequest" errors when assigning roles

**Solution**:
- **Automatic**: The script includes retry logic (up to 5 attempts with 10-second delays)
- This is normal for newly created principals (Service Principals, Security Groups, Managed Identities)
- Azure AD/Entra ID needs time to replicate resources across regions
- The script will automatically retry and succeed after replication completes
- No action needed - just wait for the retries to complete

### Re-authentication Needed

**Problem**: Need to switch Azure accounts during setup

**Solution**:
1. When prompted "Do you want to re-authenticate to Azure?", press **Y**
2. Sign in with the correct Azure account
3. Ensure the new account has required permissions

### Resource Already Exists

**Problem**: Script reports resource already exists

**Solution**: The script is designed to handle existing resources gracefully. It will:
- Skip creation if resource exists
- Validate existing configuration
- Only create missing components

This is normal and allows for re-running the script safely.

### Resource Provider Registration Timeout

**Problem**: "Resource provider registration failed" or timeout message

**Solution**:
1. Wait 5 minutes as instructed in the error message
2. Run the script again - it will resume and check registration status
3. The script automatically retries registration with 20 attempts

Resource provider registration can sometimes take time in Azure.

## What to Share with Neologik

After successful completion, share the following with Neologik:

### 1. Configuration File

Send the generated `NeologikConfiguration_<timestamp>.json` file to support@neologik.ai

### 2. Azure Access

Grant Neologik team access to:
- **Key Vault**: Access to retrieve the service principal secret
- **Storage Account**: Access to retrieve the TLS certificate

The invited Neologik team members are automatically added to the appropriate security groups with necessary permissions.

### 3. Post-Script Manual Steps

Complete these steps in the Azure Portal:

#### Upload TLS Certificate
1. Navigate to Storage Account: `stneodeploy<org><env><region><index>`
2. Go to Containers → `certificate`
3. Upload your TLS certificate (.pfx file)
4. Use **Microsoft Entra ID** authentication (not access key)

#### Store Certificate Password
1. Navigate to Key Vault: `kvneodeploy<org><env><region><index>`
2. Go to Secrets
3. Create new secret:
   - **Name**: `neologik-deployment-certificate-pfx-secret`
   - **Value**: Your certificate PFX password

### 4. Certificate Requirements

The TLS certificate (PFX) must contain:
- Server certificate
- Full certificate chain (intermediate CAs)
- Root CA certificate
- Private key

## Post-Installation Steps

After running the script:

1. ✅ **Review** the configuration file
2. ✅ **Upload** TLS certificate to Storage Account (see manual steps above)
3. ✅ **Store** certificate password in Key Vault (see manual steps above)
4. ✅ **Share** configuration file with Neologik team
5. ✅ **Verify** guest users received invitations
6. ✅ **Keep** log file for troubleshooting

All secrets are securely stored in Azure Key Vault - no manual secret management required!

## Support

### Neologik Support

For issues specific to Neologik platform:
- Contact: support@neologik.ai
- Documentation: [Neologik Documentation]

### Script Issues

For issues with this onboarding script:
- Check the log file first
- Review troubleshooting section
- Contact Neologik team for assistance

## Version History

### Version 1.0.0
- Initial release
- Automated onboarding for Neologik customers
- PowerShell 7.4+ support
- Complete Azure resource provisioning
- Comprehensive logging and error handling

## License

Copyright © 2024 Neologik. All rights reserved.

This script is provided for Neologik customer onboarding purposes only.

## Contributing

This is a Neologik internal repository. For suggestions or improvements, contact the Neologik development team.

---

**Neologik AI** - Intelligent Solutions for Modern Enterprises
