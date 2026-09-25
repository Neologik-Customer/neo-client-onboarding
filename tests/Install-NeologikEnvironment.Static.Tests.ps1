#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Static checks on Install-NeologikEnvironment.ps1: every Neologik function
    the script calls is defined in the script. A refactor once removed
    New-NeologikNceAuthApp and left its call behind, so every fresh
    onboarding failed at the Platform Sign-in registration step
    (https://github.com/Neologik-AI/project/issues/2528).

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
    # project#2579: a supplied name is resolved and set as the context; the
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

}
