<#
.SYNOPSIS
    Upgrades the Neologik Teams app that each user has installed to the latest
    version in the Teams app catalogue of the tenant.

.DESCRIPTION
    The script calls Microsoft Graph as the signed-in administrator. The script works
    in three steps:
    1. The script reads the Teams apps that were uploaded to the Teams app catalogue
       of the tenant. The script selects each Teams app whose name or description
       holds the name Neologik or the Microsoft partner number of Neologik.
    2. For each selected Teams app, the script finds each user who has the Teams app
       installed.
    3. The script upgrades each installed Teams app that is older than the latest
       version in the Teams app catalogue. The user sees no question.

    The script writes a log and a report to the folder of the script. The script
    creates no directory object and no credential. The script removes nothing.

.PARAMETER AppId
    One or more manifest ids of Teams apps. With this parameter, the script upgrades
    only the Teams apps with those manifest ids. The script then makes no search for
    the Neologik Teams apps.

.PARAMETER TenantId
    The tenant to sign in to. Without this parameter, the administrator chooses the
    tenant at the sign-in.

.PARAMETER UseDeviceAuthentication
    The script signs in with a device code. Use this parameter on a workstation where
    a browser sign-in is not possible.

.PARAMETER Force
    The script starts the upgrade without the question that asks for confirmation.

.PARAMETER WhatIf
    The script shows on screen what a run would upgrade. The script upgrades nothing
    and writes no log and no report.

.EXAMPLE
    .\Upgrade-TeamsAppInstallations.ps1
    # Upgrades every Neologik Teams app in the Teams app catalogue.

.EXAMPLE
    .\Upgrade-TeamsAppInstallations.ps1 -AppId "00000000-0000-0000-0000-000000000000"
    # Upgrades one Teams app, named by the manifest id.

.EXAMPLE
    .\Upgrade-TeamsAppInstallations.ps1 -WhatIf
    # Shows what a run would upgrade and upgrades nothing.

.NOTES
    Version: v0.2.2
    Requires: PowerShell 7.4 or later
    Requires: the Microsoft Graph PowerShell modules. The script installs the modules
    for the current user when the modules are missing
    Requires: a Global Administrator at the first run, to give consent for the tenant
    Delegated Microsoft Graph permissions requested at the sign-in:
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

$script:Version = 'v0.2.2'
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
    $target = if ($AppId) { "AppIds: $($AppId -join ', ')" } else { "All Neologik Teams apps" }
    $header = @"

===============================================================
   NEOLOGIK TEAMS APP BULK UPGRADE  $script:Version
   $target
   Log: $script:LogFile
===============================================================

"@
    Write-Host $header -ForegroundColor Cyan
    Write-Log "Starting the upgrade. Scope: $target" -Level Info
}

#endregion

#region Prerequisites

function Test-PowerShellVersion {
    if ($PSVersionTable.PSVersion -lt [Version]'7.4.0') {
        Write-Log "PowerShell 7.4 or later is required. Current version: $($PSVersionTable.PSVersion)" -Level Error
        Write-Host "Install or update PowerShell from: https://learn.microsoft.com/powershell/" -ForegroundColor Yellow
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
            Write-Log "Installing $module for the current user..." -Level Info
            Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
        }
    }

    foreach ($module in $required) {
        Import-Module $module -ErrorAction Stop
    }
    Write-Log "The Microsoft Graph modules are ready" -Level Success
}

#endregion

#region Graph operations

$script:RequiredScopes = @(
    'AppCatalog.Read.All',
    'TeamsAppInstallation.ReadWriteAndConsentForUser',
    'User.Read.All'
)

function Invoke-GraphConnect {
    param([hashtable]$Params)

    if ($UseDeviceAuthentication) {
        $Params['UseDeviceAuthentication'] = $true
        Write-Host "Device code sign-in: a code appears below. Open the address, enter the code and sign in." -ForegroundColor Cyan
        Write-Host "If a consent page appears, select 'Consent on behalf of your organization', then Accept." -ForegroundColor Yellow
    } else {
        Write-Host "A sign-in window opens. Sign in as a Global Administrator." -ForegroundColor Cyan
        Write-Host "If a consent page appears, select 'Consent on behalf of your organization', then Accept." -ForegroundColor Yellow
    }
    Write-Host ""

    try {
        Connect-MgGraph @Params -ErrorAction Stop
    }
    catch {
        if (-not $Params['UseDeviceAuthentication']) {
            Write-Log "The browser sign-in failed: $($_.Exception.Message). The script now signs in with a device code..." -Level Warning
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
        Write-Log "The sign-in did not complete" -Level Error
        exit 1
    }
    Write-Log "Signed in as $($ctx.Account) on tenant $($ctx.TenantId)" -Level Success
}

function Show-AdminConsentRequired {
    Write-Host ""
    Write-Host "Administrator consent has not been given for the permissions that this script requests." -ForegroundColor Red
    Write-Host "Run the script again, sign in as a Global Administrator and select 'Consent on behalf of your organization'." -ForegroundColor Yellow
    Write-Host ""
}

function Find-NeologikApps {
    Write-Log "Searching the Teams app catalogue for Neologik Teams apps..." -Level Info

    try {
        if ($AppId) {
            $idsLower = $AppId | ForEach-Object { $_.ToLower() }
            $orClause = ($idsLower | ForEach-Object { "externalId eq '$_'" }) -join ' or '
            $uri = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps?`$filter=($orClause)&`$expand=appDefinitions"
            $candidates = (Invoke-MgGraphRequest -Method GET -Uri $uri).value
        } else {
            # Read the Teams apps in the Teams app catalogue of the tenant, with the published versions
            $uri = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps?`$filter=distributionMethod eq 'organization'&`$expand=appDefinitions"
            $candidates = (Invoke-MgGraphRequest -Method GET -Uri $uri).value
        }
    }
    catch {
        if ($_.Exception.Message -match '403|Forbidden|insufficient privileges') {
            Write-Log "Insufficient privileges: the signed-in account cannot read the Teams app catalogue." -Level Error
            Write-Host "The signed-in account needs one of these Microsoft Entra roles:" -ForegroundColor Yellow
            Write-Host "  - Cloud Application Administrator" -ForegroundColor Yellow
            Write-Host "  - Application Administrator" -ForegroundColor Yellow
            Write-Host "  - Global Administrator" -ForegroundColor Yellow
            Write-Host "Assign one of these roles to the signed-in account, then run the script again." -ForegroundColor Yellow
            exit 1
        }
        throw
    }

    # Wrap the result in an array, so that one result and several results behave alike
    $candidates = @($candidates)
    if (-not $AppId) {

        # Select the Neologik Teams apps by text that stays the same when a Teams app is
        # renamed: the name Neologik and the Microsoft partner number of Neologik. The
        # script looks in the name and in the descriptions of the Teams app.
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
        Write-Log "The Teams app catalogue holds no Neologik Teams app" -Level Error
        exit 1
    }

    $catalog = foreach ($app in $candidates) {
        $latestDef = $app.appDefinitions |
            Where-Object { $_.publishingState -eq 'published' } |
            Sort-Object createdDateTime -Descending |
            Select-Object -First 1

        if (-not $latestDef) {
            Write-Log "Skipping '$($app.displayName)': the Teams app has no published version" -Level Warning
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

    Write-Log "Neologik Teams apps found in the Teams app catalogue: $($catalog.Count)" -Level Success
    $catalog | ForEach-Object {
        Write-Log "  - $($_.DisplayName), version $($_.LatestVersion), manifest id $($_.ExternalId)" -Level Info
    }
    return $catalog
}

function Get-UsersWithInstallation {
    param([string]$CatalogAppId, [string]$DisplayName)

    Write-Log "Listing the users of the tenant for '$DisplayName'..." -Level Info
    $users = Get-MgUser -All -Property Id, UserPrincipalName, DisplayName, AccountEnabled |
        Where-Object { $_.AccountEnabled }

    $installs = [System.Collections.Generic.List[object]]::new()
    $idx = 0
    foreach ($user in $users) {
        $idx++
        if ($idx % 50 -eq 0) {
            Write-Host "    Users checked: $idx of $($users.Count)..." -ForegroundColor DarkGray
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
                throw "Stopped: administrator consent is not given."
            }
            Write-Log "    Skipped $($user.UserPrincipalName): $($_.Exception.Message)" -Level Warning
        }
    }

    Write-Log "  Installed copies of '$DisplayName' found: $($installs.Count)" -Level Success
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
            Write-Log "Insufficient privileges for the upgrade." -Level Error
            Write-Host "The signed-in account can read the Teams app catalogue but cannot upgrade an installed Teams app." -ForegroundColor Yellow
            Write-Host "The signed-in account lacks the permission TeamsAppInstallation.ReadWriteAndConsentForUser," -ForegroundColor Yellow
            Write-Host "or lacks a Microsoft Entra role. Assign the role Cloud Application Administrator, or a higher role, to the signed-in account." -ForegroundColor Yellow
            throw "Stopping: insufficient privileges for the upgrade."
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
        Write-Host "`nThe script is ready to upgrade the Teams apps listed above." -ForegroundColor Yellow
        Write-Host "The upgrade changes the installed version of each user. Microsoft Teams asks the user nothing." -ForegroundColor Yellow
        Write-Host "Type " -NoNewline; Write-Host "YES" -ForegroundColor Green -NoNewline; Write-Host " to continue, or any other text to stop: " -NoNewline
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
        Write-Log "No user has an installed copy of the selected Teams apps. The script has nothing to upgrade" -Level Warning
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
