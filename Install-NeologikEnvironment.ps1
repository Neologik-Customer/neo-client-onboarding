<#
.SYNOPSIS
    Automated Neologik customer onboarding script for Azure environment setup.

.DESCRIPTION
    This script automates the complete onboarding process for Neologik customers, including:
    - PowerShell version validation and updates
    - Azure authentication with required permissions
    - Guest user invitations
    - Subscription, resource group, and security group creation
    - App registration and managed identity setup
    - Role assignments
    - Configuration output and logging

.VERSION
    v1.5.2

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
$script:Version = 'v1.5.2'

$script:LogFile = Join-Path $PSScriptRoot "NeologikOnboarding_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:OutputFile = Join-Path $PSScriptRoot "NeologikConfiguration_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$script:ConfigData = @{}

# Neologik guest user emails
$script:NeologikGuestUsers = @(
    'bryan.lloyd@neologik.ai',
    'rupert.fawcett@neologik.ai',
    'Jashanpreet.Magar@neologik.ai',
    'leon.simpson@neologik.ai',
    'gael.abruzzese@neologik.ai'
)

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

   - Terms of Use: https://www.neologik.ai/terms-of-use
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
        
        if ($currentContext -and $currentContext.Account) {
            Write-Log "Already connected to Azure as $($currentContext.Account.Id)" -Level Info
            
            # If TenantId is specified and different, reconnect
            if ($TenantId -and $currentContext.Tenant.Id -ne $TenantId) {
                Write-Log "Switching to specified tenant: $TenantId" -Level Info
                $azContext = Connect-AzAccount -TenantId $TenantId -ErrorAction Stop
            }
            else {
                $azContext = [PSCustomObject]@{
                    Context = $currentContext
                }
                Write-Log "Using existing Azure connection" -Level Success
            }
        }
        else {
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
        
        if ($mgContext -and $mgContext.TenantId -eq $script:ConfigData['TenantId']) {
            Write-Log "Already connected to Microsoft Graph for tenant $($mgContext.TenantId)" -Level Info
            Write-Host "`n✓ Microsoft Graph: Using existing connection (Account: $($mgContext.Account))`n" -ForegroundColor Green
        }
        else {
            # Disconnect any existing Graph connection first
            if ($mgContext) {
                Write-Log "Disconnecting from existing Microsoft Graph session (different tenant)" -Level Info
                Disconnect-MgGraph -ErrorAction SilentlyContinue
            }
            
            # Connect to Microsoft Graph using device code authentication
            Write-Log "Connecting to Microsoft Graph..." -Level Info
            Write-Host "`n" -ForegroundColor Cyan
            
            Connect-MgGraph -TenantId $script:ConfigData['TenantId'] `
                -Scopes "User.ReadWrite.All", "Group.ReadWrite.All", "Application.ReadWrite.All", "Directory.ReadWrite.All", "RoleManagement.ReadWrite.Directory" `
                -UseDeviceAuthentication `
                -ErrorAction Stop
            Write-Log "Connected to Microsoft Graph" -Level Success
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
        $userId = (Get-MgUser -UserId $script:ConfigData['UserAccount']).Id
        $globalAdminRole = Get-MgDirectoryRole -Filter "displayName eq 'Global Administrator'"
        
        if (-not $globalAdminRole) {
            # Activate the role template if not activated
            $roleTemplate = Get-MgDirectoryRoleTemplate -Filter "displayName eq 'Global Administrator'"
            $globalAdminRole = New-MgDirectoryRole -RoleTemplateId $roleTemplate.Id
        }

        $adminMembers = Get-MgDirectoryRoleMember -DirectoryRoleId $globalAdminRole.Id
        $isGlobalAdmin = $adminMembers | Where-Object { $_.Id -eq $userId }

        if ($isGlobalAdmin) {
            Write-Log "User has Global Administrator role" -Level Success
        }
        else {
            throw "User does not have Global Administrator role. Global Administrator role is required."
        }

        Write-Log "All required permissions validated successfully" -Level Success
        return $true
    }
    catch {
        Write-Log "Permission validation failed: $_" -Level Error
        throw
    }
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
        [string[]]$GuestEmails
    )

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
        [array]$GuestUsers,

        [Parameter(Mandatory = $false)]
        [string]$OrganizationCode = "",

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentType = ""
    )

    Write-Log "Creating Neologik security groups..." -Level Info

    try {
        Import-Module Microsoft.Graph.Groups -ErrorAction Stop

        # Build group names with organization code and environment type (lowercase)
        $orgLower = $OrganizationCode.ToLower()
        $envLower = if ([string]::IsNullOrWhiteSpace($EnvironmentType)) { "" } else { "-$($EnvironmentType.ToLower())" }
        $groupSuffix = if ([string]::IsNullOrWhiteSpace($OrganizationCode)) { "" } else { " - $orgLower$envLower" }

        $groups = @(
            @{
                Name = "Neologik User Group$groupSuffix"
                Description = 'Normal Neologik users for Teams app access'
            },
            @{
                Name = "Neologik NCE User Group$groupSuffix"
                Description = 'Users who need access to NCE web tool'
            },
            @{
                Name = "Neologik Admin User Group$groupSuffix"
                Description = 'Users who will administer and support the resources'
            }
        )

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

            # Add guest users to the group
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
        [string]$SubscriptionId
    )

    Write-Log "Assigning roles to security groups..." -Level Info

    try {
        # Find the Admin group (matches with or without suffix)
        $adminGroup = $SecurityGroups | Where-Object { $_.Name -like 'Neologik Admin User Group*' }

        if (-not $adminGroup) {
            throw "Neologik Admin User Group not found"
        }

        Write-Log "Assigning Contributor role to $($adminGroup.Name)..." -Level Info

        # Check if role assignment already exists
        $existingAssignment = Get-AzRoleAssignment -ObjectId $adminGroup.Id `
            -RoleDefinitionName 'Contributor' `
            -Scope "/subscriptions/$SubscriptionId" `
            -ErrorAction SilentlyContinue

        if ($existingAssignment) {
            Write-Log "Contributor role already assigned to $($adminGroup.Name)" -Level Info
        }
        else {
            # Add retry logic for newly created security groups
            $retryCount = 0
            $maxRetries = 10
            $roleAssigned = $false

            while (-not $roleAssigned -and $retryCount -lt $maxRetries) {
                try {
                    New-AzRoleAssignment -ObjectId $adminGroup.Id `
                        -RoleDefinitionName 'Contributor' `
                        -Scope "/subscriptions/$SubscriptionId" `
                        -ErrorAction Stop | Out-Null

                    Write-Log "Contributor role assigned successfully" -Level Success
                    $roleAssigned = $true
                }
                catch {
                    if ($_.Exception.Message -match "does not exist|cannot be found|BadRequest") {
                        $retryCount++
                        if ($retryCount -lt $maxRetries) {
                            Write-Log "Security group not yet replicated. Retrying in 10 seconds... (Attempt $retryCount of $maxRetries)" -Level Warning
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

        $script:ConfigData['RoleAssignments'] = @(
            @{
                Principal = $adminGroup.Name
                PrincipalType = 'Security Group'
                Role = 'Contributor'
                Scope = 'Subscription'
            },
            @{
                Principal = $adminGroup.Name
                PrincipalType = 'Security Group'
                Role = 'Key Vault Secrets Officer'
                Scope = 'Resource Group'
            },
            @{
                Principal = $adminGroup.Name
                PrincipalType = 'Security Group'
                Role = 'Storage Blob Data Contributor'
                Scope = 'Resource Group'
            }
        )

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
            SubscriptionRoles = @('Contributor', 'User Access Administrator')
            EntraRole = 'Application Administrator'
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
        $roles = @('Contributor', 'User Access Administrator')

        foreach ($roleName in $roles) {
            Write-Log "Assigning $roleName role..." -Level Info

            $existingAssignment = Get-AzRoleAssignment -ObjectId $ServicePrincipalId `
                -RoleDefinitionName $roleName `
                -Scope "/subscriptions/$SubscriptionId" `
                -ErrorAction SilentlyContinue

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

        # Assign Entra ID role (Application Administrator)
        Write-Log "Assigning Application Administrator role in Entra ID..." -Level Info
        
        try {
            Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop
            
            $appAdminRole = Get-MgDirectoryRole -Filter "displayName eq 'Application Administrator'" -ErrorAction SilentlyContinue
            
            if (-not $appAdminRole) {
                $roleTemplate = Get-MgDirectoryRoleTemplate -Filter "displayName eq 'Application Administrator'" -ErrorAction Stop
                if (-not $roleTemplate) {
                    throw "InsufficientPermissions"
                }
                $appAdminRole = New-MgDirectoryRole -RoleTemplateId $roleTemplate.Id -ErrorAction Stop
            }

            if (-not $appAdminRole -or [string]::IsNullOrEmpty($appAdminRole.Id)) {
                throw "InsufficientPermissions"
            }

            $existingRoleMember = Get-MgDirectoryRoleMember -DirectoryRoleId $appAdminRole.Id -ErrorAction SilentlyContinue | Where-Object { $_.Id -eq $ServicePrincipalId }
        }
        catch {
            if ($_.Exception.Message -match "InsufficientPermissions|Insufficient privileges|Authorization_RequestDenied|Forbidden|Request_UnsupportedQuery|BadRequest") {
                Write-Log "ERROR: Insufficient permissions to assign Application Administrator role" -Level Error
                Write-Log "Required Permission: Global Administrator or Privileged Role Administrator role in Entra ID" -Level Error
                Write-Host "`n❌ PERMISSION ERROR" -ForegroundColor Red
                Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Red
                Write-Host ""
                Write-Host "You do not have sufficient permissions to complete this setup." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "Required Permissions:" -ForegroundColor Cyan
                Write-Host "  ✓ Owner role at subscription level" -ForegroundColor Gray
                Write-Host "  ✗ Global Administrator role in Entra ID (MISSING)" -ForegroundColor Red
                Write-Host ""
                Write-Host "Please contact a user with Global Administrator permissions to run this script." -ForegroundColor Yellow
                Write-Host ""
                throw "Insufficient permissions: Global Administrator role required"
            }
            else {
                throw
            }
        }

        if ($existingRoleMember) {
            Write-Log "Application Administrator role already assigned" -Level Info
        }
        else {
            # Add retry logic for newly created service principals
            $retryCount = 0
            $maxRetries = 10
            $roleAssigned = $false

            while (-not $roleAssigned -and $retryCount -lt $maxRetries) {
                try {
                    # Use New-MgDirectoryRoleMemberByRef instead of New-MgDirectoryRoleMember
                    $body = @{
                        "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$ServicePrincipalId"
                    }
                    New-MgDirectoryRoleMemberByRef -DirectoryRoleId $appAdminRole.Id -BodyParameter $body -ErrorAction Stop
                    Write-Log "Application Administrator role assigned successfully" -Level Success
                    $roleAssigned = $true
                }
                catch {
                    # Check if it's a permission error (Forbidden/Authorization)
                    if ($_.Exception.Message -match "Forbidden|Authorization_RequestDenied|Insufficient privileges") {
                        Write-Log "ERROR: Insufficient permissions to assign Application Administrator role" -Level Error
                        Write-Log "Required Permission: Global Administrator or Privileged Role Administrator role in Entra ID" -Level Error
                        Write-Host "`n❌ PERMISSION ERROR" -ForegroundColor Red
                        Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Red
                        Write-Host ""
                        Write-Host "You do not have sufficient permissions to complete this setup." -ForegroundColor Yellow
                        Write-Host ""
                        Write-Host "Required Permissions:" -ForegroundColor Cyan
                        Write-Host "  ✓ Owner role at subscription level" -ForegroundColor Gray
                        Write-Host "  ✗ Global Administrator role in Entra ID (MISSING)" -ForegroundColor Red
                        Write-Host ""
                        Write-Host "Please contact a user with Global Administrator permissions to run this script." -ForegroundColor Yellow
                        Write-Host ""
                        throw "Insufficient permissions: Global Administrator role required"
                    }
                    # Handle case where member already exists (race condition or previous partial run)
                    elseif ($_.Exception.Message -match "already exist") {
                        Write-Log "Application Administrator role already assigned (detected on add)" -Level Info
                        $roleAssigned = $true
                    }
                    elseif ($_.Exception.Message -match "does not exist|cannot be found|not found") {
                        $retryCount++
                        if ($retryCount -lt $maxRetries) {
                            Write-Log "Service Principal not yet replicated to Entra ID. Retrying in 10 seconds... (Attempt $retryCount of $maxRetries)" -Level Warning
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

        # Assign Key Vault Secrets Officer role to Neologik Admin User Group at Resource Group level
        $adminGroup = $SecurityGroups | Where-Object { $_.Name -like 'Neologik Admin User Group*' }
        
        if ($adminGroup) {
            Write-Log "Assigning Key Vault Secrets Officer role to $($adminGroup.Name) at Resource Group level..." -Level Info
            
            $existingAssignment = Get-AzRoleAssignment -ObjectId $adminGroup.Id `
                -RoleDefinitionName 'Key Vault Secrets Officer' `
                -Scope $rgScope `
                -ErrorAction SilentlyContinue

            if ($existingAssignment) {
                Write-Log "Key Vault Secrets Officer role already assigned to $($adminGroup.Name) at Resource Group level" -Level Info
            }
            else {
                New-AzRoleAssignment -ObjectId $adminGroup.Id `
                    -RoleDefinitionName 'Key Vault Secrets Officer' `
                    -Scope $rgScope `
                    -ErrorAction Stop | Out-Null

                Write-Log "Key Vault Secrets Officer role assigned to $($adminGroup.Name) at Resource Group level successfully" -Level Success
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
        $containerName = "certificate"
        
        $existingContainer = Get-AzStorageContainer -Name $containerName -Context $ctx -ErrorAction SilentlyContinue

        if ($existingContainer) {
            Write-Log "Blob container '$containerName' already exists" -Level Info
        }
        else {
            New-AzStorageContainer -Name $containerName -Context $ctx -Permission Off -ErrorAction Stop | Out-Null
            Write-Log "Blob container '$containerName' created successfully" -Level Success
        }

        # Get resource group scope for role assignments
        $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
        $rgScope = $resourceGroup.ResourceId

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
            ContainerName = $containerName
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
        Creates User Assigned Managed Identities.
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
        $envLower = if ([string]::IsNullOrWhiteSpace($EnvironmentType)) { "" } else { "-$($EnvironmentType.ToLower())" }
        $nameSuffix = if ([string]::IsNullOrWhiteSpace($OrganizationCode)) { "" } else { "-$orgLower$envLower" }
        $displaySuffix = if ([string]::IsNullOrWhiteSpace($OrganizationCode)) { "" } else { " - $orgLower$envLower" }

        $managedIdentities = @(
            @{
                Name = "neologik-script-runner-service-connection$nameSuffix"
                DisplayName = "Neologik Script Runner Service Connection$displaySuffix"
                Roles = @('Contributor')
                EntraRole = 'Application Administrator'
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

            # Assign subscription roles
            foreach ($roleName in $miDef.Roles) {
                Write-Log "Assigning $roleName role to $displayName..." -Level Info

                $existingAssignment = Get-AzRoleAssignment -ObjectId $mi.PrincipalId `
                    -RoleDefinitionName $roleName `
                    -Scope "/subscriptions/$SubscriptionId" `
                    -ErrorAction SilentlyContinue

                if ($existingAssignment) {
                    Write-Log "$roleName role already assigned" -Level Info
                }
                else {
                    # Add retry logic as role assignment might need time after MI creation
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

            $createdIdentities += @{
                Name = $mi.Name
                PrincipalId = $mi.PrincipalId
                ClientId = $mi.ClientId
                ResourceId = $mi.Id
                SubscriptionRoles = $miDef.Roles
                EntraRole = $miDef.EntraRole
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
            Write-Host "  Container Name: $($script:ConfigData['StorageAccount'].ContainerName)"
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
        Write-Host "  Configuration: $script:OutputFile" -ForegroundColor Cyan
        Write-Host "  Log File: $script:LogFile" -ForegroundColor Cyan
        Write-Host ""

        Write-Host "⚠️  Next Steps:" -ForegroundColor Yellow
        Write-Host "  1. Review the configuration file and share it with Neologik"
        Write-Host "  2. Service principal client secret is securely stored in Key Vault: $($script:ConfigData['KeyVault'].Name)"
        Write-Host "     Secret name: $($script:ConfigData['KeyVault'].SecretName)"
        Write-Host "  3. Upload your TLS certificate (.pfx file) to Storage Account blob container:"
        Write-Host "     Storage Account: $($script:ConfigData['StorageAccount'].Name)"
        Write-Host "     Container: $($script:ConfigData['StorageAccount'].ContainerName)"
        Write-Host "  4. Store the certificate PFX password in Key Vault as a secret:"
        Write-Host "     Secret name: 'neologik-deployment-certificate-pfx-secret'"
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
        Write-ScriptHeader

        # Step 0: Show Terms and Conditions and get acceptance
        $termsAccepted = Show-TermsAndConditions
        if (-not $termsAccepted) {
            Write-Log "Installation cancelled by user - terms not accepted" -Level Warning
            exit 0
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
                # Disconnect current session
                Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
                Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            }
            else {
                Write-Host "Continuing with current connection..." -ForegroundColor Green
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

        # Step 6: Collect remaining configuration inputs
        Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
        Write-Host "║                                                               ║" -ForegroundColor Magenta
        Write-Host "║                   CONFIGURATION SETUP                         ║" -ForegroundColor Magenta
        Write-Host "║      Please review and confirm the following settings         ║" -ForegroundColor Magenta
        Write-Host "║                                                               ║" -ForegroundColor Magenta
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta

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

        # Get Organization Code with validation
        $orgCodeValid = $false
        while (-not $orgCodeValid) {
            Write-Host ""
            Write-Host "Organization Code (exactly 3 characters):" -ForegroundColor Cyan
            Write-Host "  Default: " -NoNewline -ForegroundColor Gray
            Write-Host $OrganizationCode -ForegroundColor Yellow
            Write-Host "  Press Enter to use default, or type new value: " -NoNewline -ForegroundColor Gray
            $orgInput = Read-Host

            if ([string]::IsNullOrWhiteSpace($orgInput)) {
                $script:OrganizationCode = $OrganizationCode
            }
            else {
                $script:OrganizationCode = $orgInput
            }

            # Validate length
            if ($script:OrganizationCode.Length -ne 3) {
                Write-Host "  ✗ Organization code must be exactly 3 characters. Please try again." -ForegroundColor Red
                continue
            }

            # Validate alphanumeric
            if ($script:OrganizationCode -notmatch '^[a-zA-Z0-9]{3}$') {
                Write-Host "  ✗ Organization code must contain only letters and numbers. Please try again." -ForegroundColor Red
                continue
            }

            $orgCodeValid = $true
            Write-Host "  ✓ Using: $($script:OrganizationCode)" -ForegroundColor Green
        }

        # Get Environment Type with validation
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
                $script:EnvironmentType = $EnvironmentType
                $envTypeValid = $true
                Write-Host "  ✓ Using default: $EnvironmentType" -ForegroundColor Green
            }
            elseif ($envInput -eq 'dev' -or $envInput -eq 'prd') {
                $script:EnvironmentType = $envInput
                $envTypeValid = $true
                Write-Host "  ✓ Using: $envInput" -ForegroundColor Green
            }
            else {
                Write-Host "  ✗ Invalid environment type. Must be 'dev' or 'prd'. Please try again." -ForegroundColor Red
            }
        }

        # Get Azure Region with validation
        $regionValid = $false
        $validRegions = @('uksouth', 'ukwest', 'eastus', 'westus', 'eastus2', 'westus2', 'northeurope', 'westeurope', 
                          'centralus', 'southcentralus', 'westcentralus', 'northcentralus', 'eastasia', 'southeastasia',
                          'japaneast', 'japanwest', 'australiaeast', 'australiasoutheast', 'canadacentral', 'canadaeast')
        
        while (-not $regionValid) {
            Write-Host ""
            Write-Host "Azure Region:" -ForegroundColor Cyan
            Write-Host "  Default: " -NoNewline -ForegroundColor Gray
            Write-Host $AzureRegion -ForegroundColor Yellow
            Write-Host "  Common regions: uksouth, ukwest, eastus, westus, northeurope, westeurope" -ForegroundColor Gray
            Write-Host "  Press Enter to use default, or type new value: " -NoNewline -ForegroundColor Gray
            $regionInput = Read-Host

            if ([string]::IsNullOrWhiteSpace($regionInput)) {
                $script:AzureRegion = $AzureRegion
                $regionValid = $true
                Write-Host "  ✓ Using default: $AzureRegion" -ForegroundColor Green
            }
            elseif ($validRegions -contains $regionInput.ToLower()) {
                $script:AzureRegion = $regionInput.ToLower()
                $regionValid = $true
                Write-Host "  ✓ Using: $($script:AzureRegion)" -ForegroundColor Green
            }
            else {
                Write-Host "  ✗ Invalid Azure region. Please use a valid Azure region name (e.g., uksouth, eastus). Please try again." -ForegroundColor Red
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
        # Map region names to abbreviations
        $regionAbbreviations = @{
            'uksouth' = 'uks'
            'ukwest' = 'ukw'
            'eastus' = 'eus'
            'westus' = 'wus'
            'northeurope' = 'neu'
            'westeurope' = 'weu'
        }
        
        $regionAbbrev = if ($regionAbbreviations.ContainsKey($script:AzureRegion.ToLower())) {
            $regionAbbreviations[$script:AzureRegion.ToLower()]
        } else {
            # If no mapping exists, use first 3 characters
            $script:AzureRegion.ToLower().Substring(0, [Math]::Min(3, $script:AzureRegion.Length))
        }
        
        $defaultResourceGroupName = "rg-neo-$($script:OrganizationCode.ToLower())-$($script:EnvironmentType)-$regionAbbrev-$($script:EnvironmentIndex)"

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

        # Calculate solution names based on configuration
        $script:ConfigData['SolutionName'] = "neo-$($script:OrganizationCode.ToLower())-$($script:EnvironmentType)-$regionAbbrev-$($script:EnvironmentIndex)"
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
        Write-Host "  Organization Code:    " -NoNewline; Write-Host $script:OrganizationCode -ForegroundColor Yellow
        Write-Host "  Environment Type:     " -NoNewline; Write-Host $script:EnvironmentType -ForegroundColor Yellow
        Write-Host "  Environment Index:    " -NoNewline; Write-Host $script:EnvironmentIndex -ForegroundColor Yellow
        Write-Host "  Azure Region:         " -NoNewline; Write-Host $script:AzureRegion -ForegroundColor Yellow
        Write-Host "  Resource Group Name:  " -NoNewline; Write-Host $script:ResourceGroupName -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Press Enter to continue with these settings, or Ctrl+C to cancel..." -ForegroundColor Yellow
        Read-Host

        # Step 7: Create resource group
        $null = New-NeologikResourceGroup -ResourceGroupName $script:ResourceGroupName -Location $script:AzureRegion

        # Step 8: Invite guest users
        $guestUsers = Invoke-GuestUserInvitation -GuestEmails $script:NeologikGuestUsers

        # Step 9: Create security groups (includes logged-in user + guest users)
        $securityGroups = New-NeologikSecurityGroups -GuestUsers $guestUsers -OrganizationCode $script:OrganizationCode -EnvironmentType $script:EnvironmentType

        # Step 10: Assign roles to security groups
        Set-NeologikRoleAssignments -SecurityGroups $securityGroups -SubscriptionId $script:ConfigData['SubscriptionId']

        # Step 11: Create App Registration
        $appReg = New-NeologikAppRegistration -OrganizationCode $script:OrganizationCode -EnvironmentType $script:EnvironmentType
        Set-AppRegistrationRoles -ServicePrincipalId $appReg.ServicePrincipal.Id `
            -SubscriptionId $script:ConfigData['SubscriptionId'] `
            -SecurityGroups $securityGroups

        # Step 12: Create Key Vault and store client secret
        $keyVaultName = "kvneodeploy$($script:OrganizationCode.ToLower())$($script:EnvironmentType)$regionAbbrev$($script:EnvironmentIndex)"
        
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

        # Step 13: Create Storage Account and blob container for certificates
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

        # Step 14: Create Managed Identities
        $null = New-NeologikManagedIdentities -ResourceGroupName $script:ResourceGroupName `
            -Location $script:AzureRegion `
            -SubscriptionId $script:ConfigData['SubscriptionId'] `
            -OrganizationCode $script:OrganizationCode `
            -EnvironmentType $script:EnvironmentType

        # Step 15: Export configuration
        Export-ConfigurationData

        Write-Log "Neologik onboarding completed successfully!" -Level Success
    }
    catch {
        Write-Log "Onboarding failed: $_" -Level Error
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Error
        
        # Check if this is a permission error to set appropriate exit code
        if ($_.Exception.Message -match "Insufficient permissions:|ERROR: Insufficient permissions") {
            exit 2  # Exit code 2 = Permission error
        }
        else {
            Write-Host "`n❌ Onboarding failed. Please check the log file for details:" -ForegroundColor Red
            Write-Host "   $script:LogFile" -ForegroundColor Yellow
            Write-Host ""
            
            exit 1  # Exit code 1 = General error
        }
    }
}

# Execute main function
Start-NeologikOnboarding

#endregion
