#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Tests of Remove-NeologikDirectoryObjects.ps1.

    Every external call is replaced: Microsoft Graph, module installation and the
    console. An in-memory directory answers the script's searches and records every
    deletion, so a run can be asserted to delete exactly the objects of one
    environment, in the right order, and nothing without the confirmation.

    Run: pwsh -NoProfile -Command "Invoke-Pester -Path tests -CI"
#>

Describe 'Remove-NeologikDirectoryObjects.ps1' {

AfterAll {
    Remove-Variable -Name RemovalTest -Scope Global -ErrorAction SilentlyContinue
}

BeforeAll {
    # The script under test has its own script scope, so the stand-ins keep their state in one global table.
    $global:RemovalTest = @{}
    $script:ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Remove-NeologikDirectoryObjects.ps1'

    function Connect-MgGraph {
        [CmdletBinding()]
        param($TenantId, $Scopes, $ContextScope, [switch]$NoWelcome, [switch]$UseDeviceCode)
        if ($global:RemovalTest.BrowserFails -and -not $UseDeviceCode) { throw 'InteractiveBrowserCredential authentication failed: A window handle must be configured.' }
        $global:RemovalTest.ConnectScopes = $Scopes
        $global:RemovalTest.ConnectTenant = $TenantId
        $global:RemovalTest.UsedDeviceCode = [bool]$UseDeviceCode
    }
    function Install-Module { [CmdletBinding()] param($Name, $Scope, [switch]$Force) }
    function Get-MgContext { [CmdletBinding()] param() [pscustomobject]@{ TenantId = 'tenant-1'; Account = 'admin@contoso.com' } }
    function Read-Host { param($Prompt) $global:RemovalTest.Prompted = $true; $global:RemovalTest.Answer }
    function Invoke-MgGraphRequest {
        [CmdletBinding()]
        param($Method, $Uri, $Headers)
        if ($Method -eq 'GET') {
            if ($Uri -match '/v1\.0/(users|servicePrincipals|applications|groups)\?') {
                $kind = $Matches[1]
                if ($global:RemovalTest.SecondPage -and $kind -eq 'groups' -and $Uri -notmatch 'skiptoken') {
                    return @{ value = @(); '@odata.nextLink' = "https://graph.microsoft.com/v1.0/groups?skiptoken=2" }
                }
                return @{ value = @($global:RemovalTest.Directory[$kind]) }
            }
            if ($Uri -match 'skiptoken') { return @{ value = @($global:RemovalTest.Directory['groups']) } }
            throw "Unexpected read: $Uri"
        }
        $global:RemovalTest.Deleted.Add($Uri)
        if ($global:RemovalTest.DeleteError -and $Uri -match $global:RemovalTest.DeleteErrorFor) { throw $global:RemovalTest.DeleteError }
    }
    function New-TestObject { param($Id, $Name, $Type) $o = @{ id = $Id; displayName = $Name }; if ($Type) { $o['@odata.type'] = "#microsoft.graph.$Type" }; $o }
}

BeforeEach {
    Mock Get-Module { @{ Name = 'Microsoft.Graph.Authentication' } }
    Mock Install-Module { }
    Mock Import-Module { }
    $global:RemovalTest.Deleted = [System.Collections.Generic.List[string]]::new()
    $global:RemovalTest.Answer = 'DELETE'
    $global:RemovalTest.Prompted = $false
    $global:RemovalTest.SecondPage = $false
    $global:RemovalTest.BrowserFails = $false
    $global:RemovalTest.UsedDeviceCode = $false
    $global:RemovalTest.DeleteError = $null
    $global:RemovalTest.DeleteErrorFor = $null
    $global:RemovalTest.Directory = @{
        users             = @(
            New-TestObject 'u1' 'Neologik Agent (one) - abcprd01' 'agentUser'
            New-TestObject 'u2' 'Jane Person - abcprd01' 'user'
            New-TestObject 'u3' 'Neologik Agent (two) - abcdev01' 'agentUser'
        )
        servicePrincipals = @(
            New-TestObject 's1' 'Neologik Agent Identity - agent-one - abcprd01' 'agentIdentity'
            New-TestObject 's2' 'Neologik Platform Sign-in - abcprd01'
            New-TestObject 's3' 'ais-neo-abcprd-uks-01-proj-AgentIdentity' 'agentIdentity'
            New-TestObject 's4' 'ais-neo-abcprd-uks-01-proj-AgentIdentityBlueprint' 'agentIdentityBlueprintPrincipal'
        )
        applications      = @(
            New-TestObject 'b1' 'Neologik Agent Blueprint - default - abcprd01' 'agentIdentityBlueprint'
            New-TestObject 'a1' 'Neologik Platform Sign-in - abcprd01'
            New-TestObject 'a2' 'Contoso Payroll'
            New-TestObject 'a3' 'Contoso - abcprd011'
        )
        groups            = @(
            New-TestObject 'g1' 'Neologik User Group - abcprd01'
            New-TestObject 'g2' 'ais-AgentIdentity readers'
        )
    }
}

It 'parses without errors and holds only standard ASCII' {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$tokens, [ref]$errors)
    @($errors).Count | Should -Be 0
    $bytes = [System.IO.File]::ReadAllBytes($script:ScriptPath)
    @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
}

It 'shows the synopsis and the description of the script in Get-Help, not only the syntax line' {
    # PowerShell reads no help block that follows a #Requires line directly, and Get-Help then shows only the syntax line.
    $help = Get-Help -Name $script:ScriptPath -Full
    $help.Synopsis | Should -Match '^Deletes the directory objects of one Neologik Platform environment'
    ($help.Description | Out-String) | Should -Match 'uninstall guide'
}

It 'requests only the five delegated permissions that the deletions need' {
    & $script:ScriptPath -ShortName abcprd01 | Out-Null
    $global:RemovalTest.ConnectScopes | Should -HaveCount 5
    $global:RemovalTest.ConnectScopes | Should -Contain 'AgentIdentityBlueprint.DeleteRestore.All'
    $global:RemovalTest.ConnectScopes | Should -Contain 'AgentIdentity.DeleteRestore.All'
    $global:RemovalTest.ConnectScopes | Should -Contain 'AgentIdUser.ReadWrite.All'
}

It 'passes the tenant to the sign-in when an administrator names the tenant' {
    & $script:ScriptPath -ShortName abcprd01 -TenantId 'tenant-9' | Out-Null
    $global:RemovalTest.ConnectTenant | Should -Be 'tenant-9'
}

It 'signs in with a device code when the sign-in window cannot open' {
    $global:RemovalTest.BrowserFails = $true
    & $script:ScriptPath -ShortName abcprd01 | Out-Null
    $global:RemovalTest.UsedDeviceCode | Should -BeTrue
    $LASTEXITCODE | Should -Be 0
}

It 'deletes agent accounts, then agent identities, then applications with the blueprint last, then groups' {
    & $script:ScriptPath -ShortName abcprd01 | Out-Null
    $LASTEXITCODE | Should -Be 0
    $global:RemovalTest.Deleted | Should -Be @(
        'https://graph.microsoft.com/beta/users/u1'
        'https://graph.microsoft.com/beta/servicePrincipals/s1/microsoft.graph.agentIdentity'
        'https://graph.microsoft.com/beta/servicePrincipals/s3/microsoft.graph.agentIdentity'
        'https://graph.microsoft.com/v1.0/applications/a1'
        'https://graph.microsoft.com/v1.0/applications/b1'
        'https://graph.microsoft.com/v1.0/groups/g1'
    )
}

It 'leaves a person, another environment and an object whose name only resembles the short name' {
    & $script:ScriptPath -ShortName abcprd01 | Out-Null
    ($global:RemovalTest.Deleted -join ' ') | Should -Not -Match '/users/u2|/users/u3|/applications/a2|/applications/a3|/groups/g2|/s2|/s4'
}

It 'deletes nothing when the administrator types <Answer>' -ForEach @(
    @{ Answer = 'delete' }, @{ Answer = 'yes' }, @{ Answer = '' }, @{ Answer = ' DELETE' }
) {
    $global:RemovalTest.Answer = $Answer
    & $script:ScriptPath -ShortName abcprd01 | Out-Null
    $global:RemovalTest.Prompted | Should -BeTrue
    $global:RemovalTest.Deleted | Should -HaveCount 0
    $LASTEXITCODE | Should -Be 0
}

It 'asks nothing and deletes nothing when nothing is left' {
    $global:RemovalTest.Directory = @{ users = @(); servicePrincipals = @(); applications = @(); groups = @() }
    & $script:ScriptPath -ShortName abcprd01 | Out-Null
    $global:RemovalTest.Prompted | Should -BeFalse
    $global:RemovalTest.Deleted | Should -HaveCount 0
    $LASTEXITCODE | Should -Be 0
}

It 'reads every page of a search' {
    $global:RemovalTest.SecondPage = $true
    & $script:ScriptPath -ShortName abcprd01 | Out-Null
    $global:RemovalTest.Deleted | Should -Contain 'https://graph.microsoft.com/v1.0/groups/g1'
}

It 'refuses a short name that holds a wildcard or a quotation mark' -ForEach @(
    @{ Name = '*' }, @{ Name = 'abc*' }, @{ Name = 'abc"prd' }, @{ Name = 'ab' }
) {
    { & $script:ScriptPath -ShortName $Name } | Should -Throw
    $global:RemovalTest.Deleted | Should -HaveCount 0
}

It 'continues after one failure and ends with exit code 1' {
    $global:RemovalTest.DeleteError = 'Response status code does not indicate success: Forbidden (Forbidden).'
    $global:RemovalTest.DeleteErrorFor = '/applications/a1'
    & $script:ScriptPath -ShortName abcprd01 3>$null | Out-Null
    $LASTEXITCODE | Should -Be 1
    $global:RemovalTest.Deleted | Should -Contain 'https://graph.microsoft.com/v1.0/groups/g1'
}

It 'counts an object that has already gone as removed' {
    $global:RemovalTest.DeleteError = 'Response status code does not indicate success: NotFound (Not Found).'
    $global:RemovalTest.DeleteErrorFor = '/users/u1'
    & $script:ScriptPath -ShortName abcprd01 | Out-Null
    $LASTEXITCODE | Should -Be 0
}

Context 'Signature check of the module that the script installs' {

    BeforeAll {
        # The script under test has its own script scope, so the stand-ins read the signer from the global table.
        $global:RemovalTest.Microsoft = 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'

        function New-RemovalSignature([string]$Status = 'Valid', [string]$Subject = $global:RemovalTest.Microsoft) {
            $certificate = if ($Subject) { [pscustomobject]@{ Subject = $Subject } } else { $null }
            [pscustomobject]@{ Status = $Status; SignerCertificate = $certificate }
        }

        # A module in the test module folder: a manifest, a script module and a library.
        function New-RemovalTestModule([string]$Name, [string]$Version) {
            $base = Join-Path $global:RemovalTest.ModuleRoot "$Name\$Version"
            $null = New-Item -ItemType Directory -Path (Join-Path $base 'lib') -Force
            Set-Content -LiteralPath (Join-Path $base "$Name.psd1") -Value "@{ ModuleVersion = '$Version'; RootModule = '$Name.psm1'; RequiredAssemblies = @('lib\$Name.dll') }"
            Set-Content -LiteralPath (Join-Path $base "$Name.psm1") -Value '# A script module for the test.'
            Set-Content -LiteralPath (Join-Path $base "lib\$Name.dll") -Value 'A library for the test.'
            return $base
        }
    }

    BeforeEach {
        # The test module folder is the only module path, so that Get-Module finds the test modules only.
        $global:RemovalTest.ModuleRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $global:RemovalTest.ModuleRoot
        $global:RemovalTest.SavedModulePath = $env:PSModulePath
        $env:PSModulePath = $global:RemovalTest.ModuleRoot
        $global:RemovalTest.Signatures = @{}
        $global:RemovalTest.ConnectScopes = $null
        Mock Get-Module { & (Get-Command -Name Get-Module -CommandType Cmdlet) @PesterBoundParameters }
        Mock Install-Module { param($Name) $null = New-RemovalTestModule -Name $Name -Version '2.38.0' }
        # Each file has a valid signature of Microsoft Corporation, unless a test names the end of the path of the file.
        Mock Get-AuthenticodeSignature {
            $path = if ($LiteralPath) { [string]$LiteralPath } else { [string]$FilePath }
            $match = @($global:RemovalTest.Signatures.Keys | Where-Object { $path -like "*$_" }) | Select-Object -First 1
            if ($match) { $global:RemovalTest.Signatures[$match] } else { New-RemovalSignature }
        }
    }

    AfterEach {
        $env:PSModulePath = $global:RemovalTest.SavedModulePath
    }

    It 'installs the missing module, checks each file and then signs in' {
        & $script:ScriptPath -ShortName abcprd01 | Out-Null
        $LASTEXITCODE | Should -Be 0
        Should -Invoke Install-Module -Times 1 -Exactly
        Should -Invoke Get-AuthenticodeSignature -Times 3 -Exactly
        Should -Invoke Import-Module -Times 1 -Exactly
        $global:RemovalTest.ConnectScopes | Should -HaveCount 5
    }

    It 'removes the module and stops with exit code 1 before the import and the sign-in when a file fails the check' {
        $global:RemovalTest.Signatures['Microsoft.Graph.Authentication.psm1'] = New-RemovalSignature -Status 'NotSigned' -Subject ''
        & $script:ScriptPath -ShortName abcprd01 *> $null
        $LASTEXITCODE | Should -Be 1
        Should -Invoke Import-Module -Times 0 -Exactly
        $global:RemovalTest.ConnectScopes | Should -BeNullOrEmpty
        $global:RemovalTest.Deleted | Should -HaveCount 0
        Get-ChildItem -LiteralPath $global:RemovalTest.ModuleRoot -Recurse -File | Should -BeNullOrEmpty
    }

    It 'stops with exit code 1 when a script file has the signature of another publisher' {
        $global:RemovalTest.Signatures['Microsoft.Graph.Authentication.psd1'] = New-RemovalSignature -Subject 'CN=Contoso Ltd, O=Contoso Ltd, L=London, C=GB'
        & $script:ScriptPath -ShortName abcprd01 *> $null
        $LASTEXITCODE | Should -Be 1
        Should -Invoke Import-Module -Times 0 -Exactly
    }

    It 'checks no file when the module is already installed' {
        $null = New-RemovalTestModule -Name 'Microsoft.Graph.Authentication' -Version '2.38.0'
        & $script:ScriptPath -ShortName abcprd01 | Out-Null
        $LASTEXITCODE | Should -Be 0
        Should -Invoke Install-Module -Times 0 -Exactly
        Should -Invoke Get-AuthenticodeSignature -Times 0 -Exactly
    }
}

}
