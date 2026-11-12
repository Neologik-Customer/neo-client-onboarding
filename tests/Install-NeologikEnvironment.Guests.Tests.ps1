#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
<#
    Tests of the guest lookup of Install-NeologikEnvironment.ps1.

    A guest first invited under another address keeps the address that the
    kit lists in otherMails. The lookup must find that guest, so that the
    script does not invite the guest again, with an email.

    Run: pwsh -NoProfile -Command "Invoke-Pester -Path tests -CI"
#>

Describe 'Install-NeologikEnvironment.ps1 (guest lookup)' {

BeforeAll {
    $script:ScriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Install-NeologikEnvironment.ps1'

    # A stub for the Microsoft Graph cmdlet the lookup calls: a command must exist before Pester can mock it.
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        function Invoke-MgGraphRequest { [CmdletBinding()] param($Method, $Uri, $Body, $ContentType, $OutputType, $Headers) }
    }

    # The script under test: dot-sourced, so its functions are defined here and its guarded main entry does not run.
    . $script:ScriptPath

    # One guest, first invited under another address: the listed address is only in otherMails.
    $script:Users = @(
        @{ id = 'guest-1'; displayName = 'Neologik Support'; mail = 'support@earlier.example'; userPrincipalName = 'support_earlier.example#EXT#@contoso.onmicrosoft.com'; otherMails = @('support@neologik.ai', 'support@earlier.example') }
    )

    # A fake Microsoft Graph that answers the user filter the way Microsoft Graph does.
    Mock Invoke-MgGraphRequest {
        $filter = [uri]::UnescapeDataString((($Uri -split '\$filter=')[1] -split '&')[0])
        $items = @()
        if ($filter -match "^mail eq '(.+)' or userPrincipalName eq '(.+)' or otherMails/any\(m:m eq '(.+)'\)$") {
            $address = $Matches[1] -replace "''", "'"
            $items = @($script:Users | Where-Object { $_.mail -eq $address -or $_.userPrincipalName -eq $address -or (@($_.otherMails) -contains $address) } |
                ForEach-Object { @{ id = $_.id; displayName = $_.displayName } })
        }
        @{ value = $items }
    }
}

It 'finds a guest by an address that the account holds only in otherMails' {
    $user = Find-NeologikUserByEmail -Email 'support@neologik.ai'
    $user | Should -Not -BeNullOrEmpty
    $user.id | Should -Be 'guest-1'
}

It 'finds a guest by the mail address' {
    (Find-NeologikUserByEmail -Email 'support@earlier.example').id | Should -Be 'guest-1'
}

It 'returns nothing for an address that no account holds' {
    Find-NeologikUserByEmail -Email 'nobody@neologik.ai' | Should -BeNullOrEmpty
}

It 'doubles a single quote in the address in every part of the filter' {
    $null = Find-NeologikUserByEmail -Email "o'brien@neologik.ai"
    Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly -ParameterFilter {
        [uri]::UnescapeDataString($Uri) -match "mail eq 'o''brien@neologik\.ai' or userPrincipalName eq 'o''brien@neologik\.ai' or otherMails/any\(m:m eq 'o''brien@neologik\.ai'\)"
    }
}

}
