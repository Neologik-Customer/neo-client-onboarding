#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Tests of Upgrade-TeamsAppInstallations.ps1: the signature check of the
    Microsoft Graph modules that the script installs, and the version.

    Each test runs a copy of the script in a folder on the test drive, so that
    the log of the run stays there. Stand-ins replace the PowerShell Gallery,
    the module installation, the signature reader and the sign-in. The stand-in
    of the sign-in ends the run, so no test reaches a Microsoft Teams call.

    Run: pwsh -NoProfile -Command "Invoke-Pester -Path tests -CI"
#>

Describe 'Upgrade-TeamsAppInstallations.ps1' {

AfterAll {
    Remove-Variable -Name UpgradeTest -Scope Global -ErrorAction SilentlyContinue
}

BeforeAll {
    # The script under test has its own script scope, so the stand-ins keep their state in one global table.
    $global:UpgradeTest = @{ Microsoft = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' }
    $script:SourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Upgrade-TeamsAppInstallations.ps1'
    $script:Modules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Users', 'Microsoft.Graph.Teams')

    # Stand-ins for the commands that the script calls: a command must exist before Pester can mock it.
    function Get-PSRepository { [CmdletBinding()] param($Name) [pscustomobject]@{ Name = 'PSGallery'; InstallationPolicy = 'Trusted' } }
    function Set-PSRepository { [CmdletBinding()] param($Name, $InstallationPolicy) }
    function Install-Module { [CmdletBinding()] param($Name, $Scope, [switch]$Force, [switch]$AllowClobber) }
    function Connect-MgGraph {
        [CmdletBinding()]
        param($Scopes, $TenantId, $Audience, [switch]$NoWelcome, [switch]$UseDeviceAuthentication)
        $global:UpgradeTest.SignInReached = $true
        throw 'The test ends the run at the sign-in.'
    }
    function Get-MgContext { [CmdletBinding()] param() }
    function Disconnect-MgGraph { [CmdletBinding()] param() }

    function New-UpgradeSignature([string]$Status = 'Valid', [string]$Subject = $global:UpgradeTest.Microsoft) {
        $certificate = if ($Subject) { [pscustomobject]@{ Subject = $Subject } } else { $null }
        [pscustomobject]@{ Status = $Status; SignerCertificate = $certificate }
    }

    # A module in the test module folder: a manifest, a script module and a library. Each Microsoft Graph
    # module other than Microsoft.Graph.Authentication requires Microsoft.Graph.Authentication at the same version.
    function New-UpgradeTestModule([string]$Name, [string]$Version = '2.38.0') {
        $base = Join-Path $global:UpgradeTest.ModuleRoot "$Name\$Version"
        $null = New-Item -ItemType Directory -Path (Join-Path $base 'lib') -Force
        $required = if ($Name -ne 'Microsoft.Graph.Authentication') { "@{ ModuleName = 'Microsoft.Graph.Authentication'; RequiredVersion = '$Version' }" } else { '' }
        Set-Content -LiteralPath (Join-Path $base "$Name.psd1") -Value "@{ ModuleVersion = '$Version'; RootModule = '$Name.psm1'; RequiredAssemblies = @('lib\$Name.dll'); RequiredModules = @($required) }"
        Set-Content -LiteralPath (Join-Path $base "$Name.psm1") -Value '# A script module for the test.'
        Set-Content -LiteralPath (Join-Path $base "lib\$Name.dll") -Value 'A library for the test.'
        return $base
    }

    # Runs the copy of the script and returns the text of the log of the run.
    function Invoke-UpgradeRun {
        & $global:UpgradeTest.ScriptCopy -Force *> $null
        $log = Get-ChildItem -LiteralPath $global:UpgradeTest.RunFolder -Filter 'TeamsAppUpgrade_*.log' | Select-Object -First 1
        if ($log) { Get-Content -Raw -LiteralPath $log.FullName } else { '' }
    }
}

BeforeEach {
    $global:UpgradeTest.RunFolder = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $global:UpgradeTest.ModuleRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $global:UpgradeTest.RunFolder, $global:UpgradeTest.ModuleRoot
    $global:UpgradeTest.ScriptCopy = Join-Path $global:UpgradeTest.RunFolder 'Upgrade-TeamsAppInstallations.ps1'
    Copy-Item -LiteralPath $script:SourcePath -Destination $global:UpgradeTest.ScriptCopy

    # The test module folder is the only module path, so that Get-Module finds the test modules only.
    $global:UpgradeTest.SavedModulePath = $env:PSModulePath
    $env:PSModulePath = $global:UpgradeTest.ModuleRoot
    $global:UpgradeTest.SignInReached = $false

    # Each file has a valid signature of Microsoft Corporation, unless a test names the end of the path of the file.
    $global:UpgradeTest.Signatures = @{}
    Mock Get-AuthenticodeSignature {
        $path = if ($LiteralPath) { [string]$LiteralPath } else { [string]$FilePath }
        $match = @($global:UpgradeTest.Signatures.Keys | Where-Object { $path -like "*$_" }) | Select-Object -First 1
        if ($match) { $global:UpgradeTest.Signatures[$match] } else { New-UpgradeSignature }
    }
    Mock Install-Module { param($Name) $null = New-UpgradeTestModule -Name $Name }
    Mock Import-Module { } -ParameterFilter { "$Name" -like 'Microsoft.Graph.*' }
}

AfterEach {
    $env:PSModulePath = $global:UpgradeTest.SavedModulePath
}

It 'parses without errors, holds only standard ASCII and reports version v0.2.3' {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script:SourcePath, [ref]$tokens, [ref]$errors)
    @($errors).Count | Should -Be 0
    $bytes = [System.IO.File]::ReadAllBytes($script:SourcePath)
    @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    $text = Get-Content -Raw -LiteralPath $script:SourcePath
    $text | Should -Match ([regex]::Escape("`$script:Version = 'v0.2.3'"))
    $text | Should -Match ([regex]::Escape('Version: v0.2.3'))
}

It 'installs the missing modules, checks each file and then signs in' {
    $log = Invoke-UpgradeRun
    $global:UpgradeTest.SignInReached | Should -BeTrue
    Should -Invoke Install-Module -Times 3 -Exactly
    Should -Invoke Get-AuthenticodeSignature -Times 9 -Exactly
    Should -Invoke Import-Module -Times 3 -Exactly
    $log | Should -Match 'Each file of the installed modules has a valid signature'
}

It 'removes the installed modules and stops with exit code 1 before the import and the sign-in when a file fails the check' {
    $global:UpgradeTest.Signatures['Microsoft.Graph.Teams.dll'] = New-UpgradeSignature -Status 'HashMismatch'
    $log = Invoke-UpgradeRun
    $LASTEXITCODE | Should -Be 1
    $global:UpgradeTest.SignInReached | Should -BeFalse
    Should -Invoke Import-Module -Times 0 -Exactly
    Get-ChildItem -LiteralPath $global:UpgradeTest.ModuleRoot -Recurse -File | Should -BeNullOrEmpty
    $log | Should -Match 'Microsoft\.Graph\.Teams\.dll: the file changed after the publisher signed the file'
    $log | Should -Match 'A PowerShell module failed the signature check'
}

It 'stops when a script file of the module that an installed module requires has the signature of another publisher, and removes only the modules of the run' {
    $authentication = New-UpgradeTestModule -Name 'Microsoft.Graph.Authentication'
    $global:UpgradeTest.Signatures['Microsoft.Graph.Authentication.psm1'] = New-UpgradeSignature -Subject 'CN=Contoso Ltd, O=Contoso Ltd, L=London, C=GB'
    $log = Invoke-UpgradeRun
    $LASTEXITCODE | Should -Be 1
    $global:UpgradeTest.SignInReached | Should -BeFalse
    Should -Invoke Install-Module -Times 2 -Exactly
    $log | Should -Match 'Microsoft\.Graph\.Authentication\.psm1: the signer is not Microsoft Corporation'
    Test-Path -LiteralPath $authentication | Should -BeTrue -Because 'the script did not install the module in this run'
    Test-Path -LiteralPath (Join-Path $global:UpgradeTest.ModuleRoot 'Microsoft.Graph.Users\2.38.0') | Should -BeFalse
    Test-Path -LiteralPath (Join-Path $global:UpgradeTest.ModuleRoot 'Microsoft.Graph.Teams\2.38.0') | Should -BeFalse
}

It 'checks no file when the modules are already installed' {
    foreach ($module in $script:Modules) { $null = New-UpgradeTestModule -Name $module }
    $null = Invoke-UpgradeRun
    $global:UpgradeTest.SignInReached | Should -BeTrue
    Should -Invoke Install-Module -Times 0 -Exactly
    Should -Invoke Get-AuthenticodeSignature -Times 0 -Exactly
}

}
