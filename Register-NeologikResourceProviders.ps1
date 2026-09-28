<#
.SYNOPSIS
    Registers, on one Azure subscription, the Azure resource providers and preview
    features the Neologik Platform requires, from the list in resource-providers.txt.

.DESCRIPTION
    Registration is an operation on the subscription. Install-NeologikEnvironment.ps1
    submits the whole list during onboarding. This script confirms the same list
    afterwards, and completes any registration that is outstanding, for example when the
    onboarding run reported registrations still in progress.

    Run it with an account that holds Contributor or Owner on the subscription. The
    deployment identity cannot register a provider, so a provider that is not registered
    causes the platform deployment to fail.

    Every registration is submitted first, then the whole list is checked together
    until every entry is registered or the time allowed has passed. An entry that is
    registered already is left alone, so the script can be run as often as needed. It
    exits with code 1 if an entry is still not registered at the end.

.PARAMETER SubscriptionId
    The subscription on which to register. Default: the subscription of the Azure session.

.PARAMETER TenantId
    The tenant to sign in to. Used only when no Azure session exists.

.PARAMETER TimeoutSeconds
    How long to wait for the registrations to complete. Default: 900.

.PARAMETER ListOnly
    Shows the list and stops. No sign-in takes place and Azure is not contacted.

.EXAMPLE
    ./Register-NeologikResourceProviders.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000

.EXAMPLE
    ./Register-NeologikResourceProviders.ps1 -ListOnly

.NOTES
    Requires PowerShell 7.4 or later and the modules Az.Accounts and Az.Resources.
    The list is the file resource-providers.txt, beside this script.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 900,

    [Parameter(Mandatory = $false)]
    [switch]$ListOnly
)

$ErrorActionPreference = 'Stop'

# --- Read the list -------------------------------------------------------------------------------
function Get-PlatformResourceProviderList {
    $path = Join-Path $PSScriptRoot 'resource-providers.txt'
    if (-not (Test-Path $path)) {
        throw "Resource provider list not found: $path. The file is part of the onboarding kit; restore it before running the script."
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
    foreach ($f in $features) {
        if (-not $providers.Contains($f.Provider)) {
            throw "resource-providers.txt lists feature $($f.Provider)/$($f.Feature) but not its provider $($f.Provider)."
        }
    }
    return [pscustomobject]@{ Providers = [string[]]$providers; Features = @($features); Path = $path }
}

$list = Get-PlatformResourceProviderList

if ($ListOnly) {
    Write-Host "Resource providers ($($list.Providers.Count)) from $($list.Path):"
    $list.Providers | ForEach-Object { Write-Host "  $_" }
    Write-Host "Preview features ($($list.Features.Count)):"
    $list.Features | ForEach-Object { Write-Host "  $($_.Provider)/$($_.Feature)" }
    exit 0
}

# --- Sign in and select the subscription ---------------------------------------------------------
$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    Write-Host "No Azure context found - signing in..." -ForegroundColor Yellow
    $connectParams = @{}
    if ($TenantId) { $connectParams['TenantId'] = $TenantId }
    # Azure requires multi-factor authentication for every write. The sign-in requests the
    # 'p1' authentication-context claim, so that a registration is not refused.
    # The value decodes to {"access_token":{"acrs":{"essential":true,"values":["p1"]}}}. Requires Az.Accounts 5.2.0 or later.
    if ((Get-Command Connect-AzAccount).Parameters.ContainsKey('ClaimsChallenge')) {
        $connectParams['ClaimsChallenge'] = 'eyJhY2Nlc3NfdG9rZW4iOnsiYWNycyI6eyJlc3NlbnRpYWwiOnRydWUsInZhbHVlcyI6WyJwMSJdfX19'
    }
    Connect-AzAccount @connectParams | Out-Null
}

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
}
$context = Get-AzContext -ErrorAction Stop
if (-not $context.Subscription) {
    throw "No active subscription. Pass -SubscriptionId or select one with Set-AzContext."
}

Write-Host ""
Write-Host "Registering Neologik platform resource providers and preview features" -ForegroundColor Magenta
Write-Host "  Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Gray
Write-Host "  List:         $($list.Path) ($($list.Providers.Count) providers, $($list.Features.Count) features)" -ForegroundColor Gray
Write-Host ""

# --- Submit every registration without waiting ---------------------------------------------------
$pendingProviders = [System.Collections.Generic.List[string]]::new()
$pendingFeatures = [System.Collections.Generic.List[hashtable]]::new()

Write-Host "Submitting registrations:" -ForegroundColor Cyan
foreach ($ns in $list.Providers) {
    $state = (Get-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Select-Object -First 1).RegistrationState
    if ($state -eq 'Registered') {
        Write-Host "  - $ns already registered" -ForegroundColor DarkGray
        continue
    }
    if ($state -ne 'Registering') {
        Register-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Out-Null
    }
    Write-Host "  - $ns requested (was $state)" -ForegroundColor Cyan
    $pendingProviders.Add($ns)
}
foreach ($f in $list.Features) {
    $key = "$($f.Provider)/$($f.Feature)"
    $state = (Get-AzProviderFeature -ProviderNamespace $f.Provider -FeatureName $f.Feature -ErrorAction Stop).RegistrationState
    if ($state -eq 'Registered') {
        Write-Host "  - $key already registered" -ForegroundColor DarkGray
        continue
    }
    if ($state -notin @('Registering', 'Pending')) {
        Register-AzProviderFeature -ProviderNamespace $f.Provider -FeatureName $f.Feature -ErrorAction Stop | Out-Null
    }
    Write-Host "  - $key requested (was $state)" -ForegroundColor Cyan
    $pendingFeatures.Add($f)
}

# --- Check the whole list together ---------------------------------------------------------------
if ($pendingProviders.Count -eq 0 -and $pendingFeatures.Count -eq 0) {
    Write-Host ""
    Write-Host "Done. Every provider and preview feature is already registered." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "Waiting for $($pendingProviders.Count) provider(s) and $($pendingFeatures.Count) feature(s) to reach Registered (timeout ${TimeoutSeconds}s)..." -ForegroundColor Cyan
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$resubmitted = @{}
$intervalSeconds = 15

while ($true) {
    foreach ($ns in @($pendingProviders)) {
        try { $state = (Get-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Select-Object -First 1).RegistrationState }
        catch { Write-Warning "  Could not read the state of $ns ($($_.Exception.Message)); retrying on the next pass"; continue }
        if ($state -eq 'Registered') {
            Write-Host "  + $ns registered" -ForegroundColor Green
            $pendingProviders.Remove($ns) | Out-Null
        }
        elseif ($state -ne 'Registering' -and -not $resubmitted[$ns]) {
            Write-Warning "  $ns reports $state; re-submitting the registration"
            $resubmitted[$ns] = $true
            Register-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Out-Null
        }
    }
    foreach ($f in @($pendingFeatures)) {
        $key = "$($f.Provider)/$($f.Feature)"
        try { $state = (Get-AzProviderFeature -ProviderNamespace $f.Provider -FeatureName $f.Feature -ErrorAction Stop).RegistrationState }
        catch { Write-Warning "  Could not read the state of $key ($($_.Exception.Message)); retrying on the next pass"; continue }
        if ($state -eq 'Registered') {
            # Register the provider again, so that the feature takes effect on it.
            Register-AzResourceProvider -ProviderNamespace $f.Provider -ErrorAction Stop | Out-Null
            Write-Host "  + $key registered" -ForegroundColor Green
            $pendingFeatures.Remove($f) | Out-Null
        }
        elseif ($state -notin @('Registering', 'Pending') -and -not $resubmitted[$key]) {
            Write-Warning "  $key reports $state; re-submitting the registration"
            $resubmitted[$key] = $true
            Register-AzProviderFeature -ProviderNamespace $f.Provider -FeatureName $f.Feature -ErrorAction Stop | Out-Null
        }
    }
    if ($pendingProviders.Count -eq 0 -and $pendingFeatures.Count -eq 0) { break }
    if ((Get-Date) -ge $deadline) { break }
    Write-Host "  ... $($pendingProviders.Count + $pendingFeatures.Count) still registering" -ForegroundColor DarkGray
    Start-Sleep -Seconds $intervalSeconds
}

$remaining = @($pendingProviders) + @($pendingFeatures | ForEach-Object { "$($_.Provider)/$($_.Feature)" })
Write-Host ""
if ($remaining.Count -eq 0) {
    Write-Host "Done. All $($list.Providers.Count) providers and $($list.Features.Count) preview features are registered." -ForegroundColor Green
    exit 0
}

Write-Warning "Still not registered after ${TimeoutSeconds}s: $($remaining -join ', '). Azure continues in the background; run this script again to confirm before the deployment."
exit 1
