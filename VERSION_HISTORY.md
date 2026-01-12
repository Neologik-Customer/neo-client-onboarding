# Neo Client Onboarding Scripts Version History

This document tracks the version history of the Neologik customer onboarding scripts deployed from the main branch, including significant changes, dependencies, and infrastructure requirements.

**Version Format**: `MAJOR.MINOR.PATCH` (currently: `1.7.x`)
- Major version: 1
- Minor version: 7
- Patch number: Incremented with each release

---

## Version 1.8.0
**Built**: January 12, 2026  
**Git Tag**: v1.8.0

### Major Changes
- **External Guest User Management** - Guest user emails moved to external configuration file
- **Enhanced Configuration Collection** - Added hostname and domain name capture
- **Multi-Bot Support** - Support for configuring 1-10 bots with dedicated user groups
- **Input Normalization** - Automatic lowercase conversion for key configuration values

### Features Added
- `NeologikGuestUsers.txt` file for managing guest user email addresses
  - One email per line
  - Support for comments (lines starting with #)
  - Blank lines ignored
- Hostname and domain name collection during configuration
- Bot count selection (1-10 bots)
- Per-bot configuration:
  - Agent Name: Used in security group names (e.g., "Neologik User Group bot - abc-dev")
  - Short Name: Internal identifier for the bot
- Automatic lowercase conversion for:
  - Organization code
  - Hostname
  - Domain name
  - Environment type
  - Azure region
- Enhanced input validation:
  - Agent name: lowercase, max 7 characters, letters and dashes only
  - Short name: lowercase, max 7 characters, letters and dashes only
  - Duplicate name detection for both agent and short names

### Infrastructure Changes
- **Entra ID (Azure AD)**:
  - Security groups created per bot (one user group per bot)
  - Group naming: `Neologik User Group <agent-name> - {org}-{env}`
  - Example: `Neologik User Group bot - abc-dev`, `Neologik User Group support - abc-dev`
  
- **Configuration Output**:
  - Added `OrganizationName`, `Hostname`, `DomainName` to JSON output
  - Added `BotCount` and `Bots` array with `AgentName` and `ShortName` properties
  
### Dependencies
- **Guest User File**: `NeologikGuestUsers.txt` must be present in script directory
- **No breaking changes** to Azure resources or permissions
- **Backward compatible** with existing deployments (new fields are additions only)

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Multi-bot support, external guest users, input normalization
- New: [NeologikGuestUsers.txt](NeologikGuestUsers.txt) - Guest user email configuration
- Modified: [README.md](README.md) - Updated documentation for new features
- Modified: [QUICK-REFERENCE.md](QUICK-REFERENCE.md) - Updated for multi-bot groups
- Modified: [TECHNICAL-REFERENCE.md](TECHNICAL-REFERENCE.md) - Comprehensive feature documentation
- New: [VERSION_HISTORY.md](VERSION_HISTORY.md) - This file

### Breaking Changes
- None (backward compatible)

---

## Version 1.7.5
**Built**: November 17, 2025  
**Git Tag**: v1.7.5

### Major Changes
- **Resource Provider Registration Enhancement** - Added Microsoft.Compute provider registration before storage account creation

### Features Added
- Dedicated Microsoft.Compute resource provider registration step
- Improved resource provider management with dedicated section
- Enhanced logging for resource provider operations

### Bug Fixes
- Fixed storage account creation failures due to unregistered Microsoft.Compute provider
- Improved error messages for resource provider registration

### Infrastructure Changes
- **Azure Resource Providers**:
  - Microsoft.Compute: Now explicitly registered before storage account creation
  - Microsoft.Storage: Registered before storage account operations
  - Microsoft.KeyVault: Registered before Key Vault operations
  - Microsoft.ManagedIdentity: Registered before managed identity creation
  - Microsoft.Resources: Registered before resource group operations
  
### Dependencies
- **Azure Subscription**: Requires permissions to register resource providers
- **No breaking changes** to existing resources

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Resource provider registration enhancements
- Modified: [TECHNICAL-REFERENCE.md](TECHNICAL-REFERENCE.md) - Updated to v1.7.5

---

## Version 1.7.3
**Built**: November 17, 2025  
**Git Tag**: v1.7.3

### Major Changes
- **Microsoft Graph API Compatibility** - Fixed unsupported query operations

### Bug Fixes
- Fixed `Request_UnsupportedQuery` error when querying directory roles
- Removed unsupported `-Filter` parameters from directory role queries
- Implemented manual filtering using `Where-Object` for Graph API compatibility

### Infrastructure Changes
- **No Azure resource changes**
- **API Compatibility**: Updated to work with Microsoft Graph API limitations

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Graph API query fixes

---

## Version 1.7.2
**Built**: November 17, 2025  
**Git Tag**: v1.7.2

### Major Changes
- **Enhanced Error Reporting** - Show actual error messages instead of generic permission errors

### Features Added
- Detailed error messages for Application Administrator role assignment failures
- Improved diagnostics for troubleshooting permission issues
- Better error context in log files

### Bug Fixes
- Fixed misleading "insufficient permissions" messages
- Improved error logging for role assignment operations

### Infrastructure Changes
- **No Azure resource changes**
- **Improved observability** for deployment troubleshooting

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Error reporting improvements

---

## Version 1.7.1
**Built**: November 17, 2025  
**Git Tag**: v1.7.1

### Major Changes
- **Azure AD Replication Handling** - Improved handling of replication delays

### Bug Fixes
- Restored SilentlyContinue error handling for Application Administrator role operations
- Fixed script failures due to Azure AD replication delays
- Graceful handling of resources that haven't replicated yet

### Infrastructure Changes
- **No Azure resource changes**
- **Improved reliability** when dealing with newly created Azure AD resources

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Replication delay handling

---

## Version 1.7.0
**Built**: November 17, 2025  
**Git Tag**: v1.7.0

### Major Changes
- **Service Principal Group Membership Fix** - Fixed group membership checks for newly created service principals

### Bug Fixes
- Fixed service principal group membership verification
- Used SilentlyContinue for group membership checks to handle replication delays
- Prevented false failures when checking group memberships

### Infrastructure Changes
- **No Azure resource changes**
- **Improved reliability** for service principal operations

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Group membership check fixes

---

## Version 1.6.9
**Built**: November 17, 2025  
**Git Tag**: v1.6.9

### Major Changes
- **Guest User Handling Rollback** - Restored working guest invitation pattern

### Bug Fixes
- Rolled back to proven guest invitation and group membership code
- Fixed guest user addition failures
- Restored reliable pattern from v1.4.1

### Infrastructure Changes
- **No Azure resource changes**
- **Restored stability** for guest user operations

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Guest user handling rollback

---

## Version 1.6.8
**Built**: November 17, 2025  
**Git Tag**: v1.6.8

### Major Changes
- **User Type Logging** - Added logging to distinguish member users from guest users

### Features Added
- UserType property logging for better diagnostics
- Improved visibility into member vs. guest user processing

### Infrastructure Changes
- **No Azure resource changes**
- **Enhanced logging** for user operations

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - User type logging

---

## Version 1.6.7
**Built**: November 17, 2025  
**Git Tag**: v1.6.7

### Major Changes
- **Logging Improvements** - Fixed duplicate warning prefixes and adjusted replication delays

### Bug Fixes
- Fixed double "WARNING:" prefix in log messages
- Increased Azure AD replication delay tolerance
- Improved log message formatting

### Infrastructure Changes
- **No Azure resource changes**
- **Improved logging** quality and readability

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Logging improvements

---

## Version 1.6.6
**Built**: November 17, 2025  
**Git Tag**: v1.6.6

### Major Changes
- **Azure AD Replication Delay Handling** - Graceful handling of newly created groups

### Bug Fixes
- Fixed 404 errors when accessing newly created groups
- Implemented retry logic for group operations
- Better handling of Azure AD replication delays

### Infrastructure Changes
- **No Azure resource changes**
- **Improved reliability** for group operations

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Replication delay handling

---

## Version 1.6.5
**Built**: November 17, 2025  
**Git Tag**: v1.6.5

### Major Changes
- **Guest User Error Handling** - Graceful handling of non-existent guest users

### Bug Fixes
- Handle guest users that don't exist in tenant gracefully
- Prevent script failure when guest user lookup fails
- Improved error handling for user operations

### Infrastructure Changes
- **No Azure resource changes**
- **Improved robustness** for guest user processing

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Guest user error handling

---

## Version 1.4.2
**Built**: November 17, 2025  
**Git Tag**: v1.4.2

### Major Changes
- **Git Sync Configuration Fix** - Fixed remote configuration for customer repository synchronization

### Bug Fixes
- Fixed git remote configuration in sync workflow
- Improved repository synchronization reliability

### Infrastructure Changes
- **GitHub Actions**: Updated sync workflow configuration
- **No Azure resource changes**

### Files Changed
- Modified: [.github/workflows/sync-to-customer-repo.yml](.github/workflows/sync-to-customer-repo.yml) - Git remote fixes

---

## Version 1.4.1
**Built**: November 17, 2025  
**Git Tag**: v1.4.1

### Major Changes
- **Terms and Conditions URLs** - Added links to Neologik's Terms of Use and Privacy Policy

### Features Added
- Terms of Use URL: https://www.neologik.ai/terms-of-use
- Privacy Policy URL: https://www.neologik.ai/privacy-policy
- User must review both documents before proceeding

### Infrastructure Changes
- **No Azure resource changes**
- **Enhanced compliance** with legal requirements

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Terms and conditions URLs

---

## Version 1.4.0
**Built**: November 17, 2025  
**Git Tag**: v1.4.0

### Major Changes
- **Terms and Conditions Acceptance** - Added mandatory acceptance of terms before installation

### Features Added
- Terms and conditions acceptance prompt
- User must type "I ACCEPT" to proceed with installation
- Script exits if terms are not accepted

### Infrastructure Changes
- **No Azure resource changes**
- **Compliance feature** for legal requirements

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Terms acceptance

---

## Version 1.2.3
**Built**: November 15, 2025  
**Git Tag**: v1.2.3

### Major Changes
- **Auto-Tagging Enhancement** - Updated sync workflow to automatically tag on release commits

### Features Added
- Automatic git tag creation on release commits
- Improved version tracking in customer repository

### Infrastructure Changes
- **GitHub Actions**: Enhanced sync workflow with auto-tagging
- **No Azure resource changes**

### Files Changed
- Modified: [.github/workflows/sync-to-customer-repo.yml](.github/workflows/sync-to-customer-repo.yml) - Auto-tagging

---

## Version 1.0.0
**Built**: November 15, 2025  
**Git Tag**: v1.0.0

### Major Changes
- **Initial Release** - First stable version of automated onboarding scripts

### Features Added
- PowerShell 7.4+ validation and auto-update
- Azure module dependency management
- Guest user invitation system (hardcoded list)
- Resource group creation
- Security group management
- App Registration (Service Principal) with secret storage
- Key Vault setup with RBAC
- Storage Account for certificate storage
- Managed Identity creation and configuration
- Role assignments (Contributor, User Access Administrator, Application Administrator)
- Comprehensive logging and error handling
- JSON configuration export

### Infrastructure Changes
- **Azure Resources Created**:
  - Resource Group: `rg-neo-{org}-{env}-{region}-{index}`
  - Key Vault: `kvneodeploy{org}{env}{region}{index}`
  - Storage Account: `stneodeploy{org}{env}{region}{index}`
  - Container: `certificate` (in storage account)
  - 3 Security Groups (User, NCE User, Admin)
  - 2 Managed Identities (Script Runner, SQL)
  - 1 App Registration (GitHub Service Connection)
  
- **Permissions Required**:
  - Owner role at subscription level
  - Global Administrator role in Entra ID

### Files Included
- [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Main installation script
- [README.md](README.md) - User guide
- [QUICK-REFERENCE.md](QUICK-REFERENCE.md) - Quick reference for IT/Security review
- [TECHNICAL-REFERENCE.md](TECHNICAL-REFERENCE.md) - Detailed technical documentation
- [PFX-CERT-GUIDE.md](PFX-CERT-GUIDE.md) - Certificate creation guide
- [FINISHING-STEPS-GUIDE.md](FINISHING-STEPS-GUIDE.md) - Post-deployment steps
- [LICENSE](LICENSE) - Apache 2.0 license

---

## Dependencies Reference

### Workload Dependencies
This script prepares the Azure environment for Neologik workload deployments. The following workloads depend on resources created by this script:

- **Neologik Bot Application**
  - Requires: Security groups created by this script
  - Requires: Key Vault for secrets
  - Requires: Storage Account for certificate
  - Uses: Managed identities for authentication

- **Neologik Admin Tool**
  - Requires: Security groups (Admin User Group)
  - Requires: Proper role assignments at resource group level

- **GitHub Actions Deployments**
  - Requires: Service Principal (App Registration) created by this script
  - Requires: Client secret stored in Key Vault
  - Requires: Contributor and User Access Administrator roles

### Infrastructure Dependencies

#### Azure Resources
- **Azure Subscription**
  - Active subscription with available quota
  - Owner role assignment required
  
- **Entra ID (Azure AD)**
  - Active tenant
  - Global Administrator role required
  - Guest user invitation capability enabled
  
- **Resource Group**
  - Naming: `rg-neo-{org}-{env}-{region}-{index}`
  - Location: User-specified Azure region
  
- **Key Vault**
  - Name: `kvneodeploy{org}{env}{region}{index}` (24 char max)
  - RBAC authorization enabled
  - Stores: Service principal secrets, certificate passwords
  - Access: Key Vault Secrets Officer role to Admin User Group
  
- **Storage Account**
  - Name: `stneodeploy{org}{env}{region}{index}` (24 char max)
  - Authentication: Microsoft Entra ID only (no shared keys)
  - Container: `certificate` (for TLS/SSL certificates)
  - Access: Storage Blob Data Contributor to Admin User Group
  
- **Security Groups** (Entra ID)
  - Per-bot user groups: `Neologik User Group <agent-name> - {org}-{env}` (v1.8.0+)
  - Legacy single user group: `Neologik User Group - {org}-{env}` (v1.0.0-v1.7.x)
  - NCE User Group: `Neologik NCE User Group - {org}-{env}`
  - Admin User Group: `Neologik Admin User Group - {org}-{env}`
  - Members: Logged-in user + Neologik guest users
  
- **App Registration** (Service Principal)
  - Name: `Neologik GitHub Service Connection - {org}-{env}`
  - Type: Multi-tenant
  - Secret: 365-day expiration, stored in Key Vault
  - Roles: Contributor, User Access Administrator (Subscription)
  - Entra Role: Application Administrator
  
- **Managed Identities**
  - Script Runner: `neologik-script-runner-service-connection-{org}-{env}`
  - SQL Identity: `neologik-sql-managed-identity-{org}-{env}`

#### Permissions Required

**Subscription Level**:
- Owner role (for RBAC assignments)

**Entra ID (Azure AD)**:
- Global Administrator role (for directory role assignments and guest invitations)
- OR Privileged Role Administrator (minimum for Application Administrator assignment)

#### Resource Providers
The script automatically registers these providers:
- Microsoft.Resources
- Microsoft.KeyVault
- Microsoft.Storage
- Microsoft.Compute (v1.7.5+)
- Microsoft.ManagedIdentity

---

## Version Numbering

- **Major** (1): Breaking changes, major architecture changes
- **Minor** (7): New features, backwards-compatible changes
- **Patch** (x): Bug fixes, minor improvements

---

## Maintenance Guidelines

### Updating This File
When creating a new release from main:

1. **Create new version section** at the top of the document
2. **Include**: Version number, build date, git tag
3. **Document changes**:
   - Major features and enhancements
   - Bug fixes
   - Breaking changes
   - Infrastructure changes (Azure resources, permissions, etc.)
   - Configuration file changes
   - Security group naming changes
4. **List dependencies**:
   - Changes to Azure resources
   - Permission requirement changes
   - External file dependencies (like NeologikGuestUsers.txt)
5. **Reference file changes**: Use relative links to modified files

### Tagging Releases
- Create git tags in format: `v{MAJOR}.{MINOR}.{PATCH}` (e.g., v1.8.0)
- Tag from main branch only
- Include version in commit message: `release v1.8.0 - Description`

### Breaking Changes
Mark breaking changes clearly and include migration guidance:
- Changes to security group naming
- Changes to required permissions
- Changes to configuration file format
- Changes to resource naming conventions

---

## Support & Contact

For questions about specific versions or deployment requirements:
- Email: support@neologik.ai
- Include: Version number, log file, configuration JSON file

**Last Updated**: January 12, 2026
