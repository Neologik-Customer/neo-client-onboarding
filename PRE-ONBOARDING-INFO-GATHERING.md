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

- [ ] **Hostname** (server/computer name)
  - Example: "server01", "web-server", "app-host"
  - Will be automatically converted to lowercase
  - **Required** - cannot be empty

- [ ] **Domain Name**
  - Example: "contoso.com", "example.local", "yourcompany.com"
  - Will be automatically converted to lowercase
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

### 6. Bot Configuration

- [ ] **Bot Count**
  - How many bots will be deployed? (1-10)
  - Default: 1
  - Used to create separate user groups for each bot

For **each bot**, prepare:

- [ ] **Full Bot Name** (descriptive name)
  - Example: "bot", "RAMS Agent", "Customer Service Bot"
  - Letters (upper or lower case), numbers, spaces, dashes and underscores
  - No length limit
  - Used in security group names

- [ ] **Short Name** (short identifier)
  - Example: "bot", "sup", "rams"
  - Lowercase
  - 1–4 characters
  - Must start with a letter, letters/numbers/dashes only
  - Used internally for identification

- [ ] **Authentication type** (select "anonymous" or "Teams")
  - Select "anonymous" to use in public web chats that do not require login
  - Select "Teams" to use as an app that is integrated into your Teams workspace

---