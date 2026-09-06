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
      1. Least-privilege Graph model (project#2144):
         a. Agent identity blueprint: ensures 'Neologik Agent Blueprint -
            <key> - <short-name>' and its principal exist (created here if
            absent, adopted if the pipeline created it), that the
            deployment identity owns both, that the principal holds
            AgentIdUser.ReadWrite.IdentityParentedBy, and that the GitHub
            OIDC federated credentials the deployment pipeline uses to act
            AS the blueprint are present.
         b. Deployment identity Graph roles: ensures the two retained
            application roles (Application.ReadWrite.OwnedBy,
            AgentIdentityBlueprint.AddRemoveCreds.All), then REMOVES the six
            retired tenant-wide roles (Application.Read.All,
            AgentIdentityBlueprint.Create, .UpdateAuthProperties.All,
            AgentIdentityBlueprintPrincipal.Create, AgentIdentity.Create.All,
            AgentIdUser.ReadWrite.All) - narrow before broad, so the
            pipeline never loses a capability in between. Only a Global
            Administrator can grant or revoke Graph application roles -
            Application Administrator is not sufficient.
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
      3a. Agent-user delegated grants (only with -AgentGrantsFile, the
         file the platform exports from GET /nce-api/v5/environment/
         agent-grants): for every agent and App with ENABLED agent-lane
         permission packs, the oAuth2PermissionGrant that lets its agent
         identity act as its own agent user with exactly the exported
         scope set - created or aligned, verified by reading it back.
         Nothing speculative: an agent or App with no packs is absent from
         the file and gets no grant (least exposure, project#2213). The
         file also carries the declared component Graph roles the
         deployment identity could not grant itself - granted here to the
         named workload identities (tenant-scoped reads only) - and
         whether SharePoint ingestion is part of the solution, in which
         case the Sites.Selected admin consent of the environment's
         SharePoint app is checked and its consent URL printed when missing.
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

.PARAMETER AgentGrantsFile
    Path to the JSON file the platform exports (NCE: GET
    /nce-api/v5/environment/agent-grants): the agent-user delegated grants
    driven by the packs actually enabled, the declared component Graph
    roles and the SharePoint ingestion marker. Optional; when given, step
    3a applies exactly those grants and nothing more (project#2213).

.PARAMETER MailboxGrantsFile
    Path to the JSON file Neologik exports from the platform's email
    channel registrations: an array of objects with IdentityAppId,
    IdentityObjectId, Mailbox and DisplayName. Optional; when given, step
    3b applies the scoped Exchange Online grants.

.PARAMETER RemoveLegacyGrantAppIds
    Application ids of retired identities whose Exchange Online mailbox
    assignments should be removed (the email monitor's identity at its
    migration window). Optional; used with or without -MailboxGrantsFile.

.PARAMETER UseAzureCliToken
    Sign in to Microsoft Graph with the Azure CLI session's token for the
    tenant (az account get-access-token) instead of the device-code prompt.
    For Neologik engineers running the script from a workstation whose az
    session in the tenant already satisfies multi-factor authentication -
    the device-code prompt allows only 120 seconds to complete. Customers
    keep the default device-code sign-in.

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
    [string]$BlueprintKey = 'default',

    [Parameter(Mandatory = $false)]
    [string]$AgentGrantsFile,

    [Parameter(Mandatory = $false)]
    [string]$MailboxGrantsFile,

    [Parameter(Mandatory = $false)]
    [string[]]$RemoveLegacyGrantAppIds,

    [Parameter(Mandatory = $false)]
    [switch]$UseAzureCliToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The two Microsoft Graph application roles the deployment identity keeps
# (least-privilege model, project#2144). Canonical inventory (names, ids,
# where each is used): neo-bot-service/docs/NEOLOGIK_PLATFORM_DEPLOYMENT_SP_PERMISSIONS.md.
# Matched by role value against the Graph service principal at runtime.
# Must match Install-NeologikEnvironment.ps1.
$script:RequiredGraphRoles = @(
    'Application.ReadWrite.OwnedBy',
    'AgentIdentityBlueprint.AddRemoveCreds.All'
)
# The tenant-wide roles retired by project#2144 - removed from the deployment
# identity AFTER the retained roles and the blueprint set-up are in place.
$script:RetiredGraphRoles = @(
    'Application.Read.All',
    'AgentIdentityBlueprint.Create',
    'AgentIdentityBlueprint.UpdateAuthProperties.All',
    'AgentIdentityBlueprintPrincipal.Create',
    'AgentIdentity.Create.All',
    'AgentIdUser.ReadWrite.All',
    # Granted by onboarding before project#1519 and never revoked on those
    # environments; the platform never creates Entra groups.
    'Group.Create'
)
# The blueprint PRINCIPAL's own role: agent users parented by that blueprint only.
$script:BlueprintPrincipalGraphRoles = @('AgentIdUser.ReadWrite.IdentityParentedBy')
# Deployment pipeline repositories allowed to obtain a token as the blueprint
# (GitHub OIDC, bound to the immutable repository id). Must match
# Install-NeologikEnvironment.ps1.
$script:PipelineRepositories = @(
    @{ Name = 'neo-infrastructure'; Id = '995398788' },
    @{ Name = 'neo-bot-service';    Id = '995400343' },
    @{ Name = 'neo-env-config';     Id = '995441655' }
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
# The SharePoint app's role (Sites.Selected) checked only when the exported
# grants file says SharePoint ingestion is part of the solution.
$script:SharePointAppDisplayNamePrefix = 'Neologik SharePoint Access - '
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

# ----- agent-user delegated grants (project#2213) --------------------------

function Get-NeologikScopeSet {
    param([string]$Value)
    @(($Value -split '\s+') | Where-Object { $_ } | Sort-Object -Unique) -join ' '
}

function Grant-NeologikAgentUserAccess {
    <#
    One delegated permission grant per agent or App: client = the agent
    identity (the FOUNDATION identity, by its stored client id), principal =
    the agent user (by its stored object id), resource = Microsoft Graph,
    scope = exactly the exported set. Created or aligned (a differing scope
    is PATCHed), success only after reading the grant back and comparing
    the scope SETS - Entra refuses some scope strings transiently, so a
    refused write is retried with the same scopes in a rotated order
    (project#1732). The platform never reads these grants itself: the
    operator confirms them in the NCE afterwards.
    #>
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$IdentityClientId,
        [Parameter(Mandatory)][string]$AgentUserObjectId,
        [Parameter(Mandatory)][string[]]$Scopes
    )
    $label = "Agent-user grant: $Kind $Name"
    $graph = 'https://graph.microsoft.com/v1.0'
    $graphBeta = 'https://graph.microsoft.com/beta'
    $identity = @((Invoke-MgGraphRequest -Method GET -Uri "$graphBeta/servicePrincipals?`$filter=appId eq '$IdentityClientId'&`$select=id").value) | Select-Object -First 1
    if (-not $identity) {
        Write-Log "  $Kind '$Name': agent identity $IdentityClientId not found - re-run the platform provisioning, then this script" -Level Warning
        Add-Summary $label 'MISSING - agent identity not found'
        return
    }
    $graphSp = Get-MgServicePrincipal -Filter "appId eq '$script:GraphSpAppId'"
    $desired = Get-NeologikScopeSet ($Scopes -join ' ')
    $existing = @((Invoke-MgGraphRequest -Method GET -Uri "$graph/oauth2PermissionGrants?`$filter=clientId eq '$($identity.id)' and principalId eq '$AgentUserObjectId'").value) | Select-Object -First 1
    if ($existing -and (Get-NeologikScopeSet $existing.scope) -eq $desired) {
        Write-Log "  $Kind '$Name' - grant already present ($desired)" -Level Success
        Add-Summary $label 'Already granted'
        return
    }
    $words = @($desired -split ' ')
    $applied = $false
    for ($attempt = 0; $attempt -lt 3 -and -not $applied; $attempt++) {
        $k = if ($words.Count -gt 0) { $attempt % $words.Count } else { 0 }
        $rotated = @($words[$k..($words.Count - 1)]) + @($words[0..($k - 1)] | Where-Object { $k -gt 0 })
        $scopeTry = ($rotated | Where-Object { $_ }) -join ' '
        try {
            if ($existing) {
                Invoke-MgGraphRequest -Method PATCH -Uri "$graph/oauth2PermissionGrants/$($existing.id)" `
                    -Body (@{ scope = $scopeTry } | ConvertTo-Json -Compress) -ContentType 'application/json' | Out-Null
            }
            else {
                $body = @{ clientId = $identity.id; consentType = 'Principal'; principalId = $AgentUserObjectId
                           resourceId = $graphSp.Id; scope = $scopeTry } | ConvertTo-Json -Compress
                Invoke-MgGraphRequest -Method POST -Uri "$graph/oauth2PermissionGrants" -Body $body -ContentType 'application/json' | Out-Null
            }
            $applied = $true
        }
        catch {
            Write-Log "  attempt $($attempt + 1) refused scope string '$scopeTry': $($_.Exception.Message)" -Level Warning
        }
    }
    $readback = @((Invoke-MgGraphRequest -Method GET -Uri "$graph/oauth2PermissionGrants?`$filter=clientId eq '$($identity.id)' and principalId eq '$AgentUserObjectId'").value) | Select-Object -First 1
    if ($readback -and (Get-NeologikScopeSet $readback.scope) -eq $desired) {
        Write-Log "  $Kind '$Name' - GRANTED ($desired)" -Level Success
        Add-Summary $label $(if ($existing) { "Updated ($desired)" } else { "Granted ($desired)" })
    }
    else {
        Write-Log "  $Kind '$Name' - the scope set '$desired' did not land after 3 attempts; report the string to Neologik" -Level Error
        Add-Summary $label 'PENDING - scope refused, report'
    }
}

function Grant-NeologikComponentGraphRole {
    <#
    A declared component Graph role (project#1451) the deployment identity
    could not grant: the application role on the named workload identity.
    Only unscoped roles are granted here (tenant-scoped reads); a
    mailbox- or site-scoped declaration is reported for the customer's
    Exchange or SharePoint administrator.
    #>
    param(
        [Parameter(Mandatory)][string]$App,
        [Parameter(Mandatory)][string]$IdentityName,
        [Parameter(Mandatory)][string]$RoleName,
        [string]$ScopeType
    )
    $label = "Component role: $App $RoleName"
    if ($ScopeType) {
        Write-Log "  $App '$RoleName' is $ScopeType-scoped - grant it in Exchange Online or SharePoint for the declared resource (not a Graph app role)" -Level Warning
        Add-Summary $label "SKIPPED - $ScopeType-scoped, administrator grants per resource"
        return
    }
    $sp = @((Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=displayName eq '$IdentityName'&`$select=id").value) | Select-Object -First 1
    if (-not $sp) {
        Write-Log "  workload identity '$IdentityName' not found - provision the app first" -Level Warning
        Add-Summary $label 'MISSING - identity not found'
        return
    }
    $null = Set-GraphAppRoles -PrincipalId $sp.id -Label "Component $App" -RoleNames @($RoleName)
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

$script:AgentGrants = $null
if ($AgentGrantsFile) {
    if (-not (Test-Path $AgentGrantsFile)) {
        throw "Agent grants file not found: $AgentGrantsFile"
    }
    $script:AgentGrants = Get-Content $AgentGrantsFile -Raw | ConvertFrom-Json
    $guidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    foreach ($entry in @($script:AgentGrants.grants)) {
        if ($entry.status -ne 'ready') { continue }
        if ($entry.identityClientId -notmatch $guidPattern -or $entry.agentUserObjectId -notmatch $guidPattern) {
            throw "Agent grants file: identityClientId and agentUserObjectId must be GUIDs ($($entry.name))."
        }
        if (-not @($entry.scopes).Count) {
            throw "Agent grants file: every ready entry needs scopes ($($entry.name))."
        }
    }
    Write-Log "Agent grants loaded: $(@($script:AgentGrants.grants).Count) agent/app entries, $(@($script:AgentGrants.componentGraphRoles).Count) component role(s), SharePoint ingestion: $($script:AgentGrants.sharePointIngestion)" -Level Info
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
if ($script:AgentGrants) { Write-Host "  Agent grants file:   $AgentGrantsFile" }
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

$graphScopes = @('Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'DelegatedPermissionGrant.Read.All',
    'AgentIdentityBlueprint.Create', 'AgentIdentityBlueprint.AddRemoveCreds.All', 'AgentIdentityBlueprintPrincipal.Create')
if ($script:AgentGrants) {
    # The agent-user grants are oAuth2PermissionGrants - a write scope only
    # a Global Administrator holds (the deployment identity never does).
    $graphScopes += 'DelegatedPermissionGrant.ReadWrite.All'
}
if ($Phase -eq 'PostWindow') {
    $graphScopes += 'RoleManagement.ReadWrite.Directory'
}
if ($UseAzureCliToken) {
    Write-Log 'Signing in to Microsoft Graph with the Azure CLI session token (az account get-access-token)...' -Level Info
    $cliToken = az account get-access-token --resource-type ms-graph --tenant $TenantId --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($cliToken)) {
        throw "az account get-access-token failed for tenant $TenantId - sign in first: az login --tenant $TenantId --scope https://graph.microsoft.com//.default"
    }
    Connect-MgGraph -AccessToken (ConvertTo-SecureString -String $cliToken -AsPlainText -Force) -NoWelcome
}
else {
    Write-Log 'Signing in to Microsoft Graph (device code - use your Global Administrator account)...' -Level Info
    Connect-MgGraph -TenantId $TenantId -Scopes $graphScopes -UseDeviceCode -NoWelcome
}

$deploySp = Get-MgServicePrincipal -Filter "appId eq '$DeploySpClientId'"
if (-not $deploySp) {
    throw "Deployment service principal not found for client id $DeploySpClientId in tenant $TenantId."
}
Write-Log "Deployment identity: '$($deploySp.DisplayName)'" -Level Info

if ($Phase -eq 'Window') {

    $graphSp = Get-MgServicePrincipal -Filter "appId eq '$script:GraphSpAppId'"
    $graph = 'https://graph.microsoft.com/v1.0'
    $graphBeta = 'https://graph.microsoft.com/beta'
    $odataHeaders = @{ 'OData-Version' = '4.0' }

    # Ensures a set of Graph app roles on one principal; returns the number newly granted.
    function Set-GraphAppRoles {
        param([string]$PrincipalId, [string]$Label, [string[]]$RoleNames)
        $existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalId -All |
            Where-Object { $_.ResourceId -eq $graphSp.Id }
        $count = 0
        foreach ($roleName in $RoleNames) {
            $role = $graphSp.AppRoles | Where-Object { $_.Value -eq $roleName }
            if (-not $role) {
                Write-Log "  role '$roleName' not published by Microsoft Graph in this cloud - report this to Neologik" -Level Warning
                Add-Summary "$Label role: $roleName" 'NOT FOUND - report'
                continue
            }
            if ($existing | Where-Object { $_.AppRoleId -eq $role.Id }) {
                Write-Log "  $roleName - already granted" -Level Success
                Add-Summary "$Label role: $roleName" 'Already granted'
            }
            else {
                New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalId `
                    -PrincipalId $PrincipalId -ResourceId $graphSp.Id -AppRoleId $role.Id | Out-Null
                Write-Log "  $roleName - GRANTED" -Level Success
                Add-Summary "$Label role: $roleName" 'Granted'
                $count++
            }
        }
        return $count
    }

    # ----- 1a. agent identity blueprint (owned by the deployment identity) ----
    Write-Log 'Step 1a/4: agent identity blueprint' -Level Info
    $shortName = if ($ConfigurationFile) { [string]$config.SolutionShortName } else { '' }
    if (-not $shortName) {
        # Derive from the deployment identity's name ('Neologik GitHub Service Connection - <short>').
        $shortName = ($deploySp.DisplayName -split ' - ')[-1].Trim()
    }
    $blueprintName = "Neologik Agent Blueprint - $BlueprintKey - $shortName"
    $escaped = $blueprintName -replace "'", "''"
    $found = Invoke-MgGraphRequest -Method GET -Uri "$graph/applications?`$filter=displayName eq '$escaped'&`$select=id,appId"
    $blueprint = @($found.value) | Select-Object -First 1
    if ($blueprint) {
        Write-Log "  blueprint '$blueprintName' - present (Client ID $($blueprint.appId))" -Level Success
        Add-Summary 'Agent blueprint' 'Present'
    }
    else {
        $sponsor = (Invoke-MgGraphRequest -Method GET -Uri "$graph/me?`$select=id").id
        $body = @{
            '@odata.type'         = 'Microsoft.Graph.AgentIdentityBlueprint'
            displayName           = $blueprintName
            'sponsors@odata.bind' = @("$graph/users/$sponsor")
            'owners@odata.bind'   = @("$graph/directoryObjects/$($deploySp.Id)")
        } | ConvertTo-Json -Depth 5 -Compress
        $blueprint = Invoke-MgGraphRequest -Method POST -Uri "$graph/applications/microsoft.graph.agentIdentityBlueprint" `
            -Headers $odataHeaders -Body $body -ContentType 'application/json'
        Write-Log "  blueprint '$blueprintName' - CREATED (Client ID $($blueprint.appId); sponsor = you)" -Level Success
        Add-Summary 'Agent blueprint' 'Created'
    }
    $blueprintObjectId = [string]$blueprint.id
    $blueprintAppId = [string]$blueprint.appId

    $owners = Invoke-MgGraphRequest -Method GET -Uri "$graph/applications/$blueprintObjectId/owners?`$select=id"
    if (@($owners.value | ForEach-Object { $_.id }) -contains $deploySp.Id) {
        Write-Log '  deployment identity owns the blueprint - already' -Level Success
        Add-Summary 'Blueprint owner' 'Already in place'
    }
    else {
        $ref = @{ '@odata.id' = "$graph/directoryObjects/$($deploySp.Id)" } | ConvertTo-Json -Compress
        Invoke-MgGraphRequest -Method POST -Uri "$graph/applications/$blueprintObjectId/owners/`$ref" -Body $ref -ContentType 'application/json' | Out-Null
        Write-Log '  deployment identity owns the blueprint - ADDED' -Level Success
        Add-Summary 'Blueprint owner' 'Added'
    }

    $principal = @((Invoke-MgGraphRequest -Method GET -Uri "$graph/servicePrincipals?`$filter=appId eq '$blueprintAppId'&`$select=id").value) | Select-Object -First 1
    if ($principal) {
        Write-Log '  blueprint principal - present' -Level Success
        Add-Summary 'Blueprint principal' 'Present'
    }
    else {
        $body = @{ appId = $blueprintAppId } | ConvertTo-Json -Compress
        for ($attempt = 1; $attempt -le 10; $attempt++) {
            try {
                $principal = Invoke-MgGraphRequest -Method POST -Uri "$graph/servicePrincipals/microsoft.graph.agentIdentityBlueprintPrincipal" `
                    -Headers $odataHeaders -Body $body -ContentType 'application/json'
                break
            }
            catch {
                if ($attempt -lt 10 -and ($_.Exception.Message -match 'local tenant|does not exist')) {
                    Write-Log "  blueprint not yet replicated - retrying in 15 seconds ($attempt of 10)" -Level Warning
                    Start-Sleep -Seconds 15
                    continue
                }
                throw
            }
        }
        Write-Log '  blueprint principal - CREATED' -Level Success
        Add-Summary 'Blueprint principal' 'Created'
    }
    $principalId = [string]$principal.id

    $spOwners = Invoke-MgGraphRequest -Method GET -Uri "$graph/servicePrincipals/$principalId/owners?`$select=id"
    if (-not (@($spOwners.value | ForEach-Object { $_.id }) -contains $deploySp.Id)) {
        $ref = @{ '@odata.id' = "$graph/directoryObjects/$($deploySp.Id)" } | ConvertTo-Json -Compress
        Invoke-MgGraphRequest -Method POST -Uri "$graph/servicePrincipals/$principalId/owners/`$ref" -Body $ref -ContentType 'application/json' | Out-Null
        Write-Log '  deployment identity owns the blueprint principal - ADDED' -Level Success
        Add-Summary 'Blueprint principal owner' 'Added'
    }
    else {
        Write-Log '  deployment identity owns the blueprint principal - already' -Level Success
        Add-Summary 'Blueprint principal owner' 'Already in place'
    }

    Write-Log 'Step 1b/4: blueprint principal Graph role' -Level Info
    $null = Set-GraphAppRoles -PrincipalId $principalId -Label 'Blueprint principal' -RoleNames $script:BlueprintPrincipalGraphRoles

    Write-Log 'Step 1c/4: GitHub OIDC federated credentials on the blueprint' -Level Info
    $existingCreds = Invoke-MgGraphRequest -Method GET -Uri "$graphBeta/applications/$blueprintObjectId/federatedIdentityCredentials?`$select=name"
    $existingNames = @($existingCreds.value | ForEach-Object { $_.name })
    foreach ($repo in $script:PipelineRepositories) {
        $credName = "github-oidc-$($repo.Name)"
        if ($existingNames -contains $credName) {
            Write-Log "  $credName - present" -Level Success
            Add-Summary "Blueprint credential: $credName" 'Present'
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
            -Body $body -ContentType 'application/json' | Out-Null
        Write-Log "  $credName - ADDED" -Level Success
        Add-Summary "Blueprint credential: $credName" 'Added'
    }

    # ----- 1d. deployment identity Graph roles: retained first, then retired --
    Write-Log 'Step 1d/4: deployment identity Graph roles (retained, then retired)' -Level Info
    $granted = Set-GraphAppRoles -PrincipalId $deploySp.Id -Label 'Graph' -RoleNames $script:RequiredGraphRoles
    $assignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $deploySp.Id -All |
        Where-Object { $_.ResourceId -eq $graphSp.Id }
    foreach ($roleName in $script:RetiredGraphRoles) {
        $role = $graphSp.AppRoles | Where-Object { $_.Value -eq $roleName }
        $assignment = if ($role) { $assignments | Where-Object { $_.AppRoleId -eq $role.Id } | Select-Object -First 1 } else { $null }
        if ($assignment) {
            Remove-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $deploySp.Id -AppRoleAssignmentId $assignment.Id
            Write-Log "  $roleName - REMOVED (retired, tenant-wide)" -Level Success
            Add-Summary "Retired Graph role: $roleName" 'Removed'
        }
        else {
            Write-Log "  $roleName - not held (nothing to remove)" -Level Success
            Add-Summary "Retired Graph role: $roleName" 'Not held'
        }
    }
    Write-Log "Graph roles complete ($granted newly granted)" -Level Info

    # ----- 2. sign-in group assignment ----------------------------------------
    Write-Log 'Step 2/4: NCE user group assignment to the sign-in application' -Level Info
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
        Write-Log 'Step 3/4: admin consent for the sign-in application' -Level Info
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

    # ----- 3a. agent-user grants, component roles, SharePoint consent (project#2213)
    if ($script:AgentGrants) {
        Write-Log 'Step 3a: agent-user delegated grants from the exported grants file' -Level Info
        foreach ($entry in @($script:AgentGrants.grants)) {
            if ($entry.status -ne 'ready') {
                Write-Log "  $($entry.kind) '$($entry.name)': identity not stamped yet - run the platform provisioning, export again" -Level Warning
                Add-Summary "Agent-user grant: $($entry.kind) $($entry.name)" 'SKIPPED - identity not stamped'
                continue
            }
            Grant-NeologikAgentUserAccess -Kind $entry.kind -Name $entry.name `
                -IdentityClientId $entry.identityClientId -AgentUserObjectId $entry.agentUserObjectId `
                -Scopes @($entry.scopes)
        }
        foreach ($role in @($script:AgentGrants.componentGraphRoles)) {
            if ($role.resource -and $role.resource -ne 'graph') {
                Write-Log "  $($role.app) '$($role.roleName)' is a $($role.resource) role - granted through that service, not Graph" -Level Warning
                Add-Summary "Component role: $($role.app) $($role.roleName)" "SKIPPED - $($role.resource) role"
                continue
            }
            Grant-NeologikComponentGraphRole -App $role.app -IdentityName $role.identityName `
                -RoleName $role.roleName -ScopeType $role.scopeType
        }
        if ($script:AgentGrants.sharePointIngestion) {
            Write-Log 'Step 3a: SharePoint ingestion is part of the solution - checking the Sites.Selected consent' -Level Info
            # The tenant may host several environments (the Neologik dev tenant
            # holds eight): resolve THIS environment's app by its exact name
            # first, and fall back to the prefix search only when it is the
            # single match (dev03 finding 2026-09-06, project#2213).
            $spShort = if ($ConfigurationFile) { [string]$config.SolutionShortName } else { '' }
            $spApp = $null
            if ($spShort) {
                $spApp = @((Invoke-MgGraphRequest -Method GET -Uri "$graph/servicePrincipals?`$filter=displayName eq '$script:SharePointAppDisplayNamePrefix$spShort'&`$select=id,appId,displayName").value) | Select-Object -First 1
            }
            if (-not $spApp) {
                $spCandidates = @((Invoke-MgGraphRequest -Method GET -Uri "$graph/servicePrincipals?`$filter=startswith(displayName,'$script:SharePointAppDisplayNamePrefix')&`$select=id,appId,displayName").value)
                if ($spCandidates.Count -eq 1) { $spApp = $spCandidates[0] }
                elseif ($spCandidates.Count -gt 1) {
                    Write-Log "  $($spCandidates.Count) SharePoint access apps in this tenant and no environment short name to pick by - supply -ConfigurationFile" -Level Warning
                    Add-Summary 'SharePoint Sites.Selected consent' 'UNKNOWN - several apps, environment not identified'
                    $spApp = 'ambiguous'
                }
            }
            if ($spApp -eq 'ambiguous') { }
            elseif (-not $spApp) {
                Write-Log '  SharePoint app not found in this tenant - the infrastructure deployment creates it' -Level Warning
                Add-Summary 'SharePoint Sites.Selected consent' 'MISSING - app not found'
            }
            else {
                $sitesSelected = $graphSp.AppRoles | Where-Object { $_.Value -eq 'Sites.Selected' }
                $held = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $spApp.id -All |
                    Where-Object { $_.ResourceId -eq $graphSp.Id -and $sitesSelected -and $_.AppRoleId -eq $sitesSelected.Id }
                if ($held) {
                    Write-Log "  '$($spApp.displayName)' holds Sites.Selected - consent present (sites are granted per site by a site administrator)" -Level Success
                    Add-Summary 'SharePoint Sites.Selected consent' 'Present'
                }
                else {
                    $spConsentUrl = "https://login.microsoftonline.com/$TenantId/adminconsent?client_id=$($spApp.appId)"
                    Write-Log '  Sites.Selected consent NOT found. Open this URL as Global Administrator and approve:' -Level Warning
                    Write-Host ''
                    Write-Host "    $spConsentUrl" -ForegroundColor Cyan
                    Write-Host ''
                    Add-Summary 'SharePoint Sites.Selected consent' 'MISSING - consent URL printed'
                }
            }
        }
        else {
            Write-Log 'Step 3a: no SharePoint ingestion in the solution - Sites.Selected consent not checked (least exposure)' -Level Info
            Add-Summary 'SharePoint Sites.Selected consent' 'Not needed'
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
# Machine-readable summary beside the log (project#2213): the deployment
# identity's Graph roles as they stand and every consent state, for the
# migration ticket. Written next to the script; never contains a secret.
try {
    $heldRoles = @()
    if ($deploySp) {
        $graphSpForSummary = Get-MgServicePrincipal -Filter "appId eq '$script:GraphSpAppId'"
        $heldRoles = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $deploySp.Id -All |
            Where-Object { $_.ResourceId -eq $graphSpForSummary.Id } |
            ForEach-Object { $roleId = $_.AppRoleId; ($graphSpForSummary.AppRoles | Where-Object { $_.Id -eq $roleId }).Value })
    }
    $summaryPath = Join-Path (Split-Path -Parent $PSCommandPath) ("Neologik_EnvironmentAccess_{0}_{1}.json" -f $Phase, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    [pscustomobject]@{
        tenantId               = $TenantId
        deploymentIdentity     = $DeploySpClientId
        phase                  = $Phase
        ranAt                  = (Get-Date).ToUniversalTime().ToString('o')
        deploymentGraphRoles   = $heldRoles
        expectedGraphRoles     = $script:RequiredGraphRoles
        agentGrantsFile        = $AgentGrantsFile
        items                  = $script:Summary
    } | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryPath -Encoding UTF8
    Write-Log "Summary written to $summaryPath - paste it on the migration ticket" -Level Info
}
catch {
    Write-Log "Could not write the JSON summary: $($_.Exception.Message)" -Level Warning
}
$attention = @($script:Summary | Where-Object { $_.Result -match 'MISSING|SKIPPED|NOT FOUND|PENDING' })
if ($attention.Count -gt 0) {
    Write-Log "$($attention.Count) item(s) need attention - see the summary above." -Level Warning
    exit 1
}
Write-Log "Phase '$Phase' complete - environment access is in the expected state." -Level Success
exit 0
