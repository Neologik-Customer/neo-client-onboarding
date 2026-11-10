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

It 'adds the federated credential of the deployment identity for this environment only' {
    $script:Defined | Should -Contain 'Set-NeologikDeploymentCredential'
    $script:Called | Should -Contain 'Set-NeologikDeploymentCredential'
    $text = Get-Content -Raw $script:ScriptPath
    $text | Should -Match ([regex]::Escape("claims['sub'] matches 'repo:Neologik-AI*:environment:`$EnvironmentName' and claims['repository_owner_id'] eq '109681438'"))
}

It 'records this version of the onboarding kit only after the steps of this version' {
    $text = Get-Content -Raw $script:ScriptPath
    $text | Should -Match ([regex]::Escape('Update-AzTag -ResourceId $rg.ResourceId -Tag @{ NeologikOnboardingKit = $earlierKitVersion } -Operation Merge'))
    $finalWrite = $text.IndexOf('Set-NeologikKitVersionTag -ResourceId "/subscriptions/')
    $finalWrite | Should -BeGreaterThan $text.IndexOf('$null = New-NeologikManagedIdentities')
    $finalWrite | Should -BeGreaterThan $text.IndexOf('$null = Set-NeologikDeploymentCredential')
}

It 'ships an example answer file that names the environment name' {
    $json = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'inputs-example.json') | ConvertFrom-Json
    $json.PSObject.Properties.Name | Should -Contain 'environmentName'
}

It 'creates the directory managed identity with one Microsoft Graph permission and no Azure role' {
    $text = Get-Content -Raw $script:ScriptPath
    $text | Should -Match 'Name = \$directoryIdentityName'
    $text | Should -Match "GraphAppRoles = @\('Application\.ReadWrite\.OwnedBy'\)\s+\}"
    $text | Should -Match 'neologik-directory-managed-identity\$nameSuffix'
}

It 'creates the system task managed identity with the limited role on the resource group' {
    $text = Get-Content -Raw $script:ScriptPath
    $text | Should -Match 'Name = \$systemTaskIdentityName'
    $text | Should -Match 'ResourceGroupRoleStandard = \$true'
    $text | Should -Match 'neologik-system-task-managed-identity'
}

It 'stops both identities assigning the three administrator roles, and limits other assignments to service principals' {
    $text = Get-Content -Raw $script:ScriptPath
    $text | Should -Match 'ForAnyOfAllValues:GuidNotEquals'
    $text | Should -Match "PrincipalType\] ForAnyOfAnyValues:StringEqualsIgnoreCase \{\{'ServicePrincipal'\}\}"
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
