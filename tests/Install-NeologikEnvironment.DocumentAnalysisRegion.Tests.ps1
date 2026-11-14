#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Tests of the Azure region for document analysis in Install-NeologikEnvironment.ps1.

    The onboarding script asks for the region after the Azure region. The question
    offers the Azure region of the environment when that region offers document
    analysis, and accepts only a region from the list. A run from the answer file
    reads the answer documentAnalysisRegion. The configuration file records the
    region in the field ContentUnderstandingRegion.

    Run: pwsh -NoProfile -Command "Invoke-Pester -Path tests -CI"
#>

Describe 'Install-NeologikEnvironment.ps1 (Azure region for document analysis)' {

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Install-NeologikEnvironment.ps1'

    # The script under test: dot-sourced, so its functions are defined here and its guarded main entry does not run.
    . $script:ScriptPath

    Mock Write-Log { }
    Mock Write-Host { }
}

BeforeEach {
    $script:ConfigData = @{ TenantId = '9c1f43a2-0000-4000-8000-000000000001' }
    $script:Answers = @{}
}

Context 'The list of regions' {

    It 'holds the twelve regions that Microsoft lists for document analysis' {
        $script:DocumentAnalysisRegions | Should -Be @('australiaeast', 'canadacentral', 'eastus', 'eastus2', 'japaneast', 'southcentralus', 'southeastasia', 'swedencentral', 'uksouth', 'westeurope', 'westus', 'westus3')
    }
}

Context 'The default' {

    It 'offers the Azure region of the environment when that region is on the list' {
        Get-NeologikDocumentAnalysisRegionDefault -AzureRegion 'SwedenCentral' | Should -Be 'swedencentral'
    }

    It 'offers no region when the Azure region of the environment is not on the list' {
        Get-NeologikDocumentAnalysisRegionDefault -AzureRegion 'switzerlandnorth' | Should -BeNullOrEmpty
    }

    It 'accepts the Azure region of the environment when the administrator presses Enter' {
        Mock Read-Host { '' }
        Read-NeologikDocumentAnalysisRegion -AzureRegion 'uksouth' | Should -Be 'uksouth'
        Should -Invoke Read-Host -Times 1 -Exactly
    }

    It 'requires a region from the list when the Azure region of the environment is not on the list' {
        $script:Typed = [System.Collections.Generic.Queue[string]]::new([string[]]@('', 'westeurope'))
        Mock Read-Host { $script:Typed.Dequeue() }
        Read-NeologikDocumentAnalysisRegion -AzureRegion 'switzerlandnorth' | Should -Be 'westeurope'
        Should -Invoke Read-Host -Times 2 -Exactly
    }
}

Context 'The validation' {

    It 'accepts each region on the list, in any case' {
        foreach ($region in $script:DocumentAnalysisRegions) { Test-NeologikDocumentAnalysisRegionError $region.ToUpper() | Should -BeNullOrEmpty }
    }

    It 'refuses a region that is not on the list, and names the regions on the list' {
        Test-NeologikDocumentAnalysisRegionError 'switzerlandnorth' | Should -Match 'westeurope'
        Test-NeologikDocumentAnalysisRegionError 'ukwest' | Should -Not -BeNullOrEmpty
    }

    It 'asks again until the typed region is on the list' {
        $script:Typed = [System.Collections.Generic.Queue[string]]::new([string[]]@('ukwest', 'UK South', 'WestEurope'))
        Mock Read-Host { $script:Typed.Dequeue() }
        Read-NeologikDocumentAnalysisRegion -AzureRegion 'uksouth' | Should -Be 'westeurope'
        Should -Invoke Read-Host -Times 3 -Exactly
    }
}

Context 'The answer file' {

    BeforeEach {
        $script:Answers = @{ organizationCode = 'abc'; organizationName = 'Contoso Ltd'; fqdn = 'neologik.contoso.com'; environmentType = 'prd' }
    }

    It 'takes the answer documentAnalysisRegion' {
        $script:Answers['azureRegion'] = 'switzerlandnorth'
        $script:Answers['documentAnalysisRegion'] = 'westeurope'
        $null = Set-ConfigFromAnswerFile
        $script:ConfigData['ContentUnderstandingRegion'] | Should -Be 'westeurope'
    }

    It 'uses the Azure region of the environment when the answer file holds no region for document analysis' {
        $script:Answers['azureRegion'] = 'uksouth'
        $null = Set-ConfigFromAnswerFile
        $script:ConfigData['ContentUnderstandingRegion'] | Should -Be 'uksouth'
    }

    It 'stops when the answer file holds no region for document analysis and the Azure region is not on the list' {
        $script:Answers['azureRegion'] = 'switzerlandnorth'
        { Set-ConfigFromAnswerFile } | Should -Throw -ExpectedMessage '*documentAnalysisRegion is required*'
    }

    It 'stops when the answer is not on the list' {
        $script:Answers['azureRegion'] = 'uksouth'
        $script:Answers['documentAnalysisRegion'] = 'ukwest'
        { Set-ConfigFromAnswerFile } | Should -Throw -ExpectedMessage "*documentAnalysisRegion 'ukwest'*"
    }

    It 'shows the answer as the region of the question in a run with questions' {
        Mock Read-Host { '' }
        Read-NeologikDocumentAnalysisRegion -AzureRegion 'uksouth' -Answer 'eastus' | Should -Be 'eastus'
    }

    It 'holds the answer documentAnalysisRegion in the example answer file' {
        $example = Get-Content -Raw (Join-Path (Split-Path -Parent $PSScriptRoot) 'inputs-example.json') | ConvertFrom-Json
        $example.PSObject.Properties.Name | Should -Contain 'documentAnalysisRegion'
    }
}

Context 'The configuration file' {

    It 'records the region in the field ContentUnderstandingRegion, next to the field AzureRegion' {
        $script:ConfigData['AzureRegion'] = 'switzerlandnorth'
        $script:ConfigData['ContentUnderstandingRegion'] = 'westeurope'
        $script:OutputFile = Join-Path $TestDrive 'Neologik_abc01_Configuration_20261113_120000.json'
        Export-ConfigurationData
        $config = Get-Content -Raw $script:OutputFile | ConvertFrom-Json
        $config.ContentUnderstandingRegion | Should -Be 'westeurope'
        $names = @($config.PSObject.Properties.Name)
        $names[$names.IndexOf('AzureRegion') + 1] | Should -Be 'ContentUnderstandingRegion'
    }

    It 'asks the question after the Azure region in a run with questions' {
        $text = Get-Content -Raw $script:ScriptPath
        $text | Should -Match ([regex]::Escape("`$script:ConfigData['ContentUnderstandingRegion'] = Read-NeologikDocumentAnalysisRegion -AzureRegion `$script:AzureRegion"))
    }
}

}
