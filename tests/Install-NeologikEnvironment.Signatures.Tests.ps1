#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Tests of the signature checks of Install-NeologikEnvironment.ps1. The script
    checks the Authenticode signature of a downloaded PowerShell installer before
    the installer runs. The script checks each file of each module that the script
    installs before the script imports any module.

    Run: pwsh -NoProfile -Command "Invoke-Pester -Path tests -CI"
#>

Describe 'Install-NeologikEnvironment.ps1 (signature checks)' {

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Install-NeologikEnvironment.ps1'

    # Stubs for the commands that the checks call: a command must exist before Pester can mock it.
    if (-not (Get-Command Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) {
        function Get-AuthenticodeSignature { [CmdletBinding()] param($LiteralPath, $FilePath) }
    }
    function Install-Module { [CmdletBinding()] param($Name, $MinimumVersion, $Scope, [switch]$Force, [switch]$AllowClobber) }
    function Get-PSRepository { [CmdletBinding()] param($Name) }
    function Set-PSRepository { [CmdletBinding()] param($Name, $InstallationPolicy) }

    # The script under test: dot-sourced, so its functions are defined here and its guarded main entry does not run.
    . $script:ScriptPath

    $script:Microsoft = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
    $script:JsonNet = 'CN=Json.NET (.NET Foundation), O=Json.NET (.NET Foundation), L=Redmond, S=Washington, C=US'
    $script:Contoso = 'CN=Contoso Ltd, O=Contoso Ltd, L=London, C=GB'

    function New-Signature([string]$Status = 'Valid', [string]$Subject = $script:Microsoft) {
        $certificate = if ($Subject) { [pscustomobject]@{ Subject = $Subject } } else { $null }
        [pscustomobject]@{ Status = $Status; SignerCertificate = $certificate }
    }

    # A module in the test module folder. A full module holds a manifest, a script module and a library.
    # A manifest-only module holds a manifest that names other modules and loads no code.
    function New-TestModule([string]$Name, [string]$Version, [object[]]$Requires = @(), [switch]$ManifestOnly) {
        $base = Join-Path $script:ModuleRoot "$Name\$Version"
        $null = New-Item -ItemType Directory -Path $base -Force
        $required = ($Requires | ForEach-Object { "@{ ModuleName = '$($_.Name)'; RequiredVersion = '$($_.Version)' }" }) -join ', '
        if ($ManifestOnly) {
            Set-Content -LiteralPath (Join-Path $base "$Name.psd1") -Value "@{ ModuleVersion = '$Version'; RequiredModules = @($required) }"
        }
        else {
            Set-Content -LiteralPath (Join-Path $base "$Name.psd1") -Value "@{ ModuleVersion = '$Version'; RootModule = '$Name.psm1'; RequiredAssemblies = @('lib\$Name.dll'); RequiredModules = @($required) }"
            Set-Content -LiteralPath (Join-Path $base "$Name.psm1") -Value '# A script module for the test.'
            $null = New-Item -ItemType Directory -Path (Join-Path $base 'lib') -Force
            Set-Content -LiteralPath (Join-Path $base "lib\$Name.dll") -Value 'A library for the test.'
        }
        return $base
    }

    Mock Write-Log { }
    Mock Write-Host { }
}

BeforeEach {
    # The test module folder is the only module path, so that Get-Module finds the test modules only.
    $script:ModuleRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $script:ModuleRoot
    $script:SavedModulePath = $env:PSModulePath
    $env:PSModulePath = $script:ModuleRoot

    # Each file has a valid signature of Microsoft Corporation, unless a test names the end of the path of the file.
    $script:Signatures = @{}
    Mock Get-AuthenticodeSignature {
        $path = if ($LiteralPath) { [string]$LiteralPath } else { [string]$FilePath }
        $match = @($script:Signatures.Keys | Where-Object { $path -like "*$_" }) | Select-Object -First 1
        if ($match) { $script:Signatures[$match] } else { New-Signature }
    }
}

AfterEach {
    $env:PSModulePath = $script:SavedModulePath
}

Context 'Get-NeologikSignatureProblem' {

    It 'passes a file that has a valid signature of Microsoft Corporation' {
        Get-NeologikSignatureProblem -Path 'C:\modules\Az.Accounts.psm1' -MicrosoftOnly | Should -BeNullOrEmpty
    }

    It 'reports a file that has no signature' {
        $script:Signatures['unsigned.psm1'] = New-Signature -Status 'NotSigned' -Subject ''
        Get-NeologikSignatureProblem -Path 'C:\modules\unsigned.psm1' -MicrosoftOnly | Should -Be 'the file has no signature'
    }

    It 'reports a file that changed after the publisher signed the file' {
        $script:Signatures['changed.dll'] = New-Signature -Status 'HashMismatch'
        Get-NeologikSignatureProblem -Path 'C:\modules\changed.dll' | Should -Be 'the file changed after the publisher signed the file'
    }

    It 'reports a file that another publisher signed, when the check requires Microsoft Corporation' {
        $script:Signatures['other.psm1'] = New-Signature -Subject $script:Contoso
        Get-NeologikSignatureProblem -Path 'C:\modules\other.psm1' -MicrosoftOnly | Should -BeLike 'the signer is not Microsoft Corporation*Contoso Ltd*'
    }

    It 'passes a library that another publisher signed, as the Az modules hold today' {
        $script:Signatures['Newtonsoft.Json.dll'] = New-Signature -Subject $script:JsonNet
        Get-NeologikSignatureProblem -Path 'C:\modules\Newtonsoft.Json.dll' | Should -BeNullOrEmpty
    }
}

Context 'Assert-NeologikModuleSignature' {

    It 'passes a module whose files have valid signatures, and removes nothing' {
        $base = New-TestModule -Name 'Contoso.Accounts' -Version '5.5.3'
        { Assert-NeologikModuleSignature -Modules @(@{ Name = 'Contoso.Accounts'; MinVersion = '5.2.0' }) } | Should -Not -Throw
        Test-Path -LiteralPath $base | Should -BeTrue
        Should -Invoke Get-AuthenticodeSignature -Times 3 -Exactly
    }

    It 'passes a module whose library another publisher signed' {
        $null = New-TestModule -Name 'Contoso.KeyVault' -Version '6.5.0'
        $script:Signatures['Contoso.KeyVault.dll'] = New-Signature -Subject $script:JsonNet
        { Assert-NeologikModuleSignature -Modules @(@{ Name = 'Contoso.KeyVault'; MinVersion = '5.0.0' }) } | Should -Not -Throw
    }

    It 'passes a manifest that loads no code and has no signature, and checks each module that the manifest names' {
        $null = New-TestModule -Name 'Contoso.Graph.Authentication' -Version '2.38.0'
        $null = New-TestModule -Name 'Contoso.Graph.Users' -Version '2.38.0' -Requires @(@{ Name = 'Contoso.Graph.Authentication'; Version = '2.38.0' })
        $null = New-TestModule -Name 'Contoso.Graph' -Version '2.38.0' -ManifestOnly -Requires @(
            @{ Name = 'Contoso.Graph.Authentication'; Version = '2.38.0' },
            @{ Name = 'Contoso.Graph.Users'; Version = '2.38.0' })
        $script:Signatures['Contoso.Graph.psd1'] = New-Signature -Status 'NotSigned' -Subject ''
        { Assert-NeologikModuleSignature -Modules @(@{ Name = 'Contoso.Graph'; MinVersion = '2.0.0' }) } | Should -Not -Throw
        Should -Invoke Get-AuthenticodeSignature -Times 1 -Exactly -ParameterFilter { "$LiteralPath" -like '*Contoso.Graph.Users.psm1' }
        Should -Invoke Get-AuthenticodeSignature -Times 1 -Exactly -ParameterFilter { "$LiteralPath" -like '*Contoso.Graph.Authentication.dll' }
    }

    It 'stops the run and removes the installed module when a script file has no signature' {
        $base = New-TestModule -Name 'Contoso.Accounts' -Version '5.5.3'
        $script:Signatures['Contoso.Accounts.psm1'] = New-Signature -Status 'NotSigned' -Subject ''
        { Assert-NeologikModuleSignature -Modules @(@{ Name = 'Contoso.Accounts'; MinVersion = '5.2.0' }) } |
            Should -Throw -ExpectedMessage '*failed the signature check*'
        Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Error' -and $Message -like '*Contoso.Accounts 5.5.3*Contoso.Accounts.psm1: the file has no signature' }
        Test-Path -LiteralPath $base | Should -BeFalse
    }

    It 'stops the run when a library has an invalid signature' {
        $null = New-TestModule -Name 'Contoso.Storage' -Version '9.7.0'
        $script:Signatures['Contoso.Storage.dll'] = New-Signature -Status 'HashMismatch'
        { Assert-NeologikModuleSignature -Modules @(@{ Name = 'Contoso.Storage'; MinVersion = '6.0.0' }) } |
            Should -Throw -ExpectedMessage '*failed the signature check*'
    }

    It 'stops the run when a script file has the signature of another publisher' {
        $null = New-TestModule -Name 'Contoso.Resources' -Version '10.0.0'
        $script:Signatures['Contoso.Resources.psd1'] = New-Signature -Subject $script:Contoso
        { Assert-NeologikModuleSignature -Modules @(@{ Name = 'Contoso.Resources'; MinVersion = '7.0.0' }) } |
            Should -Throw -ExpectedMessage '*failed the signature check*'
        Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Error' -and $Message -like '*the signer is not Microsoft Corporation*' }
    }

    It 'stops the run when a manifest that loads code has no signature' {
        $null = New-TestModule -Name 'Contoso.Compute' -Version '11.6.0'
        $script:Signatures['Contoso.Compute.psd1'] = New-Signature -Status 'NotSigned' -Subject ''
        { Assert-NeologikModuleSignature -Modules @(@{ Name = 'Contoso.Compute'; MinVersion = '7.0.0' }) } |
            Should -Throw -ExpectedMessage '*failed the signature check*'
    }

    It 'stops the run and removes the installed module when a module that the installed module requires fails the check' {
        $null = New-TestModule -Name 'Contoso.Graph.Authentication' -Version '2.38.0'
        $meta = New-TestModule -Name 'Contoso.Graph' -Version '2.38.0' -ManifestOnly -Requires @(@{ Name = 'Contoso.Graph.Authentication'; Version = '2.38.0' })
        $script:Signatures['Contoso.Graph.psd1'] = New-Signature -Status 'NotSigned' -Subject ''
        $script:Signatures['Contoso.Graph.Authentication.dll'] = New-Signature -Status 'NotSigned' -Subject ''
        { Assert-NeologikModuleSignature -Modules @(@{ Name = 'Contoso.Graph'; MinVersion = '2.0.0' }) } |
            Should -Throw -ExpectedMessage '*failed the signature check*'
        Test-Path -LiteralPath $meta | Should -BeFalse
    }

    It 'passes a reference assembly that has no signature' {
        $base = New-TestModule -Name 'Contoso.Exchange' -Version '3.10.1'
        $null = New-Item -ItemType Directory -Path (Join-Path $base 'ref') -Force
        Set-Content -LiteralPath (Join-Path $base 'ref\Contoso.Exchange.Reference.dll') -Value 'A reference assembly for the test.'
        $script:Signatures['ref\Contoso.Exchange.Reference.dll'] = New-Signature -Status 'NotSigned' -Subject ''
        Mock Test-NeologikReferenceAssembly { $Path -like '*\ref\*' }
        { Assert-NeologikModuleSignature -Modules @(@{ Name = 'Contoso.Exchange'; MinVersion = '3.0.0' }) } | Should -Not -Throw
        Should -Invoke Test-NeologikReferenceAssembly -Times 1 -Exactly
        Test-Path -LiteralPath $base | Should -BeTrue
    }

    It 'stops the run when a library with no signature is not a reference assembly' {
        $null = New-TestModule -Name 'Contoso.Storage' -Version '9.7.0'
        $script:Signatures['Contoso.Storage.dll'] = New-Signature -Status 'NotSigned' -Subject ''
        { Assert-NeologikModuleSignature -Modules @(@{ Name = 'Contoso.Storage'; MinVersion = '6.0.0' }) } |
            Should -Throw -ExpectedMessage '*failed the signature check*'
    }

    It 'stops the run when a reference assembly has an invalid signature' {
        $base = New-TestModule -Name 'Contoso.Exchange' -Version '3.10.1'
        $null = New-Item -ItemType Directory -Path (Join-Path $base 'ref') -Force
        Set-Content -LiteralPath (Join-Path $base 'ref\Contoso.Exchange.Reference.dll') -Value 'A reference assembly for the test.'
        $script:Signatures['ref\Contoso.Exchange.Reference.dll'] = New-Signature -Status 'HashMismatch'
        Mock Test-NeologikReferenceAssembly { $true }
        { Assert-NeologikModuleSignature -Modules @(@{ Name = 'Contoso.Exchange'; MinVersion = '3.0.0' }) } |
            Should -Throw -ExpectedMessage '*failed the signature check*'
    }

    It 'checks the modules that a manifest requires when the other values of the manifest depend on the edition of PowerShell' {
        $null = New-TestModule -Name 'Contoso.Base' -Version '1.4.0'
        $base = Join-Path $script:ModuleRoot 'Contoso.Exchange\3.10.1'
        $null = New-Item -ItemType Directory -Path $base -Force
        Set-Content -LiteralPath (Join-Path $base 'Contoso.Exchange.psd1') -Value "@{ ModuleVersion = '3.10.1'; RootModule = if (`$PSEdition -eq 'Core') { 'Contoso.Exchange.psm1' } else { 'Contoso.Exchange.psm1' }; RequiredModules = @(@{ ModuleName = 'Contoso.Base'; ModuleVersion = '1.0.0' }) }"
        Set-Content -LiteralPath (Join-Path $base 'Contoso.Exchange.psm1') -Value '# A script module for the test.'
        { Assert-NeologikModuleSignature -Modules @(@{ Name = 'Contoso.Exchange'; MinVersion = '3.0.0' }) } | Should -Not -Throw
        Should -Invoke Get-AuthenticodeSignature -Times 1 -Exactly -ParameterFilter { "$LiteralPath" -like '*Contoso.Base.psm1' }
    }
}

Context 'Get-NeologikRequiredModuleList' {

    It 'returns each entry, with the exact version or the module name' {
        $path = Join-Path $TestDrive 'Contoso.Static.psd1'
        Set-Content -LiteralPath $path -Value "@{ ModuleVersion = '1.0.0'; RequiredModules = @(@{ ModuleName = 'Contoso.A'; RequiredVersion = '2.38.0' }, 'Contoso.B') }"
        $list = @(Get-NeologikRequiredModuleList -Path $path)
        $list.Count | Should -Be 2
        $list[0]['ModuleName'] | Should -Be 'Contoso.A'
        $list[0]['RequiredVersion'] | Should -Be '2.38.0'
        $list[1] | Should -Be 'Contoso.B'
    }

    It 'returns nothing for a manifest that requires no module' {
        $path = Join-Path $TestDrive 'Contoso.Alone.psd1'
        Set-Content -LiteralPath $path -Value "@{ ModuleVersion = '1.0.0'; RootModule = 'Contoso.Alone.psm1' }"
        @(Get-NeologikRequiredModuleList -Path $path).Count | Should -Be 0
    }

    It 'refuses a value of RequiredModules that is not data' {
        $path = Join-Path $TestDrive 'Contoso.Dynamic.psd1'
        Set-Content -LiteralPath $path -Value "@{ ModuleVersion = '1.0.0'; RequiredModules = if (`$PSEdition -eq 'Core') { @('Contoso.A') } else { @('Contoso.B') } }"
        { Get-NeologikRequiredModuleList -Path $path } | Should -Throw -ExpectedMessage '*not data*'
    }
}

Context 'Test-NeologikReferenceAssembly' {

    BeforeAll {
        # Two real libraries, compiled for the test: a reference assembly and an ordinary library.
        $script:ReferenceLibrary = Join-Path $TestDrive 'Contoso.Reference.dll'
        $script:RuntimeLibrary = Join-Path $TestDrive 'Contoso.Runtime.dll'
        Add-Type -TypeDefinition '[assembly: System.Runtime.CompilerServices.ReferenceAssembly] namespace Contoso.Reference { public class Sample { } }' -OutputAssembly $script:ReferenceLibrary -OutputType Library
        Add-Type -TypeDefinition 'namespace Contoso.Runtime { public class Sample { } }' -OutputAssembly $script:RuntimeLibrary -OutputType Library
    }

    It 'recognises a reference assembly' {
        Test-NeologikReferenceAssembly -Path $script:ReferenceLibrary | Should -BeTrue
    }

    It 'does not count an ordinary library as a reference assembly' {
        Test-NeologikReferenceAssembly -Path $script:RuntimeLibrary | Should -BeFalse
    }

    It 'does not count a file that is not a library as a reference assembly' {
        $path = Join-Path $TestDrive 'Contoso.Text.dll'
        Set-Content -LiteralPath $path -Value 'Text, not a library.'
        Test-NeologikReferenceAssembly -Path $path | Should -BeFalse
    }
}

Context 'Install-RequiredModules' {

    BeforeEach {
        Mock Get-PSRepository { [pscustomobject]@{ Name = 'PSGallery'; InstallationPolicy = 'Trusted' } }
        Mock Install-Module { param($Name) $null = New-TestModule -Name $Name -Version '5.5.3' }
    }

    It 'checks the signatures after the download, and stops before any import when a file fails the check' {
        $script:Signatures['Contoso.Accounts.dll'] = New-Signature -Status 'NotSigned' -Subject ''
        { Install-RequiredModules -Modules @(@{ Name = 'Contoso.Accounts'; MinVersion = '5.2.0' }) } |
            Should -Throw -ExpectedMessage '*failed the signature check*'
        Should -Invoke Install-Module -Times 1 -Exactly
        Find-NeologikInstalledModule -Name 'Contoso.Accounts' -MinimumVersion '5.2.0' | Should -BeNullOrEmpty
    }

    It 'keeps a module whose files have valid signatures' {
        { Install-RequiredModules -Modules @(@{ Name = 'Contoso.Accounts'; MinVersion = '5.2.0' }) } | Should -Not -Throw
        Find-NeologikInstalledModule -Name 'Contoso.Accounts' -MinimumVersion '5.2.0' | Should -Not -BeNullOrEmpty
    }
}

Context 'Install-PowerShellLatest' {

    BeforeEach {
        $script:SavedTemp = $env:TEMP
        $env:TEMP = $TestDrive
        Mock Get-Command { } -ParameterFilter { $Name -eq 'winget' }
        Mock Invoke-RestMethod { [pscustomobject]@{ assets = @([pscustomobject]@{ name = 'PowerShell-7.6.9-win-x64.msi'; browser_download_url = 'https://example.invalid/PowerShell-7.6.9-win-x64.msi' }) } }
        Mock Invoke-WebRequest { param($Uri, $OutFile) Set-Content -LiteralPath $OutFile -Value 'An installer for the test.' }
        # The test stops at the start of the installer, before the script ends the PowerShell session.
        Mock Start-Process { throw 'the installer started' }
    }

    AfterEach {
        $env:TEMP = $script:SavedTemp
    }

    It 'deletes the installer and stops before the installer runs, when the installer has no valid signature' {
        $script:Signatures['PowerShell-Setup.msi'] = New-Signature -Status 'HashMismatch'
        { Install-PowerShellLatest } | Should -Throw -ExpectedMessage '*failed the signature check*'
        Should -Invoke Start-Process -Times 0 -Exactly
        Test-Path -LiteralPath (Join-Path $TestDrive 'PowerShell-Setup.msi') | Should -BeFalse
    }

    It 'stops before the installer runs, when another publisher signed the installer' {
        $script:Signatures['PowerShell-Setup.msi'] = New-Signature -Subject $script:Contoso
        { Install-PowerShellLatest } | Should -Throw -ExpectedMessage '*the signer is not Microsoft Corporation*'
        Should -Invoke Start-Process -Times 0 -Exactly
    }

    It 'runs the installer when Microsoft Corporation signed the installer' {
        { Install-PowerShellLatest } | Should -Throw -ExpectedMessage '*the installer started*'
        Should -Invoke Start-Process -Times 1 -Exactly
    }
}

}
