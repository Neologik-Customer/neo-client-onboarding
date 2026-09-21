<#
.SYNOPSIS
    Automated Neologik customer onboarding script for Azure environment setup.

.DESCRIPTION
    This script automates the complete onboarding process for Neologik customers, including:
    - PowerShell version validation and updates
    - Azure authentication with required permissions
    - Role validation (Subscription Owner and Global Administrator)
    - Guest user invitations
    - Subscription, resource group, and security group creation
    - App registration and managed identity setup
    - Role assignments
    - Configuration output and logging

.VERSION
    v5.0.0

.PARAMETER OrganizationCode
    3-character organization code (e.g., 'ABC'). Default: 'ORG'

.PARAMETER EnvironmentType
    Environment type: 'dev' or 'prd'. Default: 'dev'

.PARAMETER AzureRegion
    Azure region for resource deployment. Default: 'uksouth'

.PARAMETER TenantId
    Azure Tenant ID. If not provided, will use current context.

.PARAMETER SubscriptionName
    Name of the Azure subscription to onboard into. When supplied, the script
    selects it after sign-in and stops if this login cannot see it. When
    omitted, the subscription of the current Azure context is used. On a
    resumed run the checkpoint's subscription wins.

.PARAMETER KeyVaultName
    Override the Key Vault name. If omitted, the standard name
    'kv<solution short name>' (kvneo<org><index>, e.g. kvneoabc01) is
    generated automatically. Must be 3-24 characters, start with a letter,
    end with a letter or digit, and contain only letters, digits and hyphens.

.PARAMETER SkipPowerShellUpdate
    Skip PowerShell version check and update.

.PARAMETER SkipModuleInstall
    Skip Azure module installation check.

.PARAMETER SkipGuestInvitation
    Skip inviting Neologik guest users. Use when the client provisions its own
    accounts within its own tenant (no B2B guests). Security groups are still
    created, seeded with the signed-in user only - unless the follow-up
    add-existing-accounts step is used (see below). May also be set from the answer
    file ('skipGuestInvitation': true/false); this switch, when passed, takes
    precedence.

    When invitations are ACCEPTED interactively, the file's addresses are listed
    and a follow-up offers to add more addresses to invite, typed one per line
    (blank line to finish, commas accepted within a line) - with an empty or
    missing file the whole invite list can be typed. Unattended runs use the
    file only.

    When invitations are skipped, a follow-up question offers to add EXISTING
    accounts (pre-created B2B guests or member accounts) to the security groups
    without sending any invitation. Answer-file keys: 'addExistingAccountsToGroups'
    (true/false) and optionally 'existingAccountEmails' (array or comma-separated
    string; defaults to the NeologikGuestUsers.txt entries, or addresses typed at
    the prompt one per line - blank line to finish, commas accepted within a
    line). Each address must match the account's mail or userPrincipalName;
    an address with no matching account is reported and skipped - the run always
    continues. Accounts added this way join ALL Neologik groups, including the
    Admin User Group.

.PARAMETER ExistingServicePrincipalObjectId
    Object ID (enterprise-application / service-principal object ID, not the app/client
    ID) of a pre-existing service principal supplied by the client. When provided, the
    script does NOT create an app registration, service principal, or client secret, but
    it still assigns the required resource-group-scoped roles and Graph application
    permissions to the SP (the operator is Owner + Global Admin, so it can grant these
    whether the SP was created here or supplied by the client). The script resolves the
    SP's client (app) ID for the configuration output.
    The decision may also be driven from the answer file ('useExistingServicePrincipal':
    true/false, with 'existingServicePrincipalObjectId'); this CLI parameter, when passed,
    takes precedence. With neither, an interactive y/N prompt (default N) is shown.

.PARAMETER ExistingServicePrincipalSecret
    Client secret for the pre-existing service principal (shared by the client). Stored
    in Key Vault as 'neologik-deployment-service-principle-secret' for the deployment
    pipeline. Optional: if omitted, the Key Vault is still created but the secret is not
    stored - the client must add it manually before the first deployment. Only meaningful
    together with -ExistingServicePrincipalObjectId. May also be supplied from the answer
    file ('existingServicePrincipalSecret'), but the CLI parameter is preferred so the
    secret is not persisted to disk.

.PARAMETER NonInteractive
    CI / unattended mode. Requires a fully-populated answer file (see -AnswerFile);
    every interactive gate either resolves from switches/answer keys or throws instead
    of prompting: Terms acceptance needs -AcceptTerms, an existing Az/Graph context is
    always reused (no re-auth prompt), the configuration summary is not confirmed, a
    leftover checkpoint without -FreshRun is an error, and warn-and-prompt checks
    (Global Administrator verification, subscription selection) fail hard. Intended for
    automation where the Az and Microsoft Graph contexts are established by the caller
    before invoking this script (e.g. Connect-AzAccount -AccessToken / Connect-MgGraph
    -AccessToken). Run under 'pwsh -NonInteractive' so any unexpected prompt throws.
    Azure mandatory MFA: a pre-established USER context must carry the ARM 'p1'
    authentication-context claim (sign in with Connect-AzAccount -ClaimsChallenge) or
    resource create/update/delete calls are rejected by Azure; service principal
    contexts are exempt. The script warns but never re-authenticates in this mode.

.PARAMETER AcceptTerms
    Non-interactive acknowledgement of the Neologik Terms of Use and Privacy Policy
    (https://www.neologik.ai/terms, https://www.neologik.ai/privacy-policy). Required
    with -NonInteractive; the acceptance is written to the log.

.PARAMETER FreshRun
    Discard any existing checkpoint and start a fresh run without prompting. In
    -NonInteractive mode a leftover checkpoint without -FreshRun is an error.

.EXAMPLE
    .\Install-NeologikEnvironment.ps1 -OrganizationCode "ABC"

.EXAMPLE
    .\Install-NeologikEnvironment.ps1 -OrganizationCode "XYZ" -EnvironmentType "prd" -AzureRegion "ukwest"

.EXAMPLE
    # CI / unattended (contexts pre-established by the caller):
    pwsh -NonInteractive -File .\Install-NeologikEnvironment.ps1 -NonInteractive -AcceptTerms -FreshRun `
        -AnswerFile .\inputs.json -SkipPowerShellUpdate -SkipModuleInstall -SkipGuestInvitation `
        -SubscriptionName "My Subscription" -ExistingServicePrincipalSecret $env:SP_CLIENT_SECRET

.NOTES
    Author: Neologik
    Version: v5.0.0 (keep in step with $script:Version below)
    Requires: PowerShell 7.4+ (script will update if needed)
    Requires: Subscription Owner and Global Administrator roles
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OrganizationCode = "",

    [Parameter(Mandatory = $false)]
    # 'dmo', 'test' and 'stg' are supported but intentionally undocumented — they are
    # accepted when supplied but not advertised to the operator in prompts or help.
    [ValidateSet('dev', 'prd', 'dmo', 'test', 'stg')]
    [string]$EnvironmentType = "dev",

    [Parameter(Mandatory = $false)]
    [string]$AzureRegion = "uksouth",

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionName,

    [Parameter(Mandatory = $false)]
    [ValidateLength(3, 24)]
    [ValidatePattern('^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$')]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $false)]
    [switch]$SkipPowerShellUpdate,

    [Parameter(Mandatory = $false)]
    [switch]$SkipModuleInstall,

    [Parameter(Mandatory = $false)]
    [switch]$SkipGuestInvitation,

    [Parameter(Mandatory = $false)]
    [string]$ExistingServicePrincipalObjectId,

    [Parameter(Mandatory = $false)]
    [string]$ExistingServicePrincipalSecret,

    # Path to a JSON file of predefined inputs that pre-fill the interactive prompts.
    # When omitted, an 'inputs.json' next to the script is auto-detected.
    [Parameter(Mandatory = $false)]
    [string]$AnswerFile = "",

    # CI / unattended mode. Requires a fully-populated answer file; every interactive
    # gate either resolves from switches/answers or throws instead of prompting.
    # Intended for automation (e.g. GitHub Actions) where no console input is possible.
    [Parameter(Mandatory = $false)]
    [switch]$NonInteractive,

    # Non-interactive acceptance of the Neologik Terms of Use and Privacy Policy.
    # Required when -NonInteractive is set; the acceptance is written to the log.
    [Parameter(Mandatory = $false)]
    [switch]$AcceptTerms,

    # Discard any existing checkpoint and start a fresh run without prompting.
    # In -NonInteractive mode a leftover checkpoint without -FreshRun is an error.
    [Parameter(Mandatory = $false)]
    [switch]$FreshRun
)

# Script variables
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'

# Script version
$script:Version = 'v5.0.0'

# Initialize with timestamp - will be updated after org code and environment type are collected
$script:FileTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogFile = Join-Path $PSScriptRoot "NeologikOnboarding_$($script:FileTimestamp).log"
$script:OutputFile = Join-Path $PSScriptRoot "NeologikConfiguration_$($script:FileTimestamp).json"
$script:ConfigData = @{}
$script:CompletedSteps = [System.Collections.Generic.List[string]]::new()
$script:ProviderRegistrations = @{}
$script:CheckpointFile = Join-Path $PSScriptRoot "NeologikCheckpoint.json"
$script:CheckpointRegionAbbrev = $null

# Cached resource tag set (project#1173). Built once by Get-NeologikResourceTags on first
# use after configuration is confirmed; $null until then (and when tagging is disabled).
$script:ResourceTagsCache = $null

# Key Vault name override. Track whether the operator supplied -KeyVaultName on THIS
# invocation so that, on resume, a value saved in the checkpoint is preferred unless the
# operator explicitly overrides it again on the command line.
$script:KeyVaultNameFromCli = $PSBoundParameters.ContainsKey('KeyVaultName')
$script:KeyVaultNameOverride = if ($script:KeyVaultNameFromCli) { $KeyVaultName } else { $null }

# Whether -SkipGuestInvitation was passed on THIS invocation. Computed at script scope where
# $PSBoundParameters reflects the script parameters. When the switch is absent, the guest-invite
# decision falls back to the answer file's 'skipGuestInvitation' key, then to an interactive prompt.
$script:SkipGuestInvitationFromCli = $PSBoundParameters.ContainsKey('SkipGuestInvitation')

# Non-interactive (CI) mode flags, computed at script scope so functions can read them
# via $script: without relying on scope walking.
$script:NonInteractiveMode = $NonInteractive.IsPresent
$script:AcceptTermsFromCli = $AcceptTerms.IsPresent
$script:FreshRunMode = $FreshRun.IsPresent

# Resolved client-provided SP secret. Held here (NOT in ConfigData) so it is never written to
# the checkpoint or exported config. Set during configuration gathering; empty on resume.
$script:ExistingSpSecretResolved = ""

# Built-in default recipients for the budget / cost-report emails (used when inputs.json omits the field)
$script:DefaultBudgetCostReportEmailRecipients = @('support_budget_alerts@neologik.ai')

# Load Neologik guest user emails from file
$script:GuestUsersFile = Join-Path $PSScriptRoot "NeologikGuestUsers.txt"
if (Test-Path $script:GuestUsersFile) {
    $script:NeologikGuestUsers = @(Get-Content $script:GuestUsersFile | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\s*#' })
} else {
    Write-Warning "Guest users file not found at: $script:GuestUsersFile. It ships in the onboarding zip package - interactive runs will offer to locate it during configuration; otherwise no guest users will be invited."
    $script:NeologikGuestUsers = @()
}

# Required PowerShell modules
$script:RequiredModules = @(
    # Az.Accounts 5.2.0 is the first version with Connect-AzAccount -ClaimsChallenge,
    # needed to satisfy Azure mandatory MFA (ARM-layer enforcement) at sign-in.
    @{ Name = 'Az.Accounts'; MinVersion = '5.2.0' },
    @{ Name = 'Az.Resources'; MinVersion = '7.0.0' },
    @{ Name = 'Az.Compute'; MinVersion = '7.0.0' },
    @{ Name = 'Az.KeyVault'; MinVersion = '5.0.0' },
    @{ Name = 'Az.Storage'; MinVersion = '6.0.0' },
    @{ Name = 'Az.ManagedServiceIdentity'; MinVersion = '1.0.0' },
    @{ Name = 'Microsoft.Graph'; MinVersion = '2.0.0' }
)

# Azure mandatory MFA (ARM-layer Phase 2, enforced for all create/update/delete since
# 1 October 2025): static claims challenge requesting the 'p1' authentication-context
# claim. Decodes to {"access_token":{"acrs":{"essential":true,"values":["p1"]}}}.
# Passed at sign-in it forces interactive MFA so the resulting ARM token satisfies the
# enforcement. It is a public, well-known instruction to Entra ID - not a secret.
$script:ArmMfaClaimsChallenge = 'eyJhY2Nlc3NfdG9rZW4iOnsiYWNycyI6eyJlc3NlbnRpYWwiOnRydWUsInZhbHVlcyI6WyJwMSJdfX19'

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
        Initializes the configuration JSON file name with organization code, environment type, and
        environment index. Call after the environment index has been set.
    #>
    [CmdletBinding()]
    param()

    # Generate configuration file name from the environment name = org code + index
    # (e.g. dmo01, abc01). Environment type never appears in names (naming
    # convention alignment - project#1063).
    $configFileName = "Neologik_$($script:OrganizationCode)$($script:EnvironmentIndex)_Configuration_$($script:FileTimestamp).json"
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

    if ($script:NonInteractiveMode) {
        if ($script:AcceptTermsFromCli) {
            Write-Log "Terms and conditions accepted non-interactively via -AcceptTerms" -Level Info
            Write-Host "`n✓ Terms accepted (-AcceptTerms). Proceeding with installation...`n" -ForegroundColor Green
            return $true
        }
        throw "Non-interactive mode requires -AcceptTerms to acknowledge the Neologik Terms of Use and Privacy Policy."
    }

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
        HostName              = $script:HostName
        ResourceGroupName     = $script:ResourceGroupName
        EnvironmentIndex      = $script:EnvironmentIndex
        OutputFile            = $script:OutputFile
        KeyVaultNameOverride  = $script:KeyVaultNameOverride
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
    # Back-compat: an in-flight checkpoint from an older run stored separate Hostname/DomainName.
    $script:HostName               = if ($data.HostName) { $data.HostName }
                                     elseif ($data.Hostname -and $data.DomainName) { "$($data.Hostname).$($data.DomainName)" }
                                     else { $data.HostName }
    $script:ResourceGroupName      = $data.ResourceGroupName
    $script:EnvironmentIndex       = $data.EnvironmentIndex
    $script:CheckpointRegionAbbrev = $data.RegionAbbrev
    # Keep only the file name and rebase it onto this script's folder: the checkpoint may
    # have been written on another host (e.g. WSL) whose absolute path is meaningless here.
    $script:OutputFile             = if ($data.OutputFile) { Join-Path $PSScriptRoot (Split-Path -Leaf $data.OutputFile) }
                                     else { $script:OutputFile }

    # Prefer the Key Vault name saved in the checkpoint, unless the operator explicitly
    # supplied -KeyVaultName on this resume invocation (in which case the CLI value wins).
    if (-not $script:KeyVaultNameFromCli -and -not [string]::IsNullOrWhiteSpace($data.KeyVaultNameOverride)) {
        $script:KeyVaultNameOverride = $data.KeyVaultNameOverride
    }
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

#region Resource Tagging

function ConvertTo-NeologikCustomTags {
    <#
    .SYNOPSIS
        Parses custom resource tags into a hashtable (project#1173). Accepts a
        comma-separated 'key=value' string, or a dictionary/object (from the answer file or
        a restored checkpoint). Throws on any invalid key or value so the caller can warn
        or re-prompt. Keys: letters, digits, '.', '_' and '-' only; keys and values must
        not contain ',' or '='.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Value
    )

    $tags = @{}
    if ($null -eq $Value) { return $tags }

    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) { $tags[[string]$key] = [string]$Value[$key] }
    }
    elseif ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($prop in $Value.PSObject.Properties) { $tags[[string]$prop.Name] = [string]$prop.Value }
    }
    else {
        $text = ([string]$Value).Trim()
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            foreach ($pair in ($text -split ',')) {
                $trimmed = $pair.Trim()
                if ([string]::IsNullOrWhiteSpace($trimmed)) { throw "Empty tag entry - use comma-separated key=value pairs." }
                $parts = $trimmed -split '=', 2
                if ($parts.Count -ne 2) { throw "Tag '$trimmed' must be in key=value form." }
                $tags[$parts[0].Trim()] = $parts[1].Trim()
            }
        }
    }

    foreach ($key in @($tags.Keys)) {
        if ($key -notmatch '^[a-zA-Z0-9._-]+$') { throw "Tag key '$key' is invalid - use letters, digits, '.', '_' and '-' only." }
        if ("$($tags[$key])" -match '[,=]') { throw "Tag value for '$key' must not contain ',' or '='." }
    }

    return $tags
}

function Get-NeologikResourceTags {
    <#
    .SYNOPSIS
        Returns the tag set applied to script-created Azure resources, or $null when
        resource tagging is disabled (project#1173). Built once and cached so every
        resource carries the identical set; the customer's custom tags override the
        Neologik defaults on key collision.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ConfigData['ResourceTagsEnabled']) { return $null }
    if ($null -ne $script:ResourceTagsCache) { return $script:ResourceTagsCache }

    $tags = @{
        'Vendor'          = 'Neologik'
        'ApplicationName' = 'NeologikHarness'
        'ManagedBy'       = 'NeologikOnboarding'
        'Environment'     = "$($script:OrganizationCode)$($script:EnvironmentType)"
        'Solution'        = [string]$script:ConfigData['SolutionShortName']
        'DeploymentDate'  = (Get-Date -Format 'yyyy-MM-dd')
    }

    # Custom pairs override the defaults on key collision. A checkpoint round-trip stores
    # the hashtable as an object - ConvertTo-NeologikCustomTags accepts both shapes.
    foreach ($entry in (ConvertTo-NeologikCustomTags $script:ConfigData['ResourceTagsCustom']).GetEnumerator()) {
        $tags[[string]$entry.Key] = [string]$entry.Value
    }

    $script:ResourceTagsCache = $tags
    return $tags
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

function Invoke-AzConnect {
    <#
    .SYNOPSIS
        Connects to Azure using interactive browser authentication, falling back
        to device code authentication when a browser is unavailable (e.g. headless
        or SSH sessions).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantId
    )

    $connectParams = @{ ErrorAction = 'Stop' }
    if ($TenantId) {
        $connectParams['TenantId'] = $TenantId
    }

    # Azure mandatory MFA (ARM-layer): request the 'p1' authentication-context claim at
    # sign-in so the first token already satisfies create/update/delete enforcement.
    # Without it, a non-MFA token passes sign-in and the run fails at the first resource
    # write with a claims-challenge error. Requires Az.Accounts >= 5.2.0.
    if ((Get-Command Connect-AzAccount).Parameters.ContainsKey('ClaimsChallenge')) {
        $connectParams['ClaimsChallenge'] = $script:ArmMfaClaimsChallenge
    }
    else {
        Write-Log "Az.Accounts predates -ClaimsChallenge (< 5.2.0): sign-in may not satisfy Azure mandatory MFA and resource writes may be rejected" -Level Warning
    }

    try {
        Write-Host "`nℹ️  A browser window will open for Azure login.`n" -ForegroundColor Cyan
        return Connect-AzAccount @connectParams
    }
    catch {
        Write-Log "Interactive browser authentication failed: $($_.Exception.Message)" -Level Warning
        Write-Log "Falling back to device code authentication" -Level Info
        Write-Host "`nℹ️  A code will be displayed. Visit the URL and enter the code to authenticate.`n" -ForegroundColor Cyan
        return Connect-AzAccount @connectParams -UseDeviceAuthentication
    }
}

function Get-ArmTokenMfaClaimStatus {
    <#
    .SYNOPSIS
        Inspects the current ARM access token for the 'p1' authentication-context claim
        ('acrs') that Azure mandatory MFA requires on create/update/delete operations.
    .OUTPUTS
        'Present' - user token carrying the claim
        'Missing' - user token without the claim (resource writes will be rejected)
        'Exempt'  - application (service principal) token; exempt from mandatory MFA
        'Unknown' - token could not be acquired or inspected
    #>
    [CmdletBinding()]
    param()

    try {
        if ((Get-Command Get-AzAccessToken).Parameters.ContainsKey('AsSecureString')) {
            $secureToken = (Get-AzAccessToken -AsSecureString -ErrorAction Stop).Token
            $token = [System.Net.NetworkCredential]::new('', $secureToken).Password
        }
        else {
            $token = (Get-AzAccessToken -ErrorAction Stop).Token
        }

        # Decode the JWT payload (base64url)
        $payload = $token.Split('.')[1].Replace('-', '+').Replace('_', '/')
        switch ($payload.Length % 4) {
            2 { $payload += '==' }
            3 { $payload += '=' }
        }
        $claims = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json

        # Delegated (user) tokens carry 'scp'; app-only tokens do not and are exempt.
        if (-not $claims.scp) { return 'Exempt' }
        # 'acrs' p1 is only emitted when the claims challenge was requested at sign-in;
        # a token minted through an ordinary MFA sign-in instead carries 'amr' mfa.
        # Either satisfies the ARM enforcement.
        if (($claims.acrs -contains 'p1') -or ($claims.amr -contains 'mfa')) { return 'Present' }
        return 'Missing'
    }
    catch {
        Write-Log "Could not inspect the ARM access token for the MFA claim: $($_.Exception.Message)" -Level Warning
        return 'Unknown'
    }
}

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
            
            # Connect to Azure (interactive browser, falling back to device code)
            Write-Log "Authenticating to Azure..." -Level Info
            $azContext = Invoke-AzConnect -TenantId $TenantId
            Write-Log "Connected to Azure as $($azContext.Context.Account.Id)" -Level Success
        }
        elseif ($currentContext -and $currentContext.Account) {
            Write-Log "Already connected to Azure as $($currentContext.Account.Id)" -Level Info
            
            # If TenantId is specified and different, reconnect
            if ($TenantId -and $currentContext.Tenant.Id -ne $TenantId) {
                Write-Log "Switching to specified tenant: $TenantId" -Level Info
                $azContext = Invoke-AzConnect -TenantId $TenantId
            }
            else {
                # Azure mandatory MFA (ARM-layer): a cached token minted without MFA passes
                # this reuse path but fails the first create/update/delete with a
                # claims-challenge error - verify the 'p1' claim up front instead.
                $mfaClaimStatus = Get-ArmTokenMfaClaimStatus
                if ($mfaClaimStatus -eq 'Missing' -and -not $script:NonInteractiveMode) {
                    Write-Log "Cached Azure token lacks the MFA claim required for resource management; re-authenticating..." -Level Warning
                    $azContext = Invoke-AzConnect -TenantId $currentContext.Tenant.Id
                }
                else {
                    if ($mfaClaimStatus -eq 'Missing') {
                        Write-Log "Non-interactive: the supplied ARM user token lacks the mandatory-MFA claim ('acrs' p1); resource create/update/delete will be rejected. Establish the context with Connect-AzAccount -ClaimsChallenge or a service principal." -Level Warning
                    }
                    $azContext = [PSCustomObject]@{
                        Context = $currentContext
                    }
                    Write-Log "Using existing Azure connection" -Level Success
                }
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
                    -Scopes "User.ReadWrite.All", "User.Invite.All", "Group.ReadWrite.All", "Application.ReadWrite.All", "Directory.ReadWrite.All", "RoleManagement.ReadWrite.Directory", "AppRoleAssignment.ReadWrite.All", "AgentIdentityBlueprint.Create", "AgentIdentityBlueprint.AddRemoveCreds.All", "AgentIdentityBlueprintPrincipal.Create" `
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
            # Get current user's object ID via Graph REST on the already-established
            # connection - the Get-Mg* entity cmdlets load extra Graph submodules whose
            # assemblies can conflict with the loaded Microsoft.Graph.Authentication version.
            $currentUser = Invoke-MgGraphRequest -Method GET -Uri "v1.0/me?`$select=id" -ErrorAction Stop
            $roleAssignments = Get-AzRoleAssignment -Scope "/subscriptions/$SubscriptionId" -ObjectId $currentUser.id -ErrorAction Stop
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
            # Membership check via Graph REST on the already-established connection.
            # The previous Get-MgUser / Get-MgDirectoryRole* approach loaded the
            # Microsoft.Graph.Users and DirectoryManagement submodules, whose assemblies
            # can conflict with the loaded Microsoft.Graph.Authentication version and
            # crash the check on otherwise-healthy machines. Checking the signed-in
            # user's own active directory roles also needs no role activation write.
            $gaRoleTemplateId = '62e90394-69f5-4237-9190-012177145e10'  # Global Administrator (well-known template id)
            $memberOf = Invoke-MgGraphRequest -Method GET -Uri "v1.0/me/memberOf/microsoft.graph.directoryRole?`$select=roleTemplateId" -ErrorAction Stop
            $isGlobalAdmin = [bool]($memberOf.value | Where-Object { $_.roleTemplateId -eq $gaRoleTemplateId })
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
            # In non-interactive mode there is no operator to decide: fail hard.
            if ($script:NonInteractiveMode) {
                throw "Global Administrator role could not be verified (the check failed to run) and non-interactive mode cannot prompt. Ensure the Graph token carries directory-role read permission."
            }
            Write-Host ""
            Write-Host "⚠️  Unable to verify the Global Administrator role for $userAccount (the check failed to run)." -ForegroundColor Yellow
            Write-Host "    Global Administrator is required for app registration, admin consent, and guest invitations." -ForegroundColor Yellow
            Write-Host "    Continuing without confirming it may cause later steps to fail." -ForegroundColor Yellow
            $proceed = Read-Host "Proceed anyway? [Y/N]"
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

function Find-NeologikUserByEmail {
    <#
    .SYNOPSIS
        Resolves a user account by mail or userPrincipalName via Graph REST.
    .DESCRIPTION
        Uses Invoke-MgGraphRequest on the established Graph connection instead of
        Get-MgUser: the Microsoft.Graph.Users submodule's assembly can conflict with
        the loaded Microsoft.Graph.Authentication version and crash the lookup on
        otherwise-healthy machines. Returns the matching user (id, displayName) or
        $null when no account matches or the lookup fails.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Email
    )

    $safeEmail = $Email -replace "'", "''"
    $filter = [uri]::EscapeDataString("mail eq '$safeEmail' or userPrincipalName eq '$safeEmail'")
    try {
        $result = Invoke-MgGraphRequest -Method GET -Uri "v1.0/users?`$filter=$filter&`$select=id,displayName" -ErrorAction Stop
        if ($result.value -and $result.value.Count -gt 0) {
            # Normalize to a typed object: the response hashtable's key lookup can be
            # case-sensitive, and callers read .Id / .DisplayName. JSON keys are exact
            # camelCase ('id', 'displayName'), so these lookups are always safe.
            $match = $result.value[0]
            return [pscustomobject]@{
                Id          = $match.id
                DisplayName = $match.displayName
            }
        }
        return $null
    }
    catch {
        Write-Log "User lookup for $Email failed: $_" -Level Warning
        return $null
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
                # Non-interactive callers must supply a resolvable -SubscriptionName up front.
                if ($script:NonInteractiveMode) {
                    throw "Subscription '$SubscriptionName' not found and non-interactive mode cannot prompt for an alternative. Pass a valid -SubscriptionName."
                }
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
        [string]$Location,

        # Internal: set on the single retry after an MFA claims-challenge re-authentication.
        [Parameter(Mandatory = $false)]
        [switch]$IsMfaRetry
    )

    Write-Log "Checking for resource group: $ResourceGroupName..." -Level Info

    try {
        # Confirm the Microsoft.Resources provider (registration submitted at step 5c) before creating
        Confirm-ResourceProviderReady -Namespaces @('Microsoft.Resources')

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
            # Resource tags (project#1173): applied on the create call itself so tenants whose
            # Azure Policies deny untagged resources accept it; empty splat when disabled.
            $tagParams = @{}
            $resourceTags = Get-NeologikResourceTags
            if ($resourceTags) { $tagParams['Tag'] = $resourceTags }
            $rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location @tagParams -ErrorAction Stop
            Write-Log "Resource group created successfully" -Level Success
            
            $script:ConfigData['ResourceGroupName'] = $rg.ResourceGroupName
            $script:ConfigData['AzureRegion'] = $rg.Location
        }

        return $rg
    }
    catch {
        # Azure mandatory MFA (ARM-layer): a token minted without MFA fails create/update/
        # delete with a claims-challenge error. Re-authenticate (Invoke-AzConnect requests
        # the 'p1' claim) and retry once - backstop for tokens the up-front check missed.
        if (-not $IsMfaRetry -and -not $script:NonInteractiveMode -and $_.Exception.Message -match 'authenticat\w+ through MFA') {
            Write-Log "Azure rejected the operation because the token lacks the mandatory-MFA claim; re-authenticating and retrying..." -Level Warning
            Invoke-AzConnect -TenantId $script:ConfigData['TenantId'] | Out-Null
            return New-NeologikResourceGroup -ResourceGroupName $ResourceGroupName -Location $Location -IsMfaRetry
        }
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

function Resolve-GuestUsersFile {
    <#
    .SYNOPSIS
        Interactively locates NeologikGuestUsers.txt when it was not found next to the
        script (customers sometimes download only the .ps1 instead of unzipping the full
        onboarding package). Offers a file-browse dialog, manual path entry, or an
        explicit continue-without-guests choice.
    .OUTPUTS
        $true when a valid file was selected ($script:GuestUsersFile and
        $script:NeologikGuestUsers updated); $false when the user chose to continue
        without guest users.
    #>
    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "  NeologikGuestUsers.txt was not found next to the script:" -ForegroundColor Yellow
    Write-Host "    $script:GuestUsersFile" -ForegroundColor Gray
    Write-Host "  The file ships in the onboarding zip package (one Neologik email per line)." -ForegroundColor Gray
    Write-Host "  If you downloaded only the .ps1, unzip the full package or locate the file now." -ForegroundColor Gray

    while ($true) {
        Write-Host ""
        Write-Host "  [B] Browse for the file   [S] Skip guest invitations   or type the full path" -ForegroundColor Cyan
        Write-Host "  Your choice: " -NoNewline -ForegroundColor Yellow
        $choice = (Read-Host).Trim()

        if ($choice -match '^(s|skip)$') {
            Write-Log "User chose to continue without a guest users file - no guest users will be invited" -Level Warning
            return $false
        }

        $candidate = $null
        if ($choice -match '^(b|browse)$') {
            try {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
                $dialog = [System.Windows.Forms.OpenFileDialog]::new()
                $dialog.Title = 'Select NeologikGuestUsers.txt'
                $dialog.InitialDirectory = $PSScriptRoot
                $dialog.Filter = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
                # Topmost owner form so the dialog cannot open hidden behind the console.
                $owner = [System.Windows.Forms.Form]::new()
                $owner.TopMost = $true
                try {
                    if ($dialog.ShowDialog($owner) -ne [System.Windows.Forms.DialogResult]::OK) { continue }
                    $candidate = $dialog.FileName
                }
                finally {
                    $owner.Dispose()
                }
            }
            catch {
                Write-Host "  A file dialog is not available in this session; type the full path instead." -ForegroundColor Yellow
                continue
            }
        }
        elseif ($choice) {
            $candidate = $choice.Trim('"')
        }
        else {
            continue
        }

        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            Write-Host "  File not found: $candidate" -ForegroundColor Red
            continue
        }

        $emails = @(Get-Content -LiteralPath $candidate | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\s*#' })
        if ($emails.Count -eq 0) {
            Write-Host "  $candidate contains no guest entries (blank lines and # comments are ignored)." -ForegroundColor Red
            continue
        }

        $script:GuestUsersFile = $candidate
        $script:NeologikGuestUsers = $emails
        Write-Log "Guest users file selected: $candidate ($($emails.Count) guest(s))" -Level Success
        return $true
    }
}

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
            $existingUser = Find-NeologikUserByEmail -Email $email

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

function Read-EmailAddressList {
    <#
    .SYNOPSIS
        Reads email addresses interactively, one line per Enter with a running count.
        A line may carry several comma-separated addresses (pasting a ready-made list
        works); a blank line finishes. Returns the de-duplicated list.
    #>
    [CmdletBinding()]
    param(
        # Pre-collected addresses (e.g. the guest file's entries) - included in the
        # running count and the returned list.
        [Parameter(Mandatory = $false)]
        [string[]]$Seed = @()
    )

    $collected = @($Seed)
    while ($true) {
        Write-Host "  Address ($($collected.Count) so far): " -NoNewline -ForegroundColor Gray
        $line = Read-Host
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        $collected += @($line -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    return @($collected | Select-Object -Unique)
}

function Invoke-ExistingAccountResolution {
    <#
    .SYNOPSIS
        Resolves pre-created accounts (guests or members) by email address so they can be
        added to the security groups. Never sends invitations.
    .DESCRIPTION
        Used when the operator declined B2B guest invitations but chose to add existing
        accounts to the groups. Each address is looked up by mail or userPrincipalName;
        a match joins the group-membership list, and an address with no matching account
        is reported and SKIPPED - this step is best-effort by design and the script
        always continues (the operator can add the account in Entra ID later).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Emails
    )

    if ($Emails.Count -eq 0) {
        Write-Log "No existing-account addresses to resolve - no accounts will be added to the groups." -Level Info
        return @()
    }

    Write-Log "Resolving existing accounts for group membership (no invitations will be sent)..." -Level Info

    $resolvedUsers = @()
    foreach ($email in $Emails) {
        Write-Log "Looking up existing account: $email..." -Level Info
        $existingUser = Find-NeologikUserByEmail -Email $email

        if ($existingUser) {
            Write-Log "Account $email exists (ID: $($existingUser.Id)) - it will be added to the security groups" -Level Success
            $resolvedUsers += @{
                Email = $email
                UserId = $existingUser.Id
                Status = 'ExistingResolved'
            }
        }
        else {
            Write-Log "Account $email does not exist in this tenant (no user with that mail or user principal name) - skipped, continuing. Create the account and add it to the groups in Entra ID later." -Level Warning
        }
    }

    Write-Log "Existing accounts resolved: $($resolvedUsers.Count) of $($Emails.Count) address(es) matched." -Level Info
    $script:ConfigData['ExistingAccountsAdded'] = $resolvedUsers
    return $resolvedUsers
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
        [string]$EnvironmentIndex = ""
    )

    Write-Log "Creating Neologik security groups..." -Level Info

    try {
        Import-Module Microsoft.Graph.Groups -ErrorAction Stop

        # Group name suffix = the platform solution short name (neo{org}{index},
        # e.g. neodmo01) so script-created groups match the platform naming
        # convention (project#1063). SolutionShortName honours any override from
        # the answer file; environment type never appears in names.
        $shortName = if (-not [string]::IsNullOrWhiteSpace([string]$script:ConfigData['SolutionShortName'])) { [string]$script:ConfigData['SolutionShortName'] }
                     elseif ([string]::IsNullOrWhiteSpace($OrganizationCode)) { "" }
                     else { "neo$($OrganizationCode.ToLower())$EnvironmentIndex" }
        $groupSuffix = if ([string]::IsNullOrWhiteSpace($shortName)) { "" } else { " - $shortName" }

        # v5: one default user group. Agent channels created in the NCE reuse
        # this group (or an admin supplies another existing group id at channel
        # attach); the platform never creates groups (project#1519).
        $groups = @()
        $groups += @{
            Name = "Neologik User Group$groupSuffix"
            Description = 'Default Neologik users group - assign to agent channels created in the NCE'
        }
        # NCE delegation model (project#1341): contributors (the pre-v5 NCE
        # group renamed - object id keyed everywhere, so renaming on sight is
        # safe) and the new admins group gating Blueprints/Audit/Admin.
        $groups += @{
            Name = "Neologik NCE Contributors$groupSuffix"
            Description = 'NCE contributor role - create and change platform configuration in the Neologik Context Engine'
            PreviousNames = @("Neologik NCE User Group$groupSuffix", "Neologik Harness User Group$groupSuffix")
        }
        $groups += @{
            Name = "Neologik NCE Admins$groupSuffix"
            Description = 'NCE admin role - full access including Blueprints, Audit and the Admin page'
        }
        $groups += @{
            Name = "Neologik Admin User Group$groupSuffix"
            Description = 'Users who will administer and support the resources'
        }

        $createdGroups = @()

        foreach ($groupDef in $groups) {
            Write-Log "Processing group: $($groupDef.Name)..." -Level Info

            # Check if group exists (current name first, then any previous
            # name - found legacy groups are renamed in place so existing
            # environments keep their object ids and memberships)
            $existingGroup = Get-MgGroup -Filter "displayName eq '$($groupDef.Name)'" -ErrorAction SilentlyContinue
            if (-not $existingGroup -and $groupDef.PreviousNames) {
                foreach ($previousName in $groupDef.PreviousNames) {
                    $existingGroup = Get-MgGroup -Filter "displayName eq '$previousName'" -ErrorAction SilentlyContinue
                    if ($existingGroup) {
                        Write-Log "Renaming group '$previousName' -> '$($groupDef.Name)' (display name only; object id unchanged)" -Level Info
                        Update-MgGroup -GroupId $existingGroup.Id -DisplayName $groupDef.Name -Description $groupDef.Description -ErrorAction Stop
                        $existingGroup = Get-MgGroup -GroupId $existingGroup.Id -ErrorAction Stop
                        break
                    }
                }
            }

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
                -Scope $rgScope `
                -ErrorAction Stop
        }
        catch {
            Write-Log "ERROR: Unable to verify role assignments - insufficient permissions" -Level Error
            Write-Host "`n❌ INSUFFICIENT PERMISSIONS" -ForegroundColor Red
            Write-Host "Cannot verify role assignments. Owner role at subscription level is required." -ForegroundColor Yellow
            throw "Insufficient permissions: Cannot verify role assignments"
        }

        # No subscription-scoped roles. AKS administration is covered at RG scope by
        # 'Contributor' (control plane: start/stop/scale/upgrade) plus 'Azure Kubernetes
        # Service Cluster Admin Role' (admin kubeconfig). The AKS node resource group (MC_*)
        # is managed by AKS itself, so admins need no standing subscription-scoped grant.
        $subRoles = @()

        # Roles to assign at resource-group scope
        $rgRoles = @(
            'Contributor',
            'Azure Kubernetes Service Cluster Admin Role',
            'Key Vault Administrator',
            'Storage Blob Data Owner',
            'Storage Table Data Contributor',
            'Azure Kubernetes Service RBAC Cluster Admin',
            'Cognitive Services Data Reader',
            'Cognitive Services OpenAI Contributor',
            'Search Index Data Reader',
            'Azure AI Developer'
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

        # @(...) forces arrays so the concatenation is array+array — a single-element pipeline
        # (e.g. $subRoles = @('Contributor')) otherwise unrolls to a lone hashtable and
        # `hashtable + array` throws "A hash table can only be added to another hash table".
        $script:ConfigData['RoleAssignments'] = @($subRoles | ForEach-Object {
            @{ Principal = $adminGroup.Name; PrincipalType = 'Security Group'; Role = $_; Scope = 'Subscription' }
        }) + @($rgRoles | ForEach-Object {
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
        [string]$EnvironmentType = "",

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentIndex = ""
    )

    Write-Log "Creating App Registration for GitHub service connection..." -Level Info

    try {
        Import-Module Microsoft.Graph.Applications -ErrorAction Stop

        # App name suffix = the platform solution short name (neo{org}{index},
        # e.g. neodmo01) - naming convention alignment, project#1063.
        $appName = if ([string]::IsNullOrWhiteSpace($OrganizationCode)) {
            "Neologik GitHub Service Connection"
        } else {
            $shortName = if (-not [string]::IsNullOrWhiteSpace([string]$script:ConfigData['SolutionShortName'])) { [string]$script:ConfigData['SolutionShortName'] }
                         else { "neo$($OrganizationCode.ToLower())$EnvironmentIndex" }
            "Neologik GitHub Service Connection - $shortName"
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
            SubscriptionRoles = @('Reader')
            RGRoles = @('Contributor', 'Key Vault Certificates Officer', 'Key Vault Secrets Officer', 'Storage Blob Data Contributor', 'Azure Kubernetes Service RBAC Cluster Admin', 'Monitoring Contributor', 'Role Based Access Control Administrator')
            GraphAppRoles = @('Application.ReadWrite.OwnedBy', 'AgentIdentityBlueprint.AddRemoveCreds.All')
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

function Get-NeologikExistingAppRegistration {
    <#
    .SYNOPSIS
        Resolves a client-supplied, pre-existing service principal into the same shape
        returned by New-NeologikAppRegistration, WITHOUT creating anything.
    .DESCRIPTION
        Used when the client owns the deployment service principal and shares its object
        ID (and optionally its secret). No app registration, service principal, or secret
        is created. Role assignment and Graph consent are NOT done here - the caller runs
        Set-AppRegistrationRoles against the resolved SP, exactly as for a script-created
        one (the operator is Owner + Global Admin, so it can grant either way).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServicePrincipalObjectId,

        [Parameter(Mandatory = $false)]
        [string]$ProvidedSecret = ""
    )

    Write-Log "Using client-supplied service principal (object ID: $ServicePrincipalObjectId)..." -Level Info

    try {
        Import-Module Microsoft.Graph.Applications -ErrorAction Stop

        # Resolve the service principal by its object ID to obtain the client (app) ID.
        $sp = Get-MgServicePrincipal -ServicePrincipalId $ServicePrincipalObjectId -ErrorAction Stop
        Write-Log "Resolved service principal '$($sp.DisplayName)' (client ID: $($sp.AppId))" -Level Success

        # Best-effort resolve the backing application object ID (may be null if the app is
        # owned in a different tenant or not readable with the current permissions).
        $appObjectId = $null
        try {
            $app = Get-MgApplication -Filter "appId eq '$($sp.AppId)'" -ErrorAction SilentlyContinue
            if ($app) { $appObjectId = $app.Id }
        }
        catch {
            Write-Log "Could not resolve backing application object (continuing with client ID only): $_" -Level Warning
        }

        $requiredRgRoles = @('Contributor', 'Key Vault Certificates Officer', 'Key Vault Secrets Officer', 'Storage Blob Data Contributor', 'Azure Kubernetes Service RBAC Cluster Admin', 'Monitoring Contributor', 'Role Based Access Control Administrator')

        $script:ConfigData['AppRegistration'] = @{
            Name = $sp.DisplayName
            ClientId = $sp.AppId
            ObjectId = $appObjectId
            ServicePrincipalId = $sp.Id
            SecretExpiry = 'client-managed'
            Source = 'client-provided'
            SubscriptionRoles = @('Reader')
            RGRoles = $requiredRgRoles
            GraphAppRoles = @('Application.ReadWrite.OwnedBy', 'AgentIdentityBlueprint.AddRemoveCreds.All')
        }

        Write-Host "`n  Existing service principal resolved - roles and Graph consent will be assigned to it." -ForegroundColor Yellow

        return @{
            Application = if ($appObjectId) { $app } else { @{ Id = $null; AppId = $sp.AppId } }
            ServicePrincipal = $sp
            Secret = $ProvidedSecret
        }
    }
    catch {
        Write-Log "Failed to resolve client-supplied service principal '$ServicePrincipalObjectId': $_" -Level Error
        throw "Could not resolve the service principal object ID '$ServicePrincipalObjectId'. Verify it is the enterprise-application (service-principal) object ID and that you are signed in to the correct tenant."
    }
}

function Read-ExistingServicePrincipalChoice {
    <#
    .SYNOPSIS
        Decides whether to use a pre-existing (client-provided) service principal and, if so,
        resolves its object ID and optional secret.
    .DESCRIPTION
        Precedence:
          1. Command-line -ExistingServicePrincipalObjectId - use it, no prompt.
          2. Answer file - 'useExistingServicePrincipal' (true/false) with
             'existingServicePrincipalObjectId' / 'existingServicePrincipalSecret'. false
             skips without prompting; true uses the answer-file object ID (prompting only
             if it is missing).
          3. Interactive y/N prompt (default N).
    #>
    [CmdletBinding()]
    param(
        [string]$CliObjectId = "",
        [string]$CliSecret = "",
        [object]$AnswerUseExisting = $null,
        [string]$AnswerObjectId = "",
        [string]$AnswerSecret = ""
    )

    # The command-line secret backs any path with no answer-file secret: the CI wrapper
    # passes -ExistingServicePrincipalSecret while the object ID comes from the answer
    # file (the secret is never committed there).
    if ([string]::IsNullOrWhiteSpace($AnswerSecret)) { $AnswerSecret = $CliSecret }

    # 1. Command-line object ID provided: use it without prompting.
    if (-not [string]::IsNullOrWhiteSpace($CliObjectId)) {
        Write-Log "Existing service principal supplied via command line (object ID: $($CliObjectId.Trim()))." -Level Info
        return @{ UseExisting = $true; ObjectId = $CliObjectId.Trim(); Secret = $CliSecret }
    }

    # 2. Answer-file decision (when present).
    if ($null -ne $AnswerUseExisting) {
        $useExisting = [bool]$AnswerUseExisting
        Write-Log "Existing-service-principal decision from answer file: useExistingServicePrincipal=$useExisting." -Level Info
        if (-not $useExisting) {
            return @{ UseExisting = $false; ObjectId = ""; Secret = "" }
        }
        if (-not [string]::IsNullOrWhiteSpace($AnswerObjectId)) {
            return @{ UseExisting = $true; ObjectId = $AnswerObjectId.Trim(); Secret = $AnswerSecret }
        }
        Write-Host "  answer file sets useExistingServicePrincipal=true but supplies no existingServicePrincipalObjectId - enter it now." -ForegroundColor Yellow
        # Fall through to prompt for the object ID only (the y/N question is skipped).
    }
    else {
        # 3. No CLI value and no answer-file decision: ask the y/N question.
        Write-Host ""
        Write-Host "Use a service principal you have already created for deployment?" -ForegroundColor Cyan
        Write-Host "  Choose Y if you have already created the deployment service principal yourself" -ForegroundColor Gray
        Write-Host "  and want to use it. Choose N to let this script create one for you." -ForegroundColor Gray
        Write-Host "  (y/N, default: N): " -NoNewline -ForegroundColor Yellow
        $answer = Read-Host

        if ($answer -notmatch '^(y|yes)$') {
            return @{ UseExisting = $false; ObjectId = ""; Secret = "" }
        }
    }

    $objectId = ""
    while ([string]::IsNullOrWhiteSpace($objectId)) {
        Write-Host "  Service principal OBJECT ID (enterprise-application object ID, not the client/app ID): " -NoNewline -ForegroundColor Gray
        $objectId = Read-Host
        if ([string]::IsNullOrWhiteSpace($objectId)) {
            Write-Host "  Object ID is required. Please enter it, or press Ctrl+C to cancel." -ForegroundColor Red
        }
    }

    # Prefer an answer-file secret; otherwise read it masked so it is never echoed or logged.
    if (-not [string]::IsNullOrWhiteSpace($AnswerSecret)) {
        return @{ UseExisting = $true; ObjectId = $objectId.Trim(); Secret = $AnswerSecret }
    }
    Write-Host "  Client secret (optional - press Enter to skip and add it to Key Vault manually later): " -NoNewline -ForegroundColor Gray
    $secureSecret = Read-Host -AsSecureString
    $secretPlain = [System.Net.NetworkCredential]::new("", $secureSecret).Password

    return @{ UseExisting = $true; ObjectId = $objectId.Trim(); Secret = $secretPlain }
}

function Grant-GraphAppRolePermissions {
    <#
    .SYNOPSIS
        Grants lower-scoped Microsoft Graph application permissions to a service principal
        or managed identity, replacing the tenant-wide 'Application Administrator' directory role.
    .DESCRIPTION
        Assigns Microsoft Graph app roles (default: the deployment service principal's
        least-privilege set, Application.ReadWrite.OwnedBy and
        AgentIdentityBlueprint.AddRemoveCreds.All - project#2144) via appRoleAssignments.
        Idempotent and retries while the principal replicates to Entra ID. Reads of
        applications and service principals come with Application.ReadWrite.OwnedBy, so
        Application.Read.All is never granted.

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
        [string[]]$AppRoles = @('Application.ReadWrite.OwnedBy', 'AgentIdentityBlueprint.AddRemoveCreds.All')
    )

    # Microsoft Graph well-known IDs (appId of Microsoft Graph + application-permission app role IDs)
    $graphAppId = '00000003-0000-0000-c000-000000000000'
    $knownGraphAppRoleIds = @{
        # Deployment SP (least-privilege model, project#2144): manage owned app registrations
        # and add/remove credentials on the agent identity blueprint (the agent identity token
        # service's credential, project#2221).
        'Application.ReadWrite.OwnedBy'             = '18a4783c-866b-4cc7-a460-3d5e5662c884'
        'AgentIdentityBlueprint.AddRemoveCreds.All' = '0510736e-bdfb-4b37-9a1f-89b4a074763a'
        # Blueprint PRINCIPAL: create/manage agent users parented by that blueprint only. Agent
        # identity creation needs no grant - AgentIdentity.CreateAsManager is inherent to every
        # blueprint principal.
        'AgentIdUser.ReadWrite.IdentityParentedBy'  = '4aa6e624-eee0-40ab-bdd8-f9639038a614'
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
        # The deployment service principal is NOT a member of the Admin User
        # Group (project#2269, owner decision 2026-09-07). Its SQL access is the
        # SQL server's Microsoft Entra administrator setting, which the platform
        # infrastructure deployment declares from the identity it signs in as;
        # the Admin User Group (the human administrators) becomes a db_owner
        # contained user in every platform and App database instead. A group
        # membership would silently add every resource-group role the group
        # holds to the deployment identity.

        # Subscription-scoped roles for the deployment SP. Resource writes are RG-scoped
        # (provider/feature registration and the resource group are handled by this
        # onboarding script run as Owner; RG-scoped Contributor plus 'Role Based Access
        # Control Administrator' below cover the deployment writes). Two subscription-scoped
        # roles are required:
        #   - 'Reader': the infrastructure deploy's SKU/quota pre-flight reads
        #     subscription/location-level usage APIs (e.g. az search usage list =
        #     Microsoft.Search/locations/usages/read) that RG scope does not grant.
        #   - 'Cost Management Contributor': lets the deployment pipeline create and
        #     maintain the subscription-scoped cost report emails (neo-infrastructure
        #     scripts/ensure-cost-report-emails.sh, project#1215; onboarding only
        #     collects the recipients). It manages cost configuration only (budgets,
        #     views, scheduled actions) and grants no control over resources, staying
        #     within the least-privilege intent.
        $roles = @('Reader', 'Cost Management Contributor')

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
        # 'Role Based Access Control Administrator' replaces the legacy sub-scoped 'User Access
        # Administrator': the deployment Bicep creates role assignments in-template (kubelet Managed
        # Identity Operator, workload-identity grants, kubelet AcrPull), which require
        # Microsoft.Authorization/roleAssignments/write. RBAC Administrator grants that (roleAssignments
        # management only, no deny-assignment management). Scoped to the environment resource group to
        # contain blast radius. NOTE: if this environment points at a SHARED container-registry RG
        # (paramCrResourceGroup != this RG), the kubelet AcrPull/Push assignment lands there and needs
        # a separate RBAC Administrator grant on that shared RG (one-time shared-infra setup).
        $rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
        $rgRoles = @('Contributor', 'Key Vault Certificates Officer', 'Key Vault Secrets Officer', 'Storage Blob Data Contributor', 'Azure Kubernetes Service RBAC Cluster Admin', 'Monitoring Contributor', 'Role Based Access Control Administrator')

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

        # Grant the least-privilege Microsoft Graph application permission set to the
        # deployment service principal (project#2144):
        #   - Application.ReadWrite.OwnedBy: create app registrations and manage ONLY the
        #     ones it owns (bot/channel/sign-in apps). Replaces the tenant-wide 'Application
        #     Administrator' directory role. Reads of applications and service principals
        #     come with it, so Application.Read.All is not granted.
        #   - AgentIdentityBlueprint.AddRemoveCreds.All: add and remove federated identity
        #     credentials on the environment's agent identity blueprint - one credential for
        #     the agent identity token service's Kubernetes service account (project#2221),
        #     plus removal of retired per-workload credentials.
        #     The one residual tenant-wide Agent ID permission: Microsoft publishes no
        #     ownership-scoped variant and blueprint ownership is not honoured for app-only
        #     credential writes.
        # Everything else agent-identity-shaped is done ONCE here under the Global
        # Administrator (New-NeologikAgentBlueprint) or by the blueprint itself at deploy
        # time, so the deployment SP holds no AgentIdentityBlueprint.Create /
        # UpdateAuthProperties.All, AgentIdentityBlueprintPrincipal.Create,
        # AgentIdentity.Create.All or AgentIdUser.ReadWrite.All.
        # No Group.Create: the platform never creates Entra groups - channels reuse the
        # onboarding group or an admin-supplied existing group id (project#1519).
        Grant-GraphAppRolePermissions -PrincipalId $ServicePrincipalId -PrincipalDescription 'App Registration service principal' `
            -AppRoles @(
                'Application.ReadWrite.OwnedBy',
                'AgentIdentityBlueprint.AddRemoveCreds.All'
            )

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

function New-NeologikNceAuthApp {
    <#
    .SYNOPSIS
        Creates the 'Neologik Platform Sign-in' app registration and assigns the
        Harness user group to it (project#1084).

    .DESCRIPTION
        From v5 the Harness admin tool (NCE) authorizes from the token's
        groups claim only, and Entra emits that claim solely for groups
        ASSIGNED to this app's enterprise application. The deployment
        pipeline creates the app but its hardened service principal lacks
        AppRoleAssignment.ReadWrite.All BY DESIGN, so the assignment used to
        be a hard-blocking manual step (migration runsheet 7b) - skipping it
        locked every user out of NCE. This script runs as a Global
        Administrator, so the whole chain completes here instead:
        app + claims config + deployment-SP ownership + secret in Key Vault
        + group assignment. The pipeline (ensure-app-regs.sh) later finds
        the app by its Graph uniqueName, reuses it, reconciles properties,
        and rotates the secret when needed - its own best-effort group
        assignment becomes a no-op.

        Owner decision 2026-07-17: ONLY the Harness user group is assigned.
        The Admin User Group is Azure RBAC only and never grants NCE access.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$SecurityGroups,

        [Parameter(Mandatory = $true)]
        [string]$DeploySpObjectId,

        [Parameter(Mandatory = $true)]
        [string]$KeyVaultName
    )

    Write-Log "Creating the Neologik Platform Sign-in app registration (NCE + App portal login)..." -Level Info

    try {
        Import-Module Microsoft.Graph.Applications -ErrorAction Stop
        Import-Module Microsoft.Graph.Groups -ErrorAction Stop

        $solutionName = [string]$script:ConfigData['SolutionName']
        $shortName = [string]$script:ConfigData['SolutionShortName']
        $hostName = [string]$script:ConfigData['HostName']
        # MUST match the deployment pipeline exactly: ensure-app-regs.sh
        # resolves the app by uniqueName ('sp-admin-<solutionName>') and the
        # Key Vault secret name derives from it.
        $uniqueName = "sp-admin-$solutionName"
        $displayName = "Neologik Platform Sign-in - $shortName"
        $redirectUri = "https://$hostName/nce"

        # Resolve by the immutable Graph uniqueName - the same key the
        # deployment pipeline (ensure-app-regs.sh) uses. A display-name
        # lookup would miss an app the pipeline has since renamed and
        # attempt a duplicate create.
        $existingApp = $null
        try {
            $found = Invoke-MgGraphRequest -Method GET -Uri "v1.0/applications(uniqueName='$uniqueName')" -ErrorAction Stop
            $existingApp = Get-MgApplication -ApplicationId $found.id -ErrorAction Stop
        }
        catch {
            $existingApp = $null   # 404 = not found = create below
        }
        $secretText = $null

        if ($existingApp) {
            Write-Log "App Registration '$($existingApp.DisplayName)' already exists (Client ID: $($existingApp.AppId))" -Level Info
            $app = $existingApp
            if ($app.DisplayName -ne $displayName) {
                Update-MgApplication -ApplicationId $app.Id -DisplayName $displayName -ErrorAction Stop
                Write-Log "App Registration renamed to '$displayName'" -Level Info
            }
        }
        else {
            Write-Log "Creating App Registration: $displayName..." -Level Info
            $app = New-MgApplication -DisplayName $displayName `
                -UniqueName $uniqueName `
                -SignInAudience "AzureADMultipleOrgs" `
                -GroupMembershipClaims "ApplicationGroup" `
                -Web @{ RedirectUris = @($redirectUri) } `
                -Api @{ RequestedAccessTokenVersion = 2 } `
                -ErrorAction Stop
            Write-Log "App Registration created successfully (Client ID: $($app.AppId))" -Level Success
        }

        $sp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -ErrorAction SilentlyContinue
        if (-not $sp) {
            $sp = New-MgServicePrincipal -AppId $app.AppId -ErrorAction Stop
            Write-Log "Service Principal created successfully" -Level Success
        }

        # Deployment SP as owner: the pipeline manages this app through
        # Application.ReadWrite.OwnedBy, which only covers apps it owns.
        $owners = Get-MgApplicationOwner -ApplicationId $app.Id -ErrorAction SilentlyContinue
        if ($owners -and ($owners.Id -contains $DeploySpObjectId)) {
            Write-Log "Deployment SP is already an owner of the auth app" -Level Info
        }
        else {
            New-MgApplicationOwnerByRef -ApplicationId $app.Id `
                -BodyParameter @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$DeploySpObjectId" } `
                -ErrorAction Stop
            Write-Log "Deployment SP added as owner of the auth app" -Level Success
        }

        # Deployment SP as owner of the SERVICE PRINCIPAL object too - application
        # ownership does not extend to the service principal, so without this the
        # pipeline's servicePrincipal updates (display-name sync) are denied with
        # Authorization_RequestDenied on every deploy (project#1579). Idempotent:
        # re-running onboarding adds the missing owner on existing environments.
        $spOwners = Get-MgServicePrincipalOwner -ServicePrincipalId $sp.Id -ErrorAction SilentlyContinue
        if ($spOwners -and ($spOwners.Id -contains $DeploySpObjectId)) {
            Write-Log "Deployment SP is already an owner of the auth service principal" -Level Info
        }
        else {
            New-MgServicePrincipalOwnerByRef -ServicePrincipalId $sp.Id `
                -BodyParameter @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$DeploySpObjectId" } `
                -ErrorAction Stop
            Write-Log "Deployment SP added as owner of the auth service principal" -Level Success
        }

        # Client secret -> Key Vault under the name the pipeline expects.
        # Only mint one when the app is new or the vault has no value yet -
        # the pipeline rotates near-expiry credentials itself.
        $kvSecretName = "$uniqueName-auth-secret"
        $existingKvSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $kvSecretName -ErrorAction SilentlyContinue
        if ($existingKvSecret) {
            Write-Log "Key Vault already holds '$kvSecretName' - keeping the existing credential" -Level Info
        }
        else {
            $passwordCred = Add-MgApplicationPassword -ApplicationId $app.Id `
                -PasswordCredential @{ DisplayName = 'auth'; EndDateTime = (Get-Date).AddDays(365) } `
                -ErrorAction Stop
            $secretText = $passwordCred.SecretText
            $secureSecret = ConvertTo-SecureString -String $secretText -AsPlainText -Force
            $null = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $kvSecretName -SecretValue $secureSecret -ErrorAction Stop
            Write-Log "Client secret stored in Key Vault as '$kvSecretName'" -Level Success
        }

        # Assign the NCE role groups so their members' tokens carry the
        # groups claim NCE authorizes from (project#1341: contributors AND
        # admins). Default app role, direct groups only (nested membership
        # does not expand into the claim).
        $defaultAppRole = '00000000-0000-0000-0000-000000000000'
        $assignedGroups = @()
        foreach ($rolePattern in @('Neologik NCE Contributors*', 'Neologik NCE Admins*')) {
            $roleGroup = $SecurityGroups | Where-Object { $_.Name -like $rolePattern } | Select-Object -First 1
            if (-not $roleGroup) {
                Write-Log "Warning: no security group matches '$rolePattern' - NCE group assignment skipped. A Global Admin must assign it manually (runsheet steps 7b/7c)." -Level Warning
                continue
            }
            $alreadyAssigned = Get-MgGroupAppRoleAssignment -GroupId $roleGroup.Id -ErrorAction SilentlyContinue |
                Where-Object { $_.ResourceId -eq $sp.Id }
            if ($alreadyAssigned) {
                Write-Log "Group '$($roleGroup.Name)' is already assigned to the auth app" -Level Info
            }
            else {
                $null = New-MgGroupAppRoleAssignment -GroupId $roleGroup.Id `
                    -PrincipalId $roleGroup.Id `
                    -ResourceId $sp.Id `
                    -AppRoleId $defaultAppRole `
                    -ErrorAction Stop
                Write-Log "Group '$($roleGroup.Name)' assigned to the auth app - NCE login will carry the groups claim" -Level Success
            }
            $assignedGroups += $roleGroup.Name
        }

        $script:ConfigData['NceAuthApp'] = @{
            Name = $displayName
            ClientId = $app.AppId
            ObjectId = $app.Id
            ServicePrincipalId = $sp.Id
            UniqueName = $uniqueName
            KeyVaultSecretName = $kvSecretName
            AssignedGroups = $assignedGroups
        }

        return $script:ConfigData['NceAuthApp']
    }
    catch {
        Write-Log "Failed to create the NCE auth app: $_" -Level Error
        throw
    }
}

function New-NeologikAgentBlueprint {
    <#
    .SYNOPSIS
        Creates the environment's Microsoft Entra Agent ID agent identity blueprint (and its
        principal), owned by the deployment service principal, and gives the pipeline what it
        needs to act AS the blueprint.

    .DESCRIPTION
        Least-privilege Graph model (project#2144). Creating a blueprint, its principal and
        its credentials needs tenant-wide Graph application permissions, so those one-off
        operations run HERE under the Global Administrator instead of being granted to the
        deployment service principal. The deployment pipeline then:
          - ensures the agent identity token service's federated identity credential on the
            blueprint and removes retired per-workload credentials as the deployment SP
            (AgentIdentityBlueprint.AddRemoveCreds.All - the one residual Agent ID role,
            project#2221), and
          - mints agent identities and agent users AS THE BLUEPRINT, exchanging its GitHub
            OIDC token through the flexible federated identity credentials created below
            (neo-env-config scripts/get-blueprint-token.sh). Agent identity creation is
            inherent to every blueprint principal (AgentIdentity.CreateAsManager); agent
            user creation uses AgentIdUser.ReadWrite.IdentityParentedBy, granted here to the
            blueprint principal and scoped to that blueprint's children only.
        Idempotent: get-or-create by display name; ownership, the principal, the Graph role
        and each credential are added only when missing. The blueprint's display name is the
        pipeline's lookup key and MUST match neo-infrastructure exactly:
        'Neologik Agent Blueprint - <key> - <solutionShortName>'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeploySpObjectId,

        [Parameter(Mandatory = $true)]
        [string]$SponsorUserId,

        [Parameter(Mandatory = $false)]
        [string]$BlueprintKey = 'default'
    )

    $shortName = [string]$script:ConfigData['SolutionShortName']
    $displayName = "Neologik Agent Blueprint - $BlueprintKey - $shortName"
    $graph = 'https://graph.microsoft.com/v1.0'
    $graphBeta = 'https://graph.microsoft.com/beta'
    $odataHeaders = @{ 'OData-Version' = '4.0' }
    # The deployment pipeline repositories allowed to obtain a token as the blueprint. Each
    # credential is bound to the immutable repository id, so a renamed or forked repository
    # gains nothing. Subject shape: repo:<org>/<repo>:environment:<env> (workflow_dispatch
    # jobs bound to a GitHub environment) or repo:<org>/<repo>:ref:refs/heads/<branch>.
    $pipelineRepositories = @(
        @{ Name = 'neo-infrastructure'; Id = '995398788' },
        @{ Name = 'neo-bot-service';    Id = '995400343' },
        @{ Name = 'neo-env-config';     Id = '995441655' }
    )

    Write-Log "Ensuring the agent identity blueprint '$displayName'..." -Level Info

    try {
        # 1. Blueprint application (get-or-create by display name). Bodies go as JSON strings:
        #    Invoke-MgGraphRequest's hashtable serialisation recurses into string indexers.
        $escaped = $displayName -replace "'", "''"
        $found = Invoke-MgGraphRequest -Method GET -Uri "$graph/applications?`$filter=displayName eq '$escaped'&`$select=id,appId" -ErrorAction Stop
        $blueprint = @($found.value) | Select-Object -First 1
        if ($blueprint) {
            Write-Log "Blueprint already exists (Client ID: $($blueprint.appId))" -Level Info
        }
        else {
            $body = @{
                '@odata.type'        = 'Microsoft.Graph.AgentIdentityBlueprint'
                displayName          = $displayName
                'sponsors@odata.bind' = @("$graph/users/$SponsorUserId")
                'owners@odata.bind'   = @("$graph/directoryObjects/$DeploySpObjectId")
            } | ConvertTo-Json -Depth 5 -Compress
            $blueprint = Invoke-MgGraphRequest -Method POST -Uri "$graph/applications/microsoft.graph.agentIdentityBlueprint" `
                -Headers $odataHeaders -Body $body -ContentType 'application/json' -ErrorAction Stop
            Write-Log "Blueprint created (Client ID: $($blueprint.appId))" -Level Success
        }
        $blueprintObjectId = [string]$blueprint.id
        $blueprintAppId = [string]$blueprint.appId

        # 2. Deployment SP as owner of the blueprint application (adoption of pipeline-created
        #    blueprints; the creator above is already an owner).
        $owners = Invoke-MgGraphRequest -Method GET -Uri "$graph/applications/$blueprintObjectId/owners?`$select=id" -ErrorAction Stop
        if (@($owners.value | ForEach-Object { $_.id }) -contains $DeploySpObjectId) {
            Write-Log "Deployment SP is already an owner of the blueprint" -Level Info
        }
        else {
            $ref = @{ '@odata.id' = "$graph/directoryObjects/$DeploySpObjectId" } | ConvertTo-Json -Compress
            Invoke-MgGraphRequest -Method POST -Uri "$graph/applications/$blueprintObjectId/owners/`$ref" -Body $ref -ContentType 'application/json' -ErrorAction Stop | Out-Null
            Write-Log "Deployment SP added as owner of the blueprint" -Level Success
        }

        # 3. Blueprint principal (get-or-create by appId; a create fired within seconds of the
        #    application's creation is rejected until it replicates - retry that only).
        $principal = $null
        $sp = Invoke-MgGraphRequest -Method GET -Uri "$graph/servicePrincipals?`$filter=appId eq '$blueprintAppId'&`$select=id" -ErrorAction Stop
        $principal = @($sp.value) | Select-Object -First 1
        if ($principal) {
            Write-Log "Blueprint principal already exists" -Level Info
        }
        else {
            $body = @{ appId = $blueprintAppId } | ConvertTo-Json -Compress
            for ($attempt = 1; $attempt -le 10; $attempt++) {
                try {
                    $principal = Invoke-MgGraphRequest -Method POST -Uri "$graph/servicePrincipals/microsoft.graph.agentIdentityBlueprintPrincipal" `
                        -Headers $odataHeaders -Body $body -ContentType 'application/json' -ErrorAction Stop
                    Write-Log "Blueprint principal created" -Level Success
                    break
                }
                catch {
                    if ($attempt -lt 10 -and ($_.Exception.Message -match 'local tenant|does not exist')) {
                        Write-Log "Blueprint not yet replicated - retrying in 15 seconds ($attempt of 10)" -Level Warning
                        Start-Sleep -Seconds 15
                        continue
                    }
                    throw
                }
            }
        }
        $principalId = [string]$principal.id

        # 4. Deployment SP as owner of the principal too (application ownership does not extend
        #    to the service principal object).
        $spOwners = Invoke-MgGraphRequest -Method GET -Uri "$graph/servicePrincipals/$principalId/owners?`$select=id" -ErrorAction Stop
        if (@($spOwners.value | ForEach-Object { $_.id }) -contains $DeploySpObjectId) {
            Write-Log "Deployment SP is already an owner of the blueprint principal" -Level Info
        }
        else {
            $ref = @{ '@odata.id' = "$graph/directoryObjects/$DeploySpObjectId" } | ConvertTo-Json -Compress
            Invoke-MgGraphRequest -Method POST -Uri "$graph/servicePrincipals/$principalId/owners/`$ref" -Body $ref -ContentType 'application/json' -ErrorAction Stop | Out-Null
            Write-Log "Deployment SP added as owner of the blueprint principal" -Level Success
        }

        # 5. The blueprint principal's own Graph role: agent users under this blueprint only.
        Grant-GraphAppRolePermissions -PrincipalId $principalId -PrincipalDescription 'agent identity blueprint principal' `
            -AppRoles @('AgentIdUser.ReadWrite.IdentityParentedBy')

        # 6. GitHub OIDC flexible federated identity credentials - one per pipeline repository,
        #    get-or-create by name. Flexible credentials are a beta Graph feature (claims
        #    expression instead of a fixed subject); the token exchange they enable is what
        #    lets the pipeline act as the blueprint without any stored secret.
        $existingCreds = Invoke-MgGraphRequest -Method GET -Uri "$graphBeta/applications/$blueprintObjectId/federatedIdentityCredentials?`$select=name" -ErrorAction Stop
        $existingNames = @($existingCreds.value | ForEach-Object { $_.name })
        $credentialNames = @()
        foreach ($repo in $pipelineRepositories) {
            $credName = "github-oidc-$($repo.Name)"
            $credentialNames += $credName
            if ($existingNames -contains $credName) {
                Write-Log "Federated credential '$credName' already present" -Level Info
                continue
            }
            $expression = "claims['sub'] matches 'repo:Neologik-AI/$($repo.Name):*' and claims['repository_id'] eq '$($repo.Id)'"
            $body = @{
                name                     = $credName
                issuer                   = 'https://token.actions.githubusercontent.com'
                audiences                = @('api://AzureADTokenExchange')
                description              = "Neologik deployment pipeline ($($repo.Name)) acts as this blueprint to mint agent identities and users"
                claimsMatchingExpression = @{ value = $expression; languageVersion = 1 }
            } | ConvertTo-Json -Depth 5 -Compress
            Invoke-MgGraphRequest -Method POST -Uri "$graphBeta/applications/$blueprintObjectId/federatedIdentityCredentials" `
                -Body $body -ContentType 'application/json' -ErrorAction Stop | Out-Null
            Write-Log "Federated credential '$credName' added" -Level Success
        }

        $script:ConfigData['AgentBlueprint'] = @{
            Key = $BlueprintKey
            DisplayName = $displayName
            ClientId = $blueprintAppId
            ObjectId = $blueprintObjectId
            PrincipalId = $principalId
            SponsorUserId = $SponsorUserId
            GitHubCredentials = $credentialNames
        }
        return $script:ConfigData['AgentBlueprint']
    }
    catch {
        Write-Log "Failed to ensure the agent identity blueprint: $_" -Level Error
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

        # Optional: when empty (e.g. a client-managed service principal whose secret was
        # not shared), the Key Vault is created but the deploy-SP secret is not stored.
        [Parameter(Mandatory = $false)]
        [string]$ClientSecret = "",

        [Parameter(Mandatory = $true)]
        [array]$SecurityGroups,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    Write-Log "Creating Key Vault..." -Level Info

    try {
        Import-Module Az.KeyVault -ErrorAction Stop

        # Confirm the Microsoft.KeyVault provider (registration submitted at step 5c) before creating
        Confirm-ResourceProviderReady -Namespaces @('Microsoft.KeyVault')

        # Check if Key Vault exists
        $existingKv = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName -ErrorAction SilentlyContinue

        if ($existingKv) {
            Write-Log "Key Vault '$KeyVaultName' already exists" -Level Info
            $keyVault = $existingKv
        }
        else {
            Write-Log "Creating Key Vault: $KeyVaultName..." -Level Info
            
            # Create Key Vault
            # Resource tags (project#1173): applied on the create call; empty splat when disabled.
            $tagParams = @{}
            $resourceTags = Get-NeologikResourceTags
            if ($resourceTags) { $tagParams['Tag'] = $resourceTags }
            $keyVault = New-AzKeyVault -ResourceGroupName $ResourceGroupName `
                -VaultName $KeyVaultName `
                -Location $Location `
                @tagParams `
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

        # Now store the client secret (with retry for permission propagation).
        # When no secret was supplied (e.g. a client-managed service principal), the vault
        # is still created but the secret is left for the client to populate manually.
        $secretName = "neologik-deployment-service-principle-secret"

        if ([string]::IsNullOrWhiteSpace($ClientSecret)) {
            Write-Log "No client secret supplied - skipping secret storage. The client must add '$secretName' to Key Vault '$KeyVaultName' before the first deployment." -Level Warning
            Write-Host "`n  ⚠ Key Vault created, but no deploy-SP secret was stored." -ForegroundColor Yellow
            Write-Host "    Add the secret '$secretName' to '$KeyVaultName' before deploying." -ForegroundColor Yellow
        }
        else {
            Write-Log "Storing service principal client secret in Key Vault..." -Level Info

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

# Providers the onboarding script itself creates resources with (resource group, Key Vault,
# deployment storage account, managed identities). They are submitted first and confirmed before
# the first of those resources is created. Every entry must also appear in resource-providers.txt.
$script:OnboardingProviders = @(
    'Microsoft.Resources',
    'Microsoft.KeyVault',
    'Microsoft.Storage',
    'Microsoft.ManagedIdentity',
    'Microsoft.Compute'
)

function Get-PlatformResourceProviderList {
    <#
    .SYNOPSIS
        Reads resource-providers.txt, the single list of Azure resource providers and preview
        features the platform requires.
    .DESCRIPTION
        One entry per line; blank lines and lines starting with '#' are ignored. A provider is a
        namespace (Microsoft.Storage); a preview feature is Namespace/FeatureName
        (Microsoft.Compute/EncryptionAtHost). The file is the only place a provider is ever added.
        Fails when the file is missing, empty, malformed, or lacks a provider the script itself
        needs. Returns Providers (onboarding providers first, then file order) and Features.
    #>
    [CmdletBinding()]
    param()

    $path = Join-Path $PSScriptRoot 'resource-providers.txt'
    if (-not (Test-Path $path)) {
        throw "Resource provider list not found: $path. The file ships with the onboarding kit; restore it before running."
    }

    $providers = [System.Collections.Generic.List[string]]::new()
    $featureKeys = [System.Collections.Generic.List[string]]::new()
    $features = @()
    $lineNumber = 0
    foreach ($raw in @(Get-Content -Path $path)) {
        $lineNumber++
        # Anything from '#' onwards is a comment, whether the line starts with it or not.
        $line = ("$raw" -split '#', 2)[0].Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^(?<ns>[A-Za-z0-9]+\.[A-Za-z0-9.]+)/(?<feature>[A-Za-z0-9]+)$') {
            if (-not $featureKeys.Contains($line)) {
                $featureKeys.Add($line)
                $features += @{ Provider = $Matches.ns; Feature = $Matches.feature }
            }
        }
        elseif ($line -match '^[A-Za-z0-9]+\.[A-Za-z0-9.]+$') {
            if (-not $providers.Contains($line)) { $providers.Add($line) }
        }
        else {
            throw "resource-providers.txt line ${lineNumber}: '$line' is not a provider namespace (Microsoft.Example) or a preview feature (Microsoft.Example/FeatureName)."
        }
    }
    if ($providers.Count -eq 0) { throw "resource-providers.txt lists no resource providers." }

    $missing = @($script:OnboardingProviders | Where-Object { -not $providers.Contains($_) })
    if ($missing.Count -gt 0) {
        throw "resource-providers.txt is missing providers the onboarding script itself needs: $($missing -join ', ')."
    }
    foreach ($f in $features) {
        if (-not $providers.Contains($f.Provider)) {
            throw "resource-providers.txt lists feature $($f.Provider)/$($f.Feature) but not its provider $($f.Provider)."
        }
    }

    $ordered = @($script:OnboardingProviders) + @($providers | Where-Object { $script:OnboardingProviders -notcontains $_ })
    Write-Log "Loaded resource provider list: $($ordered.Count) providers, $($features.Count) preview features ($path)" -Level Info
    return [pscustomobject]@{ Providers = [string[]]$ordered; Features = @($features); Path = $path }
}

function Start-ResourceProviderRegistration {
    <#
    .SYNOPSIS
        Submits registration for every provider and preview feature in the list without waiting.
    .DESCRIPTION
        Registration is asynchronous in Azure: each request returns in about a second and Azure
        completes it in the background. The onboarding providers are submitted first, then the
        rest, so the script carries on with the remaining steps and confirms later with
        Wait-ResourceProviderRegistration. Entries already Registered (in Azure or in the
        checkpoint) are skipped. A request that cannot be submitted (unknown namespace or
        feature, missing permission) stops the run: the list file is the only input.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ProviderList
    )

    Write-Log "Submitting resource provider registrations ($($ProviderList.Providers.Count) providers, $($ProviderList.Features.Count) preview features)..." -Level Info
    $submitted = 0
    $alreadyRegistered = 0

    foreach ($ns in $ProviderList.Providers) {
        if ($script:ProviderRegistrations[$ns] -eq 'Registered') { $alreadyRegistered++; continue }
        try {
            $state = (Get-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Select-Object -First 1).RegistrationState
            if ($state -eq 'Registered') {
                $script:ProviderRegistrations[$ns] = 'Registered'
                $alreadyRegistered++
                continue
            }
            if ($state -ne 'Registering') {
                Register-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Out-Null
            }
            $script:ProviderRegistrations[$ns] = 'Requested'
            $submitted++
            Write-Log "Registration requested: $ns (was $state)" -Level Info
        }
        catch {
            Write-Log "Failed to request registration of resource provider '$ns': $_" -Level Error
            throw
        }
    }

    foreach ($f in $ProviderList.Features) {
        $key = "$($f.Provider)/$($f.Feature)"
        if ($script:ProviderRegistrations[$key] -eq 'Registered') { $alreadyRegistered++; continue }
        try {
            $state = (Get-AzProviderFeature -ProviderNamespace $f.Provider -FeatureName $f.Feature -ErrorAction Stop).RegistrationState
            if ($state -eq 'Registered') {
                $script:ProviderRegistrations[$key] = 'Registered'
                $alreadyRegistered++
                continue
            }
            if ($state -notin @('Registering', 'Pending')) {
                Register-AzProviderFeature -ProviderNamespace $f.Provider -FeatureName $f.Feature -ErrorAction Stop | Out-Null
            }
            $script:ProviderRegistrations[$key] = 'Requested'
            $submitted++
            Write-Log "Feature registration requested: $key (was $state)" -Level Info
        }
        catch {
            Write-Log "Failed to request registration of preview feature '$key': $_" -Level Error
            throw
        }
    }

    Save-Checkpoint -Label 'ProvidersRequested'
    Write-Host "  Resource providers: $submitted registration request(s) submitted, $alreadyRegistered already registered." -ForegroundColor Gray
    Write-Host "  Azure completes them in the background while onboarding continues." -ForegroundColor Gray
    Write-Log "Resource provider registrations submitted: $submitted requested, $alreadyRegistered already registered" -Level Success
}

function Wait-ResourceProviderRegistration {
    <#
    .SYNOPSIS
        Confirms that the given providers and preview features have reached Registered, polling
        them together in one loop.
    .DESCRIPTION
        Returns the entries still not Registered when the timeout expires (empty when every entry
        is confirmed) and records TimedOut for them in the checkpoint. A request Azure reports as
        NotRegistered is re-submitted once. When a feature reaches Registered its provider is
        re-registered so the feature propagates to it.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Providers = @(),
        [hashtable[]]$Features = @(),
        [int]$TimeoutSeconds = 600,
        [int]$IntervalSeconds = 15
    )

    $pendingProviders = [System.Collections.Generic.List[string]]::new()
    foreach ($ns in $Providers) {
        if ($script:ProviderRegistrations[$ns] -ne 'Registered') { $pendingProviders.Add($ns) }
    }
    $pendingFeatures = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($f in $Features) {
        if ($script:ProviderRegistrations["$($f.Provider)/$($f.Feature)"] -ne 'Registered') { $pendingFeatures.Add($f) }
    }
    if ($pendingProviders.Count -eq 0 -and $pendingFeatures.Count -eq 0) { return @() }

    Write-Log "Waiting for $($pendingProviders.Count) provider(s) and $($pendingFeatures.Count) preview feature(s) to reach Registered (timeout ${TimeoutSeconds}s)..." -Level Info
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $resubmitted = @{}

    while ($true) {
        $changed = $false

        foreach ($ns in @($pendingProviders)) {
            try {
                $state = (Get-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Select-Object -First 1).RegistrationState
            }
            catch {
                Write-Log "Could not read the state of resource provider '$ns': $_" -Level Warning
                continue
            }
            if ($state -eq 'Registered') {
                $script:ProviderRegistrations[$ns] = 'Registered'
                $pendingProviders.Remove($ns) | Out-Null
                $changed = $true
                Write-Log "Resource provider registered: $ns" -Level Success
            }
            elseif ($state -ne 'Registering' -and -not $resubmitted[$ns]) {
                Write-Log "Resource provider '$ns' reports $state; re-submitting the registration" -Level Warning
                $resubmitted[$ns] = $true
                try { Register-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Out-Null }
                catch { Write-Log "Re-submission failed for resource provider '$ns': $_" -Level Warning }
            }
        }

        foreach ($f in @($pendingFeatures)) {
            $key = "$($f.Provider)/$($f.Feature)"
            try {
                $state = (Get-AzProviderFeature -ProviderNamespace $f.Provider -FeatureName $f.Feature -ErrorAction Stop).RegistrationState
            }
            catch {
                Write-Log "Could not read the state of preview feature '$key': $_" -Level Warning
                continue
            }
            if ($state -eq 'Registered') {
                try { Register-AzResourceProvider -ProviderNamespace $f.Provider -ErrorAction Stop | Out-Null }
                catch { Write-Log "Provider refresh after preview feature '$key' failed: $_" -Level Warning }
                $script:ProviderRegistrations[$key] = 'Registered'
                $pendingFeatures.Remove($f) | Out-Null
                $changed = $true
                Write-Log "Preview feature registered: $key" -Level Success
            }
            elseif ($state -notin @('Registering', 'Pending') -and -not $resubmitted[$key]) {
                Write-Log "Preview feature '$key' reports $state; re-submitting the registration" -Level Warning
                $resubmitted[$key] = $true
                try { Register-AzProviderFeature -ProviderNamespace $f.Provider -FeatureName $f.Feature -ErrorAction Stop | Out-Null }
                catch { Write-Log "Re-submission failed for preview feature '$key': $_" -Level Warning }
            }
        }

        if ($changed) { Save-Checkpoint -Label 'ProvidersConfirmed' }
        if ($pendingProviders.Count -eq 0 -and $pendingFeatures.Count -eq 0) { break }
        if ((Get-Date) -ge $deadline) { break }
        Write-Host "  Waiting for $($pendingProviders.Count + $pendingFeatures.Count) registration(s) to complete..." -ForegroundColor Gray
        Start-Sleep -Seconds $IntervalSeconds
    }

    $remaining = @($pendingProviders) + @($pendingFeatures | ForEach-Object { "$($_.Provider)/$($_.Feature)" })
    if ($remaining.Count -gt 0) {
        foreach ($key in $remaining) { $script:ProviderRegistrations[$key] = 'TimedOut' }
        Save-Checkpoint -Label 'ProvidersTimedOut'
    }
    return $remaining
}

function Confirm-ResourceProviderReady {
    <#
    .SYNOPSIS
        Confirms that the named providers (submitted at step 5c) are Registered before a resource
        of that type is created. Stops the run with a clear message if one is still registering.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Namespaces
    )

    $remaining = Wait-ResourceProviderRegistration -Providers $Namespaces -TimeoutSeconds 600
    if ($remaining.Count -eq 0) {
        Write-Log "Resource provider(s) confirmed: $($Namespaces -join ', ')" -Level Info
        return
    }
    Write-Host ""
    Write-Host "  Resource providers this script needs are still registering: $($remaining -join ', ')" -ForegroundColor Yellow
    Write-Host "  Azure continues the registration in the background. Wait a few minutes, then run the script" -ForegroundColor Yellow
    Write-Host "  again and choose Y to resume; confirmed providers are skipped." -ForegroundColor Yellow
    Write-Host ""
    throw "Resource providers still registering: $($remaining -join ', '). Re-run the script to resume once they are registered."
}

function Complete-ResourceProviderRegistration {
    <#
    .SYNOPSIS
        Final confirmation of the full provider and preview-feature list before the configuration
        is exported. Anything still pending is reported and recorded in the configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ProviderList
    )

    Write-Log "Confirming the full resource provider list..." -Level Info
    $remaining = Wait-ResourceProviderRegistration -Providers $ProviderList.Providers -Features $ProviderList.Features -TimeoutSeconds 600
    $script:ConfigData['ResourceProvidersPending'] = @($remaining)
    if ($remaining.Count -eq 0) {
        Write-Log "All $($ProviderList.Providers.Count) resource providers and $($ProviderList.Features.Count) preview features are registered" -Level Success
        Write-Host "  Resource providers: all $($ProviderList.Providers.Count) providers and $($ProviderList.Features.Count) preview features registered." -ForegroundColor Green
        return
    }
    Write-Host ""
    Write-Host "  The following registrations have not completed yet (Azure continues them in the background):" -ForegroundColor Yellow
    $remaining | ForEach-Object { Write-Host "     - $_" -ForegroundColor Yellow }
    Write-Host "  Before the platform deployment, confirm them by running Register-NeologikResourceProviders.ps1" -ForegroundColor Gray
    Write-Host "  on this subscription. They are listed as ResourceProvidersPending in the configuration file." -ForegroundColor Gray
    Write-Host ""
    Write-Log "Resource provider registration still pending for: $($remaining -join ', ')" -Level Warning
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

        # Confirm the Microsoft.Storage provider (registration submitted at step 5c) before creating
        Confirm-ResourceProviderReady -Namespaces @('Microsoft.Storage')

        # Check if Storage Account exists
        $existingSa = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue

        if ($existingSa) {
            Write-Log "Storage Account '$StorageAccountName' already exists" -Level Info
            $storageAccount = $existingSa
        }
        else {
            Write-Log "Creating Storage Account: $StorageAccountName..." -Level Info
            
            # Resource tags (project#1173): applied on the create call; empty splat when disabled.
            $tagParams = @{}
            $resourceTags = Get-NeologikResourceTags
            if ($resourceTags) { $tagParams['Tag'] = $resourceTags }
            $storageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName `
                -Name $StorageAccountName `
                -Location $Location `
                -SkuName Standard_LRS `
                -Kind StorageV2 `
                -AllowBlobPublicAccess $false `
                @tagParams `
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

        # Create the blob containers via the management plane (ARM). A data-plane call
        # (New-AzStorageContainer -UseConnectedAccount) needs a storage-audience token,
        # which a static access-token login (CI) cannot mint - and shared key access is
        # disabled above. The ARM path uses the same token as the rest of the script.
        $certContainerName = "certificate"
        $jsonContainerName = "json"
        $logsContainerName = "logs"

        foreach ($containerName in @($certContainerName, $jsonContainerName, $logsContainerName)) {
            Write-Log "Creating blob container '$containerName'..." -Level Info
            $existingContainer = Get-AzRmStorageContainer -ResourceGroupName $ResourceGroupName `
                -StorageAccountName $StorageAccountName `
                -ContainerName $containerName `
                -ErrorAction SilentlyContinue

            if ($existingContainer) {
                Write-Log "Blob container '$containerName' already exists" -Level Info
            }
            else {
                New-AzRmStorageContainer -ResourceGroupName $ResourceGroupName `
                    -StorageAccountName $StorageAccountName `
                    -ContainerName $containerName `
                    -PublicAccess None -ErrorAction Stop | Out-Null
                Write-Log "Blob container '$containerName' created successfully" -Level Success
            }
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
        [string]$EnvironmentType = "",

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentIndex = "",

        [Parameter(Mandatory = $false)]
        [string]$ScriptRunnerIdentityName = "",

        [Parameter(Mandatory = $false)]
        [string]$SqlIdentityName = ""
    )

    Write-Log "Creating Managed Identities..." -Level Info

    try {
        Import-Module Az.ManagedServiceIdentity -ErrorAction Stop

        # Confirm the Microsoft.ManagedIdentity provider (registration submitted at step 5c) before creating
        Confirm-ResourceProviderReady -Namespaces @('Microsoft.ManagedIdentity')

        # Name suffix = the platform solution short name (neo{org}{index}, e.g.
        # neodmo01) - naming convention alignment, project#1063. Environment
        # type never appears in names.
        $shortName = if (-not [string]::IsNullOrWhiteSpace([string]$script:ConfigData['SolutionShortName'])) { [string]$script:ConfigData['SolutionShortName'] }
                     elseif ([string]::IsNullOrWhiteSpace($OrganizationCode)) { "" }
                     else { "neo$($OrganizationCode.ToLower())$EnvironmentIndex" }
        $nameSuffix = if ([string]::IsNullOrWhiteSpace($shortName)) { "" } else { "-$shortName" }
        $displaySuffix = if ([string]::IsNullOrWhiteSpace($shortName)) { "" } else { " - $shortName" }

        # Script-runner and SQL identity names were resolved during configuration
        # gathering (answer file / prompt / computed); empty on checkpoints written
        # before the fields existed - fall back to the computed Neologik-standard name.
        $scriptRunnerName = if (-not [string]::IsNullOrWhiteSpace($ScriptRunnerIdentityName)) { $ScriptRunnerIdentityName.Trim() } else { "neologik-script-runner-service-connection$nameSuffix" }
        $sqlIdentityName = if (-not [string]::IsNullOrWhiteSpace($SqlIdentityName)) { $SqlIdentityName.Trim() } else { "neologik-sql-managed-identity$nameSuffix" }

        $managedIdentities = @(
            @{
                Name = $scriptRunnerName
                DisplayName = "Neologik Script Runner Service Connection$displaySuffix"
                Roles = @('Contributor')
                RGRoles = @('Key Vault Secrets Officer', 'Azure Bot Service Contributor Role')
                # No GraphAppRoles: the Script Runner UAMI no longer manages app registrations
                # — that work runs as the deploy service connection (ensure-app-regs.sh) — so
                # Application.Read.All / ReadWrite.OwnedBy on the UAMI would be surplus.
            },
            @{
                Name = $sqlIdentityName
                DisplayName = "Neologik SQL Managed Identity$displaySuffix"
                Roles = @()
                EntraRole = 'Directory Readers'
            }
        )

        $createdIdentities = @()

        # Resource tags (project#1173): applied on the create call; empty splat when disabled.
        $tagParams = @{}
        $resourceTags = Get-NeologikResourceTags
        if ($resourceTags) { $tagParams['Tag'] = $resourceTags }

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
                        @tagParams `
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
                    # directoryRoleTemplates rejects $filter (Graph Request_UnsupportedQuery), so
                    # enumerate and match client-side. This branch only runs in a tenant where the
                    # role has never been activated - a virgin tenant.
                    $roleTemplate = Get-MgDirectoryRoleTemplate -All -ErrorAction Stop |
                        Where-Object { $_.DisplayName -eq $miDef.EntraRole } | Select-Object -First 1
                    if (-not $roleTemplate) {
                        throw "Directory role template '$($miDef.EntraRole)' not found in tenant $($script:ConfigData['TenantId'])."
                    }
                    Write-Log "Activating directory role '$($miDef.EntraRole)' from its template (first use in this tenant)..." -Level Info
                    $entraRole = New-MgDirectoryRole -RoleTemplateId $roleTemplate.Id -ErrorAction Stop
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

function Copy-NeologikFileToStorage {
    <#
    .SYNOPSIS
        Uploads a local file to a Storage Account blob container and verifies it
        landed by reading the blob back. Returns $true/$false; retries cover
        data-plane RBAC propagation after role assignment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [int]$MaxRetries = 12
    )

    $blobName = Split-Path -Leaf $FilePath
    try {
        # Storage context using Entra ID authentication
        $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
    }
    catch {
        Write-Log "Could not create a storage context for '$StorageAccountName': $_" -Level Warning
        return $false
    }

    $retryCount = 0
    while ($retryCount -lt $MaxRetries) {
        try {
            Set-AzStorageBlobContent -File $FilePath `
                -Container $ContainerName `
                -Blob $blobName `
                -Context $ctx `
                -Force `
                -ErrorAction Stop | Out-Null
            # Read the blob back so success means the file is verifiably there
            $null = Get-AzStorageBlob -Container $ContainerName -Blob $blobName -Context $ctx -ErrorAction Stop
            Write-Log "$Description uploaded to Storage Account: $StorageAccountName/$ContainerName/$blobName" -Level Success
            return $true
        }
        catch {
            $retryCount++
            if ($retryCount -lt $MaxRetries) {
                Write-Log "Storage data-plane permission not yet propagated. Retrying in 20 seconds... (Attempt $retryCount of $MaxRetries)" -Level Warning
                Start-Sleep -Seconds 20
            }
            else {
                Write-Log "Failed to upload $Description to Storage Account after $MaxRetries attempt(s) - it remains locally at ${FilePath}: $_" -Level Warning
            }
        }
    }
    return $false
}

function Export-ConfigurationData {
    <#
    .SYNOPSIS
        Exports configuration data to JSON file and displays summary.
    #>
    [CmdletBinding()]
    param()

    Write-Log "Exporting configuration data..." -Level Info

    try {
        # Custom resource tags may have round-tripped through the checkpoint as an object;
        # export whatever shape is held (empty object when tagging is disabled).
        $exportCustomTags = if ($null -ne $script:ConfigData['ResourceTagsCustom']) { $script:ConfigData['ResourceTagsCustom'] } else { @{} }

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
            'HostName' = $script:ConfigData['HostName']
            'BudgetEmailAddresses' = $script:ConfigData['BudgetEmailAddresses']
            'BudgetEmailFrequency' = $script:ConfigData['BudgetEmailFrequency']
            'ResourceProvidersPending' = @($script:ConfigData['ResourceProvidersPending'])
            'ResourceTagsEnabled' = [bool]$script:ConfigData['ResourceTagsEnabled']
            'ResourceTagsCustom' = $exportCustomTags
            'InvitedGuestUsers' = $script:ConfigData['InvitedGuestUsers']
            'ExistingAccountsAdded' = $script:ConfigData['ExistingAccountsAdded']
            'SecurityGroups' = $script:ConfigData['SecurityGroups']
            'AppRegistration' = $script:ConfigData['AppRegistration']
            'NceAuthApp' = $script:ConfigData['NceAuthApp']
            'AgentBlueprint' = $script:ConfigData['AgentBlueprint']
            'KeyVault' = $script:ConfigData['KeyVault']
            'StorageAccount' = $script:ConfigData['StorageAccount']
            'ManagedIdentities' = $script:ConfigData['ManagedIdentities']
            'RoleAssignments' = $script:ConfigData['RoleAssignments']
        }

        # Export to JSON
        $orderedConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:OutputFile -Encoding UTF8
        Write-Log "Configuration exported to: $script:OutputFile" -Level Success

        # Upload the JSON and log files, recording the outcomes - Neologik
        # retrieves the configuration from the json container, so a failure is
        # surfaced prominently in the completion summary. Non-interactive (CI)
        # sessions get one attempt: static access-token sessions cannot
        # authenticate data-plane calls (full logins can), so retries are pointless.
        $uploadRetries = if ($script:NonInteractiveMode) { 1 } else { 12 }
        $script:ConfigData['ConfigUploadedToStorage'] = $false
        $script:ConfigData['LogUploadedToStorage'] = $false
        if ($script:ConfigData['StorageAccount']) {
            Write-Log "Copying configuration file to Storage Account..." -Level Info
            $script:ConfigData['ConfigUploadedToStorage'] = Copy-NeologikFileToStorage `
                -FilePath $script:OutputFile `
                -StorageAccountName $script:ConfigData['StorageAccount'].Name `
                -ContainerName $script:ConfigData['StorageAccount'].JsonContainerName `
                -Description "Configuration file" `
                -MaxRetries $uploadRetries

            Write-Log "Copying log file to Storage Account..." -Level Info
            $script:ConfigData['LogUploadedToStorage'] = Copy-NeologikFileToStorage `
                -FilePath $script:LogFile `
                -StorageAccountName $script:ConfigData['StorageAccount'].Name `
                -ContainerName $script:ConfigData['StorageAccount'].LogsContainerName `
                -Description "Log file" `
                -MaxRetries $uploadRetries
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
        if ($script:ConfigData['ConfigUploadedToStorage']) {
            Write-Host "  Configuration (Blob):  $($script:ConfigData['StorageAccount'].Name)/$($script:ConfigData['StorageAccount'].JsonContainerName)/$(Split-Path -Leaf $script:OutputFile)" -ForegroundColor Cyan
        }
        Write-Host "  Log File (Local):      $script:LogFile" -ForegroundColor Cyan
        if ($script:ConfigData['LogUploadedToStorage']) {
            Write-Host "  Log File (Blob):       $($script:ConfigData['StorageAccount'].Name)/$($script:ConfigData['StorageAccount'].LogsContainerName)/$(Split-Path -Leaf $script:LogFile)" -ForegroundColor Cyan
        }
        if ($script:ConfigData['StorageAccount'] -and -not $script:ConfigData['ConfigUploadedToStorage']) {
            Write-Host ""
            Write-Host "  ⚠️  Configuration file NOT uploaded - Neologik retrieves it from the Storage Account." -ForegroundColor Red
            Write-Host "      Upload it manually: Azure Portal > '$($script:ConfigData['StorageAccount'].Name)' > Containers > '$($script:ConfigData['StorageAccount'].JsonContainerName)' > Upload" -ForegroundColor Yellow
        }
        Write-Host ""

        Write-Host "⚠️  Next Steps:" -ForegroundColor Yellow
        if ($script:ConfigData['ConfigUploadedToStorage']) {
            Write-Host "  1. Review the configuration file (available locally and in Storage Account)"
        }
        else {
            Write-Host "  1. Review the configuration file (local only - see the upload warning above)"
        }
        Write-Host "  2. Ensure that service principal client secret is securely stored in Key Vault: $($script:ConfigData['KeyVault'].Name)"
        Write-Host "     Secret name: $($script:ConfigData['KeyVault'].SecretName)"
        Write-Host "  3. Provide your TLS certificate in ONE of two ways:"
        Write-Host "     (you may create your own secure .pfx file via the instructions in PFX-CERT-GUIDE.md)"
        Write-Host "     Option A - import the .pfx directly into Key Vault as a certificate:"
        Write-Host "       In the Azure Portal (portal.azure.com), open Key Vault"
        Write-Host "       '$($script:ConfigData['KeyVault'].Name)' > Certificates > Generate/Import,"
        Write-Host "       choose Import, name the certificate 'keyvault-neo-ingress', select your"
        Write-Host "       .pfx file and enter its password."
        Write-Host "       (the password is consumed at import - do not store or share it)"
        Write-Host "     Option B - upload to the Storage Account: a ready-made .pfx file"
        Write-Host "       or, if you cannot produce a .pfx, the raw certificate files (private key,"
        Write-Host "       server certificate, CA bundle) for Neologik to assemble:"
        Write-Host "       Storage Account: $($script:ConfigData['StorageAccount'].Name)"
        Write-Host "       Container:       $($script:ConfigData['StorageAccount'].CertificateContainerName)"
        Write-Host "       Authentication:  Microsoft Entra ID (your Azure account)"
        Write-Host "  4. If you uploaded a .pfx to the Storage Account (Option B): store its"
        Write-Host "     password in Key Vault '$($script:ConfigData['KeyVault'].Name)' as a secret named:"
        Write-Host "     neologik-deployment-certificate-pfx-secret"
        Write-Host ""
    }
    catch {
        Write-Log "Failed to export configuration: $_" -Level Error
        throw
    }
}

#endregion

#region Main Execution

function Import-AnswerFile {
    <#
    .SYNOPSIS
        Loads a predefined-answers JSON file whose values pre-fill the interactive prompts.
    .DESCRIPTION
        Reads the file given by -AnswerFile, or auto-detects 'inputs.json' next to the script.
        Values populate $script:Answers and become the default for the matching
        prompt (Enter accepts, typing overrides). Only configuration inputs are read here; runtime
        decisions (terms acceptance, module install, re-auth, quota/permission warnings) are always
        asked interactively and are never read from the file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    $script:Answers = @{}
    $script:AnswerFilePath = $null

    $candidate = $null
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        if (-not (Test-Path -Path $Path)) {
            throw "Answer file not found: $Path"
        }
        $candidate = (Resolve-Path -Path $Path).Path
    }
    else {
        $p = Join-Path $PSScriptRoot 'inputs.json'
        if (Test-Path -Path $p) { $candidate = $p }
    }

    if (-not $candidate) {
        Write-Log "No answer file found - running fully interactive." -Level Info
        return
    }

    try {
        $json = Get-Content -Path $candidate -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse answer file '$candidate': $_"
    }

    foreach ($prop in $json.PSObject.Properties) {
        if ($prop.Name -eq '_readme') { continue }
        $script:Answers[$prop.Name] = $prop.Value
    }
    $script:AnswerFilePath = $candidate

    Write-Host ""
    Write-Host "  ✓ Loaded predefined inputs: $([System.IO.Path]::GetFileName($candidate))" -ForegroundColor Green
    Write-Host "    These pre-fill the prompts below - press Enter to accept, or type to override." -ForegroundColor Gray
    Write-Log "Loaded answer file: $candidate" -Level Info
}

function Get-Answer {
    <#
    .SYNOPSIS
        Returns the predefined answer for a key, or $null when absent or blank.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ($null -eq $script:Answers -or -not $script:Answers.ContainsKey($Key)) { return $null }
    $val = $script:Answers[$Key]
    if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { return $null }
    return $val
}

function Get-AnswerBool {
    <#
    .SYNOPSIS
        Returns a boolean for an answer-file key, tolerant of JSON booleans and
        true/false/yes/no/1/0 strings. Returns $null when the key is absent, blank, or holds
        an unrecognised value (the caller then warns or falls back as appropriate).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $val = Get-Answer $Key
    if ($null -eq $val) { return $null }
    if ($val -is [bool]) { return [bool]$val }
    if ("$val" -match '^(true|yes|y|1)$') { return $true }
    if ("$val" -match '^(false|no|n|0)$') { return $false }
    Write-Host "  ⚠ Ignoring invalid boolean for '$Key' in answer file (must be true/false): '$val'" -ForegroundColor Yellow
    return $null
}

function Get-PromptLabel {
    <#
    .SYNOPSIS
        Chooses the prompt's value label: "Pre-filled: " when the effective value came from the
        answer file and differs from the built-in default; otherwise "Default: ".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Effective,
        [Parameter(Mandatory = $false)]$Builtin
    )

    if ("$Effective" -ne "$Builtin") { return "Pre-filled: " }
    return "Default: "
}

function Test-ResourceGroupNameError {
    # Returns $null when the resource-group name is valid, otherwise an error string.
    param([string]$Name)
    if ($Name.Length -lt 1 -or $Name.Length -gt 90) { return "Resource group name must be 1-90 characters." }
    if ($Name -notmatch '^[\w\-\.\(\)]+$') { return "Resource group name can only contain alphanumerics, underscores, hyphens, periods, and parentheses." }
    if ($Name -match '\.$') { return "Resource group name cannot end with a period." }
    return $null
}

function Test-KeyVaultNameError {
    # Returns $null when the Key Vault name is valid, otherwise an error string.
    param([string]$Name)
    if ($Name.Length -lt 3 -or $Name.Length -gt 24) { return "Key Vault name must be 3-24 characters." }
    if ($Name -notmatch '^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$') { return "Key Vault name must start with a letter, end with a letter or digit, and contain only letters, digits and hyphens." }
    if ($Name -match '--') { return "Key Vault name cannot contain consecutive hyphens." }
    return $null
}

function Test-StorageAccountNameError {
    # Returns $null when the storage-account name is valid, otherwise an error string.
    param([string]$Name)
    if ($Name.Length -lt 3 -or $Name.Length -gt 24) { return "Storage account name must be 3-24 characters." }
    if ($Name -cnotmatch '^[a-z0-9]+$') { return "Storage account name must be lowercase letters and digits only (no hyphens)." }
    return $null
}

function Test-ManagedIdentityNameError {
    # Returns $null when the managed-identity name is valid, otherwise an error string.
    param([string]$Name)
    if ($Name.Length -lt 3 -or $Name.Length -gt 128) { return "Managed identity name must be 3-128 characters." }
    if ($Name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*$') { return "Managed identity name must start with a letter or digit and contain only letters, digits, hyphens and underscores." }
    return $null
}

function Read-NameWithDefault {
    <#
    .SYNOPSIS
        Prompts for a resource name showing an effective default (computed, or pre-filled from
        the answer file / CLI). Enter accepts the default; typing overrides. Re-prompts until the
        value passes the supplied validator. Returns the accepted name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$DefaultValue,
        [Parameter(Mandatory = $true)][scriptblock]$Validator,
        [string]$LabelPrefix = 'Default: '
    )

    while ($true) {
        Write-Host ""
        Write-Host "${Title}:" -ForegroundColor Cyan
        Write-Host "  $LabelPrefix" -NoNewline -ForegroundColor Gray
        Write-Host $DefaultValue -ForegroundColor Yellow
        Write-Host "  Press Enter to use this value, or type a new one: " -NoNewline -ForegroundColor Gray
        $entered = Read-Host

        $candidate = if ([string]::IsNullOrWhiteSpace($entered)) { $DefaultValue } else { $entered.Trim() }
        $err = & $Validator $candidate
        if ($err) {
            Write-Host "  ✗ $err Please try again." -ForegroundColor Red
            continue
        }
        Write-Host "  ✓ Using: $candidate" -ForegroundColor Green
        return $candidate
    }
}

function Test-AnswerFileComplete {
    <#
    .SYNOPSIS
        True when the answer file supplies every value that has no built-in default, so the
        configuration can be shown as a summary up front without prompting field-by-field.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $script:Answers -or $script:Answers.Count -eq 0) { return $false }

    # Fields with no built-in default must be present.
    foreach ($key in @('organizationCode', 'organizationName', 'fqdn')) {
        if (-not (Get-Answer $key)) { return $false }
    }

    # v5 (Neologik Harness): bots are not gathered at onboarding.
    return $true
}

function Resolve-BudgetEmailRecipients {
    <#
    .SYNOPSIS
        Normalizes the 'budgetCostReportEmailRecipients' answer-file value into an array of
        email addresses. Accepts an array of addresses or a single (optionally comma-separated)
        string; 'none' (or an empty list) disables the cost report and yields an empty array.
        Throws when any address is malformed.
    #>
    [CmdletBinding()]
    param($Value)

    $items = @()
    foreach ($entry in @($Value)) {
        $items += @(([string]$entry) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    if ($items.Count -eq 1 -and $items[0].ToLower() -eq 'none') { return @() }
    $invalid = @($items | Where-Object { $_ -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$' })
    if ($invalid.Count -gt 0) { throw "invalid email address(es): $($invalid -join ', ')." }
    return $items
}

function Get-CafRegionCodes {
    <#
    .SYNOPSIS
        Microsoft Cloud Adoption Framework (CAF) region -> abbreviation map. Static; no Azure call.
        Reference: https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations
    #>
    return @{
        # Americas
        'eastus' = 'eus'; 'eastus2' = 'eus2'; 'westus' = 'wus'; 'westus2' = 'wus2'; 'westus3' = 'wus3'
        'centralus' = 'cus'; 'northcentralus' = 'ncus'; 'southcentralus' = 'scus'; 'westcentralus' = 'wcus'
        'canadacentral' = 'cac'; 'canadaeast' = 'cae'; 'brazilsouth' = 'brs'; 'brazilsoutheast' = 'brse'
        'brazilus' = 'bru'; 'mexicocentral' = 'mxc'; 'chilecentral' = 'clc'
        # Europe
        'northeurope' = 'neu'; 'westeurope' = 'weu'; 'uksouth' = 'uks'; 'ukwest' = 'ukw'
        'francecentral' = 'frc'; 'francesouth' = 'frs'; 'germanywestcentral' = 'gwc'; 'germanynorth' = 'gno'
        'norwayeast' = 'noe'; 'norwaywest' = 'now'; 'swedencentral' = 'sdc'; 'swedensouth' = 'sds'
        'switzerlandnorth' = 'szn'; 'switzerlandwest' = 'szw'; 'italynorth' = 'itn'; 'polandcentral' = 'plc'
        'spaincentral' = 'spc'; 'austriaeast' = 'ate'; 'belgiumcentral' = 'bec'
        # Asia Pacific
        'eastasia' = 'eas'; 'southeastasia' = 'seas'; 'australiaeast' = 'aue'; 'australiasoutheast' = 'ause'
        'australiacentral' = 'auc'; 'australiacentral2' = 'auc2'; 'japaneast' = 'jpe'; 'japanwest' = 'jpw'
        'koreacentral' = 'krc'; 'koreasouth' = 'krs'; 'centralindia' = 'inc'; 'southindia' = 'ins'
        'westindia' = 'inw'; 'jioindiawest' = 'jiw'; 'jioindiacentral' = 'jic'; 'indonesiacentral' = 'idc'
        'malaysiawest' = 'myw'; 'newzealandnorth' = 'nzn'
        # Middle East & Africa
        'southafricanorth' = 'san'; 'southafricawest' = 'saw'; 'uaenorth' = 'uan'; 'uaecentral' = 'uac'
        'qatarcentral' = 'qac'; 'israelcentral' = 'ilc'
        # China (special subscription)
        'chinanorth' = 'cnn'; 'chinanorth2' = 'cnn2'; 'chinanorth3' = 'cnn3'
        'chinaeast' = 'cne'; 'chinaeast2' = 'cne2'; 'chinaeast3' = 'cne3'
        # Government (special subscription)
        'usgovvirginia' = 'ugv'; 'usgovarizona' = 'uga'; 'usgovtexas' = 'ugt'; 'usdodeast' = 'ude'; 'usdodcentral' = 'udc'
        # EUAP
        'centraluseuap' = 'cuse'; 'eastus2euap' = 'eus2e'
        # Geographic groups (returned by Azure API, not for deployment)
        'asia' = 'asia'; 'asiapacific' = 'apac'; 'australia' = 'au'; 'brazil' = 'br'; 'canada' = 'ca'
        'europe' = 'eu'; 'france' = 'fr'; 'germany' = 'de'; 'global' = 'global'; 'india' = 'in'
        'indonesia' = 'id'; 'israel' = 'il'; 'italy' = 'it'; 'japan' = 'jp'; 'korea' = 'kr'
        'malaysia' = 'my'; 'mexico' = 'mx'; 'newzealand' = 'nz'; 'norway' = 'no'; 'poland' = 'pl'
        'qatar' = 'qa'; 'singapore' = 'sg'; 'southafrica' = 'za'; 'spain' = 'es'; 'sweden' = 'se'
        'switzerland' = 'ch'; 'taiwan' = 'tw'; 'unitedstates' = 'us'
    }
}

function Set-ConfigFromAnswerFile {
    <#
    .SYNOPSIS
        Populates and validates all configuration from inputs.json WITHOUT prompting, deriving
        names from the static CAF region map (no Azure region retrieval). Throws on any invalid
        value so the caller can fall back to interactive entry. Returns the region abbreviation.
    #>
    [CmdletBinding()]
    param()

    # Organization code (no default)
    $oc = ([string](Get-Answer 'organizationCode')).Trim().ToLower()
    if ($oc -notmatch '^[a-z0-9]{3}$') { throw "organizationCode '$oc' must be exactly 3 lowercase alphanumeric characters." }
    $script:OrganizationCode = $oc

    # Environment type (default from -EnvironmentType, 'dev'). Accept the same set as the
    # -EnvironmentType parameter: dmo/test/stg are supported but intentionally undocumented.
    $et = [string](Get-Answer 'environmentType')
    if ([string]::IsNullOrWhiteSpace($et)) { $et = $EnvironmentType }
    $et = $et.ToLower()
    if (@('dev', 'prd', 'dmo', 'test', 'stg') -notcontains $et) { throw "environmentType '$et' must be one of 'dev', 'prd', 'dmo', 'test', 'stg'." }
    $script:EnvironmentType = $et

    # Organization name (no default)
    $on = ([string](Get-Answer 'organizationName')).Trim()
    if ([string]::IsNullOrWhiteSpace($on)) { throw "organizationName is required." }
    $script:OrganizationName = $on

    # Hostname / FQDN (no default)
    $fq = ([string](Get-Answer 'fqdn')).Trim().ToLower()
    $fq = $fq -replace '^[a-z]+://', ''
    $fq = ($fq -split '/')[0]
    $fq = $fq.Trim('.')
    if ($fq -notmatch '\.' -or $fq -notmatch '^[a-z0-9]([a-z0-9\-\.]*[a-z0-9])?$') { throw "fqdn '$fq' is not a valid fully-qualified domain name." }
    $script:HostName = $fq
    $script:ConfigData['HostName'] = $script:HostName

    # Azure region (default from -AzureRegion, 'uksouth'); abbrev from CAF map — no Azure call
    $script:MicrosoftCAFRegionCodes = Get-CafRegionCodes
    $script:AzureRegionCodes = $script:MicrosoftCAFRegionCodes
    $rg = [string](Get-Answer 'azureRegion')
    if ([string]::IsNullOrWhiteSpace($rg)) { $rg = $AzureRegion }
    $rg = $rg.ToLower()
    if (-not $script:MicrosoftCAFRegionCodes.ContainsKey($rg)) {
        throw "azureRegion '$rg' is not a recognized region — run interactively to validate it against Azure."
    }
    $script:AzureRegion = $rg
    $regionAbbrev = ([string]$script:MicrosoftCAFRegionCodes[$rg]).ToLower()

    # Environment index (default '01')
    $ei = [string](Get-Answer 'environmentIndex')
    if ([string]::IsNullOrWhiteSpace($ei)) { $ei = '01' }
    if ($ei -notmatch '^\d+$' -or [int]$ei -lt 1 -or [int]$ei -gt 99) { throw "environmentIndex '$ei' must be between 01 and 99." }
    $script:EnvironmentIndex = ([int]$ei).ToString('00')

    # Config file name now that org code, env type, and env index are known
    Initialize-ConfigurationFile

    # Solution names FIRST (answer-file override, else Neologik-standard) - the
    # short name is the naming token for every other computed default. Standard
    # construction (project#1576, supersedes project#1063): the environment
    # type joins the organisation code in every name.
    #   SolutionName      neo-{org}{env}-{region}-{index}   e.g. neo-neodev-cus-01
    #   SolutionShortName {org}{env}{index}                 e.g. neodev01
    $snAns = [string](Get-Answer 'solutionName')
    $script:ConfigData['SolutionName'] = if (-not [string]::IsNullOrWhiteSpace($snAns)) { $snAns.Trim().ToLower() }
                                         else { "neo-$($script:OrganizationCode)$($script:EnvironmentType.ToLower())-$regionAbbrev-$($script:EnvironmentIndex)" }
    $ssnAns = [string](Get-Answer 'solutionShortName')
    $script:ConfigData['SolutionShortName'] = if (-not [string]::IsNullOrWhiteSpace($ssnAns)) { $ssnAns.Trim().ToLower() }
                                              else { "$($script:OrganizationCode)$($script:EnvironmentType.ToLower())$($script:EnvironmentIndex)" }

    # Resource group name (answer-file override, else computed).
    $rgComputed = "rg-$($script:ConfigData['SolutionName'])"
    $rgAns = [string](Get-Answer 'resourceGroupName')
    $script:ResourceGroupName = if (-not [string]::IsNullOrWhiteSpace($rgAns)) { $rgAns.Trim() } else { $rgComputed }
    $rgErr = Test-ResourceGroupNameError $script:ResourceGroupName
    if ($rgErr) { throw "resourceGroupName '$($script:ResourceGroupName)': $rgErr" }

    # Key Vault name (-KeyVaultName CLI, else answer-file override, else computed).
    $kvComputed = "kv$($script:ConfigData['SolutionShortName'])"
    $kvAns = [string](Get-Answer 'keyVaultName')
    $script:KeyVaultNameOverride = if ($script:KeyVaultNameFromCli -and -not [string]::IsNullOrWhiteSpace($KeyVaultName)) { $KeyVaultName.Trim() }
                                   elseif (-not [string]::IsNullOrWhiteSpace($kvAns)) { $kvAns.Trim() }
                                   else { $kvComputed }
    $kvErr = Test-KeyVaultNameError $script:KeyVaultNameOverride
    if ($kvErr) { throw "keyVaultName '$($script:KeyVaultNameOverride)': $kvErr" }

    # Deployment storage account name (answer-file override, else computed and truncated to 24).
    $saComputed = "stneodeploy$($script:OrganizationCode)$($script:EnvironmentType.ToLower())$regionAbbrev$($script:EnvironmentIndex)"
    if ($saComputed.Length -gt 24) { $saComputed = $saComputed.Substring(0, 24) }
    $saAns = [string](Get-Answer 'storageAccountName')
    $script:ConfigData['DeployStorageAccountName'] = if (-not [string]::IsNullOrWhiteSpace($saAns)) { $saAns.Trim().ToLower() } else { $saComputed }
    $saErr = Test-StorageAccountNameError $script:ConfigData['DeployStorageAccountName']
    if ($saErr) { throw "storageAccountName '$($script:ConfigData['DeployStorageAccountName'])': $saErr" }

    # Script-runner managed identity name (answer-file override, else computed).
    $sriComputed = "neologik-script-runner-service-connection-$($script:ConfigData['SolutionShortName'])"
    $sriAns = [string](Get-Answer 'scriptRunnerIdentityName')
    $script:ConfigData['ScriptRunnerIdentityName'] = if (-not [string]::IsNullOrWhiteSpace($sriAns)) { $sriAns.Trim() } else { $sriComputed }
    $sriErr = Test-ManagedIdentityNameError $script:ConfigData['ScriptRunnerIdentityName']
    if ($sriErr) { throw "scriptRunnerIdentityName '$($script:ConfigData['ScriptRunnerIdentityName'])': $sriErr" }

    # SQL managed identity name (answer-file override, else computed).
    $sqlComputed = "neologik-sql-managed-identity-$($script:ConfigData['SolutionShortName'])"
    $sqlAns = [string](Get-Answer 'sqlIdentityName')
    $script:ConfigData['SqlIdentityName'] = if (-not [string]::IsNullOrWhiteSpace($sqlAns)) { $sqlAns.Trim() } else { $sqlComputed }
    $sqlErr = Test-ManagedIdentityNameError $script:ConfigData['SqlIdentityName']
    if ($sqlErr) { throw "sqlIdentityName '$($script:ConfigData['SqlIdentityName'])': $sqlErr" }

    # v5 (Neologik Harness): no bots at onboarding - agents and channels are
    # created post-deployment in the Harness admin tool.

    # Budget / cost-report email recipients (optional list; falls back to the built-in default).
    # An empty list disables the scheduled cost-report email (created and maintained
    # by the infrastructure deployment - neo-infrastructure scripts/ensure-cost-report-emails.sh).
    $bcrAns = Get-Answer 'budgetCostReportEmailRecipients'
    if ($null -ne $bcrAns) {
        $script:ConfigData['BudgetEmailAddresses'] = @(Resolve-BudgetEmailRecipients $bcrAns)
    }
    else {
        $script:ConfigData['BudgetEmailAddresses'] = @($script:DefaultBudgetCostReportEmailRecipients)
    }
    $script:ConfigData['BudgetEmailFrequency'] = 'Daily'

    # Resource tagging (project#1173): optional boolean (default: apply tags) plus optional
    # custom tags as an object or a comma-separated key=value string. Invalid values throw
    # so the caller falls back to interactive entry.
    $rtAns = Get-Answer 'applyResourceTags'
    if ($null -eq $rtAns) { $script:ConfigData['ResourceTagsEnabled'] = $true }
    elseif ($rtAns -is [bool]) { $script:ConfigData['ResourceTagsEnabled'] = [bool]$rtAns }
    elseif ("$rtAns" -match '^(true|yes|y|1)$') { $script:ConfigData['ResourceTagsEnabled'] = $true }
    elseif ("$rtAns" -match '^(false|no|n|0)$') { $script:ConfigData['ResourceTagsEnabled'] = $false }
    else { throw "applyResourceTags '$rtAns' must be true or false." }

    $script:ConfigData['ResourceTagsCustom'] = @{}
    if ($script:ConfigData['ResourceTagsEnabled']) {
        $rtcAns = Get-Answer 'resourceTagsCustom'
        if ($null -ne $rtcAns) {
            try { $script:ConfigData['ResourceTagsCustom'] = ConvertTo-NeologikCustomTags $rtcAns }
            catch { throw "resourceTagsCustom: $($_.Exception.Message)" }
        }
    }

    # Solution names were resolved at the top of this function (they drive every
    # computed default above).

    return $regionAbbrev
}

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

        # Load predefined inputs (from -AnswerFile, or an auto-detected inputs.json).
        # Values pre-fill the configuration prompts below; runtime decisions stay interactive.
        Import-AnswerFile -Path $AnswerFile

        # Non-interactive mode requires a fully-populated answer file — fail before any
        # prompt could fire, with a clearer error than a Read-Host failure mid-run.
        if ($script:NonInteractiveMode -and -not (Test-AnswerFileComplete)) {
            throw "Non-interactive mode requires a fully-populated answer file (organizationCode, organizationName, fqdn). Supply -AnswerFile or fix the missing keys."
        }

        # Check for an existing checkpoint and offer to resume
        $existingCheckpoint = Find-LatestCheckpoint
        if ($existingCheckpoint -and $script:FreshRunMode) {
            # -FreshRun: discard the checkpoint and start clean, no prompt.
            Write-Log "FreshRun: discarding existing checkpoint $($existingCheckpoint.Name)" -Level Warning
            Remove-Item -Path $existingCheckpoint.FullName -Force -ErrorAction SilentlyContinue
            $existingCheckpoint = $null
        }
        if ($existingCheckpoint -and $script:NonInteractiveMode) {
            # A leftover checkpoint in CI is an unexpected state: resuming silently could act
            # on stale config, and prompting is impossible. Force an explicit decision.
            throw "A checkpoint from a previous run exists ($($existingCheckpoint.Name)). Re-run with -FreshRun to discard it, or resume interactively."
        }
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
            Write-Host "  Resume from this checkpoint? (Y/N, default: Y): " -NoNewline -ForegroundColor Yellow
            $resumeChoice = Read-Host

            if ([string]::IsNullOrWhiteSpace($resumeChoice) -or $resumeChoice -eq 'Y' -or $resumeChoice -eq 'y') {
                $restored = Restore-Checkpoint -Path $existingCheckpoint.FullName
                if ($restored -eq $false) { $resuming = $false }
                else { $resuming = $true }

                Write-Host "`n  ✓ Checkpoint loaded." -ForegroundColor Green
                Write-Host "    Org: $($script:OrganizationCode)  |  Env: $($script:EnvironmentType)  |  Region: $($script:AzureRegion)" -ForegroundColor Cyan
                Write-Host "    Resource Group: $($script:ResourceGroupName)" -ForegroundColor Cyan
                $unconfirmed = @($script:ProviderRegistrations.GetEnumerator() | Where-Object { $_.Value -ne 'Registered' })
                if ($unconfirmed.Count -gt 0) {
                    Write-Host "    Provider registrations still to confirm: $($unconfirmed.Count)" -ForegroundColor Yellow
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

        if ($currentContext -and $currentContext.Account -and $script:NonInteractiveMode) {
            # CI pre-establishes the Az (and Graph) contexts before invoking this script —
            # always reuse them; never prompt, never force re-auth (an access-token context
            # cannot re-authenticate anyway).
            Write-Log "Non-interactive: reusing existing Azure context ($($currentContext.Account.Id))" -Level Info
            $script:ForceReAuth = $false
        }
        elseif ($currentContext -and $currentContext.Account) {
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

        # Step 3b: Load the resource provider list (resource-providers.txt) before sign-in so a
        # missing or malformed file fails fast.
        $script:ProviderList = Get-PlatformResourceProviderList

        # Step 4: Connect to Azure FIRST to get tenant and subscription info
        Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
        Write-Host "║                                                               ║" -ForegroundColor Magenta
        Write-Host "║                     AZURE AUTHENTICATION                      ║" -ForegroundColor Magenta
        Write-Host "║                                                               ║" -ForegroundColor Magenta
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
        Write-Host ""
        
        $null = Connect-AzureEnvironment -TenantId $TenantId

        # Step 5: Select the subscription
        # On resume, the checkpoint's subscription wins. On a fresh run a supplied
        # -SubscriptionName selects that subscription and fails hard when this login
        # cannot see it (project#2579); the login context is the fallback only when
        # the parameter is absent.
        $subscriptionSource = 'your login'
        if ($resuming -and $script:ConfigData['SubscriptionId']) {
            Set-AzContext -SubscriptionId $script:ConfigData['SubscriptionId'] -ErrorAction Stop | Out-Null
            Write-Log "Restored Azure context to subscription: $($script:ConfigData['SubscriptionId'])" -Level Info
            $subscriptionSource = 'the checkpoint'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($SubscriptionName)) {
            $requested = @(Get-AzSubscription -SubscriptionName $SubscriptionName -ErrorAction SilentlyContinue) | Select-Object -First 1
            if (-not $requested) {
                throw "Subscription '$SubscriptionName' not found for this login. Pass a subscription name this account can see, or omit -SubscriptionName to use the current context subscription."
            }
            Set-AzContext -SubscriptionId $requested.Id -ErrorAction Stop | Out-Null
            Write-Log "Selected subscription from -SubscriptionName: $($requested.Name) (ID: $($requested.Id))" -Level Info
            $subscriptionSource = '-SubscriptionName'
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
        Write-Host "Using subscription from ${subscriptionSource}:" -ForegroundColor Yellow
        Write-Host "  Name: $($currentContext.Subscription.Name)" -ForegroundColor Gray
        Write-Host "  ID:   $($currentContext.Subscription.Id)" -ForegroundColor Gray
        Write-Host ""
        
        Write-Log "Using subscription: $($currentContext.Subscription.Name) (ID: $($currentContext.Subscription.Id))" -Level Success

        # Step 5b: Validate required permissions before prompting for input
        Write-Log "Validating required permissions..." -Level Info
        $null = Test-RequiredPermissions -SubscriptionId $script:ConfigData['SubscriptionId']

        # Step 5c: Submit every resource provider and preview feature registration now (the
        # script's own five first, then the rest). Azure completes them in the background;
        # each is confirmed where its resource is created and the full list before export.
        Start-ResourceProviderRegistration -ProviderList $script:ProviderList

        # Step 6: Collect remaining configuration inputs (skipped when resuming from checkpoint)
        if (-not $resuming) {

        Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
        Write-Host "║                                                               ║" -ForegroundColor Magenta
        Write-Host "║                   CONFIGURATION SETUP                         ║" -ForegroundColor Magenta
        Write-Host "║      Please review and confirm the following settings         ║" -ForegroundColor Magenta
        Write-Host "║                                                               ║" -ForegroundColor Magenta
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta

        # When inputs.json supplies every no-default value, gather config non-interactively and
        # jump straight to the summary; otherwise prompt for each value. On "edit" (N) we re-run
        # this same block interactively.
        $answerComplete = Test-AnswerFileComplete
        $editing = $false
        while ($true) {
            if ($answerComplete -and -not $editing) {
                # inputs.json is complete — apply it directly and go straight to the summary
                # (no field-by-field prompts, and no Azure region retrieval).
                try {
                    $regionAbbrev = Set-ConfigFromAnswerFile
                }
                catch {
                    # Interactive fallback is impossible in non-interactive mode - fail with
                    # the validation error instead of hitting a Read-Host that cannot run.
                    if ($script:NonInteractiveMode) {
                        throw "inputs.json is invalid and cannot be corrected interactively (-NonInteractive): $($_.Exception.Message)"
                    }
                    Write-Host ""
                    Write-Host "  ⚠ inputs.json: $($_.Exception.Message)" -ForegroundColor Yellow
                    Write-Host "  Entering configuration interactively..." -ForegroundColor Yellow
                    $editing = $true
                    continue
                }
            }
            else {

        # Get Organization Code with validation (FIRST QUESTION)
        # No built-in default - the org code is client-specific. Pre-fill from the answer file
        # (or a -OrganizationCode passed on the command line) when available.
        $orgCodePrefill = Get-Answer 'organizationCode'
        if (-not $orgCodePrefill -and -not [string]::IsNullOrWhiteSpace($OrganizationCode)) {
            $orgCodePrefill = $OrganizationCode
        }
        $orgCodeValid = $false
        while (-not $orgCodeValid) {
            Write-Host ""
            Write-Host "Organization Code:" -ForegroundColor Cyan
            if ($orgCodePrefill) {
                Write-Host "  Pre-filled: " -NoNewline -ForegroundColor Gray
                Write-Host $orgCodePrefill -ForegroundColor Yellow
                Write-Host "  Press Enter to use pre-filled value, or type new value: " -NoNewline -ForegroundColor Gray
            }
            else
            {
                Write-Host "  Example: " -NoNewLine -ForegroundColor Gray
                Write-Host "abc" -ForegroundColor Yellow
                Write-Host "  Requirements: lowercase, exactly 3 characters, letters and numbers only" -ForegroundColor Gray
                Write-Host "  Enter organization code: " -NoNewline -ForegroundColor Gray
            }
            if ($orgCodePrefill) {
            }
            else {
            }
            $orgInput = Read-Host

            if ([string]::IsNullOrWhiteSpace($orgInput)) {
                if ($orgCodePrefill) {
                    $script:OrganizationCode = ([string]$orgCodePrefill).Trim().ToLower()
                }
                else {
                    Write-Host "  ✗ Organization code is required. Please enter a value." -ForegroundColor Red
                    continue
                }
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
        # A valid environmentType in the answer file pre-fills (and overrides) the built-in default.
        $envBuiltin = $EnvironmentType
        $envAnswer = Get-Answer 'environmentType'
        if ($envAnswer) {
            if (@('dev', 'prd') -contains ([string]$envAnswer).ToLower()) {
                $EnvironmentType = ([string]$envAnswer).ToLower()
            }
            else {
                Write-Host "  ⚠ Ignoring invalid environmentType '$envAnswer' from answer file (must be dev or prd)." -ForegroundColor Yellow
            }
        }
        $envLabel = Get-PromptLabel $EnvironmentType $envBuiltin
        $envTypeValid = $false
        while (-not $envTypeValid) {
            Write-Host ""
            Write-Host "Environment Type:" -ForegroundColor Cyan
            Write-Host "  $envLabel" -NoNewline -ForegroundColor Gray
            Write-Host $EnvironmentType -ForegroundColor Yellow
            Write-Host "  Valid options: dev, prd" -ForegroundColor Gray
            Write-Host "  Press Enter to use default, or type new value: " -NoNewline -ForegroundColor Gray
            $envInput = Read-Host

            # 'dmo', 'test' and 'stg' are accepted but deliberately not listed above.
            $allowedEnvTypes = @('dev', 'prd', 'dmo', 'test', 'stg')

            if ([string]::IsNullOrWhiteSpace($envInput)) {
                $script:EnvironmentType = $EnvironmentType.ToLower()
                $envTypeValid = $true
                Write-Host "  ✓ Using default: $($script:EnvironmentType)" -ForegroundColor Green
            }
            elseif ($allowedEnvTypes -contains $envInput.ToLower()) {
                $script:EnvironmentType = $envInput.ToLower()
                $envTypeValid = $true
                Write-Host "  ✓ Using: $($script:EnvironmentType)" -ForegroundColor Green
            }
            else {
                Write-Host "  ✗ Invalid environment type. Must be 'dev' or 'prd'. Please try again." -ForegroundColor Red
            }
        }

        # Get Organization Name
        $orgNamePrefill = Get-Answer 'organizationName'
        Write-Host ""
        Write-Host "Organization Name (full company name):" -ForegroundColor Cyan
        if ($orgNamePrefill) {
            Write-Host "  Pre-filled: " -NoNewline -ForegroundColor Gray
            Write-Host $orgNamePrefill -ForegroundColor Yellow
            Write-Host "  Press Enter to use pre-filled value, or type new value: " -NoNewline -ForegroundColor Gray
        }
        else {
            Write-Host "  Example: " -NoNewLine -ForegroundColor Gray
            Write-Host "Contoso Ltd" -ForegroundColor Yellow
            Write-Host "  Enter organization name: " -NoNewline -ForegroundColor Gray
        }
        $orgNameInput = Read-Host
        if ([string]::IsNullOrWhiteSpace($orgNameInput) -and $orgNamePrefill) {
            $orgNameInput = [string]$orgNamePrefill
        }

        while ([string]::IsNullOrWhiteSpace($orgNameInput)) {
            Write-Host "  Organization name is required. Please enter a name: " -NoNewline -ForegroundColor Yellow
            $orgNameInput = Read-Host
        }

        $script:OrganizationName = $orgNameInput.Trim()
        Write-Host "  ✓ Using: " -NoNewline -ForegroundColor Green
        Write-Host $script:OrganizationName -ForegroundColor White

        # Get the bot's hostname (full FQDN).
        # This is the complete public host, e.g. neologik.contoso.com. It is stored and consumed
        # downstream as a single value (hostName); it is never split into separate host/domain parts.
        $fqdnPrefill = Get-Answer 'fqdn'
        Write-Host ""
        Write-Host "Bot Hostname (full FQDN):" -ForegroundColor Cyan
        if ($fqdnPrefill) {
            Write-Host "  Pre-filled: " -NoNewline -ForegroundColor Gray
            Write-Host $fqdnPrefill -ForegroundColor Yellow
            Write-Host "  Press Enter to use pre-filled value, or type new value: " -NoNewline -ForegroundColor Gray
        }
        else {
            Write-Host "  Example: " -NoNewLine -ForegroundColor Gray
            Write-Host "neologik.contoso.com, abcprd.neologik.ai" -ForegroundColor Yellow
            Write-Host "  Enter full hostname: " -NoNewline -ForegroundColor Gray
        }
        $fqdnInput = Read-Host
        if ([string]::IsNullOrWhiteSpace($fqdnInput) -and $fqdnPrefill) {
            $fqdnInput = [string]$fqdnPrefill
        }

        $fqdnValid = $false
        while (-not $fqdnValid) {
            while ([string]::IsNullOrWhiteSpace($fqdnInput)) {
                Write-Host "  Hostname is required. Please enter the full FQDN: " -NoNewline -ForegroundColor Yellow
                $fqdnInput = Read-Host
            }

            # Normalize: strip any scheme/path, lowercase, trim stray dots.
            $normalizedFqdn = $fqdnInput.Trim().ToLower()
            $normalizedFqdn = $normalizedFqdn -replace '^[a-z]+://', ''
            $normalizedFqdn = ($normalizedFqdn -split '/')[0]
            $normalizedFqdn = $normalizedFqdn.Trim('.')

            # Require a dotted, DNS-valid fully-qualified name (host.domain).
            if ($normalizedFqdn -notmatch '\.' -or $normalizedFqdn -notmatch '^[a-z0-9]([a-z0-9\-\.]*[a-z0-9])?$') {
                Write-Host "  ✗ Enter a valid fully-qualified hostname, e.g. neologik.contoso.com" -ForegroundColor Red
                $fqdnInput = ""
                continue
            }

            $script:HostName = $normalizedFqdn
            $fqdnValid = $true
        }

        $script:ConfigData['HostName'] = $script:HostName
        Write-Host "  ✓ Using: " -NoNewline -ForegroundColor Green
        Write-Host $script:HostName -ForegroundColor White

        # Get Azure Region with real-time validation
        # Query Azure for available locations
        Write-Host ""
        Write-Host "Retrieving available Azure regions..." -ForegroundColor Gray
        
        # Region abbreviations from the shared CAF map (single source of truth — see Get-CafRegionCodes).
        $script:MicrosoftCAFRegionCodes = Get-CafRegionCodes
        
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
        
        # Pre-fill (and override) the default region from the answer file when provided (still validated below).
        $regionBuiltin = $AzureRegion
        $regionAnswer = Get-Answer 'azureRegion'
        if ($regionAnswer) { $AzureRegion = ([string]$regionAnswer).ToLower() }
        $regionLabel = Get-PromptLabel $AzureRegion $regionBuiltin

        $regionValid = $false

        while (-not $regionValid) {
            Write-Host ""
            Write-Host "Azure Region:" -ForegroundColor Cyan
            Write-Host "  $regionLabel" -NoNewline -ForegroundColor Gray
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
                Write-Host "  Example: " -NoNewLine -ForegroundColor Gray
                Write-Host "uksouth, ukwest, eastus, westus, northeurope, westeurope" -ForegroundColor Yellow
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
        # Source the default from the answer file when it holds a valid 1-99 value.
        $indexDefault = Get-Answer 'environmentIndex'
        if ($indexDefault -and "$indexDefault" -match '^\d+$' -and [int]"$indexDefault" -ge 1 -and [int]"$indexDefault" -le 99) {
            $indexDefault = ([int]"$indexDefault").ToString("00")
        }
        elseif ($indexDefault) {
            Write-Host "  ⚠ Ignoring invalid environmentIndex '$indexDefault' from answer file (must be 01-99)." -ForegroundColor Yellow
            $indexDefault = "01"
        }
        else {
            $indexDefault = "01"
        }
        $indexLabel = Get-PromptLabel $indexDefault "01"
        $indexValid = $false
        while (-not $indexValid) {
            Write-Host ""
            Write-Host "Environment Index Number:" -ForegroundColor Cyan
            Write-Host "  $indexLabel" -NoNewline -ForegroundColor Gray
            Write-Host $indexDefault -ForegroundColor Yellow
            Write-Host "  (Use for multiple environments: 01, 02, 03, etc.)" -ForegroundColor Gray
            Write-Host "  Press Enter to use default, or type new value: " -NoNewline -ForegroundColor Gray
            $indexInput = Read-Host

            if ([string]::IsNullOrWhiteSpace($indexInput)) {
                $script:EnvironmentIndex = $indexDefault
                $indexValid = $true
                Write-Host "  ✓ Using default: $($script:EnvironmentIndex)" -ForegroundColor Green
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

        # Config file name now that org code, env type, and env index are known
        Initialize-ConfigurationFile

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
        
        # Resource Group, Key Vault, Storage Account and script-runner identity names. Each
        # shows an effective default: the answer-file value (or, for Key Vault, a -KeyVaultName
        # CLI value) when present, otherwise the computed Neologik-standard name. Press Enter to
        # accept, or type to override; validated against Azure naming rules. This lets
        # client-specific naming conventions be applied from inputs.json without editing the script.

        # Resource group name.
        # Solution names FIRST (answer-file override, else Neologik-standard) - the
        # short name is the naming token for every other computed default
        # (project#1576: the environment type joins the organisation code).
        $snAns = [string](Get-Answer 'solutionName')
        $script:ConfigData['SolutionName'] = if (-not [string]::IsNullOrWhiteSpace($snAns)) { $snAns.Trim().ToLower() }
                                             else { "neo-$($script:OrganizationCode.ToLower())$($script:EnvironmentType.ToLower())-$regionAbbrev-$($script:EnvironmentIndex)" }
        $ssnAns = [string](Get-Answer 'solutionShortName')
        $script:ConfigData['SolutionShortName'] = if (-not [string]::IsNullOrWhiteSpace($ssnAns)) { $ssnAns.Trim().ToLower() }
                                                  else { "$($script:OrganizationCode.ToLower())$($script:EnvironmentType.ToLower())$($script:EnvironmentIndex)" }

        $rgComputed = "rg-$($script:ConfigData['SolutionName'])"
        $rgAns = [string](Get-Answer 'resourceGroupName')
        $rgDefault = if (-not [string]::IsNullOrWhiteSpace($rgAns)) { $rgAns.Trim() } else { $rgComputed }
        $script:ResourceGroupName = Read-NameWithDefault -Title 'Resource Group Name' `
            -DefaultValue $rgDefault -Validator ${function:Test-ResourceGroupNameError} `
            -LabelPrefix (Get-PromptLabel $rgDefault $rgComputed)

        # Key Vault name. Precedence for the default: -KeyVaultName CLI, then answer file, then computed.
        $kvComputed = "kv$($script:ConfigData['SolutionShortName'])"
        $kvAns = [string](Get-Answer 'keyVaultName')
        $kvDefault = if ($script:KeyVaultNameFromCli -and -not [string]::IsNullOrWhiteSpace($KeyVaultName)) { $KeyVaultName.Trim() }
                     elseif (-not [string]::IsNullOrWhiteSpace($kvAns)) { $kvAns.Trim() }
                     else { $kvComputed }
        $script:KeyVaultNameOverride = Read-NameWithDefault -Title 'Key Vault Name' `
            -DefaultValue $kvDefault -Validator ${function:Test-KeyVaultNameError} `
            -LabelPrefix (Get-PromptLabel $kvDefault $kvComputed)

        # Deployment storage account name (holds the certificate blob container).
        $saComputed = "stneodeploy$($script:OrganizationCode.ToLower())$($script:EnvironmentType.ToLower())$regionAbbrev$($script:EnvironmentIndex)"
        if ($saComputed.Length -gt 24) { $saComputed = $saComputed.Substring(0, 24) }
        $saAns = [string](Get-Answer 'storageAccountName')
        $saDefault = if (-not [string]::IsNullOrWhiteSpace($saAns)) { $saAns.Trim().ToLower() } else { $saComputed }
        $script:ConfigData['DeployStorageAccountName'] = Read-NameWithDefault -Title 'Deployment Storage Account Name' `
            -DefaultValue $saDefault -Validator ${function:Test-StorageAccountNameError} `
            -LabelPrefix (Get-PromptLabel $saDefault $saComputed)

        # Script-runner managed identity name (the deployment pipeline's service connection).
        $sriComputed = "neologik-script-runner-service-connection-$($script:ConfigData['SolutionShortName'])"
        $sriAns = [string](Get-Answer 'scriptRunnerIdentityName')
        $sriDefault = if (-not [string]::IsNullOrWhiteSpace($sriAns)) { $sriAns.Trim() } else { $sriComputed }
        $script:ConfigData['ScriptRunnerIdentityName'] = Read-NameWithDefault -Title 'Script Runner Managed Identity Name' `
            -DefaultValue $sriDefault -Validator ${function:Test-ManagedIdentityNameError} `
            -LabelPrefix (Get-PromptLabel $sriDefault $sriComputed)

        # SQL managed identity name.
        $sqlComputed = "neologik-sql-managed-identity-$($script:ConfigData['SolutionShortName'])"
        $sqlAns = [string](Get-Answer 'sqlIdentityName')
        $sqlDefault = if (-not [string]::IsNullOrWhiteSpace($sqlAns)) { $sqlAns.Trim() } else { $sqlComputed }
        $script:ConfigData['SqlIdentityName'] = Read-NameWithDefault -Title 'SQL Managed Identity Name' `
            -DefaultValue $sqlDefault -Validator ${function:Test-ManagedIdentityNameError} `
            -LabelPrefix (Get-PromptLabel $sqlDefault $sqlComputed)

        # v5: no bots are created at onboarding. Agents and their channels are
        # created post-deployment in the NCE admin tool; channels reuse the
        # default user group created above (or an admin supplies another
        # existing group id at channel attach) - the platform never creates
        # groups (project#1519).

        # Get Budget Cost-Report Email Recipient(s)
        # A daily Azure Cost Management report is emailed to these addresses. The report
        # (cost view + scheduled actions) is created and maintained by the infrastructure
        # deployment (neo-infrastructure scripts/ensure-cost-report-emails.sh), authorised
        # by the deployment SP's subscription-scoped 'Cost Management Contributor' grant
        # assigned by this script (project#1215); onboarding only collects the recipients.
        # Pre-filled from inputs.json 'budgetCostReportEmailRecipients' when present.
        # Leave blank for the default, or 'none' to disable.
        $defaultBudgetEmail = @($script:DefaultBudgetCostReportEmailRecipients)
        $budgetAns = Get-Answer 'budgetCostReportEmailRecipients'
        if ($null -ne $budgetAns) {
            try {
                $fromAnswer = @(Resolve-BudgetEmailRecipients $budgetAns)
                if ($fromAnswer.Count -gt 0) { $defaultBudgetEmail = $fromAnswer }
            }
            catch { Write-Host "  ⚠ Ignoring invalid budgetCostReportEmailRecipients from answer file: $($_.Exception.Message)" -ForegroundColor Yellow }
        }
        $budgetDefaultText = $defaultBudgetEmail -join ', '
        $budgetEmailsValid = $false
        $budgetEmails = @()
        while (-not $budgetEmailsValid) {
            Write-Host ""
            Write-Host "Budget Cost-Report Email Recipient(s):" -ForegroundColor Cyan
            Write-Host "  A daily Azure cost report is emailed to these address(es)." -ForegroundColor Gray
            Write-Host "  Enter one or more email addresses separated by commas, or 'none' to disable." -ForegroundColor Gray
            Write-Host "  Default: " -NoNewline -ForegroundColor Gray
            Write-Host $budgetDefaultText -ForegroundColor Yellow
            Write-Host "  Press Enter for default, type address(es), or 'none' to disable: " -NoNewline -ForegroundColor Gray
            $budgetEmailInput = Read-Host

            if ([string]::IsNullOrWhiteSpace($budgetEmailInput)) {
                $budgetEmails = @($defaultBudgetEmail)
            }
            elseif ($budgetEmailInput.Trim().ToLower() -eq 'none') {
                $budgetEmails = @()
            }
            else {
                $budgetEmails = @($budgetEmailInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }

            $invalidEmails = @($budgetEmails | Where-Object { $_ -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$' })
            if ($invalidEmails.Count -gt 0) {
                Write-Host "  ✗ Invalid email address(es): $($invalidEmails -join ', '). Please try again." -ForegroundColor Red
                continue
            }

            $budgetEmailsValid = $true
            if ($budgetEmails.Count -eq 0) {
                Write-Host "  ✓ Cost-report email disabled" -ForegroundColor Green
            }
            else {
                Write-Host "  ✓ Using: $($budgetEmails -join ', ')" -ForegroundColor Green
            }
        }
        $script:ConfigData['BudgetEmailAddresses'] = $budgetEmails
        $script:ConfigData['BudgetEmailFrequency'] = 'Daily'

        # Ask whether to tag created Azure resources (project#1173). Some tenants carry
        # Azure Policies that DENY creation of untagged resources, so tags must be applied
        # on the create call itself. Pre-filled from inputs.json 'applyResourceTags' and
        # 'resourceTagsCustom' when present. Default: apply tags.
        $tagsDefault = $true
        $tagsAns = Get-AnswerBool 'applyResourceTags'
        if ($null -ne $tagsAns) { $tagsDefault = $tagsAns }
        $tagsDefaultText = if ($tagsDefault) { 'true' } else { 'false' }
        $tagsValid = $false
        while (-not $tagsValid) {
            Write-Host ""
            Write-Host "Apply Azure resource tags to created resources? (true/false)" -ForegroundColor Cyan
            Write-Host "  Tags (Vendor, ApplicationName, ManagedBy, Environment, Solution," -ForegroundColor Gray
            Write-Host "  DeploymentDate) are applied when each resource is created, satisfying" -ForegroundColor Gray
            Write-Host "  Azure Policies that deny creation of untagged resources." -ForegroundColor Gray
            Write-Host "  Default: " -NoNewline -ForegroundColor Gray
            Write-Host $tagsDefaultText -ForegroundColor Yellow
            Write-Host "  Press Enter to use default, or type true/false: " -NoNewline -ForegroundColor Gray
            $tagsInput = Read-Host

            if ([string]::IsNullOrWhiteSpace($tagsInput)) {
                $script:ConfigData['ResourceTagsEnabled'] = $tagsDefault
                $tagsValid = $true
            }
            elseif ($tagsInput.Trim() -match '^(true|yes|y|1)$') {
                $script:ConfigData['ResourceTagsEnabled'] = $true
                $tagsValid = $true
            }
            elseif ($tagsInput.Trim() -match '^(false|no|n|0)$') {
                $script:ConfigData['ResourceTagsEnabled'] = $false
                $tagsValid = $true
            }
            else {
                Write-Host "  Invalid value. Enter true or false. Please try again." -ForegroundColor Red
            }
        }
        if ($script:ConfigData['ResourceTagsEnabled']) {
            Write-Host "  Using: true (resources are tagged at creation)" -ForegroundColor Green
        }
        else {
            Write-Host "  Using: false (no tags are applied)" -ForegroundColor Green
        }

        # Optional customer tags, only when tagging is enabled. Comma-separated key=value
        # pairs; custom pairs override the Neologik defaults on key collision.
        $script:ConfigData['ResourceTagsCustom'] = @{}
        if ($script:ConfigData['ResourceTagsEnabled']) {
            $customPrefill = ''
            $customAns = Get-Answer 'resourceTagsCustom'
            if ($null -ne $customAns) {
                try {
                    $prefillTags = ConvertTo-NeologikCustomTags $customAns
                    $customPrefill = (@($prefillTags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ',')
                }
                catch {
                    Write-Host "  Ignoring invalid resourceTagsCustom from answer file: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            $customValid = $false
            while (-not $customValid) {
                Write-Host ""
                Write-Host "Custom resource tags (optional):" -ForegroundColor Cyan
                Write-Host "  Comma-separated key=value pairs; keys may use letters, digits, '.', '_'" -ForegroundColor Gray
                Write-Host "  and '-'. Custom tags override the Neologik defaults on key collision." -ForegroundColor Gray
                Write-Host "  Example: " -NoNewline -ForegroundColor Gray
                Write-Host "CostCentre=IT123,Owner=Platform Team" -ForegroundColor Yellow
                if ($customPrefill) {
                    Write-Host "  Pre-filled: " -NoNewline -ForegroundColor Gray
                    Write-Host $customPrefill -ForegroundColor Yellow
                    Write-Host "  Press Enter to use pre-filled value, 'none' for no custom tags, or type new pairs: " -NoNewline -ForegroundColor Gray
                }
                else {
                    Write-Host "  Press Enter for none, or type key=value pairs: " -NoNewline -ForegroundColor Gray
                }
                $customInput = Read-Host

                if ([string]::IsNullOrWhiteSpace($customInput)) {
                    $customInput = $customPrefill
                }
                elseif ($customInput.Trim() -match '^(none)$') {
                    $customInput = ''
                }

                try {
                    $script:ConfigData['ResourceTagsCustom'] = ConvertTo-NeologikCustomTags $customInput
                    $customValid = $true
                }
                catch {
                    Write-Host "  $($_.Exception.Message) Please try again." -ForegroundColor Red
                    continue
                }

                if ($script:ConfigData['ResourceTagsCustom'].Count -gt 0) {
                    $customSummary = (@($script:ConfigData['ResourceTagsCustom'].GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')
                    Write-Host "  Using custom tags: $customSummary" -ForegroundColor Green
                }
                else {
                    Write-Host "  No custom tags" -ForegroundColor Green
                }
            }
        }

        # Solution names were resolved before the resource-name prompts above
        # (they drive every computed default).
            }

        # Provisioning decisions - presented BEFORE the summary so they appear in it and are
        # confirmed alongside the rest of the configuration. Precedence for each: command-line
        # switch/param, then the answer file, then an interactive prompt. Runs for both the
        # interactive and answer-file-complete paths. Steps 8 and 11 consume the stored
        # decision and never prompt again. (The SP secret is held in a script variable, not
        # ConfigData, so it is never written to the checkpoint or exported config.)

        # Guest invitations. Typed additions to the invite list are interactive-only;
        # default to none so the summary and Step 8 can always read the key.
        $script:ConfigData['AdditionalGuestEmails'] = @()
        if ($script:SkipGuestInvitationFromCli) {
            $script:ConfigData['SkipGuestInvitation'] = [bool]$SkipGuestInvitation
        }
        else {
            $sgAns = Get-AnswerBool 'skipGuestInvitation'
            if ($null -ne $sgAns) {
                $script:ConfigData['SkipGuestInvitation'] = $sgAns
            }
            else {
                Write-Host ""
                # Recover a missing guest users file before asking - customers sometimes
                # download only the .ps1 instead of unzipping the full onboarding package.
                if ($script:NeologikGuestUsers.Count -eq 0 -and -not (Test-Path $script:GuestUsersFile) -and -not $script:NonInteractiveMode) {
                    Resolve-GuestUsersFile | Out-Null
                }
                Write-Host "Invite Neologik guest users into this tenant?" -ForegroundColor Cyan
                if ($script:NeologikGuestUsers.Count -gt 0) {
                    Write-Host "  The following $($script:NeologikGuestUsers.Count) guest(s) from NeologikGuestUsers.txt will be invited:" -ForegroundColor Gray
                    $script:NeologikGuestUsers | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
                }
                else {
                    Write-Host "  NeologikGuestUsers.txt is empty or missing - choose Y to type the addresses" -ForegroundColor Gray
                    Write-Host "  to invite, or N to skip invitations." -ForegroundColor Gray
                }
                Write-Host "  (Y/n, default: Y - invite): " -NoNewline -ForegroundColor Yellow
                $inviteAns = Read-Host
                # Default (Enter) invites; only an explicit N/no skips.
                $script:ConfigData['SkipGuestInvitation'] = ($inviteAns -match '^(n|no)$')

                # Invitations accepted: offer to extend the file's list with typed
                # addresses (or build the whole list by hand when the file is empty or
                # missing). Interactive path only - unattended runs use the file.
                if (-not $script:ConfigData['SkipGuestInvitation']) {
                    $addMore = $false
                    if ($script:NeologikGuestUsers.Count -gt 0) {
                        Write-Host "  Do you want to add any more addresses to invite? (y/N, default: N): " -NoNewline -ForegroundColor Yellow
                        $moreAns = Read-Host
                        $addMore = ($moreAns -match '^(y|yes)$')
                    }
                    else {
                        $addMore = $true
                        Write-Host "  Enter the addresses to invite." -ForegroundColor Gray
                    }
                    if ($addMore) {
                        Write-Host "  One address per line (a line may also hold several, comma-separated)." -ForegroundColor Gray
                        Write-Host "  Press Enter on an empty line to finish." -ForegroundColor Gray
                        $combined = @(Read-EmailAddressList -Seed @($script:NeologikGuestUsers))
                        $additional = @($combined | Where-Object { $script:NeologikGuestUsers -notcontains $_ })
                        $script:ConfigData['AdditionalGuestEmails'] = $additional
                        if ($additional.Count -gt 0) {
                            Write-Host "  $($additional.Count) additional address(es) will be invited alongside the $($script:NeologikGuestUsers.Count) from the file:" -ForegroundColor Gray
                            $additional | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
                        }
                        elseif ($script:NeologikGuestUsers.Count -eq 0) {
                            Write-Host "  No addresses entered - no guests will be invited." -ForegroundColor Yellow
                        }
                    }
                }
            }
        }

        # Existing accounts into the groups (asked only when invitations were declined):
        # the client may have pre-created the Neologik team's accounts (B2B guests or
        # member accounts) and want them added to the security groups without any
        # invitation being sent. Precedence: answer file, then an interactive prompt.
        # Address source precedence: answer file 'existingAccountEmails', then
        # NeologikGuestUsers.txt or interactively typed addresses.
        $script:ConfigData['AddExistingAccountsToGroups'] = $false
        $script:ConfigData['ExistingAccountEmails'] = @()
        if ($script:ConfigData['SkipGuestInvitation']) {
            $addAns = Get-AnswerBool 'addExistingAccountsToGroups'
            if ($null -ne $addAns) {
                $script:ConfigData['AddExistingAccountsToGroups'] = $addAns
                Write-Log "Add-existing-accounts decision from answer file: addExistingAccountsToGroups=$addAns." -Level Info
            }
            elseif (-not $script:NonInteractiveMode) {
                Write-Host ""
                Write-Host "Add existing accounts to the security groups?" -ForegroundColor Cyan
                Write-Host "  Choose Y if you have already created the Neologik team's accounts in this" -ForegroundColor Gray
                Write-Host "  tenant (as guests or full members) and want them added to the security" -ForegroundColor Gray
                Write-Host "  groups now. No invitations are sent. NOTE: accounts added here go into ALL" -ForegroundColor Gray
                Write-Host "  Neologik groups, including the Admin User Group (Azure admin access) -" -ForegroundColor Gray
                Write-Host "  only list accounts that should hold Neologik admin/support access." -ForegroundColor Gray
                Write-Host "  (y/N, default: N): " -NoNewline -ForegroundColor Yellow
                $addAnswer = Read-Host
                $script:ConfigData['AddExistingAccountsToGroups'] = ($addAnswer -match '^(y|yes)$')
            }

            if ($script:ConfigData['AddExistingAccountsToGroups']) {
                $emails = @()
                $ansEmails = Get-Answer 'existingAccountEmails'
                if ($null -ne $ansEmails) {
                    foreach ($entry in @($ansEmails)) {
                        $emails += @(([string]$entry) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                    }
                    Write-Log "Existing-account addresses from answer file: $($emails.Count)." -Level Info
                }
                elseif ($script:NonInteractiveMode) {
                    # Unattended with no answer-file list: the guest users file is the source.
                    $emails = @($script:NeologikGuestUsers)
                    Write-Log "Non-interactive: existing-account addresses taken from NeologikGuestUsers.txt ($($emails.Count))." -Level Info
                }
                else {
                    $useFile = $false
                    if ($script:NeologikGuestUsers.Count -gt 0) {
                        Write-Host ""
                        Write-Host "  Where should the account addresses come from?" -ForegroundColor Cyan
                        Write-Host "  NeologikGuestUsers.txt contains $($script:NeologikGuestUsers.Count) address(es):" -ForegroundColor Gray
                        $script:NeologikGuestUsers | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
                        Write-Host "  [F] Use the file   [T] Type the addresses   (F/t, default: F): " -NoNewline -ForegroundColor Yellow
                        $srcAnswer = Read-Host
                        $useFile = ($srcAnswer -notmatch '^(t|type)$')
                    }
                    if ($useFile) {
                        $emails = @($script:NeologikGuestUsers)
                    }
                    else {
                        # Line-by-line entry via the shared reader: one address per Enter,
                        # commas accepted within a line, blank line finishes.
                        Write-Host "  Enter the email addresses, one per line (a line may also hold several," -ForegroundColor Gray
                        Write-Host "  comma-separated). Each must exactly match the account's mail or user" -ForegroundColor Gray
                        Write-Host "  principal name. Press Enter on an empty line to finish." -ForegroundColor Gray
                        $emails = @(Read-EmailAddressList)
                        if ($emails.Count -eq 0) {
                            Write-Host "  No addresses entered - no accounts will be added to the groups." -ForegroundColor Yellow
                        }
                        else {
                            Write-Host "  $($emails.Count) address(es) collected:" -ForegroundColor Gray
                            $emails | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
                        }
                    }
                }
                $script:ConfigData['ExistingAccountEmails'] = $emails
            }
        }

        # Existing (client-provided) deployment service principal.
        $spChoice = Read-ExistingServicePrincipalChoice `
            -CliObjectId $ExistingServicePrincipalObjectId `
            -CliSecret $ExistingServicePrincipalSecret `
            -AnswerUseExisting (Get-AnswerBool 'useExistingServicePrincipal') `
            -AnswerObjectId ([string](Get-Answer 'existingServicePrincipalObjectId')) `
            -AnswerSecret ([string](Get-Answer 'existingServicePrincipalSecret'))
        $script:ConfigData['UseExistingServicePrincipal'] = $spChoice.UseExisting
        $script:ConfigData['ExistingServicePrincipalObjectId'] = $spChoice.ObjectId
        $script:ExistingSpSecretResolved = $spChoice.Secret

        # Display summary
        Write-Host "`n╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                                                               ║" -ForegroundColor Cyan
        Write-Host "║                   CONFIGURATION SUMMARY                       ║" -ForegroundColor Cyan
        Write-Host "║                                                               ║" -ForegroundColor Cyan
        Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        # Single label width keeps the value column aligned (project#1577)
        function Write-SummaryRow {
            param([string]$Label, [string]$Value)
            Write-Host ("  {0,-24}" -f ($Label + ':')) -NoNewline
            Write-Host $Value -ForegroundColor Yellow
        }
        Write-SummaryRow 'Logged in User' $script:ConfigData['UserAccount']
        Write-SummaryRow 'Tenant ID' $script:ConfigData['TenantId']
        Write-SummaryRow 'Subscription Name' $script:ConfigData['SubscriptionName']
        Write-SummaryRow 'Organization Name' $script:OrganizationName
        Write-SummaryRow 'Bot Hostname (FQDN)' $script:HostName
        Write-SummaryRow 'Organization Code' $script:OrganizationCode
        Write-SummaryRow 'Environment Type' $script:EnvironmentType
        Write-SummaryRow 'Environment Index' $script:EnvironmentIndex
        Write-SummaryRow 'Azure Region' $script:AzureRegion
        Write-SummaryRow 'Resource Group Name' $script:ResourceGroupName
        Write-SummaryRow 'Key Vault Name' $script:KeyVaultNameOverride
        Write-SummaryRow 'Storage Account Name' $script:ConfigData['DeployStorageAccountName']
        Write-SummaryRow 'Script Runner Identity' $script:ConfigData['ScriptRunnerIdentityName']
        Write-SummaryRow 'SQL Managed Identity' $script:ConfigData['SqlIdentityName']
        Write-SummaryRow 'Solution Name' $script:ConfigData['SolutionName']
        Write-SummaryRow 'Solution Short Name' $script:ConfigData['SolutionShortName']
        $budgetEmailSummary = if ($script:ConfigData['BudgetEmailAddresses'].Count -gt 0) { $script:ConfigData['BudgetEmailAddresses'] -join ', ' } else { '(disabled)' }
        Write-SummaryRow 'Cost-Report Email' $budgetEmailSummary
        Write-SummaryRow 'Provider Registration' "Full platform set: $($script:ProviderList.Providers.Count) providers, $($script:ProviderList.Features.Count) preview features (resource-providers.txt)"
        $tagsSummary = if ($script:ConfigData['ResourceTagsEnabled']) {
            $customCount = @($script:ConfigData['ResourceTagsCustom'].Keys).Count
            if ($customCount -gt 0) { "Yes ($customCount custom)" } else { 'Yes' }
        }
        else { 'No' }
        Write-SummaryRow 'Apply Resource Tags' $tagsSummary
        $guestSummary = if (-not $script:ConfigData['SkipGuestInvitation']) {
                            $typedCount = @($script:ConfigData['AdditionalGuestEmails'] | Where-Object { $_ }).Count
                            if ($typedCount -gt 0) { "Yes ($($script:NeologikGuestUsers.Count) from file + $typedCount typed)" } else { 'Yes' }
                        }
                        elseif ($script:ConfigData['AddExistingAccountsToGroups']) { "No - adding $(@($script:ConfigData['ExistingAccountEmails']).Count) existing account(s) to the groups" }
                        else { 'No (skipped)' }
        Write-SummaryRow 'Invite Neologik Guests' $guestSummary
        if ($script:ConfigData['UseExistingServicePrincipal']) {
            Write-SummaryRow 'Deployment SP' "Existing: $($script:ConfigData['ExistingServicePrincipalObjectId'])"
        }
        else {
            Write-SummaryRow 'Deployment SP' 'Create new'
        }
        Write-Host ""
        if ($answerComplete) {
            if ($script:NonInteractiveMode) {
                # Answer file is complete (verified up front) — proceed without confirmation.
                Write-Log "Non-interactive: proceeding with the answer-file settings shown above" -Level Info
                break
            }
            # Required confirmation — no default; the user must type Y (continue) or N (edit).
            $confirmChoice = ''
            while ($confirmChoice -notmatch '^[YyNn]$') {
                Write-Host ""
                Write-Host "Continue with these settings? Type Y to continue, or N to edit: " -NoNewline -ForegroundColor Yellow
                $confirmChoice = (Read-Host).Trim()
            }
            if ($confirmChoice -match '^[Nn]$') {
                Write-Host "`n  Editing — you'll be prompted for each value (pre-filled from your inputs)..." -ForegroundColor Cyan
                $editing = $true
                continue
            }
            break
        }
        else {
            Write-Host "Press Enter to continue with these settings, or Ctrl+C to cancel..." -ForegroundColor Yellow
            Read-Host
            break
        }
        }

        # Save configuration to checkpoint now that it has been confirmed.
        # This allows a resume if any subsequent step fails (e.g. permission errors or provider timeouts).
        $script:CheckpointRegionAbbrev = $regionAbbrev
        Complete-OnboardingStep 'ConfigGathered'

        } else {
            # Resume path: restore the region abbreviation local variable from checkpoint data.
            $regionAbbrev = $script:CheckpointRegionAbbrev

            # Back-compat: checkpoints written before these inputs existed lack the keys — default them.
            if (-not $script:ConfigData.ContainsKey('BudgetEmailAddresses')) {
                $script:ConfigData['BudgetEmailAddresses'] = @($script:DefaultBudgetCostReportEmailRecipients)
            }
            if (-not $script:ConfigData.ContainsKey('BudgetEmailFrequency')) {
                $script:ConfigData['BudgetEmailFrequency'] = 'Daily'
            }
            # Resource tagging (project#1173) may be absent on older checkpoints - default to
            # disabled so a resumed pre-feature run keeps its original untagged behaviour.
            if (-not $script:ConfigData.ContainsKey('ResourceTagsEnabled')) {
                $script:ConfigData['ResourceTagsEnabled'] = $false
                $script:ConfigData['ResourceTagsCustom'] = @{}
            }
            # Provisioning decisions may be absent on older checkpoints — default them. The SP
            # secret is not persisted, so a resumed run cannot re-store it in Key Vault (the
            # client adds it manually if needed).
            if (-not $script:ConfigData.ContainsKey('SkipGuestInvitation')) {
                $script:ConfigData['SkipGuestInvitation'] = $false
            }
            if (-not $script:ConfigData.ContainsKey('UseExistingServicePrincipal')) {
                $script:ConfigData['UseExistingServicePrincipal'] = $false
                $script:ConfigData['ExistingServicePrincipalObjectId'] = ''
            }

            Write-Host "`n  ⏩ Configuration restored from checkpoint — skipping input prompts" -ForegroundColor Gray
            Write-Host "     Org: $($script:OrganizationCode)  |  Env: $($script:EnvironmentType)  |  Region: $($script:AzureRegion)" -ForegroundColor Cyan
            Write-Host "     Resource Group: $($script:ResourceGroupName)" -ForegroundColor Cyan
            Write-Host ""
        }

        # Step 7: Create resource group
        $null = New-NeologikResourceGroup -ResourceGroupName $script:ResourceGroupName -Location $script:AzureRegion

        # Step 8: Invite guest users (skipped when the client uses its own-tenant
        # accounts and takes no B2B guests). When invitations were declined but the
        # operator chose to add existing accounts, resolve those instead - lookup only,
        # never inviting; unresolvable addresses warn and the run continues. Both
        # decisions were made during configuration gathering and shown in the summary.
        if ($script:ConfigData['SkipGuestInvitation']) {
            Write-Log "Guest user invitation skipped (per configuration)." -Level Info
            $guestUsers = @()
            if ($script:ConfigData['AddExistingAccountsToGroups']) {
                $guestUsers = @(Invoke-ExistingAccountResolution -Emails @($script:ConfigData['ExistingAccountEmails']))
            }
        }
        else {
            # File entries plus any addresses typed at the invite prompt (existing
            # accounts are matched, the rest receive B2B invitations).
            $inviteEmails = @(@($script:NeologikGuestUsers) + @($script:ConfigData['AdditionalGuestEmails'] | Where-Object { $_ }) | Select-Object -Unique)
            $guestUsers = Invoke-GuestUserInvitation -GuestEmails $inviteEmails
        }

        # Step 9: Create security groups (includes logged-in user + guest users)
        $securityGroups = New-NeologikSecurityGroups -GuestUsers $guestUsers -OrganizationCode $script:OrganizationCode -EnvironmentType $script:EnvironmentType -EnvironmentIndex $script:EnvironmentIndex

        # Step 10: Assign roles to security groups
        $null = Set-NeologikRoleAssignments -SecurityGroups $securityGroups -SubscriptionId $script:ConfigData['SubscriptionId'] -ResourceGroupName $script:ResourceGroupName

        # Step 11: App Registration / service principal. The use-existing-vs-create decision
        # was made during configuration gathering and shown in the summary. When an existing
        # SP is used, the script does not CREATE the app registration/SP/secret - but it still
        # assigns the required roles and Graph consent to it below, exactly as for a
        # script-created SP (the operator is Owner + Global Admin either way).
        if ($script:ConfigData['UseExistingServicePrincipal']) {
            $appReg = Get-NeologikExistingAppRegistration `
                -ServicePrincipalObjectId $script:ConfigData['ExistingServicePrincipalObjectId'] `
                -ProvidedSecret $script:ExistingSpSecretResolved
        }
        else {
            $appReg = New-NeologikAppRegistration -OrganizationCode $script:OrganizationCode -EnvironmentType $script:EnvironmentType -EnvironmentIndex $script:EnvironmentIndex
        }

        # Assign roles + Graph consent to the SP whether created here or client-provided.
        $null = Set-AppRegistrationRoles -ServicePrincipalId $appReg.ServicePrincipal.Id `
            -SubscriptionId $script:ConfigData['SubscriptionId'] `
            -ResourceGroupName $script:ResourceGroupName `
            -SecurityGroups $securityGroups

        # Step 12: Create Key Vault and store client secret
        if (-not [string]::IsNullOrWhiteSpace($script:KeyVaultNameOverride)) {
            # Explicit Key Vault name (from -KeyVaultName this run, or carried over from the
            # checkpoint on resume) — use it as-is.
            $keyVaultName = $script:KeyVaultNameOverride
            Write-Log "Using Key Vault name override: $keyVaultName" -Level Info
        }
        else {
            $keyVaultName = "kv$($script:ConfigData['SolutionShortName'])"
        }

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

        # Step 12b: NCE auth app (project#1084). Created here - in the Global
        # Admin session - so the Harness user group assignment that the v5
        # groups-claim login depends on happens at onboarding time. The
        # deployment pipeline's ensure-app-regs.sh finds this app by
        # uniqueName, reuses it and reconciles its properties; its own
        # best-effort assignment (blocked for the hardened deploy SP) becomes
        # a no-op. Retires hard-blocking migration runsheet step 7b for
        # environments onboarded from this version.
        $null = New-NeologikNceAuthApp -SecurityGroups $securityGroups `
            -DeploySpObjectId $appReg.ServicePrincipal.Id `
            -KeyVaultName $keyVaultName

        # Step 12c: Entra Agent ID blueprint (project#2144). Created here - in the
        # Global Admin session - so the deployment service principal never needs
        # the tenant-wide blueprint-creation roles. The signed-in operator is the
        # blueprint's sponsor (the accountable business owner; changeable later
        # in the Entra admin centre); the deployment SP owns it and the pipeline
        # acts as the blueprint through the GitHub credentials added here.
        $null = New-NeologikAgentBlueprint -DeploySpObjectId $appReg.ServicePrincipal.Id `
            -SponsorUserId $script:ConfigData['CurrentUserId']

        # (Step 13, resource provider registration, was submitted at step 5c and is confirmed
        # in full at step 15b, before the configuration is exported.)

        # (The subscription-scoped Cost Management scheduled email is created and
        # maintained by the infrastructure deployment - neo-infrastructure
        # scripts/ensure-cost-report-emails.sh - authorised by the SP's
        # 'Cost Management Contributor' grant above, project#1215. Onboarding only
        # collects the recipients, exported via the Configuration JSON.)

        # Step 14: Create Storage Account and blob container for certificates.
        # Name was resolved during configuration gathering (answer file / prompt / computed).
        # Fall back to the computed name for checkpoints written before this field existed.
        $storageAccountName = [string]$script:ConfigData['DeployStorageAccountName']
        if ([string]::IsNullOrWhiteSpace($storageAccountName)) {
            $storageAccountName = "stneodeploy$($script:OrganizationCode.ToLower())$($script:EnvironmentType.ToLower())$regionAbbrev$($script:EnvironmentIndex)"
        }

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
            -EnvironmentType $script:EnvironmentType `
            -EnvironmentIndex $script:EnvironmentIndex `
            -ScriptRunnerIdentityName ([string]$script:ConfigData['ScriptRunnerIdentityName']) `
            -SqlIdentityName ([string]$script:ConfigData['SqlIdentityName'])

        # Step 15b: Confirm the full resource provider and preview-feature list. Anything still
        # pending is reported and exported as ResourceProvidersPending.
        Complete-ResourceProviderRegistration -ProviderList $script:ProviderList
        Complete-OnboardingStep 'ResourceProviders'

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
