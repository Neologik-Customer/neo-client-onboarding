# Pre-Onboarding Checklist

**Before running** `Install-NeologikEnvironment.ps1`, ensure you have gathered all the required information listed below.

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

- [ ] **Azure Region** (where resources will be created)
  - Must be a valid Azure region name
  - Common options:
    - UK: `uksouth`, `ukwest`
    - Europe: `northeurope`, `westeurope`, `switzerlandnorth`
    - US: `eastus`, `eastus2`, `westus`, `westus2`
    - Other: `australiaeast`, `southeastasia`, `japaneast`
  - Default: "uksouth"
  - Will be automatically converted to lowercase

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