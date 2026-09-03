<#
.SYNOPSIS
    The single Global Administrator touchpoint for a Neologik v5 migration
    window. Verifies - and where missing, applies - the directory and RBAC
    state that only a customer Global Administrator can change.

.DESCRIPTION
    Run by the customer's Global Administrator (or Privileged Role
    Administrator for the directory steps), under their own sign-in, on a
    machine with PowerShell 7.4+.

    The script is idempotent and verification-first: every action checks
    current state before writing, so on an already-compliant environment it
    is a pure verification pass and changes nothing. Run it as often as you
    like.

    Phase 'Window' (the default) - run any time BEFORE the migration window:
      1. Deployment identity Graph roles: grants the Neologik deployment
         service principal the eight Microsoft Graph application roles the
         v5 platform needs (agent identity management plus the two base
         application roles). Only a Global Administrator can grant Graph
         application roles - Application Administrator is not sufficient.
      2. Sign-in group assignment: assigns the Neologik NCE user group to
         the 'Neologik Platform Sign-in' enterprise application. From v5,
         NCE authorises purely from the sign-in token's groups claim, and
         that claim only carries groups assigned to the application -
         without this step every user is locked out of NCE after the
         upgrade. (Only the user group is assigned; the Admin User Group
         is Azure RBAC only and never grants NCE access.)
      3. Admin consent check: verifies tenant-wide admin consent exists for
         the sign-in application. If it is missing the script prints the
         consent URL for you to open and approve - consent itself stays
         interactive so you see exactly what you are approving.
      3b. Shared-mailbox grants (only with -MailboxGrantsFile): for each
         email channel registered in the Neologik Platform, grants the
         agent's channel identity Application Mail.Read / Mail.ReadWrite /
         Mail.Send in Exchange Online, scoped to that one mailbox (RBAC for
         Applications - nothing is granted in Entra ID). With
         -RemoveLegacyGrantAppIds it also removes the retired email
         monitor identity's Exchange assignments. Needs the Exchange
         Online PowerShell module and an Exchange Administrator or Global
         Administrator sign-in.

    Phase 'PostWindow' - run ONLY after Neologik confirms the migration is
    verified (on an already-hardened environment the only change it makes
    is the new 'Cost Management Contributor' grant below):
      4. Permission reduction: first ensures the deployment identity holds
         the narrow resource-group-scoped role set and the two retained
         subscription-scoped roles (read-only Reader for SKU/quota
         pre-flight; Cost Management Contributor so the deployment
         pipeline can keep the cost report emails current - cost
         configuration only), then removes its legacy broad grants - the
         Application Administrator directory role and the
         subscription-scoped Contributor and User Access Administrator
         assignments. Narrow roles are applied before broad ones are
         removed so deployments never lose access in between.

.PARAMETER ConfigurationFile
    Path to the Neologik_..._Configuration_....json file produced by
    Install-NeologikEnvironment.ps1 at onboarding. Preferred input - it
    already carries every value the script needs.

.PARAMETER Phase
    'Window' (default) or 'PostWindow'. See DESCRIPTION.

.PARAMETER TenantId
    Entra tenant id of the environment's home tenant. Required only when no
    ConfigurationFile is given.

.PARAMETER DeploySpClientId
    Application (client) id of the 'Neologik GitHub Service Connection'
    app registration. Required only when no ConfigurationFile is given.

.PARAMETER SignInAppClientId
    Application (client) id of the 'Neologik Platform Sign-in' app
    registration (older environments may still show it as 'Neologik NCE
    Auth' or 'Neologik Admin Auth' - it is the same registration).
    Required only when no ConfigurationFile is given.

.PARAMETER NceUserGroupId
    Object id of the Neologik NCE user group. Required only when no
    ConfigurationFile is given.

.PARAMETER MailboxGrantsFile
    Path to the JSON file Neologik exports from the platform's email
    channel registrations: an array of objects with IdentityAppId,
    IdentityObjectId, Mailbox and DisplayName. Optional; when given, step
    3b applies the scoped Exchange Online grants.

.PARAMETER RemoveLegacyGrantAppIds
    Application ids of retired identities whose Exchange Online mailbox
    assignments should be removed (the email monitor's identity at its
    migration window). Optional; used with or without -MailboxGrantsFile.

.PARAMETER SubscriptionId
    Azure subscription id. Required for -Phase PostWindow when no
    ConfigurationFile is given.

.PARAMETER ResourceGroupName
    Neologik resource group name. Required for -Phase PostWindow when no
    ConfigurationFile is given.

.EXAMPLE
    ./Update-NeologikEnvironmentAccess.ps1 -ConfigurationFile ./Neologik_abcprd_Configuration_20250101_120000.json

.EXAMPLE
    ./Update-NeologikEnvironmentAccess.ps1 -ConfigurationFile ./Neologik_abcprd_Configuration_20250101_120000.json -Phase PostWindow
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigurationFile,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Window', 'PostWindow')]
    [string]$Phase = 'Window',

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$DeploySpClientId,

    [Parameter(Mandatory = $false)]
    [string]$SignInAppClientId,

    [Parameter(Mandatory = $false)]
    [string]$NceUserGroupId,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$MailboxGrantsFile,

    [Parameter(Mandatory = $false)]
    [string[]]$RemoveLegacyGrantAppIds
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The eight Microsoft Graph application roles the deployment identity needs.
# Canonical inventory (names, ids, where each is used):
# neo-bot-service/docs/NEOLOGIK_PLATFORM_DEPLOYMENT_SP_PERMISSIONS.md.
# Matched by role value against the Graph service principal at runtime.
$script:RequiredGraphRoles = @(
    'Application.Read.All',
    'Application.ReadWrite.OwnedBy',
    'AgentIdentityBlueprint.Create',
    'AgentIdentityBlueprint.AddRemoveCreds.All',
    'AgentIdentityBlueprint.UpdateAuthProperties.All',
    'AgentIdentityBlueprintPrincipal.Create',
    'AgentIdentity.Create.All',
    'AgentIdUser.ReadWrite.All'
)

# The narrow resource-group role set that replaces the legacy broad grants
# (issue #774 least-privilege model). Must match Install-NeologikEnvironment.ps1.
$script:RequiredRgRoles = @(
    'Contributor',
    'Key Vault Certificates Officer',
    'Key Vault Secrets Officer',
    'Storage Blob Data Contributor',
    'Azure Kubernetes Service RBAC Cluster Admin',
    'Monitoring Contributor',
    'Role Based Access Control Administrator'
)

# The two subscription-scoped roles the deployment identity keeps under the
# least-privilege model. Must match Install-NeologikEnvironment.ps1.
# 'Reader': the infrastructure deploy's SKU/quota pre-flight reads
# subscription/location-level usage APIs that RG scope does not grant.
# 'Cost Management Contributor': lets the deployment pipeline keep the
# subscription-scoped cost report emails current (project#1215) - cost
# configuration only, no control over resources.
$script:RequiredSubRoles = @(
    'Reader',
    'Cost Management Contributor'
)

$script:GraphSpAppId = '00000003-0000-0000-c000-000000000000'
$script:AppAdminRoleTemplateId = '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3'
$script:Summary = @()

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    $stamp = Get-Date -Format 'HH:mm:ss'
    $colour = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        default   { 'Gray' }
    }
    Write-Host "[$stamp] $Message" -ForegroundColor $colour
}

function Add-Summary {
    param([string]$Item, [string]$Result)
    $script:Summary += [pscustomobject]@{ Item = $Item; Result = $Result }
}


# ----- shared-mailbox grants (email channels, project#990) ---------------------

function Grant-NeologikMailboxAccess {
    <#
    Exchange Online RBAC for Applications, scoped to ONE mailbox: the channel
    pod identity's Exchange service principal pointer, a management scope
    whose recipient filter names the mailbox, and Application Mail.Read /
    Mail.ReadWrite / Mail.Send assignments on that scope. Idempotent, and
    Exchange refuses a second scope with the same recipient filter, so an
    existing scope naming the mailbox (for example the retired email
    monitor's) is reused whatever its name.
    #>
    param(
        [Parameter(Mandatory)][string]$IdentityAppId,
        [Parameter(Mandatory)][string]$IdentityObjectId,
        [Parameter(Mandatory)][string]$Mailbox,
        [Parameter(Mandatory)][string]$DisplayName
    )
    $label = "Mailbox grant: $Mailbox -> $DisplayName"
    $sp = Get-ServicePrincipal -Identity $IdentityAppId -ErrorAction SilentlyContinue
    if (-not $sp) {
        $sp = New-ServicePrincipal -AppId $IdentityAppId -ObjectId $IdentityObjectId -DisplayName $DisplayName
        Write-Log "  service principal pointer created: $DisplayName" -Level Success
    }
    $scopeName = "Scope-$DisplayName"
    $scope = Get-ManagementScope -Identity $scopeName -ErrorAction SilentlyContinue
    if (-not $scope) {
        $scope = Get-ManagementScope | Where-Object { $_.RecipientFilter -like "*$Mailbox*" } | Select-Object -First 1
        if ($scope) { Write-Log "  reusing management scope '$($scope.Name)' (same recipient filter)" -Level Info }
    }
    if (-not $scope) {
        $scope = New-ManagementScope -Name $scopeName -RecipientRestrictionFilter "PrimarySmtpAddress -eq '$Mailbox'" -ErrorAction Stop
        Write-Log "  management scope created: $scopeName" -Level Success
    }
    $granted = 0
    foreach ($role in @(
            @{ Suffix = 'MailRead';      Role = 'Application Mail.Read' },
            @{ Suffix = 'MailReadWrite'; Role = 'Application Mail.ReadWrite' },
            @{ Suffix = 'MailSend';      Role = 'Application Mail.Send' })) {
        $assignmentName = "Assignment-$DisplayName-$($role.Suffix)"
        if (Get-ManagementRoleAssignment -Identity $assignmentName -ErrorAction SilentlyContinue) {
            continue
        }
        New-ManagementRoleAssignment -Name $assignmentName -App $IdentityObjectId -Role $role.Role `
            -CustomResourceScope $scope.Name -ErrorAction Stop | Out-Null
        $granted++
    }
    $inScope = @(Test-ServicePrincipalAuthorization -Identity $IdentityObjectId -Resource $Mailbox |
        Where-Object { $_.InScope })
    if ($inScope.Count -ge 3) {
        Write-Log "  $Mailbox -> $DisplayName - in scope for $($inScope.Count) role(s)" -Level Success
        Add-Summary $label $(if ($granted -gt 0) { "Granted ($granted role(s) added)" } else { 'Already granted' })
    }
    else {
        Write-Log "  $Mailbox -> $DisplayName - $granted role(s) added; Exchange reports $($inScope.Count) in scope (propagation can take up to two hours - re-run to confirm)" -Level Warning
        Add-Summary $label 'PENDING - re-run to confirm InScope'
    }
}

function Remove-NeologikMailboxAccess {
    <#
    Removes a retired identity's Exchange role assignments and service
    principal pointer (the email monitor's identity, replaced by the
    channel pod identity at the migration window). The management scope is
    left in place: the replacement grant reuses it.
    #>
    param([Parameter(Mandatory)][string]$LegacyAppId)
    $label = "Legacy mailbox grant: $LegacyAppId"
    $sp = Get-ServicePrincipal -Identity $LegacyAppId -ErrorAction SilentlyContinue
    if (-not $sp) {
        Write-Log "  legacy identity $LegacyAppId - no Exchange service principal (nothing to remove)" -Level Success
        Add-Summary $label 'Not present'
        return
    }
    $assignments = @(Get-ManagementRoleAssignment -RoleAssignee $sp.Identity -ErrorAction SilentlyContinue)
    foreach ($assignment in $assignments) {
        Remove-ManagementRoleAssignment -Identity $assignment.Name -Confirm:$false -ErrorAction Stop
    }
    Remove-ServicePrincipal -Identity $sp.Identity -Confirm:$false -ErrorAction Stop
    Write-Log "  legacy identity $LegacyAppId - $($assignments.Count) assignment(s) and the pointer REMOVED" -Level Success
    Add-Summary $label "Removed ($($assignments.Count) assignment(s))"
}

# ----- input resolution -------------------------------------------------------

if ($PSVersionTable.PSVersion -lt [version]'7.4') {
    throw "PowerShell 7.4 or later is required (current: $($PSVersionTable.PSVersion))."
}

if ($ConfigurationFile) {
    if (-not (Test-Path $ConfigurationFile)) {
        throw "Configuration file not found: $ConfigurationFile"
    }
    $config = Get-Content $ConfigurationFile -Raw | ConvertFrom-Json
    if (-not $TenantId) { $TenantId = $config.TenantId }
    if (-not $SubscriptionId) { $SubscriptionId = $config.SubscriptionId }
    if (-not $ResourceGroupName) { $ResourceGroupName = $config.ResourceGroupName }
    if (-not $DeploySpClientId) { $DeploySpClientId = $config.AppRegistration.ClientId }
    if (-not $SignInAppClientId -and $config.PSObject.Properties['NceAuthApp'] -and $config.NceAuthApp) {
        $SignInAppClientId = $config.NceAuthApp.ClientId
    }
    if (-not $NceUserGroupId -and $config.SecurityGroups) {
        $nceGroup = @($config.SecurityGroups | Where-Object {
                $_.Name -match 'NCE User Group|Harness User Group'
            }) | Select-Object -First 1
        if ($nceGroup) { $NceUserGroupId = $nceGroup.Id }
    }
    Write-Log "Configuration loaded: $($config.OrganizationName) ($($config.SolutionShortName))" -Level Info
}

foreach ($required in @(
        @{ Name = 'TenantId'; Value = $TenantId },
        @{ Name = 'DeploySpClientId'; Value = $DeploySpClientId })) {
    if (-not $required.Value) {
        throw "$($required.Name) could not be resolved - pass it explicitly or supply -ConfigurationFile."
    }
}
if ($Phase -eq 'PostWindow' -and (-not $SubscriptionId -or -not $ResourceGroupName)) {
    throw 'PostWindow needs SubscriptionId and ResourceGroupName - pass them explicitly or supply -ConfigurationFile.'
}

$script:MailboxGrants = @()
if ($MailboxGrantsFile) {
    if (-not (Test-Path $MailboxGrantsFile)) {
        throw "Mailbox grants file not found: $MailboxGrantsFile"
    }
    $guidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    foreach ($entry in @(Get-Content $MailboxGrantsFile -Raw | ConvertFrom-Json)) {
        foreach ($field in @('IdentityAppId', 'IdentityObjectId', 'Mailbox', 'DisplayName')) {
            if (-not $entry.PSObject.Properties[$field] -or -not $entry.$field) {
                throw "Mailbox grants file: every entry needs $field."
            }
        }
        if ($entry.IdentityAppId -notmatch $guidPattern -or $entry.IdentityObjectId -notmatch $guidPattern) {
            throw "Mailbox grants file: IdentityAppId and IdentityObjectId must be GUIDs ($($entry.DisplayName))."
        }
        if ($entry.Mailbox -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
            throw "Mailbox grants file: '$($entry.Mailbox)' is not a mailbox address."
        }
        $script:MailboxGrants += $entry
    }
    Write-Log "Mailbox grants loaded: $($script:MailboxGrants.Count) email channel(s)" -Level Info
}

Write-Host ''
Write-Host '=============================================================' -ForegroundColor Cyan
Write-Host " Neologik environment access - phase: $Phase" -ForegroundColor Cyan
Write-Host '=============================================================' -ForegroundColor Cyan
Write-Host "  Tenant:              $TenantId"
Write-Host "  Deployment identity: $DeploySpClientId"
if ($SignInAppClientId) { Write-Host "  Sign-in app:         $SignInAppClientId" }
if ($NceUserGroupId) { Write-Host "  NCE user group:      $NceUserGroupId" }
if ($script:MailboxGrants.Count -gt 0) { Write-Host "  Mailbox grants:      $($script:MailboxGrants.Count)" }
if ($RemoveLegacyGrantAppIds) { Write-Host "  Legacy grants to remove: $($RemoveLegacyGrantAppIds -join ', ')" }
if ($Phase -eq 'PostWindow') {
    Write-Host "  Subscription:        $SubscriptionId"
    Write-Host "  Resource group:      $ResourceGroupName"
}
Write-Host ''

# ----- modules + sign-in ------------------------------------------------------

foreach ($module in @('Microsoft.Graph.Applications', 'Microsoft.Graph.Groups', 'Microsoft.Graph.Identity.DirectoryManagement')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Log "Installing module $module (first run only)..." -Level Info
        Install-Module $module -Scope CurrentUser -Force -AllowClobber
    }
}

$graphScopes = @('Application.Read.All', 'AppRoleAssignment.ReadWrite.All', 'DelegatedPermissionGrant.Read.All')
if ($Phase -eq 'PostWindow') {
    $graphScopes += 'RoleManagement.ReadWrite.Directory'
}
Write-Log 'Signing in to Microsoft Graph (device code - use your Global Administrator account)...' -Level Info
Connect-MgGraph -TenantId $TenantId -Scopes $graphScopes -UseDeviceCode -NoWelcome

$deploySp = Get-MgServicePrincipal -Filter "appId eq '$DeploySpClientId'"
if (-not $deploySp) {
    throw "Deployment service principal not found for client id $DeploySpClientId in tenant $TenantId."
}
Write-Log "Deployment identity: '$($deploySp.DisplayName)'" -Level Info

if ($Phase -eq 'Window') {

    # ----- 1. deployment identity Graph roles ---------------------------------
    Write-Log 'Step 1/3: deployment identity Graph roles' -Level Info
    $graphSp = Get-MgServicePrincipal -Filter "appId eq '$script:GraphSpAppId'"
    $existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $deploySp.Id -All |
        Where-Object { $_.ResourceId -eq $graphSp.Id }
    $granted = 0
    foreach ($roleName in $script:RequiredGraphRoles) {
        $role = $graphSp.AppRoles | Where-Object { $_.Value -eq $roleName }
        if (-not $role) {
            Write-Log "  role '$roleName' not published by Microsoft Graph in this cloud - report this to Neologik" -Level Warning
            Add-Summary "Graph role: $roleName" 'NOT FOUND - report'
            continue
        }
        if ($existing | Where-Object { $_.AppRoleId -eq $role.Id }) {
            Write-Log "  $roleName - already granted" -Level Success
            Add-Summary "Graph role: $roleName" 'Already granted'
        }
        else {
            New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $deploySp.Id `
                -PrincipalId $deploySp.Id -ResourceId $graphSp.Id -AppRoleId $role.Id | Out-Null
            Write-Log "  $roleName - GRANTED" -Level Success
            Add-Summary "Graph role: $roleName" 'Granted'
            $granted++
        }
    }
    Write-Log "Graph roles complete ($granted newly granted)" -Level Info

    # ----- 2. sign-in group assignment ----------------------------------------
    Write-Log 'Step 2/3: NCE user group assignment to the sign-in application' -Level Info
    if (-not $SignInAppClientId -or -not $NceUserGroupId) {
        Write-Log '  sign-in app id or NCE user group id not available - SKIPPED. On pre-v5-onboarded environments supply both (the migration email lists them).' -Level Warning
        Add-Summary 'NCE group assignment' 'SKIPPED - ids not supplied'
    }
    else {
        $signInSp = Get-MgServicePrincipal -Filter "appId eq '$SignInAppClientId'"
        if (-not $signInSp) {
            throw "Sign-in application service principal not found for client id $SignInAppClientId."
        }
        Write-Log "  sign-in application: '$($signInSp.DisplayName)'" -Level Info
        $assignments = Get-MgGroupAppRoleAssignment -GroupId $NceUserGroupId -All |
            Where-Object { $_.ResourceId -eq $signInSp.Id }
        if ($assignments) {
            Write-Log '  NCE user group - already assigned' -Level Success
            Add-Summary 'NCE group assignment' 'Already assigned'
        }
        else {
            New-MgGroupAppRoleAssignment -GroupId $NceUserGroupId `
                -PrincipalId $NceUserGroupId -ResourceId $signInSp.Id `
                -AppRoleId '00000000-0000-0000-0000-000000000000' | Out-Null
            Write-Log '  NCE user group - ASSIGNED (sign-in tokens now carry the groups claim)' -Level Success
            Add-Summary 'NCE group assignment' 'Assigned'
        }
        $group = Get-MgGroup -GroupId $NceUserGroupId
        $memberCount = (Get-MgGroupMember -GroupId $NceUserGroupId -All | Measure-Object).Count
        if ($memberCount -eq 0) {
            Write-Log "  WARNING: group '$($group.DisplayName)' has no members - users must be DIRECT members to sign in (nested groups do not count)" -Level Warning
        }
        else {
            Write-Log "  group '$($group.DisplayName)' has $memberCount direct member(s)" -Level Info
        }

        # ----- 3. admin consent check -----------------------------------------
        Write-Log 'Step 3/3: admin consent for the sign-in application' -Level Info
        $grants = Get-MgServicePrincipalOauth2PermissionGrant -ServicePrincipalId $signInSp.Id -All |
            Where-Object { $_.ConsentType -eq 'AllPrincipals' }
        if ($grants) {
            Write-Log '  tenant-wide admin consent - present' -Level Success
            Add-Summary 'Admin consent' 'Present'
        }
        else {
            $consentUrl = "https://login.microsoftonline.com/$TenantId/adminconsent?client_id=$SignInAppClientId"
            Write-Log '  tenant-wide admin consent NOT found. Open this URL in a browser, sign in as Global Administrator and approve:' -Level Warning
            Write-Host ''
            Write-Host "    $consentUrl" -ForegroundColor Cyan
            Write-Host ''
            Write-Log '  then re-run this script to confirm.' -Level Warning
            Add-Summary 'Admin consent' 'MISSING - consent URL printed'
        }
    }

    # ----- 3b. shared-mailbox grants for email channels (project#990) ---------
    if ($script:MailboxGrants.Count -gt 0 -or $RemoveLegacyGrantAppIds) {
        Write-Log 'Step 3b: Exchange Online mailbox grants for email channels' -Level Info
        if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
            Write-Log 'Installing module ExchangeOnlineManagement (first run only)...' -Level Info
            Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force -AllowClobber
        }
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        Write-Log '  Signing in to Exchange Online (device code - the same Global Administrator account)...' -Level Info
        Connect-ExchangeOnline -Device -ShowBanner:$false
        if ((Get-OrganizationConfig).IsDehydrated) {
            Write-Log '  Enabling organisation customisation (one-off; 60 s propagation)...' -Level Info
            Enable-OrganizationCustomization
            Start-Sleep -Seconds 60
        }
        foreach ($grant in $script:MailboxGrants) {
            Grant-NeologikMailboxAccess -IdentityAppId $grant.IdentityAppId -IdentityObjectId $grant.IdentityObjectId `
                -Mailbox $grant.Mailbox -DisplayName $grant.DisplayName
        }
        foreach ($legacyAppId in @($RemoveLegacyGrantAppIds | Where-Object { $_ })) {
            Remove-NeologikMailboxAccess -LegacyAppId $legacyAppId
        }
        Disconnect-ExchangeOnline -Confirm:$false | Out-Null
    }
}
else {

    # ----- 4. PostWindow: permission reduction --------------------------------
    Write-Log 'PostWindow: reducing the deployment identity to the resource-group-scoped model' -Level Info
    Write-Log 'Only proceed if Neologik has confirmed the migration is verified.' -Level Warning

    foreach ($module in @('Az.Accounts', 'Az.Resources')) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Log "Installing module $module (first run only)..." -Level Info
            Install-Module $module -Scope CurrentUser -Force -AllowClobber
        }
    }
    Write-Log 'Signing in to Azure (device code - same administrator account)...' -Level Info
    $connectParams = @{ Tenant = $TenantId; Subscription = $SubscriptionId; UseDeviceAuthentication = $true }
    # Azure mandatory MFA (ARM-layer): request the 'p1' authentication-context claim so the
    # role-assignment writes below are not rejected with a claims-challenge error.
    # Decodes to {"access_token":{"acrs":{"essential":true,"values":["p1"]}}}; needs Az.Accounts >= 5.2.0.
    if ((Get-Command Connect-AzAccount).Parameters.ContainsKey('ClaimsChallenge')) {
        $connectParams['ClaimsChallenge'] = 'eyJhY2Nlc3NfdG9rZW4iOnsiYWNycyI6eyJlc3NlbnRpYWwiOnRydWUsInZhbHVlcyI6WyJwMSJdfX19'
    }
    Connect-AzAccount @connectParams | Out-Null

    $rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
    $subScope = "/subscriptions/$SubscriptionId"

    # 4a. narrow role set FIRST - pipelines must never lose access in between.
    foreach ($roleName in $script:RequiredRgRoles) {
        $assignment = Get-AzRoleAssignment -ObjectId $deploySp.Id -RoleDefinitionName $roleName -Scope $rgScope -ErrorAction SilentlyContinue |
            Where-Object { $_.Scope -eq $rgScope }
        if ($assignment) {
            Write-Log "  RG role '$roleName' - already in place" -Level Success
            Add-Summary "RG role: $roleName" 'Already in place'
        }
        else {
            New-AzRoleAssignment -ObjectId $deploySp.Id -RoleDefinitionName $roleName -Scope $rgScope | Out-Null
            Write-Log "  RG role '$roleName' - CREATED" -Level Success
            Add-Summary "RG role: $roleName" 'Created'
        }
    }

    # 4a2. ensure the retained subscription-scoped roles (still before any
    # removal - narrow before broad). 'Cost Management Contributor' is new at
    # v5 (project#1215): on an already-hardened environment this is the one
    # assignment this phase creates.
    foreach ($roleName in $script:RequiredSubRoles) {
        $assignment = Get-AzRoleAssignment -ObjectId $deploySp.Id -RoleDefinitionName $roleName -Scope $subScope -ErrorAction SilentlyContinue |
            Where-Object { $_.Scope -eq $subScope }
        if ($assignment) {
            Write-Log "  subscription role '$roleName' - already in place" -Level Success
            Add-Summary "Sub role: $roleName" 'Already in place'
        }
        else {
            New-AzRoleAssignment -ObjectId $deploySp.Id -RoleDefinitionName $roleName -Scope $subScope | Out-Null
            Write-Log "  subscription role '$roleName' - CREATED" -Level Success
            Add-Summary "Sub role: $roleName" 'Created'
        }
    }

    # 4b. remove legacy subscription-scoped assignments.
    foreach ($roleName in @('Contributor', 'User Access Administrator')) {
        $assignment = Get-AzRoleAssignment -ObjectId $deploySp.Id -RoleDefinitionName $roleName -Scope $subScope -ErrorAction SilentlyContinue |
            Where-Object { $_.Scope -eq $subScope }
        if ($assignment) {
            Remove-AzRoleAssignment -ObjectId $deploySp.Id -RoleDefinitionName $roleName -Scope $subScope | Out-Null
            Write-Log "  subscription role '$roleName' - REMOVED" -Level Success
            Add-Summary "Legacy sub role: $roleName" 'Removed'
        }
        else {
            Write-Log "  subscription role '$roleName' - not present (nothing to remove)" -Level Success
            Add-Summary "Legacy sub role: $roleName" 'Not present'
        }
    }

    # 4c. remove the Application Administrator directory role membership.
    $appAdminRole = Get-MgDirectoryRole -Filter "roleTemplateId eq '$script:AppAdminRoleTemplateId'" -ErrorAction SilentlyContinue
    $isMember = $false
    if ($appAdminRole) {
        $isMember = [bool](Get-MgDirectoryRoleMember -DirectoryRoleId $appAdminRole.Id -All |
                Where-Object { $_.Id -eq $deploySp.Id })
    }
    if ($isMember) {
        Remove-MgDirectoryRoleMemberDirectoryObjectByRef -DirectoryRoleId $appAdminRole.Id -DirectoryObjectId $deploySp.Id
        Write-Log '  Application Administrator directory role - REMOVED' -Level Success
        Add-Summary 'Application Administrator role' 'Removed'
    }
    else {
        Write-Log '  Application Administrator directory role - not held (nothing to remove)' -Level Success
        Add-Summary 'Application Administrator role' 'Not held'
    }
}

# ----- summary ----------------------------------------------------------------

Write-Host ''
Write-Host '============================ SUMMARY ============================' -ForegroundColor Cyan
$script:Summary | Format-Table -AutoSize | Out-String | Write-Host
$attention = @($script:Summary | Where-Object { $_.Result -match 'MISSING|SKIPPED|NOT FOUND|PENDING' })
if ($attention.Count -gt 0) {
    Write-Log "$($attention.Count) item(s) need attention - see the summary above." -Level Warning
    exit 1
}
Write-Log "Phase '$Phase' complete - environment access is in the expected state." -Level Success
exit 0
