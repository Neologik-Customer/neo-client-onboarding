<#
.SYNOPSIS
    Force-upgrade every user's installed version of Neologik Teams bot apps
    to the latest version published in the org Teams catalog.

.DESCRIPTION
    Calls Microsoft Graph to:
    1. List all Teams apps in the org catalog whose displayName matches a
       prefix (default "Neologik") — picks up every Neologik bot regardless
       of suffix (Claire Chalmers, Bidding, Lotti, SQL Agent, etc.).
    2. For each matched app, find its current installations across the tenant.
    3. Upgrade stale installations to the latest catalog version silently —
       no "Update" prompt shown to the user.

    Designed to be runnable by any support engineer with the required Entra
    role (Cloud Application Administrator, Application Administrator, or
    Global Administrator) without prior Graph experience and without access
    to the neo-env-config repo.

.PARAMETER NamePrefix
    Match Teams apps whose displayName starts with this string. Default:
    "Neologik" — covers every Neologik bot in the tenant.

.PARAMETER AppId
    Optional override. Specific Teams app manifest "id" GUID(s) to upgrade.
    When supplied, skips the displayName lookup and operates only on these.
    Accepts multiple GUIDs.

.PARAMETER TenantId
    Azure tenant ID to sign in to. Optional — if omitted, the admin signs
    in to whichever tenant is offered.

.PARAMETER UseDeviceAuthentication
    Use device-code sign-in instead of a browser pop-up. Required on locked-down
    corporate machines where browser auth is blocked.

.PARAMETER Force
    Skip the pre-flight confirmation prompt and proceed to upgrade directly.
    Use only when running unattended.

.PARAMETER WhatIf
    Report which users would be upgraded without performing the upgrade.

.EXAMPLE
    .\Upgrade-TeamsAppInstallations.ps1
    # Upgrades every "Neologik *" app in the tenant.

.EXAMPLE
    .\Upgrade-TeamsAppInstallations.ps1 -NamePrefix "Neologik - Claire"
    # Only the Claire Chalmers bot.

.EXAMPLE
    .\Upgrade-TeamsAppInstallations.ps1 -AppId "afcd3e4c-1d8d-4094-8cba-5f9e7059cd58"
    # Specific bot by manifest GUID.

.EXAMPLE
    .\Upgrade-TeamsAppInstallations.ps1 -WhatIf
    # Dry run.

.NOTES
    Version: v0.2.0
    Requires: PowerShell 7.4+
    Requires: Microsoft.Graph module (auto-installed if missing)
    Requires Entra role: Cloud Application Administrator (or higher)
    Graph delegated scopes consented at sign-in:
        - AppCatalog.Read.All
        - TeamsAppInstallation.ReadWriteAndConsentForUser.All
        - User.Read.All
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string]$NamePrefix = 'Neologik',

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string[]]$AppId,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [switch]$UseDeviceAuthentication,

    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$script:Version = 'v0.2.0'
$script:FileTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogFile = Join-Path $PSScriptRoot "TeamsAppUpgrade_$($script:FileTimestamp).log"
$script:ReportFile = Join-Path $PSScriptRoot "TeamsAppUpgrade_$($script:FileTimestamp).csv"

#region Logging

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')][string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $script:LogFile -Value "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'Info'    { Write-Host $Message }
        'Warning' { Write-Host $Message -ForegroundColor Yellow }
        'Error'   { Write-Host $Message -ForegroundColor Red }
        'Success' { Write-Host $Message -ForegroundColor Green }
    }
}

function Write-Header {
    $target = if ($AppId) { "AppIds: $($AppId -join ', ')" } else { "NamePrefix: '$NamePrefix'" }
    $header = @"

===============================================================
   NEOLOGIK TEAMS APP BULK UPGRADE  $script:Version
   $target
   Log: $script:LogFile
===============================================================

"@
    Write-Host $header -ForegroundColor Cyan
    Write-Log "Starting bulk upgrade ($target)" -Level Info
}

#endregion

#region Prerequisites

function Test-PowerShellVersion {
    if ($PSVersionTable.PSVersion -lt [Version]'7.4.0') {
        Write-Log "PowerShell 7.4+ required. Current: $($PSVersionTable.PSVersion)" -Level Error
        Write-Host "Install or update from: https://learn.microsoft.com/powershell/" -ForegroundColor Yellow
        exit 1
    }
    Write-Log "PowerShell $($PSVersionTable.PSVersion) OK" -Level Success
}

function Install-GraphModule {
    $required = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Users', 'Microsoft.Graph.Teams')
    $missing = $required | Where-Object { -not (Get-Module -ListAvailable -Name $_) }

    if ($missing) {
        $gallery = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue
        if ($gallery -and $gallery.InstallationPolicy -ne 'Trusted') {
            Write-Log "Marking PSGallery as trusted (avoids interactive prompt)" -Level Info
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
        }
        foreach ($module in $missing) {
            Write-Log "Installing $module (current user scope)..." -Level Info
            Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
        }
    }

    foreach ($module in $required) {
        Import-Module $module -ErrorAction Stop
    }
    Write-Log "Microsoft.Graph modules ready" -Level Success
}

#endregion

#region Graph operations

$script:RequiredScopes = @(
    'AppCatalog.Read.All',
    'TeamsAppInstallation.ReadWriteAndConsentForUser.All',
    'User.Read.All'
)

function Invoke-GraphSignIn {
    param([switch]$ForceDeviceCode)

    $connectParams = @{ Scopes = $script:RequiredScopes; NoWelcome = $true }
    if ($TenantId) { $connectParams['TenantId'] = $TenantId }
    if ($ForceDeviceCode -or $UseDeviceAuthentication) {
        $connectParams['UseDeviceAuthentication'] = $true
        Write-Host "  Device code authentication — code will appear shortly." -ForegroundColor Yellow
    } else {
        Write-Host "  A browser window will open — sign in with an admin account." -ForegroundColor Yellow
    }

    try {
        Connect-MgGraph @connectParams
    }
    catch {
        if (-not $connectParams['UseDeviceAuthentication']) {
            Write-Log "Browser auth failed: $($_.Exception.Message). Retrying with device code..." -Level Warning
            $connectParams['UseDeviceAuthentication'] = $true
            Connect-MgGraph @connectParams
        } else {
            throw
        }
    }
}

$script:GraphPowerShellClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'

function Test-CrossUserReadAccess {
    # Probe whether the current token actually permits CROSS-user installedApps reads.
    # Get-MgContext.Scopes alone is not sufficient — WAM returns tokens with the
    # scopes as claims even when the Graph PowerShell enterprise app does NOT have
    # admin consent for them in the tenant. Only an actual call reveals the truth.
    #
    # CRITICAL: must probe against a user OTHER than the signed-in user. Reading
    # one's own /users/{me-id}/teamwork/installedApps works under user-consent,
    # masking the admin-consent gap.
    try {
        $context = Get-MgContext
        $myUpn = $context.Account
        $myId = $null
        if ($myUpn) {
            try { $myId = (Get-MgUser -UserId $myUpn -Property Id -ErrorAction Stop).Id } catch { $myId = $null }
        }

        $candidates = Get-MgUser -Top 5 -Property Id, UserPrincipalName -ErrorAction Stop
        $other = $candidates | Where-Object { $_.Id -ne $myId } | Select-Object -First 1

        if (-not $other) {
            Write-Log "Probe inconclusive — tenant has fewer than 2 users; cannot test cross-user read" -Level Warning
            return $true
        }

        $uri = "https://graph.microsoft.com/v1.0/users/$($other.Id)/teamwork/installedApps?`$top=1"
        Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        if ($_.Exception.Message -match '403|Forbidden|insufficient privileges') {
            return $false
        }
        throw
    }
}

function Invoke-AdminConsentFlow {
    param([string]$TenantSegment)

    Write-Host @"

------------------------------------------------------------------
                  ADMIN CONSENT REQUIRED
------------------------------------------------------------------

The script needs admin consent for these Microsoft Graph scopes
to be granted to the Microsoft Graph PowerShell SDK app in this tenant:

  - AppCatalog.Read.All
  - TeamsAppInstallation.ReadWriteAndConsentForUser.All
  - User.Read.All

When you continue, the script will:
  1. Sign you out of the current Graph session.
  2. Re-sign you in via DEVICE CODE flow — which uses a normal
     Microsoft sign-in page (not WAM), so the full consent screen
     is shown.

On the consent screen in your browser:

  >>>  TICK the box 'Consent on behalf of your organization'  <<<
  >>>  THEN click ACCEPT.                                     <<<

You need to be signed in as a Global Administrator (or Cloud
Application Administrator / Application Administrator) for the
org-consent checkbox to be enabled.

If you DON'T tick the box, consent applies only to your account
and the script will keep failing for other users.

Press Enter to continue...
"@ -ForegroundColor Yellow

    Read-Host | Out-Null
}

function Connect-Graph {
    Write-Log "Signing in to Microsoft Graph..." -Level Info
    Invoke-GraphSignIn

    $context = Get-MgContext
    if (-not $context) {
        Write-Log "Sign-in did not complete" -Level Error
        exit 1
    }
    Write-Log "Connected as $($context.Account) on tenant $($context.TenantId)" -Level Success

    Write-Log "Probing cross-user read access..." -Level Info
    if (Test-CrossUserReadAccess) {
        Write-Log "Cross-user read access confirmed" -Level Success
        return
    }

    Write-Log "Probe failed — admin consent missing for the Graph PowerShell app in this tenant" -Level Warning
    Invoke-AdminConsentFlow -TenantSegment $context.TenantId

    Write-Log "Re-authenticating to pick up the new consent grant..." -Level Info
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Invoke-GraphSignIn -ForceDeviceCode

    Write-Log "Re-probing cross-user read access..." -Level Info
    if (-not (Test-CrossUserReadAccess)) {
        Write-Log "Probe still failing after consent flow" -Level Error
        Write-Host @"

Admin consent was not successfully granted. Possible causes:

  - The Accept button was not clicked on the consent screen.
  - The account used does not have a role that can grant tenant-wide consent
    (needs Global Administrator / Cloud App Administrator / Application Administrator).
  - A Conditional Access policy is blocking the consent operation.
  - 'User Consent Settings' (Entra ID -> Enterprise apps -> Consent and permissions)
    has 'Do not allow user consent' for all apps, including admin operations.

Aborting — investigate the above and re-run.

"@ -ForegroundColor Red
        exit 1
    }
    Write-Log "Admin consent granted and verified" -Level Success
}

function Find-NeologikApps {
    Write-Log "Searching org catalog for Neologik apps..." -Level Info

    try {
        if ($AppId) {
            $idsLower = $AppId | ForEach-Object { $_.ToLower() }
            $orClause = ($idsLower | ForEach-Object { "externalId eq '$_'" }) -join ' or '
            $uri = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps?`$filter=($orClause)&`$expand=appDefinitions"
            $candidates = (Invoke-MgGraphRequest -Method GET -Uri $uri).value
        } else {
            # Fetch all LOB (custom-uploaded) apps with their published definitions
            $uri = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps?`$filter=distributionMethod eq 'organization'&`$expand=appDefinitions"
            $candidates = (Invoke-MgGraphRequest -Method GET -Uri $uri).value
        }
    }
    catch {
        if ($_.Exception.Message -match '403|Forbidden|insufficient privileges') {
            Write-Log "INSUFFICIENT PRIVILEGES — the signed-in account does not have permission to read the app catalog." -Level Error
            Write-Host "The account you signed in with needs one of these Entra roles:" -ForegroundColor Yellow
            Write-Host "  - Cloud Application Administrator" -ForegroundColor Yellow
            Write-Host "  - Application Administrator" -ForegroundColor Yellow
            Write-Host "  - Global Administrator" -ForegroundColor Yellow
            Write-Host "Ask the customer to assign one of these roles, then re-run." -ForegroundColor Yellow
            exit 1
        }
        throw
    }

    # Wrap in an array so single-result branches behave the same
    $candidates = @($candidates)
    if (-not $AppId) {

        # Identify Neologik bots by signals in the manifest that survive customer
        # rebranding: the hardcoded full description (appPackage/manifest.json),
        # the developer website URL, and the publisher MPN id.
        $signals = @('Neologik', 'neologik.ai', '6560934')
        $candidates = $candidates | Where-Object {
            $defs = @($_.appDefinitions)
            foreach ($def in $defs) {
                $haystack = "$($def.description) $($def.shortDescription) $($def.displayName)"
                foreach ($s in $signals) {
                    if ($haystack -match [regex]::Escape($s)) { return $true }
                }
            }
            return $false
        }
    }

    $candidates = @($candidates)
    if ($candidates.Count -eq 0) {
        Write-Log "No Neologik apps found in org catalog" -Level Error
        exit 1
    }

    $catalog = foreach ($app in $candidates) {
        $latestDef = $app.appDefinitions |
            Where-Object { $_.publishingState -eq 'published' } |
            Sort-Object createdDateTime -Descending |
            Select-Object -First 1

        if (-not $latestDef) {
            Write-Log "Skipping '$($app.displayName)' — no published appDefinition" -Level Warning
            continue
        }

        [PSCustomObject]@{
            AppId         = $app.id
            ExternalId    = $app.externalId
            DisplayName   = $app.displayName
            LatestVersion = $latestDef.version
            LatestDefId   = $latestDef.id
        }
    }

    Write-Log "Matched $($catalog.Count) Neologik app(s) in catalog:" -Level Success
    $catalog | ForEach-Object {
        Write-Log "  - $($_.DisplayName)  v$($_.LatestVersion)  (externalId $($_.ExternalId))" -Level Info
    }
    return $catalog
}

function Get-UsersWithInstallation {
    param([string]$CatalogAppId, [string]$DisplayName)

    Write-Log "Enumerating tenant users for '$DisplayName'..." -Level Info
    $users = Get-MgUser -All -Property Id, UserPrincipalName, DisplayName, AccountEnabled |
        Where-Object { $_.AccountEnabled }

    $installs = [System.Collections.Generic.List[object]]::new()
    $idx = 0
    $consecutiveForbidden = 0
    $consentAlreadyAttempted = $false
    $i = 0
    while ($i -lt $users.Count) {
        $user = $users[$i]
        $idx++
        if ($idx % 50 -eq 0) {
            Write-Host "    Checked $idx / $($users.Count)..." -ForegroundColor DarkGray
        }
        try {
            $uri = "https://graph.microsoft.com/v1.0/users/$($user.Id)/teamwork/installedApps?`$filter=teamsApp/id eq '$CatalogAppId'&`$expand=teamsApp,teamsAppDefinition"
            $r = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
            $consecutiveForbidden = 0
            if ($r.value -and $r.value.Count -gt 0) {
                foreach ($inst in $r.value) {
                    $installs.Add([PSCustomObject]@{
                        UserId         = $user.Id
                        Upn            = $user.UserPrincipalName
                        DisplayName    = $user.DisplayName
                        InstallationId = $inst.id
                        InstalledVer   = $inst.teamsAppDefinition.version
                        InstalledDefId = $inst.teamsAppDefinition.id
                    })
                }
            }
            $i++
        }
        catch {
            $msg = $_.Exception.Message
            if ($msg -match '403|Forbidden|insufficient privileges') {
                $consecutiveForbidden++
                Write-Log "    Skipped $($user.UserPrincipalName): 403 Forbidden ($consecutiveForbidden so far)" -Level Warning

                if (-not $consentAlreadyAttempted) {
                    Write-Log "403 Forbidden on per-user read — admin consent likely missing. Triggering consent flow now." -Level Warning
                    $consentAlreadyAttempted = $true
                    $context = Get-MgContext
                    Invoke-AdminConsentFlow -TenantSegment $context.TenantId
                    Write-Log "Re-authenticating to pick up the new consent grant..." -Level Info
                    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
                    Invoke-GraphSignIn -ForceDeviceCode
                    $consecutiveForbidden = 0
                    # Don't advance $i — retry the same user with the new token
                    continue
                }

                if ($consecutiveForbidden -ge 3) {
                    Write-Log "Aborting — still seeing 403s after admin consent flow." -Level Error
                    Write-Host @"

The script attempted to grant admin consent and re-authenticate, but
per-user reads are still 403. Likely causes:

  - The Accept button was not clicked on the admin consent screen.
  - The signed-in account does not have a role that grants tenant-wide
    consent: needs Global Administrator / Cloud Application Administrator /
    Application Administrator.
  - A Conditional Access policy is blocking the Graph PowerShell SDK app
    (id 14d82eec-204b-4c2f-b7e8-296a70dab67e) for this account.
  - Entra ID -> Enterprise apps -> Consent and permissions has 'Do not
    allow user consent' configured restrictively for delegated admin ops.

Check Entra ID -> Sign-in logs for the Graph PowerShell app ID above.

"@ -ForegroundColor Red
                    throw "Aborted after $consecutiveForbidden consecutive 403s (consent flow already attempted)."
                }

                $i++
            } else {
                $consecutiveForbidden = 0
                Write-Log "    Skipped $($user.UserPrincipalName): $msg" -Level Warning
                $i++
            }
        }
    }

    Write-Log "  Found $($installs.Count) installation(s) of '$DisplayName'" -Level Success
    return $installs
}

function Invoke-UserUpgrade {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]$Installation,
        [Parameter(Mandatory = $true)]$Catalog
    )

    if ($Installation.InstalledDefId -eq $Catalog.LatestDefId) {
        return 'AlreadyLatest'
    }

    if (-not $PSCmdlet.ShouldProcess($Installation.Upn, "Upgrade '$($Catalog.DisplayName)' $($Installation.InstalledVer) -> $($Catalog.LatestVersion)")) {
        return 'WhatIf'
    }

    try {
        $uri = "https://graph.microsoft.com/v1.0/users/$($Installation.UserId)/teamwork/installedApps/$($Installation.InstallationId)/upgrade"
        $body = @{ consentedPermissionSet = @{ resourceSpecificPermissions = @() } } | ConvertTo-Json -Depth 4
        Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType 'application/json' -ErrorAction Stop
        return 'Upgraded'
    }
    catch {
        if ($_.Exception.Message -match '403|Forbidden|insufficient privileges') {
            Write-Log "INSUFFICIENT PRIVILEGES on upgrade call." -Level Error
            Write-Host "The signed-in account can read the catalog but cannot upgrade installations." -ForegroundColor Yellow
            Write-Host "It is missing the TeamsAppInstallation.ReadWriteAndConsentForUser.All scope or an Entra role" -ForegroundColor Yellow
            Write-Host "with that consent. Ask the customer to assign Cloud Application Administrator (or higher)." -ForegroundColor Yellow
            throw "Aborting — insufficient privileges on upgrade endpoint."
        }
        Write-Log "    Upgrade failed for $($Installation.Upn): $($_.Exception.Message)" -Level Warning
        return "Failed: $($_.Exception.Message)"
    }
}

#endregion

#region Main

function Invoke-Main {
    Write-Header
    Test-PowerShellVersion
    Install-GraphModule
    Connect-Graph

    $catalogApps = Find-NeologikApps

    if (-not $Force -and -not $WhatIfPreference) {
        Write-Host "`nAbout to upgrade installations for the apps listed above." -ForegroundColor Yellow
        Write-Host "This will silently update every user's installed version — no prompt is shown to them." -ForegroundColor Yellow
        Write-Host "Type " -NoNewline; Write-Host "YES" -ForegroundColor Green -NoNewline; Write-Host " to proceed, or anything else to abort: " -NoNewline
        $reply = Read-Host
        if ($reply -ne 'YES') {
            Write-Log "Aborted by user at pre-flight confirmation" -Level Warning
            return
        }
    }

    $report = [System.Collections.Generic.List[object]]::new()

    foreach ($app in $catalogApps) {
        Write-Host "`n--- $($app.DisplayName) (v$($app.LatestVersion)) ---" -ForegroundColor Cyan
        $installs = Get-UsersWithInstallation -CatalogAppId $app.AppId -DisplayName $app.DisplayName

        if ($installs.Count -eq 0) {
            continue
        }

        foreach ($inst in $installs) {
            $status = Invoke-UserUpgrade -Installation $inst -Catalog $app
            $report.Add([PSCustomObject]@{
                App         = $app.DisplayName
                ExternalId  = $app.ExternalId
                Upn         = $inst.Upn
                DisplayName = $inst.DisplayName
                FromVersion = $inst.InstalledVer
                ToVersion   = $app.LatestVersion
                Status      = $status
            })
        }
    }

    if ($report.Count -eq 0) {
        Write-Log "No installations found across $($catalogApps.Count) app(s) — nothing to do" -Level Warning
        return
    }

    $report | Export-Csv -Path $script:ReportFile -NoTypeInformation
    Write-Log "`nReport written: $script:ReportFile" -Level Success

    $summary = $report | Group-Object App, Status | Select-Object Name, Count
    Write-Host "`nSummary:" -ForegroundColor Cyan
    $summary | Format-Table -AutoSize | Out-Host

    Disconnect-MgGraph | Out-Null
    Write-Log "Done." -Level Success
}

try {
    Invoke-Main
}
catch {
    Write-Log "Fatal: $($_.Exception.Message)" -Level Error
    Write-Log $_.ScriptStackTrace -Level Error
    exit 1
}

#endregion
