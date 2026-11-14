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
    Version: v0.2.3
    Requires: PowerShell 7.4 or later
    Requires: the Microsoft Graph PowerShell modules. The script installs the modules
    for the current user when the modules are missing
    Signature check: before the script loads a module that the script installed, the
    script checks the signature of each file of the module
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

$script:Version = 'v0.2.3'
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

        # Check the signature of each file that the download brought, before the script imports any module.
        Assert-NeologikModuleSignature -Modules @($missing | ForEach-Object { @{ Name = $_; MinVersion = '' } })
    }

    foreach ($module in $required) {
        Import-Module $module -ErrorAction Stop
    }
    Write-Log "The Microsoft Graph modules are ready" -Level Success
}

# The file types that the signature check of a module reads. Microsoft Corporation publishes each
# module that the script installs, and signs each script file of the module. A module also holds
# libraries that other publishers sign, for example Json.NET. A library needs a valid signature of
# any publisher.
$script:ModuleScriptExtensions = @('.ps1', '.psm1', '.psd1', '.ps1xml', '.cdxml')
$script:ModuleLibraryExtensions = @('.dll', '.exe')

function Get-NeologikSignatureProblem {
    <#
    .SYNOPSIS
        Checks the Authenticode signature of one file. Returns an empty string when the
        file passes the check. Otherwise returns the reason.
    .DESCRIPTION
        A file passes when Windows reports a valid signature. With -MicrosoftOnly, the
        certificate that signed the file must also name the organisation Microsoft
        Corporation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$MicrosoftOnly
    )

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    switch ([string]$signature.Status) {
        'Valid' { }
        'NotSigned' { return 'the file has no signature' }
        'HashMismatch' { return 'the file changed after the publisher signed the file' }
        default { return "Windows reports the signature status $($signature.Status)" }
    }
    $subject = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
    if ($MicrosoftOnly -and $subject -notmatch '(^|,)\s*O=Microsoft Corporation\s*(,|$)') {
        return "the signer is not Microsoft Corporation. The certificate names $subject"
    }
    return ''
}

function Test-NeologikReferenceAssembly {
    <#
    .SYNOPSIS
        Returns $true when a library is a reference assembly. .NET refuses to run the code
        of a reference assembly. The function reads the metadata of the file and runs
        nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $stream = $null
    $peReader = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $peReader = [System.Reflection.PortableExecutable.PEReader]::new($stream)
        if (-not $peReader.HasMetadata) { return $false }
        $reader = [System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($peReader)
        if (-not $reader.IsAssembly) { return $false }
        foreach ($handle in $reader.GetAssemblyDefinition().GetCustomAttributes()) {
            $attribute = $reader.GetCustomAttribute($handle)
            if ($attribute.Constructor.Kind -ne [System.Reflection.Metadata.HandleKind]::MemberReference) { continue }
            $constructor = $reader.GetMemberReference([System.Reflection.Metadata.MemberReferenceHandle]$attribute.Constructor)
            if ($constructor.Parent.Kind -ne [System.Reflection.Metadata.HandleKind]::TypeReference) { continue }
            $type = $reader.GetTypeReference([System.Reflection.Metadata.TypeReferenceHandle]$constructor.Parent)
            if ($reader.GetString($type.Namespace) -eq 'System.Runtime.CompilerServices' -and $reader.GetString($type.Name) -eq 'ReferenceAssemblyAttribute') {
                return $true
            }
        }
        return $false
    }
    catch {
        # A file that is not a .NET library counts as no reference assembly. So does a file that this version of PowerShell cannot read.
        return $false
    }
    finally {
        if ($peReader) { $peReader.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
}

function Get-NeologikRequiredModuleList {
    <#
    .SYNOPSIS
        Returns each entry of RequiredModules in a module manifest. The function parses
        the manifest and reads only the value of RequiredModules, as data. The function
        can therefore read a manifest whose other values depend on the edition of
        PowerShell. The function runs nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "the manifest does not parse: $(@($errors)[0].Message)"
    }
    $table = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $false)
    if (-not $table) {
        throw 'the manifest holds no table of values'
    }
    foreach ($pair in $table.KeyValuePairs) {
        if ([string]$pair.Item1.SafeGetValue() -ne 'RequiredModules') { continue }
        $value = if ($pair.Item2 -is [System.Management.Automation.Language.PipelineBaseAst]) { $pair.Item2.GetPureExpression() } else { $null }
        if (-not $value) {
            throw 'the value of RequiredModules is not data'
        }
        return @($value.SafeGetValue() | Where-Object { $_ })
    }
    return @()
}

function Get-NeologikModuleSignatureProblem {
    <#
    .SYNOPSIS
        Checks the Authenticode signature of each script file and each library of one
        installed module. Returns one line for each file that fails the check.
    .DESCRIPTION
        Each script file must have a valid signature of Microsoft Corporation. Each
        library must have a valid signature of any publisher. A reference assembly with
        no signature passes, because .NET refuses to run the code of a reference
        assembly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$ModuleBase
    )

    $extensions = $script:ModuleScriptExtensions + $script:ModuleLibraryExtensions
    $files = @(Get-ChildItem -LiteralPath $ModuleBase -Recurse -File -ErrorAction Stop |
        Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() })
    $problems = @()

    foreach ($file in $files) {
        $isLibrary = $script:ModuleLibraryExtensions -contains $file.Extension.ToLowerInvariant()
        $problem = Get-NeologikSignatureProblem -Path $file.FullName -MicrosoftOnly:(-not $isLibrary)
        if (-not $problem) { continue }

        # .NET refuses to run the code of a reference assembly, so a reference assembly with no signature passes.
        if ($isLibrary -and
            [string](Get-AuthenticodeSignature -LiteralPath $file.FullName).Status -eq 'NotSigned' -and
            (Test-NeologikReferenceAssembly -Path $file.FullName)) {
            Write-Log "The library $($file.FullName) of the module $Name $Version is a reference assembly with no signature. .NET runs no code of a reference assembly" -Level Info
            continue
        }

        $problems += "the module $Name $Version, file $($file.FullName): $problem"
    }
    return $problems
}

function Find-NeologikInstalledModule {
    <#
    .SYNOPSIS
        Returns the installed module at a required version, or the newest installed
        version at or above a minimum version. Returns nothing when no installed version
        matches.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$MinimumVersion,

        [Parameter(Mandatory = $false)]
        [string]$RequiredVersion
    )

    $modules = @(Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue)
    if ($RequiredVersion) {
        $modules = @($modules | Where-Object { $_.Version -eq [Version]$RequiredVersion })
    }
    elseif ($MinimumVersion) {
        $modules = @($modules | Where-Object { $_.Version -ge [Version]$MinimumVersion })
    }
    return $modules | Sort-Object Version -Descending | Select-Object -First 1
}

function Assert-NeologikModuleSignature {
    <#
    .SYNOPSIS
        Checks the signature of each file of the modules that the script installed, before
        the script imports any module. Stops the run when a file fails the check.
    .DESCRIPTION
        The function checks each module that the script installed, at the version that
        the script uses. The function also checks each module that the manifest of such a
        module requires, at the version that the manifest names. When a file fails the
        check, the function removes each module that -Modules names, which the script
        installed in this run. The next run then downloads and checks each module again.
        The function then stops the run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Modules
    )

    Write-Log "Checking the signature of each file of the installed modules..." -Level Info
    $problems = @()
    $installed = @()
    $checked = @{}
    $queue = [System.Collections.Generic.Queue[object]]::new()

    foreach ($module in $Modules) {
        $found = Find-NeologikInstalledModule -Name $module.Name -MinimumVersion $module.MinVersion
        if ($found) {
            $installed += $found
            $queue.Enqueue($found)
        }
        else {
            $problems += "the module $($module.Name), which is not installed after the download"
        }
    }

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if ($checked.ContainsKey($current.ModuleBase)) { continue }
        $checked[$current.ModuleBase] = $true
        $problems += @(Get-NeologikModuleSignatureProblem -Name $current.Name -Version ([string]$current.Version) -ModuleBase $current.ModuleBase)

        # Each module that the manifest requires. The script reads the manifest as data and runs nothing.
        $manifestPath = Join-Path $current.ModuleBase "$($current.Name).psd1"
        if (-not (Test-Path -LiteralPath $manifestPath)) { continue }
        try {
            $requiredModules = @(Get-NeologikRequiredModuleList -Path $manifestPath)
        }
        catch {
            $problems += "the module $($current.Name) $($current.Version), whose manifest the script cannot read: $($_.Exception.Message)"
            continue
        }
        foreach ($required in $requiredModules) {
            $spec = if ($required -is [hashtable]) { $required } else { @{ ModuleName = [string]$required } }
            $requiredModule = Find-NeologikInstalledModule -Name $spec['ModuleName'] -RequiredVersion $spec['RequiredVersion'] -MinimumVersion $spec['ModuleVersion']
            if ($requiredModule) {
                $queue.Enqueue($requiredModule)
            }
            else {
                Write-Log "The module $($spec['ModuleName']), which the module $($current.Name) requires, is not installed. The script checks no file of that module" -Level Warning
            }
        }
    }

    if ($problems.Count -eq 0) {
        Write-Log "Each file of the installed modules has a valid signature" -Level Success
        return
    }

    foreach ($problem in $problems) {
        Write-Log "The signature check failed for $problem" -Level Error
    }
    foreach ($module in $installed) {
        try {
            Remove-Item -LiteralPath $module.ModuleBase -Recurse -Force -ErrorAction Stop
            Write-Log "Removed the module $($module.Name) $($module.Version), which the script installed in this run" -Level Warning
        }
        catch {
            Write-Log "The script could not remove the folder $($module.ModuleBase). Delete the folder before the next run: $($_.Exception.Message)" -Level Warning
        }
    }
    throw "A PowerShell module failed the signature check. The script imported no module and stops. The script removed each module that the script installed in this run. The log names each file that failed the check. Run the script again later. When the check fails again, email the log to support@neologik.ai."
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
