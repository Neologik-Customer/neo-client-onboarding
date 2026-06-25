<#
.SYNOPSIS
    Registers all Azure resource providers and preview features required by the Neologik platform
    deployment on a subscription.

.DESCRIPTION
    Provider and feature registration is a one-time, subscription-scoped operation. Install-Neologik-
    Environment.ps1 registers the full set when the operator opts in; if they opt out (the default),
    only a minimal set is registered there and this script must be run separately - by someone with
    Contributor (or Owner) on the subscription - before the infrastructure deployment runs. Running
    it here keeps the deployment service connection free of subscription-scoped permissions.

    Idempotent: providers/features already registered are detected and skipped. Safe to re-run.

.PARAMETER SubscriptionId
    Target subscription. Defaults to the current Azure context's subscription.

.PARAMETER TenantId
    Optional tenant to authenticate against if no Azure context exists.

.EXAMPLE
    ./Register-NeologikResourceProviders.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000

.NOTES
    Requires PowerShell 7.4+ and the Az.Accounts + Az.Resources modules.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$TenantId
)

$ErrorActionPreference = 'Stop'

# Full provider set required across the platform deployment. Keep in sync with the $allProviders
# list in Install-NeologikEnvironment.ps1 (Register-AllResourceProviders).
$providers = @(
    'Microsoft.Resources',
    'Microsoft.App',
    'Microsoft.Automation',
    'Microsoft.ManagedIdentity',
    'Microsoft.CognitiveServices',
    'Microsoft.DocumentDB',
    'Microsoft.Network',
    'Microsoft.ContainerRegistry',
    'Microsoft.OperationalInsights',
    'Microsoft.KeyVault',
    'Microsoft.Insights',
    'Microsoft.Search',
    'Microsoft.Storage',
    'Microsoft.ContainerService',
    'Microsoft.ContainerInstance',
    'Microsoft.Web',
    'Microsoft.MachineLearningServices',
    'Microsoft.AlertsManagement',
    'Microsoft.BotService',
    'Microsoft.Compute',
    'Microsoft.Monitor',
    'Microsoft.Quota',
    'Microsoft.Diagnostics',
    'Microsoft.ChangeSafety',
    'Microsoft.Fabric',
    'Microsoft.Help',
    'Microsoft.ResourceHealth',
    'Microsoft.SaaS',
    'Microsoft.ServiceLinker',
    'Microsoft.Sql'
)

# Preview features: ProviderNamespace / FeatureName pairs the deployment requires.
$features = @(
    @{ Provider = 'Microsoft.Compute';          Feature = 'EncryptionAtHost' },
    @{ Provider = 'Microsoft.ContainerService'; Feature = 'AzureLinuxCVMPreview' }
)

function Register-Provider {
    param([string]$Namespace)

    $provider = Get-AzResourceProvider -ProviderNamespace $Namespace -ErrorAction Stop |
        Select-Object -First 1
    if ($provider -and $provider.RegistrationState -eq 'Registered') {
        Write-Host "  - $Namespace already registered" -ForegroundColor DarkGray
        return
    }

    Write-Host "  - Registering $Namespace..." -ForegroundColor Cyan
    Register-AzResourceProvider -ProviderNamespace $Namespace -ErrorAction Stop | Out-Null

    $maxRetries = 20
    $waitSeconds = 15
    for ($i = 0; $i -lt $maxRetries; $i++) {
        Start-Sleep -Seconds $waitSeconds
        $state = (Get-AzResourceProvider -ProviderNamespace $Namespace -ErrorAction Stop |
            Select-Object -First 1).RegistrationState
        if ($state -eq 'Registered') {
            Write-Host "    + $Namespace registered" -ForegroundColor Green
            return
        }
    }
    Write-Warning "    $Namespace did not reach 'Registered' within the timeout - it may still be registering in the background."
}

function Register-Feature {
    param([string]$Namespace, [string]$Name)

    $feature = Get-AzProviderFeature -ProviderNamespace $Namespace -FeatureName $Name -ErrorAction Stop
    if ($feature.RegistrationState -eq 'Registered') {
        Write-Host "  - $Namespace/$Name already registered" -ForegroundColor DarkGray
        return
    }

    Write-Host "  - Registering feature $Namespace/$Name..." -ForegroundColor Cyan
    Register-AzProviderFeature -ProviderNamespace $Namespace -FeatureName $Name -ErrorAction Stop | Out-Null

    $maxRetries = 20
    $waitSeconds = 30
    for ($i = 0; $i -lt $maxRetries; $i++) {
        Start-Sleep -Seconds $waitSeconds
        $state = (Get-AzProviderFeature -ProviderNamespace $Namespace -FeatureName $Name -ErrorAction Stop).RegistrationState
        Write-Host "    ... $Namespace/$Name : $state ($($i + 1)/$maxRetries)" -ForegroundColor DarkGray
        if ($state -eq 'Registered') {
            # Re-register the provider so the newly enabled feature propagates.
            Register-AzResourceProvider -ProviderNamespace $Namespace -ErrorAction Stop | Out-Null
            Write-Host "    + $Namespace/$Name registered" -ForegroundColor Green
            return
        }
    }
    Write-Warning "    $Namespace/$Name did not reach 'Registered' within the timeout - check the Azure portal."
}

# --- Connect / select subscription -----------------------------------------------------------
$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    Write-Host "No Azure context found - signing in..." -ForegroundColor Yellow
    if ($TenantId) { Connect-AzAccount -TenantId $TenantId | Out-Null }
    else { Connect-AzAccount | Out-Null }
}

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
}
$context = Get-AzContext -ErrorAction Stop
if (-not $context.Subscription) {
    throw "No active subscription. Pass -SubscriptionId or select one with Set-AzContext."
}

Write-Host ""
Write-Host "Registering Neologik platform resource providers and features" -ForegroundColor Magenta
Write-Host "  Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Gray
Write-Host ""

Write-Host "Resource providers:" -ForegroundColor Cyan
foreach ($p in $providers) {
    try { Register-Provider -Namespace $p }
    catch { Write-Warning "  Failed to register provider ${p}: $($_.Exception.Message)" }
}

Write-Host ""
Write-Host "Preview features:" -ForegroundColor Cyan
foreach ($f in $features) {
    try { Register-Feature -Namespace $f.Provider -Name $f.Feature }
    catch { Write-Warning "  Failed to register feature $($f.Provider)/$($f.Feature): $($_.Exception.Message)" }
}

Write-Host ""
Write-Host "Done. Provider/feature registration submitted; any still in-progress will complete in the background." -ForegroundColor Green
