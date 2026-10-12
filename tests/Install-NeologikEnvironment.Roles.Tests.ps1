#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Tests of the role assignment checks of Install-NeologikEnvironment.ps1.

    Azure answers a read at a scope with the assignment at that scope and
    every assignment inherited from a parent scope. The script must count an
    assignment only at the scope it asked for, with the condition it expects,
    and must record only the roles it read back. The in-memory tenant below
    answers every read and records every write.

    Run: pwsh -NoProfile -Command "Invoke-Pester -Path tests -CI"
#>

Describe 'Install-NeologikEnvironment.ps1 (role assignments)' {

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Install-NeologikEnvironment.ps1'

    # Stubs for the Az cmdlets the checks call: a command must exist before Pester can mock it.
    function Get-AzRoleAssignment { [CmdletBinding()] param($ObjectId, $RoleDefinitionName, $Scope, $SignInName) }
    function New-AzRoleAssignment { [CmdletBinding()] param($ObjectId, $RoleDefinitionName, $RoleDefinitionId, $Scope, $Condition, $ConditionVersion) }
    function Set-AzRoleAssignment { [CmdletBinding()] param($InputObject, [switch]$PassThru) }
    if (-not (Get-Command Grant-GraphAppRolePermissions -ErrorAction SilentlyContinue)) {
        function Grant-GraphAppRolePermissions { [CmdletBinding()] param($PrincipalId, $PrincipalDescription, $AppRoles) }
    }

    # The script under test: dot-sourced, so its functions are defined here and its guarded main entry does not run.
    . $script:ScriptPath

    $script:Sp = '31c6287e-0000-4000-8000-000000000001'
    $script:SubScope = '/subscriptions/810ff294-0000-4000-8000-000000000002'
    $script:RgScope = "$($script:SubScope)/resourceGroups/rg-neo-abcprd-uks-01"
    $script:SubRoles = @('Reader', 'Cost Management Contributor')
    $script:Groups = @(@{ Name = 'Neologik Admin User Group - abcprd01'; Id = 'bc238432-0000-4000-8000-000000000003' })
    $script:RgRoles = @('Contributor', 'Key Vault Certificates Officer', 'Key Vault Secrets Officer', 'Storage Blob Data Contributor', 'Azure Kubernetes Service RBAC Cluster Admin', 'Monitoring Contributor', 'Role Based Access Control Administrator')

    function New-Assignment([string]$Role, [string]$Scope, [string]$Condition = '') {
        @{ ObjectId = $script:Sp; RoleDefinitionName = $Role; Scope = $Scope; Condition = $Condition }
    }

    Mock Write-Log { }
    Mock Write-Host { }
    Mock Start-Sleep { }
    Mock Grant-GraphAppRolePermissions { }
    Mock Get-AzRoleAssignment {
        param($ObjectId, $RoleDefinitionName, $Scope)
        # Azure returns the assignment at the scope and every assignment inherited from a parent scope.
        @($script:Assignments | Where-Object {
                $_.ObjectId -eq $ObjectId -and
                ((-not $RoleDefinitionName) -or $_.RoleDefinitionName -eq $RoleDefinitionName) -and
                ((-not $Scope) -or $Scope.StartsWith($_.Scope, [System.StringComparison]::OrdinalIgnoreCase))
            } | ForEach-Object { [pscustomobject]$_ })
    }
    Mock New-AzRoleAssignment {
        param($ObjectId, $RoleDefinitionName, $RoleDefinitionId, $Scope, $Condition, $ConditionVersion)
        if (-not $RoleDefinitionName -and $RoleDefinitionId -eq $script:LimitedSubRoleId) { $RoleDefinitionName = $script:LimitedSubRole }
        if (-not $script:DropWrites) {
            $script:Assignments += New-Assignment -Role $RoleDefinitionName -Scope $Scope -Condition ([string]$Condition)
        }
        $script:Writes += "NEW $RoleDefinitionName $Scope$(if ($Condition) { ' limited' })"
    }
    Mock Set-AzRoleAssignment {
        param($InputObject)
        $script:Writes += "LIMIT $($InputObject.RoleDefinitionName) $($InputObject.Scope)"
    }
}

BeforeEach {
    $script:Assignments = @()
    $script:Writes = @()
    $script:DropWrites = $false
    $script:ConfigData = @{ AppRegistration = @{ Name = 'Neologik GitHub Service Connection - abcprd01' } }
}

Context 'Test-NeologikRoleAssigned' {

    It 'does not count an assignment inherited from the subscription' {
        $script:Assignments = @(New-Assignment -Role 'Role Based Access Control Administrator' -Scope $script:SubScope -Condition $script:LimitedSubRoleCondition)
        Test-NeologikRoleAssigned -ObjectId $script:Sp -RoleName 'Role Based Access Control Administrator' -Scope $script:RgScope | Should -BeFalse
    }

    It 'counts an assignment at the scope asked for' {
        $script:Assignments = @(New-Assignment -Role 'Contributor' -Scope $script:RgScope)
        Test-NeologikRoleAssigned -ObjectId $script:Sp -RoleName 'Contributor' -Scope $script:RgScope | Should -BeTrue
    }

    It 'does not count a limited assignment when no condition is asked for' {
        $script:Assignments = @(New-Assignment -Role 'Role Based Access Control Administrator' -Scope $script:RgScope -Condition $script:LimitedSubRoleCondition)
        Test-NeologikRoleAssigned -ObjectId $script:Sp -RoleName 'Role Based Access Control Administrator' -Scope $script:RgScope | Should -BeFalse
    }

    It 'counts a limited assignment when its condition is asked for, whatever the spacing' {
        $script:Assignments = @(New-Assignment -Role 'Role Based Access Control Administrator' -Scope $script:SubScope -Condition ($script:LimitedSubRoleCondition -replace ' ', '  '))
        Test-NeologikRoleAssigned -ObjectId $script:Sp -RoleName 'Role Based Access Control Administrator' -Scope $script:SubScope -Condition $script:LimitedSubRoleCondition | Should -BeTrue
    }

    It 'answers false, not an error, when the read is refused and the caller continues silently' {
        # Az raises a non-terminating error, which the caller's -ErrorAction decides.
        Mock Get-AzRoleAssignment { Write-Error 'AuthorizationFailed' }
        Test-NeologikRoleAssigned -ObjectId $script:Sp -RoleName 'Contributor' -Scope $script:RgScope -ErrorAction SilentlyContinue | Should -BeFalse
    }
}

Context 'Set-AppRegistrationRoles' {

    It 'assigns Role Based Access Control Administrator on the resource group although the limited subscription role already exists' {
        # The state the limited subscription role leaves behind: the two subscription roles, the limited role, nothing on the resource group.
        $script:Assignments = @(
            (New-Assignment -Role 'Reader' -Scope $script:SubScope),
            (New-Assignment -Role 'Cost Management Contributor' -Scope $script:SubScope),
            (New-Assignment -Role 'Role Based Access Control Administrator' -Scope $script:SubScope -Condition $script:LimitedSubRoleCondition)
        )
        Set-AppRegistrationRoles -ServicePrincipalId $script:Sp -SubscriptionId '810ff294-0000-4000-8000-000000000002' -ResourceGroupName 'rg-neo-abcprd-uks-01' -SecurityGroups $script:Groups | Should -BeTrue
        $script:Writes | Should -Contain "NEW Role Based Access Control Administrator $($script:RgScope)"
        foreach ($role in $script:RgRoles) { $script:Writes | Should -Contain "NEW $role $($script:RgScope)" }
        @($script:Writes).Count | Should -Be $script:RgRoles.Count -Because 'the subscription roles were already held, so only the resource group roles are written'
    }

    It 'records only the roles it read back, and the time of the read' {
        Set-AppRegistrationRoles -ServicePrincipalId $script:Sp -SubscriptionId '810ff294-0000-4000-8000-000000000002' -ResourceGroupName 'rg-neo-abcprd-uks-01' -SecurityGroups $script:Groups | Should -BeTrue
        $record = $script:ConfigData['AppRegistration']
        @($record.SubscriptionRoles) | Should -Be @('Reader', 'Cost Management Contributor', 'Role Based Access Control Administrator')
        @($record.RGRoles) | Should -Be $script:RgRoles
        $record.RolesConfirmedAt | Should -Not -BeNullOrEmpty
    }

    It 'writes nothing on a subscription that already holds every role' {
        $script:Assignments = @(
            (New-Assignment -Role 'Reader' -Scope $script:SubScope),
            (New-Assignment -Role 'Cost Management Contributor' -Scope $script:SubScope),
            (New-Assignment -Role 'Role Based Access Control Administrator' -Scope $script:SubScope -Condition $script:LimitedSubRoleCondition)
        ) + @($script:RgRoles | ForEach-Object { New-Assignment -Role $_ -Scope $script:RgScope })
        Set-AppRegistrationRoles -ServicePrincipalId $script:Sp -SubscriptionId '810ff294-0000-4000-8000-000000000002' -ResourceGroupName 'rg-neo-abcprd-uks-01' -SecurityGroups $script:Groups | Should -BeTrue
        $script:Writes | Should -BeNullOrEmpty
    }

    It 'stops the run and names the role and the scope when a role is still missing after the read-back' {
        $script:DropWrites = $true
        { Set-AppRegistrationRoles -ServicePrincipalId $script:Sp -SubscriptionId '810ff294-0000-4000-8000-000000000002' -ResourceGroupName 'rg-neo-abcprd-uks-01' -SecurityGroups $script:Groups } |
            Should -Throw -ExpectedMessage "*Role Based Access Control Administrator on $($script:RgScope)*"
        $script:ConfigData['AppRegistration'].RolesConfirmedAt | Should -BeNullOrEmpty
        @($script:ConfigData['AppRegistration'].RGRoles) | Should -BeNullOrEmpty
    }
}

}
