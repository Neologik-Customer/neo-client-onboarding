#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Static checks on Install-NeologikEnvironment.ps1: every Neologik function
    the script calls is defined in the script, so that a run cannot stop at a
    call to a function that does not exist.

    Run: pwsh -NoProfile -Command "Invoke-Pester -Path tests -CI"
#>

Describe 'Install-NeologikEnvironment.ps1 (static)' {

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Install-NeologikEnvironment.ps1'
    $tokens = $null; $errors = $null
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$tokens, [ref]$errors)
    $script:ParseErrors = @($errors)
    $script:Defined = @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
    $script:Called = @($script:Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
        ForEach-Object { $_.GetCommandName() } | Where-Object { $_ -like '*-Neologik*' } | Sort-Object -Unique)
}

It 'parses without errors' {
    $script:ParseErrors.Count | Should -Be 0
}

It 'defines every Neologik function it calls' {
    $missing = @($script:Called | Where-Object { $script:Defined -notcontains $_ })
    $missing | Should -BeNullOrEmpty -Because "a called function must exist in the script: $($missing -join ', ')"
}

It 'selects the subscription named by -SubscriptionName on a fresh run' {
    # a supplied name is resolved and set as the context; the
    # login context is the fallback only when the parameter is absent.
    $text = Get-Content -Raw $script:ScriptPath
    $text | Should -Match ([regex]::Escape('[string]::IsNullOrWhiteSpace($SubscriptionName)'))
    $text | Should -Match ([regex]::Escape('Get-AzSubscription -SubscriptionName $SubscriptionName'))
    $text | Should -Not -Match ([regex]::Escape('$SubscriptionName = "Neologik-Development-01"'))
}

It 'creates the Platform Sign-in registration' {
    $script:Defined | Should -Contain 'New-NeologikNceAuthApp'
    $script:Called | Should -Contain 'New-NeologikNceAuthApp'
}

It 'records the kit version on the resource group, at the version the version history opens with' {
    $script:Defined | Should -Contain 'Set-NeologikKitVersionTag'
    $script:Called | Should -Contain 'Set-NeologikKitVersionTag'
    $text = Get-Content -Raw $script:ScriptPath
    $text | Should -Match ([regex]::Escape('Update-AzTag -ResourceId $ResourceId -Tag @{ NeologikOnboardingKit = $script:KitVersion } -Operation Merge'))
    $history = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'docs' 'VERSION_HISTORY.md')
    $top = [regex]::Match($history, '(?m)^## Version (\d+\.\d+\.\d+)').Groups[1].Value
    $text | Should -Match ([regex]::Escape("`$script:KitVersion = 'v$top'"))
}

It 'adds no federated credential to the deployment identity' {
    $script:Defined | Should -Not -Contain 'Set-NeologikDeploymentCredential'
    $text = Get-Content -Raw $script:ScriptPath
    $text | Should -Not -Match 'github-deployments-'
    $text | Should -Not -Match ([regex]::Escape(":environment:"))
}

It 'records this version of the onboarding kit only after the steps of this version' {
    $text = Get-Content -Raw $script:ScriptPath
    $text | Should -Match ([regex]::Escape('Update-AzTag -ResourceId $rg.ResourceId -Tag @{ NeologikOnboardingKit = $earlierKitVersion } -Operation Merge'))
    $finalWrite = $text.IndexOf('Set-NeologikKitVersionTag -ResourceId "/subscriptions/')
    $finalWrite | Should -BeGreaterThan $text.IndexOf('$null = New-NeologikManagedIdentities')
}

It 'ships an example answer file that names the agent registration identity and no environment name' {
    $json = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'inputs-example.json') | ConvertFrom-Json
    $json.PSObject.Properties.Name | Should -Contain 'directoryIdentityName'
    $json.PSObject.Properties.Name | Should -Not -Contain 'environmentName'
}

It 'creates the agent registration identity with one Microsoft Graph permission and no Azure role' {
    $text = Get-Content -Raw $script:ScriptPath
    $text | Should -Match 'Name = \$directoryIdentityName'
    $text | Should -Match "GraphAppRoles = @\('Application\.ReadWrite\.OwnedBy'\)\s+\}"
    $text | Should -Match 'neologik-directory-managed-identity\$nameSuffix'
    $text | Should -Not -Match 'AgentRegistration\.ReadWrite\.All'
}

It 'asks for the name of the agent registration identity and passes the name to step 15' {
    $text = Get-Content -Raw $script:ScriptPath
    ([regex]::Matches($text, [regex]::Escape("Get-Answer 'directoryIdentityName'"))).Count | Should -Be 2 -Because 'the answer file run and the run with questions both read the answer'
    $text | Should -Match ([regex]::Escape("Read-NameWithDefault -Title 'Agent Registration Identity Name'"))
    $text | Should -Match ([regex]::Escape("-DirectoryIdentityName ([string]`$script:ConfigData['DirectoryIdentityName'])"))
    $text | Should -Not -Match ([regex]::Escape("Get-Answer 'environmentName'"))
}

It 'creates the system task managed identity with the limited role on the resource group' {
    $text = Get-Content -Raw $script:ScriptPath
    $text | Should -Match 'Name = \$systemTaskIdentityName'
    $text | Should -Match 'ResourceGroupRoleStandard = \$true'
    $text | Should -Match 'neologik-system-task-managed-identity'
}

It 'stops the system task managed identity assigning the three administrator roles, and limits other assignments to service principals' {
    $text = Get-Content -Raw $script:ScriptPath
    $text | Should -Match 'ForAnyOfAllValues:GuidNotEquals'
    $text | Should -Match "PrincipalType\] ForAnyOfAnyValues:StringEqualsIgnoreCase \{\{'ServicePrincipal'\}\}"
    $text | Should -Not -Match 'fbc52c3f-28ad-4303-a892-8a056630b8f1'
    @([regex]::Matches($text, '-Condition \$script:ResourceGroupRoleCondition')).Count | Should -Be 1 -Because 'only the system task managed identity holds the limited role on the resource group'
}

It 'gives the deployment identity Role Based Access Control Administrator on the resource group without a condition' {
    $text = Get-Content -Raw $script:ScriptPath
    $text | Should -Match ([regex]::Escape("`$rgRoles = @('Contributor', 'Key Vault Certificates Officer', 'Key Vault Secrets Officer', 'Storage Blob Data Contributor', 'Azure Kubernetes Service RBAC Cluster Admin', 'Monitoring Contributor', 'Role Based Access Control Administrator')"))
    $text | Should -Not -Match ([regex]::Escape('Scope = $rgScope; Condition = $script:ResourceGroupRoleCondition'))
}

It 'limits the role on the subscription to Reader and Cost Management Reader, for service principals only' {
    $text = Get-Content -Raw $script:ScriptPath
    $text | Should -Match "'acdd72a7-3385-48ef-bd42-f606fba81ae7',\s+'72fafb9e-0641-4937-9268-a91bfd8191a3'\s+\)"
    $text | Should -Match "@Request\[Microsoft\.Authorization/roleAssignments:PrincipalType\] ForAnyOfAnyValues:StringEqualsIgnoreCase \{\{'ServicePrincipal'\}\}"
    $text | Should -Match "@Resource\[Microsoft\.Authorization/roleAssignments:PrincipalType\] ForAnyOfAnyValues:StringEqualsIgnoreCase \{\{'ServicePrincipal'\}\}"
    $text | Should -Not -Match 'fbc52c3f-28ad-4303-a892-8a056630b8f1'
}

It 'asks no question about a cost report' {
    $text = Get-Content -Raw $script:ScriptPath
    $text | Should -Not -Match 'budgetCostReportEmailRecipients|BudgetEmailAddresses|Cost-Report'
}

It 'ships an example answer file that parses and names no cost report recipient' {
    $json = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'inputs-example.json') | ConvertFrom-Json
    $json.PSObject.Properties.Name | Should -Not -Contain 'budgetCostReportEmailRecipients'
}

}
