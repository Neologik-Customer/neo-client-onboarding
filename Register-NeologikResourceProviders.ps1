<#
.SYNOPSIS
    Registers the Azure resource providers and the preview features that the Neologik
    Platform requires, on one Azure subscription. The file resource-providers.txt
    holds the list.

.DESCRIPTION
    Install-NeologikEnvironment.ps1 submits every registration of the list during
    onboarding. This script confirms every registration after onboarding. This script
    also submits each registration that is missing.

    Run this script with an account that holds the Contributor role or the Owner role
    on the subscription. The deployment identity cannot register a resource provider.
    The deployment of the Neologik Platform fails when a resource provider is not
    registered.

    The script works in this order:
    1. The script submits every registration.
    2. The script checks the whole list until every entry is registered, or until
       the wait ends.

    The script makes no change to an entry that is already registered. An
    administrator can run the script any number of times. The script ends with exit
    code 1 when an entry is still not registered at the end of the wait.

.PARAMETER SubscriptionId
    The subscription where the script registers the resource providers. Default: the
    subscription of the Azure session.

.PARAMETER TenantId
    The tenant to sign in to. The script uses the value only when no Azure session
    exists.

.PARAMETER TimeoutSeconds
    The number of seconds that the script waits for the registrations. Default: 900.

.PARAMETER ListOnly
    The script shows the list and stops. The script makes no sign-in and contacts no
    Azure service.

.EXAMPLE
    ./Register-NeologikResourceProviders.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000

.EXAMPLE
    ./Register-NeologikResourceProviders.ps1 -ListOnly

.NOTES
    Requires PowerShell 7.4 or later and the modules Az.Accounts and Az.Resources.
    The list is the file resource-providers.txt, in the folder of this script.
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
        throw "Resource provider list not found: $path. The file is part of the onboarding kit. Copy the file to the folder of this script and run the script again."
    }

    $providers = [System.Collections.Generic.List[string]]::new()
    $featureKeys = [System.Collections.Generic.List[string]]::new()
    $features = @()
    $lineNumber = 0
    foreach ($raw in @(Get-Content -Path $path)) {
        $lineNumber++
        # Text from '#' to the end of the line is a comment. The '#' can stand anywhere on the line.
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
            throw "resource-providers.txt line ${lineNumber}: '$line' is not valid. A resource provider has the form Microsoft.Example. A preview feature has the form Microsoft.Example/FeatureName."
        }
    }
    if ($providers.Count -eq 0) { throw "resource-providers.txt lists no resource provider." }
    foreach ($f in $features) {
        if (-not $providers.Contains($f.Provider)) {
            throw "resource-providers.txt lists the preview feature $($f.Provider)/$($f.Feature) without the resource provider $($f.Provider)."
        }
    }
    return [pscustomobject]@{ Providers = [string[]]$providers; Features = @($features); Path = $path }
}

$list = Get-PlatformResourceProviderList

if ($ListOnly) {
    Write-Host "Resource providers from $($list.Path), $($list.Providers.Count) in total:"
    $list.Providers | ForEach-Object { Write-Host "  $_" }
    Write-Host "Preview features, $($list.Features.Count) in total:"
    $list.Features | ForEach-Object { Write-Host "  $($_.Provider)/$($_.Feature)" }
    exit 0
}

# --- Sign in and select the subscription ---------------------------------------------------------
$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    Write-Host "No Azure session found. Signing in..." -ForegroundColor Yellow
    $connectParams = @{}
    if ($TenantId) { $connectParams['TenantId'] = $TenantId }
    # Azure requires multi-factor authentication for every write. The sign-in requests the
    # 'p1' authentication-context claim. Azure refuses a registration without the claim.
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
    throw "No subscription is selected. Give -SubscriptionId, or select a subscription with Set-AzContext."
}

Write-Host ""
Write-Host "Registering the resource providers and the preview features of the Neologik Platform" -ForegroundColor Magenta
Write-Host "  Subscription: $($context.Subscription.Name), id $($context.Subscription.Id)" -ForegroundColor Gray
Write-Host "  List:         $($list.Path), $($list.Providers.Count) resource providers and $($list.Features.Count) preview features" -ForegroundColor Gray
Write-Host ""

# --- Submit every registration without waiting ---------------------------------------------------
$pendingProviders = [System.Collections.Generic.List[string]]::new()
$pendingFeatures = [System.Collections.Generic.List[hashtable]]::new()

Write-Host "Submitting registrations:" -ForegroundColor Cyan
foreach ($ns in $list.Providers) {
    $state = (Get-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Select-Object -First 1).RegistrationState
    if ($state -eq 'Registered') {
        Write-Host "  - $ns is already registered" -ForegroundColor DarkGray
        continue
    }
    if ($state -ne 'Registering') {
        Register-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Out-Null
    }
    Write-Host "  - $ns registration submitted. The state was $state" -ForegroundColor Cyan
    $pendingProviders.Add($ns)
}
foreach ($f in $list.Features) {
    $key = "$($f.Provider)/$($f.Feature)"
    $state = (Get-AzProviderFeature -ProviderNamespace $f.Provider -FeatureName $f.Feature -ErrorAction Stop).RegistrationState
    if ($state -eq 'Registered') {
        Write-Host "  - $key is already registered" -ForegroundColor DarkGray
        continue
    }
    if ($state -notin @('Registering', 'Pending')) {
        Register-AzProviderFeature -ProviderNamespace $f.Provider -FeatureName $f.Feature -ErrorAction Stop | Out-Null
    }
    Write-Host "  - $key registration submitted. The state was $state" -ForegroundColor Cyan
    $pendingFeatures.Add($f)
}

# --- Check the whole list together ---------------------------------------------------------------
if ($pendingProviders.Count -eq 0 -and $pendingFeatures.Count -eq 0) {
    Write-Host ""
    Write-Host "Done. Every resource provider and every preview feature is already registered." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "Waiting for $($pendingProviders.Count) resource providers and $($pendingFeatures.Count) preview features. The wait ends after ${TimeoutSeconds} seconds..." -ForegroundColor Cyan
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$resubmitted = @{}
$intervalSeconds = 15

while ($true) {
    foreach ($ns in @($pendingProviders)) {
        try { $state = (Get-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Select-Object -First 1).RegistrationState }
        catch { Write-Warning "  The script could not read the state of ${ns}: $($_.Exception.Message). The script reads the state again at the next check"; continue }
        if ($state -eq 'Registered') {
            Write-Host "  + $ns registered" -ForegroundColor Green
            $pendingProviders.Remove($ns) | Out-Null
        }
        elseif ($state -ne 'Registering' -and -not $resubmitted[$ns]) {
            Write-Warning "  $ns reports the state $state. The script submits the registration again"
            $resubmitted[$ns] = $true
            Register-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Out-Null
        }
    }
    foreach ($f in @($pendingFeatures)) {
        $key = "$($f.Provider)/$($f.Feature)"
        try { $state = (Get-AzProviderFeature -ProviderNamespace $f.Provider -FeatureName $f.Feature -ErrorAction Stop).RegistrationState }
        catch { Write-Warning "  The script could not read the state of ${key}: $($_.Exception.Message). The script reads the state again at the next check"; continue }
        if ($state -eq 'Registered') {
            # Register the resource provider again. The preview feature then becomes active on the resource provider.
            Register-AzResourceProvider -ProviderNamespace $f.Provider -ErrorAction Stop | Out-Null
            Write-Host "  + $key registered" -ForegroundColor Green
            $pendingFeatures.Remove($f) | Out-Null
        }
        elseif ($state -notin @('Registering', 'Pending') -and -not $resubmitted[$key]) {
            Write-Warning "  $key reports the state $state. The script submits the registration again"
            $resubmitted[$key] = $true
            Register-AzProviderFeature -ProviderNamespace $f.Provider -FeatureName $f.Feature -ErrorAction Stop | Out-Null
        }
    }
    if ($pendingProviders.Count -eq 0 -and $pendingFeatures.Count -eq 0) { break }
    if ((Get-Date) -ge $deadline) { break }
    Write-Host "  Registrations still in progress: $($pendingProviders.Count + $pendingFeatures.Count)" -ForegroundColor DarkGray
    Start-Sleep -Seconds $intervalSeconds
}

$remaining = @($pendingProviders) + @($pendingFeatures | ForEach-Object { "$($_.Provider)/$($_.Feature)" })
Write-Host ""
if ($remaining.Count -eq 0) {
    Write-Host "Done. All $($list.Providers.Count) resource providers and $($list.Features.Count) preview features are registered." -ForegroundColor Green
    exit 0
}

Write-Warning "Still not registered after ${TimeoutSeconds} seconds: $($remaining -join ', '). Azure completes the registration without further action. Run this script again before the deployment to confirm."
exit 1
