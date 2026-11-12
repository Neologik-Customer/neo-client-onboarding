#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Tests of the configuration file that Install-NeologikEnvironment.ps1 writes
    for Neologik. The configuration file records the version of the onboarding
    kit next to the version of the onboarding script.

    Run: pwsh -NoProfile -Command "Invoke-Pester -Path tests -CI"
#>

Describe 'Install-NeologikEnvironment.ps1 (configuration file)' {

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Install-NeologikEnvironment.ps1'

    # The script under test: dot-sourced, so its functions are defined here and its guarded main entry does not run.
    . $script:ScriptPath

    Mock Write-Log { }
    Mock Write-Host { }
}

BeforeEach {
    # No storage account, so the function uploads nothing.
    $script:ConfigData = @{ TenantId = '9c1f43a2-0000-4000-8000-000000000001' }
    $script:OutputFile = Join-Path $TestDrive 'Neologik_abc01_Configuration_20261112_120000.json'
}

It 'records the version of the onboarding kit in the field KitVersion' {
    Export-ConfigurationData
    $config = Get-Content -Raw $script:OutputFile | ConvertFrom-Json
    $config.KitVersion | Should -Be $script:KitVersion
    $config.KitVersion | Should -Match '^v\d+\.\d+\.\d+$'
}

It 'keeps the field ScriptVersion first and writes the field KitVersion next to it' {
    Export-ConfigurationData
    $config = Get-Content -Raw $script:OutputFile | ConvertFrom-Json
    $config.ScriptVersion | Should -Be $script:Version
    $names = @($config.PSObject.Properties.Name)
    $names[0] | Should -Be 'ScriptVersion'
    $names[1] | Should -Be 'KitVersion'
}

}
