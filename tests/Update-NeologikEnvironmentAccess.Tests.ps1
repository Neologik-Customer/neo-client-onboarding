#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Test harness for Update-NeologikEnvironmentAccess.ps1 (project#2217,
    project#2234: the single-session migration model).

    Every external call is replaced: Microsoft Graph (the SDK cmdlets and the
    raw request seam), Azure (Az.Accounts / Az.Resources), Exchange Online,
    the Azure CLI, module installation and the console. An in-memory tenant
    model answers the script's reads and records every write, so a run can
    be asserted to change exactly what a real run would change - and, on a
    compliant tenant, nothing at all.

    Run: pwsh -NoProfile -Command "Invoke-Pester -Path tests -CI"
#>

Describe 'Update-NeologikEnvironmentAccess.ps1' {

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Update-NeologikEnvironmentAccess.ps1'

    # ----- stubs for every external command the script calls -----------------
    # (a command must exist before Pester can mock it; the Exchange cmdlets
    # only exist inside a live session, the others would need real modules.)
    function Connect-MgGraph { [CmdletBinding()] param($AccessToken, $TenantId, $Scopes, [switch]$UseDeviceCode, [switch]$NoWelcome) }
    function Get-MgContext { [CmdletBinding()] param() }
    function Invoke-MgGraphRequest { [CmdletBinding()] param($Method, $Uri, $Body, $Headers, $ContentType, [switch]$SkipHttpErrorCheck, $StatusCodeVariable, $ResponseHeadersVariable) }
    function Get-MgServicePrincipal { [CmdletBinding()] param($Filter, [switch]$All) }
    function Get-MgServicePrincipalAppRoleAssignment { [CmdletBinding()] param($ServicePrincipalId, [switch]$All) }
    function New-MgServicePrincipalAppRoleAssignment { [CmdletBinding()] param($ServicePrincipalId, $PrincipalId, $ResourceId, $AppRoleId) }
    function Remove-MgServicePrincipalAppRoleAssignment { [CmdletBinding()] param($ServicePrincipalId, $AppRoleAssignmentId) }
    function Get-MgGroupAppRoleAssignment { [CmdletBinding()] param($GroupId, [switch]$All) }
    function New-MgGroupAppRoleAssignment { [CmdletBinding()] param($GroupId, $PrincipalId, $ResourceId, $AppRoleId) }
    function Get-MgGroup { [CmdletBinding()] param($GroupId) }
    function Get-MgGroupMember { [CmdletBinding()] param($GroupId, [switch]$All) }
    function Get-MgServicePrincipalOauth2PermissionGrant { [CmdletBinding()] param($ServicePrincipalId, [switch]$All) }
    function Get-MgDirectoryRole { [CmdletBinding()] param([switch]$All, $Filter) }
    function Get-MgDirectoryRoleMember { [CmdletBinding()] param($DirectoryRoleId, [switch]$All) }
    function Remove-MgDirectoryRoleMemberDirectoryObjectByRef { [CmdletBinding()] param($DirectoryRoleId, $DirectoryObjectId) }
    function Connect-AzAccount { [CmdletBinding()] param($Tenant, $Subscription, $UseDeviceAuthentication, $ClaimsChallenge) }
    function Get-AzContext { [CmdletBinding()] param() }
    function Get-AzRoleAssignment { [CmdletBinding()] param($ObjectId, $RoleDefinitionName, $Scope) }
    function New-AzRoleAssignment { [CmdletBinding()] param($ObjectId, $RoleDefinitionName, $Scope) }
    function Remove-AzRoleAssignment { [CmdletBinding()] param($ObjectId, $RoleDefinitionName, $Scope) }
    function Connect-ExchangeOnline { [CmdletBinding()] param([switch]$Device, $ShowBanner) }
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
        Subscription     = '22222222-2222-2222-2222-222222222222'
        DeployAppId      = '33333333-3333-3333-3333-333333333333'
        DeploySpId       = '33333333-aaaa-3333-3333-333333333333'
        GraphSpId        = '00000003-aaaa-0000-c000-000000000000'
        SignInAppId      = '44444444-4444-4444-4444-444444444444'
        SignInSpId       = '44444444-aaaa-4444-4444-444444444444'
        Group            = '55555555-5555-5555-5555-555555555555'
        AdminGroup       = '55555555-aaaa-5555-5555-555555555555'
        Me               = '66666666-6666-6666-6666-666666666666'
        BlueprintAppObj  = '77777777-7777-7777-7777-777777777777'
        BlueprintAppId   = '77777777-aaaa-7777-7777-777777777777'
        BlueprintSpId    = '77777777-bbbb-7777-7777-777777777777'
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
        AppAdminRole     = 'cccccccc-1111-cccc-cccc-cccccccccccc'
        MailboxAppId     = 'dddddddd-1111-dddd-dddd-dddddddddddd'
        MailboxObjectId  = 'dddddddd-2222-dddd-dddd-dddddddddddd'
        LegacyAppId      = 'eeeeeeee-1111-eeee-eeee-eeeeeeeeeeee'
        LegacyObjectId   = 'eeeeeeee-2222-eeee-eeee-eeeeeeeeeeee'
    }
    $script:ShortName = 'abcprd01'
    $script:RgName = 'rg-neo-abcprd-uks-01'
    $script:RgScope = "/subscriptions/$($script:Ids.Subscription)/resourceGroups/$script:RgName"
    $script:SubScope = "/subscriptions/$($script:Ids.Subscription)"
    $script:AppRoleIds = @{}
    foreach ($roleName in @('Application.ReadWrite.OwnedBy', 'AgentIdentityBlueprint.AddRemoveCreds.All', 'Application.Read.All',
            'AgentIdentityBlueprint.Create', 'AgentIdentityBlueprint.UpdateAuthProperties.All', 'AgentIdentityBlueprintPrincipal.Create',
            'AgentIdentity.Create.All', 'AgentIdUser.ReadWrite.All', 'Group.Create', 'AgentIdUser.ReadWrite.IdentityParentedBy',
            'Sites.Selected', 'User.Read.All')) {
        $script:AppRoleIds[$roleName] = [guid]::NewGuid().ToString()
    }

    # ----- in-memory tenant ---------------------------------------------------------
    function New-FakeSp {
        param([string]$Id, [string]$AppId, [string]$DisplayName)
        return @{ id = $Id; appId = $AppId; displayName = $DisplayName; owners = @(); appRoleAssignments = @(); grants = @() }
    }

    function New-FakeApp {
        param([string]$Id, [string]$AppId, [string]$DisplayName)
        return @{ id = $Id; appId = $AppId; displayName = $DisplayName; owners = @(); credentials = @() }
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

    function Get-FakeApp {
        param([string]$Id)
        return @($script:Tenant.Apps | Where-Object { $_.id -eq $Id }) | Select-Object -First 1
    }

    function Add-Write {
        param([string]$Description)
        $script:Writes += $Description
    }

    function New-EmptyTenant {
        # The directory as it is before anything Neologik exists, apart from
        # the deployment identity, the Graph service principal, the sign-in
        # application and the NCE user group.
        $t = @{
            Me                    = $script:Ids.Me
            Apps                  = @()
            ServicePrincipals     = @()
            Groups                = @()
            DirectoryRoles        = @()
            AzRoleAssignments     = @()
            Exchange              = @{ ServicePrincipals = @(); Scopes = @(); Assignments = @(); InScope = $true; Dehydrated = $false }
            PageSize              = 0
            PrincipalCreateDelays = 0
            GrantRefusals         = @()
        }
        $t.ServicePrincipals += New-FakeSp -Id $script:Ids.GraphSpId -AppId '00000003-0000-0000-c000-000000000000' -DisplayName 'Microsoft Graph'
        $t.ServicePrincipals += New-FakeSp -Id $script:Ids.DeploySpId -AppId $script:Ids.DeployAppId -DisplayName "Neologik GitHub Service Connection - $script:ShortName"
        $t.ServicePrincipals += New-FakeSp -Id $script:Ids.SignInSpId -AppId $script:Ids.SignInAppId -DisplayName "Neologik Platform Sign-in - $script:ShortName"
        $t.Groups += @{ id = $script:Ids.Group; displayName = "Neologik NCE User Group - $script:ShortName"; members = @(@{ id = $script:Ids.Me }); appRoleAssignments = @() }
        return $t
    }

    function Add-CompliantDirectoryState {
        # Everything the pre-window run verifies in the directory (steps
        # 1-3), already in place.
        $t = $script:Tenant
        $app = New-FakeApp -Id $script:Ids.BlueprintAppObj -AppId $script:Ids.BlueprintAppId -DisplayName "Neologik Agent Blueprint - default - $script:ShortName"
        $app.owners = @($script:Ids.Me, $script:Ids.DeploySpId)
        $app.credentials = @('github-oidc-neo-infrastructure', 'github-oidc-neo-bot-service', 'github-oidc-neo-env-config')
        $t.Apps += $app
        $principal = New-FakeSp -Id $script:Ids.BlueprintSpId -AppId $script:Ids.BlueprintAppId -DisplayName $app.displayName
        $principal.owners = @($script:Ids.Me, $script:Ids.DeploySpId)
        $t.ServicePrincipals += $principal
        Add-FakeAppRole -SpId $script:Ids.BlueprintSpId -RoleName 'AgentIdUser.ReadWrite.IdentityParentedBy'
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'Application.ReadWrite.OwnedBy'
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'AgentIdentityBlueprint.AddRemoveCreds.All'
        $group = @($t.Groups | Where-Object { $_.id -eq $script:Ids.Group })[0]
        $group.appRoleAssignments = @(@{ Id = [guid]::NewGuid().ToString(); ResourceId = $script:Ids.SignInSpId; AppRoleId = '00000000-0000-0000-0000-000000000000' })
        $signIn = Get-FakeSp -Id $script:Ids.SignInSpId
        $signIn.grants = @(@{ id = 'grant-signin'; clientId = $script:Ids.SignInSpId; consentType = 'AllPrincipals'; principalId = $null; resourceId = $script:Ids.GraphSpId; scope = 'User.Read openid profile' })
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

    function Add-CompliantAzureState {
        # The narrow Azure role set and the retained subscription roles in
        # place, the Application Administrator role held by nobody (step 4).
        $t = $script:Tenant
        foreach ($roleName in $script:RequiredRgRoles) {
            $t.AzRoleAssignments += @{ ObjectId = $script:Ids.DeploySpId; RoleDefinitionName = $roleName; Scope = $script:RgScope }
        }
        foreach ($roleName in $script:RequiredSubRoles) {
            $t.AzRoleAssignments += @{ ObjectId = $script:Ids.DeploySpId; RoleDefinitionName = $roleName; Scope = $script:SubScope }
        }
        $t.DirectoryRoles += @{ Id = $script:Ids.AppAdminRole; RoleTemplateId = $script:AppAdminRoleTemplateId; members = @() }
    }

    function Add-LegacyAzureState {
        # The broad grants of a v4 environment: subscription Contributor and
        # User Access Administrator, Application Administrator held.
        $t = $script:Tenant
        foreach ($roleName in @('Contributor', 'User Access Administrator')) {
            $t.AzRoleAssignments += @{ ObjectId = $script:Ids.DeploySpId; RoleDefinitionName = $roleName; Scope = $script:SubScope }
        }
        $t.DirectoryRoles += @{ Id = $script:Ids.AppAdminRole; RoleTemplateId = $script:AppAdminRoleTemplateId; members = @($script:Ids.DeploySpId) }
    }

    function Add-CompliantPreWindowState {
        # Everything the pre-window run verifies, directory and Azure,
        # already in place: a pure verification pass.
        Add-CompliantDirectoryState
        Add-CompliantAzureState
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
            '^/me$' { return @{ StatusCode = 200; Headers = @{}; Body = @{ id = $t.Me } } }
            '^/applications$' {
                $filter = Get-QueryValue -Query $query -Name '$filter'
                $items = @()
                if ($filter -match "displayName eq '(.+)'$") {
                    $name = $Matches[1] -replace "''", "'"
                    $items = @($t.Apps | Where-Object { $_.displayName -eq $name } | ForEach-Object { @{ id = $_.id; appId = $_.appId } })
                }
                return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $items -Uri $Uri -Query $query) }
            }
            '^/applications/microsoft\.graph\.agentIdentityBlueprint$' {
                Add-Write "POST blueprint $($json.displayName)"
                $app = New-FakeApp -Id ([guid]::NewGuid().ToString()) -AppId ([guid]::NewGuid().ToString()) -DisplayName $json.displayName
                $app.owners = @($t.Me)
                foreach ($bind in @($json['owners@odata.bind'])) { $app.owners += ($bind -split '/')[-1] }
                $t.Apps += $app
                return @{ StatusCode = 201; Headers = @{}; Body = @{ id = $app.id; appId = $app.appId; displayName = $app.displayName } }
            }
            '^/applications/([^/]+)/owners$' {
                $app = Get-FakeApp -Id $Matches[1]
                if (-not $app) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                $items = @($app.owners | ForEach-Object { @{ id = $_ } })
                return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $items -Uri $Uri -Query $query) }
            }
            '^/applications/([^/]+)/owners/\$ref$' {
                $app = Get-FakeApp -Id $Matches[1]
                if (-not $app) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                $owner = ($json['@odata.id'] -split '/')[-1]
                if ($app.owners -contains $owner) { return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = 'One or more added object references already exist' } } } }
                Add-Write "POST app owner $owner"
                $app.owners += $owner
                return @{ StatusCode = 204; Headers = @{}; Body = $null }
            }
            '^/applications/([^/]+)/federatedIdentityCredentials$' {
                $app = Get-FakeApp -Id $Matches[1]
                if (-not $app) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                if ($Method -eq 'GET') {
                    $items = @($app.credentials | ForEach-Object { @{ name = $_ } })
                    return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $items -Uri $Uri -Query $query) }
                }
                if ($app.credentials -contains $json.name) { return @{ StatusCode = 409; Headers = @{}; Body = @{ error = @{ code = 'Request_MultipleObjectsWithSameKeyValue'; message = 'FederatedIdentityCredential with name already exists.' } } } }
                Add-Write "POST credential $($json.name)"
                $app.credentials += $json.name
                return @{ StatusCode = 201; Headers = @{}; Body = @{ id = [guid]::NewGuid().ToString(); name = $json.name } }
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
            '^/servicePrincipals/microsoft\.graph\.agentIdentityBlueprintPrincipal$' {
                $app = @($t.Apps | Where-Object { $_.appId -eq $json.appId }) | Select-Object -First 1
                if (-not $app) { return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = 'The appId does not exist' } } } }
                if ($t.PrincipalCreateDelays -gt 0) {
                    $t.PrincipalCreateDelays--
                    return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = 'The application must exist in the local tenant' } } }
                }
                Add-Write "POST blueprint principal $($json.appId)"
                $sp = New-FakeSp -Id ([guid]::NewGuid().ToString()) -AppId $json.appId -DisplayName $app.displayName
                $sp.owners = @($t.Me)
                $t.ServicePrincipals += $sp
                return @{ StatusCode = 201; Headers = @{}; Body = @{ id = $sp.id; appId = $sp.appId } }
            }
            '^/servicePrincipals/([^/]+)/owners$' {
                $sp = Get-FakeSp -Id $Matches[1]
                if (-not $sp) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                $items = @($sp.owners | ForEach-Object { @{ id = $_ } })
                return @{ StatusCode = 200; Headers = @{}; Body = (ConvertTo-FakePage -Items $items -Uri $Uri -Query $query) }
            }
            '^/servicePrincipals/([^/]+)/owners/\$ref$' {
                $sp = Get-FakeSp -Id $Matches[1]
                if (-not $sp) { return @{ StatusCode = 404; Headers = @{}; Body = @{ error = @{ code = 'Request_ResourceNotFound'; message = 'not found' } } } }
                $owner = ($json['@odata.id'] -split '/')[-1]
                if ($sp.owners -contains $owner) { return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = 'One or more added object references already exist' } } } }
                Add-Write "POST sp owner $owner"
                $sp.owners += $owner
                return @{ StatusCode = 204; Headers = @{}; Body = $null }
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
    function New-ConfigFile {
        param([string]$Path = (Join-Path $TestDrive 'config.json'), [hashtable]$Overrides = @{}, [string[]]$Remove = @())
        $config = [ordered]@{
            OrganizationName  = 'Contoso Ltd'
            TenantId          = $script:Ids.Tenant
            SubscriptionId    = $script:Ids.Subscription
            ResourceGroupName = $script:RgName
            SolutionShortName = $script:ShortName
            AppRegistration   = @{ Name = 'Neologik GitHub Service Connection'; ClientId = $script:Ids.DeployAppId }
            NceAuthApp        = @{ ClientId = $script:Ids.SignInAppId }
            SecurityGroups    = @(
                @{ Name = "Neologik NCE User Group - $script:ShortName"; Id = $script:Ids.Group },
                @{ Name = "Neologik Admin User Group - $script:ShortName"; Id = $script:Ids.AdminGroup }
            )
        }
        foreach ($key in $Overrides.Keys) { $config[$key] = $Overrides[$key] }
        foreach ($key in $Remove) { $config.Remove($key) }
        $config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
        return $Path
    }

    function New-GrantsFile {
        param([string]$Path = (Join-Path $TestDrive 'grants.json'), [object[]]$Grants = @(), [object[]]$ComponentRoles = @(),
            [bool]$SharePoint = $false, [string]$TenantId = $script:Ids.Tenant, [string[]]$Warnings = @(), [switch]$Raw, [string]$RawContent)
        if ($Raw) { Set-Content -LiteralPath $Path -Value $RawContent -Encoding UTF8 -NoNewline; return $Path }
        $payload = [ordered]@{
            schemaVersion       = 1
            environment         = 'abcprd01'
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
        # The bare array shape by default; -AsObject (or adopted ids) writes
        # the object shape with 'grants' and 'adoptedIdentityAppIds'.
        param([string]$Path = (Join-Path $TestDrive 'mailboxes.json'), [object[]]$Entries, [string[]]$AdoptedIdentityAppIds = @(),
            [switch]$AsObject, [string]$TenantId = $script:Ids.Tenant, [switch]$Raw, [string]$RawContent)
        if ($Raw) { Set-Content -LiteralPath $Path -Value $RawContent -Encoding UTF8 -NoNewline; return $Path }
        if ($null -eq $Entries) {
            $Entries = @(@{ IdentityAppId = $script:Ids.MailboxAppId; IdentityObjectId = $script:Ids.MailboxObjectId; Mailbox = 'support@contoso.com'; DisplayName = 'neo-support' })
        }
        if ($AsObject -or $AdoptedIdentityAppIds.Count -gt 0) {
            $payload = [ordered]@{ schemaVersion = 1; tenantId = $TenantId; grants = @($Entries); adoptedIdentityAppIds = @($AdoptedIdentityAppIds) }
            ConvertTo-Json -InputObject $payload -Depth 4 | Set-Content -LiteralPath $Path -Encoding UTF8
            return $Path
        }
        ConvertTo-Json -InputObject @($Entries) -Depth 4 | Set-Content -LiteralPath $Path -Encoding UTF8
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
        $output = @(Invoke-NeologikEnvironmentAccess @Parameters)
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
    Mock Remove-MgServicePrincipalAppRoleAssignment {
        param($ServicePrincipalId, $AppRoleAssignmentId)
        $sp = Get-FakeSp -Id $ServicePrincipalId
        $sp.appRoleAssignments = @($sp.appRoleAssignments | Where-Object { $_.Id -ne $AppRoleAssignmentId })
        Add-Write "REMOVE approle $ServicePrincipalId $AppRoleAssignmentId"
    }
    Mock Get-MgGroupAppRoleAssignment {
        param($GroupId)
        $group = @($script:Tenant.Groups | Where-Object { $_.id -eq $GroupId }) | Select-Object -First 1
        if (-not $group) { throw (New-NotFoundException) }
        @($group.appRoleAssignments | ForEach-Object { [pscustomobject]$_ })
    }
    Mock New-MgGroupAppRoleAssignment {
        param($GroupId, $PrincipalId, $ResourceId, $AppRoleId)
        $group = @($script:Tenant.Groups | Where-Object { $_.id -eq $GroupId }) | Select-Object -First 1
        $group.appRoleAssignments += @{ Id = [guid]::NewGuid().ToString(); ResourceId = $ResourceId; AppRoleId = $AppRoleId }
        Add-Write "NEW group assignment $GroupId $ResourceId"
    }
    Mock Get-MgGroup {
        param($GroupId)
        $group = @($script:Tenant.Groups | Where-Object { $_.id -eq $GroupId }) | Select-Object -First 1
        if (-not $group) { throw (New-NotFoundException) }
        [pscustomobject]@{ Id = $group.id; DisplayName = $group.displayName }
    }
    Mock Get-MgGroupMember {
        param($GroupId)
        $group = @($script:Tenant.Groups | Where-Object { $_.id -eq $GroupId }) | Select-Object -First 1
        if (-not $group) { throw (New-NotFoundException) }
        @($group.members | ForEach-Object { [pscustomobject]@{ Id = $_.id } })
    }
    Mock Get-MgServicePrincipalOauth2PermissionGrant {
        param($ServicePrincipalId)
        $sp = Get-FakeSp -Id $ServicePrincipalId
        if (-not $sp) { throw (New-NotFoundException) }
        @($sp.grants | ForEach-Object { [pscustomobject]@{ Id = $_.id; ConsentType = $_.consentType; Scope = $_.scope; ResourceId = $_.resourceId } })
    }
    Mock Get-MgDirectoryRole { @($script:Tenant.DirectoryRoles | ForEach-Object { [pscustomobject]@{ Id = $_.Id; RoleTemplateId = $_.RoleTemplateId } }) }
    Mock Get-MgDirectoryRoleMember {
        param($DirectoryRoleId)
        $role = @($script:Tenant.DirectoryRoles | Where-Object { $_.Id -eq $DirectoryRoleId }) | Select-Object -First 1
        @($role.members | ForEach-Object { [pscustomobject]@{ Id = $_ } })
    }
    Mock Remove-MgDirectoryRoleMemberDirectoryObjectByRef {
        param($DirectoryRoleId, $DirectoryObjectId)
        $role = @($script:Tenant.DirectoryRoles | Where-Object { $_.Id -eq $DirectoryRoleId }) | Select-Object -First 1
        $role.members = @($role.members | Where-Object { $_ -ne $DirectoryObjectId })
        Add-Write "REMOVE directory role member $DirectoryObjectId"
    }
    Mock Connect-AzAccount { $script:AzConnected = $true }
    Mock Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = $script:AzContextSubscription } } }
    Mock Get-AzRoleAssignment {
        param($ObjectId, $RoleDefinitionName, $Scope)
        # Azure returns the assignment at the scope and every inherited one above it.
        @($script:Tenant.AzRoleAssignments | Where-Object {
                $_.ObjectId -eq $ObjectId -and $_.RoleDefinitionName -eq $RoleDefinitionName -and $Scope.StartsWith($_.Scope, [System.StringComparison]::OrdinalIgnoreCase)
            } | ForEach-Object { [pscustomobject]$_ })
    }
    Mock New-AzRoleAssignment {
        param($ObjectId, $RoleDefinitionName, $Scope)
        $script:Tenant.AzRoleAssignments += @{ ObjectId = $ObjectId; RoleDefinitionName = $RoleDefinitionName; Scope = $Scope }
        Add-Write "NEW az role $RoleDefinitionName $Scope"
    }
    Mock Remove-AzRoleAssignment {
        param($ObjectId, $RoleDefinitionName, $Scope)
        $script:Tenant.AzRoleAssignments = @($script:Tenant.AzRoleAssignments | Where-Object {
                -not ($_.ObjectId -eq $ObjectId -and $_.RoleDefinitionName -eq $RoleDefinitionName -and $_.Scope -eq $Scope) })
        Add-Write "REMOVE az role $RoleDefinitionName $Scope"
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
    $script:Connected = $false
    $script:AzConnected = $false
    $script:ExchangeConnected = $false
    $script:ExchangeDisconnected = $false
    $script:ContextTenant = $script:Ids.Tenant
    $script:ContextScopes = @()
    $script:AzContextSubscription = $script:Ids.Subscription
    $script:SummaryDirs = @((Join-Path $TestDrive 'summary'))
    if (Test-Path (Join-Path $TestDrive 'summary')) { Remove-Item -Path (Join-Path $TestDrive 'summary') -Recurse -Force }
    New-Item -ItemType Directory -Path (Join-Path $TestDrive 'summary') -Force | Out-Null
}

Context 'Helpers' {
    It 'reads properties safely from objects, hashtables and null' {
        Get-NeologikProperty ([pscustomobject]@{ a = 1 }) 'a' | Should -Be 1
        Get-NeologikProperty ([pscustomobject]@{ a = 1 }) 'missing' 'dflt' | Should -Be 'dflt'
        Get-NeologikProperty @{ value = @(1, 2) } 'value' | Should -HaveCount 2
        Get-NeologikProperty @{ a = 1 } 'value' | Should -BeNullOrEmpty
        Get-NeologikProperty $null 'a' 'dflt' | Should -Be 'dflt'
    }

    It 'validates GUIDs' {
        Test-NeologikGuid $script:Ids.Tenant | Should -BeTrue
        Test-NeologikGuid 'not-a-guid' | Should -BeFalse
        Test-NeologikGuid "x' or 1 eq 1" | Should -BeFalse
        Test-NeologikGuid '' | Should -BeFalse
    }

    It 'normalises scope sets (order, duplicates, whitespace)' {
        Get-NeologikScopeSet '  Mail.Read   User.Read Mail.Read ' | Should -Be 'Mail.Read User.Read'
        Get-NeologikScopeSet 'User.Read Mail.Read' | Should -Be (Get-NeologikScopeSet 'Mail.Read User.Read')
        Get-NeologikScopeSet '' | Should -Be ''
        Get-NeologikScopeSet $null | Should -Be ''
    }

    It 'produces a one-line error text without tokens or stack traces' {
        try { throw "line one`nline two Bearer abc.def-ghi rest" } catch { $record = $_ }
        $text = Get-NeologikErrorText $record
        $text | Should -Not -Match 'abc\.def'
        $text | Should -Match 'bearer <token>'
        $text | Should -Not -Match "`n"
        Get-NeologikErrorText $null | Should -Be 'unknown error'
    }

    It 'derives the HTTP status from typed exceptions and from Graph error text' {
        try { throw (New-ForbiddenException) } catch { $forbidden = $_ }
        Get-NeologikHttpStatus $forbidden | Should -Be 403
        Test-NeologikPrivilegeError $forbidden | Should -BeTrue
        try { throw (New-NotFoundException) } catch { $notFound = $_ }
        Get-NeologikHttpStatus $notFound | Should -Be 404
        try { throw 'Request_ResourceNotFound: Resource does not exist' } catch { $textual = $_ }
        Get-NeologikHttpStatus $textual | Should -Be 404
        try { throw 'something else' } catch { $unknown = $_ }
        Get-NeologikHttpStatus $unknown | Should -Be 0
    }

    It 'honours Retry-After and caps the retry delay' {
        Get-NeologikRetryDelay -Headers @{ 'Retry-After' = @('7') } -Attempt 1 | Should -Be 7
        Get-NeologikRetryDelay -Headers @{ 'Retry-After' = @('600') } -Attempt 1 | Should -Be 60
        Get-NeologikRetryDelay -Headers @{} -Attempt 2 | Should -Be 4
        Get-NeologikRetryDelay -Headers $null -Attempt 10 | Should -Be 60
    }

    It 'refuses PowerShell below 7.4 with an ACTION REQUIRED message' {
        Test-NeologikPowerShellVersion -Version ([version]'5.1.22621') | Should -BeFalse
        ($script:Console -join "`n") | Should -Match 'ACTION REQUIRED'
        ($script:Console -join "`n") | Should -Match 'PowerShell 7.4 or later'
        Test-NeologikPowerShellVersion -Version ([version]'7.4.0') | Should -BeTrue
    }
}

Context 'Input validation (nothing is contacted when an input is wrong)' {
    It 'fails cleanly when neither a configuration file nor the ids are given' {
        $code = Invoke-Run @{ }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'TenantId could not be resolved'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'reports a missing configuration file' {
        $code = Invoke-Run @{ ConfigurationFile = (Join-Path $TestDrive 'nope.json') }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'Configuration file not found'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'reports a malformed configuration file' {
        $path = Join-Path $TestDrive 'bad.json'
        Set-Content -LiteralPath $path -Value '{ not json'
        $code = Invoke-Run @{ ConfigurationFile = $path }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'not valid JSON'
    }

    It 'reports an empty configuration file' {
        $path = Join-Path $TestDrive 'empty.json'
        Set-Content -LiteralPath $path -Value '   '
        $code = Invoke-Run @{ ConfigurationFile = $path }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'is empty'
    }

    It 'reports a configuration file that is not the onboarding export' {
        $path = Join-Path $TestDrive 'array.json'
        Set-Content -LiteralPath $path -Value '[{"IdentityAppId": "x"}]'
        $code = Invoke-Run @{ ConfigurationFile = $path }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'not the onboarding configuration'
    }

    It 'rejects ids that are not GUIDs before they reach a filter' {
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = "abc' or displayName eq 'x" }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'DeploySpClientId must be a GUID'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'requires the subscription and resource group for the pre-window run' {
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'pre-window run needs SubscriptionId'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'does not require the subscription for the post-window run' {
        Add-AgentIdentities
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry))
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId; AgentGrantsFile = $grants }
        $code | Should -Be 0
        Should -Invoke Connect-AzAccount -Times 0
    }

    It 'tolerates a configuration file without AppRegistration or SecurityGroups when the ids are explicit' {
        Add-CompliantPreWindowState
        $cfg = New-ConfigFile -Remove @('AppRegistration', 'SecurityGroups', 'NceAuthApp')
        $code = Invoke-Run @{ ConfigurationFile = $cfg; DeploySpClientId = $script:Ids.DeployAppId }
        $code | Should -Be 1
        Get-SummaryResult 'NCE group assignment' | Should -Be 'SKIPPED - ids not supplied'
        Get-SummaryResult 'Agent blueprint' | Should -Be 'Present'
    }

    It 'reports a missing agent grants file' {
        $cfg = New-ConfigFile
        $code = Invoke-Run @{ ConfigurationFile = $cfg; AgentGrantsFile = (Join-Path $TestDrive 'missing-grants.json') }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'Agent grants file not found'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'reports a malformed agent grants file' {
        $cfg = New-ConfigFile
        $grants = New-GrantsFile -Raw -RawContent '{"grants": ['
        $code = Invoke-Run @{ ConfigurationFile = $cfg; AgentGrantsFile = $grants }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'not valid JSON'
    }

    It 'reports an agent grants file of the wrong shape' {
        $cfg = New-ConfigFile
        $grants = New-GrantsFile -Raw -RawContent '[{"IdentityAppId": "x"}]'
        $code = Invoke-Run @{ ConfigurationFile = $cfg; AgentGrantsFile = $grants }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'not the platform export'
    }

    It 'refuses an agent grants file exported from another tenant' {
        $cfg = New-ConfigFile
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry)) -TenantId $script:Ids.OtherTenant
        $code = Invoke-Run @{ ConfigurationFile = $cfg; AgentGrantsFile = $grants }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'exported from tenant'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'rejects a ready grant entry without GUID ids or without scopes' {
        $cfg = New-ConfigFile
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -ClientId 'nope'))
        (Invoke-Run @{ ConfigurationFile = $cfg; AgentGrantsFile = $grants }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'must be GUIDs'
        $script:Console = @()
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('', ' ')))
        (Invoke-Run @{ ConfigurationFile = $cfg; AgentGrantsFile = $grants }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'needs scopes'
    }

    It 'accepts grant entries that are not ready without validating their ids' {
        Add-CompliantPreWindowState
        $cfg = New-ConfigFile
        $entry = New-AgentGrantEntry -Status 'identity-not-stamped' -ClientId $null -UserId $null
        $grants = New-GrantsFile -Grants @($entry)
        $code = Invoke-Run @{ ConfigurationFile = $cfg; AgentGrantsFile = $grants }
        $code | Should -Be 1
        Get-SummaryResult 'Agent-user grant: agent Support Agent' | Should -Be 'SKIPPED - identity not stamped'
    }

    It 'validates every mailbox grants entry' {
        $cfg = New-ConfigFile
        $file = New-MailboxFile -Entries @(@{ IdentityAppId = $script:Ids.MailboxAppId; IdentityObjectId = $script:Ids.MailboxObjectId; Mailbox = 'support@contoso.com' })
        (Invoke-Run @{ ConfigurationFile = $cfg; MailboxGrantsFile = $file }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'every entry needs DisplayName'
        $script:Console = @()
        $file = New-MailboxFile -Entries @(@{ IdentityAppId = 'x'; IdentityObjectId = $script:Ids.MailboxObjectId; Mailbox = 'support@contoso.com'; DisplayName = 'neo' })
        (Invoke-Run @{ ConfigurationFile = $cfg; MailboxGrantsFile = $file }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'must be GUIDs'
        $script:Console = @()
        $file = New-MailboxFile -Entries @(@{ IdentityAppId = $script:Ids.MailboxAppId; IdentityObjectId = $script:Ids.MailboxObjectId; Mailbox = 'not-an-address'; DisplayName = 'neo' })
        (Invoke-Run @{ ConfigurationFile = $cfg; MailboxGrantsFile = $file }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'is not a mailbox address'
        $script:Console = @()
        $file = New-MailboxFile -Raw -RawContent 'nonsense'
        (Invoke-Run @{ ConfigurationFile = $cfg; MailboxGrantsFile = $file }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'not valid JSON'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'rejects legacy application ids that are not GUIDs' {
        $cfg = New-ConfigFile
        (Invoke-Run @{ ConfigurationFile = $cfg; RemoveLegacyGrantAppIds = @('old-monitor') }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'RemoveLegacyGrantAppIds must be'
    }

    It 'refuses -RemoveLegacyGrantAppIds without the mailbox grants file that lists the adopted identities' {
        $cfg = New-ConfigFile
        (Invoke-Run @{ ConfigurationFile = $cfg; RemoveLegacyGrantAppIds = @($script:Ids.LegacyAppId) }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'belongs to the post-window run'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'rejects a mailbox grants file of the wrong shape, adopted ids that are not GUIDs, and another tenant''s export' {
        $cfg = New-ConfigFile
        $file = New-MailboxFile -Raw -RawContent '{"IdentityAppId": "x"}'
        (Invoke-Run @{ ConfigurationFile = $cfg; MailboxGrantsFile = $file }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'not the platform export'
        $script:Console = @()
        $file = New-MailboxFile -Entries @() -AdoptedIdentityAppIds @('not-a-guid')
        (Invoke-Run @{ ConfigurationFile = $cfg; MailboxGrantsFile = $file }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'adoptedIdentityAppIds must be'
        $script:Console = @()
        $file = New-MailboxFile -AsObject -TenantId $script:Ids.OtherTenant
        (Invoke-Run @{ ConfigurationFile = $cfg; MailboxGrantsFile = $file }) | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'exported from tenant'
        Should -Invoke Connect-MgGraph -Times 0
    }
}

Context 'Modules and sign-in' {
    It 'installs a missing Graph module before importing one consistent version' {
        Add-CompliantPreWindowState
        Mock Get-NeologikAvailableModuleVersion {
            param($Name)
            if ($Name -eq 'Microsoft.Graph.Groups' -and $script:Installs -notcontains $Name) { return @() }
            @([version]'2.38.0', [version]'2.20.0')
        }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Installs | Should -Contain 'Microsoft.Graph.Groups'
        $script:Imports | Should -Contain 'Microsoft.Graph.Applications 2.38.0'
        $script:Imports | Should -Contain 'Microsoft.Graph.Groups 2.38.0'
    }

    It 'imports the highest version every Graph module has in common' {
        Add-CompliantPreWindowState
        Mock Get-NeologikAvailableModuleVersion {
            param($Name)
            if ($Name -eq 'Microsoft.Graph.Authentication') { return @([version]'2.40.0', [version]'2.38.0') }
            @([version]'2.38.0')
        }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Imports | Should -Contain 'Microsoft.Graph.Authentication 2.38.0'
        $script:Imports | Should -Not -Contain 'Microsoft.Graph.Authentication 2.40.0'
    }

    It 'pins to the Graph version already loaded in the session' {
        Add-CompliantPreWindowState
        Mock Get-NeologikLoadedModuleVersion { param($Name) if ($Name -eq 'Microsoft.Graph.Authentication') { [version]'2.30.0' } }
        Mock Get-NeologikAvailableModuleVersion { @([version]'2.38.0', [version]'2.30.0') }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Imports | Should -Contain 'Microsoft.Graph.Groups 2.30.0'
    }

    It 'stops with ACTION REQUIRED when a module cannot be installed' {
        Mock Get-NeologikAvailableModuleVersion { @() }
        Mock Install-NeologikModule { throw 'No match was found for the specified search criteria' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'ACTION REQUIRED'
        ($script:Console -join "`n") | Should -Match 'Install-Module Microsoft.Graph.Authentication'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'stops with ACTION REQUIRED when the Graph sign-in fails' {
        Mock Connect-MgGraph { throw 'Device code authentication timed out' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'Sign in to Microsoft Graph did not complete'
        Should -Invoke Get-MgServicePrincipal -Times 0
    }

    It 'stops when the session landed in a different tenant' {
        $script:ContextTenant = $script:Ids.OtherTenant
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'landed in tenant'
        Should -Invoke Get-MgServicePrincipal -Times 0
    }

    It 'requests the read scopes the verification steps need' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter {
            $Scopes -contains 'Directory.Read.All' -and $Scopes -contains 'User.Read' -and $Scopes -contains 'AppRoleAssignment.ReadWrite.All' -and
            $Scopes -contains 'RoleManagement.ReadWrite.Directory' -and $Scopes -notcontains 'DelegatedPermissionGrant.ReadWrite.All' -and $UseDeviceCode
        }
    }

    It 'adds the grant write scope only with a grants file and the directory role scope only in the pre-window run' {
        Add-AgentIdentities
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry))
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
        Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $Scopes -contains 'DelegatedPermissionGrant.ReadWrite.All' -and $Scopes -notcontains 'RoleManagement.ReadWrite.Directory' }
        Add-CompliantExchangeState
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = (New-MailboxFile) }
        Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $Scopes -notcontains 'DelegatedPermissionGrant.ReadWrite.All' -and $Scopes -notcontains 'RoleManagement.ReadWrite.Directory' }
        Add-CompliantPreWindowState
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $Scopes -contains 'RoleManagement.ReadWrite.Directory' -and $Scopes -notcontains 'DelegatedPermissionGrant.ReadWrite.All' }
    }

    It 'warns when the session lacks a requested permission' {
        Add-CompliantPreWindowState
        $script:ContextScopes = @('Application.ReadWrite.All')
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        ($script:Console -join "`n") | Should -Match 'lacks the permission'
    }

    It 'uses the Azure CLI token when asked and never prints it' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UseAzureCliToken = $true }
        $code | Should -Be 0
        Should -Invoke Invoke-NeologikAzureCli -Times 1 -ParameterFilter { ($Arguments -join ' ') -match "get-access-token --resource-type ms-graph --tenant $($script:Ids.Tenant)" }
        Should -Invoke Connect-MgGraph -Times 1 -ParameterFilter { $AccessToken -is [securestring] -and -not $UseDeviceCode }
        ($script:Console -join "`n") | Should -Not -Match 'eyJ0b2tlbg'
    }

    It 'stops with ACTION REQUIRED when the Azure CLI is absent or not signed in' {
        Mock Test-NeologikCommand { $false }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UseAzureCliToken = $true }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'Azure CLI \(az\) is not installed'
        Mock Test-NeologikCommand { $true }
        Mock Invoke-NeologikAzureCli { @{ ExitCode = 1; Output = @() } }
        $script:Console = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); UseAzureCliToken = $true }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'az login --tenant'
        Should -Invoke Connect-MgGraph -Times 0
    }

    It 'stops with a clear message when the deployment identity does not exist' {
        $script:Tenant.ServicePrincipals = @($script:Tenant.ServicePrincipals | Where-Object { $_.id -ne $script:Ids.DeploySpId })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Deployment identity' | Should -Be 'MISSING - service principal not found'
        ($script:Console -join "`n") | Should -Match 'ACTION REQUIRED'
        $script:Writes | Should -HaveCount 0
    }

    It 'reports a Graph read failure on the deployment identity without a stack trace' {
        Mock Get-MgServicePrincipal { throw (New-ForbiddenException) }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Deployment identity') | Should -Match '^FAILED - '
    }
}

Context 'Pre-window run on a compliant environment' {
    It 'is a pure verification pass: exit 0, no writes, every item in place' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        $script:Summary | Should -Not -BeNullOrEmpty
        @($script:Summary | Where-Object { $_.Result -match $script:AttentionPattern }) | Should -HaveCount 0
        Get-SummaryResult 'Agent blueprint' | Should -Be 'Present'
        Get-SummaryResult 'Blueprint owner' | Should -Be 'Already in place'
        Get-SummaryResult 'Blueprint principal' | Should -Be 'Present'
        Get-SummaryResult 'Blueprint principal owner' | Should -Be 'Already in place'
        Get-SummaryResult 'Blueprint principal role: AgentIdUser.ReadWrite.IdentityParentedBy' | Should -Be 'Already granted'
        Get-SummaryResult 'Blueprint credential: github-oidc-neo-env-config' | Should -Be 'Present'
        Get-SummaryResult 'Graph role: Application.ReadWrite.OwnedBy' | Should -Be 'Already granted'
        Get-SummaryResult 'Retired Graph role: Group.Create' | Should -Be 'Not held'
        Get-SummaryResult 'NCE group assignment' | Should -Be 'Already assigned'
        Get-SummaryResult 'Admin consent' | Should -Be 'Present'
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Not checked - runs with the agent grants file'
        Get-SummaryResult 'RG role: Contributor' | Should -Be 'Already in place'
        Get-SummaryResult 'subscription role: Cost Management Contributor' | Should -Be 'Already in place'
        Get-SummaryResult 'Legacy subscription role: Contributor' | Should -Be 'Not present'
        Get-SummaryResult 'Application Administrator role' | Should -Be 'Not held'
        Should -Invoke Connect-AzAccount -Times 1
        ($script:Console -join "`n") | Should -Match 'pre-window run'
        ($script:Console -join "`n") | Should -Match 'Pre-window run complete'
    }

    It 'checks the Sites.Selected consent when the configuration file records SharePoint ingestion' {
        Add-CompliantPreWindowState
        Add-SharePointApp -WithConsent
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile -Overrides @{ SharePointIngestion = $true }) }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Present'
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile -Overrides @{ SharePointIngestion = $false }) }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Not needed'
        $script:Writes | Should -HaveCount 0
    }

    It 'writes the JSON summary beside the script with the held roles and every item' {
        Add-CompliantPreWindowState
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentAccess_PreWindow_*.json')
        $files | Should -HaveCount 1
        $json = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        $json.tenantId | Should -Be $script:Ids.Tenant
        $json.deploymentIdentity | Should -Be $script:Ids.DeployAppId
        $json.run | Should -Be 'PreWindow'
        $json.verifyOnly | Should -BeFalse
        $json.pendingChangeCount | Should -Be 0
        @($json.deploymentGraphRoles) | Should -Contain 'Application.ReadWrite.OwnedBy'
        @($json.deploymentGraphRoles) | Should -Contain 'AgentIdentityBlueprint.AddRemoveCreds.All'
        @($json.expectedGraphRoles) | Should -HaveCount 2
        @($json.items).Count | Should -Be $script:Summary.Count
        $json.attentionCount | Should -Be 0
        $bytes = [IO.File]::ReadAllBytes($files[0].FullName)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) | Should -BeFalse -Because 'UTF-8 without BOM'
    }

    It 'falls back to the next summary location when the first is not writable' {
        Add-CompliantPreWindowState
        $second = Join-Path $TestDrive 'summary2'
        New-Item -ItemType Directory -Path $second -Force | Out-Null
        $script:SummaryDirs = @((Join-Path $TestDrive 'does-not-exist\nested'), $second)
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        @(Get-ChildItem -Path $second -Filter '*.json') | Should -HaveCount 1
        ($script:Console -join "`n") | Should -Match 'trying the next location'
    }

    It 'derives the short name from the deployment identity when no configuration file is given' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId; SignInAppClientId = $script:Ids.SignInAppId; NceUserGroupId = $script:Ids.Group; SubscriptionId = $script:Ids.Subscription; ResourceGroupName = $script:RgName }
        $code | Should -Be 0
        Get-SummaryResult 'Agent blueprint' | Should -Be 'Present'
        $script:Writes | Should -HaveCount 0
    }

    It 'skips the group assignment and consent check when the ids are not supplied' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId; SubscriptionId = $script:Ids.Subscription; ResourceGroupName = $script:RgName }
        $code | Should -Be 1
        Get-SummaryResult 'NCE group assignment' | Should -Be 'SKIPPED - ids not supplied'
        Get-SummaryResult 'Admin consent' | Should -BeNullOrEmpty
    }
}

Context 'Pre-window run on an environment with missing state' {
    It 'performs the directory checks and then the guarded permission reduction, in that order' {
        Add-CompliantPreWindowState
        $deploy = Get-FakeSp -Id $script:Ids.DeploySpId
        $deploy.appRoleAssignments = @()
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'Application.Read.All'
        $script:Tenant.AzRoleAssignments = @()
        $script:Tenant.DirectoryRoles = @()
        Add-LegacyAzureState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Graph role: Application.ReadWrite.OwnedBy' | Should -Be 'Granted'
        Get-SummaryResult 'Retired Graph role: Application.Read.All' | Should -Be 'Removed'
        Get-SummaryResult 'RG role: Contributor' | Should -Be 'Created'
        Get-SummaryResult 'Legacy subscription role: User Access Administrator' | Should -Be 'Removed'
        Get-SummaryResult 'Application Administrator role' | Should -Be 'Removed'
        $kinds = @($script:Writes | ForEach-Object {
                if ($_ -like 'NEW approle*') { 'graph-grant' }
                elseif ($_ -like 'REMOVE approle*') { 'graph-remove' }
                elseif ($_ -like 'NEW az role*') { 'az-create' }
                elseif ($_ -like 'REMOVE az role*') { 'az-remove' }
                elseif ($_ -like 'REMOVE directory role member*') { 'role-remove' }
                else { $_ } })
        @($kinds | Select-Object -Unique) | Should -Be @('graph-grant', 'graph-remove', 'az-create', 'az-remove', 'role-remove')
        Should -Invoke Connect-AzAccount -Times 1
    }

    It 'creates the blueprint, its principal, ownership, role and credentials, then verifies clean on a second run' {
        Add-CompliantAzureState
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'Application.ReadWrite.OwnedBy'
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'AgentIdentityBlueprint.AddRemoveCreds.All'
        $group = @($script:Tenant.Groups)[0]
        $group.appRoleAssignments = @(@{ Id = 'x'; ResourceId = $script:Ids.SignInSpId; AppRoleId = '00000000-0000-0000-0000-000000000000' })
        (Get-FakeSp -Id $script:Ids.SignInSpId).grants = @(@{ id = 'g'; clientId = $script:Ids.SignInSpId; consentType = 'AllPrincipals'; principalId = $null; resourceId = $script:Ids.GraphSpId; scope = 'User.Read' })
        $script:Tenant.PrincipalCreateDelays = 2
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Agent blueprint' | Should -Be 'Created'
        Get-SummaryResult 'Blueprint owner' | Should -Be 'Already in place' -Because 'owners@odata.bind set the deployment identity at creation'
        Get-SummaryResult 'Blueprint principal' | Should -Be 'Created'
        Get-SummaryResult 'Blueprint principal owner' | Should -Be 'Added'
        Get-SummaryResult 'Blueprint principal role: AgentIdUser.ReadWrite.IdentityParentedBy' | Should -Be 'Granted'
        Get-SummaryResult 'Blueprint credential: github-oidc-neo-infrastructure' | Should -Be 'Added'
        @($script:Writes | Where-Object { $_ -like 'POST credential*' }) | Should -HaveCount 3
        @($script:Sleeps | Where-Object { $_ -eq 15 }) | Should -HaveCount 2 -Because 'the principal create is retried while the blueprint replicates'
        $blueprintApp = @($script:Tenant.Apps)[0]
        $blueprintApp.displayName | Should -Be "Neologik Agent Blueprint - default - $script:ShortName"
        $blueprintApp.owners | Should -Contain $script:Ids.DeploySpId
        $blueprintApp.owners | Should -Contain $script:Ids.Me
        # Second run: nothing left to do.
        $script:Writes = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        Get-SummaryResult 'Blueprint principal' | Should -Be 'Present'
    }

    It 'adopts a pipeline-created blueprint the deployment identity does not own yet' {
        Add-CompliantPreWindowState
        $app = Get-FakeApp -Id $script:Ids.BlueprintAppObj
        $app.owners = @($script:Ids.Me)
        $principal = Get-FakeSp -Id $script:Ids.BlueprintSpId
        $principal.owners = @()
        $app.credentials = @('github-oidc-neo-infrastructure')
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Blueprint owner' | Should -Be 'Added'
        Get-SummaryResult 'Blueprint principal owner' | Should -Be 'Added'
        Get-SummaryResult 'Blueprint credential: github-oidc-neo-infrastructure' | Should -Be 'Present'
        Get-SummaryResult 'Blueprint credential: github-oidc-neo-bot-service' | Should -Be 'Added'
        $app.owners | Should -Contain $script:Ids.DeploySpId
        $principal.owners | Should -Contain $script:Ids.DeploySpId
        @($script:Writes) | Should -HaveCount 4
    }

    It 'grants the retained Graph roles before removing the retired ones' {
        Add-CompliantPreWindowState
        $deploy = Get-FakeSp -Id $script:Ids.DeploySpId
        $deploy.appRoleAssignments = @()
        foreach ($roleName in @('Application.Read.All', 'AgentIdentity.Create.All', 'Group.Create')) { Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName $roleName }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Graph role: Application.ReadWrite.OwnedBy' | Should -Be 'Granted'
        Get-SummaryResult 'Graph role: AgentIdentityBlueprint.AddRemoveCreds.All' | Should -Be 'Granted'
        Get-SummaryResult 'Retired Graph role: Application.Read.All' | Should -Be 'Removed'
        Get-SummaryResult 'Retired Graph role: Group.Create' | Should -Be 'Removed'
        Get-SummaryResult 'Retired Graph role: AgentIdUser.ReadWrite.All' | Should -Be 'Not held'
        $roleWrites = @($script:Writes | Where-Object { $_ -match "approle $($script:Ids.DeploySpId)" })
        $roleWrites | Should -HaveCount 5
        $roleWrites[0] | Should -Match '^NEW'
        $roleWrites[1] | Should -Match '^NEW'
        $roleWrites[2] | Should -Match '^REMOVE'
        $held = @((Get-FakeSp -Id $script:Ids.DeploySpId).appRoleAssignments | ForEach-Object { $_.AppRoleId })
        $held | Should -HaveCount 2
        $held | Should -Contain $script:AppRoleIds['Application.ReadWrite.OwnedBy']
    }

    It 'leaves the retired roles in place when a retained role could not be granted' {
        Add-CompliantPreWindowState
        $deploy = Get-FakeSp -Id $script:Ids.DeploySpId
        $deploy.appRoleAssignments = @()
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'Application.Read.All'
        Mock New-MgServicePrincipalAppRoleAssignment { throw (New-ForbiddenException) }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Graph role: Application.ReadWrite.OwnedBy') | Should -Match '^FAILED - insufficient privileges'
        Get-SummaryResult 'Retired Graph role: Application.Read.All' | Should -Be 'SKIPPED - retained roles not all granted'
        Should -Invoke Remove-MgServicePrincipalAppRoleAssignment -Times 0
        (Get-FakeSp -Id $script:Ids.DeploySpId).appRoleAssignments | Should -HaveCount 1
    }

    It 'reports a Graph role the cloud does not publish without stopping' {
        Add-CompliantPreWindowState
        $script:AppRoleIds.Remove('AgentIdentityBlueprint.AddRemoveCreds.All')
        try {
            $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
            $code | Should -Be 1
            Get-SummaryResult 'Graph role: AgentIdentityBlueprint.AddRemoveCreds.All' | Should -Be 'NOT FOUND - report'
            Get-SummaryResult 'Admin consent' | Should -Be 'Present'
        }
        finally {
            $script:AppRoleIds['AgentIdentityBlueprint.AddRemoveCreds.All'] = [guid]::NewGuid().ToString()
        }
    }

    It 'assigns the NCE user group to the sign-in application when missing' {
        Add-CompliantPreWindowState
        $group = @($script:Tenant.Groups)[0]
        $group.appRoleAssignments = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'NCE group assignment' | Should -Be 'Assigned'
        Should -Invoke New-MgGroupAppRoleAssignment -Times 1 -ParameterFilter { $GroupId -eq $script:Ids.Group -and $PrincipalId -eq $script:Ids.Group -and $ResourceId -eq $script:Ids.SignInSpId -and $AppRoleId -eq '00000000-0000-0000-0000-000000000000' }
        $script:Writes | Should -HaveCount 1
    }

    It 'warns when the NCE user group has no direct members' {
        Add-CompliantPreWindowState
        $group = @($script:Tenant.Groups)[0]
        $group.members = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        ($script:Console -join "`n") | Should -Match 'has no members'
    }

    It 'reports a missing group and a missing sign-in application as MISSING, not as a crash' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile -Overrides @{ SecurityGroups = @(@{ Name = "Neologik NCE User Group - $script:ShortName"; Id = $script:Ids.AdminGroup }) }) }
        $code | Should -Be 1
        Get-SummaryResult 'NCE group assignment' | Should -Be 'MISSING - group not found (check the id)'
        Get-SummaryResult 'Admin consent' | Should -Be 'Present'
        $script:Tenant = New-EmptyTenant
        Add-CompliantPreWindowState
        $script:Tenant.ServicePrincipals = @($script:Tenant.ServicePrincipals | Where-Object { $_.id -ne $script:Ids.SignInSpId })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'NCE group assignment' | Should -Be 'MISSING - sign-in application not found'
        Get-SummaryResult 'Admin consent' | Should -Be 'SKIPPED - sign-in application not found'
    }

    It 'prints the consent URL when tenant-wide admin consent is missing' {
        Add-CompliantPreWindowState
        (Get-FakeSp -Id $script:Ids.SignInSpId).grants = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Admin consent' | Should -Be 'MISSING - consent URL printed'
        ($script:Console -join "`n") | Should -Match "https://login.microsoftonline.com/$($script:Ids.Tenant)/adminconsent\?client_id=$($script:Ids.SignInAppId)"
        $script:Writes | Should -HaveCount 0
    }

    It 'treats a user-level grant as no tenant-wide consent' {
        Add-CompliantPreWindowState
        (Get-FakeSp -Id $script:Ids.SignInSpId).grants = @(@{ id = 'p'; clientId = $script:Ids.SignInSpId; consentType = 'Principal'; principalId = $script:Ids.Me; resourceId = $script:Ids.GraphSpId; scope = 'User.Read' })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Admin consent' | Should -Be 'MISSING - consent URL printed'
    }

    It 'continues past a blueprint failure and records the dependents as skipped' {
        Add-CompliantPreWindowState
        $script:Faults += @{ Match = 'GET /applications$'; Status = 403; Code = 'Authorization_RequestDenied'; Message = 'Insufficient privileges'; Remaining = 1 }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Agent blueprint') | Should -Match '^FAILED - insufficient privileges'
        Get-SummaryResult 'Blueprint principal' | Should -Be 'SKIPPED - blueprint not available'
        Get-SummaryResult 'Graph role: Application.ReadWrite.OwnedBy' | Should -Be 'Already granted'
        Get-SummaryResult 'Admin consent' | Should -Be 'Present'
    }
}

Context 'Post-window run: agent grants file (step 5)' {
    It 'touches nothing else: no blueprint, no roles, no group assignment, no reduction' {
        # A tenant where every pre-window item is missing or legacy.
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'Application.Read.All'
        Add-LegacyAzureState
        Add-AgentIdentities -NoGrants
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read')))
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
        $code | Should -Be 0
        Get-SummaryResult 'Agent-user grant: agent Support Agent' | Should -Be 'Granted (User.Read)'
        $script:Writes | Should -HaveCount 1
        $script:Writes[0] | Should -BeLike 'POST grant*'
        foreach ($item in @('Agent blueprint', 'Graph role: Application.ReadWrite.OwnedBy', 'Retired Graph role: Application.Read.All', 'NCE group assignment',
                'Admin consent', 'RG role: Contributor', 'Legacy subscription role: Contributor', 'Application Administrator role')) {
            Get-SummaryResult $item | Should -BeNullOrEmpty -Because "the post-window run must not touch '$item'"
        }
        Should -Invoke Connect-AzAccount -Times 0
        Should -Invoke Connect-ExchangeOnline -Times 0
        @($script:Tenant.Apps) | Should -HaveCount 0
        (Get-FakeSp -Id $script:Ids.DeploySpId).appRoleAssignments | Should -HaveCount 1
        @($script:Tenant.DirectoryRoles)[0].members | Should -Contain $script:Ids.DeploySpId
        ($script:Console -join "`n") | Should -Match 'post-window run'
        ($script:Console -join "`n") | Should -Match 'Post-window run complete'
    }

    It 'does nothing beyond the SharePoint marker for a file with no entries' {
        $grants = New-GrantsFile -Grants @() -SharePoint $false
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Not needed'
        @($script:Summary | Where-Object { $_.Item -like 'Agent-user grant:*' }) | Should -HaveCount 0
        $script:Writes | Should -HaveCount 0
    }

    It 'surfaces export warnings from the file' {
        $grants = New-GrantsFile -Grants @() -Warnings @('apps not enumerated: registry unavailable')
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
        ($script:Console -join "`n") | Should -Match 'export warning: apps not enumerated'
    }

    It 'verifies an existing grant with the same scope set in any order' {
        Add-AgentIdentities -AgentScope 'Sites.ReadWrite.All User.Read'
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read', 'Sites.ReadWrite.All')))
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
        $code | Should -Be 0
        Get-SummaryResult 'Agent-user grant: agent Support Agent' | Should -Be 'Already granted'
        $script:Writes | Should -HaveCount 0
    }

    It 'creates the grant when absent and aligns it when the scope differs' {
        Add-AgentIdentities -NoGrants
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read', 'Mail.Read')))
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
        $code | Should -Be 0
        Get-SummaryResult 'Agent-user grant: agent Support Agent' | Should -Be 'Granted (Mail.Read User.Read)'
        @($script:Writes | Where-Object { $_ -like 'POST grant*' }) | Should -HaveCount 1
        $created = @((Get-FakeSp -Id $script:Ids.AgentIdentitySp).grants)[0]
        $created.principalId | Should -Be $script:Ids.AgentUser
        $created.resourceId | Should -Be $script:Ids.GraphSpId
        $created.consentType | Should -Be 'Principal'
        # Now the platform adds a pack: the existing grant is patched, not duplicated.
        $script:Writes = @()
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read', 'Mail.Read', 'Calendars.Read')))
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
        $code | Should -Be 0
        Get-SummaryResult 'Agent-user grant: agent Support Agent' | Should -Be 'Updated (Calendars.Read Mail.Read User.Read)'
        @($script:Writes | Where-Object { $_ -like 'PATCH grant*' }) | Should -HaveCount 1
        @((Get-FakeSp -Id $script:Ids.AgentIdentitySp).grants) | Should -HaveCount 1
    }

    It 'never touches a grant on another resource with the same client and principal' {
        Add-AgentIdentities -NoGrants
        $agentSp = Get-FakeSp -Id $script:Ids.AgentIdentitySp
        $agentSp.grants = @(@{ id = 'grant-sharepoint'; clientId = $script:Ids.AgentIdentitySp; principalId = $script:Ids.AgentUser; resourceId = 'sharepoint-resource'; consentType = 'Principal'; scope = 'AllSites.Read' })
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read')))
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
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
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
        $code | Should -Be 1
        Get-SummaryResult 'Agent-user grant: agent Support Agent' | Should -Be 'Already granted'
        Get-SummaryResult 'Agent-user grant: app Reference App' | Should -Be 'Updated (Mail.Read Mail.Send User.Read)'
        Get-SummaryResult 'Agent-user grant: app MS Planner' | Should -Be 'SKIPPED - identity not stamped'
        Get-SummaryResult "Agent-user grant: agent O'Brien Agent" | Should -Be 'MISSING - agent identity not found'
        $script:Writes | Should -HaveCount 1
    }

    It 'retries a refused scope string with a rotated order and reports success only after read-back' {
        Add-AgentIdentities -NoGrants
        $script:Tenant.GrantRefusals = @('Mail.Read Sites.ReadWrite.All User.Read', 'Sites.ReadWrite.All User.Read Mail.Read')
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read', 'Mail.Read', 'Sites.ReadWrite.All')))
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
        $code | Should -Be 0
        Get-SummaryResult 'Agent-user grant: agent Support Agent' | Should -Be 'Granted (Mail.Read Sites.ReadWrite.All User.Read)'
        @($script:Writes | Where-Object { $_ -like 'POST grant*' }) | Should -HaveCount 1
        ($script:Console -join "`n") | Should -Match 'attempt 2 refused'
    }

    It 'reports PENDING when every rotation is refused' {
        Add-AgentIdentities -NoGrants
        $script:Tenant.GrantRefusals = @('Mail.Read User.Read', 'User.Read Mail.Read', 'Mail.Read User.Read')
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read', 'Mail.Read')))
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
        $code | Should -Be 1
        Get-SummaryResult 'Agent-user grant: agent Support Agent' | Should -Be 'PENDING - scope refused, report'
    }

    It 'stops retrying on a privilege refusal and names the missing permission' {
        Add-AgentIdentities -NoGrants
        $script:Faults += @{ Match = 'POST /oauth2PermissionGrants$'; Status = 403; Code = 'Authorization_RequestDenied'; Message = 'Insufficient privileges to complete the operation.'; Remaining = 5 }
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read')))
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
        $code | Should -Be 1
        (Get-SummaryResult 'Agent-user grant: agent Support Agent') | Should -Match '^FAILED - insufficient privileges'
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
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
        $code | Should -Be 1
        Get-SummaryResult 'Component refapp role: User.Read.All' | Should -Be 'Granted'
        Get-SummaryResult 'Component role: refapp Mail.Read' | Should -Be 'SKIPPED - mailbox-scoped, administrator grants per resource'
        Get-SummaryResult 'Component role: refapp Application Mail.Read' | Should -Be 'SKIPPED - exchange role'
        Get-SummaryResult 'Component role: other User.Read.All' | Should -Be 'MISSING - identity not found'
        Get-SummaryResult 'Component role: broken ' | Should -Be 'SKIPPED - incomplete entry in the grants file'
        @($script:Writes | Where-Object { $_ -like "NEW approle $($script:Ids.ComponentSpId)*" }) | Should -HaveCount 1
        # Second run: the component role is already there.
        $script:Writes = @()
        $null = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
        Get-SummaryResult 'Component refapp role: User.Read.All' | Should -Be 'Already granted'
        $script:Writes | Should -HaveCount 0
    }

    It 'confirms the Sites.Selected consent of this environment''s SharePoint app' {
        Add-SharePointApp -WithConsent -Second
        $grants = New-GrantsFile -Grants @() -SharePoint $true
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Present'
        $script:Writes | Should -HaveCount 0
    }

    It 'prints the SharePoint consent URL when Sites.Selected is missing' {
        Add-SharePointApp
        $grants = New-GrantsFile -Grants @() -SharePoint $true
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
        $code | Should -Be 1
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'MISSING - consent URL printed'
        ($script:Console -join "`n") | Should -Match "adminconsent\?client_id=$($script:Ids.SharePointAppId)"
    }

    It 'falls back to the single prefix match without a short name, and reports ambiguity as UNKNOWN' {
        Add-SharePointApp -WithConsent
        $grants = New-GrantsFile -Grants @() -SharePoint $true
        $params = @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId; SignInAppClientId = $script:Ids.SignInAppId; NceUserGroupId = $script:Ids.Group; AgentGrantsFile = $grants }
        $code = Invoke-Run $params
        $code | Should -Be 0
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'Present'
        $script:Tenant.ServicePrincipals += New-FakeSp -Id $script:Ids.SharePoint2SpId -AppId $script:Ids.SharePoint2AppId -DisplayName 'Neologik SharePoint Access - other01'
        $code = Invoke-Run $params
        $code | Should -Be 1
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'UNKNOWN - several apps, environment not identified'
    }

    It 'reports a missing SharePoint app' {
        $grants = New-GrantsFile -Grants @() -SharePoint $true
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants }
        $code | Should -Be 1
        Get-SummaryResult 'SharePoint Sites.Selected consent' | Should -Be 'MISSING - app not found'
    }
}

Context 'Post-window run: mailbox grants file (step 6)' {
    It 'verifies a fully granted mailbox without writing, and always disconnects' {
        Add-CompliantExchangeState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Mailbox grant: support@contoso.com -> neo-support' | Should -Be 'Already granted'
        $script:Writes | Should -HaveCount 0
        $script:ExchangeConnected | Should -BeTrue
        $script:ExchangeDisconnected | Should -BeTrue
        Should -Invoke Connect-ExchangeOnline -Times 1 -ParameterFilter { $Device }
    }

    It 'creates the pointer, the scope and the three assignments when nothing exists' {
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Mailbox grant: support@contoso.com -> neo-support' | Should -Be 'Granted (3 role(s) added)'
        $script:Writes | Should -Contain "NEW exo sp $($script:Ids.MailboxAppId)"
        $script:Writes | Should -Contain 'NEW exo scope Scope-neo-support'
        @($script:Writes | Where-Object { $_ -like 'NEW exo assignment*' }) | Should -HaveCount 3
        Should -Invoke New-ManagementScope -Times 1 -ParameterFilter { $RecipientRestrictionFilter -eq "PrimarySmtpAddress -eq 'support@contoso.com'" }
        Should -Invoke New-ManagementRoleAssignment -Times 3 -ParameterFilter { $App -eq $script:Ids.MailboxObjectId -and $CustomResourceScope -eq 'Scope-neo-support' }
        # Second run verifies without writing.
        $script:Writes = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
    }

    It 'reuses an existing scope with the same recipient filter under another name' {
        $script:Tenant.Exchange.Scopes += @{ Name = 'Scope-email-monitor'; RecipientFilter = "PrimarySmtpAddress -eq 'support@contoso.com'" }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 0
        Should -Invoke New-ManagementScope -Times 0
        Should -Invoke New-ManagementRoleAssignment -Times 3 -ParameterFilter { $CustomResourceScope -eq 'Scope-email-monitor' }
        ($script:Console -join "`n") | Should -Match 'reusing management scope'
    }

    It 'reports PENDING while Exchange has not propagated the grant' {
        $script:Tenant.Exchange.InScope = $false
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Mailbox grant: support@contoso.com -> neo-support' | Should -Be 'PENDING - re-run to confirm InScope'
    }

    It 'reports PENDING when the authorisation test itself fails, without stopping the run' {
        Mock Test-ServicePrincipalAuthorization { throw 'The service principal was not found' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Mailbox grant: support@contoso.com -> neo-support' | Should -Be 'PENDING - re-run to confirm InScope'
        $script:ExchangeDisconnected | Should -BeTrue
    }

    It 'enables organisation customisation once when the tenant is dehydrated' {
        $script:Tenant.Exchange.Dehydrated = $true
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 0
        Should -Invoke Enable-OrganizationCustomization -Times 1
        $script:Sleeps | Should -Contain 60
    }

    It 'records a failed grant with its reason and still disconnects' {
        Mock New-ManagementRoleAssignment { throw 'The user is not assigned to any management roles' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Mailbox grant: support@contoso.com -> neo-support') | Should -Match '^FAILED - The user is not assigned'
        $script:ExchangeDisconnected | Should -BeTrue
    }

    It 'skips every mailbox item when the Exchange sign-in fails' {
        Mock Connect-ExchangeOnline { throw 'Device login timed out' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = (New-MailboxFile); RemoveLegacyGrantAppIds = @($script:Ids.LegacyAppId) }
        $code | Should -Be 1
        Get-SummaryResult 'Mailbox grant: support@contoso.com -> neo-support' | Should -Be 'SKIPPED - Exchange Online sign-in failed'
        Get-SummaryResult "Legacy mailbox grant: $($script:Ids.LegacyAppId)" | Should -Be 'SKIPPED - Exchange Online sign-in failed'
        Should -Invoke Disconnect-ExchangeOnline -Times 0
        ($script:Console -join "`n") | Should -Match 'Exchange Administrator or Global Administrator'
    }

    It 'installs the Exchange module when absent and skips when it cannot be installed' {
        Mock Get-NeologikAvailableModuleVersion { param($Name) if ($Name -eq 'ExchangeOnlineManagement' -and $script:Installs -notcontains $Name) { @() } else { @([version]'3.10.0') } }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 0
        $script:Installs | Should -Contain 'ExchangeOnlineManagement'
        Mock Install-NeologikModule { throw 'no gallery access' }
        $script:Installs = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Mailbox grant: support@contoso.com -> neo-support' | Should -Be 'SKIPPED - Exchange Online module not available'
    }

    It 'removes a retired identity''s assignments and pointer, leaving the scope' {
        $x = $script:Tenant.Exchange
        $x.ServicePrincipals += @{ Identity = $script:Ids.LegacyObjectId; ObjectId = $script:Ids.LegacyObjectId; AppId = $script:Ids.LegacyAppId; DisplayName = 'email-monitor' }
        $x.Scopes += @{ Name = 'Scope-email-monitor'; RecipientFilter = "PrimarySmtpAddress -eq 'support@contoso.com'" }
        $x.Assignments += @{ Name = 'Assignment-email-monitor-MailRead'; Role = 'Application Mail.Read'; RoleAssigneeName = $script:Ids.LegacyObjectId }
        $x.Assignments += @{ Name = 'Assignment-email-monitor-MailSend'; Role = 'Application Mail.Send'; RoleAssigneeName = $script:Ids.LegacyObjectId }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = (New-MailboxFile -Entries @()); RemoveLegacyGrantAppIds = @($script:Ids.LegacyAppId) }
        $code | Should -Be 0
        Get-SummaryResult "Legacy mailbox grant: $($script:Ids.LegacyAppId)" | Should -Be 'Removed (2 assignment(s))'
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
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = (New-MailboxFile -Entries @()); RemoveLegacyGrantAppIds = @($script:Ids.LegacyAppId) }
        $code | Should -Be 0
        Get-SummaryResult "Legacy mailbox grant: $($script:Ids.LegacyAppId)" | Should -Be 'Removed (1 assignment(s))'
        @($x.Assignments) | Should -HaveCount 1
    }

    It 'reports a retired identity that is not present' {
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = (New-MailboxFile -Entries @()); RemoveLegacyGrantAppIds = @($script:Ids.LegacyAppId) }
        $code | Should -Be 0
        Get-SummaryResult "Legacy mailbox grant: $($script:Ids.LegacyAppId)" | Should -Be 'Not present'
        $script:Writes | Should -HaveCount 0
    }

    It 'keeps the assignment of an identity the file lists as adopted by the v5 email channel' {
        $x = $script:Tenant.Exchange
        $x.ServicePrincipals += @{ Identity = $script:Ids.LegacyObjectId; ObjectId = $script:Ids.LegacyObjectId; AppId = $script:Ids.LegacyAppId; DisplayName = 'email-monitor' }
        $x.Assignments += @{ Name = 'Assignment-email-monitor-MailRead'; Role = 'Application Mail.Read'; RoleAssigneeName = $script:Ids.LegacyObjectId }
        $file = New-MailboxFile -Entries @() -AdoptedIdentityAppIds @($script:Ids.LegacyAppId.ToUpperInvariant())
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = $file; RemoveLegacyGrantAppIds = @($script:Ids.LegacyAppId) }
        $code | Should -Be 0
        Get-SummaryResult "Legacy mailbox grant: $($script:Ids.LegacyAppId)" | Should -Be 'Identity adopted by the v5 email channel - assignment kept'
        ($script:Console -join "`n") | Should -Match 'identity adopted by the v5 email channel - assignment kept'
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
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = $file; RemoveLegacyGrantAppIds = @($script:Ids.LegacyAppId, $otherAppId) }
        $code | Should -Be 0
        Get-SummaryResult "Legacy mailbox grant: $($script:Ids.LegacyAppId)" | Should -Be 'Identity adopted by the v5 email channel - assignment kept'
        Get-SummaryResult "Legacy mailbox grant: $otherAppId" | Should -Be 'Removed (1 assignment(s))'
        @($x.Assignments | Where-Object { $_.RoleAssigneeName -eq $script:Ids.LegacyObjectId }) | Should -HaveCount 1
        @($x.ServicePrincipals | Where-Object { $_.AppId -eq $otherAppId }) | Should -HaveCount 0
        $script:ExchangeDisconnected | Should -BeTrue
    }

    It 'applies the grants of the object-shaped file, with no adopted identity named' {
        $file = New-MailboxFile -AsObject
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = $file }
        $code | Should -Be 0
        Get-SummaryResult 'Mailbox grant: support@contoso.com -> neo-support' | Should -Be 'Granted (3 role(s) added)'
        ($script:Console -join "`n") | Should -Match '1 email channel\(s\), 0 adopted identity'
    }
}

Context 'Graph resilience' {
    BeforeEach {
        Add-CompliantPreWindowState
    }

    It 'retries throttling with the Retry-After delay and succeeds' {
        $script:Faults += @{ Match = 'GET /applications$'; Status = 429; Code = 'TooManyRequests'; Message = 'throttled'; Remaining = 1; Headers = @{ 'Retry-After' = @('3') } }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Sleeps | Should -Contain 3
        Get-SummaryResult 'Agent blueprint' | Should -Be 'Present'
        $script:Writes | Should -HaveCount 0
    }

    It 'retries transient service errors and gives up with a recorded failure' {
        $script:Faults += @{ Match = 'GET /applications/[^/]+/owners$'; Status = 503; Code = 'ServiceUnavailable'; Message = 'try later'; Remaining = 2 }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Blueprint owner' | Should -Be 'Already in place'
        @($script:Sleeps) | Should -HaveCount 2
        $script:Tenant = New-EmptyTenant
        Add-CompliantPreWindowState
        $script:Faults = @(@{ Match = 'GET /applications/[^/]+/owners$'; Status = 500; Code = 'InternalServerError'; Message = 'boom'; Remaining = 99 })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Blueprint owner') | Should -Match '^FAILED - Graph GET /v1.0/applications/.+ returned HTTP 500 \(InternalServerError - boom\)'
        Get-SummaryResult 'Blueprint principal' | Should -Be 'Present'
        Get-SummaryResult 'Admin consent' | Should -Be 'Present'
    }

    It 'retries a not-found right after a create (replication delay)' {
        $script:Tenant.Apps = @()
        $script:Tenant.ServicePrincipals = @($script:Tenant.ServicePrincipals | Where-Object { $_.id -ne $script:Ids.BlueprintSpId })
        $script:Faults += @{ Match = 'GET /applications/[^/]+/owners$'; Status = 404; Code = 'Request_ResourceNotFound'; Message = 'not replicated'; Remaining = 1 }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Agent blueprint' | Should -Be 'Created'
        Get-SummaryResult 'Blueprint owner' | Should -Be 'Already in place'
    }

    It 'does not retry a not-found on a plain read' {
        $script:Faults += @{ Match = 'GET /applications/[^/]+/owners$'; Status = 404; Code = 'Request_ResourceNotFound'; Message = 'gone'; Remaining = 1 }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Blueprint owner') | Should -Match 'HTTP 404'
        @($script:Sleeps) | Should -HaveCount 0
    }

    It 'follows @odata.nextLink so an owner on a later page is seen' {
        $app = Get-FakeApp -Id $script:Ids.BlueprintAppObj
        $principal = Get-FakeSp -Id $script:Ids.BlueprintSpId
        $filler = @(1..5 | ForEach-Object { [guid]::NewGuid().ToString() })
        $app.owners = @($filler) + @($script:Ids.DeploySpId)
        $principal.owners = @($filler) + @($script:Ids.DeploySpId)
        $app.credentials = @(1..7 | ForEach-Object { "other-cred-$_" }) + $app.credentials
        $script:Tenant.PageSize = 2
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Blueprint owner' | Should -Be 'Already in place'
        Get-SummaryResult 'Blueprint principal owner' | Should -Be 'Already in place'
        Get-SummaryResult 'Blueprint credential: github-oidc-neo-env-config' | Should -Be 'Present'
        $script:Writes | Should -HaveCount 0
        @($script:GraphCalls | Where-Object { $_ -match 'GET /applications/[^/]+/owners$' }).Count | Should -BeGreaterThan 1
    }

    It 'treats an "already exists" reply to an owner add as already in place' {
        $app = Get-FakeApp -Id $script:Ids.BlueprintAppObj
        $app.owners = @($script:Ids.Me)
        $script:Faults += @{ Match = 'GET /applications/[^/]+/owners$'; Status = 200; Code = ''; Message = ''; Remaining = 0 }
        Mock Invoke-NeologikGraphRaw {
            param($Method, $Uri, $Body)
            if ($Method -eq 'POST' -and $Uri -match '/owners/\$ref$') {
                return @{ StatusCode = 400; Headers = @{}; Body = @{ error = @{ code = 'Request_BadRequest'; message = 'One or more added object references already exist for the following modified properties' } } }
            }
            Invoke-FakeGraph -Method $Method -Uri $Uri -Body $Body
        }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'Blueprint owner' | Should -Be 'Already in place'
    }

    It 'never lets an unexpected exception escape: the run is recorded and the summary written' {
        Mock Set-NeologikAgentBlueprint { throw 'something nobody anticipated' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        Get-SummaryResult 'Run' | Should -Be 'FAILED - unexpected error: something nobody anticipated'
        @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter '*.json') | Should -HaveCount 1
    }
}

Context 'Pre-window run: permission reduction (step 4)' {
    It 'on an already-hardened environment creates only the Cost Management Contributor grant' {
        Add-CompliantPreWindowState
        $script:Tenant.AzRoleAssignments = @($script:Tenant.AzRoleAssignments | Where-Object { $_.RoleDefinitionName -ne 'Cost Management Contributor' })
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 1
        $script:Writes[0] | Should -Be "NEW az role Cost Management Contributor $script:SubScope"
        Get-SummaryResult 'RG role: Contributor' | Should -Be 'Already in place'
        Get-SummaryResult 'subscription role: Reader' | Should -Be 'Already in place'
        Get-SummaryResult 'subscription role: Cost Management Contributor' | Should -Be 'Created'
        Get-SummaryResult 'Legacy subscription role: Contributor' | Should -Be 'Not present'
        Get-SummaryResult 'Application Administrator role' | Should -Be 'Not held'
        Should -Invoke Connect-AzAccount -Times 1 -ParameterFilter { $Tenant -eq $script:Ids.Tenant -and $Subscription -eq $script:Ids.Subscription -and $UseDeviceAuthentication -and $ClaimsChallenge }
        # Second run: pure verification.
        $script:Writes = @()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
    }

    It 'on a legacy environment applies the narrow set before removing the broad grants' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $news = @($script:Writes | Where-Object { $_ -like 'NEW az role*' })
        $removes = @($script:Writes | Where-Object { $_ -like 'REMOVE*' })
        $news | Should -HaveCount 9
        $removes | Should -HaveCount 3
        [array]::IndexOf($script:Writes, $removes[0]) | Should -BeGreaterThan ([array]::IndexOf($script:Writes, $news[-1]))
        Get-SummaryResult 'Legacy subscription role: Contributor' | Should -Be 'Removed'
        Get-SummaryResult 'Legacy subscription role: User Access Administrator' | Should -Be 'Removed'
        Get-SummaryResult 'Application Administrator role' | Should -Be 'Removed'
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.Scope -eq $script:SubScope }).RoleDefinitionName | Should -Be @('Reader', 'Cost Management Contributor')
        @($script:Tenant.DirectoryRoles)[0].members | Should -HaveCount 0
    }

    It 'does not mistake an inherited subscription role for the resource-group assignment' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'RG role: Contributor' | Should -Be 'Created'
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.RoleDefinitionName -eq 'Contributor' -and $_.Scope -eq $script:RgScope }) | Should -HaveCount 1
    }

    It 'leaves the broad grants in place when a narrow role could not be applied, after the directory checks ran' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        Mock New-AzRoleAssignment { param($RoleDefinitionName) if ($RoleDefinitionName -eq 'Monitoring Contributor') { throw 'AuthorizationFailed: The client does not have authorization to perform action' }; $script:Tenant.AzRoleAssignments += @{ ObjectId = $ObjectId; RoleDefinitionName = $RoleDefinitionName; Scope = $Scope }; Add-Write "NEW az role $RoleDefinitionName $Scope" }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'RG role: Monitoring Contributor') | Should -Match '^FAILED - insufficient privileges'
        Get-SummaryResult 'Legacy subscription role: Contributor' | Should -Be 'SKIPPED - narrow roles not all in place'
        Get-SummaryResult 'Application Administrator role' | Should -Be 'SKIPPED - narrow roles not all in place'
        Should -Invoke Remove-AzRoleAssignment -Times 0
        Should -Invoke Remove-MgDirectoryRoleMemberDirectoryObjectByRef -Times 0
        @($script:Tenant.DirectoryRoles)[0].members | Should -Contain $script:Ids.DeploySpId
        @($script:Tenant.AzRoleAssignments | Where-Object { $_.Scope -eq $script:SubScope -and $_.RoleDefinitionName -eq 'Contributor' }) | Should -HaveCount 1
        Get-SummaryResult 'Agent blueprint' | Should -Be 'Present'
        Get-SummaryResult 'Retired Graph role: Group.Create' | Should -Be 'Not held'
        Get-SummaryResult 'Admin consent' | Should -Be 'Present'
    }

    It 'treats a RoleAssignmentExists race as already in place' {
        Add-CompliantPreWindowState
        $script:Tenant.AzRoleAssignments = @($script:Tenant.AzRoleAssignments | Where-Object { $_.RoleDefinitionName -ne 'Reader' })
        Mock New-AzRoleAssignment { throw 'RoleAssignmentExists: The role assignment already exists.' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        Get-SummaryResult 'subscription role: Reader' | Should -Be 'Already in place'
    }

    It 'stops with ACTION REQUIRED when the Azure sign-in fails, touching nothing' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        Mock Connect-AzAccount { throw 'Device code expired' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'Owner \(or User Access Administrator\)'
        Get-SummaryResult 'RG role: Contributor' | Should -Be 'SKIPPED - Azure sign-in failed'
        Get-SummaryResult 'Application Administrator role' | Should -Be 'SKIPPED - narrow Azure roles not confirmed'
        $script:Writes | Should -HaveCount 0
    }

    It 'stops when the Azure session selected another subscription' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        $script:AzContextSubscription = [guid]::NewGuid().ToString()
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'selected subscription'
        $script:Writes | Should -HaveCount 0
    }

    It 'installs the Az modules when absent' {
        Add-CompliantPreWindowState
        Mock Get-NeologikAvailableModuleVersion { param($Name) if ($Name -like 'Az.*' -and $script:Installs -notcontains $Name) { @() } else { @([version]'5.5.0') } }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 0
        $script:Installs | Should -Contain 'Az.Accounts'
        $script:Installs | Should -Contain 'Az.Resources'
    }

    It 'reports the directory role removal as failed when Graph refuses it' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        Mock Remove-MgDirectoryRoleMemberDirectoryObjectByRef { throw (New-ForbiddenException) }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Application Administrator role') | Should -Match '^FAILED - insufficient privileges'
        Get-SummaryResult 'Legacy subscription role: Contributor' | Should -Be 'Removed'
    }

    It 'reads the directory role without a filter so a read error is never mistaken for not held' {
        Add-CompliantDirectoryState
        Add-LegacyAzureState
        Mock Get-MgDirectoryRole { throw (New-ForbiddenException) }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile) }
        $code | Should -Be 1
        (Get-SummaryResult 'Application Administrator role') | Should -Match '^FAILED'
    }

    It 'accepts explicit parameters instead of a configuration file' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ TenantId = $script:Ids.Tenant; DeploySpClientId = $script:Ids.DeployAppId; SignInAppClientId = $script:Ids.SignInAppId; NceUserGroupId = $script:Ids.Group; SubscriptionId = $script:Ids.Subscription; ResourceGroupName = $script:RgName }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
    }
}

Context 'Verify-only run (-Verify)' {
    It 'reports every pending change on a legacy environment, writes nothing and exits 1' {
        Add-FakeAppRole -SpId $script:Ids.DeploySpId -RoleName 'Application.Read.All'
        Add-LegacyAzureState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 1
        $script:Writes | Should -HaveCount 0
        @($script:Tenant.Apps) | Should -HaveCount 0
        (Get-SummaryResult 'Agent blueprint') | Should -BeLike 'WOULD CREATE*'
        Get-SummaryResult 'Blueprint principal' | Should -Be 'WOULD CREATE'
        Get-SummaryResult 'Blueprint credential: github-oidc-neo-infrastructure' | Should -Be 'WOULD ADD'
        Get-SummaryResult 'Graph role: Application.ReadWrite.OwnedBy' | Should -Be 'WOULD GRANT'
        Get-SummaryResult 'Retired Graph role: Application.Read.All' | Should -Be 'WOULD REMOVE'
        Get-SummaryResult 'NCE group assignment' | Should -Be 'WOULD ASSIGN'
        Get-SummaryResult 'Admin consent' | Should -Be 'MISSING - consent URL printed'
        Get-SummaryResult 'RG role: Contributor' | Should -Be 'WOULD CREATE'
        Get-SummaryResult 'subscription role: Cost Management Contributor' | Should -Be 'WOULD CREATE'
        Get-SummaryResult 'Legacy subscription role: Contributor' | Should -Be 'WOULD REMOVE'
        Get-SummaryResult 'Application Administrator role' | Should -Be 'WOULD REMOVE'
        @($script:Summary | Where-Object { $_.Result -match '^(FAILED|SKIPPED)' }) | Should -HaveCount 0
        ($script:Console -join "`n") | Should -Match 'verify-only'
        ($script:Console -join "`n") | Should -Match 'nothing was written'
        $files = @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter 'Neologik_EnvironmentAccess_PreWindow_*.json')
        $files | Should -HaveCount 1
        $json = Get-Content -LiteralPath $files[0].FullName -Raw | ConvertFrom-Json
        $json.verifyOnly | Should -BeTrue
        $json.pendingChangeCount | Should -BeGreaterThan 10
        (Get-FakeSp -Id $script:Ids.DeploySpId).appRoleAssignments | Should -HaveCount 1
        @($script:Tenant.DirectoryRoles)[0].members | Should -Contain $script:Ids.DeploySpId
        Should -Invoke Connect-MgGraph -Times 1
        Should -Invoke Connect-AzAccount -Times 1
    }

    It 'is a clean pass on a compliant environment: exit 0, nothing pending' {
        Add-CompliantPreWindowState
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); Verify = $true }
        $code | Should -Be 0
        $script:Writes | Should -HaveCount 0
        ($script:Console -join "`n") | Should -Match 'nothing would change'
    }

    It 'reports pending agent-user and mailbox grants in the post-window run without writing' {
        Add-AgentIdentities -NoGrants
        $x = $script:Tenant.Exchange
        $x.ServicePrincipals += @{ Identity = $script:Ids.LegacyObjectId; ObjectId = $script:Ids.LegacyObjectId; AppId = $script:Ids.LegacyAppId; DisplayName = 'email-monitor' }
        $x.Assignments += @{ Name = 'Assignment-email-monitor-MailRead'; Role = 'Application Mail.Read'; RoleAssigneeName = $script:Ids.LegacyObjectId }
        $grants = New-GrantsFile -Grants @((New-AgentGrantEntry -Scopes @('User.Read', 'Mail.Read')))
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); AgentGrantsFile = $grants; MailboxGrantsFile = (New-MailboxFile); RemoveLegacyGrantAppIds = @($script:Ids.LegacyAppId); Verify = $true }
        $code | Should -Be 1
        $script:Writes | Should -HaveCount 0
        Get-SummaryResult 'Agent-user grant: agent Support Agent' | Should -Be 'WOULD GRANT (Mail.Read User.Read)'
        (Get-SummaryResult 'Mailbox grant: support@contoso.com -> neo-support') | Should -BeLike 'WOULD GRANT (service principal pointer, management scope Scope-neo-support, assignment*'
        Get-SummaryResult "Legacy mailbox grant: $($script:Ids.LegacyAppId)" | Should -Be 'WOULD REMOVE (1 assignment(s) and the pointer)'
        @((Get-FakeSp -Id $script:Ids.AgentIdentitySp).grants) | Should -HaveCount 0
        @($x.Assignments) | Should -HaveCount 1
        @($x.ServicePrincipals) | Should -HaveCount 1
        $script:ExchangeDisconnected | Should -BeTrue
    }

    It 'the write seams refuse every write in a verify-only run, whatever the caller does' {
        $script:State = @{ Verify = $true }
        { Invoke-NeologikGraph -Method POST -Uri "$script:GraphV1/oauth2PermissionGrants" -Body '{}' } | Should -Throw -ExpectedMessage '*verify-only run*'
        { Invoke-NeologikWrite -Command 'New-AzRoleAssignment' -Parameters @{ ObjectId = 'x'; RoleDefinitionName = 'Reader'; Scope = '/subscriptions/x' } } | Should -Throw -ExpectedMessage '*verify-only run*'
        $script:GraphCalls | Should -HaveCount 0
        $script:Writes | Should -HaveCount 0
        Should -Invoke New-AzRoleAssignment -Times 0
        # A read passes.
        $null = Invoke-NeologikGraph -Method GET -Uri "$script:GraphV1/me"
        $script:GraphCalls | Should -Contain 'GET /me'
        # Without -Verify the seam performs the write.
        $script:State = @{ Verify = $false }
        Invoke-NeologikWrite -Command 'New-AzRoleAssignment' -Parameters @{ ObjectId = 'x'; RoleDefinitionName = 'Reader'; Scope = '/subscriptions/x' }
        $script:Writes | Should -HaveCount 1
    }
}

Context 'Parameter surface' {
    It 'has no -Phase parameter: the files given select the run' {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors) | Should -HaveCount 0
        $names = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
        $names | Should -Not -Contain 'Phase'
        $names | Should -Contain 'Verify'
        $names | Should -Contain 'AgentGrantsFile'
        $names | Should -Contain 'MailboxGrantsFile'
        { Invoke-NeologikEnvironmentAccess -ConfigurationFile (New-ConfigFile) -Phase 'PostWindow' } | Should -Throw -ExpectedMessage "*'Phase'*"
        Should -Invoke Connect-MgGraph -Times 0
    }
}

Context 'Summary and exit code' {
    It 'flags FAILED, UNKNOWN, MISSING, SKIPPED, PENDING, NOT FOUND and WOULD as attention' {
        foreach ($result in @('FAILED - x', 'UNKNOWN - x', 'MISSING - x', 'SKIPPED - x', 'PENDING - x', 'NOT FOUND - x', 'WOULD GRANT', 'WOULD REMOVE (2 assignment(s))')) {
            $result | Should -Match $script:AttentionPattern
        }
        foreach ($result in @('Present', 'Created', 'Already granted', 'Granted (User.Read)', 'Removed', 'Not held', 'Not present', 'Not needed', 'Updated (a b)',
                'Not checked - runs with the agent grants file', 'Identity adopted by the v5 email channel - assignment kept')) {
            $result | Should -Not -Match $script:AttentionPattern
        }
    }

    It 'returns 1 and keeps going when the summary roles cannot be read' {
        Add-CompliantPreWindowState
        $script:Tenant.Exchange.InScope = $false
        Mock Get-NeologikHeldGraphRole { throw 'read failed' }
        $code = Invoke-Run @{ ConfigurationFile = (New-ConfigFile); MailboxGrantsFile = (New-MailboxFile) }
        $code | Should -Be 1
        ($script:Console -join "`n") | Should -Match 'could not be read for the summary'
        @(Get-ChildItem -Path (Join-Path $TestDrive 'summary') -Filter '*.json') | Should -HaveCount 1
    }
}

}
