<#
.SYNOPSIS
    Automated Neologik customer onboarding script for Azure environment setup.

.DESCRIPTION
    This script automates the complete onboarding process for Neologik customers, including:
    - PowerShell version validation and updates
    - Azure authentication with required permissions
    - Role validation (Subscription Owner and Global Administrator)
    - Quota pre-flight checks (vCPU and Azure OpenAI gpt-5.4-mini)
    - Guest user invitations
    - Subscription, resource group, and security group creation
    - App registration and managed identity setup
    - Role assignments
    - Configuration output and logging

.VERSION
    v1.9.0

.PARAMETER OrganizationCode
    3-character organization code (e.g., 'ABC'). Default: 'ORG'

.PARAMETER EnvironmentType
    Environment type: 'dev' or 'prd'. Default: 'dev'

.PARAMETER AzureRegion
    Azure region for resource deployment. Default: 'uksouth'

.PARAMETER TenantId
    Azure Tenant ID. If not provided, will use current context.

.PARAMETER SubscriptionName
    Name for the Azure subscription. Default: 'Neologik-Development-01'

.PARAMETER SkipPowerShellUpdate
    Skip PowerShell version check and update.

.PARAMETER SkipModuleInstall
    Skip Azure module installation check.

.EXAMPLE
    .\Install-NeologikEnvironment.ps1 -OrganizationCode "ABC"

.EXAMPLE
    .\Install-NeologikEnvironment.ps1 -OrganizationCode "XYZ" -EnvironmentType "prd" -AzureRegion "ukwest"

.NOTES
    Author: Neologik
    Version: 1.0.0
    Requires: PowerShell 7.4+ (script will update if needed)
    Requires: Subscription Owner and Global Administrator roles
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateLength(1, 3)]
    [string]$OrganizationCode = "abc",

    [Parameter(Mandatory = $false)]
    [ValidateSet('dev', 'prd')]
    [string]$EnvironmentType = "dev",

    [Parameter(Mandatory = $false)]
    [string]$AzureRegion = "uksouth",

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionName = "Neologik-Development-01",

    [Parameter(Mandatory = $false)]
    [switch]$SkipPowerShellUpdate,

    [Parameter(Mandatory = $false)]
    [switch]$SkipModuleInstall
)

# Script variables
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'

# Script version
$script:Version = 'v1.9.0'

# Initialize with timestamp - will be updated after org code and environment type are collected
$script:FileTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogFile = Join-Path $PSScriptRoot "NeologikOnboarding_$($script:FileTimestamp).log"
$script:OutputFile = Join-Path $PSScriptRoot "NeologikConfiguration_$($script:FileTimestamp).json"
$script:ConfigData = @{}
$script:CompletedSteps = [System.Collections.Generic.List[string]]::new()
$script:ProviderRegistrations = @{}
$script:CheckpointFile = Join-Path $PSScriptRoot "NeologikCheckpoint.json"
$script:CheckpointRegionAbbrev = $null

# Load Neologik guest user emails from file
$script:GuestUsersFile = Join-Path $PSScriptRoot "NeologikGuestUsers.txt"
if (Test-Path $script:GuestUsersFile) {
    $script:NeologikGuestUsers = @(Get-Content $script:GuestUsersFile | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\s*#' })
} else {
    Write-Warning "Guest users file not found at: $script:GuestUsersFile. No guest users will be invited."
    $script:NeologikGuestUsers = @()
}

# Required PowerShell modules
$script:RequiredModules = @(
    @{ Name = 'Az.Accounts'; MinVersion = '3.0.0' },
    @{ Name = 'Az.Resources'; MinVersion = '7.0.0' },
    @{ Name = 'Az.KeyVault'; MinVersion = '5.0.0' },
    @{ Name = 'Az.Storage'; MinVersion = '6.0.0' },
    @{ Name = 'Az.ManagedServiceIdentity'; MinVersion = '1.0.0' },
    @{ Name = 'Microsoft.Graph'; MinVersion = '2.0.0' }
)

#region Logging Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes message to log file and console.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"

    # Write to log file
    try {
        Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to write to log file: $_"
    }

    # Write to console
    switch ($Level) {
        'Info' { Write-Information $Message }
        'Warning' { Write-Warning $Message }
        'Error' { Write-Error $Message }
        'Success' { Write-Host $Message -ForegroundColor Green }
    }
}

function Initialize-ConfigurationFile {
    <#
    .SYNOPSIS
        Initializes the configuration JSON file name with organization code and environment type.
    #>
    [CmdletBinding()]
    param()
    
    # Generate configuration file name with org code and env type
    $configFileName = "Neologik_$($script:OrganizationCode)$($script:EnvironmentType)_Configuration_$($script:FileTimestamp).json"
    $script:OutputFile = Join-Path $PSScriptRoot $configFileName
    
    Write-Host "  ✓ Configuration file initialized: $configFileName" -ForegroundColor Green
    Write-Log "Configuration file path set to: $($script:OutputFile)" -Level Info
}

function Write-ScriptHeader {
    $header = @"

╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║          NEOLOGIK CUSTOMER ONBOARDING SCRIPT                  ║
║          $script:Version                                               ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

"@
    Write-Host $header -ForegroundColor Cyan
    Write-Log "Starting Neologik customer onboarding process (Version: $script:Version)" -Level Info
}

function Show-TermsAndConditions {
    <#
    .SYNOPSIS
        Displays terms and conditions and gets user acceptance.
    #>
    [CmdletBinding()]
    param()

    $terms = @"

═══════════════════════════════════════════════════════════════
                    TERMS AND CONDITIONS
═══════════════════════════════════════════════════════════════

By proceeding with this installation, you acknowledge and agree to

    NEOLOGIK TERMS OF USE AND PRIVACY POLICY

   - Terms of Use: https://www.neologik.ai/terms
   - Privacy Policy: https://www.neologik.ai/privacy-policy
   - You must read and accept both documents to proceed

═══════════════════════════════════════════════════════════════

"@

    Write-Host $terms -ForegroundColor Yellow
    
    Write-Host "Do you accept the Neologik Terms of Use and Privacy Policy? " -NoNewline -ForegroundColor Cyan
    Write-Host "(Type 'I ACCEPT' to continue, or 'N' to exit): " -NoNewline -ForegroundColor Cyan
    $acceptance = Read-Host
    
    if ($acceptance -eq 'I ACCEPT') {
        Write-Log "User accepted terms and conditions" -Level Info
        Write-Host "`n✓ Terms accepted. Proceeding with installation...`n" -ForegroundColor Green
        return $true
    }
    else {
        Write-Log "User declined terms and conditions" -Level Warning
        Write-Host "`n✗ Terms not accepted. Installation cancelled.`n" -ForegroundColor Red
        return $false
    }
}

#endregion

#region Checkpoint Management

function Find-LatestCheckpoint {
    <#
    .SYNOPSIS
        Returns the checkpoint file if it exists in the script directory.
    #>
    if (Test-Path $script:CheckpointFile) { return Get-Item $script:CheckpointFile }
    return $null
}

function Save-Checkpoint {
    <#
    .SYNOPSIS
        Saves current script state to the checkpoint file so the run can be resumed after a failure.
    #>
    [CmdletBinding()]
    param([string]$Label = 'progress')

    if (-not $script:CheckpointFile) { return }

    $state = [ordered]@{
        Version               = $script:Version
        SavedAt               = (Get-Date -Format 'o')
        Label                 = $Label
        CompletedSteps        = @($script:CompletedSteps)
        ProviderRegistrations = $script:ProviderRegistrations
        RegionAbbrev          = $script:CheckpointRegionAbbrev
        ConfigData            = $script:ConfigData
        OrganizationCode      = $script:OrganizationCode
        EnvironmentType       = $script:EnvironmentType
        AzureRegion           = $script:AzureRegion
        OrganizationName      = $script:OrganizationName
        Hostname              = $script:Hostname
        DomainName            = $script:DomainName
        ResourceGroupName     = $script:ResourceGroupName
        EnvironmentIndex      = $script:EnvironmentIndex
        BotCount              = $script:BotCount
        BotConfigurations     = $script:BotConfigurations
        OutputFile            = $script:OutputFile
    }

    try {
        $state | ConvertTo-Json -Depth 10 | Set-Content -Path $script:CheckpointFile -Encoding UTF8
    }
    catch {
        Write-Warning "Could not save checkpoint: $_"
    }
}

function Restore-Checkpoint {
    <#
    .SYNOPSIS
        Restores script state from a checkpoint file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        $data = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "Checkpoint file is corrupt or unreadable: $_"
        Write-Host "`n  ⚠ Could not load checkpoint. Starting a fresh run instead." -ForegroundColor Yellow
        return $false
    }

    # Restore ConfigData as a flat hashtable
    $script:ConfigData = @{}
    foreach ($prop in $data.ConfigData.PSObject.Properties) {
        $script:ConfigData[$prop.Name] = $prop.Value
    }

    # Restore ProviderRegistrations as hashtable
    $script:ProviderRegistrations = @{}
    if ($data.ProviderRegistrations) {
        foreach ($prop in $data.ProviderRegistrations.PSObject.Properties) {
            $script:ProviderRegistrations[$prop.Name] = $prop.Value
        }
    }

    # Restore CompletedSteps
    $script:CompletedSteps = [System.Collections.Generic.List[string]]::new()
    foreach ($step in $data.CompletedSteps) {
        $script:CompletedSteps.Add([string]$step)
    }

    # Restore named script variables
    $script:OrganizationCode       = $data.OrganizationCode
    $script:EnvironmentType        = $data.EnvironmentType
    $script:AzureRegion            = $data.AzureRegion
    $script:OrganizationName       = $data.OrganizationName
    $script:Hostname               = $data.Hostname
    $script:DomainName             = $data.DomainName
    $script:ResourceGroupName      = $data.ResourceGroupName
    $script:EnvironmentIndex       = $data.EnvironmentIndex
    $script:BotCount               = [int]$data.BotCount
    $script:BotConfigurations      = $data.BotConfigurations
    $script:CheckpointRegionAbbrev = $data.RegionAbbrev
    $script:OutputFile             = $data.OutputFile
}

function Complete-OnboardingStep {
    <#
    .SYNOPSIS
        Records a step as completed in the checkpoint.
    #>
    [CmdletBinding()]
    param([string]$StepName)
    if (-not $script:CompletedSteps.Contains($StepName)) {
        $script:CompletedSteps.Add($StepName)
    }
    Save-Checkpoint -Label $StepName
}

#endregion

#region PowerShell Version Management

function Test-PowerShellVersion {
    <#
    .SYNOPSIS
        Checks if PowerShell version meets minimum requirements.
    #>
    [CmdletBinding()]
    param()

    Write-Log "Checking PowerShell version..." -Level Info
    $currentVersion = $PSVersionTable.PSVersion
    $requiredVersion = [Version]"7.4.0"

    Write-Log "Current PowerShell version: $currentVersion" -Level Info

    if ($currentVersion -ge $requiredVersion) {
        Write-Log "PowerShell version meets requirements (>= 7.4.0)" -Level Success
        return $true
    }
    else {
        Write-Log "PowerShell version $currentVersion is below required version $requiredVersion" -Level Warning
        return $false
    }
}

function Install-PowerShellLatest {
    <#
    .SYNOPSIS
        Installs or updates PowerShell to the latest version.
    #>
    [CmdletBinding()]
    param()

    Write-Log "Installing/Updating PowerShell..." -Level Info

    try {
        # Check if winget is available
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        
        if ($winget) {
            Write-Log "Using winget to install/update PowerShell..." -Level Info
            winget install --id Microsoft.PowerShell --source winget --silent --accept-package-agreements --accept-source-agreements | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log "PowerShell has been updated successfully." -Level Success
                Write-Log "Please restart this script in the new PowerShell version." -Level Warning
                Write-Host "`nPlease close this window and run the script again from PowerShell 7.4+`n" -ForegroundColor Yellow
                exit 0
            }
            else {
                throw "winget installation failed with exit code $LASTEXITCODE"
            }
        }
        else {
            # Fallback to MSI download
            Write-Log "winget not found. Downloading PowerShell installer..." -Level Info
            $installerUrl = "https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.6-win-x64.msi"
            $installerPath = Join-Path $env:TEMP "PowerShell-Setup.msi"

            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
            
            Write-Log "Installing PowerShell from MSI..." -Level Info
            Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" /qn /norestart" -Wait -NoNewWindow

            Write-Log "PowerShell has been installed successfully." -Level Success
            Write-Log "Please restart this script in the new PowerShell version." -Level Warning
            Write-Host "`nPlease close this window and run the script again from PowerShell 7.4+`n" -ForegroundColor Yellow
            exit 0
        }
    }
    catch {
        Write-Log "Failed to install/update PowerShell: $_" -Level Error
        throw
    }
}

#endregion

#region Module Management

function Test-RequiredModules {
    <#
    .SYNOPSIS
        Checks if required Azure modules are installed.
    #>
    [CmdletBinding()]
    param()

    Write-Log "Checking required PowerShell modules..." -Level Info
    $missingModules = @()

    foreach ($module in $script:RequiredModules) {
        $installedModule = Get-Module -ListAvailable -Name $module.Name | 
            Where-Object { $_.Version -ge [Version]$module.MinVersion } |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($installedModule) {
            Write-Log "Module $($module.Name) version $($installedModule.Version) is installed" -Level Info
        }
        else {
            Write-Log "Module $($module.Name) (>= $($module.MinVersion)) is not installed" -Level Warning
            $missingModules += $module
        }
    }

    return $missingModules
}

function Install-RequiredModules {
    <#
    .SYNOPSIS
        Installs missing required modules.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Modules
    )

    Write-Log "Installing missing modules..." -Level Info

    # Set PSGallery as trusted
    $psGallery = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue
    if ($psGallery -and $psGallery.InstallationPolicy -ne 'Trusted') {
        Write-Log "Setting PSGallery as trusted repository..." -Level Info
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
    }

    foreach ($module in $Modules) {
        try {
            Write-Log "Installing module: $($module.Name)..." -Level Info
            Install-Module -Name $module.Name -MinimumVersion $module.MinVersion -Scope CurrentUser -Force -AllowClobber
            Write-Log "Module $($module.Name) installed successfully" -Level Success
        }
        catch {
            Write-Log "Failed to install module $($module.Name): $_" -Level Error
            throw
        }
    }
}

#endregion

#region Azure Authentication

function Connect-AzureEnvironment {
    <#
    .SYNOPSIS
        Authenticates to Azure and validates permissions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantId
    )

    Write-Log "Connecting to Azure..." -Level Info

    try {
        # Import required modules
        Import-Module Az.Accounts -ErrorAction Stop
        Import-Module Az.Resources -ErrorAction Stop
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

        # Check if already connected to Azure
        $currentContext = Get-AzContext -ErrorAction SilentlyContinue
        
        # Force re-authentication if requested or if not connected
        if ($script:ForceReAuth -or -not $currentContext -or -not $currentContext.Account) {
            if ($script:ForceReAuth) {
                Write-Log "Force re-authentication requested" -Level Info
            }
            
            # Connect to Azure using device code authentication
            Write-Log "Authenticating to Azure..." -Level Info
            Write-Host "`nℹ️  Using device code authentication for Azure login." -ForegroundColor Cyan
            Write-Host "A code will be displayed. Visit the URL and enter the code to authenticate.`n" -ForegroundColor Cyan
            
            if ($TenantId) {
                $azContext = Connect-AzAccount -TenantId $TenantId -UseDeviceAuthentication -ErrorAction Stop
            }
            else {
                $azContext = Connect-AzAccount -UseDeviceAuthentication -ErrorAction Stop
            }
            Write-Log "Connected to Azure as $($azContext.Context.Account.Id)" -Level Success
        }
        elseif ($currentContext -and $currentContext.Account) {
            Write-Log "Already connected to Azure as $($currentContext.Account.Id)" -Level Info
            
            # If TenantId is specified and different, reconnect
            if ($TenantId -and $currentContext.Tenant.Id -ne $TenantId) {
                Write-Log "Switching to specified tenant: $TenantId" -Level Info
                $azContext = Connect-AzAccount -TenantId $TenantId -UseDeviceAuthentication -ErrorAction Stop
            }
            else {
                $azContext = [PSCustomObject]@{
                    Context = $currentContext
                }
                Write-Log "Using existing Azure connection" -Level Success
            }
        }

        # Store context information
        $script:ConfigData['TenantId'] = $azContext.Context.Tenant.Id
        
        # Try to get tenant name from different sources
        $tenantName = $null
        
        # First, try Get-AzTenant which is most reliable
        try {
            $tenant = Get-AzTenant -TenantId $azContext.Context.Tenant.Id -ErrorAction Stop
            if ($tenant -and $tenant.Name) {
                $tenantName = $tenant.Name
            }
        }
        catch {
            Write-Log "Could not retrieve tenant name from Get-AzTenant" -Level Warning
        }
        
        # Fallback: Try tenant context property
        if (-not $tenantName -and $azContext.Context.Tenant.Directory) {
            $tenantName = $azContext.Context.Tenant.Directory
        }
        
        # Fallback: Extract from HomeAccountId
        if (-not $tenantName -and $azContext.Context.Account.ExtendedProperties.HomeAccountId) {
            # Extract domain from HomeAccountId (format: objectid.tenantid@domain)
            $homeAccountId = $azContext.Context.Account.ExtendedProperties.HomeAccountId
            if ($homeAccountId -match '@(.+)$') {
                $tenantName = $matches[1]
            }
        }
        
        # Fallback: Try Microsoft Graph
        if (-not $tenantName) {
            try {
                $mgOrg = Get-MgOrganization -ErrorAction Stop | Select-Object -First 1
                if ($mgOrg) {
                    $tenantName = if ($mgOrg.DisplayName) { $mgOrg.DisplayName } else { $mgOrg.VerifiedDomains[0].Name }
                }
            }
            catch {
                Write-Log "Could not retrieve tenant name from Microsoft Graph" -Level Warning
            }
        }
        
        $script:ConfigData['TenantName'] = $tenantName
        $script:ConfigData['UserAccount'] = $azContext.Context.Account.Id

        Write-Log "Tenant ID: $($script:ConfigData['TenantId'])" -Level Info
        if ($tenantName) {
            Write-Log "Tenant Name: $tenantName" -Level Info
        }
        Write-Log "User Account: $($script:ConfigData['UserAccount'])" -Level Info

        # Check if already connected to Microsoft Graph
        $mgContext = Get-MgContext -ErrorAction SilentlyContinue
        
        # Force re-authentication if requested
        if ($script:ForceReAuth) {
            if ($mgContext) {
                Write-Log "Force re-authentication: Disconnecting from Microsoft Graph" -Level Info
                Disconnect-MgGraph -ErrorAction SilentlyContinue
                $mgContext = $null
            }
        }
        
        if ($mgContext -and $mgContext.TenantId -eq $script:ConfigData['TenantId'] -and -not $script:ForceReAuth) {
            Write-Log "Already connected to Microsoft Graph for tenant $($mgContext.TenantId)" -Level Info
            Write-Host "`n✓ Microsoft Graph: Using existing connection (Account: $($mgContext.Account))`n" -ForegroundColor Green
        }
        else {
            # Disconnect any existing Graph connection first
            if ($mgContext) {
                Write-Log "Disconnecting from existing Microsoft Graph session (different tenant)" -Level Info
                Disconnect-MgGraph -ErrorAction SilentlyContinue
            }

            # Reuse the existing Azure token for Graph — avoids a second browser prompt
            Write-Log "Connecting to Microsoft Graph via existing Azure token..." -Level Info
            try {
                # Az.Accounts >= 2.17 returns .Token as a SecureString (mandatory in 5.x). Request it
                # explicitly when supported; older versions still hand back a plain JWT string.
                if ((Get-Command Get-AzAccessToken).Parameters.ContainsKey('AsSecureString')) {
                    $graphToken = (Get-AzAccessToken -ResourceTypeName MSGraph -TenantId $script:ConfigData['TenantId'] -AsSecureString -ErrorAction Stop).Token
                }
                else {
                    $graphToken = (Get-AzAccessToken -ResourceTypeName MSGraph -TenantId $script:ConfigData['TenantId'] -ErrorAction Stop).Token
                }
                # Microsoft.Graph 2.x requires -AccessToken as a SecureString. If Az already gave us one,
                # pass it through — wrapping it again coerces it to the literal "System.Security.SecureString"
                # and yields a garbage token (Graph 401 IDX14102 on the first call).
                if ($graphToken -is [System.Security.SecureString]) {
                    $secureGraphToken = $graphToken
                }
                else {
                    $secureGraphToken = ConvertTo-SecureString -String $graphToken -AsPlainText -Force
                }
                Connect-MgGraph -AccessToken $secureGraphToken -ErrorAction Stop
                Write-Log "Connected to Microsoft Graph using Azure session token" -Level Success
            }
            catch {
                Write-Log "Azure token insufficient for Graph (consent may be required) — falling back to interactive login: $_" -Level Warning
                Write-Host "`nℹ️  A browser window will open for Microsoft Graph login.`n" -ForegroundColor Cyan
                Connect-MgGraph -TenantId $script:ConfigData['TenantId'] `
                    -Scopes "User.ReadWrite.All", "User.Invite.All", "Group.ReadWrite.All", "Application.ReadWrite.All", "Directory.ReadWrite.All", "RoleManagement.ReadWrite.Directory" `
                    -ErrorAction Stop
                Write-Log "Connected to Microsoft Graph via interactive login" -Level Success
            }
        }

        # Get the actual user ID from Azure AD (works for both member and guest users)
        # Use the UserAccount from Azure context
        $userIdentifier = $script:ConfigData['UserAccount']
        
        if ($userIdentifier) {
            try {
                Write-Log "Attempting to retrieve user ID for: $userIdentifier" -Level Info
                
                # Try Azure AD first (more reliable, uses ARM authentication)
                $currentAzUser = Get-AzADUser -UserPrincipalName $userIdentifier -ErrorAction SilentlyContinue
                
                if (-not $currentAzUser) {
                    # Fallback: Try by mail address for guest users
                    $currentAzUser = Get-AzADUser -Mail $userIdentifier -ErrorAction SilentlyContinue
                }
                
                if ($currentAzUser) {
                    $script:ConfigData['CurrentUserId'] = $currentAzUser.Id
                    Write-Log "Current User ID retrieved successfully: $($script:ConfigData['CurrentUserId'])" -Level Success
                }
                else {
                    Write-Log "Could not retrieve user ID (this is normal for some guest users)" -Level Warning
                    Write-Log "The logged-in user will not be automatically added to security groups, but guest users are already added by email." -Level Info
                }
            }
            catch {
                Write-Log "Could not retrieve user ID: $($_.Exception.Message)" -Level Warning
                Write-Log "The logged-in user will not be automatically added to security groups, but guest users are already added by email." -Level Info
            }
        }
        else {
            Write-Log "WARNING: UserAccount not found in ConfigData" -Level Warning
        }

        return $azContext
    }
    catch {
        Write-Log "Failed to connect to Azure: $_" -Level Error
        throw
    }
}

function Test-RequiredPermissions {
    <#
    .SYNOPSIS
        Validates that the user has required permissions (Subscription Owner and Global Admin).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    Write-Log "Validating user permissions..." -Level Info

    try {
        # Import Microsoft.Graph modules
        Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop

        # Get the current user account
        $userAccount = $script:ConfigData['UserAccount']
        
        if ([string]::IsNullOrWhiteSpace($userAccount)) {
            throw "User account information is missing. Please ensure Azure authentication completed successfully."
        }

        Write-Log "Checking permissions for user: $userAccount" -Level Info

        # Check Subscription Owner role
        Write-Log "Checking Subscription Owner role..." -Level Info
        
        # Try with SignInName first, then fall back to ObjectId
        try {
            $roleAssignments = Get-AzRoleAssignment -Scope "/subscriptions/$SubscriptionId" -SignInName $userAccount -ErrorAction Stop
        }
        catch {
            Write-Log "Trying alternative method to get role assignments..." -Level Info
            # Get current user's object ID from Graph
            $currentUser = Get-MgUser -UserId $userAccount -ErrorAction Stop
            $roleAssignments = Get-AzRoleAssignment -Scope "/subscriptions/$SubscriptionId" -ObjectId $currentUser.Id -ErrorAction Stop
        }
        
        $isOwner = $roleAssignments | Where-Object { $_.RoleDefinitionName -eq 'Owner' }

        if ($isOwner) {
            Write-Log "User has Owner role on subscription" -Level Success
        }
        else {
            throw "User does not have Owner role on the subscription. Owner role is required."
        }

        # Check Global Administrator role
        Write-Log "Checking Global Administrator role..." -Level Info

        $isGlobalAdmin = $false
        $globalAdminConfirmed = $true
        try {
            $userId = (Get-MgUser -UserId $script:ConfigData['UserAccount']).Id
            $globalAdminRole = Get-MgDirectoryRole -Filter "displayName eq 'Global Administrator'"

            if (-not $globalAdminRole) {
                # Activate the role template if not activated
                $roleTemplate = Get-MgDirectoryRoleTemplate -Filter "displayName eq 'Global Administrator'"
                $globalAdminRole = New-MgDirectoryRole -RoleTemplateId $roleTemplate.Id
            }

            $adminMembers = Get-MgDirectoryRoleMember -DirectoryRoleId $globalAdminRole.Id
            $isGlobalAdmin = [bool]($adminMembers | Where-Object { $_.Id -eq $userId })
        }
        catch {
            # The check itself failed (e.g. a Graph token/permission issue such as IDX14102) —
            # we cannot confirm the role either way, so treat it as unconfirmed rather than fatal.
            $globalAdminConfirmed = $false
            Write-Log "Unable to verify Global Administrator role: $_" -Level Warning
        }

        if ($isGlobalAdmin) {
            Write-Log "User has Global Administrator role" -Level Success
        }
        elseif ($globalAdminConfirmed) {
            # The check ran successfully and the user is definitively not a member — fail hard.
            throw "User does not have Global Administrator role. Global Administrator role is required."
        }
        else {
            # The check could not complete (e.g. a Graph token/permission error such as IDX14102),
            # so membership is genuinely unknown — let the operator decide whether to continue.
            Write-Host ""
            Write-Host "⚠️  Unable to verify the Global Administrator role for $userAccount (the check failed to run)." -ForegroundColor Yellow
            Write-Host "    Global Administrator is required for app registration, admin consent, and guest invitations." -ForegroundColor Yellow
            Write-Host "    Continuing without confirming it may cause later steps to fail." -ForegroundColor Yellow
            $proceed = Read-Host "Proceed anyway? [Y/n]"
            if ($proceed -match '^\s*(n|no)\s*$') {
                throw "Global Administrator role could not be verified and the operator chose not to continue."
            }
            Write-Log "Operator chose to proceed without a verified Global Administrator role." -Level Warning
        }

        Write-Log "All required permissions validated successfully" -Level Success
        return $true
    }
    catch {
        Write-Log "Permission validation failed: $_" -Level Error
        throw
    }
}

function Test-QuotaRequirements {
    <#
    .SYNOPSIS
        Checks vCPU and Azure OpenAI gpt-5.4-mini quota availability for the target region.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                                                               ║" -ForegroundColor Cyan
    Write-Host "║                  QUOTA PRE-FLIGHT CHECKS                      ║" -ForegroundColor Cyan
    Write-Host "║                                                               ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Log "Checking quota requirements for region: $Location" -Level Info

    $quotaIssues = @()

    # vCPU quota — Standard D2ds v6 / Standard DC2ds v6
    Write-Host "  Checking vCPU quota (Standard D2ds v6 / Standard DC2ds v6)..." -ForegroundColor Gray
    try {
        $vmUsages = Get-AzVMUsage -Location $Location -ErrorAction Stop

        $ddsv6   = $vmUsages | Where-Object { $_.Name.Value -like '*DDSv6*'   -or $_.Name.LocalizedValue -like '*DDSv6*' }
        $dcsdsv6 = $vmUsages | Where-Object { $_.Name.Value -like '*DCDSv6*'  -or $_.Name.LocalizedValue -like '*DCDSv6*' }

        $checkedAny = $false
        foreach ($quota in @($ddsv6, $dcsdsv6)) {
            if (-not $quota) { continue }
            $checkedAny = $true
            $available  = $quota.Limit - $quota.CurrentValue
            $label      = $quota.Name.LocalizedValue
            if ($available -gt 0) {
                Write-Host "  ✓ ${label}: $($quota.CurrentValue)/$($quota.Limit) vCPUs used ($available available)" -ForegroundColor Green
                Write-Log "${label} quota: $($quota.CurrentValue)/$($quota.Limit) ($available available)" -Level Info
            }
            else {
                Write-Host "  ✗ ${label}: $($quota.CurrentValue)/$($quota.Limit) vCPUs used (none available)" -ForegroundColor Red
                Write-Log "${label} quota exhausted: $($quota.CurrentValue)/$($quota.Limit)" -Level Warning
                $quotaIssues += "vCPU quota for ${label} is at its limit in ${Location} — a quota increase request is required"
            }
        }

        if (-not $checkedAny) {
            Write-Host "  ⚠ Standard DDSv6 / DCDSv6 quota not found in ${Location} — VM series may not be available here" -ForegroundColor Yellow
            Write-Log "Standard DDSv6/DCDSv6 quota not found in region: $Location" -Level Warning
            $quotaIssues += "Standard D2ds v6 / Standard DC2ds v6 quota was not found in ${Location} — confirm this VM series is available in this region"
        }
    }
    catch {
        Write-Host "  ⚠ Could not check vCPU quota: $_" -ForegroundColor Yellow
        Write-Log "vCPU quota check failed: $_" -Level Warning
    }

    # Azure OpenAI quota — gpt-5.4-mini
    Write-Host "  Checking Azure OpenAI gpt-5.4-mini quota..." -ForegroundColor Gray
    try {
        $uri      = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.CognitiveServices/locations/$Location/usages?api-version=2024-10-01"
        $response = Invoke-AzRestMethod -Uri $uri -Method GET -ErrorAction Stop

        if ($response.StatusCode -eq 200) {
            $usages       = ($response.Content | ConvertFrom-Json).value
            $openAiQuotas = $usages | Where-Object { $_.name.value -like '*gpt-5.4-mini*' }

            if ($openAiQuotas) {
                foreach ($q in $openAiQuotas) {
                    $available = $q.limit - $q.currentValue
                    $label     = $q.name.localizedValue
                    if ($available -gt 0) {
                        Write-Host "  ✓ ${label}: $($q.currentValue)/$($q.limit) TPM used ($available available)" -ForegroundColor Green
                        Write-Log "OpenAI gpt-5.4-mini quota: $($q.currentValue)/$($q.limit) TPM used" -Level Info
                    }
                    else {
                        Write-Host "  ✗ ${label}: $($q.currentValue)/$($q.limit) TPM used (none available)" -ForegroundColor Red
                        Write-Log "OpenAI gpt-5.4-mini quota exhausted: $($q.currentValue)/$($q.limit)" -Level Warning
                        $quotaIssues += "Azure OpenAI gpt-5.4-mini quota is exhausted in ${Location} — a quota increase request is required (https://aka.ms/oai/stuquotarequest)"
                    }
                }
            }
            else {
                Write-Host "  ⚠ gpt-5.4-mini quota entry not found in ${Location}" -ForegroundColor Yellow
                Write-Log "gpt-5.4-mini quota not found in region: $Location" -Level Warning
                $quotaIssues += "Azure OpenAI gpt-5.4-mini quota was not found in ${Location} — confirm the model is available here (supported: East US2, Sweden Central, South Central US, Poland Central)"
            }
        }
        else {
            Write-Host "  ⚠ Could not retrieve OpenAI quota (HTTP $($response.StatusCode))" -ForegroundColor Yellow
            Write-Log "OpenAI quota check returned HTTP $($response.StatusCode)" -Level Warning
        }
    }
    catch {
        Write-Host "  ⚠ Could not check Azure OpenAI quota: $_" -ForegroundColor Yellow
        Write-Log "OpenAI quota check failed: $_" -Level Warning
    }

    Write-Host ""

    if ($quotaIssues.Count -gt 0) {
        Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║                                                               ║" -ForegroundColor Yellow
        Write-Host "║                    ⚠  QUOTA WARNING                          ║" -ForegroundColor Yellow
        Write-Host "║                                                               ║" -ForegroundColor Yellow
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  The following quota issues were detected:" -ForegroundColor Yellow
        foreach ($issue in $quotaIssues) {
            Write-Host "  • $issue" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "  Deploying without sufficient quota may cause failures later." -ForegroundColor Gray
        Write-Host "  See QUICK-REFERENCE.md → Prerequisites for how to request increases." -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Continue anyway? (Y/N, default: Y): " -NoNewline -ForegroundColor Yellow
        $continueChoice = Read-Host

        if ([string]::IsNullOrWhiteSpace($continueChoice) -or $continueChoice -eq 'Y' -or $continueChoice -eq 'y') {
            Write-Host "  Continuing with quota warnings acknowledged..." -ForegroundColor Yellow
            Write-Log "User chose to continue despite quota warnings: $($quotaIssues -join '; ')" -Level Warning
        }
        else {
            Write-Host ""
            Write-Host "  Installation cancelled. Please request the required quota increases and re-run the script." -ForegroundColor Red
            Write-Log "Installation cancelled by user due to quota warnings" -Level Warning
            exit 0
        }
    }
    else {
        Write-Host "  ✓ All quota checks passed." -ForegroundColor Green
        Write-Log "All quota checks passed" -Level Success
    }

    Write-Host ""
}

function Register-RequiredResourceProvider {
    <#
    .SYNOPSIS
        Ensures a resource provider is registered in the subscription.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProviderNamespace
    )

    Write-Log "Checking resource provider registration: $ProviderNamespace..." -Level Info

    try {
        $provider = Get-AzResourceProvider -ProviderNamespace $ProviderNamespace -ErrorAction Stop

        if ($provider.RegistrationState -eq 'Registered') {
            Write-Log "Resource provider '$ProviderNamespace' is already registered" -Level Info
            return $true
        }

        if ($provider.RegistrationState -eq 'Registering') {
            Write-Log "Resource provider '$ProviderNamespace' is currently registering..." -Level Info
        }
        else {
            Write-Log "Registering resource provider: $ProviderNamespace..." -Level Info
            Register-AzResourceProvider -ProviderNamespace $ProviderNamespace -ErrorAction Stop | Out-Null
        }

        # Wait for registration to complete with retry logic
        $maxRetries = 20
        $retryCount = 0
        $waitSeconds = 10

        while ($retryCount -lt $maxRetries) {
            Start-Sleep -Seconds $waitSeconds
            $provider = Get-AzResourceProvider -ProviderNamespace $ProviderNamespace -ErrorAction Stop
            
            Write-Log "Resource provider '$ProviderNamespace' status: $($provider.RegistrationState)" -Level Info

            if ($provider.RegistrationState -eq 'Registered') {
                Write-Log "Resource provider '$ProviderNamespace' registered successfully" -Level Success
                return $true
            }

            if ($provider.RegistrationState -ne 'Registering') {
                throw "Resource provider registration failed. Current state: $($provider.RegistrationState)"
            }

            $retryCount++
            Write-Log "Waiting for registration to complete... (Attempt $retryCount of $maxRetries)" -Level Info
        }

        # Registration timed out
        Write-Log "Resource provider '$ProviderNamespace' registration timed out after $($maxRetries * $waitSeconds) seconds" -Level Error
        Write-Log "Current registration status: $($provider.RegistrationState)" -Level Error
        Write-Host "`n❌ Resource Provider Registration Failed" -ForegroundColor Red
        Write-Host "   Provider: $ProviderNamespace" -ForegroundColor Yellow
        Write-Host "   Status: $($provider.RegistrationState)" -ForegroundColor Yellow
        Write-Host "   Please wait 5 minutes and try running the script again." -ForegroundColor Yellow
        Write-Host ""
        throw "Resource provider registration failed. Please try again in 5 minutes."
    }
    catch {
        Write-Log "Failed to register resource provider '$ProviderNamespace': $_" -Level Error
        throw
    }
}

#endregion

#region Subscription and Resource Group Management

function New-NeologikSubscription {
    <#
    .SYNOPSIS
        Creates or validates Azure subscription.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionName
    )

    Write-Log "Checking for subscription: $SubscriptionName..." -Level Info

    try {
        $subscription = Get-AzSubscription -SubscriptionName $SubscriptionName -ErrorAction SilentlyContinue

        if ($subscription) {
            Write-Log "Subscription '$SubscriptionName' already exists (ID: $($subscription.Id))" -Level Info
            $script:ConfigData['SubscriptionName'] = $subscription.Name
            $script:ConfigData['SubscriptionId'] = $subscription.Id
            
            # Set context to this subscription
            Set-AzContext -SubscriptionId $subscription.Id | Out-Null
            Write-Log "Set context to subscription: $SubscriptionName" -Level Success
        }
        else {
            Write-Log "Subscription '$SubscriptionName' not found." -Level Warning
            Write-Log "Note: Subscription creation requires Enterprise Agreement or Microsoft Customer Agreement." -Level Warning
            
            # List available subscriptions
            $existingSubscriptions = Get-AzSubscription
            if ($existingSubscriptions) {
                Write-Host "`nAvailable subscriptions:" -ForegroundColor Yellow
                $existingSubscriptions | ForEach-Object { Write-Host "  - $($_.Name) ($($_.Id))" }
                
                Write-Host "`nWould you like to use an existing subscription? (Y/N): " -NoNewline -ForegroundColor Cyan
                $useExisting = Read-Host
                if ($useExisting -eq 'Y' -or $useExisting -eq 'y' -or [string]::IsNullOrWhiteSpace($useExisting)) {
                    Write-Host "Enter the subscription name: " -NoNewline -ForegroundColor Cyan
                    $subName = Read-Host
                    $subscription = Get-AzSubscription -SubscriptionName $subName -ErrorAction Stop
                    $script:ConfigData['SubscriptionName'] = $subscription.Name
                    $script:ConfigData['SubscriptionId'] = $subscription.Id
                    Set-AzContext -SubscriptionId $subscription.Id | Out-Null
                    Write-Log "Using existing subscription: $subName" -Level Success
                }
                else {
                    throw "Subscription setup cancelled by user."
                }
            }
            else {
                throw "No subscriptions found. Please create a subscription first."
            }
        }

        return $subscription
    }
    catch {
        Write-Log "Failed to handle subscription: $_" -Level Error
        throw
    }
}

function New-NeologikResourceGroup {
    <#
    .SYNOPSIS
        Creates or validates resource group.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$Location
    )

    Write-Log "Checking for resource group: $ResourceGroupName..." -Level Info

    try {
        # Ensure Microsoft.Resources provider is registered
        Register-RequiredResourceProvider -ProviderNamespace 'Microsoft.Resources'

        $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue

        if ($rg) {
            Write-Log "Resource group '$ResourceGroupName' already exists in location $($rg.Location)" -Level Info
            
            # Check if location matches
            if ($rg.Location -ne $Location) {
                Write-Log "Warning: Existing resource group location ($($rg.Location)) differs from specified location ($Location)" -Level Warning
            }
            
            $script:ConfigData['ResourceGroupName'] = $rg.ResourceGroupName
            $script:ConfigData['AzureRegion'] = $rg.Location
        }
        else {
            Write-Log "Creating resource group: $ResourceGroupName in $Location..." -Level Info
            $rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -ErrorAction Stop
            Write-Log "Resource group created successfully" -Level Success
            
            $script:ConfigData['ResourceGroupName'] = $rg.ResourceGroupName
            $script:ConfigData['AzureRegion'] = $rg.Location
        }

        return $rg
    }
    catch {
        # Detect Azure RBAC authorization failures and surface them with a clear message
        if ($_.Exception.Message -match 'AuthorizationFailed|does not have authorization|does not have.*permission|Forbidden') {
            Write-Host "`n❌ PERMISSION ERROR: Cannot create resource group '$ResourceGroupName'" -ForegroundColor Red
            Write-Host "   The current account lacks permission to create resource groups in this subscription." -ForegroundColor Yellow
            Write-Host "   Required role: 'Owner' or 'Contributor' at subscription scope." -ForegroundColor Yellow
            Write-Host "   Subscription: $($script:ConfigData['SubscriptionId'])" -ForegroundColor Yellow
            Write-Host "   Ask your Azure administrator to grant the Owner role on the subscription," -ForegroundColor Cyan
            Write-Host "   then re-run the script and choose 'Y' to resume from the checkpoint." -ForegroundColor Cyan
            Write-Log "Resource group creation blocked by Azure RBAC. User: $($script:ConfigData['UserAccount']). Subscription: $($script:ConfigData['SubscriptionId'])" -Level Error
            throw "Insufficient permissions: Cannot create resource group '$ResourceGroupName' — Owner or Contributor role required at subscription scope"
        }
        Write-Log "Failed to create/validate resource group: $_" -Level Error
        throw
    }
}

#endregion

#region Guest User Management

function Invoke-GuestUserInvitation {
    <#
    .SYNOPSIS
        Invites Neologik guest users to the tenant.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$GuestEmails
    )

    # If no guest emails provided, return empty array
    if ($GuestEmails.Count -eq 0) {
        Write-Log "No guest users to invite. Skipping guest user invitation." -Level Info
        return @()
    }

    Write-Log "Inviting Neologik guest users..." -Level Info

    try {
        Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction Stop

        $invitedUsers = @()

        foreach ($email in $GuestEmails) {
            Write-Log "Processing guest user: $email..." -Level Info

            # Check if user already exists
            $existingUser = Get-MgUser -Filter "mail eq '$email' or userPrincipalName eq '$email'" -ErrorAction SilentlyContinue

            if ($existingUser) {
                Write-Log "Guest user $email already exists (ID: $($existingUser.Id))" -Level Info
                $invitedUsers += @{
                    Email = $email
                    UserId = $existingUser.Id
                    Status = 'AlreadyExists'
                }
            }
            else {
                # Send invitation
                Write-Log "Sending invitation to $email..." -Level Info
                
                $invitation = New-MgInvitation -InvitedUserEmailAddress $email `
                    -InviteRedirectUrl "https://portal.azure.com" `
                    -SendInvitationMessage:$true `
                    -ErrorAction Stop

                Write-Log "Invitation sent to $email (ID: $($invitation.InvitedUser.Id))" -Level Success
                
                $invitedUsers += @{
                    Email = $email
                    UserId = $invitation.InvitedUser.Id
                    Status = 'Invited'
                }
            }
        }

        $script:ConfigData['InvitedGuestUsers'] = $invitedUsers
        return $invitedUsers
    }
    catch {
        Write-Log "Failed to invite guest users: $_" -Level Error
        throw
    }
}

#endregion

#region Security Group Management

function New-NeologikSecurityGroups {
    <#
    .SYNOPSIS
        Creates Neologik security groups in Entra ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$GuestUsers,

        [Parameter(Mandatory = $false)]
        [string]$OrganizationCode = "",

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentType = "",

        [Parameter(Mandatory = $false)]
        [array]$BotNames = @("bot")
    )

    Write-Log "Creating Neologik security groups..." -Level Info

    try {
        Import-Module Microsoft.Graph.Groups -ErrorAction Stop

        # Build group names with organization code and environment type (lowercase)
        $orgLower = $OrganizationCode.ToLower()
        $envLower = if ([string]::IsNullOrWhiteSpace($EnvironmentType)) { "" } else { "-$($EnvironmentType.ToLower())" }
        $groupSuffix = if ([string]::IsNullOrWhiteSpace($OrganizationCode)) { "" } else { " - $orgLower$envLower" }

        # Build groups array starting with bot-specific user groups
        $groups = @()
        
        # Create a user group for each bot
        foreach ($botName in $BotNames) {
            $groups += @{
                Name = "Neologik User Group $botName$groupSuffix"
                Description = "Neologik users for Teams app access - $botName bot"
            }
        }
        
        # Add NCE and Admin groups (unchanged)
        $groups += @{
            Name = "Neologik NCE User Group$groupSuffix"
            Description = 'Users who need access to NCE web tool'
        }
        $groups += @{
            Name = "Neologik Admin User Group$groupSuffix"
            Description = 'Users who will administer and support the resources'
        }

        $createdGroups = @()

        foreach ($groupDef in $groups) {
            Write-Log "Processing group: $($groupDef.Name)..." -Level Info

            # Check if group exists
            $existingGroup = Get-MgGroup -Filter "displayName eq '$($groupDef.Name)'" -ErrorAction SilentlyContinue

            if ($existingGroup) {
                Write-Log "Group '$($groupDef.Name)' already exists (ID: $($existingGroup.Id))" -Level Info
                $group = $existingGroup
            }
            else {
                Write-Log "Creating group: $($groupDef.Name)..." -Level Info
                
                $group = New-MgGroup -DisplayName $groupDef.Name `
                    -Description $groupDef.Description `
                    -MailEnabled:$false `
                    -SecurityEnabled:$true `
                    -MailNickname ($groupDef.Name -replace '\s', '') `
                    -ErrorAction Stop

                Write-Log "Group created successfully (ID: $($group.Id))" -Level Success
            }

            # Add guest users to the group (if any)
            if ($GuestUsers.Count -gt 0) {
                Write-Log "Adding guest users to group: $($groupDef.Name)..." -Level Info
                
                foreach ($guestUser in $GuestUsers) {
                    try {
                        # Check if user is already a member
                        $isMember = Get-MgGroupMember -GroupId $group.Id -Filter "id eq '$($guestUser.UserId)'" -ErrorAction SilentlyContinue

                        if ($isMember) {
                            Write-Log "User $($guestUser.Email) is already a member of $($groupDef.Name)" -Level Info
                        }
                        else {
                            New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $guestUser.UserId -ErrorAction Stop
                            Write-Log "Added $($guestUser.Email) to $($groupDef.Name)" -Level Success
                        }
                    }
                    catch {
                        Write-Log "Warning: Could not add $($guestUser.Email) to $($groupDef.Name): $_" -Level Warning
                    }
                }
            }
            else {
                Write-Log "No guest users to add to group: $($groupDef.Name)" -Level Info
            }

            # Add the logged-in user to the group
            Write-Log "Adding logged-in user to group: $($groupDef.Name)..." -Level Info
            try {
                # Use the stored user ID which works for both member and guest users
                if ($script:ConfigData['CurrentUserId']) {
                    $currentUserId = $script:ConfigData['CurrentUserId']
                    $isMember = Get-MgGroupMember -GroupId $group.Id -Filter "id eq '$currentUserId'" -ErrorAction SilentlyContinue

                    if ($isMember) {
                        Write-Log "Logged-in user is already a member of $($groupDef.Name)" -Level Info
                    }
                    else {
                        New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $currentUserId -ErrorAction Stop
                        Write-Log "Added logged-in user to $($groupDef.Name)" -Level Success
                    }
                }
                else {
                    Write-Log "Warning: Could not determine current user ID, skipping group membership" -Level Warning
                }
            }
            catch {
                Write-Log "Warning: Could not add logged-in user to $($groupDef.Name): $_" -Level Warning
            }

            $createdGroups += @{
                Name = $group.DisplayName
                Id = $group.Id
                Description = $groupDef.Description
            }
        }

        $script:ConfigData['SecurityGroups'] = $createdGroups
        return $createdGroups
    }
    catch {
        Write-Log "Failed to create security groups: $_" -Level Error
        throw
    }
}

#endregion

#region Role Assignment

function Set-NeologikRoleAssignments {
    <#
    .SYNOPSIS
        Assigns roles to security groups.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$SecurityGroups,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
    )

    Write-Log "Assigning roles to security groups..." -Level Info

    try {
        # Find the Admin group (matches with or without suffix)
        $adminGroup = $SecurityGroups | Where-Object { $_.Name -like 'Neologik Admin User Group*' }

        if (-not $adminGroup) {
            throw "Neologik Admin User Group not found"
        }

        $subScope = "/subscriptions/$SubscriptionId"
        $rgScope  = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"

        # Verify permissions with a test call before assigning anything
        try {
            $null = Get-AzRoleAssignment -ObjectId $adminGroup.Id `
                -RoleDefinitionName 'Contributor' `
                -Scope $subScope `
                -ErrorAction Stop
        }
        catch {
            Write-Log "ERROR: Unable to verify role assignments - insufficient permissions" -Level Error
            Write-Host "`n❌ INSUFFICIENT PERMISSIONS" -ForegroundColor Red
            Write-Host "Cannot verify role assignments. Owner role at subscription level is required." -ForegroundColor Yellow
            throw "Insufficient permissions: Cannot verify role assignments"
        }

        # Roles to assign at subscription scope
        $subRoles = @(
            'Contributor',
            'Cost Management Contributor',
            'Monitoring Contributor'
        )

        # Roles to assign at resource-group scope
        $rgRoles = @(
            'Key Vault Administrator',
            'Storage Blob Data Contributor',
            'Storage Blob Data Owner',
            'Storage Table Data Contributor',
            'Azure Kubernetes Service RBAC Cluster Admin',
            'Cognitive Services Contributor',
            'Cognitive Services Data Reader',
            'Cognitive Services OpenAI Contributor',
            'Cosmos DB Account Reader Role',
            'Search Service Contributor',
            'Search Index Data Reader',
            'Azure AI Developer',
            'AzureML Data Scientist'
        )

        $assignRole = {
            param($ObjectId, $RoleName, $Scope, $GroupName)
            $existing = Get-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleName -Scope $Scope -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Log "$RoleName already assigned to $GroupName" -Level Info
                return
            }
            $retryCount = 0
            $maxRetries = 10
            $assigned = $false
            while (-not $assigned -and $retryCount -lt $maxRetries) {
                try {
                    New-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleName -Scope $Scope -ErrorAction Stop | Out-Null
                    Write-Log "$RoleName assigned to $GroupName successfully" -Level Success
                    $assigned = $true
                }
                catch {
                    if ($_.Exception.Message -match "does not exist|cannot be found|BadRequest") {
                        $retryCount++
                        if ($retryCount -lt $maxRetries) {
                            Write-Log "Security group not yet replicated. Retrying in 10 seconds... (Attempt $retryCount of $maxRetries)" -Level Warning
                            Start-Sleep -Seconds 10
                        }
                        else { throw }
                    }
                    else { throw }
                }
            }
        }

        foreach ($role in $subRoles) {
            Write-Log "Assigning $role to $($adminGroup.Name) at subscription scope..." -Level Info
            & $assignRole $adminGroup.Id $role $subScope $adminGroup.Name
        }

        foreach ($role in $rgRoles) {
            Write-Log "Assigning $role to $($adminGroup.Name) at resource group scope..." -Level Info
            & $assignRole $adminGroup.Id $role $rgScope $adminGroup.Name
        }

        $script:ConfigData['RoleAssignments'] = ($subRoles | ForEach-Object {
            @{ Principal = $adminGroup.Name; PrincipalType = 'Security Group'; Role = $_; Scope = 'Subscription' }
        }) + ($rgRoles | ForEach-Object {
            @{ Principal = $adminGroup.Name; PrincipalType = 'Security Group'; Role = $_; Scope = 'Resource Group' }
        })

        return $true
    }
    catch {
        Write-Log "Failed to assign roles: $_" -Level Error
        throw
    }
}

#endregion

#region App Registration

function New-NeologikAppRegistration {
    <#
    .SYNOPSIS
        Creates App Registration for GitHub service connection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$OrganizationCode = "",

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentType = ""
    )

    Write-Log "Creating App Registration for GitHub service connection..." -Level Info

    try {
        Import-Module Microsoft.Graph.Applications -ErrorAction Stop

        # Build app name with organization code and environment type (lowercase)
        $appName = if ([string]::IsNullOrWhiteSpace($OrganizationCode)) {
            "Neologik GitHub Service Connection"
        } else {
            $orgLower = $OrganizationCode.ToLower()
            $envLower = if ([string]::IsNullOrWhiteSpace($EnvironmentType)) { "" } else { "-$($EnvironmentType.ToLower())" }
            "Neologik GitHub Service Connection - $orgLower$envLower"
        }

        # Check if app registration exists
        $existingApp = Get-MgApplication -Filter "displayName eq '$appName'" -ErrorAction SilentlyContinue

        if ($existingApp) {
            Write-Log "App Registration '$appName' already exists (Client ID: $($existingApp.AppId))" -Level Info
            $app = $existingApp
        }
        else {
            Write-Log "Creating App Registration: $appName..." -Level Info

            $app = New-MgApplication -DisplayName $appName `
                -SignInAudience "AzureADMultipleOrgs" `
                -ErrorAction Stop

            Write-Log "App Registration created successfully (Client ID: $($app.AppId))" -Level Success
        }

        # Create service principal if it doesn't exist
        $sp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -ErrorAction SilentlyContinue

        if (-not $sp) {
            Write-Log "Creating Service Principal for App Registration..." -Level Info
            $sp = New-MgServicePrincipal -AppId $app.AppId -ErrorAction Stop
            Write-Log "Service Principal created successfully" -Level Success
        }
        else {
            Write-Log "Service Principal already exists" -Level Info
        }

        # Create client secret
        Write-Log "Creating client secret..." -Level Info
        
        $secretName = "auth"
        $secretEndDate = (Get-Date).AddDays(365)

        $passwordCred = Add-MgApplicationPassword -ApplicationId $app.Id `
            -PasswordCredential @{
            DisplayName = $secretName
            EndDateTime = $secretEndDate
        } -ErrorAction Stop

        Write-Log "Client secret created successfully (expires: $secretEndDate)" -Level Success
        Write-Host "`n✓ Client secret created and will be securely stored in Key Vault" -ForegroundColor Green

        # Grant admin consent for required permissions
        Write-Log "Configuring API permissions..." -Level Info
        # Note: Admin consent must be granted manually or through Graph API with appropriate permissions

        $script:ConfigData['AppRegistration'] = @{
            Name = $app.DisplayName
            ClientId = $app.AppId
            ObjectId = $app.Id
            ServicePrincipalId = $sp.Id
            SecretExpiry = $secretEndDate.ToString('yyyy-MM-dd')
            SubscriptionRoles = @('Contributor', 'Cost Management Contributor')
            RGRoles = @('Key Vault Certificates Officer', 'Key Vault Secrets Officer', 'Storage Blob Data Contributor', 'Azure Kubernetes Service RBAC Cluster Admin', 'Monitoring Contributor')
            GraphAppRoles = @('Application.Read.All', 'Application.ReadWrite.OwnedBy')
        }

        return @{
            Application = $app
            ServicePrincipal = $sp
            Secret = $passwordCred.SecretText
        }
    }
    catch {
        Write-Log "Failed to create App Registration: $_" -Level Error
        throw
    }
}

function Grant-GraphAppRolePermissions {
    <#
    .SYNOPSIS
        Grants lower-scoped Microsoft Graph application permissions to a service principal
        or managed identity, replacing the tenant-wide 'Application Administrator' directory role.
    .DESCRIPTION
        Assigns Microsoft Graph app roles (default: Application.Read.All and
        Application.ReadWrite.OwnedBy) via appRoleAssignments. Idempotent and retries while the
        principal replicates to Entra ID.

        NOTE: Application.ReadWrite.OwnedBy only permits managing app registrations the principal
        OWNS. Any flow that mutates an app registration with this identity (e.g. secret rotation)
        must first register the identity as an owner of that app.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PrincipalId,

        [Parameter(Mandatory = $false)]
        [string]$PrincipalDescription = 'service principal',

        [Parameter(Mandatory = $false)]
        [string[]]$AppRoles = @('Application.Read.All', 'Application.ReadWrite.OwnedBy')
    )

    # Microsoft Graph well-known IDs (appId of Microsoft Graph + application-permission app role IDs)
    $graphAppId = '00000003-0000-0000-c000-000000000000'
    $knownGraphAppRoleIds = @{
        'Application.Read.All'          = '9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30'
        'Application.ReadWrite.OwnedBy' = '18a4783c-866b-4cc7-a460-3d5e5662c884'
    }

    Write-Log "Granting Microsoft Graph app permissions ($($AppRoles -join ', ')) to $PrincipalDescription..." -Level Info

    # Resolve the Microsoft Graph service principal object ID in this tenant
    try {
        $graphSpResponse = Invoke-MgGraphRequest -Method GET `
            -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$graphAppId'" `
            -ErrorAction Stop
        $graphSpId = $graphSpResponse.value | Select-Object -First 1 -ExpandProperty id
    }
    catch {
        Write-Log "ERROR: Failed to resolve the Microsoft Graph service principal: $($_.Exception.Message)" -Level Error
        throw
    }

    if (-not $graphSpId) {
        throw "Could not resolve the Microsoft Graph service principal (appId $graphAppId) in this tenant."
    }

    foreach ($roleName in $AppRoles) {
        $appRoleId = $knownGraphAppRoleIds[$roleName]
        if (-not $appRoleId) {
            throw "Unknown Microsoft Graph app role '$roleName'. Add its app role ID to `$knownGraphAppRoleIds."
        }

        # Skip if the app role is already assigned to this principal
        try {
            $existing = Invoke-MgGraphRequest -Method GET `
                -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments" `
                -ErrorAction Stop
            $alreadyAssigned = $existing.value | Where-Object { $_.appRoleId -eq $appRoleId -and $_.resourceId -eq $graphSpId } | Select-Object -First 1
        }
        catch {
            if ($_.Exception.Message -match "InsufficientPermissions|Insufficient privileges|Authorization_RequestDenied|Forbidden") {
                Write-Log "ERROR: Insufficient permissions to read Graph app role assignments" -Level Error
                Write-Host "`n❌ PERMISSION ERROR" -ForegroundColor Red
                Write-Host "Assigning Microsoft Graph application permissions requires Privileged Role Administrator or Global Administrator in Entra ID." -ForegroundColor Yellow
                throw "Insufficient permissions: cannot read app role assignments"
            }
            $alreadyAssigned = $null
        }

        if ($alreadyAssigned) {
            Write-Log "Graph app role '$roleName' already assigned" -Level Info
            continue
        }

        # Assign, retrying while the principal replicates to Entra ID
        $retryCount = 0
        $maxRetries = 10
        $roleAssigned = $false

        while (-not $roleAssigned -and $retryCount -lt $maxRetries) {
            try {
                # Pass the body as a JSON string (not a hashtable): Invoke-MgGraphRequest's
                # hashtable serialization recurses into a string value's .Chars indexer and
                # throws "Self referencing loop detected ... Path 'resourceId.Chars'".
                $body = @{
                    principalId = [string]$PrincipalId
                    resourceId  = [string]$graphSpId
                    appRoleId   = [string]$appRoleId
                } | ConvertTo-Json -Compress
                Invoke-MgGraphRequest -Method POST `
                    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments" `
                    -Body $body `
                    -ContentType 'application/json' `
                    -ErrorAction Stop | Out-Null
                Write-Log "Graph app role '$roleName' assigned successfully" -Level Success
                $roleAssigned = $true
            }
            catch {
                if ($_.Exception.Message -match "already exist|conflicting object|Permission being assigned already exists") {
                    Write-Log "Graph app role '$roleName' already assigned (detected on add)" -Level Info
                    $roleAssigned = $true
                }
                elseif ($_.Exception.Message -match "Forbidden|Authorization_RequestDenied|Insufficient privileges") {
                    Write-Log "ERROR: Insufficient permissions to assign Graph app role '$roleName'" -Level Error
                    Write-Host "`n❌ PERMISSION ERROR" -ForegroundColor Red
                    Write-Host "Required: Privileged Role Administrator or Global Administrator in Entra ID." -ForegroundColor Yellow
                    throw "Insufficient permissions: cannot assign Graph app role '$roleName'"
                }
                elseif ($_.Exception.Message -match "does not exist|cannot be found|not found|ResourceNotFound") {
                    $retryCount++
                    if ($retryCount -lt $maxRetries) {
                        Write-Log "$PrincipalDescription not yet replicated to Entra ID. Retrying in 10 seconds... (Attempt $retryCount of $maxRetries)" -Level Warning
                        Start-Sleep -Seconds 10
                    }
                    else {
                        throw
                    }
                }
                else {
                    throw
                }
            }
        }
    }
}

function Set-AppRegistrationRoles {
    <#
    .SYNOPSIS
        Assigns roles to App Registration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServicePrincipalId,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [array]$SecurityGroups
    )

    Write-Log "Assigning roles to App Registration..." -Level Info

    try {
        # Add to Neologik Admin User Group (matches with or without suffix)
        $adminGroup = $SecurityGroups | Where-Object { $_.Name -like 'Neologik Admin User Group*' }
        
        if ($adminGroup) {
            Write-Log "Adding App Registration to $($adminGroup.Name)..." -Level Info
            
            try {
                $isMember = Get-MgGroupMember -GroupId $adminGroup.Id -Filter "id eq '$ServicePrincipalId'" -ErrorAction SilentlyContinue

                if ($isMember) {
                    Write-Log "Service Principal is already a member of the group" -Level Info
                }
                else {
                    New-MgGroupMember -GroupId $adminGroup.Id -DirectoryObjectId $ServicePrincipalId -ErrorAction Stop
                    Write-Log "Service Principal added to $($adminGroup.Name)" -Level Success
                }
            }
            catch {
                Write-Log "Warning: Could not add Service Principal to group: $_" -Level Warning
            }
        }

        # Assign subscription roles
        $roles = @('Contributor', 'Cost Management Contributor')

        foreach ($roleName in $roles) {
            Write-Log "Assigning $roleName role..." -Level Info

            try {
                $existingAssignment = Get-AzRoleAssignment -ObjectId $ServicePrincipalId `
                    -RoleDefinitionName $roleName `
                    -Scope "/subscriptions/$SubscriptionId" `
                    -ErrorAction Stop
            }
            catch {
                Write-Log "ERROR: Unable to verify $roleName role assignment - insufficient permissions" -Level Error
                Write-Host "`n❌ INSUFFICIENT PERMISSIONS" -ForegroundColor Red
                Write-Host "Cannot verify role assignments. Owner role at subscription level is required." -ForegroundColor Yellow
                throw "Insufficient permissions: Cannot verify role assignments"
            }

            if ($existingAssignment) {
                Write-Log "$roleName role already assigned" -Level Info
            }
            else {
                # Add retry logic for newly created service principals
                $retryCount = 0
                $maxRetries = 10
                $roleAssigned = $false

                while (-not $roleAssigned -and $retryCount -lt $maxRetries) {
                    try {
                        New-AzRoleAssignment -ObjectId $ServicePrincipalId `
                            -RoleDefinitionName $roleName `
                            -Scope "/subscriptions/$SubscriptionId" `
                            -ErrorAction Stop | Out-Null

                        Write-Log "$roleName role assigned successfully" -Level Success
                        $roleAssigned = $true
                    }
                    catch {
                        # Check if it's a permission error (Forbidden)
                        if ($_.Exception.Message -match "Forbidden|not authorized") {
                            Write-Log "ERROR: Insufficient permissions to assign $roleName role" -Level Error
                            Write-Log "Required Permission: Owner role at subscription level" -Level Error
                            Write-Host "`n❌ PERMISSION ERROR" -ForegroundColor Red
                            Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Red
                            Write-Host ""
                            Write-Host "You do not have sufficient permissions to complete this setup." -ForegroundColor Yellow
                            Write-Host ""
                            Write-Host "Required Permissions:" -ForegroundColor Cyan
                            Write-Host "  ✗ Owner role at subscription level (MISSING)" -ForegroundColor Red
                            Write-Host "  ? Global Administrator role in Entra ID" -ForegroundColor Gray
                            Write-Host ""
                            Write-Host "Current Issue: Cannot assign '$roleName' role to the service principal." -ForegroundColor Yellow
                            Write-Host ""
                            Write-Host "Please contact a user with Owner permissions at the subscription level to run this script." -ForegroundColor Yellow
                            Write-Host ""
                            throw "Insufficient permissions: Owner role at subscription level required to assign $roleName"
                        }
                        elseif ($_.Exception.Message -match "does not exist|cannot be found|BadRequest") {
                            $retryCount++
                            if ($retryCount -lt $maxRetries) {
                                Write-Log "Service Principal not yet replicated. Retrying in 10 seconds... (Attempt $retryCount of $maxRetries)" -Level Warning
                                Start-Sleep -Seconds 10
                            }
                            else {
                                throw
                            }
                        }
                        else {
                            throw
                        }
                    }
                }
            }
        }

        # Assign resource-group-scoped roles (previously required UAA to assign during deployment)
        $rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
        $rgRoles = @('Key Vault Certificates Officer', 'Key Vault Secrets Officer', 'Storage Blob Data Contributor', 'Azure Kubernetes Service RBAC Cluster Admin', 'Monitoring Contributor')

        foreach ($roleName in $rgRoles) {
            Write-Log "Assigning $roleName role at resource group scope..." -Level Info

            $existingAssignment = Get-AzRoleAssignment -ObjectId $ServicePrincipalId `
                -RoleDefinitionName $roleName `
                -Scope $rgScope `
                -ErrorAction SilentlyContinue

            if ($existingAssignment) {
                Write-Log "$roleName role already assigned at RG scope" -Level Info
            }
            else {
                $retryCount = 0
                $maxRetries = 10
                $roleAssigned = $false

                while (-not $roleAssigned -and $retryCount -lt $maxRetries) {
                    try {
                        New-AzRoleAssignment -ObjectId $ServicePrincipalId `
                            -RoleDefinitionName $roleName `
                            -Scope $rgScope `
                            -ErrorAction Stop | Out-Null

                        Write-Log "$roleName role assigned successfully at RG scope" -Level Success
                        $roleAssigned = $true
                    }
                    catch {
                        if ($_.Exception.Message -match "does not exist|cannot be found|BadRequest") {
                            $retryCount++
                            if ($retryCount -lt $maxRetries) {
                                Write-Log "Service Principal not yet replicated. Retrying in 10 seconds... (Attempt $retryCount of $maxRetries)" -Level Warning
                                Start-Sleep -Seconds 10
                            }
                            else {
                                throw
                            }
                        }
                        else {
                            throw
                        }
                    }
                }
            }
        }

        # Grant lower-scoped Microsoft Graph application permissions to the service principal.
        # Replaces the tenant-wide 'Application Administrator' Entra directory role with
        # Application.Read.All + Application.ReadWrite.OwnedBy (manage owned apps only).
        Grant-GraphAppRolePermissions -PrincipalId $ServicePrincipalId -PrincipalDescription 'App Registration service principal'

        # Update ConfigData with group membership
        if ($script:ConfigData['AppRegistration'] -and $adminGroup) {
            $script:ConfigData['AppRegistration']['GroupMemberships'] = @($adminGroup.Name)
        }

        return $true
    }
    catch {
        # If it's a permission error, it's already been logged with formatted message
        if ($_.Exception.Message -match "Insufficient permissions:|ERROR: Insufficient permissions") {
            throw  # Re-throw without adding more text
        }
        Write-Log "Failed to assign roles to App Registration: $_" -Level Error
        throw
    }
}

#endregion

#region Key Vault

function New-NeologikKeyVault {
    <#
    .SYNOPSIS
        Creates Key Vault and stores the service principal secret.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$KeyVaultName,

        [Parameter(Mandatory = $true)]
        [string]$ClientSecret,

        [Parameter(Mandatory = $true)]
        [array]$SecurityGroups,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    Write-Log "Creating Key Vault..." -Level Info

    try {
        Import-Module Az.KeyVault -ErrorAction Stop

        # Ensure Microsoft.KeyVault provider is registered
        Register-RequiredResourceProvider -ProviderNamespace 'Microsoft.KeyVault'

        # Check if Key Vault exists
        $existingKv = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName -ErrorAction SilentlyContinue

        if ($existingKv) {
            Write-Log "Key Vault '$KeyVaultName' already exists" -Level Info
            $keyVault = $existingKv
        }
        else {
            Write-Log "Creating Key Vault: $KeyVaultName..." -Level Info
            
            # Create Key Vault
            $keyVault = New-AzKeyVault -ResourceGroupName $ResourceGroupName `
                -VaultName $KeyVaultName `
                -Location $Location `
                -ErrorAction Stop

            # Enable RBAC authorization
            Write-Log "Enabling RBAC authorization on Key Vault..." -Level Info
            try {
                # Use switch parameter (no value needed)
                Update-AzKeyVault -ResourceGroupName $ResourceGroupName `
                    -VaultName $KeyVaultName `
                    -EnableRbacAuthorization `
                    -ErrorAction Stop
            }
            catch {
                if ($_.Exception.Message -match "parameter.*EnableRbacAuthorization|Cannot find") {
                    # Fallback: Set via ARM template properties for older module versions
                    Write-Log "Using ARM API to enable RBAC authorization..." -Level Warning
                    
                    $keyVaultResource = Get-AzResource -ResourceId "/subscriptions/$((Get-AzContext).Subscription.Id)/resourceGroups/$ResourceGroupName/providers/Microsoft.KeyVault/vaults/$KeyVaultName"
                    $keyVaultResource.Properties.enableRbacAuthorization = $true
                    $null = Set-AzResource -ResourceId $keyVaultResource.ResourceId -Properties $keyVaultResource.Properties -Force
                }
                else {
                    throw
                }
            }

            Write-Log "Key Vault created successfully with RBAC authorization" -Level Success
            
            # Refresh the Key Vault object
            $keyVault = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName
        }

        # Get resource group scope for role assignments
        $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
        $rgScope = $resourceGroup.ResourceId

        # Assign Key Vault Secrets Officer role to current user FIRST (so we can store secrets)
        Write-Log "Assigning Key Vault Secrets Officer role to current user..." -Level Info
        if ($script:ConfigData['CurrentUserId']) {
            $existingUserAssignment = Get-AzRoleAssignment -ObjectId $script:ConfigData['CurrentUserId'] `
                -RoleDefinitionName 'Key Vault Secrets Officer' `
                -Scope $rgScope `
                -ErrorAction SilentlyContinue

            if (-not $existingUserAssignment) {
                New-AzRoleAssignment -ObjectId $script:ConfigData['CurrentUserId'] `
                    -RoleDefinitionName 'Key Vault Secrets Officer' `
                    -Scope $rgScope `
                    -ErrorAction Stop | Out-Null
                Write-Log "Key Vault Secrets Officer role assigned to current user" -Level Success
                
                # Wait for role propagation
                Write-Log "Waiting 15 seconds for role assignment to propagate..." -Level Info
                Start-Sleep -Seconds 15
            }
            else {
                Write-Log "Current user already has Key Vault Secrets Officer role" -Level Info
            }
        }

        # Assign Key Vault data-plane roles to Neologik Admin User Group at Resource Group level
        $adminGroup = $SecurityGroups | Where-Object { $_.Name -like 'Neologik Admin User Group*' }

        if ($adminGroup) {
            foreach ($roleName in @('Key Vault Secrets Officer', 'Key Vault Certificates Officer')) {
                Write-Log "Assigning $roleName role to $($adminGroup.Name) at Resource Group level..." -Level Info

                $existingAssignment = Get-AzRoleAssignment -ObjectId $adminGroup.Id `
                    -RoleDefinitionName $roleName `
                    -Scope $rgScope `
                    -ErrorAction SilentlyContinue

                if ($existingAssignment) {
                    Write-Log "$roleName role already assigned to $($adminGroup.Name) at Resource Group level" -Level Info
                }
                else {
                    New-AzRoleAssignment -ObjectId $adminGroup.Id `
                        -RoleDefinitionName $roleName `
                        -Scope $rgScope `
                        -ErrorAction Stop | Out-Null

                    Write-Log "$roleName role assigned to $($adminGroup.Name) at Resource Group level successfully" -Level Success
                }
            }
        }

        # Now store the client secret (with retry for permission propagation)
        Write-Log "Storing service principal client secret in Key Vault..." -Level Info
        $secretName = "neologik-deployment-service-principle-secret"
        
        $retryCount = 0
        $maxRetries = 10
        $secretStored = $false

        while (-not $secretStored -and $retryCount -lt $maxRetries) {
            try {
                $secureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
                $null = Set-AzKeyVaultSecret -VaultName $KeyVaultName `
                    -Name $secretName `
                    -SecretValue $secureSecret `
                    -ErrorAction Stop

                Write-Log "Client secret stored successfully as '$secretName'" -Level Success
                $secretStored = $true
            }
            catch {
                if ($_.Exception.Message -match "Forbidden|not authorized") {
                    $retryCount++
                    if ($retryCount -lt $maxRetries) {
                        Write-Log "Permission not yet propagated. Retrying in 10 seconds... (Attempt $retryCount of $maxRetries)" -Level Warning
                        Start-Sleep -Seconds 10
                    }
                    else {
                        throw
                    }
                }
                else {
                    throw
                }
            }
        }

        $script:ConfigData['KeyVault'] = @{
            Name = $keyVault.VaultName
            ResourceId = $keyVault.ResourceId
            VaultUri = $keyVault.VaultUri
            SecretName = $secretName
        }

        return $keyVault
    }
    catch {
        Write-Log "Failed to create Key Vault: $_" -Level Error
        throw
    }
}

#endregion

#region Resource Provider Registration

function Register-AllResourceProviders {
    <#
    .SYNOPSIS
        Registers Microsoft.Compute resource provider for the subscription.
    #>
    [CmdletBinding()]
    param()

    $providers = @(
        'Microsoft.Compute',
        'Microsoft.KeyVault',
        'Microsoft.ManagedIdentity',
        'Microsoft.Resources',
        'Microsoft.Storage'
    )

    Write-Log "Registering all required Azure resource providers..." -Level Info

    foreach ($provider in $providers) {
        # Skip providers already confirmed registered in a previous run (checkpoint)
        if ($script:ProviderRegistrations[$provider] -eq 'Registered') {
            Write-Log "Resource provider '$provider' already registered (from checkpoint)" -Level Info
            continue
        }

        try {
            Register-RequiredResourceProvider -ProviderNamespace $provider
            $script:ProviderRegistrations[$provider] = 'Registered'
            Save-Checkpoint -Label "Provider_$provider"
        }
        catch {
            # Timeouts are normal for slow Azure regions — record and continue rather than aborting.
            # The provider registration continues in the background; on the next run the real-time
            # state check inside Register-RequiredResourceProvider will pick it up as Registered.
            if ($_.Exception.Message -match 'timed out|Please try again') {
                Write-Log "Resource provider '$provider' registration timed out - it may still be registering in Azure" -Level Warning
                $script:ProviderRegistrations[$provider] = 'TimedOut'
                Save-Checkpoint -Label "Provider_${provider}_TimedOut"
            }
            else {
                Write-Log "Failed to register resource provider '$provider': $_" -Level Error
                throw
            }
        }
    }

    # Report any providers that timed out so the user is aware
    $timedOutProviders = @($script:ProviderRegistrations.GetEnumerator() | Where-Object { $_.Value -eq 'TimedOut' } | Select-Object -ExpandProperty Key)
    if ($timedOutProviders.Count -gt 0) {
        Write-Host "`n⚠️  The following resource providers timed out and may still be registering in Azure:" -ForegroundColor Yellow
        $timedOutProviders | ForEach-Object { Write-Host "     - $_" -ForegroundColor Yellow }
        Write-Host "   This is normal — Azure continues registering them in the background." -ForegroundColor Gray
        Write-Host "   Re-run the script and choose 'Y' to resume; timed-out providers will be re-checked" -ForegroundColor Gray
        Write-Host "   and skipped automatically once they reach the 'Registered' state." -ForegroundColor Gray
        Write-Host ""
        Write-Log "Resource provider registration timed out for: $($timedOutProviders -join ', ')" -Level Warning
    }
    else {
        Write-Log "All resource providers registered successfully" -Level Success
    }

    # Register Microsoft.Compute/EncryptionAtHost feature (required for AKS encrypted node pools)
    Write-Log "Checking Microsoft.Compute/EncryptionAtHost feature registration..." -Level Info
    try {
        $feature = Get-AzProviderFeature -ProviderNamespace 'Microsoft.Compute' -FeatureName 'EncryptionAtHost' -ErrorAction Stop
        if ($feature.RegistrationState -eq 'Registered') {
            Write-Log "Microsoft.Compute/EncryptionAtHost feature is already registered" -Level Info
        } else {
            Write-Log "Registering Microsoft.Compute/EncryptionAtHost feature..." -Level Info
            Register-AzProviderFeature -ProviderNamespace 'Microsoft.Compute' -FeatureName 'EncryptionAtHost' -ErrorAction Stop | Out-Null

            # Wait up to 10 minutes for feature registration
            $maxRetries = 20
            $waitSeconds = 30
            for ($i = 0; $i -lt $maxRetries; $i++) {
                Start-Sleep -Seconds $waitSeconds
                $feature = Get-AzProviderFeature -ProviderNamespace 'Microsoft.Compute' -FeatureName 'EncryptionAtHost' -ErrorAction Stop
                Write-Host "  ⏳ EncryptionAtHost: $($feature.RegistrationState) ($($i + 1)/$maxRetries)..." -ForegroundColor Gray
                Write-Log "EncryptionAtHost feature status: $($feature.RegistrationState)" -Level Info
                if ($feature.RegistrationState -eq 'Registered') {
                    Register-AzResourceProvider -ProviderNamespace 'Microsoft.Compute' -ErrorAction Stop | Out-Null
                    Write-Log "Microsoft.Compute/EncryptionAtHost feature registered successfully" -Level Success
                    break
                }
            }
            if ($feature.RegistrationState -ne 'Registered') {
                Write-Log "Microsoft.Compute/EncryptionAtHost feature registration timed out — check Azure portal for status" -Level Warning
            }
        }
    } catch {
        Write-Log "Failed to register Microsoft.Compute/EncryptionAtHost feature: $_" -Level Warning
    }
}

#endregion

#region Storage Account

function New-NeologikStorageAccount {
    <#
    .SYNOPSIS
        Creates Storage Account and blob container for certificates.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [array]$SecurityGroups
    )

    Write-Log "Creating Storage Account..." -Level Info

    try {
        Import-Module Az.Storage -ErrorAction Stop

        # Ensure Microsoft.Storage provider is registered
        Register-RequiredResourceProvider -ProviderNamespace 'Microsoft.Storage'

        # Check if Storage Account exists
        $existingSa = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue

        if ($existingSa) {
            Write-Log "Storage Account '$StorageAccountName' already exists" -Level Info
            $storageAccount = $existingSa
        }
        else {
            Write-Log "Creating Storage Account: $StorageAccountName..." -Level Info
            
            $storageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName `
                -Name $StorageAccountName `
                -Location $Location `
                -SkuName Standard_LRS `
                -Kind StorageV2 `
                -AllowBlobPublicAccess $false `
                -ErrorAction Stop

            Write-Log "Storage Account created successfully" -Level Success
        }

        # Disable shared key access to enforce Entra ID authentication
        Write-Log "Configuring Storage Account to use Microsoft Entra authentication..." -Level Info
        Set-AzStorageAccount -ResourceGroupName $ResourceGroupName `
            -Name $StorageAccountName `
            -AllowSharedKeyAccess $false `
            -ErrorAction Stop | Out-Null
        
        Write-Log "Storage Account configured to use Microsoft Entra authentication (shared key access disabled)" -Level Success

        # Get storage context using Entra ID authentication
        $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount

        # Create blob container for certificates
        Write-Log "Creating blob container 'certificate'..." -Level Info
        $certContainerName = "certificate"
        
        $existingCertContainer = Get-AzStorageContainer -Name $certContainerName -Context $ctx -ErrorAction SilentlyContinue

        if ($existingCertContainer) {
            Write-Log "Blob container '$certContainerName' already exists" -Level Info
        }
        else {
            New-AzStorageContainer -Name $certContainerName -Context $ctx -Permission Off -ErrorAction Stop | Out-Null
            Write-Log "Blob container '$certContainerName' created successfully" -Level Success
        }

        # Create blob container for JSON configuration files
        Write-Log "Creating blob container 'json'..." -Level Info
        $jsonContainerName = "json"
        
        $existingJsonContainer = Get-AzStorageContainer -Name $jsonContainerName -Context $ctx -ErrorAction SilentlyContinue

        if ($existingJsonContainer) {
            Write-Log "Blob container '$jsonContainerName' already exists" -Level Info
        }
        else {
            New-AzStorageContainer -Name $jsonContainerName -Context $ctx -Permission Off -ErrorAction Stop | Out-Null
            Write-Log "Blob container '$jsonContainerName' created successfully" -Level Success
        }

        # Create blob container for log files
        Write-Log "Creating blob container 'logs'..." -Level Info
        $logsContainerName = "logs"
        
        $existingLogsContainer = Get-AzStorageContainer -Name $logsContainerName -Context $ctx -ErrorAction SilentlyContinue

        if ($existingLogsContainer) {
            Write-Log "Blob container '$logsContainerName' already exists" -Level Info
        }
        else {
            New-AzStorageContainer -Name $logsContainerName -Context $ctx -Permission Off -ErrorAction Stop | Out-Null
            Write-Log "Blob container '$logsContainerName' created successfully" -Level Success
        }

        # Get resource group scope for role assignments
        $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
        $rgScope = $resourceGroup.ResourceId

        # Assign Storage Blob Data Contributor role to current user FIRST (so we can upload logs and config)
        Write-Log "Assigning Storage Blob Data Contributor role to current user..." -Level Info
        if ($script:ConfigData['CurrentUserId']) {
            $existingUserAssignment = Get-AzRoleAssignment -ObjectId $script:ConfigData['CurrentUserId'] `
                -RoleDefinitionName 'Storage Blob Data Contributor' `
                -Scope $rgScope `
                -ErrorAction SilentlyContinue

            if (-not $existingUserAssignment) {
                New-AzRoleAssignment -ObjectId $script:ConfigData['CurrentUserId'] `
                    -RoleDefinitionName 'Storage Blob Data Contributor' `
                    -Scope $rgScope `
                    -ErrorAction Stop | Out-Null
                Write-Log "Storage Blob Data Contributor role assigned to current user" -Level Success
                
                # Wait for role propagation
                Write-Log "Waiting 15 seconds for role assignment to propagate..." -Level Info
                Start-Sleep -Seconds 15
            }
            else {
                Write-Log "Current user already has Storage Blob Data Contributor role" -Level Info
            }
        }

        # Assign Storage Blob Data Contributor role to Neologik Admin User Group at Resource Group level
        $adminGroup = $SecurityGroups | Where-Object { $_.Name -like 'Neologik Admin User Group*' }
        
        if ($adminGroup) {
            Write-Log "Assigning Storage Blob Data Contributor role to $($adminGroup.Name) at Resource Group level..." -Level Info
            
            $existingAssignment = Get-AzRoleAssignment -ObjectId $adminGroup.Id `
                -RoleDefinitionName 'Storage Blob Data Contributor' `
                -Scope $rgScope `
                -ErrorAction SilentlyContinue

            if ($existingAssignment) {
                Write-Log "Storage Blob Data Contributor role already assigned to $($adminGroup.Name) at Resource Group level" -Level Info
            }
            else {
                New-AzRoleAssignment -ObjectId $adminGroup.Id `
                    -RoleDefinitionName 'Storage Blob Data Contributor' `
                    -Scope $rgScope `
                    -ErrorAction Stop | Out-Null

                Write-Log "Storage Blob Data Contributor role assigned to $($adminGroup.Name) at Resource Group level successfully" -Level Success
            }
        }

        $script:ConfigData['StorageAccount'] = @{
            Name = $storageAccount.StorageAccountName
            ResourceId = $storageAccount.Id
            BlobEndpoint = $storageAccount.PrimaryEndpoints.Blob
            CertificateContainerName = $certContainerName
            JsonContainerName = $jsonContainerName
            LogsContainerName = $logsContainerName
        }

        return $storageAccount
    }
    catch {
        Write-Log "Failed to create Storage Account: $_" -Level Error
        throw
    }
}

#endregion

#region Managed Identity

function New-NeologikManagedIdentities {
    <#
    .SYNOPSIS
        Creates User Assigned Managed Identities and assigns all required RBAC roles.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $false)]
        [string]$OrganizationCode = "",

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentType = ""
    )

    Write-Log "Creating Managed Identities..." -Level Info

    try {
        Import-Module Az.ManagedServiceIdentity -ErrorAction Stop

        # Ensure Microsoft.ManagedIdentity provider is registered
        Register-RequiredResourceProvider -ProviderNamespace 'Microsoft.ManagedIdentity'

        # Build names with organization code and environment type (lowercase)
        $orgLower = $OrganizationCode.ToLower()
        $envLower = if ([string]::IsNullOrWhiteSpace($EnvironmentType)) { "" } else { "$($EnvironmentType.ToLower())" }
        $nameSuffix = if ([string]::IsNullOrWhiteSpace($OrganizationCode)) { "" } else { "-$orgLower$envLower" }
        $displaySuffix = if ([string]::IsNullOrWhiteSpace($OrganizationCode)) { "" } else { " - $orgLower$envLower" }

        $managedIdentities = @(
            @{
                Name = "neologik-script-runner-service-connection$nameSuffix"
                DisplayName = "Neologik Script Runner Service Connection$displaySuffix"
                Roles = @('Contributor')
                RGRoles = @('Key Vault Secrets Officer', 'Azure Bot Service Contributor Role')
                GraphAppRoles = @('Application.Read.All', 'Application.ReadWrite.OwnedBy')
            },
            @{
                Name = "neologik-sql-managed-identity$nameSuffix"
                DisplayName = "Neologik SQL Managed Identity$displaySuffix"
                Roles = @()
                EntraRole = 'Directory Readers'
            }
        )

        $createdIdentities = @()

        foreach ($miDef in $managedIdentities) {
            $displayName = if ($miDef.DisplayName) { $miDef.DisplayName } else { $miDef.Name }
            Write-Log "Processing Managed Identity: $displayName..." -Level Info

            # Check if MI exists
            $existingMI = Get-AzUserAssignedIdentity -ResourceGroupName $ResourceGroupName -Name $miDef.Name -ErrorAction SilentlyContinue

            if ($existingMI) {
                Write-Log "Managed Identity '$displayName' already exists (ID: $($existingMI.PrincipalId))" -Level Info
                $mi = $existingMI
            }
            else {
                Write-Log "Creating Managed Identity: $displayName..." -Level Info
                
                try {
                    $mi = New-AzUserAssignedIdentity -ResourceGroupName $ResourceGroupName `
                        -Name $miDef.Name `
                        -Location $Location `
                        -ErrorAction Stop

                    Write-Log "Managed Identity created successfully (Principal ID: $($mi.PrincipalId))" -Level Success
                }
                catch {
                    Write-Log "ERROR: Failed to create Managed Identity '$displayName'" -Level Error
                    Write-Log "Error details: $($_.Exception.Message)" -Level Error
                    if ($_.Exception.InnerException) {
                        Write-Log "Inner exception: $($_.Exception.InnerException.Message)" -Level Error
                    }
                    throw
                }
            }

            # Assign subscription-scoped roles
            foreach ($roleName in $miDef.Roles) {
                Write-Log "Assigning $roleName role to $displayName at subscription scope..." -Level Info

                $existingAssignment = Get-AzRoleAssignment -ObjectId $mi.PrincipalId `
                    -RoleDefinitionName $roleName `
                    -Scope "/subscriptions/$SubscriptionId" `
                    -ErrorAction SilentlyContinue

                if ($existingAssignment) {
                    Write-Log "$roleName role already assigned" -Level Info
                }
                else {
                    $retryCount = 0
                    $maxRetries = 10
                    $assigned = $false

                    while (-not $assigned -and $retryCount -lt $maxRetries) {
                        try {
                            New-AzRoleAssignment -ObjectId $mi.PrincipalId `
                                -RoleDefinitionName $roleName `
                                -Scope "/subscriptions/$SubscriptionId" `
                                -ErrorAction Stop | Out-Null
                            $assigned = $true
                            Write-Log "$roleName role assigned successfully" -Level Success
                        }
                        catch {
                            $retryCount++
                            if ($retryCount -lt $maxRetries) {
                                Write-Log "Retrying role assignment in 10 seconds... (Attempt $retryCount of $maxRetries)" -Level Warning
                                Start-Sleep -Seconds 10
                            }
                            else {
                                throw
                            }
                        }
                    }
                }
            }

            # Assign resource-group-scoped roles
            if ($miDef.RGRoles) {
                $rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
                foreach ($roleName in $miDef.RGRoles) {
                    Write-Log "Assigning $roleName role to $displayName at resource group scope..." -Level Info

                    $existingAssignment = Get-AzRoleAssignment -ObjectId $mi.PrincipalId `
                        -RoleDefinitionName $roleName `
                        -Scope $rgScope `
                        -ErrorAction SilentlyContinue

                    if ($existingAssignment) {
                        Write-Log "$roleName role already assigned at RG scope" -Level Info
                    }
                    else {
                        $retryCount = 0
                        $maxRetries = 10
                        $assigned = $false

                        while (-not $assigned -and $retryCount -lt $maxRetries) {
                            try {
                                New-AzRoleAssignment -ObjectId $mi.PrincipalId `
                                    -RoleDefinitionName $roleName `
                                    -Scope $rgScope `
                                    -ErrorAction Stop | Out-Null
                                $assigned = $true
                                Write-Log "$roleName role assigned successfully at RG scope" -Level Success
                            }
                            catch {
                                $retryCount++
                                if ($retryCount -lt $maxRetries) {
                                    Write-Log "Retrying role assignment in 10 seconds... (Attempt $retryCount of $maxRetries)" -Level Warning
                                    Start-Sleep -Seconds 10
                                }
                                else {
                                    throw
                                }
                            }
                        }
                    }
                }
            }

            # Assign Entra ID role
            if ($miDef.EntraRole) {
                Write-Log "Assigning $($miDef.EntraRole) role in Entra ID..." -Level Info
                
                Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop
                
                $entraRole = Get-MgDirectoryRole -Filter "displayName eq '$($miDef.EntraRole)'" -ErrorAction SilentlyContinue
                
                if (-not $entraRole) {
                    $roleTemplate = Get-MgDirectoryRoleTemplate -Filter "displayName eq '$($miDef.EntraRole)'"
                    if ($roleTemplate) {
                        $entraRole = New-MgDirectoryRole -RoleTemplateId $roleTemplate.Id
                    }
                }

                if ($entraRole) {
                    # Add retry logic for newly created managed identities (may need time to replicate in AD)
                    $retryCount = 0
                    $maxRetries = 10
                    $roleAssigned = $false

                    while (-not $roleAssigned -and $retryCount -lt $maxRetries) {
                        try {
                            # Check if already a member
                            $existingRoleMember = Get-MgDirectoryRoleMember -DirectoryRoleId $entraRole.Id -ErrorAction SilentlyContinue | Where-Object { $_.Id -eq $mi.PrincipalId }

                            if ($existingRoleMember) {
                                Write-Log "$($miDef.EntraRole) role already assigned" -Level Info
                                $roleAssigned = $true
                            }
                            else {
                                # Try to add the member
                                $body = @{
                                    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($mi.PrincipalId)"
                                }
                                New-MgDirectoryRoleMemberByRef -DirectoryRoleId $entraRole.Id -BodyParameter $body -ErrorAction Stop
                                Write-Log "$($miDef.EntraRole) role assigned successfully" -Level Success
                                $roleAssigned = $true
                            }
                        }
                        catch {
                            # Handle case where member already exists
                            if ($_.Exception.Message -match "already exist") {
                                Write-Log "$($miDef.EntraRole) role already assigned (detected on add)" -Level Info
                                $roleAssigned = $true
                            }
                            # Handle case where resource not found (needs replication time)
                            elseif ($_.Exception.Message -match "does not exist" -or $_.Exception.Message -match "NotFound") {
                                $retryCount++
                                if ($retryCount -lt $maxRetries) {
                                    Write-Log "Managed Identity not yet replicated to Entra ID. Retrying in 10 seconds... (Attempt $retryCount of $maxRetries)" -Level Warning
                                    Start-Sleep -Seconds 10
                                }
                                else {
                                    throw
                                }
                            }
                            else {
                                throw
                            }
                        }
                    }
                }
            }

            # Grant lower-scoped Microsoft Graph app permissions (replaces Application Administrator)
            if ($miDef.GraphAppRoles) {
                Grant-GraphAppRolePermissions -PrincipalId $mi.PrincipalId `
                    -PrincipalDescription "Managed Identity '$($miDef.Name)'" `
                    -AppRoles $miDef.GraphAppRoles
            }

            $createdIdentities += @{
                Name = $mi.Name
                PrincipalId = $mi.PrincipalId
                ClientId = $mi.ClientId
                ResourceId = $mi.Id
                SubscriptionRoles = $miDef.Roles
                RGRoles = $miDef.RGRoles
                EntraRole = $miDef.EntraRole
                GraphAppRoles = $miDef.GraphAppRoles
                GroupMemberships = @()  # Managed Identities are not added to security groups
            }
        }

        $script:ConfigData['ManagedIdentities'] = $createdIdentities
        return $createdIdentities
    }
    catch {
        Write-Log "Failed to create Managed Identities: $_" -Level Error
        throw
    }
}

#endregion

#region Output and Reporting

function Export-ConfigurationData {
    <#
    .SYNOPSIS
        Exports configuration data to JSON file and displays summary.
    #>
    [CmdletBinding()]
    param()

    Write-Log "Exporting configuration data..." -Level Info

    try {
        # Create ordered output with specific field order
        $orderedConfig = [ordered]@{
            'ScriptVersion' = $script:Version
            'GeneratedAt' = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            'OrganizationName' = $script:OrganizationName
            'OrganizationCode' = $script:OrganizationCode
            'TenantName' = $script:ConfigData['TenantName']
            'TenantId' = $script:ConfigData['TenantId']
            'SubscriptionName' = $script:ConfigData['SubscriptionName']
            'SubscriptionId' = $script:ConfigData['SubscriptionId']
            'ResourceGroupName' = $script:ConfigData['ResourceGroupName']
            'SolutionName' = $script:ConfigData['SolutionName']
            'SolutionShortName' = $script:ConfigData['SolutionShortName']
            'UserAccount' = $script:ConfigData['UserAccount']
            'AzureRegion' = $script:ConfigData['AzureRegion']
            'Hostname' = $script:ConfigData['Hostname']
            'DomainName' = $script:ConfigData['DomainName']
            'BotCount' = $script:ConfigData['BotCount']
            'Bots' = $script:ConfigData['Bots']
            'InvitedGuestUsers' = $script:ConfigData['InvitedGuestUsers']
            'SecurityGroups' = $script:ConfigData['SecurityGroups']
            'AppRegistration' = $script:ConfigData['AppRegistration']
            'KeyVault' = $script:ConfigData['KeyVault']
            'StorageAccount' = $script:ConfigData['StorageAccount']
            'ManagedIdentities' = $script:ConfigData['ManagedIdentities']
            'RoleAssignments' = $script:ConfigData['RoleAssignments']
        }

        # Export to JSON
        $orderedConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:OutputFile -Encoding UTF8
        Write-Log "Configuration exported to: $script:OutputFile" -Level Success

        # Copy JSON file to Storage Account blob container
        try {
            if ($script:ConfigData['StorageAccount']) {
                Write-Log "Copying configuration file to Storage Account..." -Level Info
                
                $storageAccountName = $script:ConfigData['StorageAccount'].Name
                $jsonContainerName = $script:ConfigData['StorageAccount'].JsonContainerName
                $blobName = Split-Path -Leaf $script:OutputFile
                
                # Get storage context using Entra ID authentication
                $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
                
                # Upload the JSON file to the json blob container
                Set-AzStorageBlobContent -File $script:OutputFile `
                    -Container $jsonContainerName `
                    -Blob $blobName `
                    -Context $ctx `
                    -Force `
                    -ErrorAction Stop | Out-Null
                
                Write-Log "Configuration file uploaded to Storage Account: $storageAccountName/$jsonContainerName/$blobName" -Level Success
            }
        }
        catch {
            Write-Log "Warning: Failed to copy configuration file to Storage Account: $_" -Level Warning
            Write-Log "The configuration file is still available locally at: $script:OutputFile" -Level Info
        }

        # Copy log file to Storage Account blob container
        try {
            if ($script:ConfigData['StorageAccount']) {
                Write-Log "Copying log file to Storage Account..." -Level Info
                
                $storageAccountName = $script:ConfigData['StorageAccount'].Name
                $logsContainerName = $script:ConfigData['StorageAccount'].LogsContainerName
                $logBlobName = Split-Path -Leaf $script:LogFile
                
                # Get storage context using Entra ID authentication
                $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -UseConnectedAccount
                
                # Upload the log file to the logs blob container
                Set-AzStorageBlobContent -File $script:LogFile `
                    -Container $logsContainerName `
                    -Blob $logBlobName `
                    -Context $ctx `
                    -Force `
                    -ErrorAction Stop | Out-Null
                
                Write-Log "Log file uploaded to Storage Account: $storageAccountName/$logsContainerName/$logBlobName" -Level Success
            }
        }
        catch {
            Write-Log "Warning: Failed to copy log file to Storage Account: $_" -Level Warning
            Write-Log "The log file is still available locally at: $script:LogFile" -Level Info
        }

        # Display summary
        Write-Host "`n" -NoNewline
        Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║                                                               ║" -ForegroundColor Green
        Write-Host "║          NEOLOGIK ONBOARDING COMPLETED SUCCESSFULLY           ║" -ForegroundColor Green
        Write-Host "║                                                               ║" -ForegroundColor Green
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host "`n"

        Write-Host "Configuration Summary:" -ForegroundColor Cyan
        Write-Host "═══════════════════════" -ForegroundColor Cyan
        Write-Host ""

        # Tenant Information
        Write-Host "Tenant Information:" -ForegroundColor Yellow
        Write-Host "  Tenant ID: $($script:ConfigData['TenantId'])"
        Write-Host "  Tenant Name: $($script:ConfigData['TenantName'])"
        Write-Host ""

        # Subscription Information
        Write-Host "Subscription Information:" -ForegroundColor Yellow
        Write-Host "  Subscription Name: $($script:ConfigData['SubscriptionName'])"
        Write-Host "  Subscription ID: $($script:ConfigData['SubscriptionId'])"
        Write-Host ""

        # Resource Group
        Write-Host "Resource Group:" -ForegroundColor Yellow
        Write-Host "  Name: $($script:ConfigData['ResourceGroupName'])"
        Write-Host "  Region: $($script:ConfigData['AzureRegion'])"
        Write-Host ""

        # Security Groups
        Write-Host "Security Groups:" -ForegroundColor Yellow
        foreach ($group in $script:ConfigData['SecurityGroups']) {
            Write-Host "  - $($group.Name)"
            Write-Host "    ID: $($group.Id)"
        }
        Write-Host ""

        # App Registration
        if ($script:ConfigData['AppRegistration']) {
            Write-Host "App Registration:" -ForegroundColor Yellow
            Write-Host "  Name: $($script:ConfigData['AppRegistration'].Name)"
            Write-Host "  Client ID: $($script:ConfigData['AppRegistration'].ClientId)"
            Write-Host ""
        }

        # Key Vault
        if ($script:ConfigData['KeyVault']) {
            Write-Host "Key Vault:" -ForegroundColor Yellow
            Write-Host "  Name: $($script:ConfigData['KeyVault'].Name)"
            Write-Host "  Vault URI: $($script:ConfigData['KeyVault'].VaultUri)"
            Write-Host "  Secret Name: $($script:ConfigData['KeyVault'].SecretName)"
            Write-Host ""
        }

        # Storage Account
        if ($script:ConfigData['StorageAccount']) {
            Write-Host "Storage Account:" -ForegroundColor Yellow
            Write-Host "  Name: $($script:ConfigData['StorageAccount'].Name)"
            Write-Host "  Blob Endpoint: $($script:ConfigData['StorageAccount'].BlobEndpoint)"
            Write-Host "  Certificate Container: $($script:ConfigData['StorageAccount'].CertificateContainerName)"
            Write-Host "  JSON Container: $($script:ConfigData['StorageAccount'].JsonContainerName)"
            Write-Host "  Logs Container: $($script:ConfigData['StorageAccount'].LogsContainerName)"
            Write-Host ""
        }

        # Managed Identities
        Write-Host "Managed Identities:" -ForegroundColor Yellow
        foreach ($mi in $script:ConfigData['ManagedIdentities']) {
            Write-Host "  - $($mi.Name)"
            Write-Host "    Principal ID: $($mi.PrincipalId)"
        }
        Write-Host ""

        Write-Host "Output Files:" -ForegroundColor Yellow
        Write-Host "  Configuration (Local): $script:OutputFile" -ForegroundColor Cyan
        if ($script:ConfigData['StorageAccount']) {
            Write-Host "  Configuration (Blob):  $($script:ConfigData['StorageAccount'].Name)/$($script:ConfigData['StorageAccount'].JsonContainerName)/$(Split-Path -Leaf $script:OutputFile)" -ForegroundColor Cyan
        }
        Write-Host "  Log File (Local):      $script:LogFile" -ForegroundColor Cyan
        if ($script:ConfigData['StorageAccount']) {
            Write-Host "  Log File (Blob):       $($script:ConfigData['StorageAccount'].Name)/$($script:ConfigData['StorageAccount'].LogsContainerName)/$(Split-Path -Leaf $script:LogFile)" -ForegroundColor Cyan
        }
        Write-Host ""

        Write-Host "⚠️  Next Steps:" -ForegroundColor Yellow
        Write-Host "  1. Review the configuration file (available locally and in Storage Account)"
        Write-Host "  2. Service principal client secret is securely stored in Key Vault: $($script:ConfigData['KeyVault'].Name)"
        Write-Host "     Secret name: $($script:ConfigData['KeyVault'].SecretName)"
        Write-Host "  3. Import your TLS certificate (.pfx file) into Key Vault as a certificate:"
        Write-Host "     Key Vault:        $($script:ConfigData['KeyVault'].Name)"
        Write-Host "     Certificate name: keyvault-neo-ingress"
        Write-Host "     Command:"
        Write-Host "       az keyvault certificate import --vault-name $($script:ConfigData['KeyVault'].Name) --name keyvault-neo-ingress --file certificate.pfx --password <PFX_PASSWORD>"
        Write-Host "     (The PFX password is consumed at import time — it does not need to be stored separately.)"
        Write-Host ""

        return $script:OutputFile
    }
    catch {
        Write-Log "Failed to export configuration: $_" -Level Error
        throw
    }
}

#endregion

#region Main Execution

function Get-UserInput {
    <#
    .SYNOPSIS
        Prompts user for input with a default value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter(Mandatory = $true)]
        [string]$DefaultValue,

        [Parameter(Mandatory = $false)]
        [switch]$IsSecret
    )

    Write-Host ""
    Write-Host $Prompt -ForegroundColor Cyan
    Write-Host "  Default: " -NoNewline -ForegroundColor Gray
    Write-Host $DefaultValue -ForegroundColor Yellow
    
    if ($IsSecret) {
        Write-Host "  Press Enter to use default, or type new value (input hidden): " -NoNewline -ForegroundColor Gray
        $secureInput = Read-Host -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput)
        $userInput = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    else {
        Write-Host "  Press Enter to use default, or type new value: " -NoNewline -ForegroundColor Gray
        $userInput = Read-Host
    }

    if ([string]::IsNullOrWhiteSpace($userInput)) {
        Write-Host "  ✓ Using default: $DefaultValue" -ForegroundColor Green
        return $DefaultValue
    }
    else {
        Write-Host "  ✓ Using: $userInput" -ForegroundColor Green
        return $userInput
    }
}

function Start-NeologikOnboarding {
    <#
    .SYNOPSIS
        Main function to orchestrate the onboarding process.
    #>
    [CmdletBinding()]
    param()

    try {
        $resuming = $false
        Write-ScriptHeader

        # Check for an existing checkpoint and offer to resume
        $existingCheckpoint = Find-LatestCheckpoint
        if ($existingCheckpoint) {
            $age = (Get-Date) - $existingCheckpoint.LastWriteTime
            $ageStr = if ($age.TotalDays -ge 1) { "$([int]$age.TotalDays) day(s) ago" }
                      elseif ($age.TotalHours -ge 1) { "$([int]$age.TotalHours) hour(s) ago" }
                      else { "$([int]$age.TotalMinutes) minute(s) ago" }

            Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
            Write-Host "║                                                               ║" -ForegroundColor Yellow
            Write-Host "║                  RESUME PREVIOUS RUN?                         ║" -ForegroundColor Yellow
            Write-Host "║                                                               ║" -ForegroundColor Yellow
            Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  A saved checkpoint was found ($ageStr):" -ForegroundColor Gray
            Write-Host "  $($existingCheckpoint.Name)" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  Resume from this checkpoint? (default: Y): " -NoNewline -ForegroundColor Yellow
            $resumeChoice = Read-Host

            if ([string]::IsNullOrWhiteSpace($resumeChoice) -or $resumeChoice -eq 'Y' -or $resumeChoice -eq 'y') {
                $restored = Restore-Checkpoint -Path $existingCheckpoint.FullName
                if ($restored -eq $false) { $resuming = $false }
                else { $resuming = $true }

                Write-Host "`n  ✓ Checkpoint loaded." -ForegroundColor Green
                Write-Host "    Org: $($script:OrganizationCode)  |  Env: $($script:EnvironmentType)  |  Region: $($script:AzureRegion)" -ForegroundColor Cyan
                Write-Host "    Resource Group: $($script:ResourceGroupName)" -ForegroundColor Cyan
                $timedOut = @($script:ProviderRegistrations.GetEnumerator() | Where-Object { $_.Value -eq 'TimedOut' })
                if ($timedOut.Count -gt 0) {
                    Write-Host "    Provider registrations to retry: $($timedOut.Count)" -ForegroundColor Yellow
                }
                Write-Host ""
                Write-Log "Resuming from checkpoint: $($existingCheckpoint.FullName)" -Level Info
            }
            else {
                Write-Host "`n  Starting a fresh run..." -ForegroundColor Green
                Write-Host ""
            }
        }

        # Step 0: Show Terms and Conditions (skip when resuming — already accepted)
        if (-not $resuming) {
            $termsAccepted = Show-TermsAndConditions
            if (-not $termsAccepted) {
                Write-Log "Installation cancelled by user - terms not accepted" -Level Warning
                exit 0
            }
        }
        else {
            Write-Log "Resuming from checkpoint — Terms and Conditions acceptance carried over" -Level Info
        }

        # Step 1: Check PowerShell version first
        if (-not $SkipPowerShellUpdate) {
            $psVersionOk = Test-PowerShellVersion
            if (-not $psVersionOk) {
                Write-Host ""
                Write-Host "PowerShell needs to be updated to version 7.4 or higher." -ForegroundColor Yellow
                Write-Host "Would you like to update PowerShell now? (Y/N): " -NoNewline -ForegroundColor Cyan
                $update = Read-Host
                if ($update -eq 'Y' -or $update -eq 'y' -or [string]::IsNullOrWhiteSpace($update)) {
                    Install-PowerShellLatest
                }
                else {
                    throw "PowerShell 7.4+ is required. Please update PowerShell and run this script again."
                }
            }
        }

        # Step 2: Check and install required modules
        if (-not $SkipModuleInstall) {
            $missingModules = Test-RequiredModules
            if ($missingModules.Count -gt 0) {
                Write-Log "The following modules need to be installed:" -Level Warning
                $missingModules | ForEach-Object { Write-Log "  - $($_.Name) >= $($_.MinVersion)" -Level Info }
                
                Write-Host ""
                Write-Host "Would you like to install missing modules now? (Y/N): " -NoNewline -ForegroundColor Cyan
                $install = Read-Host
                if ($install -eq 'Y' -or $install -eq 'y' -or [string]::IsNullOrWhiteSpace($install)) {
                    Install-RequiredModules -Modules $missingModules
                }
                else {
                    throw "Required modules are missing. Please install them and run this script again."
                }
            }
        }

        # Step 3: Check if user wants to re-authenticate
        $currentContext = Get-AzContext -ErrorAction SilentlyContinue
        
        if ($currentContext -and $currentContext.Account) {
            Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
            Write-Host "║                                                               ║" -ForegroundColor Yellow
            Write-Host "║                  CURRENT AZURE CONNECTION                     ║" -ForegroundColor Yellow
            Write-Host "║                                                               ║" -ForegroundColor Yellow
            Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "You are currently logged in as:" -ForegroundColor Gray
            Write-Host "  User:         " -NoNewline -ForegroundColor Gray
            Write-Host "$($currentContext.Account.Id)" -ForegroundColor Cyan
            Write-Host "  Tenant:       " -NoNewline -ForegroundColor Gray
            Write-Host "$($currentContext.Tenant.Id)" -ForegroundColor Cyan
            if ($currentContext.Subscription) {
                Write-Host "  Subscription: " -NoNewline -ForegroundColor Gray
                Write-Host "$($currentContext.Subscription.Name)" -ForegroundColor Cyan
            }
            Write-Host ""
            Write-Host "Do you want to re-authenticate to Azure? (default: N)" -ForegroundColor Yellow
            Write-Host "  Your choice (N/Y): " -NoNewline -ForegroundColor Yellow
            $reauth = Read-Host
            
            if ($reauth -eq 'Y' -or $reauth -eq 'y') {
                Write-Host "You will be prompted to login to Azure..." -ForegroundColor Green
                # Disconnect current session completely
                Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
                Clear-AzContext -Scope CurrentUser -Force -ErrorAction SilentlyContinue
                Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
                # Set flag to force re-authentication
                $script:ForceReAuth = $true
            }
            else {
                Write-Host "Continuing with current connection..." -ForegroundColor Green
                $script:ForceReAuth = $false
            }
            Write-Host ""
        }

        # Step 4: Connect to Azure FIRST to get tenant and subscription info
        Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
        Write-Host "║                                                               ║" -ForegroundColor Magenta
        Write-Host "║                     AZURE AUTHENTICATION                      ║" -ForegroundColor Magenta
        Write-Host "║                                                               ║" -ForegroundColor Magenta
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
        Write-Host ""
        
        $null = Connect-AzureEnvironment -TenantId $TenantId

        # Step 5: Get current subscription from context
        # On resume, switch to the subscription from the checkpoint before reading the context.
        if ($resuming -and $script:ConfigData['SubscriptionId']) {
            Set-AzContext -SubscriptionId $script:ConfigData['SubscriptionId'] -ErrorAction Stop | Out-Null
            Write-Log "Restored Azure context to subscription: $($script:ConfigData['SubscriptionId'])" -Level Info
        }

        $currentContext = Get-AzContext
        if (-not $currentContext -or -not $currentContext.Subscription) {
            throw "No active Azure subscription found. Please ensure you're logged in with access to a subscription."
        }

        $script:ConfigData['SubscriptionName'] = $currentContext.Subscription.Name
        $script:ConfigData['SubscriptionId'] = $currentContext.Subscription.Id
        
        Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                                                               ║" -ForegroundColor Cyan
        Write-Host "║                   SUBSCRIPTION INFORMATION                    ║" -ForegroundColor Cyan
        Write-Host "║                                                               ║" -ForegroundColor Cyan
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Using subscription from your login:" -ForegroundColor Yellow
        Write-Host "  Name: $($currentContext.Subscription.Name)" -ForegroundColor Gray
        Write-Host "  ID:   $($currentContext.Subscription.Id)" -ForegroundColor Gray
        Write-Host ""
        
        Write-Log "Using subscription: $($currentContext.Subscription.Name) (ID: $($currentContext.Subscription.Id))" -Level Success

        # Step 5b: Validate required permissions before prompting for input
        Write-Log "Validating required permissions..." -Level Info
        $null = Test-RequiredPermissions -SubscriptionId $script:ConfigData['SubscriptionId']

        # Step 6: Collect remaining configuration inputs (skipped when resuming from checkpoint)
        if (-not $resuming) {

        Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
        Write-Host "║                                                               ║" -ForegroundColor Magenta
        Write-Host "║                   CONFIGURATION SETUP                         ║" -ForegroundColor Magenta
        Write-Host "║      Please review and confirm the following settings         ║" -ForegroundColor Magenta
        Write-Host "║                                                               ║" -ForegroundColor Magenta
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta

        # Get Organization Code with validation (FIRST QUESTION)
        $orgCodeValid = $false
        while (-not $orgCodeValid) {
            Write-Host ""
            Write-Host "Organization Code (exactly 3 characters):" -ForegroundColor Cyan
            Write-Host "  Default: " -NoNewline -ForegroundColor Gray
            Write-Host $OrganizationCode -ForegroundColor Yellow
            Write-Host "  Requirements: lowercase, exactly 3 characters, letters and numbers only" -ForegroundColor Gray
            Write-Host "  Press Enter to use default, or type new value: " -NoNewline -ForegroundColor Gray
            $orgInput = Read-Host

            if ([string]::IsNullOrWhiteSpace($orgInput)) {
                $script:OrganizationCode = $OrganizationCode.ToLower()
            }
            else {
                $script:OrganizationCode = $orgInput.Trim().ToLower()
            }

            # Validate length
            if ($script:OrganizationCode.Length -ne 3) {
                Write-Host "  ✗ Organization code must be exactly 3 characters. Please try again." -ForegroundColor Red
                continue
            }

            # Validate lowercase alphanumeric only
            if ($script:OrganizationCode -notmatch '^[a-z0-9]{3}$') {
                Write-Host "  ✗ Organization code must contain only lowercase letters and numbers. Please try again." -ForegroundColor Red
                continue
            }

            $orgCodeValid = $true
            Write-Host "  ✓ Using: $($script:OrganizationCode)" -ForegroundColor Green
        }

        # Get Environment Type with validation (SECOND QUESTION)
        $envTypeValid = $false
        while (-not $envTypeValid) {
            Write-Host ""
            Write-Host "Environment Type:" -ForegroundColor Cyan
            Write-Host "  Default: " -NoNewline -ForegroundColor Gray
            Write-Host $EnvironmentType -ForegroundColor Yellow
            Write-Host "  Valid options: dev, prd" -ForegroundColor Gray
            Write-Host "  Press Enter to use default, or type new value: " -NoNewline -ForegroundColor Gray
            $envInput = Read-Host

            if ([string]::IsNullOrWhiteSpace($envInput)) {
                $script:EnvironmentType = $EnvironmentType.ToLower()
                $envTypeValid = $true
                Write-Host "  ✓ Using default: $($script:EnvironmentType)" -ForegroundColor Green
            }
            elseif ($envInput.ToLower() -eq 'dev' -or $envInput.ToLower() -eq 'prd') {
                $script:EnvironmentType = $envInput.ToLower()
                $envTypeValid = $true
                Write-Host "  ✓ Using: $($script:EnvironmentType)" -ForegroundColor Green
            }
            else {
                Write-Host "  ✗ Invalid environment type. Must be 'dev' or 'prd'. Please try again." -ForegroundColor Red
            }
        }

        # Initialize configuration file now that we have org code and environment type
        Initialize-ConfigurationFile

        # Get Organization Name
        Write-Host ""
        Write-Host "Organization Name (full company name):" -ForegroundColor Cyan
        Write-Host "  Example: Contoso Ltd, Acme Corporation" -ForegroundColor Gray
        Write-Host "  Enter organization name: " -NoNewline -ForegroundColor Gray
        $orgNameInput = Read-Host

        while ([string]::IsNullOrWhiteSpace($orgNameInput)) {
            Write-Host "  Organization name is required. Please enter a name: " -NoNewline -ForegroundColor Yellow
            $orgNameInput = Read-Host
        }

        $script:OrganizationName = $orgNameInput.Trim()
        Write-Host "  ✓ Using: " -NoNewline -ForegroundColor Green
        Write-Host $script:OrganizationName -ForegroundColor White

        # Get Hostname
        Write-Host ""
        Write-Host "Bot DNS Hostname:" -ForegroundColor Cyan
        Write-Host "  Example: neologik, neologik-dev" -ForegroundColor Gray
        Write-Host "  Enter DNS hostname: " -NoNewline -ForegroundColor Gray
        $hostnameInput = Read-Host

        while ([string]::IsNullOrWhiteSpace($hostnameInput)) {
            Write-Host "  DNS hostname is required. Please enter a DNS hostname: " -NoNewline -ForegroundColor Yellow
            $hostnameInput = Read-Host
        }

        $script:Hostname = $hostnameInput.Trim().ToLower()
        $script:ConfigData['Hostname'] = $script:Hostname
        Write-Host "  ✓ Using: " -NoNewline -ForegroundColor Green
        Write-Host $script:Hostname -ForegroundColor White

        # Get Domain Name
        Write-Host ""
        Write-Host "Bot DNS Domain Name:" -ForegroundColor Cyan
        Write-Host "  Example: contoso.com, example.co.uk" -ForegroundColor Gray
        Write-Host "  Enter DNS domain name: " -NoNewline -ForegroundColor Gray
        $domainInput = Read-Host

        while ([string]::IsNullOrWhiteSpace($domainInput)) {
            Write-Host "  DNS domain name is required. Please enter a DNS domain name: " -NoNewline -ForegroundColor Yellow
            $domainInput = Read-Host
        }

        $script:DomainName = $domainInput.Trim().ToLower()
        $script:ConfigData['DomainName'] = $script:DomainName
        Write-Host "  ✓ Using: " -NoNewline -ForegroundColor Green
        Write-Host $script:DomainName -ForegroundColor White

        # Get Azure Region with real-time validation
        # Query Azure for available locations
        Write-Host ""
        Write-Host "Retrieving available Azure regions..." -ForegroundColor Gray
        
        # Microsoft Cloud Adoption Framework (CAF) recommended region abbreviations
        # Reference: https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations
        $script:MicrosoftCAFRegionCodes = @{
            # Americas
            'eastus' = 'eus'
            'eastus2' = 'eus2'
            'westus' = 'wus'
            'westus2' = 'wus2'
            'westus3' = 'wus3'
            'centralus' = 'cus'
            'northcentralus' = 'ncus'
            'southcentralus' = 'scus'
            'westcentralus' = 'wcus'
            'canadacentral' = 'cac'
            'canadaeast' = 'cae'
            'brazilsouth' = 'brs'
            'brazilsoutheast' = 'brse'
            'brazilus' = 'bru'
            'mexicocentral' = 'mxc'
            'chilecentral' = 'clc'
            
            # Europe
            'northeurope' = 'neu'
            'westeurope' = 'weu'
            'uksouth' = 'uks'
            'ukwest' = 'ukw'
            'francecentral' = 'frc'
            'francesouth' = 'frs'
            'germanywestcentral' = 'gwc'
            'germanynorth' = 'gno'
            'norwayeast' = 'noe'
            'norwaywest' = 'now'
            'swedencentral' = 'sdc'
            'swedensouth' = 'sds'
            'switzerlandnorth' = 'szn'
            'switzerlandwest' = 'szw'
            'italynorth' = 'itn'
            'polandcentral' = 'plc'
            'spaincentral' = 'spc'
            'austriaeast' = 'ate'
            'belgiumcentral' = 'bec'
            
            # Asia Pacific
            'eastasia' = 'eas'
            'southeastasia' = 'seas'
            'australiaeast' = 'aue'
            'australiasoutheast' = 'ause'
            'australiacentral' = 'auc'
            'australiacentral2' = 'auc2'
            'japaneast' = 'jpe'
            'japanwest' = 'jpw'
            'koreacentral' = 'krc'
            'koreasouth' = 'krs'
            'centralindia' = 'inc'
            'southindia' = 'ins'
            'westindia' = 'inw'
            'jioindiawest' = 'jiw'
            'jioindiacentral' = 'jic'
            'indonesiacentral' = 'idc'
            'malaysiawest' = 'myw'
            'newzealandnorth' = 'nzn'
            
            # Middle East & Africa
            'southafricanorth' = 'san'
            'southafricawest' = 'saw'
            'uaenorth' = 'uan'
            'uaecentral' = 'uac'
            'qatarcentral' = 'qac'
            'israelcentral' = 'ilc'
            
            # China (requires special subscription)
            'chinanorth' = 'cnn'
            'chinanorth2' = 'cnn2'
            'chinanorth3' = 'cnn3'
            'chinaeast' = 'cne'
            'chinaeast2' = 'cne2'
            'chinaeast3' = 'cne3'
            
            # Government (requires special subscription)
            'usgovvirginia' = 'ugv'
            'usgovarizona' = 'uga'
            'usgovtexas' = 'ugt'
            'usdodeast' = 'ude'
            'usdodcentral' = 'udc'
            
            # EUAP (Early Update Access Program) regions
            'centraluseuap' = 'cuse'
            'eastus2euap' = 'eus2e'
            
            # Geographic groups (not for deployment, but returned by Azure API)
            'asia' = 'asia'
            'asiapacific' = 'apac'
            'australia' = 'au'
            'brazil' = 'br'
            'canada' = 'ca'
            'europe' = 'eu'
            'france' = 'fr'
            'germany' = 'de'
            'global' = 'global'
            'india' = 'in'
            'indonesia' = 'id'
            'israel' = 'il'
            'italy' = 'it'
            'japan' = 'jp'
            'korea' = 'kr'
            'malaysia' = 'my'
            'mexico' = 'mx'
            'newzealand' = 'nz'
            'norway' = 'no'
            'poland' = 'pl'
            'qatar' = 'qa'
            'singapore' = 'sg'
            'southafrica' = 'za'
            'spain' = 'es'
            'sweden' = 'se'
            'switzerland' = 'ch'
            'taiwan' = 'tw'
            'unitedstates' = 'us'
        }
        
        try {
            $azureLocations = Get-AzLocation | Sort-Object Location
            
            # Build region codes mapping using Microsoft CAF standards
            $script:AzureRegionCodes = @{}
            $script:AzureRegionDisplayNames = @{}
            
            foreach ($location in $azureLocations) {
                $locationName = $location.Location.ToLower()
                $displayName = $location.DisplayName
                
                # Use Microsoft CAF standard abbreviation if available
                if ($script:MicrosoftCAFRegionCodes.ContainsKey($locationName)) {
                    $code = $script:MicrosoftCAFRegionCodes[$locationName]
                } else {
                    # Fallback for new regions not yet in CAF standards
                    Write-Log "Region '$locationName' not in CAF standards, creating abbreviation" -Level Info
                    if ($locationName -match '([a-z]+)([0-9]+)') {
                        $base = $Matches[1]
                        $num = $Matches[2]
                        $code = ($base.Substring(0, [Math]::Min(3, $base.Length)) + $num).ToLower()
                    } else {
                        $code = $locationName.Substring(0, [Math]::Min(3, $locationName.Length)).ToLower()
                    }
                }
                
                $script:AzureRegionCodes[$locationName] = $code
                $script:AzureRegionDisplayNames[$locationName] = $displayName
            }
            
            $locationCount = $azureLocations.Count
            $cafCount = ($azureLocations | Where-Object { $script:MicrosoftCAFRegionCodes.ContainsKey($_.Location.ToLower()) }).Count
            Write-Host "✓ Retrieved $locationCount Azure regions ($cafCount using Microsoft CAF standards)" -ForegroundColor Green
        }
        catch {
            Write-Log "Warning: Could not retrieve Azure locations dynamically. Using fallback validation." -Level Warning
            Write-Host "  ⚠ Could not retrieve regions from Azure. Will validate region when creating resource group." -ForegroundColor Yellow
            $azureLocations = $null
            # Use CAF standards as fallback
            $script:AzureRegionCodes = $script:MicrosoftCAFRegionCodes
        }
        
        $regionValid = $false
        
        while (-not $regionValid) {
            Write-Host ""
            Write-Host "Azure Region:" -ForegroundColor Cyan
            Write-Host "  Default: " -NoNewline -ForegroundColor Gray
            Write-Host $AzureRegion -ForegroundColor Yellow
            
            if ($azureLocations) {
                # Show some common regions
                $commonRegions = $azureLocations | Where-Object { 
                    $_.Location -in @('uksouth', 'ukwest', 'eastus', 'westus', 'northeurope', 'westeurope', 'switzerlandnorth')
                } | Select-Object -First 7
                
                if ($commonRegions) {
                    Write-Host "  Common regions: " -NoNewline -ForegroundColor Gray
                    Write-Host ($commonRegions.Location -join ', ') -ForegroundColor Gray
                }
                Write-Host "  Type 'list' to see all available regions" -ForegroundColor Gray
            } else {
                Write-Host "  Examples: uksouth, ukwest, eastus, westus, northeurope, westeurope" -ForegroundColor Gray
            }
            
            Write-Host "  Press Enter to use default, or type new value: " -NoNewline -ForegroundColor Gray
            $regionInput = Read-Host

            # Handle special command to list all regions
            if ($regionInput.ToLower() -eq 'list' -and $azureLocations) {
                Write-Host ""
                Write-Host "Available Azure Regions:" -ForegroundColor Cyan
                Write-Host "------------------------" -ForegroundColor Cyan
                foreach ($loc in $azureLocations) {
                    $code = if ($script:AzureRegionCodes.ContainsKey($loc.Location.ToLower())) { 
                        $script:AzureRegionCodes[$loc.Location.ToLower()] 
                    } else { 
                        'N/A' 
                    }
                    Write-Host ("  {0,-25} {1,-35} ({2})" -f $loc.Location, $loc.DisplayName, $code) -ForegroundColor Gray
                }
                Write-Host ""
                continue
            }

            if ([string]::IsNullOrWhiteSpace($regionInput)) {
                $script:AzureRegion = $AzureRegion.ToLower()
                # Validate default region
                if ($azureLocations) {
                    $validLocation = $azureLocations | Where-Object { $_.Location.ToLower() -eq $script:AzureRegion }
                    if ($validLocation) {
                        $regionValid = $true
                        $code = $script:AzureRegionCodes[$script:AzureRegion]
                        $displayName = $script:AzureRegionDisplayNames[$script:AzureRegion]
                        Write-Host "  ✓ Using default: $($script:AzureRegion) - $displayName (Code: $code)" -ForegroundColor Green
                    } else {
                        Write-Host "  ✗ Default region '$($script:AzureRegion)' is not available in this subscription." -ForegroundColor Red
                        continue
                    }
                } else {
                    # Fallback validation: Check default against Microsoft CAF region list
                    if ($script:MicrosoftCAFRegionCodes.ContainsKey($script:AzureRegion)) {
                        $regionValid = $true
                        $code = $script:MicrosoftCAFRegionCodes[$script:AzureRegion]
                        Write-Host "  ✓ Using default: $($script:AzureRegion) (Code: $code)" -ForegroundColor Green
                        Write-Host "  ⚠ Note: Region validated against CAF standards only. Will verify with Azure on resource creation." -ForegroundColor Yellow
                    } else {
                        Write-Host "  ✗ Default region '$($script:AzureRegion)' is not found in Microsoft CAF standards." -ForegroundColor Red
                        Write-Host "  Please enter a valid Azure region." -ForegroundColor Gray
                        continue
                    }
                }
            }
            else {
                $normalizedInput = $regionInput.ToLower()
                if ($azureLocations) {
                    $validLocation = $azureLocations | Where-Object { $_.Location.ToLower() -eq $normalizedInput }
                    if ($validLocation) {
                        $script:AzureRegion = $normalizedInput
                        $regionValid = $true
                        $code = $script:AzureRegionCodes[$script:AzureRegion]
                        $displayName = $script:AzureRegionDisplayNames[$script:AzureRegion]
                        Write-Host "  ✓ Using: $($script:AzureRegion) - $displayName (Code: $code)" -ForegroundColor Green
                    } else {
                        Write-Host "  ✗ Invalid Azure region '$regionInput'. Not available in this subscription." -ForegroundColor Red
                        Write-Host "  Type 'list' to see all available regions" -ForegroundColor Gray
                    }
                } else {
                    # Fallback validation: Check against Microsoft CAF region list
                    if ($script:MicrosoftCAFRegionCodes.ContainsKey($normalizedInput)) {
                        $script:AzureRegion = $normalizedInput
                        $regionValid = $true
                        $code = $script:MicrosoftCAFRegionCodes[$normalizedInput]
                        Write-Host "  ✓ Using: $($script:AzureRegion) (Code: $code)" -ForegroundColor Green
                        Write-Host "  ⚠ Note: Region validated against CAF standards only. Will verify with Azure on resource creation." -ForegroundColor Yellow
                    } else {
                        Write-Host "  ✗ Invalid Azure region '$regionInput'. Not found in Microsoft CAF standards." -ForegroundColor Red
                        Write-Host "  Common regions: uksouth, ukwest, eastus, westus, northeurope, westeurope, switzerlandnorth" -ForegroundColor Gray
                        Write-Host "  Please enter a valid Azure region name." -ForegroundColor Gray
                    }
                }
            }
        }

        # Get Environment Index with validation
        $indexValid = $false
        while (-not $indexValid) {
            Write-Host ""
            Write-Host "Environment Index Number:" -ForegroundColor Cyan
            Write-Host "  Default: " -NoNewline -ForegroundColor Gray
            Write-Host "01" -ForegroundColor Yellow
            Write-Host "  (Use for multiple environments: 01, 02, 03, etc.)" -ForegroundColor Gray
            Write-Host "  Press Enter to use default, or type new value: " -NoNewline -ForegroundColor Gray
            $indexInput = Read-Host

            if ([string]::IsNullOrWhiteSpace($indexInput)) {
                $script:EnvironmentIndex = "01"
                $indexValid = $true
                Write-Host "  ✓ Using default: 01" -ForegroundColor Green
            }
            else {
                # Validate it's a number
                if ($indexInput -match '^\d+$') {
                    $indexNumber = [int]$indexInput
                    
                    # Validate range (01-99)
                    if ($indexNumber -ge 1 -and $indexNumber -le 99) {
                        $script:EnvironmentIndex = $indexNumber.ToString("00")
                        $indexValid = $true
                        Write-Host "  ✓ Using: $($script:EnvironmentIndex)" -ForegroundColor Green
                    }
                    else {
                        Write-Host "  ✗ Environment index must be between 01 and 99. Please try again." -ForegroundColor Red
                    }
                }
                else {
                    Write-Host "  ✗ Environment index must be a number. Please try again." -ForegroundColor Red
                }
            }
        }

        # Calculate resource group name based on inputs
        # Use Azure region codes from real-time lookup
        $regionAbbrev = if ($script:AzureRegionCodes -and $script:AzureRegionCodes.ContainsKey($script:AzureRegion.ToLower())) {
            $script:AzureRegionCodes[$script:AzureRegion.ToLower()].ToLower()
        } else {
            # Fallback: create smart abbreviation
            Write-Log "Creating abbreviation for region '$($script:AzureRegion)'" -Level Info
            if ($script:AzureRegion -match '([a-z]+)([0-9]+)') {
                $base = $Matches[1]
                $num = $Matches[2]
                ($base.Substring(0, [Math]::Min(3, $base.Length)) + $num).ToLower()
            } else {
                $script:AzureRegion.ToLower().Substring(0, [Math]::Min(3, $script:AzureRegion.Length))
            }
        }
        
        $defaultResourceGroupName = "rg-neo-$($script:OrganizationCode.ToLower())$($script:EnvironmentType)-$regionAbbrev-$($script:EnvironmentIndex)"

        # Get Resource Group Name with validation
        $rgNameValid = $false
        while (-not $rgNameValid) {
            Write-Host ""
            Write-Host "Resource Group Name:" -ForegroundColor Cyan
            Write-Host "  Default: " -NoNewline -ForegroundColor Gray
            Write-Host $defaultResourceGroupName -ForegroundColor Yellow
            Write-Host "  Press Enter to use default, or type new value: " -NoNewline -ForegroundColor Gray
            $rgInput = Read-Host

            if ([string]::IsNullOrWhiteSpace($rgInput)) {
                $script:ResourceGroupName = $defaultResourceGroupName
                $rgNameValid = $true
                Write-Host "  ✓ Using default: $defaultResourceGroupName" -ForegroundColor Green
            }
            else {
                # Validate length (1-90 characters)
                if ($rgInput.Length -lt 1 -or $rgInput.Length -gt 90) {
                    Write-Host "  ✗ Resource group name must be between 1 and 90 characters. Please try again." -ForegroundColor Red
                    continue
                }

                # Validate characters (alphanumerics, underscores, hyphens, periods, and parentheses)
                if ($rgInput -notmatch '^[\w\-\.\(\)]+$') {
                    Write-Host "  ✗ Resource group name can only contain alphanumerics, underscores, hyphens, periods, and parentheses. Please try again." -ForegroundColor Red
                    continue
                }

                # Validate doesn't end with period
                if ($rgInput -match '\.$') {
                    Write-Host "  ✗ Resource group name cannot end with a period. Please try again." -ForegroundColor Red
                    continue
                }

                $script:ResourceGroupName = $rgInput
                $rgNameValid = $true
                Write-Host "  ✓ Using: $rgInput" -ForegroundColor Green
            }
        }

        # Get Number of Bots with validation
        $botCountValid = $false
        while (-not $botCountValid) {
            Write-Host ""
            Write-Host "How many bots will there be?" -ForegroundColor Cyan
            Write-Host "  Default: " -NoNewline -ForegroundColor Gray
            Write-Host "1" -ForegroundColor Yellow
            Write-Host "  Press Enter to use default, or type new value: " -NoNewline -ForegroundColor Gray
            $botCountInput = Read-Host

            if ([string]::IsNullOrWhiteSpace($botCountInput)) {
                $script:BotCount = 1
                $botCountValid = $true
                Write-Host "  ✓ Using default: 1" -ForegroundColor Green
            }
            else {
                # Validate it's a number
                if ($botCountInput -match '^\d+$') {
                    $botNumber = [int]$botCountInput
                    
                    # Validate range (1-10)
                    if ($botNumber -ge 1 -and $botNumber -le 10) {
                        $script:BotCount = $botNumber
                        $botCountValid = $true
                        Write-Host "  ✓ Using: $($script:BotCount)" -ForegroundColor Green
                    }
                    else {
                        Write-Host "  ✗ Bot count must be between 1 and 10. Please try again." -ForegroundColor Red
                    }
                }
                else {
                    Write-Host "  ✗ Bot count must be a number. Please try again." -ForegroundColor Red
                }
            }
        }

        # Get Bot Names (Agent Name and Short Name for each bot)
        $script:BotConfigurations = @()
        for ($i = 1; $i -le $script:BotCount; $i++) {
            $defaultAgentName = if ($i -eq 1) { "bot" } else { "bot$i" }
            $agentNameValid = $false
            $agentName = ""
            
            # Get Agent Name
            while (-not $agentNameValid) {
                Write-Host ""
                Write-Host "Full Agent Name for Bot $i`:" -ForegroundColor Cyan
                Write-Host "  Default: " -NoNewline -ForegroundColor Gray
                Write-Host $defaultAgentName -ForegroundColor Yellow
                Write-Host "  Requirements: letters, numbers, spaces, dashes, and underscores allowed" -ForegroundColor Gray
                Write-Host "  Press Enter to use default, or type new value: " -NoNewline -ForegroundColor Gray
                $agentNameInput = Read-Host

                $agentName = if ([string]::IsNullOrWhiteSpace($agentNameInput)) {
                    $defaultAgentName
                } else {
                    $agentNameInput.Trim()
                }

                # Validate not empty
                if ([string]::IsNullOrWhiteSpace($agentName)) {
                    Write-Host "  ✗ Agent name cannot be empty. Please try again." -ForegroundColor Red
                    continue
                }

                # Validate characters (letters, numbers, spaces, dashes, and underscores)
                if ($agentName -notmatch '^[A-Za-z0-9 \-_]+$') {
                    Write-Host "  ✗ Agent name must contain only letters, numbers, spaces, dashes, and underscores. Please try again." -ForegroundColor Red
                    continue
                }

                # Check for duplicates
                if ($script:BotConfigurations | Where-Object { $_.AgentName -eq $agentName }) {
                    Write-Host "  ✗ Agent name '$agentName' is already used. Please choose a different name." -ForegroundColor Red
                    continue
                }

                $agentNameValid = $true
                Write-Host "  ✓ Using: $agentName" -ForegroundColor Green
            }

            # Get Bot Short Name
            $defaultBotShortName = if ($i -eq 1) { "bot" } else { "bot$i" }
            $botShortNameValid = $false
            
            while (-not $botShortNameValid) {
                Write-Host ""
                Write-Host "Bot $i Short Name:" -ForegroundColor Cyan
                Write-Host "  Default: " -NoNewline -ForegroundColor Gray
                Write-Host $defaultBotShortName -ForegroundColor Yellow
                Write-Host "  Requirements: lowercase, max 4 characters, letters and dashes only" -ForegroundColor Gray
                Write-Host "  Press Enter to use default, or type new value: " -NoNewline -ForegroundColor Gray
                $botShortNameInput = Read-Host

                $botShortName = if ([string]::IsNullOrWhiteSpace($botShortNameInput)) {
                    $defaultBotShortName
                } else {
                    $botShortNameInput.Trim()
                }

                # Validate lowercase
                if ($botShortName -cne $botShortName.ToLower()) {
                    Write-Host "  ✗ Bot short name must be lowercase. Please try again." -ForegroundColor Red
                    continue
                }

                # Validate length
                if ($botShortName.Length -lt 1 -or $botShortName.Length -gt 4) {
                    Write-Host "  ✗ Bot short name must be between 1 and 4 characters. Please try again." -ForegroundColor Red
                    continue
                }

                # Validate characters (lowercase letters and dashes only)
                if ($botShortName -notmatch '^[a-z][a-z\-]*$') {
                    Write-Host "  ✗ Bot short name must contain only lowercase letters and dashes, and must start with a letter. Please try again." -ForegroundColor Red
                    continue
                }

                # Check for duplicates
                if ($script:BotConfigurations | Where-Object { $_.ShortName -eq $botShortName }) {
                    Write-Host "  ✗ Bot short name '$botShortName' is already used. Please choose a different name." -ForegroundColor Red
                    continue
                }

                $botShortNameValid = $true
                Write-Host "  ✓ Using: $botShortName" -ForegroundColor Green
            }

            # Store both names for this bot
            $script:BotConfigurations += @{
                AgentName = $agentName
                ShortName = $botShortName
            }
        }

        $script:ConfigData['BotCount'] = $script:BotCount
        $script:ConfigData['Bots'] = $script:BotConfigurations

        # Calculate solution names based on configuration
        $script:ConfigData['SolutionName'] = "neo-$($script:OrganizationCode.ToLower())$($script:EnvironmentType)-$regionAbbrev-$($script:EnvironmentIndex)"
        $script:ConfigData['SolutionShortName'] = "neo$($script:OrganizationCode.ToLower())$($script:EnvironmentType)$regionAbbrev$($script:EnvironmentIndex)"

        # Display summary
        Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                                                               ║" -ForegroundColor Cyan
        Write-Host "║                   CONFIGURATION SUMMARY                       ║" -ForegroundColor Cyan
        Write-Host "║                                                               ║" -ForegroundColor Cyan
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Logged in User:       " -NoNewline; Write-Host $script:ConfigData['UserAccount'] -ForegroundColor Yellow
        Write-Host "  Tenant ID:            " -NoNewline; Write-Host $script:ConfigData['TenantId'] -ForegroundColor Yellow
        Write-Host "  Subscription Name:    " -NoNewline; Write-Host $script:ConfigData['SubscriptionName'] -ForegroundColor Yellow
        Write-Host "  Organization Name:    " -NoNewline; Write-Host $script:OrganizationName -ForegroundColor Yellow
        Write-Host "  Bot DNS Hostname:     " -NoNewline; Write-Host $script:Hostname -ForegroundColor Yellow
        Write-Host "  Bot DNS Domain Name:  " -NoNewline; Write-Host $script:DomainName -ForegroundColor Yellow
        Write-Host "  Organization Code:    " -NoNewline; Write-Host $script:OrganizationCode -ForegroundColor Yellow
        Write-Host "  Environment Type:     " -NoNewline; Write-Host $script:EnvironmentType -ForegroundColor Yellow
        Write-Host "  Environment Index:    " -NoNewline; Write-Host $script:EnvironmentIndex -ForegroundColor Yellow
        Write-Host "  Azure Region:         " -NoNewline; Write-Host $script:AzureRegion -ForegroundColor Yellow
        Write-Host "  Resource Group Name:  " -NoNewline; Write-Host $script:ResourceGroupName -ForegroundColor Yellow
        Write-Host "  Bot Count:            " -NoNewline; Write-Host $script:BotCount -ForegroundColor Yellow
        foreach ($bot in $script:BotConfigurations) {
            Write-Host "  Bot:                  " -NoNewline; Write-Host "$($bot.AgentName) (short: $($bot.ShortName))" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "Press Enter to continue with these settings, or Ctrl+C to cancel..." -ForegroundColor Yellow
        Read-Host

        # Save configuration to checkpoint now that it has been confirmed.
        # This allows a resume if any subsequent step fails (e.g. permission errors or provider timeouts).
        $script:CheckpointRegionAbbrev = $regionAbbrev
        Complete-OnboardingStep 'ConfigGathered'

        } else {
            # Resume path: restore the region abbreviation local variable from checkpoint data.
            $regionAbbrev = $script:CheckpointRegionAbbrev

            Write-Host "`n  ⏩ Configuration restored from checkpoint — skipping input prompts" -ForegroundColor Gray
            Write-Host "     Org: $($script:OrganizationCode)  |  Env: $($script:EnvironmentType)  |  Region: $($script:AzureRegion)" -ForegroundColor Cyan
            Write-Host "     Resource Group: $($script:ResourceGroupName)  |  Bots: $($script:BotCount)" -ForegroundColor Cyan
            Write-Host ""
        }

        # Step 6.5: Quota pre-flight checks
        Test-QuotaRequirements -Location $script:AzureRegion -SubscriptionId $script:ConfigData['SubscriptionId']

        # Step 7: Create resource group
        $null = New-NeologikResourceGroup -ResourceGroupName $script:ResourceGroupName -Location $script:AzureRegion

        # Step 8: Invite guest users
        $guestUsers = Invoke-GuestUserInvitation -GuestEmails $script:NeologikGuestUsers

        # Step 9: Create security groups (includes logged-in user + guest users)
        # Extract agent names for group creation
        $agentNames = $script:BotConfigurations | ForEach-Object { $_.AgentName }
        $securityGroups = New-NeologikSecurityGroups -GuestUsers $guestUsers -OrganizationCode $script:OrganizationCode -EnvironmentType $script:EnvironmentType -BotNames $agentNames

        # Step 10: Assign roles to security groups
        Set-NeologikRoleAssignments -SecurityGroups $securityGroups -SubscriptionId $script:ConfigData['SubscriptionId'] -ResourceGroupName $script:ResourceGroupName

        # Step 11: Create App Registration
        $appReg = New-NeologikAppRegistration -OrganizationCode $script:OrganizationCode -EnvironmentType $script:EnvironmentType
        Set-AppRegistrationRoles -ServicePrincipalId $appReg.ServicePrincipal.Id `
            -SubscriptionId $script:ConfigData['SubscriptionId'] `
            -ResourceGroupName $script:ResourceGroupName `
            -SecurityGroups $securityGroups

        # Step 12: Create Key Vault and store client secret
        $keyVaultName = "kvneo$($script:OrganizationCode.ToLower())$($script:EnvironmentType)$($script:EnvironmentIndex)"
        
        # Key Vault names must be 3-24 characters, only alphanumeric and hyphens
        if ($keyVaultName.Length -gt 24) {
            Write-Log "Key Vault name too long, truncating to 24 characters" -Level Warning
            $keyVaultName = $keyVaultName.Substring(0, 24)
        }
        
        $null = New-NeologikKeyVault -ResourceGroupName $script:ResourceGroupName `
            -Location $script:AzureRegion `
            -KeyVaultName $keyVaultName `
            -ClientSecret $appReg.Secret `
            -SecurityGroups $securityGroups `
            -SubscriptionId $script:ConfigData['SubscriptionId']

        # Step 13: Register all required Azure resource providers
        Register-AllResourceProviders
        Complete-OnboardingStep 'ResourceProviders'

        # Step 14: Create Storage Account and blob container for certificates
        $storageAccountName = "stneodeploy$($script:OrganizationCode.ToLower())$($script:EnvironmentType)$regionAbbrev$($script:EnvironmentIndex)"
        
        # Storage account names must be 3-24 characters, lowercase alphanumeric only
        if ($storageAccountName.Length -gt 24) {
            Write-Log "Storage Account name too long, truncating to 24 characters" -Level Warning
            $storageAccountName = $storageAccountName.Substring(0, 24)
        }
        
        $null = New-NeologikStorageAccount -ResourceGroupName $script:ResourceGroupName `
            -Location $script:AzureRegion `
            -StorageAccountName $storageAccountName `
            -SecurityGroups $securityGroups

        # Step 15: Create Managed Identities
        $null = New-NeologikManagedIdentities -ResourceGroupName $script:ResourceGroupName `
            -Location $script:AzureRegion `
            -SubscriptionId $script:ConfigData['SubscriptionId'] `
            -OrganizationCode $script:OrganizationCode `
            -EnvironmentType $script:EnvironmentType

        # Step 16: Export configuration
        Export-ConfigurationData

        # Remove checkpoint on successful completion — no longer needed
        if ($script:CheckpointFile -and (Test-Path $script:CheckpointFile)) {
            Remove-Item $script:CheckpointFile -ErrorAction SilentlyContinue
            Write-Log "Checkpoint file removed after successful completion" -Level Info
        }

        Write-Log "Neologik onboarding completed successfully!" -Level Success
    }
    catch {
        Write-Log "Onboarding failed: $_" -Level Error
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error

        if ($_.Exception.Message -match "Insufficient permissions:|ERROR: Insufficient permissions") {
            Write-Host "`n❌ Onboarding stopped: insufficient permissions." -ForegroundColor Red
            Write-Host "   See the error details above for the specific permission required." -ForegroundColor Yellow
            if ($script:CheckpointFile -and (Test-Path $script:CheckpointFile)) {
                Write-Host ""
                Write-Host "  ✓ Your configuration has been saved as a checkpoint." -ForegroundColor Green
                Write-Host "    Once permissions are granted, re-run the script and choose 'Y' to resume" -ForegroundColor Cyan
                Write-Host "    from where you left off — no need to re-enter configuration." -ForegroundColor Cyan
            }
            Write-Host ""
            exit 2
        }
        else {
            Write-Host "`n❌ Onboarding failed. Please check the log file for details:" -ForegroundColor Red
            Write-Host "   $script:LogFile" -ForegroundColor Yellow
            if ($script:CheckpointFile -and (Test-Path $script:CheckpointFile)) {
                Write-Host ""
                Write-Host "  ✓ Your configuration has been saved as a checkpoint." -ForegroundColor Green
                Write-Host "    Re-run the script and choose 'Y' to resume from where you left off." -ForegroundColor Cyan
            }
            Write-Host ""
            exit 1
        }
    }
}

# Execute main function
Start-NeologikOnboarding

#endregion
