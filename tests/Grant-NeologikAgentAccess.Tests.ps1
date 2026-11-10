#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Tests of Grant-NeologikAgentAccess.ps1 (project#3192).

    Every external call is replaced: Microsoft Graph (the SDK cmdlets and the
    raw request seam), Exchange Online, the Azure CLI, module installation and
    the console. An in-memory tenant model answers the script's reads and
    records every write, so a run can be asserted to change exactly what a
    real run would change - and, on a tenant that holds every grant, nothing
    at all.

    Run: pwsh -NoProfile -Command "Invoke-Pester -Path tests -CI"
#>

Describe 'Grant-NeologikAgentAccess.ps1' {

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Grant-NeologikAgentAccess.ps1'

    # ----- stubs for every external command the script calls -----------------
    # (a command must exist before Pester can mock it; the Exchange cmdlets
    # only exist inside a live session, the others would need real modules.)
    function Connect-MgGraph { [CmdletBinding()] param($AccessToken, $TenantId, $Scopes, [switch]$UseDeviceCode, [switch]$NoWelcome) }
    function Get-MgContext { [CmdletBinding()] param() }
    function Invoke-MgGraphRequest { [CmdletBinding()] param($Method, $Uri, $Body, $Headers, $ContentType, [switch]$SkipHttpErrorCheck, $StatusCodeVariable, $ResponseHeadersVariable) }
    function Get-MgServicePrincipal { [CmdletBinding()] param($Filter, [switch]$All) }
    function Get-MgServicePrincipalAppRoleAssignment { [CmdletBinding()] param($ServicePrincipalId, [switch]$All) }
    function New-MgServicePrincipalAppRoleAssignment { [CmdletBinding()] param($ServicePrincipalId, $PrincipalId, $ResourceId, $AppRoleId) }
    function Connect-ExchangeOnline { [CmdletBinding()] param([switch]$Device, $ShowBanner, $UserPrincipalName) }
    function Disconnect-ExchangeOnline { [CmdletBinding(SupportsShouldProcess)] param() }
    function Get-OrganizationConfig { [CmdletBinding()] param() }
    function Enable-OrganizationCustomization { [CmdletBinding()] param() }
    function Get-ServicePrincipal { [CmdletBinding()] param($Identity) }
    function New-ServicePrincipal { [CmdletBinding()] param($AppId, $ObjectId, $DisplayName) }
    function Remove-ServicePrincipal { [CmdletBinding(SupportsShouldProcess)] param($Identity) }
    function Get-ManagementScope { [CmdletBinding()] param($Identity) }
    function New-ManagementScope { [CmdletBinding()] param($Name, $RecipientRestrictionFilter) }
    function Get-ManagementRoleAssignment { [CmdletBinding()] param($Identity, $RoleAssignee) }
    function New-ManagementRoleAssignment { [CmdletBinding()] param($Name, $App, $Role, $CustomResourceScope) }
    function Remove-ManagementRoleAssignment { [CmdletBinding(SupportsShouldProcess)] param($Identity) }
    function Test-ServicePrincipalAuthorization { [CmdletBinding()] param($Identity, $Resource) }

    # The script under test: dot-sourced, so its functions are defined here
    # and its guarded main entry does not run.
    . $script:ScriptPath

    # ----- fixed identifiers ------------------------------------------------------
    $script:Ids = @{
        Tenant           = '11111111-1111-1111-1111-111111111111'
        OtherTenant      = '99999999-9999-9999-9999-999999999999'
        GraphSpId        = '00000003-aaaa-0000-c000-000000000000'
        Me               = '66666666-6666-6666-6666-666666666666'
        AgentIdentityApp = '88888888-8888-8888-8888-888888888888'
        AgentIdentitySp  = '88888888-aaaa-8888-8888-888888888888'
        AgentUser        = '88888888-bbbb-8888-8888-888888888888'
        AppIdentityApp   = '88888888-cccc-8888-8888-888888888888'
        AppIdentitySp    = '88888888-dddd-8888-8888-888888888888'
        AppUser          = '88888888-eeee-8888-8888-888888888888'
        ComponentSpId    = 'aaaaaaaa-1111-aaaa-aaaa-aaaaaaaaaaaa'
        SharePointSpId   = 'bbbbbbbb-1111-bbbb-bbbb-bbbbbbbbbbbb'
        SharePointAppId  = 'bbbbbbbb-2222-bbbb-bbbb-bbbbbbbbbbbb'
        SharePoint2SpId  = 'bbbbbbbb-3333-bbbb-bbbb-bbbbbbbbbbbb'
        SharePoint2AppId = 'bbbbbbbb-4444-bbbb-bbbb-bbbbbbbbbbbb'
        EarlierSpId      = 'bbbbbbbb-5555-bbbb-bbbb-bbbbbbbbbbbb'
        EarlierAppId     = 'bbbbbbbb-6666-bbbb-bbbb-bbbbbbbbbbbb'
        MailboxAppId     = 'dddddddd-1111-dddd-dddd-dddddddddddd'
        MailboxObjectId  = 'dddddddd-2222-dddd-dddd-dddddddddddd'
        LegacyAppId      = 'eeeeeeee-1111-eeee-eeee-eeeeeeeeeeee'
        LegacyObjectId   = 'eeeeeeee-2222-eeee-eeee-eeeeeeeeeeee'
    }
    $script:ShortName = 'abcprd01'
    $script:AppRoleIds = @{}
    foreach ($roleName in @('Sites.Selected', 'Sites.FullControl.All', 'User.Read.All', 'Mail.Read')) {
        $script:AppRoleIds[$roleName] = [guid]::NewGuid().ToString()
    }

    # ----- in-memory tenant ---------------------------------------------------------
    function New-FakeSp {
        param([string]$Id, [string]$AppId, [string]$DisplayName)
        return @{ id = $Id; appId = $AppId; displayName = $DisplayName; appRoleAssignments = @(); grants = @() }
    }

    function Add-FakeAppRole {
        param([string]$SpId, [string]$RoleName)
        $sp = Get-FakeSp -Id $SpId
        $sp.appRoleAssignments += @{ Id = [guid]::NewGuid().ToString(); AppRoleId = $script:AppRoleIds[$RoleName]; ResourceId = $script:Ids.GraphSpId; PrincipalId = $SpId }
    }

    function Get-FakeSp {
        param([string]$Id)
        return @($script:Tenant.ServicePrincipals | Where-Object { $_.id -eq $Id }) | Select-Object -First 1
    }

    function Add-Write {
        param([string]$Description)
        $script:Writes += $Description
    }

    function New-EmptyTenant {
        # The directory with the Graph service principal and nothing of Neologik, and
        # an Exchange Online organisation with no grant.
        $t = @{
            Me                = $script:Ids.Me
            ServicePrincipals = @()
            Exchange          = @{ ServicePrincipals = @(); Scopes = @(); Assignments = @(); InScope = $true; Dehydrated = $false }
            PageSize          = 0
            GrantRefusals     = @()
            # The signed-in administrator: a Global Administrator.
            MeDirectoryRoles  = @(@{ id = 'role-ga'; displayName = 'Global Administrator'; roleTemplateId = '62e90394-69f5-4237-9190-012177145e10' })
        }
        $t.ServicePrincipals += New-FakeSp -Id $script:Ids.GraphSpId -AppId '00000003-0000-0000-c000-000000000000' -DisplayName 'Microsoft Graph'
        return $t
    }

    function Add-AgentIdentities {
        # The agent-lane identities the grants file refers to.
        param([string]$AgentScope = 'User.Read Sites.ReadWrite.All', [string]$AppScope = 'User.Read', [switch]$NoGrants)
        $t = $script:Tenant
        $agentSp = New-FakeSp -Id $script:Ids.AgentIdentitySp -AppId $script:Ids.AgentIdentityApp -DisplayName 'agent-identity'
        $appSp = New-FakeSp -Id $script:Ids.AppIdentitySp -AppId $script:Ids.AppIdentityApp -DisplayName 'app-identity'
        if (-not $NoGrants) {
            if ($AgentScope) { $agentSp.grants = @(@{ id = 'grant-agent'; clientId = $script:Ids.AgentIdentitySp; principalId = $script:Ids.AgentUser; resourceId = $script:Ids.GraphSpId; consentType = 'Principal'; scope = $AgentScope }) }
            if ($AppScope) { $appSp.grants = @(@{ id = 'grant-app'; clientId = $script:Ids.AppIdentitySp; principalId = $script:Ids.AppUser; resourceId = $script:Ids.GraphSpId; consentType = 'Principal'; scope = $AppScope }) }
        }
        $t.ServicePrincipals += $agentSp
        $t.ServicePrincipals += $appSp
        $component = New-FakeSp -Id $script:Ids.ComponentSpId -AppId ([guid]::NewGuid().ToString()) -DisplayName 'neo-refapp-api'
        $t.ServicePrincipals += $component
    }

    function Add-SharePointApp {
        param([switch]$WithConsent, [switch]$Second)
        $t = $script:Tenant
        $sp = New-FakeSp -Id $script:Ids.SharePointSpId -AppId $script:Ids.SharePointAppId -DisplayName "Neologik SharePoint Access - $script:ShortName"
        $t.ServicePrincipals += $sp
        if ($WithConsent) { Add-FakeAppRole -SpId $script:Ids.SharePointSpId -RoleName 'Sites.Selected' }
        if ($Second) {
            $t.ServicePrincipals += New-FakeSp -Id $script:Ids.SharePoint2SpId -AppId $script:Ids.SharePoint2AppId -DisplayName 'Neologik SharePoint Access - other01'
        }
    }

    function Add-EarlierSharePointApp {
        # A hand-made SharePoint application. The customer gave the consent to this
        # application before the deployment created the SharePoint application of
        # the environment.
        param([string]$RoleName = 'Sites.Selected')
        $script:Tenant.ServicePrincipals += New-FakeSp -Id $script:Ids.EarlierSpId -AppId $script:Ids.EarlierAppId -DisplayName 'Neologik SharePoint API Access'
        Add-FakeAppRole -SpId $script:Ids.EarlierSpId -RoleName $RoleName
    }

    function Add-CompliantExchangeState {
        param([string]$DisplayName = 'neo-support')
        $x = $script:Tenant.Exchange
        $x.ServicePrincipals += @{ Identity = $script:Ids.MailboxObjectId; ObjectId = $script:Ids.MailboxObjectId; AppId = $script:Ids.MailboxAppId; DisplayName = $DisplayName }
        $x.Scopes += @{ Name = "Scope-$DisplayName"; RecipientFilter = "PrimarySmtpAddress -eq 'support@contoso.com'" }
        foreach ($suffix in @('MailRead', 'MailReadWrite', 'MailSend')) {
            $x.Assignments += @{ Name = "Assignment-$DisplayName-$suffix"; Role = "Application Mail.$($suffix -replace '^Mail', '')"; RoleAssigneeName = $script:Ids.MailboxObjectId }
        }
    }

    # ----- Graph request router -------------------------------------------------------
    function Get-QueryValue {
        param([string]$Query, [string]$Name)
        $decoded = [uri]::UnescapeDataString($Query)
        foreach ($part in ($decoded.TrimStart('?') -split '&')) {
            $kv = $part -split '=', 2
            if ($kv[0] -eq $Name -and $kv.Count -eq 2) { return $kv[1] }
        }
        return $null
    }

    function Remove-FakeRefusal {
        # Consumes ONE queued refusal for a scope string (each entry refuses once).
        param([string]$Scope)
        $list = [System.Collections.ArrayList]@($script:Tenant.GrantRefusals)
        $index = $list.IndexOf($Scope)
        if ($index -ge 0) { $list.RemoveAt($index) }
        $script:Tenant.GrantRefusals = @($list)
    }

    function ConvertTo-FakePage {
        # Slices a collection into pages when PageSize is set.
        param([object[]]$Items, [string]$Uri, [string]$Query)
        $pageSize = [int]$script:Tenant.PageSize
        $skip = 0
        $token = Get-QueryValue -Query $Query -Name '$skiptoken'
        if ($token) { $skip = [int]$token }
        if ($pageSize -le 0 -or $Items.Count -le $pageSize) {
            if ($skip -gt 0) { return @{ value = @($Items | Select-Object -Skip $skip) } }
            return @{ value = @($Items) }
        }
        $page = @($Items | Select-Object -Skip $skip -First $pageSize)
        $result = @{ value = $page }
        if ($skip + $pageSize -lt $Items.Count) {
            $base = $Uri -replace '&\$skiptoken=\d+', ''
            $result['@odata.nextLink'] = "$base&`$skiptoken=$($skip + $pageSize)"
        }
        return $result
    }

    function Invoke-FakeGraph {
        param([string]$Method, [string]$Uri, $Body)
        $t = $script:Tenant
        $parsed = [uri]$Uri
        $path = $parsed.AbsolutePath -replace '^/(v1\.0|beta)', ''
        $query = $parsed.Query
        $script:GraphCalls += "$Method $path"
        # Fault injection: the first matching fault with attempts left answers.
        foreach ($fault in @($script:Faults)) {
            if ($fault.Remaining -gt 0 -and "$Method $path" -match $fault.Match) {
                $fault.Remaining--
                $headers = if ($fault.ContainsKey('Headers')) { $fault.Headers } else { @{} }
                return @{ StatusCode = $fault.Status; Headers = $headers; Body = @{ error = @{ code = $fault.Code; message = $fault.Message } } }
            }
        }
        $json = $null
        if ($Body) { $json = $Body | ConvertFrom-Json -AsHashtable }
        switch -Regex ($path) {
            '^/me$' { return @{ StatusCode = 200; Headers = @{}; Body = @{ id = $t.Me; userPrincipalName = 'admin@contoso.com'; displayName = 'Contoso Administrator' } } }
            '^/me/memberOf/microsoft\.graph\.directoryRole$' {
                return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items @($t.MeDirectoryRoles) -Uri $Uri -Query $query) }
            }
            '^/servicePrincipals$' {
                $filter = Get-QueryValue -Query $query -Name '$filter'
                $items = @()
                if ($filter -match "^appId eq '(.+)'$") {
                    $appId = $Matches[1]
                    $items = @($t.ServicePrincipals | Where-Object { $_.appId -eq $appId })
                }
                elseif ($filter -match "^displayName eq '(.+)'$") {
                    $name = $Matches[1] -replace "''", "'"
                    $items = @($t.ServicePrincipals | Where-Object { $_.displayName -eq $name })
                }
                elseif ($filter -match "^startswith\(displayName,'(.+)'\)$") {
                    $prefix = $Matches[1] -replace "''", "'"
                    $items = @($t.ServicePrincipals | Where-Object { $_.displayName.StartsWith($prefix) })
                }
                $projected = @($items | ForEach-Object { @{ id = $_.id; appId = $_.appId; displayName = $_.displayName } })
                return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $projected -Uri $Uri -Query $query) }
            }
            '^/oauth2PermissionGrants$' {
                if ($Method -eq 'GET') {
                    $filter = Get-QueryValue -Query $query -Name '$filter'
                    $items = @()
                    if ($filter -match "clientId eq '([^']+)' and principalId eq '([^']+)' and resourceId eq '([^']+)'") {
                        $clientId = $Matches[1]; $principalId = $Matches[2]; $resourceId = $Matches[3]
                        $sp = Get-FakeSp -Id $clientId
                        if ($sp) { $items = @($sp.grants | Where-Object { $_.principalId -eq $principalId -and $_.resourceId -eq $resourceId }) }
                    }
                    return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $items -Uri $Uri -Query $query) }
                }
                if ($t.GrantRefusals -contains $json.scope) {
                    Remove-FakeRefusal -Scope $json.scope
                    return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = "Invalid value specified for property 'scope'" } } }
                }
                $sp = Get-FakeSp -Id $json.clientId
                $grant = @{ id = [guid]::NewGuid().ToString(); clientId = $json.clientId; principalId = $json.principalId; resourceId = $json.resourceId; consentType = $json.consentType; scope = $json.scope }
                $sp.grants += $grant
                Add-Write "POST grant $($json.clientId) $($json.scope)"
                return @{ StatusCode = 201; Headers = @{}; Body = $grant }
            }
            '^/oauth2PermissionGrants/([^/]+)$' {
                $grantId = $Matches[1]
                if ($t.GrantRefusals -contains $json.scope) {
                    Remove-FakeRefusal -Scope $json.scope
                    return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = "Invalid value specified for property 'scope'" } } }
                }
                foreach ($sp in $t.ServicePrincipals) {
                    foreach ($grant in $sp.grants) {
                        if ($grant.id -eq $grantId) {
                            $grant.scope = $json.scope
                            Add-Write "PATCH grant $grantId $($json.scope)"
                            return @{ StatusCode = 204; Headers = @{}; Body = $null }
                        }
                    }
                }
                return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'grant not found' } } }
            }
        }
        return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = "no route for $Method $path" } } }
    }

    function ConvertTo-SpObject {
        param($Sp)
        $appRoles = @()
        if ($Sp.id -eq $script:Ids.GraphSpId) {
            $appRoles = @($script:AppRoleIds.Keys | ForEach-Object { [pscustomobject]@{ Id = $script:AppRoleIds[$_]; Value = $_ } })
        }
        return [pscustomobject]@{ Id = $Sp.id; AppId = $Sp.appId; DisplayName = $Sp.displayName; AppRoles = $appRoles }
    }

    function New-NotFoundException {
        param([string]$Message = 'Request_ResourceNotFound: Resource does not exist')
        return [System.Net.Http.HttpRequestException]::new($Message, $null, [System.Net.HttpStatusCode]::NotFound)
    }

    function New-ForbiddenException {
        return [System.Net.Http.HttpRequestException]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.', $null, [System.Net.HttpStatusCode]::Forbidden)
    }

    # ----- fixtures ---------------------------------------------------------------------
    function New-GrantsFile {
        # The agent grants file as the Neologik Admin Tool exports it: the tenant and
        # the environment are in the file, so a command needs no other value.
        param([string]$Path = (Join-Path $TestDrive 'grants.json'), [object[]]$Grants = @(), [object[]]$ComponentRoles = @(),
            [bool]$SharePoint = $false, [string]$TenantId = $script:Ids.Tenant, [string]$Environment = $script:ShortName,
            [string[]]$Warnings = @(), [switch]$Raw, [string]$RawContent)
        if ($Raw) { Set-Content -LiteralPath $Path -Value $RawContent -Encoding UTF8 -NoNewline; return $Path }
        $payload = [ordered]@{
            schemaVersion       = 1
            environment         = $Environment
            tenantId            = $TenantId
            exportedAt          = '2026-09-06T12:00:00Z'
            grants              = @($Grants)
            componentGraphRoles = @($ComponentRoles)
            sharePointIngestion = $SharePoint
            warnings            = @($Warnings)
        }
        $payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
        return $Path
    }

    function New-AgentGrantEntry {
        param([string]$Kind = 'agent', [string]$Name = 'Support Agent', [string]$ClientId = $script:Ids.AgentIdentityApp,
            [string]$UserId = $script:Ids.AgentUser, [string[]]$Scopes = @('User.Read', 'Sites.ReadWrite.All'), [string]$Status = 'ready')
        return [ordered]@{ kind = $Kind; id = [guid]::NewGuid().ToString(); name = $Name; identityClientId = $ClientId; agentUserObjectId = $UserId
            packs = @('sharepoint'); scopes = $Scopes; grantState = 'outstanding'; status = $Status }
    }

    function New-MailboxFile {
        # The object shape with 'tenantId', 'grants' and 'adoptedIdentityAppIds' by
        # default, as the Neologik Admin Tool exports it; -AsArray writes the bare
        # list of entries, which names no tenant.
        param([string]$Path = (Join-Path $TestDrive 'mailboxes.json'), [object[]]$Entries, [string[]]$AdoptedIdentityAppIds = @(),
            [switch]$AsArray, [string]$TenantId = $script:Ids.Tenant, [switch]$Raw, [string]$RawContent)
        if ($Raw) { Set-Content -LiteralPath $Path -Value $RawContent -Encoding UTF8 -NoNewline; return $Path }
        if ($null -eq $Entries) {
            $Entries = @(@{ IdentityAppId = $script:Ids.MailboxAppId; IdentityObjectId = $script:Ids.MailboxObjectId; Mailbox = 'support@contoso.com'; DisplayName = 'neo-support' })
        }
        if ($AsArray) {
            ConvertTo-Json -InputObject @($Entries) -Depth 4 | Set-Content -LiteralPath $Path -Encoding UTF8
            return $Path
        }
        $payload = [ordered]@{ schemaVersion = 1; tenantId = $TenantId; grants = @($Entries); adoptedIdentityAppIds = @($AdoptedIdentityAppIds) }
        ConvertTo-Json -InputObject $payload -Depth 4 | Set-Content -LiteralPath $Path -Encoding UTF8
        return $Path
    }

    function Get-SummaryResult {
        param([string]$Item)
        $row = @($script:Summary | Where-Object { $_.Item -eq $Item }) | Select-Object -First 1
        if ($row) { return $row.Result }
        return $null
    }

    function Invoke-Run {
        # Runs the main entry and returns its single output (the exit code).
        param([hashtable]$Parameters)
        $output = @(Invoke-NeologikAgentAccess @Parameters)
        $output.Count | Should -Be 1 -Because 'the main entry must emit exactly one object: the exit code'
        $output[0] | Should -BeOfType [int]
        return [int]$output[0]
    }

    # ----- default mocks: a healthy machine, tenant answers from the model -------------
    Mock Write-Host { param($Object) $script:Console += [string]$Object }
    Mock Start-Sleep { param($Seconds) $script:Sleeps += [int]$Seconds }
    Mock Get-NeologikAvailableModuleVersion { param($Name) @([version]'2.38.0') }
    Mock Get-NeologikLoadedModuleVersion { $null }
    Mock Install-NeologikModule { param($Name) $script:Installs += $Name }
    Mock Import-NeologikModule { param($Name, $RequiredVersion) $script:Imports += "$Name $RequiredVersion" }
    Mock Test-NeologikCommand { $true }
    Mock Invoke-NeologikAzureCli { @{ ExitCode = 0; Output = @('eyJ0b2tlbg') } }
    # every endpoint answers, and the script's own device code
    # completes on the first poll (the identity platform is never contacted).
    Mock Test-NeologikEndpoint { $true }
    Mock Invoke-NeologikTokenRequest {
        param($Uri, $Body)
        $script:TokenRequests += @{ Uri = $Uri; Body = $Body }
        if ($Uri -match '/devicecode$') {
            return @{ StatusCode = 200; Body = @{ device_code = 'dc-1'; user_code = 'ABCD-EFGH'; verification_uri = 'https://microsoft.com/devicelogin'; expires_in = 900; interval = 5 } }
        }
        return @{ StatusCode = 200; Body = @{ access_token = 'eyJ0b2tlbg'; refresh_token = 'rt-1' } }
    }
    # The browser sign-in: by default no browser opens, so a run falls back to the
    # device code above. The context 'Browser sign-in' opens the browser.
    Mock Start-NeologikLoopbackListener {
        [pscustomobject]@{ Port = 50999 } | Add-Member -MemberType ScriptMethod -Name Stop -Value { } -PassThru
    }
    Mock Open-NeologikBrowser { param($Uri) $script:BrowserUris += $Uri; $script:BrowserOpens }
    Mock Test-NeologikDesktop { $script:Desktop }
    Mock Get-NeologikSummaryDirectory { @($script:SummaryDirs) }
    Mock Invoke-NeologikGraphRaw { param($Method, $Uri, $Body) Invoke-FakeGraph -Method $Method -Uri $Uri -Body $Body }
    Mock Connect-MgGraph { $script:Connected = $true }
    Mock Get-MgContext { [pscustomobject]@{ TenantId = $script:ContextTenant; Account = 'admin@contoso.com'; Scopes = @($script:ContextScopes) } }
    Mock Get-MgServicePrincipal {
        param($Filter)
        if ($Filter -match "appId eq '([^']+)'") {
            $appId = $Matches[1]
            $sp = @($script:Tenant.ServicePrincipals | Where-Object { $_.appId -eq $appId }) | Select-Object -First 1
            if ($sp) { ConvertTo-SpObject -Sp $sp }
        }
    }
    Mock Get-MgServicePrincipalAppRoleAssignment {
        param($ServicePrincipalId)
        $sp = Get-FakeSp -Id $ServicePrincipalId
        if (-not $sp) { throw (New-NotFoundException) }
        @($sp.appRoleAssignments | ForEach-Object { [pscustomobject]$_ })
    }
    Mock New-MgServicePrincipalAppRoleAssignment {
        param($ServicePrincipalId, $PrincipalId, $ResourceId, $AppRoleId)
        $sp = Get-FakeSp -Id $ServicePrincipalId
        $sp.appRoleAssignments += @{ Id = [guid]::NewGuid().ToString(); AppRoleId = $AppRoleId; ResourceId = $ResourceId; PrincipalId = $PrincipalId }
        Add-Write "NEW approle $ServicePrincipalId $AppRoleId"
    }
    Mock Connect-ExchangeOnline { $script:ExchangeConnected = $true }
    Mock Disconnect-ExchangeOnline { $script:ExchangeDisconnected = $true }
    Mock Get-OrganizationConfig { [pscustomobject]@{ IsDehydrated = [bool]$script:Tenant.Exchange.Dehydrated } }
    Mock Enable-OrganizationCustomization { Add-Write 'ENABLE org customisation' }
    Mock Get-ServicePrincipal {
        param($Identity)
        $sp = @($script:Tenant.Exchange.ServicePrincipals | Where-Object { $_.AppId -eq $Identity -or $_.ObjectId -eq $Identity -or $_.DisplayName -eq $Identity }) | Select-Object -First 1
        if ($sp) { [pscustomobject]$sp }
    }
    Mock New-ServicePrincipal {
        param($AppId, $ObjectId, $DisplayName)
        $sp = @{ Identity = $ObjectId; ObjectId = $ObjectId; AppId = $AppId; DisplayName = $DisplayName }
        $script:Tenant.Exchange.ServicePrincipals += $sp
        Add-Write "NEW exo sp $AppId"
        [pscustomobject]$sp
    }
    Mock Remove-ServicePrincipal {
        param($Identity)
        $script:Tenant.Exchange.ServicePrincipals = @($script:Tenant.Exchange.ServicePrincipals | Where-Object { $_.Identity -ne $Identity })
        Add-Write "REMOVE exo sp $Identity"
    }
    Mock Get-ManagementScope {
        param($Identity)
        $scopes = @($script:Tenant.Exchange.Scopes)
        if ($Identity) { $scopes = @($scopes | Where-Object { $_.Name -eq $Identity }) }
        @($scopes | ForEach-Object { [pscustomobject]$_ })
    }
    Mock New-ManagementScope {
        param($Name, $RecipientRestrictionFilter)
        $scope = @{ Name = $Name; RecipientFilter = $RecipientRestrictionFilter }
        $script:Tenant.Exchange.Scopes += $scope
        Add-Write "NEW exo scope $Name"
        [pscustomobject]$scope
    }
    Mock Get-ManagementRoleAssignment {
        param($Identity, $RoleAssignee)
        $assignments = @($script:Tenant.Exchange.Assignments)
        if ($Identity) { $assignments = @($assignments | Where-Object { $_.Name -eq $Identity }) }
        if ($RoleAssignee) {
            if ($script:Tenant.Exchange.ContainsKey('RoleAssigneeUnsupported') -and $script:Tenant.Exchange.RoleAssigneeUnsupported) {
                throw 'The RoleAssignee parameter does not accept service principals'
            }
            $assignments = @($assignments | Where-Object { $_.RoleAssigneeName -eq $RoleAssignee })
        }
        @($assignments | ForEach-Object { [pscustomobject]$_ })
    }
    Mock New-ManagementRoleAssignment {
        param($Name, $App, $Role, $CustomResourceScope)
        $script:Tenant.Exchange.Assignments += @{ Name = $Name; Role = $Role; RoleAssigneeName = $App; Scope = $CustomResourceScope }
        Add-Write "NEW exo assignment $Name"
    }
    Mock Remove-ManagementRoleAssignment {
        param($Identity)
        $script:Tenant.Exchange.Assignments = @($script:Tenant.Exchange.Assignments | Where-Object { $_.Name -ne $Identity })
        Add-Write "REMOVE exo assignment $Identity"
    }
    Mock Test-ServicePrincipalAuthorization {
        param($Identity, $Resource)
        $inScope = [bool]$script:Tenant.Exchange.InScope
        @('Application Mail.Read', 'Application Mail.ReadWrite', 'Application Mail.Send') | ForEach-Object {
            [pscustomobject]@{ RoleName = $_; InScope = $inScope }
        }
    }
}

BeforeEach {
    $script:Tenant = New-EmptyTenant
    $script:Writes = @()
    $script:GraphCalls = @()
    $script:Faults = @()
    $script:Console = @()
    $script:Sleeps = @()
    $script:Installs = @()
    $script:Imports = @()
    $script:TokenRequests = @()
    $script:BrowserUris = @()
    $script:BrowserOpens = $false
    $script:Desktop = $false
    $script:Connected = $false
    $script:ExchangeConnected = $false
    $script:ExchangeDisconnected = $false
    $script:ContextTenant = $script:Ids.Tenant
    $script:ContextScopes = @()
    $script:SummaryDirs = @((Join-Path $TestDrive 'summary'))
    if (Test-Path (Join-Path $TestDrive 'summary')) { Remove-Item -Path (Join-Path $TestDrive 'summary') -Recurse -Force }
    New-Item -ItemType Directory -Path (Join-Path $TestDrive 'summary') -Force | Out-Null
}

Context 'Helpers' {
    It 'reads a Microsoft Graph PowerShell dictionary, such as AdditionalProperties (project#3847)' {
        $extra = [System.Collections.Generic.Dictionary[string, object]]::new()
        $extra['@odata.type'] = '#microsoft.graph.directoryRole'
        Get-NeologikProperty $extra '@odata.type' | Should -Be '#microsoft.graph.directoryRole'
        Get-NeologikProperty $extra 'missing' 'dflt' | Should -Be 'dflt'
        Test-NeologikProperty $extra '@odata.type' | Should -BeTrue
        Test-NeologikProperty $extra 'missing' | Should -BeFalse
    }

    It 'normalises scope sets (order, duplicates, whitespace)' {
        Get-NeologikScopeSet '  Mail.Read   User.Read Mail.Read ' | Should -Be 'Mail.Read User.Read'
        Get-NeologikScopeSet 'User.Read Mail.Read' | Should -Be (Get-NeologikScopeSet 'Mail.Read User.Read')
        Get-NeologikScopeSet '' | Should -Be ''
        Get-NeologikScopeSet $null | Should -Be ''
    }

    It 'validates GUIDs' {
        Test-NeologikGuid $script:Ids.Tenant | Should -BeTrue
        Test-NeologikGuid 'not-a-guid' | Should -BeFalse
        Test-NeologikGuid "x' or 1 eq 1" | Should -BeFalse
        Test-NeologikGuid '' | Should -BeFalse
    }

    It 'refuses PowerShell below 7.4 with an ACTION REQUIRED message' {
        Test-NeologikPowerShellVersion -Version ([version]'5.1.22621') | Should -BeFalse
        ($script:Console -join "`n") | Should -Match 'ACTION REQUIRED'
        ($script:Console -join "`n") | Should -Match 'PowerShell 7.4 or later'
        Test-NeologikPowerShellVersion -Version ([version]'7.4.0') | Should -BeTrue
    }
}

Context 'Input validation (nothing is contacted when an input is wrong)' {
    It 'refuses a command that names no grants file' {
        $code = Invoke-Run @{ }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The command names no grants file'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'takes the tenant and the short name of the environment from the agent grants file' {
        Add-AgentIdentities
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @((New-AgentGrantEntry))) }
        $code | Should -Be 0
        $console = $script:Console -join "`n"
        $console | Should -Match "Tenant:\s+$($script:Ids.Tenant), from the agent grants file"
        $console | Should -Match "Short name of the environment:\s+$script:ShortName, from the agent grants file"
        Should -Invoke Connect-MgGraph -Times 1
    }

    It 'needs -TenantId when the mailbox grants file alone is the bare list, which names no tenant' {
        Add-CompliantExchangeState
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile -AsArray) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The command does not give TenantId, and no file names the tenant'
        Should -Invoke Connect-MgGraph -Times 0
        $script:Console = @()
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile -AsArray); TenantId = $script:Ids.Tenant }
        $code | Should -Be 0
        ($script:Console -join "`n") | Should -Match "Tenant:\s+$($script:Ids.Tenant), from -TenantId"
    }

    It 'takes the tenant from the object-shaped mailbox grants file' {
        Add-CompliantExchangeState
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 0
        ($script:Console -join "`n") | Should -Match "Tenant:\s+$($script:Ids.Tenant), from the mailbox grants file"
    }

    It 'rejects a -TenantId or a -SharePointAppClientId that is not a GUID before contacting anything' {
        $grants = New-GrantsFile -Grants @()
        (Invoke-Run @{ AgentGrantsFile = $grants; TenantId = "abc' or displayName eq 'x" }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'TenantId must be a GUID'
        $script:Console = @()
        (Invoke-Run @{ AgentGrantsFile = $grants; SharePointAppClientId = 'nope' }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'SharePointAppClientId must be a GUID'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'reports a missing agent grants file' {
        $code = Invoke-Run @{ AgentGrantsFile = (Join-Path $TestDrive 'missing-grants.json') }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The agent grants file does not exist'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'reports a malformed agent grants file' {
        $grants = New-GrantsFile -Raw -RawContent '{"grants": ['
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'not valid JSON'
    }

    It 'reports an agent grants file of the wrong shape' {
        $grants = New-GrantsFile -Raw -RawContent '[{"IdentityAppId": "x"}]'
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'not the file that the Neologik Admin Tool exports'
    }

    It 'refuses an agent grants file exported from another tenant than -TenantId names' {
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry)) -TenantId $script:Ids.OtherTenant
        $code = Invoke-Run @{ AgentGrantsFile = $grants; TenantId = $script:Ids.Tenant }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'belongs to tenant'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'refuses a mailbox grants file of another tenant than the agent grants file names' {
        $grants = New-GrantsFile -Grants @()
        $mailboxes = New-MailboxFile -TenantId $script:Ids.OtherTenant
        $code = Invoke-Run @{ AgentGrantsFile = $grants; MailboxGrantsFile = $mailboxes }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The mailbox grants file belongs to tenant'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'rejects a ready grant entry without GUID ids or without scopes' {
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -ClientId 'nope'))
        (Invoke-Run @{ AgentGrantsFile = $grants }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'must be GUIDs'
        $script:Console = @()
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('', ' ')))
        (Invoke-Run @{ AgentGrantsFile = $grants }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'needs scopes'
    }

    It 'accepts grant entries that are not ready without validating their ids' {
        $entry = New-AgentGrantEntry -Status 'identity-not-stamped' -ClientId $null -UserId $null
        $grants = New-GrantsFile -Grants @($entry)
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 1
        Get-SummaryResult 'Grant to agent user: agent Support Agent' | Should -Be 'SKIPPED: the agent grants file marks the entry as not ready'
    }

    It 'validates every mailbox grants entry' {
        $file = New-MailboxFile -Entries @(@{ IdentityAppId = $script:Ids.MailboxAppId; IdentityObjectId = $script:Ids.MailboxObjectId; Mailbox = 'support@contoso.com' })
        (Invoke-Run @{ MailboxGrantsFile = $file }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'each entry needs DisplayName'
        $script:Console = @()
        $file = New-MailboxFile -Entries @(@{ IdentityAppId = 'x'; IdentityObjectId = $script:Ids.MailboxObjectId; Mailbox = 'support@contoso.com'; DisplayName = 'neo' })
        (Invoke-Run @{ MailboxGrantsFile = $file }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'must be GUIDs'
        $script:Console = @()
        $file = New-MailboxFile -Entries @(@{ IdentityAppId = $script:Ids.MailboxAppId; IdentityObjectId = $script:Ids.MailboxObjectId; Mailbox = 'not-an-address'; DisplayName = 'neo' })
        (Invoke-Run @{ MailboxGrantsFile = $file }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'is not a mailbox address'
        $script:Console = @()
        $file = New-MailboxFile -Raw -RawContent 'nonsense'
        (Invoke-Run @{ MailboxGrantsFile = $file }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'not valid JSON'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'rejects legacy application ids that are not GUIDs' {
        (Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile); RemoveLegacyGrantAppIds = @('old-monitor') }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'RemoveLegacyGrantAppIds must hold'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'refuses -RemoveLegacyGrantAppIds without the mailbox grants file that lists the adopted identities' {
        (Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @()); RemoveLegacyGrantAppIds = @($script:Ids.LegacyAppId) }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'RemoveLegacyGrantAppIds needs the mailbox grants file'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'rejects a mailbox grants file of the wrong shape, and adopted ids that are not GUIDs' {
        $file = New-MailboxFile -Raw -RawContent '{"IdentityAppId": "x"}'
        (Invoke-Run @{ MailboxGrantsFile = $file }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'does not have the expected form'
        $script:Console = @()
        $file = New-MailboxFile -Entries @() -AdoptedIdentityAppIds @('not-a-guid')
        (Invoke-Run @{ MailboxGrantsFile = $file }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'adoptedIdentityAppIds must hold'
        Should -Invoke Connect-MgGraph -Times 0
    }
}

Context 'Modules and sign-in' {
    It 'installs a missing Graph module before importing one consistent version' {
        Add-AgentIdentities
        Mock Get-NeologikAvailableModuleVersion {
            param($Name)
            if ($Name -eq 'Microsoft.Graph.Applications' -and $script:Installs -notcontains $Name) { return @() }
            @([version]'2.38.0', [version]'2.20.0')
        }
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @((New-AgentGrantEntry))) }
        $code | Should -Be 0
        $script:Installs | Should -Contain 'Microsoft.Graph.Applications'
        $script:Imports | Should -Contain 'Microsoft.Graph.Authentication 2.38.0'
        $script:Imports | Should -Contain 'Microsoft.Graph.Applications 2.38.0'
        # The grants need no group or directory-role module.
        $script:Imports | Should -Not -Contain 'Microsoft.Graph.Groups 2.38.0'
    }

    It 'stops with ACTION REQUIRED when a module cannot be installed' {
        Mock Get-NeologikAvailableModuleVersion { @() }
        Mock Install-NeologikModule { throw 'No match was found for the specified search criteria' }
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @()) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'ACTION REQUIRED'
        ($script:Console -join "`n") | Should -Match 'Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Applications -Scope CurrentUser -Force'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'stops with ACTION REQUIRED when the Graph sign-in fails' {
        Mock Connect-MgGraph { throw 'Device code authentication timed out' }
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @()) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The sign-in to Microsoft Graph did not complete'
        Should -Invoke Get-MgServicePrincipal -Times 0
    }

    It 'stops when the session landed in a different tenant' {
        $script:ContextTenant = $script:Ids.OtherTenant
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @()) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The sign-in is for tenant'
        Should -Invoke Get-MgServicePrincipal -Times 0
    }

    It 'requests the grant write scope only with an agent grants file, and never a directory or group write scope' {
        Add-AgentIdentities
        Add-CompliantExchangeState
        $graphScopes = {
            $request = @($script:TokenRequests | Where-Object { $_.Uri -match '/devicecode$' }) | Select-Object -Last 1
            @($request.Body.scope -split ' ')
        }
        $null = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @((New-AgentGrantEntry))) }
        $scopes = & $graphScopes
        $scopes | Should -Contain 'Directory.Read.All'
        $scopes | Should -Contain 'User.Read'
        $scopes | Should -Contain 'AppRoleAssignment.ReadWrite.All'
        $scopes | Should -Contain 'DelegatedPermissionGrant.ReadWrite.All'
        $scopes | Should -Contain 'offline_access'
        foreach ($never in @('RoleManagement.ReadWrite.Directory', 'GroupMember.ReadWrite.All', 'Group.ReadWrite.All', 'User.Invite.All',
                'Application.ReadWrite.All', 'AgentIdentityBlueprint.Create', 'AgentIdentityBlueprintPrincipal.ReadWrite.All')) {
            $scopes | Should -Not -Contain $never -Because 'the grants run writes no directory object other than the grants'
        }
        $script:TokenRequests = @()
        $null = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile) }
        (& $graphScopes) | Should -Not -Contain 'DelegatedPermissionGrant.ReadWrite.All'
        (& $graphScopes) | Should -Contain 'Directory.Read.All'
        Should -Invoke Connect-MgGraph -Times 2 -ParameterFilter { $AccessToken -is [securestring] -and -not $UseDeviceCode }
    }

    It 'warns when the session lacks a requested permission' {
        $script:ContextScopes = @('User.Read')
        $null = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @()) }
        ($script:Console -join "`n") | Should -Match 'lacks the permission'
    }

    It 'uses the Azure CLI token when asked and never prints it' {
        Add-AgentIdentities
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @((New-AgentGrantEntry))); UseAzureCliToken = $true }
        $code | Should -Be 0
        Should -Invoke Invoke-NeologikAzureCli -Times 1 -ParameterFilter { ($Arguments -join ' ') -match "get-access-token --resource-type ms-graph --tenant $($script:Ids.Tenant)" }
        Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $AccessToken -is [securestring] -and -not $UseDeviceCode }
        ($script:Console -join "`n") | Should -Not -Match 'eyJ0b2tlbg'
    }

    It 'stops with ACTION REQUIRED when the Azure CLI is absent or not signed in' {
        Mock Test-NeologikCommand { $false }
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @()); UseAzureCliToken = $true }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'The Azure CLI is not installed'
        Mock Test-NeologikCommand { $true }
        Mock Invoke-NeologikAzureCli { @{ ExitCode = 1; Output = @() } }
        $script:Console = @()
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @()); UseAzureCliToken = $true }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'az login --tenant'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'stops with a clear message when the tenant holds no service principal of Microsoft Graph' {
        $script:Tenant.ServicePrincipals = @($script:Tenant.ServicePrincipals | Where-Object { $_.id -ne $script:Ids.GraphSpId })
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @((New-AgentGrantEntry))) }
        $code | Should -Be 1
        Get-SummaryResult 'Service principal of Microsoft Graph' | Should -Be 'MISSING: report to Neologik'
        $script:Writes | Should -HaveCount 0
    }
}

Context 'Sign-in and preflight' {
    It 'prints the sign-in address and code itself, waits, and signs in to Graph with the token' {
        Add-AgentIdentities
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @((New-AgentGrantEntry))) }
        $code | Should -Be 0
        $console = $script:Console -join "`n"
        $console | Should -Match 'https://microsoft.com/devicelogin'
        $console | Should -Match 'Enter the code: ABCD-EFGH'
        $console | Should -Match 'valid for 15 minutes'
        Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $AccessToken -is [securestring] }
        @($script:TokenRequests | Where-Object { $_.Uri -match '/devicecode$' }) | Should -HaveCount 1 -Because 'the grants run signs in to Microsoft Graph only'
        $console | Should -Not -Match 'eyJ0b2tlbg'
    }

    It 'keeps waiting while the sign-in is pending, reports every 30 seconds and gives up when the code expires' {
        Mock Invoke-NeologikTokenRequest {
            param($Uri, $Body)
            $script:TokenRequests += @{ Uri = $Uri; Body = $Body }
            if ($Uri -match '/devicecode$') {
                return @{ StatusCode = 200; Body = @{ device_code = 'dc-1'; user_code = 'WXYZ-1234'; verification_uri = 'https://microsoft.com/devicelogin'; expires_in = 120; interval = 10 } }
            }
            return @{ StatusCode = 400; Body = @{ error = 'authorization_pending'; error_description = 'AADSTS70016: Pending end-user authorization.' } }
        }
        Mock Test-NeologikCommand { $false }
        Mock Connect-MgGraph { throw 'Device code authentication timed out' }
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @()) }
        $code | Should -Be 1
        $console = $script:Console -join "`n"
        $console | Should -Match 'The script still waits for the sign-in to Microsoft Graph\. Code WXYZ-1234'
        $console | Should -Match 'code expired after 2 minutes'
        # Bounded: polled at once and after each of the twelve 10-second waits, never more.
        @($script:TokenRequests | Where-Object { $_.Uri -match '/token$' }).Count | Should -Be 13
        ($script:Sleeps | Measure-Object -Sum).Sum | Should -Be 120
        $console | Should -Match 'The sign-in to Microsoft Graph did not complete\. The script tried four methods'
        Should -Invoke Get-MgServicePrincipal -Times 0
    }

    It 'falls back to the Azure CLI session when the device code is declined, then to the Graph PowerShell prompt' {
        Add-AgentIdentities
        Mock Invoke-NeologikTokenRequest {
            param($Uri, $Body)
            if ($Uri -match '/devicecode$') {
                return @{ StatusCode = 200; Body = @{ device_code = 'dc-1'; user_code = 'ABCD-EFGH'; verification_uri = 'https://microsoft.com/devicelogin'; expires_in = 900; interval = 5 } }
            }
            return @{ StatusCode = 400; Body = @{ error = 'authorization_declined'; error_description = 'AADSTS70020: The end user declined.' } }
        }
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry))
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 0
        $console = $script:Console -join "`n"
        $console | Should -Match 'The sign-in to Microsoft Graph did not complete\. AADSTS70020'
        $console | Should -Match 'The script now tries the Azure CLI session of this workstation'
        Should -Invoke Invoke-NeologikAzureCli -Times 1 -ParameterFilter { ($Arguments -join ' ') -match 'ms-graph' }
        Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $AccessToken -is [securestring] }

        # No CLI either: the Graph PowerShell device-code prompt is the last method.
        Mock Test-NeologikCommand { $false }
        $script:Console = @()
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 0
        Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $UseDeviceCode }
        ($script:Console -join "`n") | Should -Match 'The script now tries the device code prompt of Microsoft Graph PowerShell'
    }

    It 'stops before the sign-in with ACTION REQUIRED when an endpoint is not reachable' {
        Mock Test-NeologikEndpoint { param($Uri) $Uri -notmatch 'graph\.microsoft\.com' }
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @()) }
        $code | Should -Be 1
        $console = $script:Console -join "`n"
        $console | Should -Match 'ACTION REQUIRED'
        $console | Should -Match 'cannot reach:'
        $console | Should -Match 'Microsoft Graph: https://graph.microsoft.com/'
        Should -Invoke Invoke-NeologikTokenRequest -Times 0
        Should -Invoke Connect-MgGraph -Times 0
        $script:Writes | Should -HaveCount 0
    }

    It 'checks the Exchange Online address only with a mailbox grants file, and never Azure Resource Manager' {
        Add-AgentIdentities
        Mock Test-NeologikEndpoint { param($Uri) $Uri -notmatch 'outlook\.office365\.com' }
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @((New-AgentGrantEntry))) }
        $code | Should -Be 0
        Should -Invoke Test-NeologikEndpoint -Times 0 -ParameterFilter { $Uri -match 'management\.azure\.com' }
        $script:Console = @()
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'Exchange Online: https://outlook.office365.com/'
        Should -Invoke Connect-ExchangeOnline -Times 0
    }

    It 'stops a real run when the signed-in account is not an active Global Administrator, and only warns in verify-only' {
        Add-AgentIdentities
        $script:Tenant.MeDirectoryRoles = @(@{ id = 'role-ua'; displayName = 'User Administrator'; roleTemplateId = 'fe930be7-5e62-47db-91af-98c3a49a38b1' })
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry))
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 1
        $console = $script:Console -join "`n"
        $console | Should -Match 'admin@contoso.com does not hold an active Global Administrator role'
        $console | Should -Match 'Privileged Identity Management'
        Should -Invoke Get-MgServicePrincipal -Times 0
        $script:Writes | Should -HaveCount 0

        $script:Console = @()
        $code = Invoke-Run @{ AgentGrantsFile = $grants; Verify = $true }
        $code | Should -Be 0
        ($script:Console -join "`n") | Should -Match 'The run with -Verify continues'
    }
}

Context 'The agent grants file (step 1)' {
    It 'applies the file and nothing else: one write, no Exchange Online sign-in' {
        Add-AgentIdentities -NoGrants
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read')))
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 0
        Get-SummaryResult 'Grant to agent user: agent Support Agent' | Should -Be 'Granted: User.Read'
        $script:Writes | Should -HaveCount 1
        $script:Writes[0] | Should -BeLike 'POST grant*'
        Should -Invoke Connect-ExchangeOnline -Times 0
        $console = $script:Console -join "`n"
        $console | Should -Match 'Neologik agent access: the grants run'
        $console | Should -Match 'Step 1: the grants to agent users'
        $console | Should -Match 'The grants run is complete'
    }

Context 'Browser sign-in' {
    BeforeAll {
        # An access token that names the account admin@contoso.com. The script reads the
        # claims and never checks the signature.
        $claims = ConvertTo-NeologikBase64Url ([System.Text.Encoding]::UTF8.GetBytes('{"upn":"admin@contoso.com"}'))
        $script:AdminJwt = "eyJhbGciOiJub25lIn0.$claims.sig"
        function Get-BrowserQuery {
            # The parameters of the sign-in address that the script opened, by position.
            param([int]$Index)
            ConvertFrom-NeologikQueryString ($script:BrowserUris[$Index].Split('?', 2)[1])
        }
    }

    BeforeEach {
        $script:BrowserOpens = $true
        # The browser returns the code with the state of the address that the script opened.
        Mock Wait-NeologikLoopbackRequest {
            param($Listener, $TimeoutSeconds, $Label)
            $query = Get-BrowserQuery -Index ($script:BrowserUris.Count - 1)
            @{ code = "code-$Label"; state = $query.state }
        }
        Mock Invoke-NeologikTokenRequest {
            param($Uri, $Body)
            $script:TokenRequests += @{ Uri = $Uri; Body = $Body }
            if ($Uri -match '/devicecode$') {
                return @{ StatusCode = 200; Body = @{ device_code = 'dc-1'; user_code = 'ABCD-EFGH'; verification_uri = 'https://microsoft.com/devicelogin'; expires_in = 900; interval = 5 } }
            }
            return @{ StatusCode = 200; Body = @{ access_token = $script:AdminJwt; refresh_token = 'rt-1' } }
        }
    }

    It 'signs in to Graph in the browser first and asks for no device code' {
        Add-AgentIdentities
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @((New-AgentGrantEntry))) }
        $code | Should -Be 0
        @($script:TokenRequests | Where-Object { $_.Uri -match '/devicecode$' }).Count | Should -Be 0
        $script:BrowserUris | Should -HaveCount 1 -Because 'the grants run signs in to Microsoft Graph only'

        $graphUri = $script:BrowserUris[0]
        $graphUri | Should -Match "^https://login\.microsoftonline\.com/$($script:Ids.Tenant)/oauth2/v2\.0/authorize\?"
        $graphQuery = Get-BrowserQuery -Index 0
        $graphQuery.client_id | Should -Be '14d82eec-204b-4c2f-b7e8-296a70dab67e'
        $graphQuery.redirect_uri | Should -Be 'http://localhost:50999/'
        $graphQuery.code_challenge_method | Should -Be 'S256'
        $graphQuery.prompt | Should -Be 'select_account'
        @($graphQuery.scope -split ' ') | Should -Contain 'Directory.Read.All'
        $graphToken = @($script:TokenRequests | Where-Object { $_.Body.client_id -eq '14d82eec-204b-4c2f-b7e8-296a70dab67e' }) | Select-Object -First 1
        $graphToken.Uri | Should -Match '/token$'
        $graphToken.Body.grant_type | Should -Be 'authorization_code'
        $graphToken.Body.code | Should -Be 'code-Microsoft Graph'
        $graphToken.Body.redirect_uri | Should -Be 'http://localhost:50999/'
        # The proof key: the challenge in the address is the hash of the verifier in the token request.
        $hash = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::ASCII.GetBytes($graphToken.Body.code_verifier))
        $graphQuery.code_challenge | Should -Be (ConvertTo-NeologikBase64Url $hash)

        Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $AccessToken -is [securestring] -and -not $UseDeviceCode }
        $console = $script:Console -join "`n"
        $console | Should -Match 'opens the sign-in page in the browser of this computer'
        $console | Should -Not -Match 'Enter the code'
        $console | Should -Not -Match ([regex]::Escape($script:AdminJwt))
    }

    It 'falls back to the device code when the browser sign-in does not complete in time' {
        Add-AgentIdentities
        Mock Wait-NeologikLoopbackRequest { $null }
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @((New-AgentGrantEntry))) }
        $code | Should -Be 0
        $console = $script:Console -join "`n"
        $console | Should -Match 'The sign-in to Microsoft Graph in the browser did not complete within 5 minutes'
        $console | Should -Match 'Enter the code: ABCD-EFGH'
        @($script:TokenRequests | Where-Object { $_.Uri -match '/devicecode$' }).Count | Should -Be 1
    }

    It 'falls back to the device code when no browser opens' {
        Add-AgentIdentities
        $script:BrowserOpens = $false
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @((New-AgentGrantEntry))) }
        $code | Should -Be 0
        ($script:Console -join "`n") | Should -Match 'The sign-in to Microsoft Graph in the browser did not start\. The script tries a device code'
        Should -Invoke Wait-NeologikLoopbackRequest -Times 0
    }

    It 'names a Conditional Access refusal in the browser and falls back to the device code' {
        Add-AgentIdentities
        Mock Wait-NeologikLoopbackRequest {
            $query = Get-BrowserQuery -Index ($script:BrowserUris.Count - 1)
            @{ error = 'access_denied'; error_description = 'AADSTS53003: Access has been blocked by Conditional Access policies.'; state = $query.state }
        }
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @((New-AgentGrantEntry))) }
        $code | Should -Be 0
        ($script:Console -join "`n") | Should -Match 'A Conditional Access policy of the tenant refused the sign-in to Microsoft Graph with the browser\. AADSTS53003'
        @($script:TokenRequests | Where-Object { $_.Body.grant_type -eq 'authorization_code' }).Count | Should -Be 0
        @($script:TokenRequests | Where-Object { $_.Uri -match '/devicecode$' }).Count | Should -Be 1
    }

    It 'ignores an answer whose state this run did not request' {
        Add-AgentIdentities
        Mock Wait-NeologikLoopbackRequest { @{ code = 'code-other'; state = 'another-state' } }
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @((New-AgentGrantEntry))) }
        $code | Should -Be 0
        ($script:Console -join "`n") | Should -Match 'returned an answer that this run did not request'
        @($script:TokenRequests | Where-Object { $_.Body.grant_type -eq 'authorization_code' }).Count | Should -Be 0
    }

    It 'names a Conditional Access refusal of the device code and tries the next method at once' {
        Add-AgentIdentities
        $script:BrowserOpens = $false
        Mock Invoke-NeologikTokenRequest {
            param($Uri, $Body)
            if ($Uri -match '/devicecode$') {
                return @{ StatusCode = 200; Body = @{ device_code = 'dc-1'; user_code = 'ABCD-EFGH'; verification_uri = 'https://microsoft.com/devicelogin'; expires_in = 900; interval = 5 } }
            }
            return @{ StatusCode = 400; Body = @{ error = 'invalid_grant'; error_codes = @(53003); error_description = 'AADSTS53003: Access has been blocked by Conditional Access policies.' } }
        }
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @((New-AgentGrantEntry))) }
        $code | Should -Be 0
        $console = $script:Console -join "`n"
        $console | Should -Match 'A Conditional Access policy of the tenant refused the sign-in to Microsoft Graph with a device code'
        $console | Should -Match 'The script now tries the Azure CLI session of this workstation'
        ($script:Sleeps | Measure-Object -Sum).Sum | Should -Be 0
    }

    It 'signs in to Exchange Online in the browser first, with the account of the Graph sign-in' {
        Add-CompliantExchangeState
        $script:Desktop = $true
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 0
        Should -Invoke Connect-ExchangeOnline -Times 1 -ParameterFilter { -not $Device -and $UserPrincipalName -eq 'admin@contoso.com' }
        Should -Invoke Connect-ExchangeOnline -Times 0 -ParameterFilter { $Device }
    }

    It 'falls back to the Exchange Online device code when the browser sign-in fails' {
        Add-CompliantExchangeState
        $script:Desktop = $true
        Mock Connect-ExchangeOnline { param([switch]$Device) if (-not $Device) { throw 'The browser sign-in was cancelled' }; $script:ExchangeConnected = $true }
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 0
        Should -Invoke Connect-ExchangeOnline -Times 1 -ParameterFilter { $Device }
        ($script:Console -join "`n") | Should -Match 'The sign-in to Exchange Online in the browser did not complete\. The browser sign-in was cancelled\. The script tries a device code'
        $script:ExchangeConnected | Should -BeTrue
    }
}

Context 'Browser sign-in: the loopback listener' {
    It 'reads the result of the sign-in from a real loopback request and answers the browser' {
        # The real listener: the default mock replaces the command name, not the function.
        $listener = & (Get-Command -Name Start-NeologikLoopbackListener -CommandType Function)
        $http = [System.Net.Http.HttpClient]::new()
        try {
            $task = $http.GetAsync("http://localhost:$($listener.Port)/?code=abc%2B1&state=xyz")
            $query = Wait-NeologikLoopbackRequest -Listener $listener -TimeoutSeconds 10 -Label 'Test'
            $query.code | Should -Be 'abc+1'
            $query.state | Should -Be 'xyz'
            $response = $task.GetAwaiter().GetResult()
            [int]$response.StatusCode | Should -Be 200
            $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | Should -Match 'The sign-in is complete\. Return to the PowerShell window\.'
        }
        finally {
            $listener.Stop()
            $http.Dispose()
        }
    }

    It 'answers a request with no result with 404 and gives up when the time ends' {
        # The real listener: the default mock replaces the command name, not the function.
        $listener = & (Get-Command -Name Start-NeologikLoopbackListener -CommandType Function)
        $http = [System.Net.Http.HttpClient]::new()
        try {
            $task = $http.GetAsync("http://localhost:$($listener.Port)/favicon.ico")
            $query = Wait-NeologikLoopbackRequest -Listener $listener -TimeoutSeconds 2 -Label 'Test'
            $query | Should -BeNullOrEmpty
            [int]($task.GetAwaiter().GetResult().StatusCode) | Should -Be 404
        }
        finally {
            $listener.Stop()
            $http.Dispose()
        }
    }
}

    It 'does nothing beyond the SharePoint marker for a file with no entries' {
        $grants = New-GrantsFile -Grants @() -SharePoint $false
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Not needed'
        @($script:Summary | Where-Object { $_.Item -like 'Grant to agent user:*' }) | Should -HaveCount 0
        $script:Writes | Should -HaveCount 0
    }

    It 'surfaces export warnings from the file' {
        $grants = New-GrantsFile -Grants @() -Warnings @('apps not enumerated: registry unavailable')
        $null = Invoke-Run @{ AgentGrantsFile = $grants }
        ($script:Console -join "`n") | Should -Match 'Warning in the agent grants file: apps not enumerated'
    }

    It 'verifies an existing grant with the same scope set in any order' {
        Add-AgentIdentities -AgentScope 'Sites.ReadWrite.All User.Read'
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read', 'Sites.ReadWrite.All')))
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 0
        Get-SummaryResult 'Grant to agent user: agent Support Agent' | Should -Be 'Already granted'
        $script:Writes | Should -HaveCount 0
    }

    It 'creates the grant when absent and aligns it when the scope differs' {
        Add-AgentIdentities -NoGrants
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read', 'Mail.Read')))
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 0
        Get-SummaryResult 'Grant to agent user: agent Support Agent' | Should -Be 'Granted: Mail.Read User.Read'
        @($script:Writes | Where-Object { $_ -like 'POST grant*' }) | Should -HaveCount 1
        $created = @((Get-FakeSp -Id $script:Ids.AgentIdentitySp).grants)[0]
        $created.principalId | Should -Be $script:Ids.AgentUser
        $created.resourceId | Should -Be $script:Ids.GraphSpId
        $created.consentType | Should -Be 'Principal'
        # Now the platform adds a pack: the existing grant is patched, not duplicated.
        $script:Writes = @()
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read', 'Mail.Read', 'Calendars.Read')))
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 0
        Get-SummaryResult 'Grant to agent user: agent Support Agent' | Should -Be 'Updated: Calendars.Read Mail.Read User.Read'
        @($script:Writes | Where-Object { $_ -like 'PATCH grant*' }) | Should -HaveCount 1
        @((Get-FakeSp -Id $script:Ids.AgentIdentitySp).grants) | Should -HaveCount 1
    }

    It 'never touches a grant on another resource with the same client and principal' {
        Add-AgentIdentities -NoGrants
        $agentSp = Get-FakeSp -Id $script:Ids.AgentIdentitySp
        $agentSp.grants = @(@{ id = 'grant-sharepoint'; clientId = $script:Ids.AgentIdentitySp; principalId = $script:Ids.AgentUser; resourceId = 'sharepoint-resource'; consentType = 'Principal'; scope = 'AllSites.Read' })
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read')))
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 0
        @($script:Writes | Where-Object { $_ -like 'POST grant*' }) | Should -HaveCount 1
        @($script:Writes | Where-Object { $_ -like 'PATCH grant*' }) | Should -HaveCount 0
        @($agentSp.grants | Where-Object { $_.id -eq 'grant-sharepoint' })[0].scope | Should -Be 'AllSites.Read'
    }

    It 'handles many agents and apps in one file' {
        Add-AgentIdentities -AgentScope 'User.Read' -AppScope 'User.Read Mail.Read'
        $entries = @(
            (New-AgentGrantEntry -Kind 'agent' -Name 'Support Agent' -Scopes @('User.Read')),
            (New-AgentGrantEntry -Kind 'app' -Name 'Reference App' -ClientId $script:Ids.AppIdentityApp -UserId $script:Ids.AppUser -Scopes @('User.Read', 'Mail.Read', 'Mail.Send')),
            (New-AgentGrantEntry -Kind 'app' -Name 'MS Planner' -Status 'identity-not-stamped' -ClientId $null -UserId $null),
            (New-AgentGrantEntry -Kind 'agent' -Name "O'Brien Agent" -ClientId ([guid]::NewGuid().ToString()) -UserId ([guid]::NewGuid().ToString()) -Scopes @('User.Read'))
        )
        $grants = New-GrantsFile -Grants $entries
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 1
        Get-SummaryResult 'Grant to agent user: agent Support Agent' | Should -Be 'Already granted'
        Get-SummaryResult 'Grant to agent user: app Reference App' | Should -Be 'Updated: Mail.Read Mail.Send User.Read'
        Get-SummaryResult 'Grant to agent user: app MS Planner' | Should -Be 'SKIPPED: the agent grants file marks the entry as not ready'
        Get-SummaryResult "Grant to agent user: agent O'Brien Agent" | Should -Be 'MISSING: the tenant holds no agent identity with this client id'
        $script:Writes | Should -HaveCount 1
    }

    It 'retries a refused scope string with a rotated order and reports success only after read-back' {
        Add-AgentIdentities -NoGrants
        $script:Tenant.GrantRefusals = @('Mail.Read Sites.ReadWrite.All User.Read', 'Sites.ReadWrite.All User.Read Mail.Read')
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read', 'Mail.Read', 'Sites.ReadWrite.All')))
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 0
        Get-SummaryResult 'Grant to agent user: agent Support Agent' | Should -Be 'Granted: Mail.Read Sites.ReadWrite.All User.Read'
        @($script:Writes | Where-Object { $_ -like 'POST grant*' }) | Should -HaveCount 1
        ($script:Console -join "`n") | Should -Match 'Attempt 2: Microsoft Entra ID refused'
    }

    It 'reports PENDING when every rotation is refused' {
        Add-AgentIdentities -NoGrants
        $script:Tenant.GrantRefusals = @('Mail.Read User.Read', 'User.Read Mail.Read', 'Mail.Read User.Read')
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read', 'Mail.Read')))
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 1
        Get-SummaryResult 'Grant to agent user: agent Support Agent' | Should -Be 'PENDING: Microsoft Entra ID refused the permissions. Report to Neologik'
    }

    It 'stops retrying on a privilege refusal and names the missing permission' {
        Add-AgentIdentities -NoGrants
        $script:Faults += @{ Match = 'POST /oauth2PermissionGrants$'; Status = 403; Code = 'Authorization_RequestDenied'; Message = 'Insufficient privileges to complete the operation.'; Remaining = 5 }
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read')))
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 1
        (Get-SummaryResult 'Grant to agent user: agent Support Agent') | Should -Match '^FAILED: insufficient privileges'
        @($script:GraphCalls | Where-Object { $_ -eq 'POST /oauth2PermissionGrants' }) | Should -HaveCount 1
    }

    It 'grants declared component Graph roles and reports scoped or non-Graph declarations' {
        Add-AgentIdentities
        $roles = @(
            [ordered]@{ app = 'refapp'; component = 'refapp-api'; identityName = 'neo-refapp-api'; resource = 'graph'; roleName = 'User.Read.All'; scopeType = $null; scopeEnvVar = $null },
            [ordered]@{ app = 'refapp'; component = 'refapp-api'; identityName = 'neo-refapp-api'; resource = 'graph'; roleName = 'Mail.Read'; scopeType = 'mailbox'; scopeEnvVar = 'MAILBOX' },
            [ordered]@{ app = 'refapp'; component = 'refapp-api'; identityName = 'neo-refapp-api'; resource = 'exchange'; roleName = 'Application Mail.Read'; scopeType = $null; scopeEnvVar = $null },
            [ordered]@{ app = 'other'; component = 'other-api'; identityName = 'neo-other-api'; resource = 'graph'; roleName = 'User.Read.All'; scopeType = $null; scopeEnvVar = $null },
            [ordered]@{ app = 'broken'; component = 'broken-api'; identityName = ''; resource = 'graph'; roleName = ''; scopeType = $null; scopeEnvVar = $null }
        )
        $grants = New-GrantsFile -Grants @() -ComponentRoles $roles
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 1
        Get-SummaryResult 'App refapp permission: User.Read.All' | Should -Be 'Granted'
        Get-SummaryResult 'App refapp permission: Mail.Read' | Should -Be 'SKIPPED: the permission is limited to one mailbox. An administrator grants the permission in Exchange Online or in SharePoint'
        Get-SummaryResult 'App refapp permission: Application Mail.Read' | Should -Be 'SKIPPED: the role belongs to exchange, not to Microsoft Graph'
        Get-SummaryResult 'App other permission: User.Read.All' | Should -Be 'MISSING: the tenant holds no workload identity with this name'
        Get-SummaryResult 'App broken permission: ' | Should -Be 'SKIPPED: the entry in the agent grants file is incomplete'
        @($script:Writes | Where-Object { $_ -like "NEW approle $($script:Ids.ComponentSpId)*" }) | Should -HaveCount 1
        # Second run: the component role is already there.
        $script:Writes = @()
        $null = Invoke-Run @{ AgentGrantsFile = $grants }
        Get-SummaryResult 'App refapp permission: User.Read.All' | Should -Be 'Already granted'
        $script:Writes | Should -HaveCount 0
    }

    It 'confirms the Sites.Selected consent of this environment''s SharePoint app' {
        Add-SharePointApp -WithConsent -Second
        $grants = New-GrantsFile -Grants @() -SharePoint $true
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Present'
        $script:Writes | Should -HaveCount 0
    }

    It 'prints the SharePoint consent URL when Sites.Selected is missing' {
        Add-SharePointApp
        $grants = New-GrantsFile -Grants @() -SharePoint $true
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 1
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'MISSING: the script printed the consent address'
        ($script:Console -join "`n") | Should -Match "adminconsent\?client_id=$($script:Ids.SharePointAppId)"
    }

    It 'grants Sites.Selected in place of the consent address when an earlier application holds the consent' {
        Add-SharePointApp
        Add-EarlierSharePointApp
        $grants = New-GrantsFile -Grants @() -SharePoint $true
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be "Granted to 'Neologik SharePoint Access - $script:ShortName'"
        $script:Writes | Should -Be @("NEW approle $($script:Ids.SharePointSpId) $($script:AppRoleIds['Sites.Selected'])")
        ($script:Console -join "`n") | Should -Not -Match 'adminconsent\?client_id='
    }

    It 'finds the SharePoint application by the client id that the command names' {
        $script:Tenant.ServicePrincipals += New-FakeSp -Id $script:Ids.SharePointSpId -AppId $script:Ids.SharePointAppId -DisplayName 'Contoso document access'
        Add-FakeAppRole -SpId $script:Ids.SharePointSpId -RoleName 'Sites.Selected'
        $grants = New-GrantsFile -Grants @() -SharePoint $true
        $code = Invoke-Run @{ AgentGrantsFile = $grants; SharePointAppClientId = $script:Ids.SharePointAppId }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Present'
    }

    It 'falls back to the single prefix match when no file and no parameter names the short name, and reports ambiguity as UNKNOWN' {
        Add-SharePointApp -WithConsent
        $grants = New-GrantsFile -Grants @() -SharePoint $true -Environment ''
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Present'
        $script:Tenant.ServicePrincipals += New-FakeSp -Id $script:Ids.SharePoint2SpId -AppId $script:Ids.SharePoint2AppId -DisplayName 'Neologik SharePoint Access - other01'
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 1
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'UNKNOWN: the tenant holds several SharePoint applications. Add -SolutionShortName or -SharePointAppClientId to the command'
        # -SolutionShortName names the environment when the file does not.
        $code = Invoke-Run @{ AgentGrantsFile = $grants; SolutionShortName = $script:ShortName }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Present'
        ($script:Console -join "`n") | Should -Match "Short name of the environment:\s+$script:ShortName, from -SolutionShortName"
    }

    It 'reports a missing SharePoint app' {
        $grants = New-GrantsFile -Grants @() -SharePoint $true
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 1
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'MISSING: the tenant holds no SharePoint application'
    }
}

Context 'The mailbox grants file (step 2)' {
    It 'verifies a fully granted mailbox without writing, and always disconnects' {
        Add-CompliantExchangeState
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Mailbox grant: support@contoso.com for neo-support' | Should -Be 'Already granted'
        $script:Writes | Should -HaveCount 0
        $script:ExchangeConnected | Should -BeTrue
        $script:ExchangeDisconnected | Should -BeTrue
        Should -Invoke Connect-ExchangeOnline -Times 1 -ParameterFilter { $Device }
        ($script:Console -join "`n") | Should -Match 'Step 2: the Exchange Online mailbox grants'
    }

    It 'creates the pointer, the scope and the three assignments when nothing exists' {
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Mailbox grant: support@contoso.com for neo-support' | Should -Be 'Granted: 3 role(s) added'
        $script:Writes | Should -Contain "NEW exo sp $($script:Ids.MailboxAppId)"
        $script:Writes | Should -Contain 'NEW exo scope Scope-neo-support'
        @($script:Writes | Where-Object { $_ -like 'NEW exo assignment*' }) | Should -HaveCount 3
        Should -Invoke New-ManagementScope -Times 1 -ParameterFilter { $RecipientRestrictionFilter -eq "PrimarySmtpAddress -eq 'support@contoso.com'" }
        Should -Invoke New-ManagementRoleAssignment -Times 3 -ParameterFilter { $App -eq $script:Ids.MailboxObjectId -and $CustomResourceScope -eq 'Scope-neo-support' }
        # Second run verifies without writing.
        $script:Writes = @()
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
    }

    It 'reuses an existing scope with the same recipient filter under another name' {
        $script:Tenant.Exchange.Scopes += @{ Name = 'Scope-email-monitor'; RecipientFilter = "PrimarySmtpAddress -eq 'support@contoso.com'" }
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 0
        Should -Invoke New-ManagementScope -Times 0
        Should -Invoke New-ManagementRoleAssignment -Times 3 -ParameterFilter { $CustomResourceScope -eq 'Scope-email-monitor' }
        ($script:Console -join "`n") | Should -Match 'uses the existing management scope'
    }

    It 'reports PENDING while Exchange has not propagated the grant' {
        $script:Tenant.Exchange.InScope = $false
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Mailbox grant: support@contoso.com for neo-support' | Should -Be 'PENDING: run the script again to confirm the mailbox grant'
    }

    It 'reports PENDING when the authorisation test itself fails, without stopping the run' {
        Mock Test-ServicePrincipalAuthorization { throw 'The service principal was not found' }
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Mailbox grant: support@contoso.com for neo-support' | Should -Be 'PENDING: run the script again to confirm the mailbox grant'
        $script:ExchangeDisconnected | Should -BeTrue
    }

    It 'enables organisation customisation once when the tenant is dehydrated' {
        $script:Tenant.Exchange.Dehydrated = $true
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 0
        Should -Invoke Enable-OrganizationCustomization -Times 1
        $script:Sleeps | Should -Contain 60
    }

    It 'records a failed grant with its reason and still disconnects' {
        Mock New-ManagementRoleAssignment { throw 'The user is not assigned to any management roles' }
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Mailbox grant: support@contoso.com for neo-support') | Should -Match '^FAILED: The user is not assigned'
        $script:ExchangeDisconnected | Should -BeTrue
    }

    It 'skips every mailbox item when the Exchange sign-in fails' {
        Mock Connect-ExchangeOnline { throw 'Device login timed out' }
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile); RemoveLegacyGrantAppIds = @($script:Ids.LegacyAppId) }
        $code | Should -Be 1
        Get-SummaryResult 'Mailbox grant: support@contoso.com for neo-support' | Should -Be 'SKIPPED: the sign-in to Exchange Online failed'
        Get-SummaryResult "Mailbox grant to remove: $($script:Ids.LegacyAppId)" | Should -Be 'SKIPPED: the sign-in to Exchange Online failed'
        Should -Invoke Disconnect-ExchangeOnline -Times 0
        ($script:Console -join "`n") | Should -Match 'an Exchange Administrator or as a Global Administrator'
    }

    It 'installs the Exchange module when absent and skips when it cannot be installed' {
        Mock Get-NeologikAvailableModuleVersion { param($Name) if ($Name -eq 'ExchangeOnlineManagement' -and $script:Installs -notcontains $Name) { @() } else { @([version]'3.10.0') } }
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 0
        $script:Installs | Should -Contain 'ExchangeOnlineManagement'
        Mock Install-NeologikModule { throw 'no gallery access' }
        $script:Installs = @()
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Mailbox grant: support@contoso.com for neo-support' | Should -Be 'SKIPPED: the Exchange Online module is not available'
    }

    It 'removes a retired identity''s assignments and pointer, leaving the scope' {
        $x = $script:Tenant.Exchange
        $x.ServicePrincipals += @{ Identity = $script:Ids.LegacyObjectId; ObjectId = $script:Ids.LegacyObjectId; AppId = $script:Ids.LegacyAppId; DisplayName = 'email-monitor' }
        $x.Scopes += @{ Name = 'Scope-email-monitor'; RecipientFilter = "PrimarySmtpAddress -eq 'support@contoso.com'" }
        $x.Assignments += @{ Name = 'Assignment-email-monitor-MailRead'; Role = 'Application Mail.Read'; RoleAssigneeName = $script:Ids.LegacyObjectId }
        $x.Assignments += @{ Name = 'Assignment-email-monitor-MailSend'; Role = 'Application Mail.Send'; RoleAssigneeName = $script:Ids.LegacyObjectId }
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile -Entries @()); RemoveLegacyGrantAppIds = @($script:Ids.LegacyAppId) }
        $code | Should -Be 0
        Get-SummaryResult "Mailbox grant to remove: $($script:Ids.LegacyAppId)" | Should -Be 'Removed: 2 role assignment(s)'
        @($x.Assignments) | Should -HaveCount 0
        @($x.ServicePrincipals) | Should -HaveCount 0
        @($x.Scopes) | Should -HaveCount 1
        $script:ExchangeDisconnected | Should -BeTrue
    }

    It 'finds the retired identity''s assignments even when -RoleAssignee is refused' {
        $x = $script:Tenant.Exchange
        $x.RoleAssigneeUnsupported = $true
        $x.ServicePrincipals += @{ Identity = $script:Ids.LegacyObjectId; ObjectId = $script:Ids.LegacyObjectId; AppId = $script:Ids.LegacyAppId; DisplayName = 'email-monitor' }
        $x.Assignments += @{ Name = 'Assignment-email-monitor-MailRead'; Role = 'Application Mail.Read'; RoleAssigneeName = $script:Ids.LegacyObjectId }
        $x.Assignments += @{ Name = 'Assignment-other-MailRead'; Role = 'Application Mail.Read'; RoleAssigneeName = 'someone-else' }
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile -Entries @()); RemoveLegacyGrantAppIds = @($script:Ids.LegacyAppId) }
        $code | Should -Be 0
        Get-SummaryResult "Mailbox grant to remove: $($script:Ids.LegacyAppId)" | Should -Be 'Removed: 1 role assignment(s)'
        @($x.Assignments) | Should -HaveCount 1
    }

    It 'reports a retired identity that is not present' {
        $code = Invoke-Run @{ MailboxGrantsFile = (New-MailboxFile -Entries @()); RemoveLegacyGrantAppIds = @($script:Ids.LegacyAppId) }
        $code | Should -Be 0
        Get-SummaryResult "Mailbox grant to remove: $($script:Ids.LegacyAppId)" | Should -Be 'Not present'
        $script:Writes | Should -HaveCount 0
    }

    It 'keeps the assignment of an identity the file lists as adopted by the v5 email channel' {
        $x = $script:Tenant.Exchange
        $x.ServicePrincipals += @{ Identity = $script:Ids.LegacyObjectId; ObjectId = $script:Ids.LegacyObjectId; AppId = $script:Ids.LegacyAppId; DisplayName = 'email-monitor' }
        $x.Assignments += @{ Name = 'Assignment-email-monitor-MailRead'; Role = 'Application Mail.Read'; RoleAssigneeName = $script:Ids.LegacyObjectId }
        $file = New-MailboxFile -Entries @() -AdoptedIdentityAppIds @($script:Ids.LegacyAppId.ToUpperInvariant())
        $code = Invoke-Run @{ MailboxGrantsFile = $file; RemoveLegacyGrantAppIds = @($script:Ids.LegacyAppId) }
        $code | Should -Be 0
        Get-SummaryResult "Mailbox grant to remove: $($script:Ids.LegacyAppId)" | Should -Be 'Kept. An email channel uses the identity'
        ($script:Console -join "`n") | Should -Match 'an email channel uses the identity\. The script keeps the role assignments'
        @($x.Assignments) | Should -HaveCount 1
        @($x.ServicePrincipals) | Should -HaveCount 1
        $script:Writes | Should -HaveCount 0
        Should -Invoke Connect-ExchangeOnline -Times 0 -Because 'nothing is left to apply or remove'
    }

    It 'removes the identities that are not adopted alongside one that is' {
        $x = $script:Tenant.Exchange
        $otherAppId = [guid]::NewGuid().ToString()
        $otherObjectId = [guid]::NewGuid().ToString()
        $x.ServicePrincipals += @{ Identity = $script:Ids.LegacyObjectId; ObjectId = $script:Ids.LegacyObjectId; AppId = $script:Ids.LegacyAppId; DisplayName = 'email-monitor' }
        $x.ServicePrincipals += @{ Identity = $otherObjectId; ObjectId = $otherObjectId; AppId = $otherAppId; DisplayName = 'old-monitor' }
        $x.Assignments += @{ Name = 'Assignment-email-monitor-MailRead'; Role = 'Application Mail.Read'; RoleAssigneeName = $script:Ids.LegacyObjectId }
        $x.Assignments += @{ Name = 'Assignment-old-monitor-MailRead'; Role = 'Application Mail.Read'; RoleAssigneeName = $otherObjectId }
        $file = New-MailboxFile -Entries @() -AdoptedIdentityAppIds @($script:Ids.LegacyAppId)
        $code = Invoke-Run @{ MailboxGrantsFile = $file; RemoveLegacyGrantAppIds = @($script:Ids.LegacyAppId, $otherAppId) }
        $code | Should -Be 0
        Get-SummaryResult "Mailbox grant to remove: $($script:Ids.LegacyAppId)" | Should -Be 'Kept. An email channel uses the identity'
        Get-SummaryResult "Mailbox grant to remove: $otherAppId" | Should -Be 'Removed: 1 role assignment(s)'
        @($x.Assignments | Where-Object { $_.RoleAssigneeName -eq $script:Ids.LegacyObjectId }) | Should -HaveCount 1
        @($x.ServicePrincipals | Where-Object { $_.AppId -eq $otherAppId }) | Should -HaveCount 0
        $script:ExchangeDisconnected | Should -BeTrue
    }

    It 'applies the grants of the bare list with -TenantId' {
        $file = New-MailboxFile -AsArray
        $code = Invoke-Run @{ MailboxGrantsFile = $file; TenantId = $script:Ids.Tenant }
        $code | Should -Be 0
        Get-SummaryResult 'Mailbox grant: support@contoso.com for neo-support' | Should -Be 'Granted: 3 role(s) added'
        ($script:Console -join "`n") | Should -Match 'Email channels: 1\. Identities that an email channel uses: 0'
    }

    It 'applies both files in one run, the agent grants file first' {
        Add-AgentIdentities -NoGrants
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read')))
        $code = Invoke-Run @{ AgentGrantsFile = $grants; MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Grant to agent user: agent Support Agent' | Should -Be 'Granted: User.Read'
        Get-SummaryResult 'Mailbox grant: support@contoso.com for neo-support' | Should -Be 'Granted: 3 role(s) added'
        $script:Writes[0] | Should -BeLike 'POST grant*'
        @($script:Writes | Where-Object { $_ -like 'NEW exo*' }) | Should -HaveCount 5
    }
}

Context 'Verify-only run (-Verify)' {
    It 'reports pending agent-user and mailbox grants without writing' {
        Add-AgentIdentities -NoGrants
        $x = $script:Tenant.Exchange
        $x.ServicePrincipals += @{ Identity = $script:Ids.LegacyObjectId; ObjectId = $script:Ids.LegacyObjectId; AppId = $script:Ids.LegacyAppId; DisplayName = 'email-monitor' }
        $x.Assignments += @{ Name = 'Assignment-email-monitor-MailRead'; Role = 'Application Mail.Read'; RoleAssigneeName = $script:Ids.LegacyObjectId }
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read', 'Mail.Read')))
        $code = Invoke-Run @{ AgentGrantsFile = $grants; MailboxGrantsFile = (New-MailboxFile); RemoveLegacyGrantAppIds = @($script:Ids.LegacyAppId); Verify = $true }
        $code | Should -Be 1
        $script:Writes | Should -HaveCount 0
        Get-SummaryResult 'Grant to agent user: agent Support Agent' | Should -Be 'WOULD GRANT: Mail.Read User.Read'
        (Get-SummaryResult 'Mailbox grant: support@contoso.com for neo-support') | Should -BeLike 'WOULD GRANT: Exchange service principal, management scope Scope-neo-support, role assignment*'
        Get-SummaryResult "Mailbox grant to remove: $($script:Ids.LegacyAppId)" | Should -Be 'WOULD REMOVE: 1 role assignment(s) and the Exchange service principal'
        @((Get-FakeSp -Id $script:Ids.AgentIdentitySp).grants) | Should -HaveCount 0
        @($x.Assignments) | Should -HaveCount 1
        @($x.ServicePrincipals) | Should -HaveCount 1
        $script:ExchangeDisconnected | Should -BeTrue
        $console = $script:Console -join "`n"
        $console | Should -Match 'the grants run with -Verify'
        $console | Should -Match 'A run without -Verify would change 3 item\(s\)\. The script wrote nothing'
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_AgentAccess_*.json')
        $files | Should -HaveCount 1
        $json = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        $json.verifyOnly | Should -BeTrue
        $json.pendingChangeCount | Should -Be 3
    }

    It 'is a clean pass when every grant is in place: exit 0, nothing pending' {
        Add-AgentIdentities -AgentScope 'User.Read'
        Add-CompliantExchangeState
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read')))
        $code = Invoke-Run @{ AgentGrantsFile = $grants; MailboxGrantsFile = (New-MailboxFile); Verify = $true }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        ($script:Console -join "`n") | Should -Match 'would change nothing'
    }

    It 'the write seams refuse every write in a verify-only run, whatever the caller does' {
        $script:State = @{ Verify = $true }
        { Invoke-NeologikGraph -Method POST -Uri "$script:GraphV1/oauth2PermissionGrants" -Body '{}' } | Should -Throw -ExpectedMessage '*The run with -Verify refused the write*'
        { Invoke-NeologikWrite -Command 'New-ManagementScope' -Parameters @{ Name = 'x'; RecipientRestrictionFilter = 'y' } } | Should -Throw -ExpectedMessage '*The run with -Verify refused the write*'
        $script:GraphCalls | Should -HaveCount 0
        $script:Writes | Should -HaveCount 0
        Should -Invoke New-ManagementScope -Times 0
        # A read passes.
        $null = Invoke-NeologikGraph -Method GET -Uri "$script:GraphV1/me"
        $script:GraphCalls | Should -Contain 'GET /me'
        # Without -Verify the seam performs the write.
        $script:State = @{ Verify = $false }
        $null = Invoke-NeologikWrite -Command 'New-ManagementScope' -Parameters @{ Name = 'x'; RecipientRestrictionFilter = 'y' }
        $script:Writes | Should -HaveCount 1
    }
}

Context 'Parameter surface' {
    It 'takes the two files and the tenant, and nothing of the migration script' {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors) | Should -HaveCount 0
        $names = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
        foreach ($name in @('AgentGrantsFile', 'MailboxGrantsFile', 'RemoveLegacyGrantAppIds', 'TenantId', 'SolutionShortName', 'SharePointAppClientId', 'Verify', 'UseAzureCliToken')) {
            $names | Should -Contain $name
        }
        # The migration script (Neologik-Customer/neo-client-migration) takes the deployment identity, the
        # configuration file, the Azure scope and the later run; the grants run needs none of them.
        foreach ($name in @('ConfigurationFile', 'DeploySpClientId', 'SubscriptionId', 'ResourceGroupName', 'LaterRun', 'KitVersion', 'UploadStorageAccountName', 'Phase')) {
            $names | Should -Not -Contain $name
        }
        { Invoke-NeologikAgentAccess -AgentGrantsFile (New-GrantsFile) -LaterRun } | Should -Throw -ExpectedMessage "*'LaterRun'*"
        Should -Invoke Connect-MgGraph -Times 0
    }
}

Context 'Summary, files and exit code' {
    It 'flags FAILED, UNKNOWN, MISSING, SKIPPED, PENDING, NOT FOUND and WOULD as attention' {
        foreach ($result in @('FAILED - x', 'UNKNOWN - x', 'MISSING - x', 'SKIPPED - x', 'PENDING - x', 'NOT FOUND - x', 'WOULD GRANT', 'WOULD REMOVE: 2 role assignment(s)')) {
            $result | Should -Match $script:AttentionPattern
        }
        foreach ($result in @('Present', 'Already granted', 'Granted: User.Read', 'Removed: 1 role assignment(s)', 'Not present', 'Not needed', 'Updated: a b',
                'Kept. An email channel uses the identity')) {
            $result | Should -Not -Match $script:AttentionPattern
        }
    }

    It 'writes the log file and the summary file beside the script, and lists them for the administrator' {
        Add-AgentIdentities -NoGrants
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read')))
        $code = Invoke-Run @{ AgentGrantsFile = $grants }
        $code | Should -Be 0
        $logs = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'NeologikAgentAccess_*.log')
        $logs | Should -HaveCount 1
        $log = Get-Content -LiteralPath $logs[0].FullName -Raw
        $log | Should -Match "Neologik agent access script, onboarding kit $([regex]::Escape($script:KitVersion))"
        $log | Should -Match 'Neologik agent access: the grants run'
        $log | Should -Match '\[Summary\] Grant to agent user: agent Support Agent: Granted: User.Read'
        $log | Should -Match 'SUMMARY'
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_AgentAccess_*.json')
        $files | Should -HaveCount 1
        $json = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        $json.kitVersion | Should -Be $script:KitVersion
        $json.tenantId | Should -Be $script:Ids.Tenant
        $json.solutionShortName | Should -Be $script:ShortName
        $json.agentGrantsFile | Should -Be $grants
        $json.mailboxGrantsFile | Should -Be ''
        $json.verifyOnly | Should -BeFalse
        $json.logFile | Should -Be $logs[0].FullName
        @($json.items).Count | Should -Be $script:Summary.Count
        $json.attentionCount | Should -Be 0
        $json.pendingChangeCount | Should -Be 0
        $bytes = [IO.File]::ReadAllBytes($files[0].FullName)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) | Should -BeFalse -Because 'UTF-8 without BOM'
        $text = $script:Console -join "`n"
        $text | Should -Match 'FILES TO SEND TO NEOLOGIK'
        $text | Should -Match 'NeologikAgentAccess_\d+_\d+\.log'
        $text | Should -Match 'Neologik_AgentAccess_\d+_\d+\.json'
        $text | Should -Not -Match 'Snapshot'
        $text | Should -Not -Match 'Uploaded to the storage account'
    }

    It 'writes the log file and the summary file when an input is wrong, before contacting anything' {
        $code = Invoke-Run @{ AgentGrantsFile = (Join-Path $TestDrive 'missing-grants.json') }
        $code | Should -Be 1
        Should -Invoke Connect-MgGraph -Times 0
        $logs = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'NeologikAgentAccess_*.log')
        $logs | Should -HaveCount 1
        $log = Get-Content -LiteralPath $logs[0].FullName -Raw
        $log | Should -Match '\[Error\] .*The agent grants file does not exist'
        $log | Should -Match '\[ActionRequired\]'
        $log | Should -Match '\[Summary\] Run: FAILED: an input is wrong'
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_AgentAccess_*.json')
        $files | Should -HaveCount 1
        $json = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        $json.exitReason | Should -Match '^an input is wrong'
        $json.attentionCount | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'FILES TO SEND TO NEOLOGIK'
    }

    It 'records a failed Microsoft Graph request with its status and request id in the log file' {
        Add-AgentIdentities -NoGrants
        $script:Faults += @{ Match = 'GET /servicePrincipals$'; Status = 403; Code = 'Authorization_RequestDenied'; Message = 'Insufficient privileges'; Remaining = 1; Headers = @{ 'request-id' = @('req-0001') } }
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read')))) }
        $code | Should -Be 1
        (Get-SummaryResult 'Grant to agent user: agent Support Agent') | Should -Match '^FAILED: '
        $logs = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'NeologikAgentAccess_*.log')
        $log = Get-Content -LiteralPath $logs[0].FullName -Raw
        $log | Should -Match '\[Graph\] GET .*/servicePrincipals.* returned HTTP 403\. request-id req-0001\. .*Authorization_RequestDenied: Insufficient privileges'
    }

    It 'never lets an unexpected exception escape: the run is recorded and the summary written' {
        Mock Set-NeologikAgentUserGrant { throw 'something nobody anticipated' }
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @()) }
        $code | Should -Be 1
        Get-SummaryResult 'Run' | Should -Be 'FAILED: unexpected error. something nobody anticipated'
        @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_AgentAccess_*.json') | Should -HaveCount 1
    }

    It 'continues without a log file when no folder accepts one' {
        Mock Get-NeologikSummaryDirectory { @((Join-Path $TestDrive 'does-not-exist')) }
        $code = Invoke-Run @{ AgentGrantsFile = (New-GrantsFile -Grants @()) }
        $code | Should -Be 0
        ($script:Console -join "`n") | Should -Match 'could not create the log file'
        ($script:Console -join "`n") | Should -Match 'could not write the summary file to any folder'
    }

    It 'declares the kit version the version history opens with' {
        $history = Get-Content -Raw (Join-Path (Split-Path -Parent $script:ScriptPath) 'docs' 'VERSION_HISTORY.md')
        $top = [regex]::Match($history, '(?m)^## Version (\d+\.\d+\.\d+)').Groups[1].Value
        $script:KitVersion | Should -Be "v$top"
    }
}

}
