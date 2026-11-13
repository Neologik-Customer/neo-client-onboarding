#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Tests of the signature check of Grant-NeologikAgentAccess.ps1. After the
    script installs a module, the script checks each file of each installed
    module before the script imports any module of the set. The tests install
    fake modules into a test module folder and replace the signature reader.

    Run: pwsh -NoProfile -Command "Invoke-Pester -Path tests -CI"
#>

Describe 'Grant-NeologikAgentAccess.ps1 (signature check)' {

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Grant-NeologikAgentAccess.ps1'

    # Stubs for the commands that the check calls: a command must exist before Pester can mock it.
    if (-not (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) {
        function Get-AuthenticodeSignature { [CmdletBinding()] param($LiteralPath, $FilePath) }
    }
    function Install-Module { [CmdletBinding()] param($Name, $Scope, [switch]$Force, [switch]$AllowClobber, $MinimumVersion) }

    # The script under test: dot-sourced, so its functions are defined here and its guarded main entry does not run.
    . $script:ScriptPath

    $script:Microsoft = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
    $script:Contoso = 'CN=Contoso Ltd, O=Contoso Ltd, L=London, C=GB'
    $script:InstallHint = 'Install-Module Contoso.Graph.Authentication, Contoso.Graph.Applications -Scope CurrentUser -Force'

    function New-Signature([string]$Status = 'Valid', [string]$Subject = $script:Microsoft) {
        $certificate = if ($Subject) { [pscustomobject]@{ Subject = $Subject } } else { $null }
        [pscustomobject]@{ Status = $Status; SignerCertificate = $certificate }
    }

    # A module in the test module folder: a manifest, a script module and a library. -Manifest replaces the manifest text.
    function New-TestModule([string]$Name, [string]$Version, [object[]]$Requires = @(), [string]$Manifest, [string[]]$ReferenceAssemblies = @()) {
        $base = Join-Path $script:ModuleRoot "$Name\$Version"
        $null = New-Item -ItemType Directory -Path (Join-Path $base 'lib') -Force
        $required = ($Requires | ForEach-Object { "@{ ModuleName = '$($_.Name)'; RequiredVersion = '$($_.Version)' }" }) -join ', '
        if (-not $Manifest) {
            $Manifest = "@{ ModuleVersion = '$Version'; RootModule = '$Name.psm1'; RequiredAssemblies = @('lib\$Name.dll'); RequiredModules = @($required) }"
        }
        Set-Content -LiteralPath (Join-Path $base "$Name.psd1") -Value $Manifest
        Set-Content -LiteralPath (Join-Path $base "$Name.psm1") -Value '# A script module for the test.'
        Set-Content -LiteralPath (Join-Path $base "lib\$Name.dll") -Value 'A library for the test.'
        foreach ($reference in $ReferenceAssemblies) {
            $null = New-Item -ItemType Directory -Path (Join-Path $base 'ref') -Force
            Set-Content -LiteralPath (Join-Path $base "ref\$reference") -Value 'A reference assembly for the test.'
        }
        return $base
    }
}

BeforeEach {
    # The test module folder is the only module path, so that Get-Module finds the test modules only.
    $script:ModuleRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $script:ModuleRoot
    $script:SavedModulePath = $env:PSModulePath
    $env:PSModulePath = $script:ModuleRoot
    $script:Console = @()
    $script:Imports = @()

    # Each file has a valid signature of Microsoft Corporation, unless a test names the end of the path of the file.
    $script:Signatures = @{}
    Mock Get-AuthenticodeSignature {
        $path = if ($LiteralPath) { [string]$LiteralPath } else { [string]$FilePath }
        $match = @($script:Signatures.Keys | Where-Object { $path -like "*$_" }) | Select-Object -First 1
        if ($match) { $script:Signatures[$match] } else { New-Signature }
    }
    Mock Write-Host { param($Object) $script:Console += [string]$Object }
    Mock Import-Module { param($Name, $RequiredVersion) $script:Imports += "$Name $RequiredVersion" }
    Mock Install-Module {
        param($Name)
        if ($Name -eq 'Contoso.Graph.Applications') {
            $null = New-TestModule -Name 'Contoso.Graph.Authentication' -Version '2.38.0'
            $null = New-TestModule -Name $Name -Version '2.38.0' -Requires @(@{ Name = 'Contoso.Graph.Authentication'; Version = '2.38.0' })
        }
        else {
            $null = New-TestModule -Name $Name -Version '2.38.0'
        }
    }
}

AfterEach {
    $env:PSModulePath = $script:SavedModulePath
}

It 'checks each file of the installed modules and then imports one version of the set' {
    $result = Import-NeologikModuleSet -Names @('Contoso.Graph.Authentication', 'Contoso.Graph.Applications') -MinimumVersion '2.0.0' -InstallHint $script:InstallHint
    $result | Should -BeTrue
    Should -Invoke Install-Module -Times 2 -Exactly
    Should -Invoke Get-AuthenticodeSignature -ParameterFilter { "$LiteralPath" -like '*Contoso.Graph.Applications.psm1' } -Times 1 -Exactly
    $script:Imports | Should -Be @('Contoso.Graph.Authentication 2.38.0', 'Contoso.Graph.Applications 2.38.0')
}

It 'removes the installed modules, imports nothing and names no install command when a file fails the check' {
    $script:Signatures['Contoso.Graph.Applications.psm1'] = New-Signature -Status 'NotSigned' -Subject ''
    $result = Import-NeologikModuleSet -Names @('Contoso.Graph.Authentication', 'Contoso.Graph.Applications') -MinimumVersion '2.0.0' -InstallHint $script:InstallHint
    $result | Should -BeFalse
    Should -Invoke Import-Module -Times 0 -Exactly
    Get-Module -ListAvailable -Name 'Contoso.Graph.Applications' | Should -BeNullOrEmpty
    $console = $script:Console -join "`n"
    $console | Should -Match 'ACTION REQUIRED'
    $console | Should -Match 'failed the signature check'
    $console | Should -Match 'Contoso\.Graph\.Applications\.psm1: the file has no signature'
    $console | Should -Not -Match ([regex]::Escape($script:InstallHint))
}

It 'still names the install command when the install itself fails' {
    Mock Install-Module { throw 'No match was found for the specified search criteria' }
    $result = Import-NeologikModuleSet -Names @('Contoso.Graph.Authentication') -MinimumVersion '2.0.0' -InstallHint $script:InstallHint
    $result | Should -BeFalse
    ($script:Console -join "`n") | Should -Match ([regex]::Escape($script:InstallHint))
    Should -Invoke Get-AuthenticodeSignature -Times 0 -Exactly
}

It 'checks nothing when every module of the set is already installed' {
    $null = New-TestModule -Name 'Contoso.Graph.Authentication' -Version '2.38.0'
    $result = Import-NeologikModuleSet -Names @('Contoso.Graph.Authentication') -MinimumVersion '2.0.0' -InstallHint $script:InstallHint
    $result | Should -BeTrue
    Should -Invoke Install-Module -Times 0 -Exactly
    Should -Invoke Get-AuthenticodeSignature -Times 0 -Exactly
}

It 'passes a module whose manifest depends on the edition of PowerShell and whose reference assembly has no signature, as the Exchange Online module holds today' {
    Mock Install-Module {
        param($Name)
        $null = New-TestModule -Name 'Contoso.Base' -Version '1.4.0'
        $manifest = "@{ ModuleVersion = '3.10.1'; RootModule = if (`$PSEdition -eq 'Core') { 'Contoso.Exchange.psm1' } else { 'Contoso.Exchange.psm1' }; RequiredModules = @(@{ ModuleName = 'Contoso.Base'; ModuleVersion = '1.0.0' }) }"
        $null = New-TestModule -Name $Name -Version '3.10.1' -Manifest $manifest -ReferenceAssemblies @('Contoso.Exchange.Reference.dll')
    }
    $script:Signatures['ref\Contoso.Exchange.Reference.dll'] = New-Signature -Status 'NotSigned' -Subject ''
    Mock Test-NeologikReferenceAssembly { $Path -like '*\ref\*' }
    $result = Import-NeologikModuleSet -Names @('Contoso.Exchange') -MinimumVersion '3.0.0' -InstallHint 'Install-Module Contoso.Exchange -Scope CurrentUser -Force'
    $result | Should -BeTrue
    Should -Invoke Get-AuthenticodeSignature -ParameterFilter { "$LiteralPath" -like '*Contoso.Base.psm1' } -Times 1 -Exactly
    $script:Imports | Should -Be @('Contoso.Exchange 3.10.1')
}

It 'stops when a file of the module that the installed module requires has the signature of another publisher' {
    Mock Install-Module {
        param($Name)
        $null = New-TestModule -Name 'Contoso.Base' -Version '1.4.0'
        $null = New-TestModule -Name $Name -Version '3.10.1' -Manifest "@{ ModuleVersion = '3.10.1'; RootModule = 'Contoso.Exchange.psm1'; RequiredModules = @(@{ ModuleName = 'Contoso.Base'; ModuleVersion = '1.0.0' }) }"
    }
    $script:Signatures['Contoso.Base.psd1'] = New-Signature -Subject $script:Contoso
    $result = Import-NeologikModuleSet -Names @('Contoso.Exchange') -MinimumVersion '3.0.0' -InstallHint 'Install-Module Contoso.Exchange -Scope CurrentUser -Force'
    $result | Should -BeFalse
    Get-Module -ListAvailable -Name 'Contoso.Exchange' | Should -BeNullOrEmpty
    ($script:Console -join "`n") | Should -Match 'the signer is not Microsoft Corporation'
    Should -Invoke Import-Module -Times 0 -Exactly
}

}
