#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Tests of the descriptions that Install-NeologikEnvironment.ps1 writes into
    the directory: the description of each security group and of each
    federated credential. Each description names each object in full, in one
    or two sentences, with no abbreviation, no dash and no brackets.

    Run: pwsh -NoProfile -Command "Invoke-Pester -Path tests -CI"
#>

Describe 'Install-NeologikEnvironment.ps1 (descriptions)' {

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Install-NeologikEnvironment.ps1'

    # Stubs for the Microsoft Graph commands: a command must exist before Pester can mock it.
    function Get-MgGroup { [CmdletBinding()] param($Filter, $GroupId) }
    function New-MgGroup { [CmdletBinding()] param($DisplayName, $Description, [switch]$MailEnabled, [switch]$SecurityEnabled, $MailNickname) }
    function Update-MgGroup { [CmdletBinding()] param($GroupId, $DisplayName, $Description) }
    function Get-MgGroupMember { [CmdletBinding()] param($GroupId, $Filter) }
    function New-MgGroupMember { [CmdletBinding()] param($GroupId, $DirectoryObjectId) }
    function Invoke-MgGraphRequest { [CmdletBinding()] param($Method, $Uri, $Body, $ContentType, $Headers) }

    # The script under test: dot-sourced, so its functions are defined here and its guarded main entry does not run.
    . $script:ScriptPath

    $script:Expected = @{
        'Neologik User Group - neoabc01'        = 'This security group holds the people who use the Neologik agents of this environment. In the Neologik Admin Tool, each channel of a Neologik agent names the security group whose members can use the Neologik agent.'
        'Neologik NCE Contributors - neoabc01'  = 'Members of this security group hold the contributor role in the Neologik Admin Tool. A member can create and change the configuration of the Neologik Platform.'
        'Neologik NCE Admins - neoabc01'        = 'Members of this security group hold the administrator role in the Neologik Admin Tool. A member has full access to the Neologik Admin Tool, including the Blueprints, Audit and Admin pages.'
        'Neologik Admin User Group - neoabc01'  = 'Members of this security group administer and support the Azure resources of this Neologik Platform environment. This security group holds Azure roles on the resource group of the environment.'
    }
    $script:DeploySp = '5b0e6c1d-0000-4000-8000-000000000020'

    # The rules for each description: no abbreviation, no dash, no brackets, one or two sentences.
    function Assert-PlainDescription([string]$Text) {
        $Text | Should -Not -BeNullOrEmpty
        $Text | Should -Not -Match '\bNCE\b' -Because 'a description names each object in full'
        $Text | Should -Not -Match '\s-\s|--' -Because 'a description holds no dash'
        $Text | Should -Not -Match '[()\[\];]' -Because 'a description holds no brackets and no semicolon'
        $Text | Should -Match '\.$'
        @($Text -split '(?<=\.)\s+').Count | Should -BeLessOrEqual 2
    }

    Mock Write-Log { }
    Mock Write-Host { }
    Mock Start-Sleep { }
    Mock Import-Module { } -ParameterFilter { $Name -like 'Microsoft.Graph*' }
    Mock Get-MgGroupMember { }
    Mock New-MgGroupMember { }
    Mock Update-MgGroup { }
    Mock New-MgGroup {
        param($DisplayName, $Description)
        $script:Created += [pscustomobject]@{ Name = $DisplayName; Description = $Description }
        [pscustomobject]@{ Id = "id-$($script:Created.Count)"; DisplayName = $DisplayName }
    }
}

BeforeEach {
    $script:ConfigData = @{ SolutionShortName = 'neoabc01'; CurrentUserId = '0d6a7e21-0000-4000-8000-000000000030' }
    $script:Created = @()
    $script:Posts = @()
}

Context 'Security groups' {

    It 'creates each security group with a plain English description' {
        Mock Get-MgGroup { }
        $null = New-NeologikSecurityGroups -GuestUsers @()
        @($script:Created).Count | Should -Be 4
        foreach ($group in $script:Created) {
            $group.Description | Should -BeExactly $script:Expected[$group.Name]
            Assert-PlainDescription $group.Description
        }
        Should -Invoke Update-MgGroup -Times 0 -Exactly
    }

    It 'writes the description of this version to an existing security group that holds another description' {
        Mock Get-MgGroup {
            param($Filter)
            if ($Filter -like "*'Neologik User Group - neoabc01'*") {
                [pscustomobject]@{ Id = 'group-users'; DisplayName = 'Neologik User Group - neoabc01'; Description = 'Default Neologik users group - assign to agent channels created in the NCE' }
            }
        }
        $groups = New-NeologikSecurityGroups -GuestUsers @()
        @($groups).Count | Should -Be 4
        Should -Invoke Update-MgGroup -Times 1 -Exactly
        Should -Invoke Update-MgGroup -Times 1 -Exactly -ParameterFilter {
            $GroupId -eq 'group-users' -and -not $DisplayName -and $Description -ceq $script:Expected['Neologik User Group - neoabc01']
        }
        @($script:Created).Count | Should -Be 3
    }

    It 'writes nothing to an existing security group that already holds the description' {
        Mock Get-MgGroup {
            param($Filter)
            foreach ($name in $script:Expected.Keys) {
                if ($Filter -like "*'$name'*") { return [pscustomobject]@{ Id = "id-$name"; DisplayName = $name; Description = $script:Expected[$name] } }
            }
        }
        $null = New-NeologikSecurityGroups -GuestUsers @()
        Should -Invoke Update-MgGroup -Times 0 -Exactly
        Should -Invoke New-MgGroup -Times 0 -Exactly
    }

    It 'reports a warning and continues when the update of a description fails' {
        Mock Get-MgGroup {
            param($Filter)
            if ($Filter -like "*'Neologik Admin User Group - neoabc01'*") {
                [pscustomobject]@{ Id = 'group-admin'; DisplayName = 'Neologik Admin User Group - neoabc01'; Description = 'Users who will administer and support the resources' }
            }
        }
        Mock Update-MgGroup { throw 'Authorization_RequestDenied' }
        $groups = New-NeologikSecurityGroups -GuestUsers @()
        @($groups).Count | Should -Be 4
        Should -Invoke Write-Log -ParameterFilter { $Level -eq 'Warning' -and $Message -like "*could not update the description of the security group 'Neologik Admin User Group - neoabc01'*" }
    }

    It 'renames a contributors group that holds a former name, and writes the description in the same call' {
        # The rename keeps the environment of a customer onboarded before version 5 working after an upgrade.
        Mock Get-MgGroup {
            param($Filter, $GroupId)
            if ($GroupId) { return [pscustomobject]@{ Id = $GroupId; DisplayName = 'Neologik NCE Contributors - neoabc01'; Description = $script:Expected['Neologik NCE Contributors - neoabc01'] } }
            if ($Filter -like "*'Neologik NCE User Group - neoabc01'*") { return [pscustomobject]@{ Id = 'group-former'; DisplayName = 'Neologik NCE User Group - neoabc01'; Description = 'NCE user group' } }
        }
        $null = New-NeologikSecurityGroups -GuestUsers @()
        Should -Invoke Update-MgGroup -Times 1 -Exactly
        Should -Invoke Update-MgGroup -Times 1 -Exactly -ParameterFilter {
            $GroupId -eq 'group-former' -and $DisplayName -eq 'Neologik NCE Contributors - neoabc01' -and $Description -ceq $script:Expected['Neologik NCE Contributors - neoabc01']
        }
        @($script:Created).Count | Should -Be 3
    }
}

Context 'Federated credentials' {

    It 'adds the federated credential of the deployment identity with a plain English description' {
        Mock Invoke-MgGraphRequest {
            param($Method, $Uri, $Body)
            if ($Method -eq 'POST') { $script:Posts += [pscustomobject]@{ Uri = $Uri; Body = ($Body | ConvertFrom-Json) }; return }
            if ($Uri -like '*federatedIdentityCredentials*') { return @{ value = @() } }
            if ($Uri -like '*applications*filter*') { return @{ value = @(@{ id = 'deployment-application' }) } }
        }
        $null = Set-NeologikDeploymentCredential -ClientId '6f1c2d3e-0000-4000-8000-000000000010' -EnvironmentName 'abcprd'
        @($script:Posts).Count | Should -Be 1
        $script:Posts[0].Body.name | Should -Be 'github-deployments-abcprd'
        $script:Posts[0].Body.description | Should -BeExactly 'This federated credential lets a Neologik deployment run for the environment abcprd sign in as the deployment identity with no stored secret. The federated credential adds no permission.'
        Assert-PlainDescription $script:Posts[0].Body.description
    }

    It 'adds one federated credential for each repository to the agent identity blueprint, each with a plain English description' {
        Mock Grant-GraphAppRolePermissions { }
        Mock Invoke-MgGraphRequest {
            param($Method, $Uri, $Body)
            if ($Method -eq 'POST') { $script:Posts += [pscustomobject]@{ Uri = $Uri; Body = ($Body | ConvertFrom-Json) }; return @{} }
            switch -Wildcard ($Uri) {
                '*sponsors*' { return @{ value = @(@{ id = 'sponsor'; displayName = 'Global Administrator' }) } }
                '*owners*' { return @{ value = @(@{ id = $script:DeploySp }) } }
                '*federatedIdentityCredentials*' { return @{ value = @() } }
                '*servicePrincipals*filter*' { return @{ value = @(@{ id = 'blueprint-principal' }) } }
                '*applications*filter*' { return @{ value = @(@{ id = 'blueprint-object'; appId = 'blueprint-application' }) } }
            }
        }
        $null = New-NeologikAgentBlueprint -DeploySpObjectId $script:DeploySp -SponsorUserId 'sponsor'
        $credentials = @($script:Posts | Where-Object { $_.Uri -like '*federatedIdentityCredentials' })
        @($credentials | ForEach-Object { $_.Body.name }) | Should -Be @('github-oidc-neo-infrastructure', 'github-oidc-neo-bot-service', 'github-oidc-neo-env-config')
        foreach ($credential in $credentials) {
            $repository = $credential.Body.name -replace '^github-oidc-', ''
            $credential.Body.description | Should -BeExactly "This federated credential lets a Neologik deployment run in the Neologik GitHub repository $repository sign in as this agent identity blueprint with no stored secret. The Neologik deployment then creates the agent identities and the agent users of this environment."
            Assert-PlainDescription $credential.Body.description
        }
    }
}

}
