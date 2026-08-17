# Pre-Onboarding Checklist

**Before running** `Install-NeologikEnvironment.ps1`, ensure you have gathered all the required information listed below.

---

## 📋 Information to Gather

Before running the script, prepare the following information. You will be prompted for these during script execution:

### 1. Deployment Type

- [ ] **Deployment Type**
  - Options: `neo-small` or `neo-secure`
  - Choose the appropriate deployment configuration
  - **Required** - cannot be empty

### 2. Organization Information

- [ ] **Organization Name** (full company name)
  - Example: "Contoso Ltd", "Acme Corporation"
  - Used for documentation and identification
  - **Required** - cannot be empty

- [ ] **Organization Code** (3-character identifier)
  - Example: "ABC", "sec", "xyz"
  - Must be **exactly 3 characters**
  - Only letters and numbers allowed
  - Will be automatically converted to lowercase
  - Default: "abc"

### 3. Environment Configuration

- [ ] **Environment Type**
  - Options: `dev` (development) or `prd` (production)
  - Will be automatically converted to lowercase
  - Default: "dev"

- [ ] **Environment Index**
  - Number for this environment: 01, 02, 03, etc.
  - Use "01" for first setup
  - Must be between 01 and 99
  - Default: "01"

### 4. Network Information

- [ ] **Bot Hostname (full FQDN)**
  - Example: "neologik.contoso.com", "xyzprd.neologik.ai"
  - Enter the complete public hostname; any `https://` prefix or trailing path is stripped and it is converted to lowercase
  - **Required** - cannot be empty

### 5. Azure Configuration

- [ ] **Azure Region** (where resources will be created)
  - Must be a valid Azure region name
  - Common options:
    - UK: `uksouth`, `ukwest`
    - Europe: `northeurope`, `westeurope`, `switzerlandnorth`
    - US: `eastus`, `eastus2`, `westus`, `westus2`
    - Other: `australiaeast`, `southeastasia`, `japaneast`
  - Default: "uksouth"
  - Will be automatically converted to lowercase

### 6. Provisioning Decisions

Note: you will **not** be asked about bots or agents - agents and their channels are created after deployment in the Neologik admin tool.

- [ ] **Resource naming** (optional)
  - The script computes Neologik-standard names for everything it creates (resource group, Key Vault, storage account, managed identities) and shows each as a default you can accept with Enter
  - If your organisation mandates its own Azure naming convention, prepare the names in advance (they can also be pre-filled via `inputs.json`) and share the convention with Neologik

- [ ] **Neologik guest invitations** (yes/no)
  - Default: yes - the Neologik team members listed in `NeologikGuestUsers.txt` are invited as B2B guests
  - Choose no if you provision accounts for the Neologik team in your own tenant instead
  - If you choose no, a follow-up question offers to add your pre-created accounts (guests or full members) to the security groups with no invitation sent - prepare their exact email addresses (each must match the account's mail or user principal name); addresses can come from the file or be typed in

- [ ] **Deployment service principal** (create vs. bring your own)
  - Default: the script creates the deployment service principal for you
  - If you prefer to create it yourself, follow [CREATE-SP-GUIDE.md](CREATE-SP-GUIDE.md) and have ready: its **object ID** (the enterprise-application / service-principal object ID, not the client/app ID) and, optionally, its client secret (or add the secret to Key Vault yourself before the first deployment)

---