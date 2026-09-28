<#
.SYNOPSIS
    Upgrades every user's installed copy of the Neologik Teams apps to the latest
    version published in your organisation's Teams app catalogue.

.DESCRIPTION
    The script calls Microsoft Graph, as the signed-in administrator, to:
    1. Read the apps your organisation has uploaded to its Teams app catalogue and
       select the Neologik apps, by the Neologik name or Neologik's Microsoft partner
       number in the name or description of the app.
    2. Find, for each app selected, the users who have it installed.
    3. Upgrade each installation that is not at the latest version in the catalogue.
       The user sees no update prompt.

    It writes a log and a report beside itself. It creates no directory object and no
    credential, and removes nothing.

.PARAMETER AppId
    One or more Teams app manifest ids to upgrade. When given, the script upgrades the
    catalogue apps with those ids and does not search for the Neologik apps.

.PARAMETER TenantId
    The tenant to sign in to. When omitted, the administrator chooses the tenant at
    sign-in.

.PARAMETER UseDeviceAuthentication
    Signs in with a device code instead of the browser, for a workstation on which a
    browser sign-in is not possible.

.PARAMETER Force
    Omits the confirmation before the upgrade.

.PARAMETER WhatIf
    A dry run. Shows on screen what would be upgraded and upgrades nothing. No log and
    no report is written.

.EXAMPLE
    .\Upgrade-TeamsAppInstallations.ps1
    # Upgrades every Neologik app in the catalogue.

.EXAMPLE
    .\Upgrade-TeamsAppInstallations.ps1 -AppId "00000000-0000-0000-0000-000000000000"
    # Upgrades one app, named by its manifest id.

.EXAMPLE
    .\Upgrade-TeamsAppInstallations.ps1 -WhatIf
    # A dry run.

.NOTES
    Version: v0.2.0
    Requires: PowerShell 7.4 or later
    Requires: the Microsoft Graph PowerShell modules, installed for the current user
    if they are missing
    Requires: a Global Administrator at the first run, to consent on behalf of your
    organisation
    Delegated Microsoft Graph permissions requested at sign-in:
        - AppCatalog.Read.All
        - TeamsAppInstallation.ReadWriteAndConsentForUser
        - User.Read.All
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
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
    $target = if ($AppId) { "AppIds: $($AppId -join ', ')" } else { "All Neologik apps" }
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
            Write-Log "Marking the PowerShell Gallery as a trusted repository" -Level Info
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
    'TeamsAppInstallation.ReadWriteAndConsentForUser',
    'User.Read.All'
)

$script:GraphPowerShellAppId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
$script:MicrosoftGraphAppId  = '00000003-0000-0000-c000-000000000000'

function Grant-AdminConsent {
    # This function is not called by the script. It would grant the three permissions
    # to Microsoft Graph PowerShell for the whole tenant. Consent is given by the
    # administrator at sign-in instead.
    Write-Log "Granting org-wide admin consent for required scopes..." -Level Info

    $graphPsSp = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$($script:GraphPowerShellAppId)'").value | Select-Object -First 1
    if (-not $graphPsSp) {
        Write-Log "  Creating the service principal of Microsoft Graph PowerShell in this tenant..." -Level Info
        $createBody = @{ appId = $script:GraphPowerShellAppId } | ConvertTo-Json
        $graphPsSp = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/servicePrincipals' -Body $createBody -ContentType 'application/json'
    }
    $graphSp = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$($script:MicrosoftGraphAppId)'").value | Select-Object -First 1

    $existing = (Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$($graphPsSp.id)' and resourceId eq '$($graphSp.id)' and consentType eq 'AllPrincipals'").value | Select-Object -First 1

    if ($existing) {
        $existingScopes = $existing.scope -split ' '
        $missing = $script:RequiredScopes | Where-Object { $existingScopes -notcontains $_ }
        if (-not $missing) {
            Write-Log "  Admin consent already in place - no changes needed" -Level Success
            return
        }
        $merged = (($existingScopes + $script:RequiredScopes) | Sort-Object -Unique) -join ' '
        $body = @{ scope = $merged } | ConvertTo-Json
        Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($existing.id)" -Body $body -ContentType 'application/json' | Out-Null
        Write-Log "  Existing grant updated with missing scopes" -Level Success
    } else {
        $body = @{
            clientId    = $graphPsSp.id
            consentType = 'AllPrincipals'
            principalId = $null
            resourceId  = $graphSp.id
            scope       = ($script:RequiredScopes -join ' ')
        } | ConvertTo-Json
        Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' -Body $body -ContentType 'application/json' | Out-Null
        Write-Log "  Admin consent granted org-wide" -Level Success
    }
}

function Invoke-GraphConnect {
    param([hashtable]$Params)

    if ($UseDeviceAuthentication) {
        $Params['UseDeviceAuthentication'] = $true
        Write-Host "Device-code sign-in: code will appear below - open the URL, paste, sign in." -ForegroundColor Cyan
        Write-Host "If a consent screen appears, tick 'Consent on behalf of your organization' before Accept." -ForegroundColor Yellow
    } else {
        Write-Host "A sign-in window will open. Sign in as a Global Administrator." -ForegroundColor Cyan
        Write-Host "If a consent screen appears, tick 'Consent on behalf of your organization' before Accept." -ForegroundColor Yellow
    }
    Write-Host ""

    try {
        Connect-MgGraph @Params -ErrorAction Stop
    }
    catch {
        if (-not $Params['UseDeviceAuthentication']) {
            Write-Log "Browser sign-in failed: $($_.Exception.Message). Retrying with device code..." -Level Warning
            $Params['UseDeviceAuthentication'] = $true
            Connect-MgGraph @Params -ErrorAction Stop
        } else {
            throw
        }
    }
}

function Initialize-GraphSession {
    $params = @{
        Scopes    = $script:RequiredScopes
        NoWelcome = $true
    }
    if ($TenantId) { $params['TenantId'] = $TenantId }
    else           { $params['Audience'] = 'organizations' }

    Invoke-GraphConnect -Params $params

    $ctx = Get-MgContext
    if (-not $ctx) {
        Write-Log "Sign-in did not complete" -Level Error
        exit 1
    }
    Write-Log "Signed in as $($ctx.Account) on tenant $($ctx.TenantId)" -Level Success
}

function Show-AdminConsentRequired {
    Write-Host ""
    Write-Host "Administrator consent has not been given for the permissions this script requests." -ForegroundColor Red
    Write-Host "Run the script again, sign in as a Global Administrator and select 'Consent on behalf of your organization'." -ForegroundColor Yellow
    Write-Host ""
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
            # Read the apps the organisation has uploaded, with their published versions
            $uri = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps?`$filter=distributionMethod eq 'organization'&`$expand=appDefinitions"
            $candidates = (Invoke-MgGraphRequest -Method GET -Uri $uri).value
        }
    }
    catch {
        if ($_.Exception.Message -match '403|Forbidden|insufficient privileges') {
            Write-Log "Insufficient privileges: the signed-in account does not have permission to read the app catalog." -Level Error
            Write-Host "The account you signed in with needs one of these Entra roles:" -ForegroundColor Yellow
            Write-Host "  - Cloud Application Administrator" -ForegroundColor Yellow
            Write-Host "  - Application Administrator" -ForegroundColor Yellow
            Write-Host "  - Global Administrator" -ForegroundColor Yellow
            Write-Host "Assign one of these roles to the signed-in account, then re-run." -ForegroundColor Yellow
            exit 1
        }
        throw
    }

    # Wrap in an array, so that one result behaves as several do
    $candidates = @($candidates)
    if (-not $AppId) {

        # Select the Neologik apps by text that remains when an app is renamed: the
        # Neologik name and Neologik's Microsoft partner number, in the name and the
        # descriptions of the app.
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
            Write-Log "Skipping '$($app.displayName)' - no published appDefinition" -Level Warning
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
    foreach ($user in $users) {
        $idx++
        if ($idx % 50 -eq 0) {
            Write-Host "    Checked $idx / $($users.Count)..." -ForegroundColor DarkGray
        }
        try {
            $uri = "https://graph.microsoft.com/v1.0/users/$($user.Id)/teamwork/installedApps?`$filter=teamsApp/id eq '$CatalogAppId'&`$expand=teamsApp,teamsAppDefinition"
            $r = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
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
        }
        catch {
            if ($_.Exception.Message -match '403|Forbidden|insufficient privileges') {
                Show-AdminConsentRequired
                throw "Aborted: admin consent not granted."
            }
            Write-Log "    Skipped $($user.UserPrincipalName): $($_.Exception.Message)" -Level Warning
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
            Write-Log "Insufficient privileges on the upgrade call." -Level Error
            Write-Host "The signed-in account can read the catalog but cannot upgrade installations." -ForegroundColor Yellow
            Write-Host "It is missing the TeamsAppInstallation.ReadWriteAndConsentForUser scope or an Entra role" -ForegroundColor Yellow
            Write-Host "with that consent. Assign Cloud Application Administrator (or higher) to the signed-in account." -ForegroundColor Yellow
            throw "Aborting - insufficient privileges on upgrade endpoint."
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
    Initialize-GraphSession

    $catalogApps = Find-NeologikApps

    if (-not $Force -and -not $WhatIfPreference) {
        Write-Host "`nAbout to upgrade installations for the apps listed above." -ForegroundColor Yellow
        Write-Host "This will silently update every user's installed version - no prompt is shown to them." -ForegroundColor Yellow
        Write-Host "Type " -NoNewline; Write-Host "YES" -ForegroundColor Green -NoNewline; Write-Host " to proceed, or anything else to abort: " -NoNewline
        $reply = Read-Host
        if ($reply -ne 'YES') {
            Write-Log "Stopped by the administrator at the confirmation" -Level Warning
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
        Write-Log "No installations found across $($catalogApps.Count) app(s) - nothing to do" -Level Warning
        return
    }

    $report | Export-Csv -Path $script:ReportFile -NoTypeInformation
    Write-Log "`nReport written: $script:ReportFile" -Level Success

    $summary = $report | Group-Object App, Status | Select-Object Name, @{ Name = 'Users Updated'; Expression = { $_.Count } }
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
