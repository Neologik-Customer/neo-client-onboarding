#Requires -Version 7.4
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

    The script never stops on the first problem: every item is verified or
    applied independently, a failing item is recorded in the summary with
    its reason, and dependent removals are held back whenever the narrow
    grants that must precede them did not all land. The run ends with a
    summary table and a machine-readable JSON summary; the exit code is 0
    when everything is in the expected state and 1 when any item needs
    attention.

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
         removed so deployments never lose access in between; if any
         narrow role could not be applied, nothing is removed.

    Microsoft Graph sign-in scopes requested (all delegated, under your own
    account): Application.ReadWrite.All, AppRoleAssignment.ReadWrite.All,
    Directory.Read.All, User.Read, DelegatedPermissionGrant.Read.All,
    AgentIdentityBlueprint.Create, AgentIdentityBlueprint.AddRemoveCreds.All,
    AgentIdentityBlueprintPrincipal.Create; plus
    DelegatedPermissionGrant.ReadWrite.All only with -AgentGrantsFile and
    RoleManagement.ReadWrite.Directory only for -Phase PostWindow.

    Output: a summary table, and a JSON summary file
    Neologik_EnvironmentAccess_<phase>_<stamp>.json written beside the
    script (or in the current folder, or the temp folder, when that
    location is not writable). Exit code 0 = everything in the expected
    state; 1 = at least one item needs attention (see the summary).

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
    3a applies exactly those grants and nothing more (project#2213). The
    file's tenant id must match the tenant this run targets.

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

.PARAMETER BlueprintKey
    Key segment of the agent identity blueprint name ('default' unless
    Neologik tells you otherwise).

.EXAMPLE
    ./Update-NeologikEnvironmentAccess.ps1 -ConfigurationFile ./Neologik_abcprd_Configuration_20250101_120000.json

.EXAMPLE
    ./Update-NeologikEnvironmentAccess.ps1 -ConfigurationFile ./Neologik_abcprd_Configuration_20250101_120000.json -Phase PostWindow
#>

# This is an interactive console script: Write-Host is the intended output
# channel (the summary table and consent URLs must reach the operator, never
# the pipeline). The Azure CLI token is converted to a SecureString because
# Connect-MgGraph 2.x accepts nothing else; it is never written anywhere.
# Write-Log matches the sibling Install-NeologikEnvironment.ps1. ShouldProcess
# is not used: every write is preceded by a verification of the same state.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive console script; the summary and consent URLs are for the operator.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Connect-MgGraph 2.x requires a SecureString; the token comes from the Azure CLI cache and is never persisted.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'Write-Log matches the sibling onboarding script; no built-in Write-Log exists in PowerShell 7.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPositionalParameters', 'Get-NeologikProperty', Justification = 'The property accessor reads as (object, name, default); named parameters would triple its length at 60 call sites.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Verification-first and idempotent by design; every write follows a read of the same state.')]
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

# The legacy subscription-scoped roles removed by the PostWindow phase.
$script:LegacySubRoles = @('Contributor', 'User Access Administrator')

$script:GraphSpAppId = '00000003-0000-0000-c000-000000000000'
# The SharePoint app's role (Sites.Selected) checked only when the exported
# grants file says SharePoint ingestion is part of the solution.
$script:SharePointAppDisplayNamePrefix = 'Neologik SharePoint Access - '
$script:AppAdminRoleTemplateId = '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3'
$script:GraphV1 = 'https://graph.microsoft.com/v1.0'
$script:GraphBeta = 'https://graph.microsoft.com/beta'
$script:OdataHeaders = @{ 'OData-Version' = '4.0' }
$script:GuidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
# Summary results matching this pattern need the operator's attention and
# make the exit code 1.
$script:AttentionPattern = 'MISSING|SKIPPED|NOT FOUND|PENDING|FAILED|UNKNOWN'
# Microsoft Graph PowerShell SDK 2.x is required (SecureString access tokens,
# -SkipHttpErrorCheck); ExchangeOnlineManagement 3.x for device-code sign-in.
$script:GraphModuleMinimumVersion = [version]'2.0.0'
$script:ExchangeModuleMinimumVersion = [version]'3.0.0'
$script:GraphModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Applications',
    'Microsoft.Graph.Groups',
    'Microsoft.Graph.Identity.DirectoryManagement'
)
$script:Summary = @()
# Shared run state (inputs, resolved principals); populated by the main entry.
$script:State = @{}

# ----- console + summary helpers ---------------------------------------------

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

function Write-ActionRequired {
    # One clear instruction block for the operator: what to do and why.
    param([string]$Message)
    Write-Host ''
    Write-Host 'ACTION REQUIRED' -ForegroundColor Yellow
    foreach ($line in ($Message -split "`n")) {
        Write-Host "  $($line.TrimEnd())" -ForegroundColor Yellow
    }
    Write-Host ''
}

function Add-Summary {
    param([string]$Item, [string]$Result)
    $script:Summary += [pscustomobject]@{ Item = $Item; Result = $Result }
}

function Get-NeologikProperty {
    <#
    Safe property read for JSON objects (PSCustomObject) and Graph responses
    (hashtables) alike: strict mode throws on a missing property or key, and
    an exported file or a Graph reply may legitimately omit one.
    #>
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function Test-NeologikGuid {
    param([string]$Value)
    return [bool]($Value -match $script:GuidPattern)
}

function Get-NeologikErrorText {
    <#
    A one-line reason for the summary and the log: the exception message
    (first line) plus the Graph error body when the SDK attached one. Never
    a token or a stack trace.
    #>
    param($ErrorRecord)
    if ($null -eq $ErrorRecord) { return 'unknown error' }
    $text = ''
    $exception = Get-NeologikProperty $ErrorRecord 'Exception'
    if ($exception) { $text = [string](Get-NeologikProperty $exception 'Message' '') }
    elseif ($ErrorRecord -is [string]) { $text = $ErrorRecord }
    else { $text = [string]$ErrorRecord }
    $details = Get-NeologikProperty $ErrorRecord 'ErrorDetails'
    $detailText = if ($details) { [string](Get-NeologikProperty $details 'Message' '') } else { '' }
    if ($detailText -and $text -notlike "*$detailText*") { $text = "$text $detailText" }
    $text = ($text -split "`r?`n" | Where-Object { $_.Trim() }) -join ' '
    $text = $text -replace '(?i)bearer\s+[A-Za-z0-9\-_\.=]+', 'bearer <token>'
    if ($text.Length -gt 300) { $text = $text.Substring(0, 300) + '...' }
    if (-not $text) { $text = 'unknown error' }
    return $text
}

function Get-NeologikHttpStatus {
    # Best-effort HTTP status of a failed Graph or SDK call (0 when unknown).
    param($ErrorRecord)
    $exception = Get-NeologikProperty $ErrorRecord 'Exception'
    while ($exception) {
        $status = Get-NeologikProperty $exception 'StatusCode'
        if ($null -ne $status -and "$status" -match '^\d+$') { return [int]$status }
        if ($null -ne $status) {
            try { return [int][System.Net.HttpStatusCode]$status } catch { Write-Verbose "ignored: $($_.Exception.Message)" }
        }
        $response = Get-NeologikProperty $exception 'Response'
        if ($response) {
            $status = Get-NeologikProperty $response 'StatusCode'
            if ($null -ne $status) { try { return [int]$status } catch { Write-Verbose "ignored: $($_.Exception.Message)" } }
        }
        $exception = Get-NeologikProperty $exception 'InnerException'
    }
    $text = Get-NeologikErrorText $ErrorRecord
    if ($text -match '(?i)Authorization_RequestDenied|Insufficient privileges|Forbidden') { return 403 }
    if ($text -match '(?i)Request_ResourceNotFound|does not exist|not found') { return 404 }
    if ($text -match '(?i)TooManyRequests|throttl') { return 429 }
    return 0
}

function Test-NeologikPrivilegeError {
    param($ErrorRecord)
    return ((Get-NeologikHttpStatus $ErrorRecord) -eq 403)
}

function Get-NeologikScopeSet {
    param([string]$Value)
    @(($Value -split '\s+') | Where-Object { $_ } | Sort-Object -Unique) -join ' '
}

# ----- module, sign-in and process seams ----------------------------------------
# Thin wrappers around the commands that touch the machine or the network;
# they carry no logic so the test harness can replace them.

function Get-NeologikAvailableModuleVersion {
    param([string]$Name)
    return @(Get-Module -ListAvailable -Name $Name | ForEach-Object { [version]$_.Version })
}

function Get-NeologikLoadedModuleVersion {
    param([string]$Name)
    $loaded = @(Get-Module -Name $Name) | Select-Object -First 1
    if ($loaded) { return [version]$loaded.Version }
    return $null
}

function Install-NeologikModule {
    param([string]$Name, [version]$MinimumVersion)
    Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber -MinimumVersion $MinimumVersion -ErrorAction Stop
}

function Import-NeologikModule {
    param([string]$Name, [version]$RequiredVersion)
    if ($RequiredVersion) {
        Import-Module -Name $Name -RequiredVersion $RequiredVersion -ErrorAction Stop
    }
    else {
        Import-Module -Name $Name -ErrorAction Stop
    }
}

function Test-NeologikCommand {
    param([string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Invoke-NeologikAzureCli {
    <#
    Runs az with the given arguments; returns the exit code and the stdout
    lines. Local preferences keep a non-zero exit code or stderr chatter from
    becoming a terminating error (PowerShell 7.4+ can promote either).
    #>
    param([string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    $raw = @(& az @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $lines = @($raw | Where-Object { $_ -is [string] })
    return @{ ExitCode = $exitCode; Output = $lines }
}

function Invoke-NeologikGraphRaw {
    <#
    One Microsoft Graph request through the SDK with HTTP errors returned,
    not thrown: status code, response headers and body for the caller.
    #>
    param([string]$Method, [string]$Uri, $Body, [hashtable]$Headers, [string]$ContentType)
    $statusCode = $null
    $responseHeaders = $null
    $request = @{
        Method                  = $Method
        Uri                     = $Uri
        SkipHttpErrorCheck      = $true
        StatusCodeVariable      = 'statusCode'
        ResponseHeadersVariable = 'responseHeaders'
    }
    if ($null -ne $Body) { $request['Body'] = $Body }
    if ($Headers -and $Headers.Count -gt 0) { $request['Headers'] = $Headers }
    if ($ContentType) { $request['ContentType'] = $ContentType }
    $response = Invoke-MgGraphRequest @request
    return @{ StatusCode = [int]$statusCode; Headers = $responseHeaders; Body = $response }
}

function Get-NeologikSummaryDirectory {
    # Candidate folders for the JSON summary, in order of preference.
    $candidates = @()
    if ($PSCommandPath) { $candidates += (Split-Path -Parent $PSCommandPath) }
    $candidates += (Get-Location).Path
    $candidates += [System.IO.Path]::GetTempPath()
    return @($candidates | Where-Object { $_ } | Select-Object -Unique)
}

# ----- Microsoft Graph request helpers ------------------------------------------

function Get-NeologikRetryDelay {
    param($Headers, [int]$Attempt)
    $delay = [math]::Min(60, [math]::Pow(2, $Attempt))
    $retryAfter = $null
    if ($Headers -is [System.Collections.IDictionary]) {
        foreach ($key in @($Headers.Keys)) {
            if ("$key" -eq 'Retry-After') { $retryAfter = $Headers[$key]; break }
        }
    }
    if ($null -ne $retryAfter) {
        $value = [string](@($retryAfter) | Select-Object -First 1)
        if ($value -match '^\d+$') { $delay = [math]::Min(60, [math]::Max(1, [int]$value)) }
    }
    return [int]$delay
}

function Get-NeologikGraphErrorMessage {
    param([int]$StatusCode, [string]$Method, [string]$Uri, $Body)
    $path = $Uri
    try { $path = ([uri]$Uri).AbsolutePath } catch { Write-Verbose "ignored: $($_.Exception.Message)" }
    $detail = ''
    $graphError = Get-NeologikProperty $Body 'error'
    if ($graphError) {
        $code = [string](Get-NeologikProperty $graphError 'code' '')
        $message = [string](Get-NeologikProperty $graphError 'message' '')
        $detail = (@($code, $message) | Where-Object { $_ }) -join ' - '
    }
    $text = "Graph $Method $path returned HTTP $StatusCode"
    if ($detail) { $text = "$text ($detail)" }
    return $text
}

function Invoke-NeologikGraph {
    <#
    A Microsoft Graph request that retries throttling (429) and transient
    service errors (502/503/504) with the Retry-After header honoured, and
    - with -RetryNotFound, used right after a create - a 404 caused by
    replication delay. Any other failure is thrown as an
    HttpRequestException carrying the status code and the Graph error text.
    #>
    param(
        [string]$Method = 'GET',
        [Parameter(Mandatory)][string]$Uri,
        $Body,
        [hashtable]$Headers,
        [string]$ContentType = 'application/json',
        [switch]$RetryNotFound,
        [int]$MaxAttempts = 5
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $result = Invoke-NeologikGraphRaw -Method $Method -Uri $Uri -Body $Body -Headers $Headers -ContentType $ContentType
        $status = [int]$result.StatusCode
        if ($status -ge 200 -and $status -lt 300) { return $result.Body }
        $transient = ($status -in @(429, 502, 503, 504)) -or ($RetryNotFound -and $status -eq 404)
        if ($transient -and $attempt -lt $MaxAttempts) {
            $delay = Get-NeologikRetryDelay -Headers $result.Headers -Attempt $attempt
            Write-Log "  Graph returned $status - retrying in $delay s ($attempt of $MaxAttempts)" -Level Warning
            Start-Sleep -Seconds $delay
            continue
        }
        $message = Get-NeologikGraphErrorMessage -StatusCode $status -Method $Method -Uri $Uri -Body $result.Body
        throw [System.Net.Http.HttpRequestException]::new($message, $null, [System.Net.HttpStatusCode]$status)
    }
}

function Get-NeologikGraphCollection {
    # GET a collection, following @odata.nextLink until the last page.
    param([Parameter(Mandatory)][string]$Uri, [switch]$RetryNotFound, [int]$MaxPages = 200)
    $items = @()
    $next = $Uri
    $pages = 0
    while ($next -and $pages -lt $MaxPages) {
        $page = Invoke-NeologikGraph -Method GET -Uri $next -RetryNotFound:$RetryNotFound
        $items += @(Get-NeologikProperty $page 'value' @())
        $next = [string](Get-NeologikProperty $page '@odata.nextLink' '')
        $pages++
    }
    return , $items
}

function Get-NeologikGraphAppRole {
    param([string]$RoleName)
    return @($script:State.GraphSp.AppRoles | Where-Object { $_.Value -eq $RoleName }) | Select-Object -First 1
}

# ----- input resolution -------------------------------------------------------

function Read-NeologikJsonFile {
    # Reads and parses a JSON input file; a missing, empty or malformed file
    # is an input error with the file named.
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw [System.ArgumentException]::new("$Label not found: $Path")
    }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw [System.ArgumentException]::new("$Label is empty: $Path")
    }
    try {
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        throw [System.ArgumentException]::new("$Label is not valid JSON ($Path): $(Get-NeologikErrorText $_)")
    }
}

function Resolve-NeologikInput {
    <#
    Resolves every input from the configuration file and the explicit
    parameters, validates ids and input files, and fills $script:State.
    Every problem is reported as an ArgumentException with the exact
    correction for the operator.
    #>
    param([hashtable]$Parameters)
    $state = $script:State
    foreach ($name in @('ConfigurationFile', 'Phase', 'TenantId', 'DeploySpClientId', 'SignInAppClientId', 'NceUserGroupId',
            'SubscriptionId', 'ResourceGroupName', 'BlueprintKey', 'AgentGrantsFile', 'MailboxGrantsFile')) {
        $state[$name] = [string](Get-NeologikProperty $Parameters $name '')
    }
    if (-not $state.Phase) { $state.Phase = 'Window' }
    if (-not $state.BlueprintKey) { $state.BlueprintKey = 'default' }
    $state.RemoveLegacyGrantAppIds = @(Get-NeologikProperty $Parameters 'RemoveLegacyGrantAppIds' @() | Where-Object { $_ })
    $state.UseAzureCliToken = [bool](Get-NeologikProperty $Parameters 'UseAzureCliToken' $false)
    $state.Config = $null
    $state.ShortName = ''
    $state.AgentGrants = $null
    $state.MailboxGrants = @()

    if ($state.ConfigurationFile) {
        $config = Read-NeologikJsonFile -Path $state.ConfigurationFile -Label 'Configuration file'
        if ($config -is [System.Array] -or $null -eq $config) {
            throw [System.ArgumentException]::new("Configuration file is not the onboarding configuration JSON (expected an object with TenantId and AppRegistration): $($state.ConfigurationFile)")
        }
        $state.Config = $config
        if (-not $state.TenantId) { $state.TenantId = [string](Get-NeologikProperty $config 'TenantId' '') }
        if (-not $state.SubscriptionId) { $state.SubscriptionId = [string](Get-NeologikProperty $config 'SubscriptionId' '') }
        if (-not $state.ResourceGroupName) { $state.ResourceGroupName = [string](Get-NeologikProperty $config 'ResourceGroupName' '') }
        if (-not $state.DeploySpClientId) {
            $state.DeploySpClientId = [string](Get-NeologikProperty (Get-NeologikProperty $config 'AppRegistration') 'ClientId' '')
        }
        if (-not $state.SignInAppClientId) {
            $state.SignInAppClientId = [string](Get-NeologikProperty (Get-NeologikProperty $config 'NceAuthApp') 'ClientId' '')
        }
        if (-not $state.NceUserGroupId) {
            $nceGroup = @(@(Get-NeologikProperty $config 'SecurityGroups' @()) | Where-Object {
                    [string](Get-NeologikProperty $_ 'Name' '') -match 'NCE User Group|Harness User Group'
                }) | Select-Object -First 1
            if ($nceGroup) { $state.NceUserGroupId = [string](Get-NeologikProperty $nceGroup 'Id' '') }
        }
        $state.ShortName = [string](Get-NeologikProperty $config 'SolutionShortName' '')
        Write-Log "Configuration loaded: $(Get-NeologikProperty $config 'OrganizationName' '') ($($state.ShortName))" -Level Info
    }

    foreach ($required in @(
            @{ Name = 'TenantId'; Value = $state.TenantId },
            @{ Name = 'DeploySpClientId'; Value = $state.DeploySpClientId })) {
        if (-not $required.Value) {
            throw [System.ArgumentException]::new("$($required.Name) could not be resolved - pass it explicitly or supply -ConfigurationFile.")
        }
    }
    foreach ($idCheck in @(
            @{ Name = 'TenantId'; Value = $state.TenantId },
            @{ Name = 'DeploySpClientId'; Value = $state.DeploySpClientId },
            @{ Name = 'SignInAppClientId'; Value = $state.SignInAppClientId },
            @{ Name = 'NceUserGroupId'; Value = $state.NceUserGroupId },
            @{ Name = 'SubscriptionId'; Value = $state.SubscriptionId })) {
        if ($idCheck.Value -and -not (Test-NeologikGuid $idCheck.Value)) {
            throw [System.ArgumentException]::new("$($idCheck.Name) must be a GUID (got '$($idCheck.Value)').")
        }
    }
    if ($state.Phase -eq 'PostWindow' -and (-not $state.SubscriptionId -or -not $state.ResourceGroupName)) {
        throw [System.ArgumentException]::new('PostWindow needs SubscriptionId and ResourceGroupName - pass them explicitly or supply -ConfigurationFile.')
    }
    foreach ($legacyAppId in $state.RemoveLegacyGrantAppIds) {
        if (-not (Test-NeologikGuid $legacyAppId)) {
            throw [System.ArgumentException]::new("RemoveLegacyGrantAppIds must be application id GUIDs (got '$legacyAppId').")
        }
    }

    if ($state.AgentGrantsFile) {
        $grantsFile = Read-NeologikJsonFile -Path $state.AgentGrantsFile -Label 'Agent grants file'
        if ($grantsFile -is [System.Array] -or $null -eq $grantsFile -or $null -eq (Get-NeologikProperty $grantsFile 'grants')) {
            throw [System.ArgumentException]::new("Agent grants file is not the platform export (expected an object with 'grants', 'componentGraphRoles' and 'sharePointIngestion'): $($state.AgentGrantsFile)")
        }
        $fileTenant = [string](Get-NeologikProperty $grantsFile 'tenantId' '')
        if ($fileTenant -and $fileTenant -ne $state.TenantId) {
            throw [System.ArgumentException]::new("Agent grants file was exported from tenant $fileTenant but this run targets tenant $($state.TenantId) - export the file from the environment in this tenant.")
        }
        $entries = @(Get-NeologikProperty $grantsFile 'grants' @())
        foreach ($entry in $entries) {
            $name = [string](Get-NeologikProperty $entry 'name' '(unnamed)')
            if ([string](Get-NeologikProperty $entry 'status' '') -ne 'ready') { continue }
            $clientId = [string](Get-NeologikProperty $entry 'identityClientId' '')
            $userId = [string](Get-NeologikProperty $entry 'agentUserObjectId' '')
            if (-not (Test-NeologikGuid $clientId) -or -not (Test-NeologikGuid $userId)) {
                throw [System.ArgumentException]::new("Agent grants file: identityClientId and agentUserObjectId must be GUIDs ($name).")
            }
            $scopes = @(@(Get-NeologikProperty $entry 'scopes' @()) | ForEach-Object { [string]$_ } | Where-Object { $_.Trim() })
            if ($scopes.Count -eq 0) {
                throw [System.ArgumentException]::new("Agent grants file: every ready entry needs scopes ($name).")
            }
        }
        $state.AgentGrants = $grantsFile
        $componentRoles = @(Get-NeologikProperty $grantsFile 'componentGraphRoles' @())
        $sharePoint = [bool](Get-NeologikProperty $grantsFile 'sharePointIngestion' $false)
        Write-Log "Agent grants loaded: $($entries.Count) agent/app entries, $($componentRoles.Count) component role(s), SharePoint ingestion: $sharePoint" -Level Info
        foreach ($warning in @(Get-NeologikProperty $grantsFile 'warnings' @() | Where-Object { $_ })) {
            Write-Log "  export warning: $warning" -Level Warning
        }
    }

    if ($state.MailboxGrantsFile) {
        $mailboxFile = Read-NeologikJsonFile -Path $state.MailboxGrantsFile -Label 'Mailbox grants file'
        $mailboxEntries = @()
        foreach ($entry in @($mailboxFile)) {
            foreach ($field in @('IdentityAppId', 'IdentityObjectId', 'Mailbox', 'DisplayName')) {
                if (-not [string](Get-NeologikProperty $entry $field '')) {
                    throw [System.ArgumentException]::new("Mailbox grants file: every entry needs $field.")
                }
            }
            $display = [string](Get-NeologikProperty $entry 'DisplayName')
            if (-not (Test-NeologikGuid ([string](Get-NeologikProperty $entry 'IdentityAppId'))) -or
                -not (Test-NeologikGuid ([string](Get-NeologikProperty $entry 'IdentityObjectId')))) {
                throw [System.ArgumentException]::new("Mailbox grants file: IdentityAppId and IdentityObjectId must be GUIDs ($display).")
            }
            $mailbox = [string](Get-NeologikProperty $entry 'Mailbox')
            if ($mailbox -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
                throw [System.ArgumentException]::new("Mailbox grants file: '$mailbox' is not a mailbox address.")
            }
            if ($display -match "[`"'`r`n]") {
                throw [System.ArgumentException]::new("Mailbox grants file: DisplayName '$display' must not contain quotes.")
            }
            $mailboxEntries += [pscustomobject]@{
                IdentityAppId    = [string](Get-NeologikProperty $entry 'IdentityAppId')
                IdentityObjectId = [string](Get-NeologikProperty $entry 'IdentityObjectId')
                Mailbox          = $mailbox.Trim().ToLowerInvariant()
                DisplayName      = $display
            }
        }
        $state.MailboxGrants = $mailboxEntries
        Write-Log "Mailbox grants loaded: $($mailboxEntries.Count) email channel(s)" -Level Info
    }
}

function Test-NeologikPowerShellVersion {
    param([version]$Version = $PSVersionTable.PSVersion)
    if ($Version -lt [version]'7.4') {
        Write-ActionRequired "PowerShell 7.4 or later is required (current: $Version).`nInstall it from https://aka.ms/powershell and run this script from 'pwsh', not 'powershell'."
        return $false
    }
    return $true
}

function Write-NeologikHeader {
    $state = $script:State
    Write-Host ''
    Write-Host '=============================================================' -ForegroundColor Cyan
    Write-Host " Neologik environment access - phase: $($state.Phase)" -ForegroundColor Cyan
    Write-Host '=============================================================' -ForegroundColor Cyan
    Write-Host "  Tenant:              $($state.TenantId)"
    Write-Host "  Deployment identity: $($state.DeploySpClientId)"
    if ($state.SignInAppClientId) { Write-Host "  Sign-in app:         $($state.SignInAppClientId)" }
    if ($state.NceUserGroupId) { Write-Host "  NCE user group:      $($state.NceUserGroupId)" }
    if ($state.AgentGrants) { Write-Host "  Agent grants file:   $($state.AgentGrantsFile)" }
    if ($state.MailboxGrants.Count -gt 0) { Write-Host "  Mailbox grants:      $($state.MailboxGrants.Count)" }
    if ($state.RemoveLegacyGrantAppIds.Count -gt 0) { Write-Host "  Legacy grants to remove: $($state.RemoveLegacyGrantAppIds -join ', ')" }
    if ($state.Phase -eq 'PostWindow') {
        Write-Host "  Subscription:        $($state.SubscriptionId)"
        Write-Host "  Resource group:      $($state.ResourceGroupName)"
    }
    Write-Host ''
}

# ----- modules + sign-in ------------------------------------------------------

function Import-NeologikModuleSet {
    <#
    Ensures a set of modules is installed (at or above a minimum version)
    and imports ONE consistent version of all of them: mixed Microsoft.Graph
    module versions fail at import with an assembly conflict, the most
    common cause of a broken run on an administrator's workstation.
    Returns $true, or $false after printing what to do.
    #>
    param([string[]]$Names, [version]$MinimumVersion, [string]$InstallHint)
    try {
        foreach ($name in $Names) {
            $versions = @(Get-NeologikAvailableModuleVersion -Name $name | Where-Object { $_ -ge $MinimumVersion })
            if ($versions.Count -eq 0) {
                Write-Log "Installing module $name (first run only)..." -Level Info
                Install-NeologikModule -Name $name -MinimumVersion $MinimumVersion
            }
        }
        # A version already loaded in this session pins the choice; otherwise
        # the highest version every module has in common.
        $target = $null
        foreach ($name in $Names) {
            $loaded = Get-NeologikLoadedModuleVersion -Name $name
            if ($loaded) { $target = $loaded; break }
        }
        if (-not $target) {
            $common = $null
            foreach ($name in $Names) {
                $versions = @(Get-NeologikAvailableModuleVersion -Name $name | Where-Object { $_ -ge $MinimumVersion })
                $common = if ($null -eq $common) { $versions } else { @($common | Where-Object { $versions -contains $_ }) }
            }
            $target = @($common | Sort-Object -Descending) | Select-Object -First 1
        }
        foreach ($name in $Names) {
            if ($target) { Import-NeologikModule -Name $name -RequiredVersion $target }
            else { Import-NeologikModule -Name $name }
        }
        return $true
    }
    catch {
        Write-Log "PowerShell module set-up failed: $(Get-NeologikErrorText $_)" -Level Error
        Write-ActionRequired "The PowerShell modules this script needs could not be installed or loaded.`nIn a new PowerShell 7 window run:`n  $InstallHint`nthen run this script again."
        return $false
    }
}

function Get-NeologikGraphScope {
    $state = $script:State
    $scopes = @('Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'Directory.Read.All', 'User.Read',
        'DelegatedPermissionGrant.Read.All', 'AgentIdentityBlueprint.Create', 'AgentIdentityBlueprint.AddRemoveCreds.All',
        'AgentIdentityBlueprintPrincipal.Create')
    if ($state.AgentGrants) {
        # The agent-user grants are oAuth2PermissionGrants - a write scope only
        # a Global Administrator holds (the deployment identity never does).
        $scopes += 'DelegatedPermissionGrant.ReadWrite.All'
    }
    if ($state.Phase -eq 'PostWindow') {
        $scopes += 'RoleManagement.ReadWrite.Directory'
    }
    return $scopes
}

function Connect-NeologikGraph {
    # Signs in to Microsoft Graph and checks the session is in the expected
    # tenant. Returns $true, or $false after printing what to do.
    $state = $script:State
    $scopes = Get-NeologikGraphScope
    try {
        if ($state.UseAzureCliToken) {
            Write-Log 'Signing in to Microsoft Graph with the Azure CLI session token (az account get-access-token)...' -Level Info
            if (-not (Test-NeologikCommand -Name 'az')) {
                Write-ActionRequired "The Azure CLI (az) is not installed on this machine. Install it, sign in (az login --tenant $($state.TenantId)), or run the script without -UseAzureCliToken."
                return $false
            }
            $cli = Invoke-NeologikAzureCli -Arguments @('account', 'get-access-token', '--resource-type', 'ms-graph', '--tenant', $state.TenantId, '--query', 'accessToken', '-o', 'tsv')
            $cliToken = [string](@($cli.Output) | Where-Object { $_ -and $_.Trim() } | Select-Object -Last 1)
            if ($cli.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($cliToken)) {
                Write-ActionRequired "az account get-access-token failed for tenant $($state.TenantId).`nSign in first: az login --tenant $($state.TenantId) --scope https://graph.microsoft.com//.default`nthen run this script again (or run it without -UseAzureCliToken for the device-code sign-in)."
                return $false
            }
            Connect-MgGraph -AccessToken (ConvertTo-SecureString -String $cliToken.Trim() -AsPlainText -Force) -NoWelcome -ErrorAction Stop
        }
        else {
            Write-Log 'Signing in to Microsoft Graph (device code - use your Global Administrator account)...' -Level Info
            Connect-MgGraph -TenantId $state.TenantId -Scopes $scopes -UseDeviceCode -NoWelcome -ErrorAction Stop
        }
    }
    catch {
        Write-Log "Microsoft Graph sign-in failed: $(Get-NeologikErrorText $_)" -Level Error
        Write-ActionRequired "Sign in to Microsoft Graph did not complete.`nRun the script again and finish the device-code sign-in within 120 seconds with a Global Administrator account of tenant $($state.TenantId), approving the requested permissions."
        return $false
    }
    $context = $null
    try { $context = Get-MgContext -ErrorAction Stop } catch { $context = $null }
    if (-not $context) {
        Write-ActionRequired "No Microsoft Graph session was established. Run the script again and complete the sign-in."
        return $false
    }
    $contextTenant = [string](Get-NeologikProperty $context 'TenantId' '')
    if ($contextTenant -and $contextTenant -ne $state.TenantId) {
        Write-ActionRequired "The sign-in landed in tenant $contextTenant but this environment lives in tenant $($state.TenantId).`nRun 'Disconnect-MgGraph', then run the script again and sign in with a Global Administrator account of tenant $($state.TenantId)."
        return $false
    }
    $account = [string](Get-NeologikProperty $context 'Account' '')
    if ($account) { Write-Log "Signed in as $account (tenant $($state.TenantId))" -Level Info }
    $granted = @(Get-NeologikProperty $context 'Scopes' @())
    if ($granted.Count -gt 0) {
        $missing = @($scopes | Where-Object { $granted -notcontains $_ })
        if ($missing.Count -gt 0) {
            Write-Log "  the session lacks the permission(s) $($missing -join ', ') - items that need them will be reported as failed" -Level Warning
        }
    }
    return $true
}

function Resolve-NeologikPrincipal {
    # The deployment identity and the Microsoft Graph service principal -
    # nothing can be verified without them.
    $state = $script:State
    try {
        $deploySp = @(Get-MgServicePrincipal -Filter "appId eq '$($state.DeploySpClientId)'" -ErrorAction Stop) | Select-Object -First 1
    }
    catch {
        Write-Log "Could not read the deployment identity: $(Get-NeologikErrorText $_)" -Level Error
        Add-Summary 'Deployment identity' "FAILED - $(Get-NeologikErrorText $_)"
        return $false
    }
    if (-not $deploySp) {
        Write-Log "Deployment service principal not found for client id $($state.DeploySpClientId) in tenant $($state.TenantId)." -Level Error
        Add-Summary 'Deployment identity' 'MISSING - service principal not found'
        Write-ActionRequired "The deployment identity (client id $($state.DeploySpClientId)) does not exist in tenant $($state.TenantId).`nCheck the configuration file or the -DeploySpClientId value with Neologik before running again."
        return $false
    }
    $state.DeploySp = $deploySp
    Write-Log "Deployment identity: '$($deploySp.DisplayName)'" -Level Info
    try {
        $graphSp = @(Get-MgServicePrincipal -Filter "appId eq '$script:GraphSpAppId'" -ErrorAction Stop) | Select-Object -First 1
    }
    catch {
        Write-Log "Could not read the Microsoft Graph service principal: $(Get-NeologikErrorText $_)" -Level Error
        Add-Summary 'Microsoft Graph service principal' "FAILED - $(Get-NeologikErrorText $_)"
        return $false
    }
    if (-not $graphSp) {
        Add-Summary 'Microsoft Graph service principal' 'MISSING - report to Neologik'
        Write-Log 'The Microsoft Graph service principal is missing from this tenant - report this to Neologik.' -Level Error
        return $false
    }
    $state.GraphSp = $graphSp
    return $true
}

# ----- Graph app roles ---------------------------------------------------------

function Grant-NeologikGraphAppRole {
    <#
    Ensures a set of Graph application roles on one principal. Each role is
    verified and granted independently; the result records how many were
    newly granted and whether every role is now held.
    #>
    param([string]$PrincipalId, [string]$Label, [string[]]$RoleNames)
    $graphSp = $script:State.GraphSp
    $outcome = @{ Granted = 0; Failed = 0; Complete = $true }
    $existing = @()
    try {
        $existing = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalId -All -ErrorAction Stop |
            Where-Object { $_.ResourceId -eq $graphSp.Id })
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  could not read the role assignments of $Label`: $reason" -Level Error
        foreach ($roleName in $RoleNames) { Add-Summary "$Label role: $roleName" "FAILED - $reason" }
        $outcome.Failed = $RoleNames.Count
        $outcome.Complete = $false
        return $outcome
    }
    foreach ($roleName in $RoleNames) {
        $role = Get-NeologikGraphAppRole -RoleName $roleName
        if (-not $role) {
            Write-Log "  role '$roleName' not published by Microsoft Graph in this cloud - report this to Neologik" -Level Warning
            Add-Summary "$Label role: $roleName" 'NOT FOUND - report'
            $outcome.Complete = $false
            continue
        }
        if (@($existing | Where-Object { $_.AppRoleId -eq $role.Id }).Count -gt 0) {
            Write-Log "  $roleName - already granted" -Level Success
            Add-Summary "$Label role: $roleName" 'Already granted'
            continue
        }
        try {
            New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalId `
                -PrincipalId $PrincipalId -ResourceId $graphSp.Id -AppRoleId $role.Id -ErrorAction Stop | Out-Null
            Write-Log "  $roleName - GRANTED" -Level Success
            Add-Summary "$Label role: $roleName" 'Granted'
            $outcome.Granted++
        }
        catch {
            $reason = Get-NeologikErrorText $_
            if ($reason -match '(?i)already exists|Permission being assigned already exists') {
                Write-Log "  $roleName - already granted" -Level Success
                Add-Summary "$Label role: $roleName" 'Already granted'
                continue
            }
            if (Test-NeologikPrivilegeError $_) {
                $reason = 'insufficient privileges - sign in as a Global Administrator'
            }
            Write-Log "  $roleName - FAILED ($reason)" -Level Error
            Add-Summary "$Label role: $roleName" "FAILED - $reason"
            $outcome.Failed++
            $outcome.Complete = $false
        }
    }
    return $outcome
}

# ----- agent-user delegated grants (project#2213) --------------------------

function Get-NeologikAgentUserGrant {
    # The one delegated grant client -> agent user on Microsoft Graph.
    param([string]$IdentityObjectId, [string]$AgentUserObjectId)
    $graphSp = $script:State.GraphSp
    $uri = "$script:GraphV1/oauth2PermissionGrants?`$filter=clientId eq '$IdentityObjectId' and principalId eq '$AgentUserObjectId' and resourceId eq '$($graphSp.Id)'"
    return @(Get-NeologikGraphCollection -Uri $uri) | Select-Object -First 1
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
    $graphSp = $script:State.GraphSp
    try {
        $identity = @(Get-NeologikGraphCollection -Uri "$script:GraphBeta/servicePrincipals?`$filter=appId eq '$IdentityClientId'&`$select=id") | Select-Object -First 1
        if (-not $identity) {
            Write-Log "  $Kind '$Name': agent identity $IdentityClientId not found - re-run the platform provisioning, then this script" -Level Warning
            Add-Summary $label 'MISSING - agent identity not found'
            return
        }
        $identityId = [string](Get-NeologikProperty $identity 'id')
        $desired = Get-NeologikScopeSet ($Scopes -join ' ')
        $existing = Get-NeologikAgentUserGrant -IdentityObjectId $identityId -AgentUserObjectId $AgentUserObjectId
        if ($existing -and (Get-NeologikScopeSet ([string](Get-NeologikProperty $existing 'scope' ''))) -eq $desired) {
            Write-Log "  $Kind '$Name' - grant already present ($desired)" -Level Success
            Add-Summary $label 'Already granted'
            return
        }
        $words = @($desired -split ' ' | Where-Object { $_ })
        $applied = $false
        $denied = $false
        for ($attempt = 0; $attempt -lt 3 -and -not $applied -and -not $denied; $attempt++) {
            $k = if ($words.Count -gt 0) { $attempt % $words.Count } else { 0 }
            $rotated = @($words[$k..($words.Count - 1)])
            if ($k -gt 0) { $rotated += @($words[0..($k - 1)]) }
            $scopeTry = ($rotated | Where-Object { $_ }) -join ' '
            try {
                if ($existing) {
                    $null = Invoke-NeologikGraph -Method PATCH -Uri "$script:GraphV1/oauth2PermissionGrants/$(Get-NeologikProperty $existing 'id')" `
                        -Body (@{ scope = $scopeTry } | ConvertTo-Json -Compress)
                }
                else {
                    $body = @{ clientId = $identityId; consentType = 'Principal'; principalId = $AgentUserObjectId
                               resourceId = $graphSp.Id; scope = $scopeTry } | ConvertTo-Json -Compress
                    $null = Invoke-NeologikGraph -Method POST -Uri "$script:GraphV1/oauth2PermissionGrants" -Body $body
                }
                $applied = $true
            }
            catch {
                if (Test-NeologikPrivilegeError $_) {
                    $denied = $true
                    Write-Log "  $Kind '$Name' - the directory refused the write: $(Get-NeologikErrorText $_)" -Level Error
                }
                else {
                    Write-Log "  attempt $($attempt + 1) refused scope string '$scopeTry': $(Get-NeologikErrorText $_)" -Level Warning
                }
            }
        }
        if ($denied) {
            Add-Summary $label 'FAILED - insufficient privileges (Global Administrator with DelegatedPermissionGrant.ReadWrite.All needed)'
            return
        }
        $readback = Get-NeologikAgentUserGrant -IdentityObjectId $identityId -AgentUserObjectId $AgentUserObjectId
        if ($readback -and (Get-NeologikScopeSet ([string](Get-NeologikProperty $readback 'scope' ''))) -eq $desired) {
            Write-Log "  $Kind '$Name' - GRANTED ($desired)" -Level Success
            Add-Summary $label $(if ($existing) { "Updated ($desired)" } else { "Granted ($desired)" })
        }
        else {
            Write-Log "  $Kind '$Name' - the scope set '$desired' did not land after 3 attempts; report the string to Neologik" -Level Error
            Add-Summary $label 'PENDING - scope refused, report'
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  $Kind '$Name' - FAILED ($reason)" -Level Error
        Add-Summary $label "FAILED - $reason"
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
    try {
        $escaped = $IdentityName -replace "'", "''"
        $sp = @(Get-NeologikGraphCollection -Uri "$script:GraphV1/servicePrincipals?`$filter=displayName eq '$escaped'&`$select=id") | Select-Object -First 1
        if (-not $sp) {
            Write-Log "  workload identity '$IdentityName' not found - provision the app first" -Level Warning
            Add-Summary $label 'MISSING - identity not found'
            return
        }
        $null = Grant-NeologikGraphAppRole -PrincipalId ([string](Get-NeologikProperty $sp 'id')) -Label "Component $App" -RoleNames @($RoleName)
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  $App '$RoleName' - FAILED ($reason)" -Level Error
        Add-Summary $label "FAILED - $reason"
    }
}

# ----- shared-mailbox grants (email channels, project#990) ---------------------

function Get-NeologikExchangeServicePrincipal {
    param([string]$Identity)
    try { return (Get-ServicePrincipal -Identity $Identity -ErrorAction SilentlyContinue) } catch { return $null }
}

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
    try {
        $sp = Get-NeologikExchangeServicePrincipal -Identity $IdentityAppId
        if (-not $sp) {
            $sp = New-ServicePrincipal -AppId $IdentityAppId -ObjectId $IdentityObjectId -DisplayName $DisplayName -ErrorAction Stop
            Write-Log "  service principal pointer created: $DisplayName" -Level Success
        }
        $scopeName = "Scope-$DisplayName"
        $scope = $null
        try { $scope = Get-ManagementScope -Identity $scopeName -ErrorAction SilentlyContinue } catch { $scope = $null }
        if (-not $scope) {
            $scope = @(Get-ManagementScope -ErrorAction Stop | Where-Object { [string](Get-NeologikProperty $_ 'RecipientFilter' '') -like "*$Mailbox*" }) | Select-Object -First 1
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
            $assignment = $null
            try { $assignment = Get-ManagementRoleAssignment -Identity $assignmentName -ErrorAction SilentlyContinue } catch { $assignment = $null }
            if ($assignment) { continue }
            New-ManagementRoleAssignment -Name $assignmentName -App $IdentityObjectId -Role $role.Role `
                -CustomResourceScope $scope.Name -ErrorAction Stop | Out-Null
            $granted++
        }
        $inScope = @()
        try {
            $inScope = @(Test-ServicePrincipalAuthorization -Identity $IdentityObjectId -Resource $Mailbox -ErrorAction Stop |
                Where-Object { [bool](Get-NeologikProperty $_ 'InScope' $false) })
        }
        catch {
            Write-Log "  $Mailbox -> $DisplayName - $granted role(s) added; the authorisation test could not run yet ($(Get-NeologikErrorText $_)) - re-run to confirm" -Level Warning
            Add-Summary $label 'PENDING - re-run to confirm InScope'
            return
        }
        if ($inScope.Count -ge 3) {
            Write-Log "  $Mailbox -> $DisplayName - in scope for $($inScope.Count) role(s)" -Level Success
            Add-Summary $label $(if ($granted -gt 0) { "Granted ($granted role(s) added)" } else { 'Already granted' })
        }
        else {
            Write-Log "  $Mailbox -> $DisplayName - $granted role(s) added; Exchange reports $($inScope.Count) in scope (propagation can take up to two hours - re-run to confirm)" -Level Warning
            Add-Summary $label 'PENDING - re-run to confirm InScope'
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  $Mailbox -> $DisplayName - FAILED ($reason)" -Level Error
        Add-Summary $label "FAILED - $reason"
    }
}

function Get-NeologikExchangeAssignment {
    # Every Exchange role assignment held by a service principal pointer.
    param($ServicePrincipal)
    $assignments = @()
    try {
        $assignments = @(Get-ManagementRoleAssignment -RoleAssignee $ServicePrincipal.Identity -ErrorAction Stop)
    }
    catch {
        $assignments = @()
    }
    if ($assignments.Count -eq 0) {
        # Fallback: match the assignee by any of the pointer's identifiers.
        $ids = @(
            [string](Get-NeologikProperty $ServicePrincipal 'ObjectId' ''),
            [string](Get-NeologikProperty $ServicePrincipal 'AppId' ''),
            [string](Get-NeologikProperty $ServicePrincipal 'DisplayName' ''),
            [string](Get-NeologikProperty $ServicePrincipal 'Identity' '')
        ) | Where-Object { $_ }
        $assignments = @(Get-ManagementRoleAssignment -ErrorAction Stop | Where-Object {
                $ids -contains [string](Get-NeologikProperty $_ 'RoleAssigneeName' '')
            })
    }
    return , $assignments
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
    try {
        $sp = Get-NeologikExchangeServicePrincipal -Identity $LegacyAppId
        if (-not $sp) {
            Write-Log "  legacy identity $LegacyAppId - no Exchange service principal (nothing to remove)" -Level Success
            Add-Summary $label 'Not present'
            return
        }
        $assignments = @(Get-NeologikExchangeAssignment -ServicePrincipal $sp)
        foreach ($assignment in $assignments) {
            Remove-ManagementRoleAssignment -Identity $assignment.Name -Confirm:$false -ErrorAction Stop
        }
        Remove-ServicePrincipal -Identity $sp.Identity -Confirm:$false -ErrorAction Stop
        Write-Log "  legacy identity $LegacyAppId - $($assignments.Count) assignment(s) and the pointer REMOVED" -Level Success
        Add-Summary $label "Removed ($($assignments.Count) assignment(s))"
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  legacy identity $LegacyAppId - FAILED ($reason)" -Level Error
        Add-Summary $label "FAILED - $reason"
    }
}

# ----- Window phase steps -----------------------------------------------------

function Set-NeologikAgentBlueprint {
    <#
    Step 1a-1c: the agent identity blueprint, its ownership, its principal,
    the principal's Graph role and the GitHub OIDC credentials. Each item is
    independent once the blueprint exists; when the blueprint itself cannot
    be resolved the dependents are recorded as skipped.
    #>
    $state = $script:State
    $deploySp = $state.DeploySp
    $graph = $script:GraphV1
    $graphBeta = $script:GraphBeta

    Write-Log 'Step 1a/4: agent identity blueprint' -Level Info
    $shortName = $state.ShortName
    if (-not $shortName) {
        # Derive from the deployment identity's name ('Neologik GitHub Service Connection - <short>').
        $shortName = ([string]$deploySp.DisplayName -split ' - ')[-1].Trim()
    }
    $blueprintName = "Neologik Agent Blueprint - $($state.BlueprintKey) - $shortName"
    $escaped = $blueprintName -replace "'", "''"
    $blueprint = $null
    $created = $false
    try {
        $blueprint = @(Get-NeologikGraphCollection -Uri "$graph/applications?`$filter=displayName eq '$escaped'&`$select=id,appId") | Select-Object -First 1
        if ($blueprint) {
            Write-Log "  blueprint '$blueprintName' - present (Client ID $(Get-NeologikProperty $blueprint 'appId'))" -Level Success
            Add-Summary 'Agent blueprint' 'Present'
        }
        else {
            $sponsor = [string](Get-NeologikProperty (Invoke-NeologikGraph -Method GET -Uri "$graph/me?`$select=id") 'id' '')
            if (-not $sponsor) { throw 'the signed-in user could not be resolved as the blueprint sponsor' }
            $body = @{
                '@odata.type'         = 'Microsoft.Graph.AgentIdentityBlueprint'
                displayName           = $blueprintName
                'sponsors@odata.bind' = @("$graph/users/$sponsor")
                'owners@odata.bind'   = @("$graph/directoryObjects/$($deploySp.Id)")
            } | ConvertTo-Json -Depth 5 -Compress
            $blueprint = Invoke-NeologikGraph -Method POST -Uri "$graph/applications/microsoft.graph.agentIdentityBlueprint" `
                -Headers $script:OdataHeaders -Body $body
            $created = $true
            Write-Log "  blueprint '$blueprintName' - CREATED (Client ID $(Get-NeologikProperty $blueprint 'appId'); sponsor = you)" -Level Success
            Add-Summary 'Agent blueprint' 'Created'
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        if (Test-NeologikPrivilegeError $_) { $reason = "insufficient privileges ($reason)" }
        Write-Log "  blueprint '$blueprintName' - FAILED ($reason)" -Level Error
        Add-Summary 'Agent blueprint' "FAILED - $reason"
        $blueprint = $null
    }
    if (-not $blueprint) {
        foreach ($item in @('Blueprint owner', 'Blueprint principal', 'Blueprint principal owner', 'Blueprint principal role', 'Blueprint credentials')) {
            Add-Summary $item 'SKIPPED - blueprint not available'
        }
        return
    }
    $blueprintObjectId = [string](Get-NeologikProperty $blueprint 'id')
    $blueprintAppId = [string](Get-NeologikProperty $blueprint 'appId')

    # Blueprint ownership by the deployment identity.
    try {
        $owners = @(Get-NeologikGraphCollection -Uri "$graph/applications/$blueprintObjectId/owners?`$select=id" -RetryNotFound:$created)
        if (@($owners | ForEach-Object { [string](Get-NeologikProperty $_ 'id' '') }) -contains $deploySp.Id) {
            Write-Log '  deployment identity owns the blueprint - already' -Level Success
            Add-Summary 'Blueprint owner' 'Already in place'
        }
        else {
            $ref = @{ '@odata.id' = "$graph/directoryObjects/$($deploySp.Id)" } | ConvertTo-Json -Compress
            try {
                $null = Invoke-NeologikGraph -Method POST -Uri "$graph/applications/$blueprintObjectId/owners/`$ref" -Body $ref -RetryNotFound:$created
                Write-Log '  deployment identity owns the blueprint - ADDED' -Level Success
                Add-Summary 'Blueprint owner' 'Added'
            }
            catch {
                if ((Get-NeologikErrorText $_) -match '(?i)already exist') {
                    Write-Log '  deployment identity owns the blueprint - already' -Level Success
                    Add-Summary 'Blueprint owner' 'Already in place'
                }
                else { throw }
            }
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  blueprint owner - FAILED ($reason)" -Level Error
        Add-Summary 'Blueprint owner' "FAILED - $reason"
    }

    # Blueprint principal (get-or-create by appId; a create fired within
    # seconds of the application's creation is rejected until it replicates).
    $principal = $null
    $principalCreated = $false
    try {
        $principal = @(Get-NeologikGraphCollection -Uri "$graph/servicePrincipals?`$filter=appId eq '$blueprintAppId'&`$select=id") | Select-Object -First 1
        if ($principal) {
            Write-Log '  blueprint principal - present' -Level Success
            Add-Summary 'Blueprint principal' 'Present'
        }
        else {
            $body = @{ appId = $blueprintAppId } | ConvertTo-Json -Compress
            for ($attempt = 1; $attempt -le 10; $attempt++) {
                try {
                    $principal = Invoke-NeologikGraph -Method POST -Uri "$graph/servicePrincipals/microsoft.graph.agentIdentityBlueprintPrincipal" `
                        -Headers $script:OdataHeaders -Body $body
                    break
                }
                catch {
                    $status = Get-NeologikHttpStatus $_
                    if ($attempt -lt 10 -and (($status -in @(400, 404)) -or ((Get-NeologikErrorText $_) -match 'local tenant|does not exist'))) {
                        Write-Log "  blueprint not yet replicated - retrying in 15 seconds ($attempt of 10)" -Level Warning
                        Start-Sleep -Seconds 15
                        continue
                    }
                    throw
                }
            }
            $principalCreated = $true
            Write-Log '  blueprint principal - CREATED' -Level Success
            Add-Summary 'Blueprint principal' 'Created'
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  blueprint principal - FAILED ($reason)" -Level Error
        Add-Summary 'Blueprint principal' "FAILED - $reason"
        $principal = $null
    }
    if ($principal) {
        $principalId = [string](Get-NeologikProperty $principal 'id')
        try {
            $spOwners = @(Get-NeologikGraphCollection -Uri "$graph/servicePrincipals/$principalId/owners?`$select=id" -RetryNotFound:$principalCreated)
            if (@($spOwners | ForEach-Object { [string](Get-NeologikProperty $_ 'id' '') }) -contains $deploySp.Id) {
                Write-Log '  deployment identity owns the blueprint principal - already' -Level Success
                Add-Summary 'Blueprint principal owner' 'Already in place'
            }
            else {
                $ref = @{ '@odata.id' = "$graph/directoryObjects/$($deploySp.Id)" } | ConvertTo-Json -Compress
                try {
                    $null = Invoke-NeologikGraph -Method POST -Uri "$graph/servicePrincipals/$principalId/owners/`$ref" -Body $ref -RetryNotFound:$principalCreated
                    Write-Log '  deployment identity owns the blueprint principal - ADDED' -Level Success
                    Add-Summary 'Blueprint principal owner' 'Added'
                }
                catch {
                    if ((Get-NeologikErrorText $_) -match '(?i)already exist') {
                        Write-Log '  deployment identity owns the blueprint principal - already' -Level Success
                        Add-Summary 'Blueprint principal owner' 'Already in place'
                    }
                    else { throw }
                }
            }
        }
        catch {
            $reason = Get-NeologikErrorText $_
            Write-Log "  blueprint principal owner - FAILED ($reason)" -Level Error
            Add-Summary 'Blueprint principal owner' "FAILED - $reason"
        }

        Write-Log 'Step 1b/4: blueprint principal Graph role' -Level Info
        $null = Grant-NeologikGraphAppRole -PrincipalId $principalId -Label 'Blueprint principal' -RoleNames $script:BlueprintPrincipalGraphRoles
    }
    else {
        Add-Summary 'Blueprint principal owner' 'SKIPPED - principal not available'
        Add-Summary 'Blueprint principal role' 'SKIPPED - principal not available'
    }

    Write-Log 'Step 1c/4: GitHub OIDC federated credentials on the blueprint' -Level Info
    $existingNames = $null
    try {
        $existingCreds = @(Get-NeologikGraphCollection -Uri "$graphBeta/applications/$blueprintObjectId/federatedIdentityCredentials?`$select=name" -RetryNotFound:$created)
        $existingNames = @($existingCreds | ForEach-Object { [string](Get-NeologikProperty $_ 'name' '') })
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  federated credentials could not be read - FAILED ($reason)" -Level Error
        Add-Summary 'Blueprint credentials' "FAILED - $reason"
    }
    if ($null -ne $existingNames) {
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
            try {
                $null = Invoke-NeologikGraph -Method POST -Uri "$graphBeta/applications/$blueprintObjectId/federatedIdentityCredentials" -Body $body -RetryNotFound:$created
                Write-Log "  $credName - ADDED" -Level Success
                Add-Summary "Blueprint credential: $credName" 'Added'
            }
            catch {
                $reason = Get-NeologikErrorText $_
                if ($reason -match '(?i)already exist') {
                    Write-Log "  $credName - present" -Level Success
                    Add-Summary "Blueprint credential: $credName" 'Present'
                    continue
                }
                Write-Log "  $credName - FAILED ($reason)" -Level Error
                Add-Summary "Blueprint credential: $credName" "FAILED - $reason"
            }
        }
    }
}

function Set-NeologikDeploymentGraphRole {
    <#
    Step 1d: the deployment identity's Graph roles - retained first, then
    the retired tenant-wide ones removed. The removals run only when every
    retained role is confirmed held, so the pipeline never loses a
    capability in between.
    #>
    $state = $script:State
    $deploySp = $state.DeploySp
    $graphSp = $state.GraphSp
    Write-Log 'Step 1d/4: deployment identity Graph roles (retained, then retired)' -Level Info
    $outcome = Grant-NeologikGraphAppRole -PrincipalId $deploySp.Id -Label 'Graph' -RoleNames $script:RequiredGraphRoles
    if (-not $outcome.Complete) {
        Write-Log '  retained roles are not all in place - the retired roles are left untouched (narrow before broad)' -Level Warning
        foreach ($roleName in $script:RetiredGraphRoles) {
            Add-Summary "Retired Graph role: $roleName" 'SKIPPED - retained roles not all granted'
        }
        return
    }
    $assignments = @()
    try {
        $assignments = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $deploySp.Id -All -ErrorAction Stop |
            Where-Object { $_.ResourceId -eq $graphSp.Id })
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  could not read the deployment identity's role assignments - FAILED ($reason)" -Level Error
        foreach ($roleName in $script:RetiredGraphRoles) { Add-Summary "Retired Graph role: $roleName" "FAILED - $reason" }
        return
    }
    foreach ($roleName in $script:RetiredGraphRoles) {
        $role = Get-NeologikGraphAppRole -RoleName $roleName
        $assignment = if ($role) { @($assignments | Where-Object { $_.AppRoleId -eq $role.Id }) | Select-Object -First 1 } else { $null }
        if (-not $assignment) {
            Write-Log "  $roleName - not held (nothing to remove)" -Level Success
            Add-Summary "Retired Graph role: $roleName" 'Not held'
            continue
        }
        try {
            Remove-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $deploySp.Id -AppRoleAssignmentId $assignment.Id -ErrorAction Stop
            Write-Log "  $roleName - REMOVED (retired, tenant-wide)" -Level Success
            Add-Summary "Retired Graph role: $roleName" 'Removed'
        }
        catch {
            $reason = Get-NeologikErrorText $_
            if ((Get-NeologikHttpStatus $_) -eq 404) {
                Write-Log "  $roleName - not held (nothing to remove)" -Level Success
                Add-Summary "Retired Graph role: $roleName" 'Not held'
                continue
            }
            if (Test-NeologikPrivilegeError $_) { $reason = 'insufficient privileges - sign in as a Global Administrator' }
            Write-Log "  $roleName - FAILED ($reason)" -Level Error
            Add-Summary "Retired Graph role: $roleName" "FAILED - $reason"
        }
    }
    Write-Log "Graph roles complete ($($outcome.Granted) newly granted)" -Level Info
}

function Set-NeologikSignInGroupAssignment {
    # Steps 2 and 3: the NCE user group on the sign-in application, and the
    # tenant-wide admin consent check for that application.
    $state = $script:State
    Write-Log 'Step 2/4: NCE user group assignment to the sign-in application' -Level Info
    if (-not $state.SignInAppClientId -or -not $state.NceUserGroupId) {
        Write-Log '  sign-in app id or NCE user group id not available - SKIPPED. On pre-v5-onboarded environments supply both (the migration email lists them).' -Level Warning
        Add-Summary 'NCE group assignment' 'SKIPPED - ids not supplied'
        return
    }
    $signInSp = $null
    try {
        $signInSp = @(Get-MgServicePrincipal -Filter "appId eq '$($state.SignInAppClientId)'" -ErrorAction Stop) | Select-Object -First 1
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  sign-in application could not be read - FAILED ($reason)" -Level Error
        Add-Summary 'NCE group assignment' "FAILED - $reason"
        Add-Summary 'Admin consent' 'SKIPPED - sign-in application not read'
        return
    }
    if (-not $signInSp) {
        Write-Log "  sign-in application service principal not found for client id $($state.SignInAppClientId) - check the id with Neologik" -Level Error
        Add-Summary 'NCE group assignment' 'MISSING - sign-in application not found'
        Add-Summary 'Admin consent' 'SKIPPED - sign-in application not found'
        return
    }
    Write-Log "  sign-in application: '$($signInSp.DisplayName)'" -Level Info
    try {
        $assignments = @(Get-MgGroupAppRoleAssignment -GroupId $state.NceUserGroupId -All -ErrorAction Stop |
            Where-Object { $_.ResourceId -eq $signInSp.Id })
        if ($assignments.Count -gt 0) {
            Write-Log '  NCE user group - already assigned' -Level Success
            Add-Summary 'NCE group assignment' 'Already assigned'
        }
        else {
            New-MgGroupAppRoleAssignment -GroupId $state.NceUserGroupId `
                -PrincipalId $state.NceUserGroupId -ResourceId $signInSp.Id `
                -AppRoleId '00000000-0000-0000-0000-000000000000' -ErrorAction Stop | Out-Null
            Write-Log '  NCE user group - ASSIGNED (sign-in tokens now carry the groups claim)' -Level Success
            Add-Summary 'NCE group assignment' 'Assigned'
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        $status = Get-NeologikHttpStatus $_
        if ($status -eq 404) {
            Write-Log "  NCE user group $($state.NceUserGroupId) not found - check the group id" -Level Error
            Add-Summary 'NCE group assignment' 'MISSING - group not found (check the id)'
        }
        elseif ($status -eq 403) {
            Write-Log '  NCE user group assignment refused - sign in as a Global Administrator' -Level Error
            Add-Summary 'NCE group assignment' 'FAILED - insufficient privileges (Global Administrator needed)'
        }
        else {
            Write-Log "  NCE user group assignment - FAILED ($reason)" -Level Error
            Add-Summary 'NCE group assignment' "FAILED - $reason"
        }
    }
    try {
        $group = Get-MgGroup -GroupId $state.NceUserGroupId -ErrorAction Stop
        $memberCount = @(Get-MgGroupMember -GroupId $state.NceUserGroupId -All -ErrorAction Stop).Count
        if ($memberCount -eq 0) {
            Write-Log "  WARNING: group '$($group.DisplayName)' has no members - users must be DIRECT members to sign in (nested groups do not count)" -Level Warning
        }
        else {
            Write-Log "  group '$($group.DisplayName)' has $memberCount direct member(s)" -Level Info
        }
    }
    catch {
        Write-Log "  group membership could not be read ($(Get-NeologikErrorText $_)) - check the group has direct members" -Level Warning
    }

    # ----- 3. admin consent check -----------------------------------------
    Write-Log 'Step 3/4: admin consent for the sign-in application' -Level Info
    try {
        $grants = @(Get-MgServicePrincipalOauth2PermissionGrant -ServicePrincipalId $signInSp.Id -All -ErrorAction Stop |
            Where-Object { $_.ConsentType -eq 'AllPrincipals' })
        if ($grants.Count -gt 0) {
            Write-Log '  tenant-wide admin consent - present' -Level Success
            Add-Summary 'Admin consent' 'Present'
        }
        else {
            $consentUrl = "https://login.microsoftonline.com/$($state.TenantId)/adminconsent?client_id=$($state.SignInAppClientId)"
            Write-Log '  tenant-wide admin consent NOT found. Open this URL in a browser, sign in as Global Administrator and approve:' -Level Warning
            Write-Host ''
            Write-Host "    $consentUrl" -ForegroundColor Cyan
            Write-Host ''
            Write-Log '  then re-run this script to confirm.' -Level Warning
            Add-Summary 'Admin consent' 'MISSING - consent URL printed'
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  admin consent could not be verified - FAILED ($reason)" -Level Error
        Add-Summary 'Admin consent' "FAILED - $reason"
    }
}

function Test-NeologikSharePointConsent {
    # The Sites.Selected admin consent of THIS environment's SharePoint app.
    $state = $script:State
    $graph = $script:GraphV1
    $graphSp = $state.GraphSp
    Write-Log 'Step 3a: SharePoint ingestion is part of the solution - checking the Sites.Selected consent' -Level Info
    try {
        # The tenant may host several environments (the Neologik dev tenant
        # holds eight): resolve THIS environment's app by its exact name
        # first, and fall back to the prefix search only when it is the
        # single match (dev03 finding 2026-09-06, project#2213).
        $spApp = $null
        $ambiguous = $false
        if ($state.ShortName) {
            $exact = ("$script:SharePointAppDisplayNamePrefix$($state.ShortName)") -replace "'", "''"
            $spApp = @(Get-NeologikGraphCollection -Uri "$graph/servicePrincipals?`$filter=displayName eq '$exact'&`$select=id,appId,displayName") | Select-Object -First 1
        }
        if (-not $spApp) {
            $prefix = $script:SharePointAppDisplayNamePrefix -replace "'", "''"
            $spCandidates = @(Get-NeologikGraphCollection -Uri "$graph/servicePrincipals?`$filter=startswith(displayName,'$prefix')&`$select=id,appId,displayName")
            if ($spCandidates.Count -eq 1) { $spApp = $spCandidates[0] }
            elseif ($spCandidates.Count -gt 1) {
                Write-Log "  $($spCandidates.Count) SharePoint access apps in this tenant and no environment short name to pick by - supply -ConfigurationFile" -Level Warning
                Add-Summary 'SharePoint Sites.Selected consent' 'UNKNOWN - several apps, environment not identified'
                $ambiguous = $true
            }
        }
        if ($ambiguous) { return }
        if (-not $spApp) {
            Write-Log '  SharePoint app not found in this tenant - the infrastructure deployment creates it' -Level Warning
            Add-Summary 'SharePoint Sites.Selected consent' 'MISSING - app not found'
            return
        }
        $sitesSelected = Get-NeologikGraphAppRole -RoleName 'Sites.Selected'
        $spAppId = [string](Get-NeologikProperty $spApp 'id')
        $held = @()
        if ($sitesSelected) {
            $held = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $spAppId -All -ErrorAction Stop |
                Where-Object { $_.ResourceId -eq $graphSp.Id -and $_.AppRoleId -eq $sitesSelected.Id })
        }
        if ($held.Count -gt 0) {
            Write-Log "  '$(Get-NeologikProperty $spApp 'displayName')' holds Sites.Selected - consent present (sites are granted per site by a site administrator)" -Level Success
            Add-Summary 'SharePoint Sites.Selected consent' 'Present'
        }
        else {
            $spConsentUrl = "https://login.microsoftonline.com/$($state.TenantId)/adminconsent?client_id=$(Get-NeologikProperty $spApp 'appId')"
            Write-Log '  Sites.Selected consent NOT found. Open this URL as Global Administrator and approve:' -Level Warning
            Write-Host ''
            Write-Host "    $spConsentUrl" -ForegroundColor Cyan
            Write-Host ''
            Add-Summary 'SharePoint Sites.Selected consent' 'MISSING - consent URL printed'
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  Sites.Selected consent could not be verified - FAILED ($reason)" -Level Error
        Add-Summary 'SharePoint Sites.Selected consent' "FAILED - $reason"
    }
}

function Set-NeologikAgentUserGrant {
    # Step 3a: the exported agent-user grants, component roles and the
    # SharePoint consent check.
    $state = $script:State
    $grantsFile = $state.AgentGrants
    Write-Log 'Step 3a: agent-user delegated grants from the exported grants file' -Level Info
    foreach ($entry in @(Get-NeologikProperty $grantsFile 'grants' @())) {
        $kind = [string](Get-NeologikProperty $entry 'kind' 'agent')
        $name = [string](Get-NeologikProperty $entry 'name' '(unnamed)')
        if ([string](Get-NeologikProperty $entry 'status' '') -ne 'ready') {
            Write-Log "  $kind '$name': identity not stamped yet - run the platform provisioning, export again" -Level Warning
            Add-Summary "Agent-user grant: $kind $name" 'SKIPPED - identity not stamped'
            continue
        }
        $scopes = @(@(Get-NeologikProperty $entry 'scopes' @()) | ForEach-Object { [string]$_ } | Where-Object { $_.Trim() })
        Grant-NeologikAgentUserAccess -Kind $kind -Name $name `
            -IdentityClientId ([string](Get-NeologikProperty $entry 'identityClientId')) `
            -AgentUserObjectId ([string](Get-NeologikProperty $entry 'agentUserObjectId')) `
            -Scopes $scopes
    }
    foreach ($role in @(Get-NeologikProperty $grantsFile 'componentGraphRoles' @())) {
        $app = [string](Get-NeologikProperty $role 'app' '(app)')
        $roleName = [string](Get-NeologikProperty $role 'roleName' '')
        $resource = [string](Get-NeologikProperty $role 'resource' '')
        $identityName = [string](Get-NeologikProperty $role 'identityName' '')
        if ($resource -and $resource -ne 'graph') {
            Write-Log "  $app '$roleName' is a $resource role - granted through that service, not Graph" -Level Warning
            Add-Summary "Component role: $app $roleName" "SKIPPED - $resource role"
            continue
        }
        if (-not $roleName -or -not $identityName) {
            Write-Log "  $app`: a component role entry without roleName or identityName - export the file again" -Level Warning
            Add-Summary "Component role: $app $roleName" 'SKIPPED - incomplete entry in the grants file'
            continue
        }
        Grant-NeologikComponentGraphRole -App $app -IdentityName $identityName `
            -RoleName $roleName -ScopeType ([string](Get-NeologikProperty $role 'scopeType' ''))
    }
    if ([bool](Get-NeologikProperty $grantsFile 'sharePointIngestion' $false)) {
        Test-NeologikSharePointConsent
    }
    else {
        Write-Log 'Step 3a: no SharePoint ingestion in the solution - Sites.Selected consent not checked (least exposure)' -Level Info
        Add-Summary 'SharePoint Sites.Selected consent' 'Not needed'
    }
}

function Set-NeologikMailboxGrant {
    # Step 3b: Exchange Online mailbox grants for email channels and the
    # removal of retired identities' assignments.
    $state = $script:State
    Write-Log 'Step 3b: Exchange Online mailbox grants for email channels' -Level Info
    $items = @()
    foreach ($grant in $state.MailboxGrants) { $items += "Mailbox grant: $($grant.Mailbox) -> $($grant.DisplayName)" }
    foreach ($legacyAppId in $state.RemoveLegacyGrantAppIds) { $items += "Legacy mailbox grant: $legacyAppId" }
    if (-not (Import-NeologikModuleSet -Names @('ExchangeOnlineManagement') -MinimumVersion $script:ExchangeModuleMinimumVersion `
                -InstallHint 'Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force')) {
        foreach ($item in $items) { Add-Summary $item 'SKIPPED - Exchange Online module not available' }
        return
    }
    $connected = $false
    try {
        Write-Log '  Signing in to Exchange Online (device code - the same Global Administrator account)...' -Level Info
        Connect-ExchangeOnline -Device -ShowBanner:$false -ErrorAction Stop
        $connected = $true
    }
    catch {
        Write-Log "  Exchange Online sign-in failed: $(Get-NeologikErrorText $_)" -Level Error
        Write-ActionRequired "Exchange Online sign-in did not complete. Run the script again and finish the device-code sign-in with an Exchange Administrator or Global Administrator account of tenant $($state.TenantId)."
        foreach ($item in $items) { Add-Summary $item 'SKIPPED - Exchange Online sign-in failed' }
        return
    }
    try {
        try {
            $organisation = Get-OrganizationConfig -ErrorAction Stop
            if ([bool](Get-NeologikProperty $organisation 'IsDehydrated' $false)) {
                Write-Log '  Enabling organisation customisation (one-off; 60 s propagation)...' -Level Info
                Enable-OrganizationCustomization -ErrorAction Stop
                Start-Sleep -Seconds 60
            }
        }
        catch {
            Write-Log "  organisation customisation could not be verified ($(Get-NeologikErrorText $_)) - continuing" -Level Warning
        }
        foreach ($grant in $state.MailboxGrants) {
            Grant-NeologikMailboxAccess -IdentityAppId $grant.IdentityAppId -IdentityObjectId $grant.IdentityObjectId `
                -Mailbox $grant.Mailbox -DisplayName $grant.DisplayName
        }
        foreach ($legacyAppId in $state.RemoveLegacyGrantAppIds) {
            Remove-NeologikMailboxAccess -LegacyAppId $legacyAppId
        }
    }
    finally {
        if ($connected) {
            try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction Stop | Out-Null } catch { Write-Verbose "ignored: $($_.Exception.Message)" }
        }
    }
}

function Invoke-NeologikWindowPhase {
    $state = $script:State
    Set-NeologikAgentBlueprint
    Set-NeologikDeploymentGraphRole
    Set-NeologikSignInGroupAssignment
    if ($state.AgentGrants) { Set-NeologikAgentUserGrant }
    if ($state.MailboxGrants.Count -gt 0 -or $state.RemoveLegacyGrantAppIds.Count -gt 0) { Set-NeologikMailboxGrant }
}

# ----- PostWindow phase -------------------------------------------------------

function Connect-NeologikAzure {
    # Signs in to Azure for the role-assignment writes; returns $true or
    # $false after printing what to do.
    $state = $script:State
    Write-Log 'Signing in to Azure (device code - same administrator account)...' -Level Info
    try {
        $connectParams = @{ Tenant = $state.TenantId; Subscription = $state.SubscriptionId; UseDeviceAuthentication = $true }
        # Azure mandatory MFA (ARM-layer): request the 'p1' authentication-context claim so the
        # role-assignment writes below are not rejected with a claims-challenge error.
        # Decodes to {"access_token":{"acrs":{"essential":true,"values":["p1"]}}}; needs Az.Accounts >= 5.2.0.
        if ((Get-Command Connect-AzAccount -ErrorAction Stop).Parameters.ContainsKey('ClaimsChallenge')) {
            $connectParams['ClaimsChallenge'] = 'eyJhY2Nlc3NfdG9rZW4iOnsiYWNycyI6eyJlc3NlbnRpYWwiOnRydWUsInZhbHVlcyI6WyJwMSJdfX19'
        }
        Connect-AzAccount @connectParams -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Log "Azure sign-in failed: $(Get-NeologikErrorText $_)" -Level Error
        Write-ActionRequired "Sign in to Azure did not complete.`nRun the script again and finish the device-code sign-in with an account that holds Owner (or User Access Administrator) on subscription $($state.SubscriptionId) in tenant $($state.TenantId)."
        return $false
    }
    try {
        $context = Get-AzContext -ErrorAction Stop
        $contextSub = [string](Get-NeologikProperty (Get-NeologikProperty $context 'Subscription') 'Id' '')
        if ($contextSub -and $contextSub -ne $state.SubscriptionId) {
            Write-ActionRequired "The Azure sign-in selected subscription $contextSub, not $($state.SubscriptionId).`nMake sure your account has access to subscription $($state.SubscriptionId) and run the script again."
            return $false
        }
    }
    catch {
        Write-Log "Azure context could not be read ($(Get-NeologikErrorText $_)) - continuing" -Level Warning
    }
    return $true
}

function Set-NeologikAzureRoleAssignment {
    # Ensures one role assignment for the deployment identity at one scope.
    # Returns $true when the assignment is in place.
    param([string]$RoleName, [string]$Scope, [string]$Label)
    $deploySp = $script:State.DeploySp
    try {
        $assignment = @(Get-AzRoleAssignment -ObjectId $deploySp.Id -RoleDefinitionName $RoleName -Scope $Scope -ErrorAction Stop |
            Where-Object { $_.Scope -eq $Scope })
        if ($assignment.Count -gt 0) {
            Write-Log "  $Label role '$RoleName' - already in place" -Level Success
            Add-Summary "$Label role: $RoleName" 'Already in place'
            return $true
        }
        try {
            New-AzRoleAssignment -ObjectId $deploySp.Id -RoleDefinitionName $RoleName -Scope $Scope -ErrorAction Stop | Out-Null
        }
        catch {
            if ((Get-NeologikErrorText $_) -match '(?i)RoleAssignmentExists|already exists') {
                Write-Log "  $Label role '$RoleName' - already in place" -Level Success
                Add-Summary "$Label role: $RoleName" 'Already in place'
                return $true
            }
            throw
        }
        Write-Log "  $Label role '$RoleName' - CREATED" -Level Success
        Add-Summary "$Label role: $RoleName" 'Created'
        return $true
    }
    catch {
        $reason = Get-NeologikErrorText $_
        if ($reason -match '(?i)AuthorizationFailed|does not have authorization|Forbidden') {
            $reason = 'insufficient privileges - the signed-in account needs Owner or User Access Administrator on the subscription'
        }
        Write-Log "  $Label role '$RoleName' - FAILED ($reason)" -Level Error
        Add-Summary "$Label role: $RoleName" "FAILED - $reason"
        return $false
    }
}

function Remove-NeologikAzureRoleAssignment {
    param([string]$RoleName, [string]$Scope, [string]$Label)
    $deploySp = $script:State.DeploySp
    try {
        $assignment = @(Get-AzRoleAssignment -ObjectId $deploySp.Id -RoleDefinitionName $RoleName -Scope $Scope -ErrorAction Stop |
            Where-Object { $_.Scope -eq $Scope })
        if ($assignment.Count -eq 0) {
            Write-Log "  $Label role '$RoleName' - not present (nothing to remove)" -Level Success
            Add-Summary "Legacy $Label role: $RoleName" 'Not present'
            return
        }
        Remove-AzRoleAssignment -ObjectId $deploySp.Id -RoleDefinitionName $RoleName -Scope $Scope -ErrorAction Stop | Out-Null
        Write-Log "  $Label role '$RoleName' - REMOVED" -Level Success
        Add-Summary "Legacy $Label role: $RoleName" 'Removed'
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  $Label role '$RoleName' - removal FAILED ($reason)" -Level Error
        Add-Summary "Legacy $Label role: $RoleName" "FAILED - $reason"
    }
}

function Remove-NeologikAppAdminRole {
    # 4c. The Application Administrator directory role membership.
    $deploySp = $script:State.DeploySp
    try {
        $appAdminRole = @(Get-MgDirectoryRole -All -ErrorAction Stop | Where-Object { $_.RoleTemplateId -eq $script:AppAdminRoleTemplateId }) | Select-Object -First 1
        $isMember = $false
        if ($appAdminRole) {
            $isMember = @(Get-MgDirectoryRoleMember -DirectoryRoleId $appAdminRole.Id -All -ErrorAction Stop |
                Where-Object { $_.Id -eq $deploySp.Id }).Count -gt 0
        }
        if ($isMember) {
            Remove-MgDirectoryRoleMemberDirectoryObjectByRef -DirectoryRoleId $appAdminRole.Id -DirectoryObjectId $deploySp.Id -ErrorAction Stop
            Write-Log '  Application Administrator directory role - REMOVED' -Level Success
            Add-Summary 'Application Administrator role' 'Removed'
        }
        else {
            Write-Log '  Application Administrator directory role - not held (nothing to remove)' -Level Success
            Add-Summary 'Application Administrator role' 'Not held'
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        if (Test-NeologikPrivilegeError $_) { $reason = 'insufficient privileges - sign in as a Global Administrator or Privileged Role Administrator' }
        Write-Log "  Application Administrator directory role - FAILED ($reason)" -Level Error
        Add-Summary 'Application Administrator role' "FAILED - $reason"
    }
}

function Invoke-NeologikPostWindowPhase {
    $state = $script:State
    Write-Log 'PostWindow: reducing the deployment identity to the resource-group-scoped model' -Level Info
    Write-Log 'Only proceed if Neologik has confirmed the migration is verified.' -Level Warning

    $azureItems = @()
    foreach ($roleName in $script:RequiredRgRoles) { $azureItems += "RG role: $roleName" }
    foreach ($roleName in $script:RequiredSubRoles) { $azureItems += "Sub role: $roleName" }
    foreach ($roleName in $script:LegacySubRoles) { $azureItems += "Legacy Sub role: $roleName" }
    if (-not (Import-NeologikModuleSet -Names @('Az.Accounts', 'Az.Resources') -MinimumVersion ([version]'2.0.0') `
                -InstallHint 'Install-Module Az.Accounts, Az.Resources -Scope CurrentUser -Force')) {
        foreach ($item in $azureItems) { Add-Summary $item 'SKIPPED - Az modules not available' }
        Add-Summary 'Application Administrator role' 'SKIPPED - narrow Azure roles not confirmed'
        return
    }
    if (-not (Connect-NeologikAzure)) {
        foreach ($item in $azureItems) { Add-Summary $item 'SKIPPED - Azure sign-in failed' }
        Add-Summary 'Application Administrator role' 'SKIPPED - narrow Azure roles not confirmed'
        return
    }

    $rgScope = "/subscriptions/$($state.SubscriptionId)/resourceGroups/$($state.ResourceGroupName)"
    $subScope = "/subscriptions/$($state.SubscriptionId)"

    # 4a. narrow role set FIRST - pipelines must never lose access in between.
    $narrowComplete = $true
    foreach ($roleName in $script:RequiredRgRoles) {
        if (-not (Set-NeologikAzureRoleAssignment -RoleName $roleName -Scope $rgScope -Label 'RG')) { $narrowComplete = $false }
    }

    # 4a2. ensure the retained subscription-scoped roles (still before any
    # removal - narrow before broad). 'Cost Management Contributor' is new at
    # v5 (project#1215): on an already-hardened environment this is the one
    # assignment this phase creates.
    foreach ($roleName in $script:RequiredSubRoles) {
        if (-not (Set-NeologikAzureRoleAssignment -RoleName $roleName -Scope $subScope -Label 'subscription')) { $narrowComplete = $false }
    }

    if (-not $narrowComplete) {
        Write-Log '  the narrow role set is not complete - the legacy broad grants are left in place (narrow before broad)' -Level Warning
        foreach ($roleName in $script:LegacySubRoles) { Add-Summary "Legacy subscription role: $roleName" 'SKIPPED - narrow roles not all in place' }
        Add-Summary 'Application Administrator role' 'SKIPPED - narrow roles not all in place'
        return
    }

    # 4b. remove legacy subscription-scoped assignments.
    foreach ($roleName in $script:LegacySubRoles) {
        Remove-NeologikAzureRoleAssignment -RoleName $roleName -Scope $subScope -Label 'subscription'
    }

    # 4c. remove the Application Administrator directory role membership.
    Remove-NeologikAppAdminRole
}

# ----- summary ----------------------------------------------------------------

function Get-NeologikHeldGraphRole {
    # The deployment identity's Graph application roles as they stand.
    $state = $script:State
    if (-not $state.ContainsKey('DeploySp') -or -not $state.DeploySp -or -not $state.ContainsKey('GraphSp') -or -not $state.GraphSp) { return @() }
    $graphSp = $state.GraphSp
    $held = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $state.DeploySp.Id -All -ErrorAction Stop |
        Where-Object { $_.ResourceId -eq $graphSp.Id } |
        ForEach-Object { $roleId = $_.AppRoleId; @($graphSp.AppRoles | Where-Object { $_.Id -eq $roleId } | ForEach-Object { $_.Value }) })
    return , @($held | Where-Object { $_ })
}

function Write-NeologikSummary {
    # Prints the summary table, writes the JSON summary and returns the
    # exit code: 0 when nothing needs attention, otherwise 1.
    $state = $script:State
    Write-Host ''
    Write-Host '============================ SUMMARY ============================' -ForegroundColor Cyan
    if ($script:Summary.Count -gt 0) {
        $script:Summary | Format-Table -AutoSize | Out-String | Write-Host
    }
    else {
        Write-Host '  (no items were verified - see the messages above)'
    }
    $attention = @($script:Summary | Where-Object { $_.Result -match $script:AttentionPattern })
    # Machine-readable summary beside the log (project#2213): the deployment
    # identity's Graph roles as they stand and every consent state, for the
    # migration ticket. Written next to the script; never contains a secret.
    try {
        $heldRoles = @()
        try { $heldRoles = @(Get-NeologikHeldGraphRole) }
        catch { Write-Log "The deployment identity's current Graph roles could not be read for the summary: $(Get-NeologikErrorText $_)" -Level Warning }
        $json = [pscustomobject]@{
            tenantId             = [string](Get-NeologikProperty $state 'TenantId' '')
            deploymentIdentity   = [string](Get-NeologikProperty $state 'DeploySpClientId' '')
            phase                = [string](Get-NeologikProperty $state 'Phase' '')
            ranAt                = (Get-Date).ToUniversalTime().ToString('o')
            deploymentGraphRoles = @($heldRoles)
            expectedGraphRoles   = @($script:RequiredGraphRoles)
            agentGrantsFile      = [string](Get-NeologikProperty $state 'AgentGrantsFile' '')
            items                = @($script:Summary)
            attentionCount       = $attention.Count
        } | ConvertTo-Json -Depth 5
        $fileName = 'Neologik_EnvironmentAccess_{0}_{1}.json' -f [string](Get-NeologikProperty $state 'Phase' 'Window'), (Get-Date -Format 'yyyyMMdd_HHmmss')
        $written = $null
        foreach ($directory in @(Get-NeologikSummaryDirectory)) {
            $summaryPath = Join-Path $directory $fileName
            try {
                Set-Content -LiteralPath $summaryPath -Value $json -Encoding UTF8 -ErrorAction Stop
                $written = $summaryPath
                break
            }
            catch {
                Write-Log "Could not write the JSON summary to $directory ($(Get-NeologikErrorText $_)) - trying the next location" -Level Warning
            }
        }
        if ($written) { Write-Log "Summary written to $written - paste it on the migration ticket" -Level Info }
        else { Write-Log 'Could not write the JSON summary anywhere - paste the summary table on the migration ticket instead' -Level Warning }
    }
    catch {
        Write-Log "Could not write the JSON summary: $(Get-NeologikErrorText $_)" -Level Warning
    }
    if ($attention.Count -gt 0) {
        Write-Log "$($attention.Count) item(s) need attention - see the summary above." -Level Warning
        return 1
    }
    Write-Log "Phase '$($state.Phase)' complete - environment access is in the expected state." -Level Success
    return 0
}

# ----- main entry ---------------------------------------------------------------

function Invoke-NeologikEnvironmentAccess {
    <#
    The run. Returns the exit code (0 = everything in the expected state,
    1 = attention needed) and never throws: every failure is reported with
    the action the operator should take.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [string]$ConfigurationFile,
        [ValidateSet('Window', 'PostWindow')]
        [string]$Phase = 'Window',
        [string]$TenantId,
        [string]$DeploySpClientId,
        [string]$SignInAppClientId,
        [string]$NceUserGroupId,
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$BlueprintKey = 'default',
        [string]$AgentGrantsFile,
        [string]$MailboxGrantsFile,
        [string[]]$RemoveLegacyGrantAppIds,
        [switch]$UseAzureCliToken
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $script:Summary = @()
    $script:State = @{}

    if (-not (Test-NeologikPowerShellVersion)) { return 1 }

    try {
        Resolve-NeologikInput -Parameters @{
            ConfigurationFile       = $ConfigurationFile
            Phase                   = $Phase
            TenantId                = $TenantId
            DeploySpClientId        = $DeploySpClientId
            SignInAppClientId       = $SignInAppClientId
            NceUserGroupId          = $NceUserGroupId
            SubscriptionId          = $SubscriptionId
            ResourceGroupName       = $ResourceGroupName
            BlueprintKey            = $BlueprintKey
            AgentGrantsFile         = $AgentGrantsFile
            MailboxGrantsFile       = $MailboxGrantsFile
            RemoveLegacyGrantAppIds = @($RemoveLegacyGrantAppIds)
            UseAzureCliToken        = [bool]$UseAzureCliToken
        }
    }
    catch [System.ArgumentException] {
        Write-Log $_.Exception.Message -Level Error
        Write-ActionRequired $_.Exception.Message
        return 1
    }
    catch {
        Write-Log "The inputs could not be read: $(Get-NeologikErrorText $_)" -Level Error
        Write-ActionRequired "The inputs could not be read: $(Get-NeologikErrorText $_)"
        return 1
    }

    Write-NeologikHeader

    if (-not (Import-NeologikModuleSet -Names $script:GraphModules -MinimumVersion $script:GraphModuleMinimumVersion `
                -InstallHint 'Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Applications, Microsoft.Graph.Groups, Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser -Force')) {
        return 1
    }
    if (-not (Connect-NeologikGraph)) { return 1 }
    if (-not (Resolve-NeologikPrincipal)) { return (Write-NeologikSummary) }

    try {
        if ($script:State.Phase -eq 'Window') { Invoke-NeologikWindowPhase }
        else { Invoke-NeologikPostWindowPhase }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "Unexpected error - the run stopped early: $reason" -Level Error
        Add-Summary 'Run' "FAILED - unexpected error: $reason"
    }
    return (Write-NeologikSummary)
}

# Dot-sourcing (the test harness) defines the functions without running.
if ($MyInvocation.InvocationName -ne '.') {
    $neologikExitCode = Invoke-NeologikEnvironmentAccess @PSBoundParameters
    exit ([int](@($neologikExitCode)[-1]))
}
