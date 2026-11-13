<#
.SYNOPSIS
    Prepares an Azure subscription and a Microsoft Entra tenant for one Neologik
    Platform environment.

.DESCRIPTION
    A Global Administrator who is also Owner of the subscription runs the script once.

    The script works in these steps:
    1. The script checks the PowerShell version and the PowerShell modules.
    2. The script signs in to Azure and to Microsoft Graph with the account of the
       administrator.
    3. The script checks the Owner role and the Global Administrator role.
    4. The script registers the five Azure resource providers that the script needs
       for the resources that the script creates.
    5. The script invites the Neologik support accounts as guests, when the
       administrator chooses invitation.
    6. The script creates the resource group, the security groups, the deployment
       identity, the Key Vault, the Platform Sign-in application, the agent identity
       blueprint, the deployment storage account and three managed identities. The
       script assigns the roles of each. The script adds one federated credential to
       the deployment identity.
    7. The script registers the other Azure resource providers and the preview
       features that the Neologik Platform requires, and confirms every registration.
    8. The script writes a configuration file and a log.

    README.md describes how to run the script.
    docs\QUICK-REFERENCE.md lists each change and each permission.

.PARAMETER OrganizationCode
    The organisation code of three characters, for example 'abc'. Without this
    parameter, the script asks for the organisation code.

.PARAMETER EnvironmentType
    The environment type: 'dev' or 'prd'. Default: 'dev'.

.PARAMETER AzureRegion
    The Azure region for the resources. Default: 'uksouth'.

.PARAMETER TenantId
    The tenant to sign in to. Default: the tenant of the sign-in.

.PARAMETER SubscriptionName
    The name of the Azure subscription to use. With this parameter, the script
    selects the subscription after the sign-in. The script stops when the account
    cannot see the subscription. Without this parameter, the script uses the
    subscription of the sign-in. A resumed run uses the subscription from the
    checkpoint.

.PARAMETER KeyVaultName
    A name of your choice for the Key Vault. Without this parameter, the script uses
    the standard name 'kv<short name>', for example kvabcprd01.
    Rules for the name: 3 to 24 characters. Letters, digits and hyphens. The first
    character is a letter. The last character is a letter or a digit.

.PARAMETER SkipPowerShellUpdate
    The script does not check the PowerShell version.

.PARAMETER SkipModuleInstall
    The script does not check the PowerShell modules.

.PARAMETER SkipGuestInvitation
    The script invites no Neologik guest user. Use this parameter when you create
    accounts for Neologik support staff in your own tenant. The script still creates
    the security groups, with the signed-in user as a member.

    The key 'skipGuestInvitation' in the answer file has the same effect. When both
    are given, the parameter decides.

    When the administrator accepts invitation at the question, the script lists the
    addresses in NeologikGuestUsers.txt. The administrator can then type further
    addresses, one on each line. An unattended run uses the addresses in
    NeologikGuestUsers.txt only.

    When the administrator declines invitation, the script asks whether to add
    existing accounts to the security groups. The script sends no invitation. The
    keys in the answer file are 'addExistingAccountsToGroups' and
    'existingAccountEmails'. Each address must match the mail address or the user
    principal name of an account. The script reports an address that matches no
    account and continues. Each account added in this way joins all four Neologik
    security groups. One of the four is the Admin User Group.

.PARAMETER ExistingServicePrincipalObjectId
    The object ID of the enterprise application of a deployment service principal
    that you created. Do not give the application ID or the client ID.

    With this parameter, the script creates no application registration, no service
    principal and no client secret. The script assigns the Azure roles and the
    Microsoft Graph application permissions to the deployment service principal that
    you name.

    The keys 'useExistingServicePrincipal' and 'existingServicePrincipalObjectId' in
    the answer file have the same effect. When both are given, the parameter
    decides. Without the parameter and without the keys, the script asks.

.PARAMETER ExistingServicePrincipalSecret
    The client secret of the deployment service principal that you created. The
    script stores the client secret in the Key Vault, as the secret
    'neologik-deployment-service-principle-secret'.

    Without this parameter, the script stores no client
    secret. Add the client secret to the Key Vault before the first deployment.

    The key 'existingServicePrincipalSecret' in the answer file has the same effect.
    Prefer the parameter, which keeps the client secret out of the answer file.

.PARAMETER AnswerFile
    The path of a JSON file of answers. Default: 'inputs.json' in the folder of the
    script.

.PARAMETER NonInteractive
    The script runs without questions.

    The answer file must hold the organisation code, the organisation name and the
    host name. The script takes each answer from a switch or from the answer file.
    The script stops when an answer is missing.

    Give -AcceptTerms to accept the terms. The caller signs in to Azure and to
    Microsoft Graph before the caller starts the script. The script uses both
    sessions. When an earlier run left a checkpoint, the script stops with an error,
    unless -FreshRun is given.

    Azure requires multi-factor authentication for every write. The Azure session of
    a user must therefore hold the 'p1' authentication-context claim. To obtain the
    claim, sign in with Connect-AzAccount -ClaimsChallenge. With -NonInteractive,
    the script shows a warning when the claim is absent. The script does not sign in
    again.

.PARAMETER AcceptTerms
    Accepts the Neologik Terms of Use and the Privacy Policy in an unattended run.
    Terms of Use: https://www.neologik.ai/terms
    Privacy Policy: https://www.neologik.ai/privacy-policy
    Required with -NonInteractive. The script writes the acceptance to the log.

.PARAMETER FreshRun
    The script deletes the checkpoint of an earlier run without a question and
    starts again.

.EXAMPLE
    .\Install-NeologikEnvironment.ps1

.EXAMPLE
    .\Install-NeologikEnvironment.ps1 -OrganizationCode "abc" -EnvironmentType "prd" -AzureRegion "ukwest"

.EXAMPLE
    # An unattended run. The caller has signed in to Azure and to Microsoft Graph in the same session.
    .\Install-NeologikEnvironment.ps1 -NonInteractive -AcceptTerms -FreshRun `
        -AnswerFile .\inputs.json -SkipPowerShellUpdate -SkipModuleInstall

.NOTES
    Requires: PowerShell 7.4 or later
    Requires: Owner on the subscription and Global Administrator in the tenant
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OrganizationCode = "",

    [Parameter(Mandatory = $false)]
    # Neologik reserves the values 'dmo', 'test' and 'stg' for environments that Neologik operates.
    [ValidateSet('dev', 'prd', 'dmo', 'test', 'stg')]
    [string]$EnvironmentType = "dev",

    [Parameter(Mandatory = $false)]
    [string]$AzureRegion = "uksouth",

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionName,

    [Parameter(Mandatory = $false)]
    [ValidateLength(3, 24)]
    [ValidatePattern('^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$')]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $false)]
    [switch]$SkipPowerShellUpdate,

    [Parameter(Mandatory = $false)]
    [switch]$SkipModuleInstall,

    [Parameter(Mandatory = $false)]
    [switch]$SkipGuestInvitation,

    [Parameter(Mandatory = $false)]
    [string]$ExistingServicePrincipalObjectId,

    [Parameter(Mandatory = $false)]
    [string]$ExistingServicePrincipalSecret,

    # The path of a JSON file of answers. Each answer becomes the default value of the matching question.
    # Without this parameter, the script uses the file 'inputs.json' in the folder of the script, when the file exists.
    [Parameter(Mandatory = $false)]
    [string]$AnswerFile = "",

    # The script runs without questions and requires a complete answer file. The script takes each
    # answer from a switch or from the answer file. The script stops when an answer is missing.
    [Parameter(Mandatory = $false)]
    [switch]$NonInteractive,

    # Accepts the Neologik Terms of Use and the Privacy Policy in an unattended run.
    # Required with -NonInteractive. The script writes the acceptance to the log.
    [Parameter(Mandatory = $false)]
    [switch]$AcceptTerms,

    # The script deletes the checkpoint of an earlier run without a question and starts again.
    # In an unattended run without -FreshRun, a checkpoint of an earlier run stops the script.
    [Parameter(Mandatory = $false)]
    [switch]$FreshRun
)

# Script variables
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
$WarningPreference = 'Continue'

# Script version
$script:Version = 'v5.0.15'

# The version of the onboarding kit. The script records the version on the resource group, in the tag NeologikOnboardingKit.
# The configuration file records the same version, in the field KitVersion.
$script:KitVersion = 'v5.2.0'

# The third role of the deployment identity on the subscription: Role Based Access
# Control Administrator, limited by a condition to two roles, for service principals
# only. The deployment runs the ingress controller of a Private Endpoint environment
# with Application Gateway for Containers. Microsoft requires the identity of that
# controller to hold Reader on the resource group that Azure Kubernetes Service creates
# for the nodes of the cluster, which is outside the resource group of the environment.
# The platform's configuration API reads the daily cost of the resource group
# of the nodes for the return on investment report, so the deployment assigns
# Cost Management Reader on that resource group to the identity of the
# configuration API. The condition lets the deployment identity assign those two
# roles and no other role, and remove only those two.
$script:LimitedSubRole = 'Role Based Access Control Administrator'
$script:LimitedSubRoleId = 'f58310d9-a9f6-439a-9e8d-f62e7b41a168'
# Reader, then Cost Management Reader.
$script:LimitedSubRoleAssignableIds = @(
    'acdd72a7-3385-48ef-bd42-f606fba81ae7',
    '72fafb9e-0641-4937-9268-a91bfd8191a3'
)
$script:LimitedSubRoleConditionVersion = '2.0'
$script:LimitedSubRoleCondition = ("((!(ActionMatches{{'Microsoft.Authorization/roleAssignments/write'}})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {{{0}}} AND @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {{'ServicePrincipal'}})) AND ((!(ActionMatches{{'Microsoft.Authorization/roleAssignments/delete'}})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {{{0}}} AND @Resource[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {{'ServicePrincipal'}}))" -f ($script:LimitedSubRoleAssignableIds -join ', '))

# Role Based Access Control Administrator on the resource group of the environment, held by
# the system task managed identity. The condition stops the managed identity assigning or removing
# Owner, User Access Administrator or Role Based Access Control Administrator. The managed identity
# can assign or remove every other role for service principals only. The deployment identity holds
# Role Based Access Control Administrator on the resource group without a condition.
# Owner, User Access Administrator, then Role Based Access Control Administrator.
$script:ResourceGroupRoleExcludedIds = @(
    '8e3af657-a8ff-443c-a75c-2fe8c4bcb635',
    '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9',
    'f58310d9-a9f6-439a-9e8d-f62e7b41a168'
)
$script:ResourceGroupRoleCondition = ("((!(ActionMatches{{'Microsoft.Authorization/roleAssignments/write'}})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {{{0}}} AND @Request[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {{'ServicePrincipal'}})) AND ((!(ActionMatches{{'Microsoft.Authorization/roleAssignments/delete'}})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {{{0}}} AND @Resource[Microsoft.Authorization/roleAssignments:PrincipalType] ForAnyOfAnyValues:StringEqualsIgnoreCase {{'ServicePrincipal'}}))" -f ($script:ResourceGroupRoleExcludedIds -join ', '))

# The time stamp of the run. The names of the log and of the configuration file hold the time stamp.
$script:FileTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogFile = Join-Path $PSScriptRoot "NeologikOnboarding_$($script:FileTimestamp).log"
$script:OutputFile = Join-Path $PSScriptRoot "NeologikConfiguration_$($script:FileTimestamp).json"
$script:ConfigData = @{}
$script:CompletedSteps = [System.Collections.Generic.List[string]]::new()
$script:ProviderRegistrations = @{}
$script:CheckpointFile = Join-Path $PSScriptRoot "NeologikCheckpoint.json"
$script:CheckpointRegionAbbrev = $null

# The tags for the resources. The script builds the tags once, after the administrator confirms
# the configuration. The value is $null before that point, and when the administrator chooses no tags.
$script:ResourceTagsCache = $null

# A name of your choice for the Key Vault. The script records whether this run gave -KeyVaultName.
# A resumed run uses the name from the checkpoint.
# A resumed run that gives -KeyVaultName uses the name from the parameter.
$script:KeyVaultNameFromCli = $PSBoundParameters.ContainsKey('KeyVaultName')
$script:KeyVaultNameOverride = if ($script:KeyVaultNameFromCli) { $KeyVaultName } else { $null }

# Records whether this run gave -SkipGuestInvitation. Without the parameter, the decision comes
# from the key 'skipGuestInvitation' in the answer file. Without the key, the script asks.
$script:SkipGuestInvitationFromCli = $PSBoundParameters.ContainsKey('SkipGuestInvitation')

# The settings of an unattended run. Script scope lets every function read the settings.
$script:NonInteractiveMode = $NonInteractive.IsPresent
$script:AcceptTermsFromCli = $AcceptTerms.IsPresent
$script:FreshRunMode = $FreshRun.IsPresent

# The client secret of a deployment service principal that you created. The script holds the client secret
# here and not in ConfigData. The checkpoint and the configuration file therefore never hold the client secret. The value is empty on a resumed run.
$script:ExistingSpSecretResolved = ""

# The addresses of the Neologik guest users, read from NeologikGuestUsers.txt
$script:GuestUsersFile = Join-Path $PSScriptRoot "NeologikGuestUsers.txt"
if (Test-Path $script:GuestUsersFile) {
    $script:NeologikGuestUsers = @(Get-Content $script:GuestUsersFile | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\s*#' })
} else {
    Write-Warning "NeologikGuestUsers.txt not found at: $script:GuestUsersFile. The file is part of the onboarding kit. A run with questions asks for the file during configuration. An unattended run invites no guest user."
    $script:NeologikGuestUsers = @()
}

# The PowerShell modules that the script requires
$script:RequiredModules = @(
    # Az.Accounts 5.2.0 is the first version in which Connect-AzAccount accepts -ClaimsChallenge.
    # The sign-in needs -ClaimsChallenge to meet the multi-factor authentication requirement of Azure.
    @{ Name = 'Az.Accounts'; MinVersion = '5.2.0' },
    @{ Name = 'Az.Resources'; MinVersion = '7.0.0' },
    @{ Name = 'Az.Compute'; MinVersion = '7.0.0' },
    @{ Name = 'Az.KeyVault'; MinVersion = '5.0.0' },
    @{ Name = 'Az.Storage'; MinVersion = '6.0.0' },
    @{ Name = 'Az.ManagedServiceIdentity'; MinVersion = '1.0.0' },
    @{ Name = 'Microsoft.Graph'; MinVersion = '2.0.0' }
)

# The file types that the signature check of a module reads. Microsoft Corporation publishes each
# required module and signs each script file of the module. A module also holds libraries that other
# publishers sign, for example Json.NET. A library needs a valid signature of any publisher.
$script:ModuleScriptExtensions = @('.ps1', '.psm1', '.psd1', '.ps1xml', '.cdxml')
$script:ModuleLibraryExtensions = @('.dll', '.exe')

# Azure requires multi-factor authentication for every create, update and delete. This
# claims challenge requests the 'p1' authentication-context claim at the sign-in. The
# Azure Resource Manager token then meets the requirement. The value decodes to
# {"access_token":{"acrs":{"essential":true,"values":["p1"]}}}. Microsoft documents the
# value. The value is not a secret.
$script:ArmMfaClaimsChallenge = 'eyJhY2Nlc3NfdG9rZW4iOnsiYWNycyI6eyJlc3NlbnRpYWwiOnRydWUsInZhbHVlcyI6WyJwMSJdfX19'

#region Logging Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes a message to the log file and to the console. With -LogFileOnly, to the log file only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info',

        [Parameter(Mandatory = $false)]
        [switch]$LogFileOnly
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"

    # Write to log file
    try {
        Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction Stop
    }
    catch {
        Write-Warning "The script could not write to the log file: $_"
    }

    if ($LogFileOnly) { return }

    # Write to console. An error message goes to the console in red and throws nothing.
    # Write-Error would throw, because $ErrorActionPreference is 'Stop', and the messages that
    # follow an error message would never print. Each caller stops explicitly.
    switch ($Level) {
        'Info' { Write-Information $Message }
        'Warning' { Write-Warning $Message }
        'Error' { Write-Host $Message -ForegroundColor Red }
        'Success' { Write-Host $Message -ForegroundColor Green }
    }
}

function Initialize-ConfigurationFile {
    <#
    .SYNOPSIS
        Sets the name of the configuration file from the organisation code and the
        environment index. The script calls the function when the environment index
        is known.
    #>
    [CmdletBinding()]
    param()

    # The name of the configuration file holds the organisation code and the environment index.
    $configFileName = "Neologik_$($script:OrganizationCode)$($script:EnvironmentIndex)_Configuration_$($script:FileTimestamp).json"
    $script:OutputFile = Join-Path $PSScriptRoot $configFileName
    
    Write-Host "  [OK] Name of the configuration file: $configFileName" -ForegroundColor Green
    Write-Log "Path of the configuration file: $($script:OutputFile)" -Level Info
}

function Write-ScriptHeader {
    $header = @"

+===============================================================+
|                                                               |
|          NEOLOGIK ONBOARDING SCRIPT                           |
|          $script:Version                                               |
|                                                               |
+===============================================================+

"@
    Write-Host $header -ForegroundColor Cyan
    Write-Log "Starting the Neologik onboarding script, version $script:Version" -Level Info
}

function Show-TermsAndConditions {
    <#
    .SYNOPSIS
        Shows the terms and asks the administrator to accept the terms.
    #>
    [CmdletBinding()]
    param()

    $terms = @"

===============================================================
                    TERMS AND CONDITIONS
===============================================================

By proceeding with this installation, you acknowledge and agree to

    NEOLOGIK TERMS OF USE AND PRIVACY POLICY

   - Terms of Use: https://www.neologik.ai/terms
   - Privacy Policy: https://www.neologik.ai/privacy-policy
   - You must read and accept both documents to proceed

===============================================================

"@

    Write-Host $terms -ForegroundColor Yellow

    if ($script:NonInteractiveMode) {
        if ($script:AcceptTermsFromCli) {
            Write-Log "The terms were accepted with -AcceptTerms in an unattended run" -Level Info
            Write-Host "`n[OK] Terms accepted with -AcceptTerms. The script continues...`n" -ForegroundColor Green
            return $true
        }
        throw "An unattended run requires -AcceptTerms, to accept the Neologik Terms of Use and the Privacy Policy."
    }

    Write-Host "Do you accept the Neologik Terms of Use and the Privacy Policy? " -NoNewline -ForegroundColor Cyan
    Write-Host "Type 'I ACCEPT' to continue, or 'N' to stop: " -NoNewline -ForegroundColor Cyan
    $acceptance = Read-Host
    
    if ($acceptance -eq 'I ACCEPT') {
        Write-Log "The administrator accepted the terms" -Level Info
        Write-Host "`n[OK] Terms accepted. The script continues...`n" -ForegroundColor Green
        return $true
    }
    else {
        Write-Log "The administrator declined the terms" -Level Warning
        Write-Host "`n[X] Terms not accepted. The script stops.`n" -ForegroundColor Red
        return $false
    }
}

#endregion

#region Checkpoint Management

function Find-LatestCheckpoint {
    <#
    .SYNOPSIS
        Returns the checkpoint file when the checkpoint file exists in the folder of
        the script.
    #>
    if (Test-Path $script:CheckpointFile) { return Get-Item $script:CheckpointFile }
    return $null
}

function Save-Checkpoint {
    <#
    .SYNOPSIS
        Saves the state of the run to the checkpoint file. A later run can then resume.
    #>
    [CmdletBinding()]
    param([string]$Label = 'progress')

    if (-not $script:CheckpointFile) { return }

    $state = [ordered]@{
        Version               = $script:Version
        SavedAt               = (Get-Date -Format 'o')
        Label                 = $Label
        CompletedSteps        = @($script:CompletedSteps)
        ProviderRegistrations = $script:ProviderRegistrations
        RegionAbbrev          = $script:CheckpointRegionAbbrev
        ConfigData            = $script:ConfigData
        OrganizationCode      = $script:OrganizationCode
        EnvironmentType       = $script:EnvironmentType
        AzureRegion           = $script:AzureRegion
        OrganizationName      = $script:OrganizationName
        HostName              = $script:HostName
        ResourceGroupName     = $script:ResourceGroupName
        EnvironmentIndex      = $script:EnvironmentIndex
        OutputFile            = $script:OutputFile
        KeyVaultNameOverride  = $script:KeyVaultNameOverride
    }

    try {
        $state | ConvertTo-Json -Depth 10 | Set-Content -Path $script:CheckpointFile -Encoding UTF8
    }
    catch {
        Write-Warning "The script could not save the checkpoint: $_"
    }
}

function Restore-Checkpoint {
    <#
    .SYNOPSIS
        Restores the state of the run from a checkpoint file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        $data = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning "The script cannot read the checkpoint file: $_"
        Write-Host "`n  [!] The script could not read the checkpoint. The script starts a new run." -ForegroundColor Yellow
        return $false
    }

    # Restore ConfigData as a hashtable
    $script:ConfigData = @{}
    foreach ($prop in $data.ConfigData.PSObject.Properties) {
        $script:ConfigData[$prop.Name] = $prop.Value
    }

    # Restore ProviderRegistrations as a hashtable
    $script:ProviderRegistrations = @{}
    if ($data.ProviderRegistrations) {
        foreach ($prop in $data.ProviderRegistrations.PSObject.Properties) {
            $script:ProviderRegistrations[$prop.Name] = $prop.Value
        }
    }

    # Restore CompletedSteps
    $script:CompletedSteps = [System.Collections.Generic.List[string]]::new()
    foreach ($step in $data.CompletedSteps) {
        $script:CompletedSteps.Add([string]$step)
    }

    # Restore named script variables
    $script:OrganizationCode       = $data.OrganizationCode
    $script:EnvironmentType        = $data.EnvironmentType
    $script:AzureRegion            = $data.AzureRegion
    $script:OrganizationName       = $data.OrganizationName
    # A checkpoint can hold the host name as two separate parts: the host and the domain.
    $script:HostName               = if ($data.HostName) { $data.HostName }
                                     elseif ($data.Hostname -and $data.DomainName) { "$($data.Hostname).$($data.DomainName)" }
                                     else { $data.HostName }
    $script:ResourceGroupName      = $data.ResourceGroupName
    $script:EnvironmentIndex       = $data.EnvironmentIndex
    $script:CheckpointRegionAbbrev = $data.RegionAbbrev
    # Keep the file name only, and use the folder of this script. Another computer may have
    # written the checkpoint, and a path from another computer is not valid here.
    $script:OutputFile             = if ($data.OutputFile) { Join-Path $PSScriptRoot (Split-Path -Leaf $data.OutputFile) }
                                     else { $script:OutputFile }

    # Use the Key Vault name from the checkpoint. When this run gives -KeyVaultName,
    # use the name from the parameter.
    if (-not $script:KeyVaultNameFromCli -and -not [string]::IsNullOrWhiteSpace($data.KeyVaultNameOverride)) {
        $script:KeyVaultNameOverride = $data.KeyVaultNameOverride
    }
}

function Complete-OnboardingStep {
    <#
    .SYNOPSIS
        Records in the checkpoint that a step is complete.
    #>
    [CmdletBinding()]
    param([string]$StepName)
    if (-not $script:CompletedSteps.Contains($StepName)) {
        $script:CompletedSteps.Add($StepName)
    }
    Save-Checkpoint -Label $StepName
}

#endregion

#region Resource Tagging

function ConvertTo-NeologikCustomTags {
    <#
    .SYNOPSIS
        Reads custom resource tags into a hashtable. The function accepts a string of
        'key=value' pairs separated by commas. The function also accepts an object
        from the answer file or from the checkpoint. The function throws when a key
        or a value is not valid. The caller can then show a warning or ask again.
        A key holds letters, digits, '.', '_' and '-'. A value holds no ',' and no '='.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Value
    )

    $tags = @{}
    if ($null -eq $Value) { return $tags }

    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) { $tags[[string]$key] = [string]$Value[$key] }
    }
    elseif ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($prop in $Value.PSObject.Properties) { $tags[[string]$prop.Name] = [string]$prop.Value }
    }
    else {
        $text = ([string]$Value).Trim()
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            foreach ($pair in ($text -split ',')) {
                $trimmed = $pair.Trim()
                if ([string]::IsNullOrWhiteSpace($trimmed)) { throw "Empty tag entry. Use key=value pairs separated by commas." }
                $parts = $trimmed -split '=', 2
                if ($parts.Count -ne 2) { throw "Tag '$trimmed' must have the form key=value." }
                $tags[$parts[0].Trim()] = $parts[1].Trim()
            }
        }
    }

    foreach ($key in @($tags.Keys)) {
        if ($key -notmatch '^[a-zA-Z0-9._-]+$') { throw "Tag key '$key' is not valid. Use letters, digits, '.', '_' and '-' only." }
        if ("$($tags[$key])" -match '[,=]') { throw "The tag value for '$key' must hold no ',' and no '='." }
    }

    return $tags
}

function Get-NeologikResourceTags {
    <#
    .SYNOPSIS
        Returns the tags for the Azure resources that the script creates. Returns $null
        when the administrator chooses no tags. The function builds the tags once, so
        that every resource receives the same tags. A custom tag replaces a standard
        tag of the same name.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ConfigData['ResourceTagsEnabled']) { return $null }
    if ($null -ne $script:ResourceTagsCache) { return $script:ResourceTagsCache }

    $tags = @{
        'Vendor'          = 'Neologik'
        'ApplicationName' = 'NeologikPlatform'
        'ManagedBy'       = 'NeologikOnboarding'
        'Environment'     = "$($script:OrganizationCode)$($script:EnvironmentType)"
        'Solution'        = [string]$script:ConfigData['SolutionShortName']
        'DeploymentDate'  = (Get-Date -Format 'yyyy-MM-dd')
    }

    # A custom tag replaces a standard tag of the same name. The checkpoint holds the tags
    # as an object. ConvertTo-NeologikCustomTags accepts a string and an object.
    foreach ($entry in (ConvertTo-NeologikCustomTags $script:ConfigData['ResourceTagsCustom']).GetEnumerator()) {
        $tags[[string]$entry.Key] = [string]$entry.Value
    }

    $script:ResourceTagsCache = $tags
    return $tags
}

function Set-NeologikKitVersionTag {
    <#
    .SYNOPSIS
        Records the version of the onboarding kit on the resource group, in the tag
        NeologikOnboardingKit. The function adds the tag and keeps every existing tag.
        The function writes the tag even when the administrator chooses no tags. The
        Neologik Platform reads the tag before an upgrade.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceId
    )

    Write-Log "Recording version $($script:KitVersion) of the onboarding kit on the resource group, in the tag NeologikOnboardingKit..." -Level Info
    Update-AzTag -ResourceId $ResourceId -Tag @{ NeologikOnboardingKit = $script:KitVersion } -Operation Merge -ErrorAction Stop | Out-Null
    Write-Log "Version of the onboarding kit recorded" -Level Success
}

#endregion

#region Signature Checks

function Get-NeologikSignatureProblem {
    <#
    .SYNOPSIS
        Checks the Authenticode signature of one file. Returns an empty string when the
        file passes the check. Otherwise returns the reason.
    .DESCRIPTION
        A file passes when Windows reports a valid signature. With -MicrosoftOnly, the
        certificate that signed the file must also name the organisation Microsoft
        Corporation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [switch]$MicrosoftOnly
    )

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    switch ([string]$signature.Status) {
        'Valid' { }
        'NotSigned' { return 'the file has no signature' }
        'HashMismatch' { return 'the file changed after the publisher signed the file' }
        default { return "Windows reports the signature status $($signature.Status)" }
    }
    $subject = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
    if ($MicrosoftOnly -and $subject -notmatch '(^|,)\s*O=Microsoft Corporation\s*(,|$)') {
        return "the signer is not Microsoft Corporation. The certificate names $subject"
    }
    return ''
}

function Test-NeologikManifestLoadsNoCode {
    <#
    .SYNOPSIS
        Returns $true when a module manifest loads no code: no root module, no
        nested module, no assembly, no script, no type file and no format file. The
        function reads the manifest as data and runs nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $data = Import-PowerShellDataFile -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        return $false
    }
    foreach ($key in @('RootModule', 'ModuleToProcess', 'NestedModules', 'RequiredAssemblies', 'ScriptsToProcess', 'TypesToProcess', 'FormatsToProcess')) {
        if ($data.ContainsKey($key) -and @($data[$key] | Where-Object { $_ }).Count -gt 0) {
            return $false
        }
    }
    return $true
}

function Test-NeologikReferenceAssembly {
    <#
    .SYNOPSIS
        Returns $true when a library is a reference assembly. .NET refuses to run the code
        of a reference assembly. The function reads the metadata of the file and runs
        nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $stream = $null
    $peReader = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $peReader = [System.Reflection.PortableExecutable.PEReader]::new($stream)
        if (-not $peReader.HasMetadata) { return $false }
        $reader = [System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($peReader)
        if (-not $reader.IsAssembly) { return $false }
        foreach ($handle in $reader.GetAssemblyDefinition().GetCustomAttributes()) {
            $attribute = $reader.GetCustomAttribute($handle)
            if ($attribute.Constructor.Kind -ne [System.Reflection.Metadata.HandleKind]::MemberReference) { continue }
            $constructor = $reader.GetMemberReference([System.Reflection.Metadata.MemberReferenceHandle]$attribute.Constructor)
            if ($constructor.Parent.Kind -ne [System.Reflection.Metadata.HandleKind]::TypeReference) { continue }
            $type = $reader.GetTypeReference([System.Reflection.Metadata.TypeReferenceHandle]$constructor.Parent)
            if ($reader.GetString($type.Namespace) -eq 'System.Runtime.CompilerServices' -and $reader.GetString($type.Name) -eq 'ReferenceAssemblyAttribute') {
                return $true
            }
        }
        return $false
    }
    catch {
        # A file that is not a .NET library counts as no reference assembly. So does a file that this version of PowerShell cannot read.
        return $false
    }
    finally {
        if ($peReader) { $peReader.Dispose() }
        if ($stream) { $stream.Dispose() }
    }
}

function Get-NeologikRequiredModuleList {
    <#
    .SYNOPSIS
        Returns each entry of RequiredModules in a module manifest. The function parses
        the manifest and reads only the value of RequiredModules, as data. The function
        can therefore read a manifest whose other values depend on the edition of
        PowerShell. The function runs nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) {
        throw "the manifest does not parse: $(@($errors)[0].Message)"
    }
    $table = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $false)
    if (-not $table) {
        throw 'the manifest holds no table of values'
    }
    foreach ($pair in $table.KeyValuePairs) {
        if ([string]$pair.Item1.SafeGetValue() -ne 'RequiredModules') { continue }
        $value = if ($pair.Item2 -is [System.Management.Automation.Language.PipelineBaseAst]) { $pair.Item2.GetPureExpression() } else { $null }
        if (-not $value) {
            throw 'the value of RequiredModules is not data'
        }
        return @($value.SafeGetValue() | Where-Object { $_ })
    }
    return @()
}

function Get-NeologikModuleSignatureProblem {
    <#
    .SYNOPSIS
        Checks the Authenticode signature of each script file and each library of one
        installed module. Returns one line for each file that fails the check.
    .DESCRIPTION
        Each script file must have a valid signature of Microsoft Corporation. Each
        library must have a valid signature of any publisher. A reference assembly with
        no signature passes, because .NET refuses to run the code of a reference
        assembly. A module whose only file is a manifest that loads no code passes
        without a signature. The module Microsoft.Graph is such a module: the manifest
        names the Microsoft Graph modules, and the script checks each of those modules.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$ModuleBase
    )

    $extensions = $script:ModuleScriptExtensions + $script:ModuleLibraryExtensions
    $files = @(Get-ChildItem -LiteralPath $ModuleBase -Recurse -File -ErrorAction Stop |
        Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() })
    $problems = @()

    foreach ($file in $files) {
        $isLibrary = $script:ModuleLibraryExtensions -contains $file.Extension.ToLowerInvariant()
        $problem = Get-NeologikSignatureProblem -Path $file.FullName -MicrosoftOnly:(-not $isLibrary)
        if (-not $problem) { continue }

        # A manifest with no signature passes when the manifest is the only file of the module and loads no code.
        if ($files.Count -eq 1 -and $file.Name -eq "$Name.psd1" -and
            [string](Get-AuthenticodeSignature -LiteralPath $file.FullName).Status -eq 'NotSigned' -and
            (Test-NeologikManifestLoadsNoCode -Path $file.FullName)) {
            Write-Log "The manifest of the module $Name $Version loads no code and has no signature. The script checks each module that the manifest names" -Level Info
            continue
        }

        # .NET refuses to run the code of a reference assembly, so a reference assembly with no signature passes.
        if ($isLibrary -and
            [string](Get-AuthenticodeSignature -LiteralPath $file.FullName).Status -eq 'NotSigned' -and
            (Test-NeologikReferenceAssembly -Path $file.FullName)) {
            Write-Log "The library $($file.FullName) of the module $Name $Version is a reference assembly with no signature. .NET runs no code of a reference assembly" -Level Info
            continue
        }

        $problems += "the module $Name $Version, file $($file.FullName): $problem"
    }
    return $problems
}

function Find-NeologikInstalledModule {
    <#
    .SYNOPSIS
        Returns the installed module at a required version, or the newest installed
        version at or above a minimum version. Returns nothing when no installed version
        matches.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$MinimumVersion,

        [Parameter(Mandatory = $false)]
        [string]$RequiredVersion
    )

    $modules = @(Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue)
    if ($RequiredVersion) {
        $modules = @($modules | Where-Object { $_.Version -eq [Version]$RequiredVersion })
    }
    elseif ($MinimumVersion) {
        $modules = @($modules | Where-Object { $_.Version -ge [Version]$MinimumVersion })
    }
    return $modules | Sort-Object Version -Descending | Select-Object -First 1
}

function Assert-NeologikModuleSignature {
    <#
    .SYNOPSIS
        Checks the signature of each file of the modules that the script installed, before
        the script imports any module. Stops the run when a file fails the check.
    .DESCRIPTION
        The function checks each module that the script installed, at the version that
        the script uses. The function also checks each module that the manifest of such a
        module requires, at the version that the manifest names. When a file fails the
        check, the function removes each module that -Modules names, which the script
        installed in this run. The next run then downloads and checks each module again.
        The function then stops the run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Modules
    )

    Write-Log "Checking the signature of each file of the installed modules..." -Level Info
    $problems = @()
    $installed = @()
    $checked = @{}
    $queue = [System.Collections.Generic.Queue[object]]::new()

    foreach ($module in $Modules) {
        $found = Find-NeologikInstalledModule -Name $module.Name -MinimumVersion $module.MinVersion
        if ($found) {
            $installed += $found
            $queue.Enqueue($found)
        }
        else {
            $problems += "the module $($module.Name), which is not installed after the download"
        }
    }

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if ($checked.ContainsKey($current.ModuleBase)) { continue }
        $checked[$current.ModuleBase] = $true
        $problems += @(Get-NeologikModuleSignatureProblem -Name $current.Name -Version ([string]$current.Version) -ModuleBase $current.ModuleBase)

        # Each module that the manifest requires. The script reads the manifest as data and runs nothing.
        $manifestPath = Join-Path $current.ModuleBase "$($current.Name).psd1"
        if (-not (Test-Path -LiteralPath $manifestPath)) { continue }
        try {
            $requiredModules = @(Get-NeologikRequiredModuleList -Path $manifestPath)
        }
        catch {
            $problems += "the module $($current.Name) $($current.Version), whose manifest the script cannot read: $($_.Exception.Message)"
            continue
        }
        foreach ($required in $requiredModules) {
            $spec = if ($required -is [hashtable]) { $required } else { @{ ModuleName = [string]$required } }
            $requiredModule = Find-NeologikInstalledModule -Name $spec['ModuleName'] -RequiredVersion $spec['RequiredVersion'] -MinimumVersion $spec['ModuleVersion']
            if ($requiredModule) {
                $queue.Enqueue($requiredModule)
            }
            else {
                Write-Log "The module $($spec['ModuleName']), which the module $($current.Name) requires, is not installed. The script checks no file of that module" -Level Warning
            }
        }
    }

    if ($problems.Count -eq 0) {
        Write-Log "Each file of the installed modules has a valid signature" -Level Success
        return
    }

    foreach ($problem in $problems) {
        Write-Log "The signature check failed for $problem" -Level Error
    }
    foreach ($module in $installed) {
        try {
            Remove-Item -LiteralPath $module.ModuleBase -Recurse -Force -ErrorAction Stop
            Write-Log "Removed the module $($module.Name) $($module.Version), which the script installed in this run" -Level Warning
        }
        catch {
            Write-Log "The script could not remove the folder $($module.ModuleBase). Delete the folder before the next run: $($_.Exception.Message)" -Level Warning
        }
    }
    throw "A PowerShell module failed the signature check. The script imported no module and stops. The script removed each module that the script installed in this run. The log names each file that failed the check. Run the script again later. When the check fails again, email the log to support@neologik.ai."
}

#endregion

#region PowerShell Version Management

function Test-PowerShellVersion {
    <#
    .SYNOPSIS
        Checks whether the PowerShell version meets the minimum requirement.
    #>
    [CmdletBinding()]
    param()

    Write-Log "Checking the PowerShell version..." -Level Info
    $currentVersion = $PSVersionTable.PSVersion
    $requiredVersion = [Version]"7.4.0"

    Write-Log "Current PowerShell version: $currentVersion" -Level Info

    if ($currentVersion -ge $requiredVersion) {
        Write-Log "The PowerShell version meets the requirement of 7.4.0 or later" -Level Success
        return $true
    }
    else {
        Write-Log "PowerShell version $currentVersion is older than the required version $requiredVersion" -Level Warning
        return $false
    }
}

function Install-PowerShellLatest {
    <#
    .SYNOPSIS
        Installs PowerShell, or updates PowerShell to the latest version.
    #>
    [CmdletBinding()]
    param()

    Write-Log "Installing or updating PowerShell..." -Level Info

    try {
        # Check whether winget is available
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        
        if ($winget) {
            Write-Log "Installing or updating PowerShell with winget..." -Level Info
            winget install --id Microsoft.PowerShell --source winget --silent --accept-package-agreements --accept-source-agreements | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log "PowerShell is updated." -Level Success
                Write-Log "Run this script again in the new PowerShell version." -Level Warning
                Write-Host "`nClose this window and run the script again in PowerShell 7.4 or later`n" -ForegroundColor Yellow
                exit 0
            }
            else {
                throw "The installation with winget failed with exit code $LASTEXITCODE"
            }
        }
        else {
            # Without winget, download the installer
            Write-Log "winget is not available. Downloading the PowerShell installer..." -Level Info
            # The name of the installer holds the version number of the release. The script reads the
            # name from the latest release, so that the address never names a version that Microsoft removed.
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
            $installer = @($release.assets | Where-Object { $_.name -like 'PowerShell-*-win-x64.msi' }) | Select-Object -First 1
            if (-not $installer) {
                throw "The latest PowerShell release holds no installer for Windows x64. Install PowerShell 7 from https://aka.ms/powershell and run the script again."
            }
            $installerPath = Join-Path $env:TEMP "PowerShell-Setup.msi"

            Write-Log "Downloading $($installer.name)..." -Level Info
            Invoke-WebRequest -Uri $installer.browser_download_url -OutFile $installerPath -UseBasicParsing

            # The installer runs only with a valid signature of Microsoft Corporation, which signs each PowerShell installer.
            $signatureProblem = Get-NeologikSignatureProblem -Path $installerPath -MicrosoftOnly
            if ($signatureProblem) {
                Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
                throw "The PowerShell installer $($installer.name) failed the signature check: $signatureProblem. The script deleted the installer and installed nothing. Install PowerShell 7 from https://aka.ms/powershell and run the script again."
            }
            Write-Log "The PowerShell installer has a valid signature of Microsoft Corporation" -Level Success
            
            Write-Log "Installing PowerShell from the installer file..." -Level Info
            Start-Process msiexec.exe -ArgumentList "/i `"$installerPath`" /qn /norestart" -Wait -NoNewWindow

            Write-Log "PowerShell is installed." -Level Success
            Write-Log "Run this script again in the new PowerShell version." -Level Warning
            Write-Host "`nClose this window and run the script again in PowerShell 7.4 or later`n" -ForegroundColor Yellow
            exit 0
        }
    }
    catch {
        Write-Log "The script could not install or update PowerShell: $_" -Level Error
        throw
    }
}

#endregion

#region Module Management

function Test-RequiredModules {
    <#
    .SYNOPSIS
        Checks whether the required PowerShell modules are installed.
    #>
    [CmdletBinding()]
    param()

    Write-Log "Checking the required PowerShell modules..." -Level Info
    $missingModules = @()

    foreach ($module in $script:RequiredModules) {
        $installedModule = Get-Module -ListAvailable -Name $module.Name | 
            Where-Object { $_.Version -ge [Version]$module.MinVersion } |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($installedModule) {
            Write-Log "Module $($module.Name) version $($installedModule.Version) is installed" -Level Info
        }
        else {
            Write-Log "Module $($module.Name), version $($module.MinVersion) or later, is not installed" -Level Warning
            $missingModules += $module
        }
    }

    return $missingModules
}

function Install-RequiredModules {
    <#
    .SYNOPSIS
        Installs the required PowerShell modules that are missing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Modules
    )

    Write-Log "Installing the missing modules..." -Level Info

    # Mark the PowerShell Gallery as a trusted repository
    $psGallery = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue
    if ($psGallery -and $psGallery.InstallationPolicy -ne 'Trusted') {
        Write-Log "Marking the PowerShell Gallery as a trusted repository..." -Level Info
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
    }

    foreach ($module in $Modules) {
        try {
            Write-Log "Installing the module $($module.Name)..." -Level Info
            Install-Module -Name $module.Name -MinimumVersion $module.MinVersion -Scope CurrentUser -Force -AllowClobber
            Write-Log "Module $($module.Name) installed" -Level Success
        }
        catch {
            Write-Log "The script could not install the module $($module.Name): $_" -Level Error
            throw
        }
    }

    # Check the signature of each file that the download brought, before the script imports any module.
    Assert-NeologikModuleSignature -Modules $Modules
}

#endregion

#region Azure Authentication

function Invoke-AzConnect {
    <#
    .SYNOPSIS
        Signs in to Azure in the browser. Signs in with a device code when no browser
        is available.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantId
    )

    $connectParams = @{ ErrorAction = 'Stop' }
    if ($TenantId) {
        $connectParams['TenantId'] = $TenantId
    }

    # Azure requires multi-factor authentication for every write. The sign-in requests the
    # 'p1' authentication-context claim, so that the first token already meets the
    # requirement. Without the claim, the run fails at the first write. Requires Az.Accounts
    # 5.2.0 or later.
    if ((Get-Command Connect-AzAccount).Parameters.ContainsKey('ClaimsChallenge')) {
        $connectParams['ClaimsChallenge'] = $script:ArmMfaClaimsChallenge
    }
    else {
        Write-Log "The installed version of Az.Accounts is older than 5.2.0 and does not accept -ClaimsChallenge. The sign-in may not meet the multi-factor authentication requirement of Azure, and Azure may refuse a write" -Level Warning
    }

    try {
        Write-Host "`n[i]  A browser window opens for the sign-in to Azure.`n" -ForegroundColor Cyan
        return Connect-AzAccount @connectParams
    }
    catch {
        Write-Log "The browser sign-in failed: $($_.Exception.Message)" -Level Warning
        Write-Log "The script now signs in with a device code" -Level Info
        Write-Host "`n[i]  The script shows a code. Open the address and enter the code to sign in.`n" -ForegroundColor Cyan
        return Connect-AzAccount @connectParams -UseDeviceAuthentication
    }
}

function Get-ArmTokenMfaClaimStatus {
    <#
    .SYNOPSIS
        Reads the Azure Resource Manager token and looks for the 'p1'
        authentication-context claim. Azure requires the claim for every create,
        update and delete.
    .OUTPUTS
        'Present': the token of a user, with the claim
        'Missing': the token of a user, without the claim. Azure refuses each write
        'Exempt':  the token of an application. The requirement does not apply
        'Unknown': the function could not obtain or read the token
    #>
    [CmdletBinding()]
    param()

    try {
        if ((Get-Command Get-AzAccessToken).Parameters.ContainsKey('AsSecureString')) {
            $secureToken = (Get-AzAccessToken -AsSecureString -ErrorAction Stop).Token
            $token = [System.Net.NetworkCredential]::new('', $secureToken).Password
        }
        else {
            $token = (Get-AzAccessToken -ErrorAction Stop).Token
        }

        # Decode the payload of the token
        $payload = $token.Split('.')[1].Replace('-', '+').Replace('_', '/')
        switch ($payload.Length % 4) {
            2 { $payload += '==' }
            3 { $payload += '=' }
        }
        $claims = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json

        # The token of a user holds 'scp'. The token of an application holds no 'scp' and is exempt.
        if (-not $claims.scp) { return 'Exempt' }
        # Microsoft Entra ID issues the 'acrs' claim p1 only when the sign-in made the claims challenge. The
        # token of an ordinary multi-factor sign-in holds 'amr' mfa. Either claim
        # meets the requirement.
        if (($claims.acrs -contains 'p1') -or ($claims.amr -contains 'mfa')) { return 'Present' }
        return 'Missing'
    }
    catch {
        Write-Log "The script could not read the Azure Resource Manager token to check the multi-factor authentication claim: $($_.Exception.Message)" -Level Warning
        return 'Unknown'
    }
}

function Connect-AzureEnvironment {
    <#
    .SYNOPSIS
        Signs in to Azure and to Microsoft Graph.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantId
    )

    Write-Log "Signing in to Azure..." -Level Info

    try {
        # Import required modules
        Import-Module Az.Accounts -ErrorAction Stop
        Import-Module Az.Resources -ErrorAction Stop
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

        # Check whether an Azure session exists
        $currentContext = Get-AzContext -ErrorAction SilentlyContinue
        
        # Sign in again when the administrator asks, or when no Azure session exists
        if ($script:ForceReAuth -or -not $currentContext -or -not $currentContext.Account) {
            if ($script:ForceReAuth) {
                Write-Log "The administrator asked to sign in again" -Level Info
            }
            
            # Sign in to Azure in the browser. Use a device code when the browser sign-in fails
            Write-Log "Signing in to Azure..." -Level Info
            $azContext = Invoke-AzConnect -TenantId $TenantId
            Write-Log "Signed in to Azure as $($azContext.Context.Account.Id)" -Level Success
        }
        elseif ($currentContext -and $currentContext.Account) {
            Write-Log "Already signed in to Azure as $($currentContext.Account.Id)" -Level Info
            
            # When -TenantId names another tenant, sign in to that tenant
            if ($TenantId -and $currentContext.Tenant.Id -ne $TenantId) {
                Write-Log "Signing in to the tenant $TenantId" -Level Info
                $azContext = Invoke-AzConnect -TenantId $TenantId
            }
            else {
                # Azure requires multi-factor authentication for every write. A token from an
                # earlier sign-in without the claim passes this point and fails at the first write. The script
                # therefore checks the claim now.
                $mfaClaimStatus = Get-ArmTokenMfaClaimStatus
                if ($mfaClaimStatus -eq 'Missing' -and -not $script:NonInteractiveMode) {
                    Write-Log "The stored Azure token lacks the multi-factor authentication claim that Azure requires for a write. The script signs in again..." -Level Warning
                    $azContext = Invoke-AzConnect -TenantId $currentContext.Tenant.Id
                }
                else {
                    if ($mfaClaimStatus -eq 'Missing') {
                        Write-Log "Unattended run: the Azure Resource Manager token of the user lacks the multi-factor authentication claim 'acrs' p1. Azure refuses each create, update and delete. Sign in with Connect-AzAccount -ClaimsChallenge, or sign in as a service principal." -Level Warning
                    }
                    $azContext = [PSCustomObject]@{
                        Context = $currentContext
                    }
                    Write-Log "Using the existing Azure session" -Level Success
                }
            }
        }

        # Store the details of the Azure session
        $script:ConfigData['TenantId'] = $azContext.Context.Tenant.Id
        
        # Read the name of the tenant. The script tries four sources in order
        $tenantName = $null
        
        # Source 1: Get-AzTenant, the most reliable source
        try {
            $tenant = Get-AzTenant -TenantId $azContext.Context.Tenant.Id -ErrorAction Stop
            if ($tenant -and $tenant.Name) {
                $tenantName = $tenant.Name
            }
        }
        catch {
            Write-Log "The script could not read the name of the tenant from Get-AzTenant" -Level Warning
        }
        
        # Source 2: the tenant property of the Azure session
        if (-not $tenantName -and $azContext.Context.Tenant.Directory) {
            $tenantName = $azContext.Context.Tenant.Directory
        }
        
        # Source 3: the HomeAccountId of the account
        if (-not $tenantName -and $azContext.Context.Account.ExtendedProperties.HomeAccountId) {
            # Read the domain from the HomeAccountId. The format is objectid.tenantid@domain
            $homeAccountId = $azContext.Context.Account.ExtendedProperties.HomeAccountId
            if ($homeAccountId -match '@(.+)$') {
                $tenantName = $matches[1]
            }
        }
        
        # Source 4: Microsoft Graph
        if (-not $tenantName) {
            try {
                $mgOrg = Get-MgOrganization -ErrorAction Stop | Select-Object -First 1
                if ($mgOrg) {
                    $tenantName = if ($mgOrg.DisplayName) { $mgOrg.DisplayName } else { $mgOrg.VerifiedDomains[0].Name }
                }
            }
            catch {
                Write-Log "The script could not read the name of the tenant from Microsoft Graph" -Level Warning
            }
        }
        
        $script:ConfigData['TenantName'] = $tenantName
        $script:ConfigData['UserAccount'] = $azContext.Context.Account.Id

        Write-Log "Tenant ID: $($script:ConfigData['TenantId'])" -Level Info
        if ($tenantName) {
            Write-Log "Tenant Name: $tenantName" -Level Info
        }
        Write-Log "User Account: $($script:ConfigData['UserAccount'])" -Level Info

        # Check whether a Microsoft Graph session exists
        $mgContext = Get-MgContext -ErrorAction SilentlyContinue
        
        # Sign in again when the administrator asks
        if ($script:ForceReAuth) {
            if ($mgContext) {
                Write-Log "The administrator asked to sign in again. Ending the Microsoft Graph session" -Level Info
                Disconnect-MgGraph -ErrorAction SilentlyContinue
                $mgContext = $null
            }
        }
        
        if ($mgContext -and $mgContext.TenantId -eq $script:ConfigData['TenantId'] -and -not $script:ForceReAuth) {
            Write-Log "Already signed in to Microsoft Graph for tenant $($mgContext.TenantId)" -Level Info
            Write-Host "`n[OK] Microsoft Graph: the script uses the existing session, account $($mgContext.Account)`n" -ForegroundColor Green
        }
        else {
            # End the existing Microsoft Graph session first
            if ($mgContext) {
                Write-Log "Ending the existing Microsoft Graph session, which is for another tenant" -Level Info
                Disconnect-MgGraph -ErrorAction SilentlyContinue
            }

            # Request the Microsoft Graph token from the Azure session. The administrator then sees no second sign-in
            Write-Log "Signing in to Microsoft Graph with a token from the Azure session..." -Level Info
            try {
                # Current versions of Az.Accounts return the token as a secure string. Earlier versions return
                # plain text. Request the secure string where the parameter exists.
                if ((Get-Command Get-AzAccessToken).Parameters.ContainsKey('AsSecureString')) {
                    $graphToken = (Get-AzAccessToken -ResourceTypeName MSGraph -TenantId $script:ConfigData['TenantId'] -AsSecureString -ErrorAction Stop).Token
                }
                else {
                    $graphToken = (Get-AzAccessToken -ResourceTypeName MSGraph -TenantId $script:ConfigData['TenantId'] -ErrorAction Stop).Token
                }
                # Microsoft Graph PowerShell requires the token as a secure string. The script passes a secure string
                # unchanged. A second conversion would produce a token that is not valid.
                if ($graphToken -is [System.Security.SecureString]) {
                    $secureGraphToken = $graphToken
                }
                else {
                    $secureGraphToken = ConvertTo-SecureString -String $graphToken -AsPlainText -Force
                }
                Connect-MgGraph -AccessToken $secureGraphToken -ErrorAction Stop
                Write-Log "Signed in to Microsoft Graph with a token from the Azure session" -Level Success
            }
            catch {
                Write-Log "Microsoft Graph did not accept the token from the Azure session. Consent may be required. The script now makes an interactive sign-in: $_" -Level Warning
                Write-Host "`n[i]  A browser window opens for the sign-in to Microsoft Graph.`n" -ForegroundColor Cyan
                Connect-MgGraph -TenantId $script:ConfigData['TenantId'] `
                    -Scopes "User.ReadWrite.All", "User.Invite.All", "Group.ReadWrite.All", "Application.ReadWrite.All", "Directory.ReadWrite.All", "RoleManagement.ReadWrite.Directory", "AppRoleAssignment.ReadWrite.All", "AgentIdentityBlueprint.Create", "AgentIdentityBlueprint.AddRemoveCreds.All", "AgentIdentityBlueprintPrincipal.Create", "AgentIdentityBlueprintPrincipal.ReadWrite.All" `
                    -ErrorAction Stop
                Write-Log "Signed in to Microsoft Graph with an interactive sign-in" -Level Success
            }
        }

        # Find the id of the signed-in user. The id works for a member and for a guest
        # The account comes from the Azure session
        $userIdentifier = $script:ConfigData['UserAccount']
        
        if ($userIdentifier) {
            try {
                Write-Log "Reading the id of the user $userIdentifier" -Level Info
                
                # Look up the user through Azure first
                $currentAzUser = Get-AzADUser -UserPrincipalName $userIdentifier -ErrorAction SilentlyContinue
                
                if (-not $currentAzUser) {
                    # Without a result, look up the user by mail address, which finds a guest
                    $currentAzUser = Get-AzADUser -Mail $userIdentifier -ErrorAction SilentlyContinue
                }
                
                if ($currentAzUser) {
                    $script:ConfigData['CurrentUserId'] = $currentAzUser.Id
                    Write-Log "Id of the signed-in user: $($script:ConfigData['CurrentUserId'])" -Level Success
                }
                else {
                    Write-Log "The script could not read the id of the signed-in user. This result is normal for some guest users" -Level Warning
                    Write-Log "The script does not add the signed-in user to the security groups. The script adds the guest users by email address." -Level Info
                }
            }
            catch {
                Write-Log "The script could not read the id of the signed-in user: $($_.Exception.Message)" -Level Warning
                Write-Log "The script does not add the signed-in user to the security groups. The script adds the guest users by email address." -Level Info
            }
        }
        else {
            Write-Log "Warning: the configuration holds no user account" -Level Warning
        }

        return $azContext
    }
    catch {
        Write-Log "The sign-in to Azure failed: $_" -Level Error
        throw
    }
}

function Test-RequiredPermissions {
    <#
    .SYNOPSIS
        Checks that the signed-in user holds Owner on the subscription and Global
        Administrator in the tenant.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    Write-Log "Checking the roles of the signed-in user..." -Level Info

    try {
        # Import the Microsoft Graph modules
        Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop

        # Read the account of the signed-in user
        $userAccount = $script:ConfigData['UserAccount']
        
        if ([string]::IsNullOrWhiteSpace($userAccount)) {
            throw "The script holds no account for the signed-in user. Check that the sign-in to Azure completed."
        }

        Write-Log "Checking the roles of the user $userAccount" -Level Info

        # Check the Owner role on the subscription
        Write-Log "Checking the Owner role on the subscription..." -Level Info
        
        # Look up by SignInName first, then by ObjectId
        try {
            $roleAssignments = Get-AzRoleAssignment -Scope "/subscriptions/$SubscriptionId" -SignInName $userAccount -ErrorAction Stop
        }
        catch {
            Write-Log "Reading the role assignments by object id..." -Level Info
            # Find the id of the signed-in user with a Microsoft Graph request on the open session.
            # The cmdlets for users load further Microsoft Graph modules. The versions of those modules
            # can conflict with the module that is already loaded.
            $currentUser = Invoke-MgGraphRequest -Method GET -Uri "v1.0/me?`$select=id" -ErrorAction Stop
            $roleAssignments = Get-AzRoleAssignment -Scope "/subscriptions/$SubscriptionId" -ObjectId $currentUser.id -ErrorAction Stop
        }
        
        $isOwner = $roleAssignments | Where-Object { $_.RoleDefinitionName -eq 'Owner' }

        if ($isOwner) {
            Write-Log "The user holds the Owner role on the subscription" -Level Success
        }
        else {
            throw "The user does not hold the Owner role on the subscription. The script requires the Owner role."
        }

        # Check the Global Administrator role
        Write-Log "Checking the Global Administrator role..." -Level Info

        $isGlobalAdmin = $false
        $globalAdminConfirmed = $true
        try {
            # Read the membership with a Microsoft Graph request on the open session,
            # for the same reason. The signed-in user can read the directory roles of the signed-in user
            # without an activated role.
            $gaRoleTemplateId = '62e90394-69f5-4237-9190-012177145e10'  # Global Administrator. Microsoft publishes the id of the role template
            $memberOf = Invoke-MgGraphRequest -Method GET -Uri "v1.0/me/memberOf/microsoft.graph.directoryRole?`$select=roleTemplateId" -ErrorAction Stop
            $isGlobalAdmin = [bool]($memberOf.value | Where-Object { $_.roleTemplateId -eq $gaRoleTemplateId })
        }
        catch {
            # The script could not make the check. The script does not know whether the user holds the role.
            # The script treats the role as not confirmed, and not as missing.
            $globalAdminConfirmed = $false
            Write-Log "The script could not check the Global Administrator role: $_" -Level Warning
        }

        if ($isGlobalAdmin) {
            Write-Log "The user holds the Global Administrator role" -Level Success
        }
        elseif ($globalAdminConfirmed) {
            # The script made the check. The user does not hold the role. Stop.
            throw "The user does not hold the Global Administrator role. The script requires the Global Administrator role."
        }
        else {
            # The script could not make the check. The administrator decides whether to continue.
            # An unattended run has no administrator to ask. Stop.
            if ($script:NonInteractiveMode) {
                throw "The script could not check the Global Administrator role, and an unattended run cannot ask a question. Check that the Microsoft Graph token allows the read of directory roles."
            }
            Write-Host ""
            Write-Host "[!]  The script could not check the Global Administrator role for $userAccount." -ForegroundColor Yellow
            Write-Host "    The script requires the Global Administrator role to create application registrations, to assign security groups and to invite guests." -ForegroundColor Yellow
            Write-Host "    Without the role, a later step may fail." -ForegroundColor Yellow
            $proceed = Read-Host "Proceed anyway? [Y/N]"
            if ($proceed -match '^\s*(n|no)\s*$') {
                throw "The script could not check the Global Administrator role, and the administrator chose to stop."
            }
            Write-Log "The administrator chose to continue without a check of the Global Administrator role." -Level Warning
        }

        Write-Log "The signed-in user holds both required roles" -Level Success
        return $true
    }
    catch {
        Write-Log "The check of the roles failed: $_" -Level Error
        throw
    }
}

function Find-NeologikUserByEmail {
    <#
    .SYNOPSIS
        Finds a user account by mail address, by user principal name or by another
        mail address of the account.
    .DESCRIPTION
        The function sends a Microsoft Graph request on the open session. The function
        returns the id and the displayName of the account. The function returns $null
        when no account matches or when the request fails. A guest first invited under
        another address keeps this address in otherMails, so the function also matches
        otherMails, and the script does not invite that guest again.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Email
    )

    $safeEmail = $Email -replace "'", "''"
    $filter = [uri]::EscapeDataString("mail eq '$safeEmail' or userPrincipalName eq '$safeEmail' or otherMails/any(m:m eq '$safeEmail')")
    try {
        $result = Invoke-MgGraphRequest -Method GET -Uri "v1.0/users?`$filter=$filter&`$select=id,displayName" -ErrorAction Stop
        if ($result.value -and $result.value.Count -gt 0) {
            # Return a typed object. The keys of the answer are exactly 'id' and 'displayName'.
            $match = $result.value[0]
            return [pscustomobject]@{
                Id          = $match.id
                DisplayName = $match.displayName
            }
        }
        return $null
    }
    catch {
        Write-Log "The lookup of the user $Email failed: $_" -Level Warning
        return $null
    }
}

#endregion

#region Resource Group Management

function New-NeologikResourceGroup {
    <#
    .SYNOPSIS
        Creates the resource group, or confirms the resource group that exists.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        # True during the one further attempt that follows a second sign-in.
        [Parameter(Mandatory = $false)]
        [switch]$IsMfaRetry
    )

    Write-Log "Looking for the resource group $ResourceGroupName..." -Level Info

    try {
        # Confirm the resource provider Microsoft.Resources before the creation. Step 5c submitted the registration
        Confirm-ResourceProviderReady -Namespaces @('Microsoft.Resources')

        $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue

        if ($rg) {
            Write-Log "Resource group '$ResourceGroupName' already exists in the Azure region $($rg.Location)" -Level Info
            
            # Check whether the Azure region matches
            if ($rg.Location -ne $Location) {
                Write-Log "Warning: the resource group is in the Azure region $($rg.Location). The configuration names the Azure region $Location" -Level Warning
            }
            
            $script:ConfigData['ResourceGroupName'] = $rg.ResourceGroupName
            $script:ConfigData['AzureRegion'] = $rg.Location
        }
        else {
            Write-Log "Creating the resource group $ResourceGroupName in $Location..." -Level Info
            # The script applies the tags at creation. A tenant whose Azure Policy refuses a resource
            # without tags then accepts the resource. The value is empty when the administrator chooses no tags.
            $tagParams = @{}
            $resourceTags = Get-NeologikResourceTags
            if ($resourceTags) { $tagParams['Tag'] = $resourceTags }
            $rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location @tagParams -ErrorAction Stop
            Write-Log "Resource group created" -Level Success
            
            $script:ConfigData['ResourceGroupName'] = $rg.ResourceGroupName
            $script:ConfigData['AzureRegion'] = $rg.Location
        }

        # The resource group records the version of the onboarding kit. When an earlier version of the onboarding kit
        # prepared the resource group, the tag keeps that version until step 15c, so the tag never names a step that did not run.
        # The write then changes no value, and Azure still checks multi-factor authentication for the write.
        $earlierKitVersion = if ($rg.Tags) { [string]$rg.Tags['NeologikOnboardingKit'] } else { '' }
        if ($earlierKitVersion) {
            Update-AzTag -ResourceId $rg.ResourceId -Tag @{ NeologikOnboardingKit = $earlierKitVersion } -Operation Merge -ErrorAction Stop | Out-Null
        }
        else {
            Set-NeologikKitVersionTag -ResourceId $rg.ResourceId
        }

        return $rg
    }
    catch {
        # Azure requires multi-factor authentication for every write. When Azure refuses this write
        # for that reason, sign in again with the claim and try once more.
        if (-not $IsMfaRetry -and -not $script:NonInteractiveMode -and $_.Exception.Message -match 'authenticat\w+ through MFA') {
            Write-Log "Azure refused the write, because the token lacks the multi-factor authentication claim. The script signs in again and tries once more..." -Level Warning
            Invoke-AzConnect -TenantId $script:ConfigData['TenantId'] | Out-Null
            return New-NeologikResourceGroup -ResourceGroupName $ResourceGroupName -Location $Location -IsMfaRetry
        }
        # Report a refusal caused by a missing permission with a clear message
        if ($_.Exception.Message -match 'AuthorizationFailed|does not have authorization|does not have.*permission|Forbidden') {
            Write-Host "`n[X] PERMISSION ERROR: the script cannot create the resource group '$ResourceGroupName'" -ForegroundColor Red
            Write-Host "   The signed-in account cannot create a resource group in this subscription." -ForegroundColor Yellow
            Write-Host "   Required role: 'Owner' or 'Contributor' on the subscription." -ForegroundColor Yellow
            Write-Host "   Subscription: $($script:ConfigData['SubscriptionId'])" -ForegroundColor Yellow
            Write-Host "   Obtain the Owner role on the subscription." -ForegroundColor Cyan
            Write-Host "   Then run the script again and choose 'Y' to resume from the checkpoint." -ForegroundColor Cyan
            Write-Log "Azure role-based access control refused the creation of the resource group. User: $($script:ConfigData['UserAccount']). Subscription: $($script:ConfigData['SubscriptionId'])" -Level Error
            throw "Insufficient permissions: the script cannot create the resource group '$ResourceGroupName'. The Owner role or the Contributor role on the subscription is required"
        }
        Write-Log "The script could not create or confirm the resource group: $_" -Level Error
        throw
    }
}

#endregion

#region Guest User Management

function Resolve-GuestUsersFile {
    <#
    .SYNOPSIS
        Finds NeologikGuestUsers.txt when the file is not in the folder of the script.
        The function gives the administrator three choices: select the file in a
        dialog, type the path of the file, or continue without guest users.
    .OUTPUTS
        $true when the administrator selected a file. The function then sets
        $script:GuestUsersFile and $script:NeologikGuestUsers.
        $false when the administrator chose to continue without guest users.
    #>
    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "  NeologikGuestUsers.txt is not in the folder of the script:" -ForegroundColor Yellow
    Write-Host "    $script:GuestUsersFile" -ForegroundColor Gray
    Write-Host "  The file is part of the onboarding kit and holds one Neologik email address on each line." -ForegroundColor Gray
    Write-Host "  Extract the whole onboarding kit, or select the file now." -ForegroundColor Gray

    while ($true) {
        Write-Host ""
        Write-Host "  [B] Select the file in a dialog   [S] Continue without guest invitation   or type the full path" -ForegroundColor Cyan
        Write-Host "  Your choice: " -NoNewline -ForegroundColor Yellow
        $choice = (Read-Host).Trim()

        if ($choice -match '^(s|skip)$') {
            Write-Log "The administrator chose to continue without NeologikGuestUsers.txt. The script invites no guest user" -Level Warning
            return $false
        }

        $candidate = $null
        if ($choice -match '^(b|browse)$') {
            try {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
                $dialog = [System.Windows.Forms.OpenFileDialog]::new()
                $dialog.Title = 'Select NeologikGuestUsers.txt'
                $dialog.InitialDirectory = $PSScriptRoot
                $dialog.Filter = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
                # Keep the dialog in front of the console
                $owner = [System.Windows.Forms.Form]::new()
                $owner.TopMost = $true
                try {
                    if ($dialog.ShowDialog($owner) -ne [System.Windows.Forms.DialogResult]::OK) { continue }
                    $candidate = $dialog.FileName
                }
                finally {
                    $owner.Dispose()
                }
            }
            catch {
                Write-Host "  This session cannot show a file dialog. Type the full path." -ForegroundColor Yellow
                continue
            }
        }
        elseif ($choice) {
            $candidate = $choice.Trim('"')
        }
        else {
            continue
        }

        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            Write-Host "  File not found: $candidate" -ForegroundColor Red
            continue
        }

        $emails = @(Get-Content -LiteralPath $candidate | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^\s*#' })
        if ($emails.Count -eq 0) {
            Write-Host "  $candidate holds no address. The script ignores blank lines and lines that begin with #." -ForegroundColor Red
            continue
        }

        $script:GuestUsersFile = $candidate
        $script:NeologikGuestUsers = $emails
        Write-Log "Selected file: $candidate, $($emails.Count) addresses" -Level Success
        return $true
    }
}

function Invoke-GuestUserInvitation {
    <#
    .SYNOPSIS
        Invites Neologik guest users to the tenant.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$GuestEmails
    )

    # Without guest addresses, return an empty array
    if ($GuestEmails.Count -eq 0) {
        Write-Log "The list of guest users is empty. The script invites no guest user." -Level Info
        return @()
    }

    Write-Log "Inviting Neologik guest users..." -Level Info

    try {
        Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction Stop

        $invitedUsers = @()

        foreach ($email in $GuestEmails) {
            Write-Log "Looking up the guest user $email..." -Level Info

            # Check whether the user already exists
            $existingUser = Find-NeologikUserByEmail -Email $email

            if ($existingUser) {
                Write-Log "Guest user $email already exists, id $($existingUser.Id)" -Level Info
                $invitedUsers += @{
                    Email = $email
                    UserId = $existingUser.Id
                    Status = 'AlreadyExists'
                }
            }
            else {
                # Send invitation
                Write-Log "Sending the invitation to $email..." -Level Info
                
                $invitation = New-MgInvitation -InvitedUserEmailAddress $email `
                    -InviteRedirectUrl "https://portal.azure.com" `
                    -SendInvitationMessage:$true `
                    -ErrorAction Stop

                Write-Log "Invitation sent to $email, id $($invitation.InvitedUser.Id)" -Level Success
                
                $invitedUsers += @{
                    Email = $email
                    UserId = $invitation.InvitedUser.Id
                    Status = 'Invited'
                }
            }
        }

        $script:ConfigData['InvitedGuestUsers'] = $invitedUsers
        return $invitedUsers
    }
    catch {
        Write-Log "The script could not invite the guest users: $_" -Level Error
        throw
    }
}

function Read-EmailAddressList {
    <#
    .SYNOPSIS
        Reads email addresses at the prompt, one line at a time, and shows the count.
        A line can hold several addresses separated by commas. An empty line ends the
        entry. Returns the list without duplicates.
    #>
    [CmdletBinding()]
    param(
        # The count and the result include the addresses collected before the prompt,
        # for example the addresses from NeologikGuestUsers.txt.
        [Parameter(Mandatory = $false)]
        [string[]]$Seed = @()
    )

    $collected = @($Seed)
    while ($true) {
        Write-Host "  Address, $($collected.Count) entered so far: " -NoNewline -ForegroundColor Gray
        $line = Read-Host
        if ([string]::IsNullOrWhiteSpace($line)) { break }
        $collected += @($line -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    return @($collected | Select-Object -Unique)
}

function Invoke-ExistingAccountResolution {
    <#
    .SYNOPSIS
        Finds existing accounts by email address, so that the script can add the
        accounts to the security groups. An account can be a guest or a member. The
        function sends no invitation.
    .DESCRIPTION
        The script calls the function when the administrator declined invitation and
        chose to add existing accounts. The function looks up each address by mail
        address and by user principal name. The function adds each account found to
        the list. The function reports an address that matches no account and
        continues. An administrator can add such an account in Microsoft Entra ID
        later.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Emails
    )

    if ($Emails.Count -eq 0) {
        Write-Log "The list of existing accounts is empty. The script adds no account to the security groups." -Level Info
        return @()
    }

    Write-Log "Looking up the existing accounts for the security groups. The script sends no invitation..." -Level Info

    $resolvedUsers = @()
    foreach ($email in $Emails) {
        Write-Log "Looking up the existing account $email..." -Level Info
        $existingUser = Find-NeologikUserByEmail -Email $email

        if ($existingUser) {
            Write-Log "Account $email exists, id $($existingUser.Id). The script adds the account to the security groups" -Level Success
            $resolvedUsers += @{
                Email = $email
                UserId = $existingUser.Id
                Status = 'ExistingResolved'
            }
        }
        else {
            Write-Log "No account in this tenant has the mail address or the user principal name $email. The script continues without the account. Create the account and add the account to the security groups in Microsoft Entra ID later." -Level Warning
        }
    }

    Write-Log "Existing accounts found: $($resolvedUsers.Count) of $($Emails.Count) addresses." -Level Info
    $script:ConfigData['ExistingAccountsAdded'] = $resolvedUsers
    return $resolvedUsers
}

#endregion

#region Security Group Management

function New-NeologikSecurityGroups {
    <#
    .SYNOPSIS
        Creates the four Neologik security groups in Microsoft Entra ID.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$GuestUsers,

        [Parameter(Mandatory = $false)]
        [string]$OrganizationCode = "",

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentType = "",

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentIndex = ""
    )

    Write-Log "Creating the Neologik security groups..." -Level Info

    try {
        Import-Module Microsoft.Graph.Groups -ErrorAction Stop

        # The last part of each group name is the short name. The short name is <org><env><index>,
        # or the short name from the answer file.
        $shortName = if (-not [string]::IsNullOrWhiteSpace([string]$script:ConfigData['SolutionShortName'])) { [string]$script:ConfigData['SolutionShortName'] }
                     elseif ([string]::IsNullOrWhiteSpace($OrganizationCode)) { "" }
                     else { "neo$($OrganizationCode.ToLower())$EnvironmentIndex" }
        $groupSuffix = if ([string]::IsNullOrWhiteSpace($shortName)) { "" } else { " - $shortName" }

        # The standard security group for users. A channel of an agent in the Neologik Admin Tool uses
        # this security group, or an existing security group that an administrator names. The Neologik Platform creates no security group.
        $groups = @()
        $groups += @{
            Name = "Neologik User Group$groupSuffix"
            Description = 'This security group holds the people who use the Neologik agents of this environment. In the Neologik Admin Tool, each channel of a Neologik agent names the security group whose members can use the Neologik agent.'
        }
        # The two security groups for roles in the Neologik Admin Tool: contributors and administrators.
        # When the contributors group exists under another recognised name, the script renames the group. The group keeps the id.
        $groups += @{
            Name = "Neologik NCE Contributors$groupSuffix"
            Description = 'Members of this security group hold the contributor role in the Neologik Admin Tool. A member can create and change the configuration of the Neologik Platform.'
            PreviousNames = @("Neologik NCE User Group$groupSuffix", "Neologik Harness User Group$groupSuffix")
        }
        $groups += @{
            Name = "Neologik NCE Admins$groupSuffix"
            Description = 'Members of this security group hold the administrator role in the Neologik Admin Tool. A member has full access to the Neologik Admin Tool, including the Blueprints, Audit and Admin pages.'
        }
        $groups += @{
            Name = "Neologik Admin User Group$groupSuffix"
            Description = 'Members of this security group administer and support the Azure resources of this Neologik Platform environment. This security group holds Azure roles on the resource group of the environment.'
        }

        $createdGroups = @()

        foreach ($groupDef in $groups) {
            Write-Log "Looking for the security group $($groupDef.Name)..." -Level Info

            # Look for the security group under the standard name, then under each other recognised name. The script
            # renames a security group found under another recognised name. The group keeps the id and the members.
            $existingGroup = Get-MgGroup -Filter "displayName eq '$($groupDef.Name)'" -ErrorAction SilentlyContinue
            if (-not $existingGroup -and $groupDef.PreviousNames) {
                foreach ($previousName in $groupDef.PreviousNames) {
                    $existingGroup = Get-MgGroup -Filter "displayName eq '$previousName'" -ErrorAction SilentlyContinue
                    if ($existingGroup) {
                        Write-Log "Renaming the security group '$previousName' to '$($groupDef.Name)'. The script changes the display name only. The object id stays the same" -Level Info
                        Update-MgGroup -GroupId $existingGroup.Id -DisplayName $groupDef.Name -Description $groupDef.Description -ErrorAction Stop
                        $existingGroup = Get-MgGroup -GroupId $existingGroup.Id -ErrorAction Stop
                        break
                    }
                }
            }

            if ($existingGroup) {
                Write-Log "Security group '$($groupDef.Name)' already exists, id $($existingGroup.Id)" -Level Info
                $group = $existingGroup

                # A security group from an earlier run can hold the description of an earlier version of the
                # script. The script then writes the description of this version. A failed update leaves the
                # earlier description, and the run continues.
                if ([string]$existingGroup.Description -cne $groupDef.Description) {
                    try {
                        Update-MgGroup -GroupId $existingGroup.Id -Description $groupDef.Description -ErrorAction Stop
                        Write-Log "Description of the security group '$($groupDef.Name)' updated" -Level Success
                    }
                    catch {
                        Write-Log "Warning: the script could not update the description of the security group '$($groupDef.Name)': $_" -Level Warning
                    }
                }
            }
            else {
                Write-Log "Creating the security group $($groupDef.Name)..." -Level Info
                
                $group = New-MgGroup -DisplayName $groupDef.Name `
                    -Description $groupDef.Description `
                    -MailEnabled:$false `
                    -SecurityEnabled:$true `
                    -MailNickname ($groupDef.Name -replace '\s', '') `
                    -ErrorAction Stop

                Write-Log "Security group created, id $($group.Id)" -Level Success
            }

            # Add the guest users to the security group, when guest users exist
            if ($GuestUsers.Count -gt 0) {
                Write-Log "Adding the guest users to the security group $($groupDef.Name)..." -Level Info
                
                foreach ($guestUser in $GuestUsers) {
                    try {
                        # Check whether the user is already a member
                        $isMember = Get-MgGroupMember -GroupId $group.Id -Filter "id eq '$($guestUser.UserId)'" -ErrorAction SilentlyContinue

                        if ($isMember) {
                            Write-Log "User $($guestUser.Email) is already a member of $($groupDef.Name)" -Level Info
                        }
                        else {
                            New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $guestUser.UserId -ErrorAction Stop
                            Write-Log "Added $($guestUser.Email) to $($groupDef.Name)" -Level Success
                        }
                    }
                    catch {
                        Write-Log "Warning: the script could not add $($guestUser.Email) to $($groupDef.Name): $_" -Level Warning
                    }
                }
            }
            else {
                Write-Log "No guest users to add to the security group $($groupDef.Name)" -Level Info
            }

            # Add the signed-in user to the group
            Write-Log "Adding the signed-in user to the security group $($groupDef.Name)..." -Level Info
            try {
                # The id from the sign-in works for a member and for a guest
                if ($script:ConfigData['CurrentUserId']) {
                    $currentUserId = $script:ConfigData['CurrentUserId']
                    $isMember = Get-MgGroupMember -GroupId $group.Id -Filter "id eq '$currentUserId'" -ErrorAction SilentlyContinue

                    if ($isMember) {
                        Write-Log "The signed-in user is already a member of $($groupDef.Name)" -Level Info
                    }
                    else {
                        New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $currentUserId -ErrorAction Stop
                        Write-Log "Added the signed-in user to $($groupDef.Name)" -Level Success
                    }
                }
                else {
                    Write-Log "Warning: the script does not know the id of the signed-in user. The script does not add the signed-in user to the security group" -Level Warning
                }
            }
            catch {
                Write-Log "Warning: the script could not add the signed-in user to $($groupDef.Name): $_" -Level Warning
            }

            $createdGroups += @{
                Name = $group.DisplayName
                Id = $group.Id
                Description = $groupDef.Description
            }
        }

        $script:ConfigData['SecurityGroups'] = $createdGroups
        return $createdGroups
    }
    catch {
        Write-Log "The script could not create the security groups: $_" -Level Error
        throw
    }
}

#endregion

#region Role Assignment

function Set-NeologikRoleAssignments {
    <#
    .SYNOPSIS
        Assigns the Azure roles of the Admin User Group.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$SecurityGroups,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
    )

    Write-Log "Assigning the roles of the Admin User Group..." -Level Info

    try {
        # Find the Admin User Group
        $adminGroup = $SecurityGroups | Where-Object { $_.Name -like 'Neologik Admin User Group*' }

        if (-not $adminGroup) {
            throw "Neologik Admin User Group not found"
        }

        $subScope = "/subscriptions/$SubscriptionId"
        $rgScope  = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"

        # Confirm the permission with a read before the first role assignment
        try {
            $null = Get-AzRoleAssignment -ObjectId $adminGroup.Id `
                -RoleDefinitionName 'Contributor' `
                -Scope $rgScope `
                -ErrorAction Stop
        }
        catch {
            Write-Log "ERROR: the script cannot read the role assignments, because a permission is missing" -Level Error
            Write-Host "`n[X] INSUFFICIENT PERMISSIONS" -ForegroundColor Red
            Write-Host "The script cannot read the role assignments. The Owner role on the subscription is required." -ForegroundColor Yellow
            throw "Insufficient permissions: Cannot verify role assignments"
        }

        # The Admin User Group receives no role on the subscription. A member administers the cluster
        # from the resource group. The Contributor role gives access to the control plane of the cluster.
        # Azure Kubernetes Service Cluster Admin Role gives access to the administrator credentials of the cluster.
        # Azure Kubernetes Service manages the node resource group of the cluster.
        $subRoles = @()

        # The roles to assign on the resource group
        $rgRoles = @(
            'Contributor',
            'Azure Kubernetes Service Cluster Admin Role',
            'Key Vault Administrator',
            'Storage Blob Data Owner',
            'Storage Table Data Contributor',
            'Azure Kubernetes Service RBAC Cluster Admin',
            'Cognitive Services Data Reader',
            'Cognitive Services OpenAI Contributor',
            'Search Index Data Reader',
            'Azure AI Developer'
        )

        $assignRole = {
            param($ObjectId, $RoleName, $Scope, $GroupName)
            $existing = Test-NeologikRoleAssigned -ObjectId $ObjectId -RoleName $RoleName -Scope $Scope -ErrorAction SilentlyContinue
            if ($existing) {
                Write-Log "$RoleName already assigned to $GroupName" -Level Info
                return
            }
            $retryCount = 0
            $maxRetries = 10
            $assigned = $false
            while (-not $assigned -and $retryCount -lt $maxRetries) {
                try {
                    New-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleName -Scope $Scope -ErrorAction Stop | Out-Null
                    Write-Log "$RoleName assigned to $GroupName" -Level Success
                    $assigned = $true
                }
                catch {
                    if ($_.Exception.Message -match "does not exist|cannot be found|BadRequest") {
                        $retryCount++
                        if ($retryCount -lt $maxRetries) {
                            Write-Log "Microsoft Entra ID does not yet show the new security group. The script tries again in 10 seconds. Attempt $retryCount of $maxRetries" -Level Warning
                            Start-Sleep -Seconds 10
                        }
                        else { throw }
                    }
                    else { throw }
                }
            }
        }

        foreach ($role in $subRoles) {
            Write-Log "Assigning $role to $($adminGroup.Name) on the subscription..." -Level Info
            & $assignRole $adminGroup.Id $role $subScope $adminGroup.Name
        }

        foreach ($role in $rgRoles) {
            Write-Log "Assigning $role to $($adminGroup.Name) on the resource group..." -Level Info
            & $assignRole $adminGroup.Id $role $rgScope $adminGroup.Name
        }

        # @(...) keeps each list an array, so that PowerShell joins two lists as arrays. Without @(...),
        # a list of one entry becomes a single hashtable, and PowerShell cannot join a hashtable to an array.
        $script:ConfigData['RoleAssignments'] = @($subRoles | ForEach-Object {
            @{ Principal = $adminGroup.Name; PrincipalType = 'Security Group'; Role = $_; Scope = 'Subscription' }
        }) + @($rgRoles | ForEach-Object {
            @{ Principal = $adminGroup.Name; PrincipalType = 'Security Group'; Role = $_; Scope = 'Resource Group' }
        })

        return $true
    }
    catch {
        Write-Log "The script could not assign the roles: $_" -Level Error
        throw
    }
}

#endregion

#region App Registration

function New-NeologikAppRegistration {
    <#
    .SYNOPSIS
        Creates the application registration, the service principal and the client secret
        of the deployment identity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$OrganizationCode = "",

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentType = "",

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentIndex = ""
    )

    Write-Log "Creating the application registration of the deployment identity..." -Level Info

    try {
        Import-Module Microsoft.Graph.Applications -ErrorAction Stop

        # The last part of the application name is the short name.
        $appName = if ([string]::IsNullOrWhiteSpace($OrganizationCode)) {
            "Neologik GitHub Service Connection"
        } else {
            $shortName = if (-not [string]::IsNullOrWhiteSpace([string]$script:ConfigData['SolutionShortName'])) { [string]$script:ConfigData['SolutionShortName'] }
                         else { "neo$($OrganizationCode.ToLower())$EnvironmentIndex" }
            "Neologik GitHub Service Connection - $shortName"
        }

        # Look for the application registration
        $existingApp = Get-MgApplication -Filter "displayName eq '$appName'" -ErrorAction SilentlyContinue

        if ($existingApp) {
            Write-Log "Application registration '$appName' already exists, client id $($existingApp.AppId)" -Level Info
            $app = $existingApp
        }
        else {
            Write-Log "Creating the application registration $appName..." -Level Info

            # Single tenant: the deployment signs in to this tenant only, with the client secret.
            # No account of another directory uses the registration.
            $app = New-MgApplication -DisplayName $appName `
                -SignInAudience "AzureADMyOrg" `
                -ErrorAction Stop

            Write-Log "Application registration created, client id $($app.AppId)" -Level Success
        }

        # Create the service principal when the service principal is absent
        $sp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -ErrorAction SilentlyContinue

        if (-not $sp) {
            Write-Log "Creating the service principal of the application registration..." -Level Info
            $sp = New-MgServicePrincipal -AppId $app.AppId -ErrorAction Stop
            Write-Log "Service principal created" -Level Success
        }
        else {
            Write-Log "The service principal already exists" -Level Info
        }

        # Create the client secret
        Write-Log "Creating the client secret..." -Level Info

        $secretName = "auth"
        $secretEndDate = (Get-Date).AddDays(365)

        $passwordCred = Add-MgApplicationPassword -ApplicationId $app.Id `
            -PasswordCredential @{
            DisplayName = $secretName
            EndDateTime = $secretEndDate
        } -ErrorAction Stop

        Write-Log "Client secret created. Expiry date: $secretEndDate" -Level Success
        Write-Host "`n[OK] Client secret created. The script stores the client secret in the Key Vault" -ForegroundColor Green

        # Record the deployment identity in the configuration. The function
        # Grant-GraphAppRolePermissions grants the two Microsoft Graph application permissions in a later step.
        Write-Log "Recording the deployment identity in the configuration..." -Level Info

        $script:ConfigData['AppRegistration'] = @{
            Name = $app.DisplayName
            ClientId = $app.AppId
            ObjectId = $app.Id
            ServicePrincipalId = $sp.Id
            SecretExpiry = $secretEndDate.ToString('yyyy-MM-dd')
            SubscriptionRoles = @('Reader', 'Cost Management Contributor')
            RGRoles = @('Contributor', 'Key Vault Certificates Officer', 'Key Vault Secrets Officer', 'Storage Blob Data Contributor', 'Azure Kubernetes Service RBAC Cluster Admin', 'Monitoring Contributor', 'Role Based Access Control Administrator')
            GraphAppRoles = @('Application.ReadWrite.OwnedBy', 'AgentIdentityBlueprint.AddRemoveCreds.All')
        }

        return @{
            Application = $app
            ServicePrincipal = $sp
            Secret = $passwordCred.SecretText
        }
    }
    catch {
        Write-Log "The script could not create the application registration: $_" -Level Error
        throw
    }
}

function Get-NeologikExistingAppRegistration {
    <#
    .SYNOPSIS
        Reads a deployment service principal that you created. Returns the deployment
        service principal in the same form as New-NeologikAppRegistration. The
        function creates nothing.
    .DESCRIPTION
        The script calls the function when you created the deployment service
        principal and gave the object ID. The function
        creates no application registration, no service principal and no client
        secret. The caller assigns the roles with Set-AppRegistrationRoles, exactly as
        for a deployment service principal that the script creates.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServicePrincipalObjectId,

        [Parameter(Mandatory = $false)]
        [string]$ProvidedSecret = ""
    )

    Write-Log "Using the deployment service principal that you created, object ID $ServicePrincipalObjectId..." -Level Info

    try {
        Import-Module Microsoft.Graph.Applications -ErrorAction Stop

        # Read the service principal by the object ID, to obtain the client ID
        $sp = Get-MgServicePrincipal -ServicePrincipalId $ServicePrincipalObjectId -ErrorAction Stop
        Write-Log "Service principal found: '$($sp.DisplayName)', client ID $($sp.AppId)" -Level Success

        # Read the application object where possible. The read fails when the application
        # belongs to another tenant, or when the permissions of the session do not allow the read.
        $appObjectId = $null
        try {
            $app = Get-MgApplication -Filter "appId eq '$($sp.AppId)'" -ErrorAction SilentlyContinue
            if ($app) { $appObjectId = $app.Id }
        }
        catch {
            Write-Log "The script could not read the application object and continues with the client ID only: $_" -Level Warning
        }

        $requiredRgRoles = @('Contributor', 'Key Vault Certificates Officer', 'Key Vault Secrets Officer', 'Storage Blob Data Contributor', 'Azure Kubernetes Service RBAC Cluster Admin', 'Monitoring Contributor', 'Role Based Access Control Administrator')

        $script:ConfigData['AppRegistration'] = @{
            Name = $sp.DisplayName
            ClientId = $sp.AppId
            ObjectId = $appObjectId
            ServicePrincipalId = $sp.Id
            SecretExpiry = 'client-managed'
            Source = 'client-provided'
            SubscriptionRoles = @('Reader', 'Cost Management Contributor')
            RGRoles = $requiredRgRoles
            GraphAppRoles = @('Application.ReadWrite.OwnedBy', 'AgentIdentityBlueprint.AddRemoveCreds.All')
        }

        Write-Host "`n  Deployment service principal found. The script assigns the Azure roles and the Microsoft Graph application permissions to the deployment service principal." -ForegroundColor Yellow

        return @{
            Application = if ($appObjectId) { $app } else { @{ Id = $null; AppId = $sp.AppId } }
            ServicePrincipal = $sp
            Secret = $ProvidedSecret
        }
    }
    catch {
        Write-Log "The script could not read the deployment service principal '$ServicePrincipalObjectId': $_" -Level Error
        throw "No service principal has the object ID '$ServicePrincipalObjectId'. Check that the value is the object ID of the enterprise application. Check that you are signed in to the correct tenant."
    }
}

function Read-ExistingServicePrincipalChoice {
    <#
    .SYNOPSIS
        Decides whether to use a deployment service principal that you created. When
        the decision is yes, the function obtains the object ID and the client secret.
    .DESCRIPTION
        The function looks at three sources, in this order:
          1. The parameter -ExistingServicePrincipalObjectId. The function uses the
             value and asks no question.
          2. The answer file. The key 'useExistingServicePrincipal' holds true or
             false. With false, the function asks no question. With true, the
             function uses the key 'existingServicePrincipalObjectId' and the key
             'existingServicePrincipalSecret'. The function asks for the object ID
             only when the answer file holds no object ID.
          3. The question on screen. The default answer is No.
    #>
    [CmdletBinding()]
    param(
        [string]$CliObjectId = "",
        [string]$CliSecret = "",
        [object]$AnswerUseExisting = $null,
        [string]$AnswerObjectId = "",
        [string]$AnswerSecret = ""
    )

    # The client secret from the command line applies in every case where the answer file
    # holds no client secret.
    if ([string]::IsNullOrWhiteSpace($AnswerSecret)) { $AnswerSecret = $CliSecret }

    # 1. The command line gave the object ID. Use the object ID and ask no question.
    if (-not [string]::IsNullOrWhiteSpace($CliObjectId)) {
        Write-Log "The command line names a deployment service principal, object ID $($CliObjectId.Trim())." -Level Info
        return @{ UseExisting = $true; ObjectId = $CliObjectId.Trim(); Secret = $CliSecret }
    }

    # 2. The answer file holds the decision.
    if ($null -ne $AnswerUseExisting) {
        $useExisting = [bool]$AnswerUseExisting
        Write-Log "Decision from the answer file: useExistingServicePrincipal=$useExisting." -Level Info
        if (-not $useExisting) {
            return @{ UseExisting = $false; ObjectId = ""; Secret = "" }
        }
        if (-not [string]::IsNullOrWhiteSpace($AnswerObjectId)) {
            return @{ UseExisting = $true; ObjectId = $AnswerObjectId.Trim(); Secret = $AnswerSecret }
        }
        Write-Host "  The answer file sets useExistingServicePrincipal=true and holds no existingServicePrincipalObjectId. Enter the object ID now." -ForegroundColor Yellow
        # Continue, and ask for the object ID only.
    }
    else {
        # 3. No parameter and no answer in the answer file. Ask the question.
        Write-Host ""
        Write-Host "Use a service principal you have already created for deployment?" -ForegroundColor Cyan
        Write-Host "  Choose Y when you created the deployment service principal and want the script to use that service principal." -ForegroundColor Gray
        Write-Host "  Choose N when the script is to create the deployment service principal." -ForegroundColor Gray
        Write-Host "  (y/N, default: N): " -NoNewline -ForegroundColor Yellow
        $answer = Read-Host

        if ($answer -notmatch '^(y|yes)$') {
            return @{ UseExisting = $false; ObjectId = ""; Secret = "" }
        }
    }

    $objectId = ""
    while ([string]::IsNullOrWhiteSpace($objectId)) {
        Write-Host "  Object ID of the enterprise application. Do not enter the client ID or the application ID: " -NoNewline -ForegroundColor Gray
        $objectId = Read-Host
        if ([string]::IsNullOrWhiteSpace($objectId)) {
            Write-Host "  The object ID is required. Enter the object ID, or press Ctrl+C to stop." -ForegroundColor Red
        }
    }

    # Use the client secret from the answer file when present. Otherwise read the client secret at a hidden
    # prompt. The script never shows and never logs the client secret.
    if (-not [string]::IsNullOrWhiteSpace($AnswerSecret)) {
        return @{ UseExisting = $true; ObjectId = $objectId.Trim(); Secret = $AnswerSecret }
    }
    Write-Host "  Client secret. Optional. Press Enter to give no client secret and to add the client secret to the Key Vault later: " -NoNewline -ForegroundColor Gray
    $secureSecret = Read-Host -AsSecureString
    $secretPlain = [System.Net.NetworkCredential]::new("", $secureSecret).Password

    return @{ UseExisting = $true; ObjectId = $objectId.Trim(); Secret = $secretPlain }
}

function Grant-GraphAppRolePermissions {
    <#
    .SYNOPSIS
        Grants Microsoft Graph application permissions to a service principal.
    .DESCRIPTION
        The default set is the set of the deployment identity:
        Application.ReadWrite.OwnedBy and AgentIdentityBlueprint.AddRemoveCreds.All.
        The function makes no change to a permission that is already granted. A new
        service principal takes time to reach every server of Microsoft Entra ID.
        The function tries again until then.

        Application.ReadWrite.OwnedBy includes the read of applications and of service
        principals. The function therefore grants no Application.Read.All.

        With Application.ReadWrite.OwnedBy, the service principal manages only the
        application registrations that the service principal owns. The script
        therefore makes the service principal an owner of each application
        registration that the service principal is to manage.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PrincipalId,

        [Parameter(Mandatory = $false)]
        [string]$PrincipalDescription = 'service principal',

        [Parameter(Mandatory = $false)]
        [string[]]$AppRoles = @('Application.ReadWrite.OwnedBy', 'AgentIdentityBlueprint.AddRemoveCreds.All')
    )

    # The application id of Microsoft Graph, and the id of each application permission of Microsoft Graph
    $graphAppId = '00000003-0000-0000-c000-000000000000'
    $knownGraphAppRoleIds = @{
        # The deployment identity: manage the application registrations that the deployment identity owns,
        # and add and remove credentials on the agent identity blueprint.
        'Application.ReadWrite.OwnedBy'             = '18a4783c-866b-4cc7-a460-3d5e5662c884'
        'AgentIdentityBlueprint.AddRemoveCreds.All' = '0510736e-bdfb-4b37-9a1f-89b4a074763a'
        # The service principal of the agent identity blueprint: create and manage the agent users of
        # that agent identity blueprint only. The creation of agent identities needs no grant. The service
        # principal of each agent identity blueprint can create the agent identities of that agent identity blueprint.
        'AgentIdUser.ReadWrite.IdentityParentedBy'  = '4aa6e624-eee0-40ab-bdd8-f9639038a614'
        # The agent registration identity: write the entry of each Neologik agent in the agent registry of the
        # Microsoft 365 admin center, with a named owner.
        'AgentRegistration.ReadWrite.All'           = '39fb8c64-7bd3-4107-8515-14d6e55ddda4'
    }

    Write-Log "Granting the Microsoft Graph application permissions $($AppRoles -join ', ') to $PrincipalDescription..." -Level Info

    # Find the service principal of Microsoft Graph in this tenant
    try {
        $graphSpResponse = Invoke-MgGraphRequest -Method GET `
            -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$graphAppId'" `
            -ErrorAction Stop
        $graphSpId = $graphSpResponse.value | Select-Object -First 1 -ExpandProperty id
    }
    catch {
        Write-Log "ERROR: the script could not find the service principal of Microsoft Graph: $($_.Exception.Message)" -Level Error
        throw
    }

    if (-not $graphSpId) {
        throw "The script could not find the service principal of Microsoft Graph, application id $graphAppId, in this tenant."
    }

    foreach ($roleName in $AppRoles) {
        $appRoleId = $knownGraphAppRoleIds[$roleName]
        if (-not $appRoleId) {
            throw "The script does not know the Microsoft Graph application permission '$roleName'. Add the id of the permission to `$knownGraphAppRoleIds."
        }

        # Make no change when the service principal already holds the permission
        try {
            $existing = Invoke-MgGraphRequest -Method GET `
                -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments" `
                -ErrorAction Stop
            $alreadyAssigned = $existing.value | Where-Object { $_.appRoleId -eq $appRoleId -and $_.resourceId -eq $graphSpId } | Select-Object -First 1
        }
        catch {
            if ($_.Exception.Message -match "InsufficientPermissions|Insufficient privileges|Authorization_RequestDenied|Forbidden") {
                Write-Log "ERROR: Insufficient permissions to read the Microsoft Graph application permissions" -Level Error
                Write-Host "`n[X] PERMISSION ERROR" -ForegroundColor Red
                Write-Host "The grant of a Microsoft Graph application permission requires the role Privileged Role Administrator or Global Administrator in Microsoft Entra ID." -ForegroundColor Yellow
                throw "Insufficient permissions: cannot read app role assignments"
            }
            $alreadyAssigned = $null
        }

        if ($alreadyAssigned) {
            Write-Log "Microsoft Graph application permission '$roleName' already granted" -Level Info
            continue
        }

        # Grant the permission. A new service principal takes time to reach every server of Microsoft Entra ID. Try again until then
        $retryCount = 0
        $maxRetries = 10
        $roleAssigned = $false

        while (-not $roleAssigned -and $retryCount -lt $maxRetries) {
            try {
                # Send the body as a JSON string. The conversion of a hashtable
                # fails on a string value.
                $body = @{
                    principalId = [string]$PrincipalId
                    resourceId  = [string]$graphSpId
                    appRoleId   = [string]$appRoleId
                } | ConvertTo-Json -Compress
                Invoke-MgGraphRequest -Method POST `
                    -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments" `
                    -Body $body `
                    -ContentType 'application/json' `
                    -ErrorAction Stop | Out-Null
                Write-Log "Microsoft Graph application permission '$roleName' granted" -Level Success
                $roleAssigned = $true
            }
            catch {
                if ($_.Exception.Message -match "already exist|conflicting object|Permission being assigned already exists") {
                    Write-Log "Microsoft Graph application permission '$roleName' already granted. Microsoft Graph reported the existing grant" -Level Info
                    $roleAssigned = $true
                }
                elseif ($_.Exception.Message -match "Forbidden|Authorization_RequestDenied|Insufficient privileges") {
                    Write-Log "ERROR: Insufficient permissions to grant the Microsoft Graph application permission '$roleName'" -Level Error
                    Write-Host "`n[X] PERMISSION ERROR" -ForegroundColor Red
                    Write-Host "Required role: Privileged Role Administrator or Global Administrator in Microsoft Entra ID." -ForegroundColor Yellow
                    throw "Insufficient permissions: cannot assign Graph app role '$roleName'"
                }
                elseif ($_.Exception.Message -match "does not exist|cannot be found|not found|ResourceNotFound") {
                    $retryCount++
                    if ($retryCount -lt $maxRetries) {
                        Write-Log "Microsoft Entra ID does not yet show $PrincipalDescription. The script tries again in 10 seconds. Attempt $retryCount of $maxRetries" -Level Warning
                        Start-Sleep -Seconds 10
                    }
                    else {
                        throw
                    }
                }
                else {
                    throw
                }
            }
        }
    }
}

function Set-NeologikLimitedSubscriptionRole {
    <#
    .SYNOPSIS
        Assigns the limited Role Based Access Control Administrator role to the
        deployment identity on the subscription.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServicePrincipalId,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    Set-NeologikConditionedRole -ObjectId $ServicePrincipalId `
        -Scope "/subscriptions/$SubscriptionId" `
        -Condition $script:LimitedSubRoleCondition `
        -Description 'limited to two roles'
}

function Set-NeologikConditionedRole {
    <#
    .SYNOPSIS
        Assigns Role Based Access Control Administrator at one scope, with a condition.
    .DESCRIPTION
        An assignment that already carries the condition is reported. An assignment without the
        condition, or with another condition, is removed and created again with
        the condition, because Azure keeps the condition of an existing assignment
        on an update. An absent assignment is created.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ObjectId,

        [Parameter(Mandatory = $true)]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [string]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $roleName = $script:LimitedSubRole
    $wanted = ($Condition -replace '\s', '').ToLowerInvariant()
    Write-Log "Assigning the role $roleName, $Description..." -Level Info

    try {
        $assignments = @(Get-AzRoleAssignment -ObjectId $ObjectId `
            -RoleDefinitionName $roleName `
            -Scope $scope `
            -ErrorAction Stop | Where-Object { $_.Scope -eq $scope })
    }
    catch {
        Write-Log "ERROR: the script cannot read the role assignment $roleName, because a permission is missing" -Level Error
        Write-Host "`n[X] INSUFFICIENT PERMISSIONS" -ForegroundColor Red
        Write-Host "The script cannot read the role assignments. The Owner role on the subscription is required." -ForegroundColor Yellow
        throw "Insufficient permissions: Cannot verify role assignments"
    }

    $limited = @($assignments | Where-Object { (([string]$_.Condition) -replace '\s', '').ToLowerInvariant() -eq $wanted })
    if ($limited.Count -gt 0) {
        Write-Log "$roleName role already assigned with the limit" -Level Info
        return
    }
    if ($assignments.Count -gt 0) {
        # The role is held without the limit, or with an older one. Azure keeps the
        # condition of an existing assignment on an update, so the script removes the
        # assignment and creates it again below with the limit. Azure answers a read
        # with the removed assignment for a while, so the script waits until the read
        # no longer returns it before creating the new one.
        Remove-AzRoleAssignment -ObjectId $ObjectId `
            -RoleDefinitionName $roleName `
            -Scope $scope `
            -ErrorAction Stop | Out-Null
        Write-Log "$roleName role: the existing assignment is removed, so the limit can be applied" -Level Info
        $removeChecks = 0
        while ($removeChecks -lt 12) {
            $remaining = @(Get-AzRoleAssignment -ObjectId $ObjectId `
                -RoleDefinitionName $roleName `
                -Scope $scope `
                -ErrorAction SilentlyContinue | Where-Object { $_.Scope -eq $scope })
            if ($remaining.Count -eq 0) { break }
            $removeChecks++
            Write-Log "Azure still shows the removed assignment. The script reads again in 5 seconds. Attempt $removeChecks of 12" -Level Warning
            Start-Sleep -Seconds 5
        }
    }

    # A new service principal takes time to reach every server of Microsoft Entra ID. Try again until then
    $retryCount = 0
    $maxRetries = 10
    $roleAssigned = $false
    while (-not $roleAssigned -and $retryCount -lt $maxRetries) {
        try {
            New-AzRoleAssignment -ObjectId $ObjectId `
                -RoleDefinitionId $script:LimitedSubRoleId `
                -Scope $scope `
                -Condition $Condition `
                -ConditionVersion $script:LimitedSubRoleConditionVersion `
                -ErrorAction Stop | Out-Null

            Write-Log "$roleName role assigned with the limit" -Level Success
            $roleAssigned = $true
        }
        catch {
            if ($_.Exception.Message -match "RoleAssignmentExists|already exists") {
                # The assignment exists: with the limit, the script is done; without it,
                # Azure answered for a removed assignment, and the script tries again.
                $held = @(Get-AzRoleAssignment -ObjectId $ObjectId `
                    -RoleDefinitionName $roleName `
                    -Scope $scope `
                    -ErrorAction SilentlyContinue | Where-Object {
                        $_.Scope -eq $scope -and
                        (([string]$_.Condition) -replace '\s', '').ToLowerInvariant() -eq $wanted })
                if ($held.Count -gt 0) {
                    Write-Log "$roleName role already assigned with the limit" -Level Info
                    $roleAssigned = $true
                }
                else {
                    $retryCount++
                    Write-Log "$roleName role: Azure still shows the removed assignment. The script tries again in 10 seconds. Attempt $retryCount of $maxRetries" -Level Warning
                    Start-Sleep -Seconds 10
                }
            }
            elseif ($_.Exception.Message -match "Forbidden|not authorized") {
                Write-Log "ERROR: Insufficient permissions to assign $roleName role" -Level Error
                Write-Log "Required role: Owner on the subscription" -Level Error
                Write-Host "`n[X] PERMISSION ERROR" -ForegroundColor Red
                Write-Host "A user who holds the Owner role on the subscription must run this script." -ForegroundColor Yellow
                throw "Insufficient permissions: Owner role at subscription level required to assign $roleName"
            }
            elseif ($_.Exception.Message -match "does not exist|cannot be found|BadRequest") {
                $retryCount++
                if ($retryCount -lt $maxRetries) {
                    Write-Log "Microsoft Entra ID does not yet show the new service principal. The script tries again in 10 seconds. Attempt $retryCount of $maxRetries" -Level Warning
                    Start-Sleep -Seconds 10
                }
                else {
                    throw
                }
            }
            else {
                throw
            }
        }
    }
}

function Test-NeologikRoleAssigned {
    <#
    .SYNOPSIS
        Answers whether a principal holds a role at exactly one scope.

    .DESCRIPTION
        Get-AzRoleAssignment -Scope returns the assignments at the scope and
        every assignment inherited from a parent scope. The onboarding script
        needs the assignment at the scope itself. An inherited assignment can
        carry a condition that limits it, and the limited role of the
        deployment identity on the subscription must never stand in for the
        unlimited role on the resource group. An assignment counts when its
        scope is the scope asked for and its condition is the condition asked
        for: none, unless the caller names one.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ObjectId,

        [Parameter(Mandatory = $true)]
        [string]$RoleName,

        [Parameter(Mandatory = $true)]
        [string]$Scope,

        [string]$Condition = ''
    )

    $wanted = ($Condition -replace '\s', '').ToLowerInvariant()
    $assignments = @(Get-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleName -Scope $Scope)
    foreach ($assignment in $assignments) {
        if ([string]$assignment.Scope -ne $Scope) { continue }
        $held = (([string]$assignment.Condition) -replace '\s', '').ToLowerInvariant()
        if ($held -eq $wanted) { return $true }
    }
    return $false
}

function Confirm-NeologikDeploymentIdentityRoles {
    <#
    .SYNOPSIS
        Reads back the Azure roles of the deployment identity and records what it holds.

    .DESCRIPTION
        After the role assignments, the onboarding script reads the assignments
        of the deployment identity at the subscription and at the resource group
        and compares them with the roles the deployment needs. A role counts
        only at its own scope and only with the condition the onboarding script
        gives it: the limited role on the subscription with its condition,
        every other role without one. A new assignment can take a moment to
        appear in a read, so the script reads again, up to six times. A role
        still missing stops the run and names the role and the scope. The
        configuration file and the completion summary record the roles from
        this read, never the list the script set out to assign.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServicePrincipalId,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string[]]$SubscriptionRoles,

        [Parameter(Mandatory = $true)]
        [string[]]$ResourceGroupRoles
    )

    $subScope = "/subscriptions/$SubscriptionId"
    $rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
    $wanted = @()
    foreach ($roleName in $SubscriptionRoles) { $wanted += @{ Role = $roleName; Scope = $subScope; Condition = '' } }
    $wanted += @{ Role = $script:LimitedSubRole; Scope = $subScope; Condition = $script:LimitedSubRoleCondition }
    foreach ($roleName in $ResourceGroupRoles) { $wanted += @{ Role = $roleName; Scope = $rgScope; Condition = '' } }

    Write-Log "Reading back the roles of the deployment identity..." -Level Info
    $missing = @()
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        $missing = @($wanted | Where-Object { -not (Test-NeologikRoleAssigned -ObjectId $ServicePrincipalId -RoleName $_.Role -Scope $_.Scope -Condition $_.Condition -ErrorAction Stop) })
        if ($missing.Count -eq 0) { break }
        if ($attempt -lt 6) {
            Write-Log "Azure does not yet show every role of the deployment identity. The script reads again in 10 seconds. Attempt $attempt of 6" -Level Warning
            Start-Sleep -Seconds 10
        }
    }

    $heldSub = @()
    $heldRg = @()
    foreach ($entry in $wanted) {
        if ($missing -contains $entry) { continue }
        if ($entry.Scope -eq $subScope) { $heldSub += $entry.Role } else { $heldRg += $entry.Role }
    }
    foreach ($roleName in $heldSub) { Write-Log "Confirmed: $roleName on the subscription" -Level Success }
    foreach ($roleName in $heldRg) { Write-Log "Confirmed: $roleName on the resource group" -Level Success }

    if ($script:ConfigData['AppRegistration']) {
        $script:ConfigData['AppRegistration']['SubscriptionRoles'] = $heldSub
        $script:ConfigData['AppRegistration']['RGRoles'] = $heldRg
        $script:ConfigData['AppRegistration']['RolesConfirmedAt'] = if ($missing.Count -eq 0) { Get-Date -Format 'yyyy-MM-dd HH:mm:ss' } else { $null }
    }

    if ($missing.Count -gt 0) {
        $names = @($missing | ForEach-Object { "$($_.Role) on $($_.Scope)" })
        foreach ($name in $names) { Write-Log "MISSING: $name" -Level Error }
        throw "The deployment identity is missing a role: $($names -join '; '). The deployment cannot run without it. Run the onboarding script again with -FreshRun, signed in as an Owner of the subscription"
    }
    return $true
}

function Set-AppRegistrationRoles {
    <#
    .SYNOPSIS
        Assigns the Azure roles of the deployment identity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServicePrincipalId,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [array]$SecurityGroups
    )

    Write-Log "Assigning the roles of the deployment identity..." -Level Info

    try {
        # The deployment identity is not a member of the Admin User Group. A member holds
        # every role of the Admin User Group on the resource group. The deployment identity reaches SQL
        # through the Microsoft Entra administrator setting of the SQL server. The deployment by Neologik
        # sets that administrator.

        # The roles of the deployment identity on the subscription. The deployment identity writes resources in
        # the resource group only. The deployment identity needs two roles on the subscription:
        #   - Reader: the deployment reads usage and quota. Azure holds usage and quota for the subscription
        #     and the Azure region.
        #   - Cost Management Contributor: the deployment deletes any retired budget, cost view and
        #     scheduled cost email. The role covers cost configuration and support requests only.
        $roles = @('Reader', 'Cost Management Contributor')

        foreach ($roleName in $roles) {
            Write-Log "Assigning the role $roleName..." -Level Info

            try {
                $existingAssignment = Test-NeologikRoleAssigned -ObjectId $ServicePrincipalId -RoleName $roleName -Scope "/subscriptions/$SubscriptionId" -ErrorAction Stop
            }
            catch {
                Write-Log "ERROR: the script cannot read the role assignment $roleName, because a permission is missing" -Level Error
                Write-Host "`n[X] INSUFFICIENT PERMISSIONS" -ForegroundColor Red
                Write-Host "The script cannot read the role assignments. The Owner role on the subscription is required." -ForegroundColor Yellow
                throw "Insufficient permissions: Cannot verify role assignments"
            }

            if ($existingAssignment) {
                Write-Log "$roleName role already assigned" -Level Info
            }
            else {
                # A new service principal takes time to reach every server of Microsoft Entra ID. Try again until then
                $retryCount = 0
                $maxRetries = 10
                $roleAssigned = $false

                while (-not $roleAssigned -and $retryCount -lt $maxRetries) {
                    try {
                        New-AzRoleAssignment -ObjectId $ServicePrincipalId `
                            -RoleDefinitionName $roleName `
                            -Scope "/subscriptions/$SubscriptionId" `
                            -ErrorAction Stop | Out-Null

                        Write-Log "$roleName role assigned" -Level Success
                        $roleAssigned = $true
                    }
                    catch {
                        # Azure refused the role assignment because a permission is missing
                        if ($_.Exception.Message -match "Forbidden|not authorized") {
                            Write-Log "ERROR: Insufficient permissions to assign $roleName role" -Level Error
                            Write-Log "Required role: Owner on the subscription" -Level Error
                            Write-Host "`n[X] PERMISSION ERROR" -ForegroundColor Red
                            Write-Host "================================================================" -ForegroundColor Red
                            Write-Host ""
                            Write-Host "The signed-in account lacks a role that the script requires." -ForegroundColor Yellow
                            Write-Host ""
                            Write-Host "Required Permissions:" -ForegroundColor Cyan
                            Write-Host "  [X] Owner role on the subscription: MISSING" -ForegroundColor Red
                            Write-Host "  ? Global Administrator role in Microsoft Entra ID" -ForegroundColor Gray
                            Write-Host ""
                            Write-Host "Current problem: the script cannot assign the role '$roleName' to the service principal." -ForegroundColor Yellow
                            Write-Host ""
                            Write-Host "A user who holds the Owner role on the subscription must run this script." -ForegroundColor Yellow
                            Write-Host ""
                            throw "Insufficient permissions: Owner role at subscription level required to assign $roleName"
                        }
                        elseif ($_.Exception.Message -match "does not exist|cannot be found|BadRequest") {
                            $retryCount++
                            if ($retryCount -lt $maxRetries) {
                                Write-Log "Microsoft Entra ID does not yet show the new service principal. The script tries again in 10 seconds. Attempt $retryCount of $maxRetries" -Level Warning
                                Start-Sleep -Seconds 10
                            }
                            else {
                                throw
                            }
                        }
                        else {
                            throw
                        }
                    }
                }
            }
        }

        # The third role on the subscription: Role Based Access Control Administrator, limited
        # to two roles. The variables at the top of the script hold the condition.
        Set-NeologikLimitedSubscriptionRole -ServicePrincipalId $ServicePrincipalId -SubscriptionId $SubscriptionId

        # The roles of the deployment identity on the resource group. The deployment creates role
        # assignments for the identities of the cluster. The deployment identity therefore needs the role
        # Role Based Access Control Administrator. The role on the resource group has no limit.
        $rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
        $rgRoles = @('Contributor', 'Key Vault Certificates Officer', 'Key Vault Secrets Officer', 'Storage Blob Data Contributor', 'Azure Kubernetes Service RBAC Cluster Admin', 'Monitoring Contributor', 'Role Based Access Control Administrator')

        foreach ($roleName in $rgRoles) {
            Write-Log "Assigning the role $roleName on the resource group..." -Level Info

            $existingAssignment = Test-NeologikRoleAssigned -ObjectId $ServicePrincipalId -RoleName $roleName -Scope $rgScope -ErrorAction SilentlyContinue

            if ($existingAssignment) {
                Write-Log "$roleName role already assigned on the resource group" -Level Info
            }
            else {
                $retryCount = 0
                $maxRetries = 10
                $roleAssigned = $false

                while (-not $roleAssigned -and $retryCount -lt $maxRetries) {
                    try {
                        New-AzRoleAssignment -ObjectId $ServicePrincipalId `
                            -RoleDefinitionName $roleName `
                            -Scope $rgScope `
                            -ErrorAction Stop | Out-Null

                        Write-Log "$roleName role assigned on the resource group" -Level Success
                        $roleAssigned = $true
                    }
                    catch {
                        if ($_.Exception.Message -match "does not exist|cannot be found|BadRequest") {
                            $retryCount++
                            if ($retryCount -lt $maxRetries) {
                                Write-Log "Microsoft Entra ID does not yet show the new service principal. The script tries again in 10 seconds. Attempt $retryCount of $maxRetries" -Level Warning
                                Start-Sleep -Seconds 10
                            }
                            else {
                                throw
                            }
                        }
                        else {
                            throw
                        }
                    }
                }
            }
        }

        # Read the roles back. The configuration file records what the deployment identity holds,
        # and a missing role stops the run here, in front of the administrator.
        $null = Confirm-NeologikDeploymentIdentityRoles -ServicePrincipalId $ServicePrincipalId `
            -SubscriptionId $SubscriptionId `
            -ResourceGroupName $ResourceGroupName `
            -SubscriptionRoles $roles `
            -ResourceGroupRoles $rgRoles

        # Grant the deployment identity two Microsoft Graph application permissions:
        #   - Application.ReadWrite.OwnedBy: create application registrations, and manage only
        #     the application registrations that the deployment identity owns. The permission includes the read of applications and of service principals.
        #   - AgentIdentityBlueprint.AddRemoveCreds.All: add and remove federated credentials on
        #     the agent identity blueprint of the environment. Microsoft publishes no form of
        #     this permission that applies only to the agent identity blueprints that the deployment identity owns.
        # The script does every other action for agent identities once, here, signed in as a Global
        # Administrator, in New-NeologikAgentBlueprint. After the deployment, the agent identity blueprint
        # creates the agent identities and the agent users. The deployment identity therefore holds no permission to
        # create agent identity blueprints, agent identities or agent users, and no
        # permission to create groups. The Neologik Platform creates no group.
        Grant-GraphAppRolePermissions -PrincipalId $ServicePrincipalId -PrincipalDescription 'App Registration service principal' `
            -AppRoles @(
                'Application.ReadWrite.OwnedBy',
                'AgentIdentityBlueprint.AddRemoveCreds.All'
            )

        # Record each group membership in the configuration
        if ($script:ConfigData['AppRegistration'] -and $adminGroup) {
            $script:ConfigData['AppRegistration']['GroupMemberships'] = @($adminGroup.Name)
        }

        return $true
    }
    catch {
        # The script has already reported the refusal caused by a missing permission
        if ($_.Exception.Message -match "Insufficient permissions:|ERROR: Insufficient permissions") {
            throw  # Throw the error again, unchanged
        }
        Write-Log "The script could not assign the roles of the deployment identity: $_" -Level Error
        throw
    }
}

function New-NeologikNceAuthApp {
    <#
    .SYNOPSIS
        Creates the application registration 'Neologik Platform Sign-in' and assigns the
        security groups to the application.

    .DESCRIPTION
        The Neologik Admin Tool reads the security groups of a user from the
        groups claim of the sign-in token. Microsoft Entra ID issues the groups claim
        only for security groups that are assigned to the enterprise application.

        A Global Administrator runs the script. The script therefore makes the
        application registration, the claims, the owners, the client secret and the
        group assignments here. The deployment by Neologik finds the application
        registration by the unique name and maintains the application registration.

        The script assigns two security groups: the NCE Contributors group and the
        NCE Admins group. The Admin User Group holds Azure roles only and gives no
        access to the Neologik Admin Tool.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$SecurityGroups,

        [Parameter(Mandatory = $true)]
        [string]$DeploySpObjectId,

        [Parameter(Mandatory = $true)]
        [string]$KeyVaultName
    )

    Write-Log "Creating the Platform Sign-in application, for the sign-in to the Neologik Admin Tool and to Apps..." -Level Info

    try {
        Import-Module Microsoft.Graph.Applications -ErrorAction Stop
        Import-Module Microsoft.Graph.Groups -ErrorAction Stop

        $solutionName = [string]$script:ConfigData['SolutionName']
        $shortName = [string]$script:ConfigData['SolutionShortName']
        $hostName = [string]$script:ConfigData['HostName']
        # The unique name of the application registration. The deployment by Neologik finds the application registration by the unique name.
        $uniqueName = "sp-admin-$solutionName"
        $displayName = "Neologik Platform Sign-in - $shortName"
        $redirectUri = "https://$hostName/nce"

        # Find the application registration by the unique name, which never changes. A search by display
        # name can miss an application registration with a changed display name, and then create a duplicate.
        $existingApp = $null
        try {
            $found = Invoke-MgGraphRequest -Method GET -Uri "v1.0/applications(uniqueName='$uniqueName')" -ErrorAction Stop
            $existingApp = Get-MgApplication -ApplicationId $found.id -ErrorAction Stop
        }
        catch {
            $existingApp = $null   # Not found. The script creates the application registration below
        }
        $secretText = $null

        if ($existingApp) {
            Write-Log "Application registration '$($existingApp.DisplayName)' already exists, client id $($existingApp.AppId)" -Level Info
            $app = $existingApp
            if ($app.DisplayName -ne $displayName) {
                Update-MgApplication -ApplicationId $app.Id -DisplayName $displayName -ErrorAction Stop
                Write-Log "Application registration renamed to '$displayName'" -Level Info
            }
        }
        else {
            Write-Log "Creating the application registration $displayName..." -Level Info
            $app = New-MgApplication -DisplayName $displayName `
                -UniqueName $uniqueName `
                -SignInAudience "AzureADMultipleOrgs" `
                -GroupMembershipClaims "ApplicationGroup" `
                -Web @{ RedirectUris = @($redirectUri) } `
                -Api @{ RequestedAccessTokenVersion = 2 } `
                -ErrorAction Stop
            Write-Log "Application registration created, client id $($app.AppId)" -Level Success
        }

        $sp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -ErrorAction SilentlyContinue
        if (-not $sp) {
            $sp = New-MgServicePrincipal -AppId $app.AppId -ErrorAction Stop
            Write-Log "Service principal created" -Level Success
        }

        # Make the deployment identity an owner of the application.
        $owners = Get-MgApplicationOwner -ApplicationId $app.Id -ErrorAction SilentlyContinue
        if ($owners -and ($owners.Id -contains $DeploySpObjectId)) {
            Write-Log "The deployment identity is already an owner of the Platform Sign-in application" -Level Info
        }
        else {
            New-MgApplicationOwnerByRef -ApplicationId $app.Id `
                -BodyParameter @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$DeploySpObjectId" } `
                -ErrorAction Stop
            Write-Log "The deployment identity was added as an owner of the Platform Sign-in application" -Level Success
        }

        # Make the deployment identity an owner of the service principal too. Ownership
        # of an application does not include the service principal of the application.
        $spOwners = Get-MgServicePrincipalOwner -ServicePrincipalId $sp.Id -ErrorAction SilentlyContinue
        if ($spOwners -and ($spOwners.Id -contains $DeploySpObjectId)) {
            Write-Log "The deployment identity is already an owner of the service principal of the Platform Sign-in application" -Level Info
        }
        else {
            New-MgServicePrincipalOwnerByRef -ServicePrincipalId $sp.Id `
                -BodyParameter @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$DeploySpObjectId" } `
                -ErrorAction Stop
            Write-Log "The deployment identity was added as an owner of the service principal of the Platform Sign-in application" -Level Success
        }

        # The script stores the client secret in the Key Vault, under the name that the deployment by Neologik
        # reads. The script creates a client secret only when the application is new, or when the Key Vault holds no client secret.
        # The deployment by Neologik renews a client secret that is close to the expiry date.
        $kvSecretName = "$uniqueName-auth-secret"
        $existingKvSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $kvSecretName -ErrorAction SilentlyContinue
        if ($existingKvSecret) {
            Write-Log "The Key Vault already holds '$kvSecretName'. The script keeps the existing client secret" -Level Info
        }
        else {
            $passwordCred = Add-MgApplicationPassword -ApplicationId $app.Id `
                -PasswordCredential @{ DisplayName = 'auth'; EndDateTime = (Get-Date).AddDays(365) } `
                -ErrorAction Stop
            $secretText = $passwordCred.SecretText
            $secureSecret = ConvertTo-SecureString -String $secretText -AsPlainText -Force
            $null = Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $kvSecretName -SecretValue $secureSecret -ErrorAction Stop
            Write-Log "Client secret stored in the Key Vault as '$kvSecretName'" -Level Success
        }

        # Assign the two security groups for roles. The sign-in token of a member then names the
        # security groups in the groups claim. The Neologik Admin Tool reads the groups claim. The script
        # uses the default access role. Only a direct member counts. A group inside a group does not appear in the groups claim.
        $defaultAppRole = '00000000-0000-0000-0000-000000000000'
        $assignedGroups = @()
        foreach ($rolePattern in @('Neologik NCE Contributors*', 'Neologik NCE Admins*')) {
            $roleGroup = $SecurityGroups | Where-Object { $_.Name -like $rolePattern } | Select-Object -First 1
            if (-not $roleGroup) {
                Write-Log "Warning: no security group matches '$rolePattern'. The script made no group assignment for this name. A Global Administrator must assign the security group in the Microsoft Entra admin centre, under Enterprise applications, Users and groups." -Level Warning
                continue
            }
            $alreadyAssigned = Get-MgGroupAppRoleAssignment -GroupId $roleGroup.Id -ErrorAction SilentlyContinue |
                Where-Object { $_.ResourceId -eq $sp.Id }
            if ($alreadyAssigned) {
                Write-Log "Security group '$($roleGroup.Name)' is already assigned to the Platform Sign-in application" -Level Info
            }
            else {
                $null = New-MgGroupAppRoleAssignment -GroupId $roleGroup.Id `
                    -PrincipalId $roleGroup.Id `
                    -ResourceId $sp.Id `
                    -AppRoleId $defaultAppRole `
                    -ErrorAction Stop
                Write-Log "Security group '$($roleGroup.Name)' assigned to the Platform Sign-in application. The sign-in token of a member now names the security group" -Level Success
            }
            $assignedGroups += $roleGroup.Name
        }

        $script:ConfigData['NceAuthApp'] = @{
            Name = $displayName
            ClientId = $app.AppId
            ObjectId = $app.Id
            ServicePrincipalId = $sp.Id
            UniqueName = $uniqueName
            KeyVaultSecretName = $kvSecretName
            AssignedGroups = $assignedGroups
        }

        return $script:ConfigData['NceAuthApp']
    }
    catch {
        Write-Log "The script could not create the Platform Sign-in application: $_" -Level Error
        throw
    }
}

function New-NeologikAgentBlueprint {
    <#
    .SYNOPSIS
        Creates the agent identity blueprint of the environment and the service
        principal of the agent identity blueprint. The deployment identity owns both.
        The function also creates the federated credentials that let the deployment by
        Neologik sign in as the agent identity blueprint.

    .DESCRIPTION
        The creation of an agent identity blueprint, of the service principal and of
        the credentials needs Microsoft Graph permissions for the whole tenant. The
        script therefore does these actions here, once, signed in as a Global
        Administrator. The deployment identity receives none of these permissions.

        After onboarding, the deployment by Neologik does two things:
          1. As the deployment identity, the deployment maintains the federated
             credential of the agent identity service on the agent identity blueprint.
             The permission is AgentIdentityBlueprint.AddRemoveCreds.All.
          2. As the agent identity blueprint, the deployment creates agent identities
             and agent users. The deployment signs in with the federated credentials
             created below.

        The service principal of an agent identity blueprint can create the agent
        identities of that agent identity blueprint. The creation of agent users
        needs the permission AgentIdUser.ReadWrite.IdentityParentedBy. The function
        grants that permission to the service principal of the agent identity
        blueprint. The permission applies only to the agent users of that agent
        identity blueprint.

        The function creates only what is absent: the agent identity blueprint, the
        owner, the service principal, the Microsoft Graph permission and each
        credential. The function finds the agent identity blueprint by display name.
        The display name is 'Neologik Agent Blueprint - <key> - <short name>'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DeploySpObjectId,

        [Parameter(Mandatory = $true)]
        [string]$SponsorUserId,

        [Parameter(Mandatory = $false)]
        [string]$BlueprintKey = 'default'
    )

    $shortName = [string]$script:ConfigData['SolutionShortName']
    $displayName = "Neologik Agent Blueprint - $BlueprintKey - $shortName"
    $graph = 'https://graph.microsoft.com/v1.0'
    $graphBeta = 'https://graph.microsoft.com/beta'
    $odataHeaders = @{ 'OData-Version' = '4.0' }
    # The repositories of the Neologik deployment that may obtain a token as the agent identity blueprint.
    # Each credential names the repository by the repository id, which never changes. A
    # repository that is renamed or copied gains nothing.
    $pipelineRepositories = @(
        @{ Name = 'neo-infrastructure'; Id = '995398788' },
        @{ Name = 'neo-bot-service';    Id = '995400343' },
        @{ Name = 'neo-env-config';     Id = '995441655' }
    )

    Write-Log "Looking for the agent identity blueprint '$displayName'..." -Level Info

    try {
        # 1. The blueprint application, created if no application holds the display name.
        #    The body is sent as a JSON string.
        $escaped = $displayName -replace "'", "''"
        $found = Invoke-MgGraphRequest -Method GET -Uri "$graph/applications?`$filter=displayName eq '$escaped'&`$select=id,appId" -ErrorAction Stop
        $blueprint = @($found.value) | Select-Object -First 1
        $blueprintExisted = [bool]$blueprint
        if ($blueprint) {
            Write-Log "The agent identity blueprint already exists, client id $($blueprint.appId)" -Level Info
        }
        else {
            $body = @{
                '@odata.type'        = 'Microsoft.Graph.AgentIdentityBlueprint'
                displayName          = $displayName
                'sponsors@odata.bind' = @("$graph/users/$SponsorUserId")
                'owners@odata.bind'   = @("$graph/directoryObjects/$DeploySpObjectId")
            } | ConvertTo-Json -Depth 5 -Compress
            $blueprint = Invoke-MgGraphRequest -Method POST -Uri "$graph/applications/microsoft.graph.agentIdentityBlueprint" `
                -Headers $odataHeaders -Body $body -ContentType 'application/json' -ErrorAction Stop
            Write-Log "Agent identity blueprint created, client id $($blueprint.appId). The sponsor is the signed-in administrator" -Level Success
        }
        $blueprintObjectId = [string]$blueprint.id
        $blueprintAppId = [string]$blueprint.appId

        # 2. The deployment identity as an owner of the blueprint application.
        $owners = Invoke-MgGraphRequest -Method GET -Uri "$graph/applications/$blueprintObjectId/owners?`$select=id" -ErrorAction Stop
        if (@($owners.value | ForEach-Object { $_.id }) -contains $DeploySpObjectId) {
            Write-Log "The deployment identity is already an owner of the agent identity blueprint" -Level Info
        }
        else {
            $ref = @{ '@odata.id' = "$graph/directoryObjects/$DeploySpObjectId" } | ConvertTo-Json -Compress
            Invoke-MgGraphRequest -Method POST -Uri "$graph/applications/$blueprintObjectId/owners/`$ref" -Body $ref -ContentType 'application/json' -ErrorAction Stop | Out-Null
            Write-Log "The deployment identity was added as an owner of the agent identity blueprint" -Level Success
        }

        # 2b. The sponsor of the agent identity blueprint. The sponsor is the person who is accountable for the
        #     agents of the environment. Each agent identity that the Neologik Platform creates takes the sponsor
        #     of the agent identity blueprint. A new agent identity blueprint has the signed-in administrator as
        #     the sponsor. The script adds the signed-in administrator to an agent identity blueprint that exists
        #     with no sponsor.
        if ($blueprintExisted) {
            $sponsorsUri = "$graph/applications/$blueprintObjectId/microsoft.graph.agentIdentityBlueprint/sponsors"
            $sponsors = Invoke-MgGraphRequest -Method GET -Uri "$sponsorsUri`?`$select=id,displayName" -ErrorAction Stop
            $sponsorNames = @($sponsors.value | ForEach-Object { if ($_.displayName) { [string]$_.displayName } else { [string]$_.id } })
            if ($sponsorNames.Count -gt 0) {
                Write-Log "The sponsor of the agent identity blueprint: $($sponsorNames -join ', ')" -Level Info
            }
            else {
                $ref = @{ '@odata.id' = "$graph/directoryObjects/$SponsorUserId" } | ConvertTo-Json -Compress
                Invoke-MgGraphRequest -Method POST -Uri "$sponsorsUri/`$ref" -Body $ref -ContentType 'application/json' -ErrorAction Stop | Out-Null
                Write-Log "The signed-in administrator was added as the sponsor of the agent identity blueprint" -Level Success
            }
        }

        # 3. The service principal of the agent identity blueprint, created when absent. A new application takes
        #    time to reach every server of Microsoft Entra ID. The script tries the creation again until then.
        $principal = $null
        $sp = Invoke-MgGraphRequest -Method GET -Uri "$graph/servicePrincipals?`$filter=appId eq '$blueprintAppId'&`$select=id" -ErrorAction Stop
        $principal = @($sp.value) | Select-Object -First 1
        if ($principal) {
            Write-Log "The service principal of the agent identity blueprint already exists" -Level Info
        }
        else {
            # The request binds the deployment identity as an owner. Microsoft Graph accepts an owner in the
            # request that creates the service principal.
            $body = @{ appId = $blueprintAppId; 'owners@odata.bind' = @("$graph/directoryObjects/$DeploySpObjectId") } | ConvertTo-Json -Compress
            for ($attempt = 1; $attempt -le 10; $attempt++) {
                try {
                    $principal = Invoke-MgGraphRequest -Method POST -Uri "$graph/servicePrincipals/microsoft.graph.agentIdentityBlueprintPrincipal" `
                        -Headers $odataHeaders -Body $body -ContentType 'application/json' -ErrorAction Stop
                    Write-Log "Service principal of the agent identity blueprint created" -Level Success
                    break
                }
                catch {
                    if ($attempt -lt 10 -and ($_.Exception.Message -match 'local tenant|does not exist')) {
                        Write-Log "Microsoft Entra ID does not yet show the new agent identity blueprint. The script tries again in 15 seconds. Attempt $attempt of 10" -Level Warning
                        Start-Sleep -Seconds 15
                        continue
                    }
                    throw
                }
            }
        }
        $principalId = [string]$principal.id

        # 4. The deployment identity as an owner of the service principal too. Ownership of an
        #    application does not include the service principal of the application.
        $spOwners = Invoke-MgGraphRequest -Method GET -Uri "$graph/servicePrincipals/$principalId/owners?`$select=id" -ErrorAction Stop
        if (@($spOwners.value | ForEach-Object { $_.id }) -contains $DeploySpObjectId) {
            Write-Log "The deployment identity is already an owner of the service principal of the agent identity blueprint" -Level Info
        }
        else {
            $ref = @{ '@odata.id' = "$graph/directoryObjects/$DeploySpObjectId" } | ConvertTo-Json -Compress
            Invoke-MgGraphRequest -Method POST -Uri "$graph/servicePrincipals/$principalId/owners/`$ref" -Body $ref -ContentType 'application/json' -ErrorAction Stop | Out-Null
            Write-Log "The deployment identity was added as an owner of the service principal of the agent identity blueprint" -Level Success
        }

        # 5. The Microsoft Graph role of the blueprint principal: the agent users of this blueprint only.
        Grant-GraphAppRolePermissions -PrincipalId $principalId -PrincipalDescription 'agent identity blueprint principal' `
            -AppRoles @('AgentIdUser.ReadWrite.IdentityParentedBy')

        # 6. The federated credentials, one for each repository, created when absent. The script stores no
        #    secret. The deployment by Neologik exchanges the token of the Neologik deployment service
        #    for a token of the agent identity blueprint.
        $existingCreds = Invoke-MgGraphRequest -Method GET -Uri "$graphBeta/applications/$blueprintObjectId/federatedIdentityCredentials?`$select=name" -ErrorAction Stop
        $existingNames = @($existingCreds.value | ForEach-Object { $_.name })
        $credentialNames = @()
        foreach ($repo in $pipelineRepositories) {
            $credName = "github-oidc-$($repo.Name)"
            $credentialNames += $credName
            if ($existingNames -contains $credName) {
                Write-Log "Federated credential '$credName' already exists" -Level Info
                continue
            }
            $expression = "claims['sub'] matches 'repo:Neologik-AI/$($repo.Name):*' and claims['repository_id'] eq '$($repo.Id)'"
            $body = @{
                name                     = $credName
                issuer                   = 'https://token.actions.githubusercontent.com'
                audiences                = @('api://AzureADTokenExchange')
                description              = "This federated credential lets a Neologik deployment run in the Neologik GitHub repository $($repo.Name) sign in as this agent identity blueprint with no stored secret. The Neologik deployment then creates the agent identities and the agent users of this environment."
                claimsMatchingExpression = @{ value = $expression; languageVersion = 1 }
            } | ConvertTo-Json -Depth 5 -Compress
            Invoke-MgGraphRequest -Method POST -Uri "$graphBeta/applications/$blueprintObjectId/federatedIdentityCredentials" `
                -Body $body -ContentType 'application/json' -ErrorAction Stop | Out-Null
            Write-Log "Federated credential '$credName' created" -Level Success
        }

        $script:ConfigData['AgentBlueprint'] = @{
            Key = $BlueprintKey
            DisplayName = $displayName
            ClientId = $blueprintAppId
            ObjectId = $blueprintObjectId
            PrincipalId = $principalId
            GitHubCredentials = $credentialNames
        }
        return $script:ConfigData['AgentBlueprint']
    }
    catch {
        Write-Log "The script could not create the agent identity blueprint: $_" -Level Error
        throw
    }
}

#endregion

#region Key Vault

function Set-NeologikDeploymentCredential {
    <#
    .SYNOPSIS
        Adds one federated credential to the application registration of the deployment
        identity. The Neologik deployment can then sign in as the deployment identity
        with no stored secret. The federated credential accepts only a Neologik
        deployment run that names this environment, and adds no permission.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$EnvironmentName
    )

    $credentialName = "github-deployments-$EnvironmentName"
    # The id of the Neologik deployment organisation never changes. GitHub writes the name of the
    # organisation in the subject in one of two forms, so the expression holds a wildcard straight
    # after the name and also checks the id.
    $expression = "claims['sub'] matches 'repo:Neologik-AI*:environment:$EnvironmentName' and claims['repository_owner_id'] eq '109681438'"
    Write-Log "Adding the federated credential '$credentialName' to the deployment identity..." -Level Info

    try {
        # A new application registration takes time to reach every server of Microsoft Entra ID. Try again until then
        $objectId = $null
        $retryCount = 0
        $maxRetries = 10
        while (-not $objectId) {
            $apps = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=appId eq '$ClientId'&`$select=id" -ErrorAction Stop
            $objectId = @($apps.value | ForEach-Object { $_.id }) | Select-Object -First 1
            if (-not $objectId) {
                $retryCount++
                if ($retryCount -ge $maxRetries) {
                    throw "This tenant holds no application registration with the client ID $ClientId. The deployment service principal must come from an application registration in this tenant"
                }
                Write-Log "Microsoft Entra ID does not yet show the application registration. The script tries again in 10 seconds. Attempt $retryCount of $maxRetries" -Level Warning
                Start-Sleep -Seconds 10
            }
        }

        $uri = "https://graph.microsoft.com/beta/applications/$objectId/federatedIdentityCredentials"
        $existing = Invoke-MgGraphRequest -Method GET -Uri "${uri}?`$select=name" -ErrorAction Stop
        if (@($existing.value | ForEach-Object { $_.name }) -contains $credentialName) {
            Write-Log "Federated credential '$credentialName' already exists" -Level Info
        }
        else {
            $body = @{
                name                     = $credentialName
                issuer                   = 'https://token.actions.githubusercontent.com'
                audiences                = @('api://AzureADTokenExchange')
                description              = "This federated credential lets a Neologik deployment run for the environment $EnvironmentName sign in as the deployment identity with no stored secret. The federated credential adds no permission."
                claimsMatchingExpression = @{ value = $expression; languageVersion = 1 }
            } | ConvertTo-Json -Depth 5 -Compress
            Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType 'application/json' -ErrorAction Stop | Out-Null
            Write-Log "Federated credential '$credentialName' created" -Level Success
        }

        $script:ConfigData['DeploymentCredential'] = @{
            Name = $credentialName
            EnvironmentName = $EnvironmentName
        }
        return $script:ConfigData['DeploymentCredential']
    }
    catch {
        Write-Log "The script could not add the federated credential to the deployment identity: $_" -Level Error
        throw
    }
}

function New-NeologikKeyVault {
    <#
    .SYNOPSIS
        Creates the Key Vault and stores the client secret of the deployment identity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$KeyVaultName,

        # Optional. The value is empty when you created the deployment service principal and gave no client secret.
        # The script then creates the Key Vault and stores no client secret.
        [Parameter(Mandatory = $false)]
        [string]$ClientSecret = "",

        [Parameter(Mandatory = $true)]
        [array]$SecurityGroups,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )

    Write-Log "Creating the Key Vault..." -Level Info

    try {
        Import-Module Az.KeyVault -ErrorAction Stop

        # Confirm the resource provider Microsoft.KeyVault before the creation. Step 5c submitted the registration
        Confirm-ResourceProviderReady -Namespaces @('Microsoft.KeyVault')

        # Check whether the Key Vault exists
        $existingKv = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName -ErrorAction SilentlyContinue

        if ($existingKv) {
            Write-Log "Key Vault '$KeyVaultName' already exists" -Level Info
            $keyVault = $existingKv
        }
        else {
            Write-Log "Creating the Key Vault $KeyVaultName..." -Level Info
            
            # Create Key Vault
            # The script applies the tags at creation. The value is empty when the administrator chooses no tags.
            $tagParams = @{}
            $resourceTags = Get-NeologikResourceTags
            if ($resourceTags) { $tagParams['Tag'] = $resourceTags }
            $keyVault = New-AzKeyVault -ResourceGroupName $ResourceGroupName `
                -VaultName $KeyVaultName `
                -Location $Location `
                @tagParams `
                -ErrorAction Stop

            # Turn on Azure role-based access control
            Write-Log "Turning on Azure role-based access control on the Key Vault..." -Level Info
            try {
                # The parameter is a switch
                Update-AzKeyVault -ResourceGroupName $ResourceGroupName `
                    -VaultName $KeyVaultName `
                    -EnableRbacAuthorization `
                    -ErrorAction Stop
            }
            catch {
                if ($_.Exception.Message -match "parameter.*EnableRbacAuthorization|Cannot find") {
                    # A version of the module without the switch: set the property on the resource
                    Write-Log "Turning on Azure role-based access control through Azure Resource Manager..." -Level Warning
                    
                    $keyVaultResource = Get-AzResource -ResourceId "/subscriptions/$((Get-AzContext).Subscription.Id)/resourceGroups/$ResourceGroupName/providers/Microsoft.KeyVault/vaults/$KeyVaultName"
                    $keyVaultResource.Properties.enableRbacAuthorization = $true
                    $null = Set-AzResource -ResourceId $keyVaultResource.ResourceId -Properties $keyVaultResource.Properties -Force
                }
                else {
                    throw
                }
            }

            Write-Log "Key Vault created, with Azure role-based access control" -Level Success
            
            # Read the Key Vault again
            $keyVault = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -VaultName $KeyVaultName
        }

        # The scope of the role assignments: the resource group
        $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
        $rgScope = $resourceGroup.ResourceId

        # Assign Key Vault Secrets Officer to the signed-in user first, so that the script can store the client secret
        Write-Log "Assigning the role Key Vault Secrets Officer to the signed-in user..." -Level Info
        if ($script:ConfigData['CurrentUserId']) {
            $existingUserAssignment = Test-NeologikRoleAssigned -ObjectId $script:ConfigData['CurrentUserId'] -RoleName 'Key Vault Secrets Officer' -Scope $rgScope -ErrorAction SilentlyContinue

            if (-not $existingUserAssignment) {
                New-AzRoleAssignment -ObjectId $script:ConfigData['CurrentUserId'] `
                    -RoleDefinitionName 'Key Vault Secrets Officer' `
                    -Scope $rgScope `
                    -ErrorAction Stop | Out-Null
                Write-Log "Role Key Vault Secrets Officer assigned to the signed-in user" -Level Success
                
                # Wait until the role assignment is active
                Write-Log "Waiting 15 seconds until the role assignment is active..." -Level Info
                Start-Sleep -Seconds 15
            }
            else {
                Write-Log "The signed-in user already holds the role Key Vault Secrets Officer" -Level Info
            }
        }

        # Assign the Key Vault roles of the Admin User Group, on the resource group
        $adminGroup = $SecurityGroups | Where-Object { $_.Name -like 'Neologik Admin User Group*' }

        if ($adminGroup) {
            foreach ($roleName in @('Key Vault Secrets Officer', 'Key Vault Certificates Officer')) {
                Write-Log "Assigning the role $roleName to $($adminGroup.Name) on the resource group..." -Level Info

                $existingAssignment = Test-NeologikRoleAssigned -ObjectId $adminGroup.Id -RoleName $roleName -Scope $rgScope -ErrorAction SilentlyContinue

                if ($existingAssignment) {
                    Write-Log "$roleName role already assigned to $($adminGroup.Name) on the resource group" -Level Info
                }
                else {
                    New-AzRoleAssignment -ObjectId $adminGroup.Id `
                        -RoleDefinitionName $roleName `
                        -Scope $rgScope `
                        -ErrorAction Stop | Out-Null

                    Write-Log "$roleName role assigned to $($adminGroup.Name) on the resource group" -Level Success
                }
            }
        }

        # Store the client secret. Try again until the role assignment is active. The value is empty
        # when you created the deployment service principal and gave no client secret. The script then
        # creates the Key Vault, and you add the client secret to the Key Vault.
        $secretName = "neologik-deployment-service-principle-secret"

        if ([string]::IsNullOrWhiteSpace($ClientSecret)) {
            Write-Log "No client secret was given. The script stores nothing. Add the secret '$secretName' to the Key Vault '$KeyVaultName' before the first deployment." -Level Warning
            Write-Host "`n  [!] The script created the Key Vault and stored no client secret of the deployment identity." -ForegroundColor Yellow
            Write-Host "    Add the secret '$secretName' to '$KeyVaultName' before the first deployment." -ForegroundColor Yellow
        }
        else {
            Write-Log "Storing the client secret of the deployment identity in the Key Vault..." -Level Info

            $retryCount = 0
            $maxRetries = 10
            $secretStored = $false

            while (-not $secretStored -and $retryCount -lt $maxRetries) {
                try {
                    $secureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
                    $null = Set-AzKeyVaultSecret -VaultName $KeyVaultName `
                        -Name $secretName `
                        -SecretValue $secureSecret `
                        -ErrorAction Stop

                    Write-Log "Client secret stored as '$secretName'" -Level Success
                    $secretStored = $true
                }
                catch {
                    if ($_.Exception.Message -match "Forbidden|not authorized") {
                        $retryCount++
                        if ($retryCount -lt $maxRetries) {
                            Write-Log "The role assignment is not yet active. The script tries again in 10 seconds. Attempt $retryCount of $maxRetries" -Level Warning
                            Start-Sleep -Seconds 10
                        }
                        else {
                            throw
                        }
                    }
                    else {
                        throw
                    }
                }
            }
        }

        $script:ConfigData['KeyVault'] = @{
            Name = $keyVault.VaultName
            ResourceId = $keyVault.ResourceId
            VaultUri = $keyVault.VaultUri
            SecretName = $secretName
        }

        return $keyVault
    }
    catch {
        Write-Log "The script could not create the Key Vault: $_" -Level Error
        throw
    }
}

#endregion

#region Resource Provider Registration

# The resource providers of the resources that the script creates: the resource group, the Key Vault,
# the storage account, the managed identities, and Microsoft.Compute for the storage account. The script submits
# these registrations at step 5c, after the check of the roles, and confirms each registration before the script
# creates the resource. The script submits every other entry at step 15b, after the managed identities.
# resource-providers.txt must list each of these resource providers.
$script:OnboardingProviders = @(
    'Microsoft.Resources',
    'Microsoft.KeyVault',
    'Microsoft.Storage',
    'Microsoft.ManagedIdentity',
    'Microsoft.Compute'
)

function Get-PlatformResourceProviderList {
    <#
    .SYNOPSIS
        Reads resource-providers.txt. The file lists the Azure resource providers and
        the preview features that the Neologik Platform requires.
    .DESCRIPTION
        The file holds one entry on each line. The function ignores a blank line. Text
        after '#' is a comment.
        A resource provider has the form Microsoft.Storage.
        A preview feature has the form Microsoft.Compute/EncryptionAtHost.
        The function fails in four cases: the file is missing, the file is empty, a
        line has the wrong form, or the file lacks a resource provider that the script
        needs.
        The function returns Providers, OnboardingProviders, PlatformProviders and
        Features. Providers holds the resource providers that the script needs first,
        then the other resource providers in the order of the file. OnboardingProviders
        holds the first group. PlatformProviders holds the second group.
    #>
    [CmdletBinding()]
    param()

    $path = Join-Path $PSScriptRoot 'resource-providers.txt'
    if (-not (Test-Path $path)) {
        throw "Resource provider list not found: $path. The file is part of the onboarding kit. Copy the file to the folder of the script and run the script again."
    }

    $providers = [System.Collections.Generic.List[string]]::new()
    $featureKeys = [System.Collections.Generic.List[string]]::new()
    $features = @()
    $lineNumber = 0
    foreach ($raw in @(Get-Content -Path $path)) {
        $lineNumber++
        # Text from '#' to the end of the line is a comment. The '#' can stand anywhere on the line.
        $line = ("$raw" -split '#', 2)[0].Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^(?<ns>[A-Za-z0-9]+\.[A-Za-z0-9.]+)/(?<feature>[A-Za-z0-9]+)$') {
            if (-not $featureKeys.Contains($line)) {
                $featureKeys.Add($line)
                $features += @{ Provider = $Matches.ns; Feature = $Matches.feature }
            }
        }
        elseif ($line -match '^[A-Za-z0-9]+\.[A-Za-z0-9.]+$') {
            if (-not $providers.Contains($line)) { $providers.Add($line) }
        }
        else {
            throw "resource-providers.txt line ${lineNumber}: '$line' is not valid. A resource provider has the form Microsoft.Example. A preview feature has the form Microsoft.Example/FeatureName."
        }
    }
    if ($providers.Count -eq 0) { throw "resource-providers.txt lists no resource provider." }

    $missing = @($script:OnboardingProviders | Where-Object { -not $providers.Contains($_) })
    if ($missing.Count -gt 0) {
        throw "resource-providers.txt lacks resource providers that the onboarding script needs: $($missing -join ', ')."
    }
    foreach ($f in $features) {
        if (-not $providers.Contains($f.Provider)) {
            throw "resource-providers.txt lists the preview feature $($f.Provider)/$($f.Feature) without the resource provider $($f.Provider)."
        }
    }

    $platformProviders = @($providers | Where-Object { $script:OnboardingProviders -notcontains $_ })
    $ordered = @($script:OnboardingProviders) + $platformProviders
    Write-Log "Resource provider list read from ${path}: $($ordered.Count) resource providers and $($features.Count) preview features" -Level Info
    return [pscustomobject]@{
        Providers           = [string[]]$ordered
        OnboardingProviders = [string[]]@($script:OnboardingProviders)
        PlatformProviders   = [string[]]$platformProviders
        Features            = @($features)
        Path                = $path
    }
}

function Start-ResourceProviderRegistration {
    <#
    .SYNOPSIS
        Submits the registration of the given resource providers and preview
        features. The function does not wait for the registrations.
    .DESCRIPTION
        Azure completes a registration while the script continues. Step 5c submits
        the resource providers that the script needs. Step 15b submits the other
        resource providers and the preview features.
        Wait-ResourceProviderRegistration confirms the registrations later.

        The function makes no change to an entry that is already registered in Azure
        or recorded in the checkpoint.

        The run stops when Azure refuses a request. Two causes are possible: the
        resource provider or the preview feature does not exist, or a permission is
        missing.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Providers = @(),
        [hashtable[]]$Features = @()
    )

    Write-Log "Submitting the registrations of $($Providers.Count) resource providers and $($Features.Count) preview features..." -Level Info
    $submitted = 0
    $alreadyRegistered = 0

    foreach ($ns in $Providers) {
        if ($script:ProviderRegistrations[$ns] -eq 'Registered') { $alreadyRegistered++; continue }
        try {
            $state = (Get-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Select-Object -First 1).RegistrationState
            if ($state -eq 'Registered') {
                $script:ProviderRegistrations[$ns] = 'Registered'
                $alreadyRegistered++
                continue
            }
            if ($state -ne 'Registering') {
                Register-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Out-Null
            }
            $script:ProviderRegistrations[$ns] = 'Requested'
            $submitted++
            Write-Log "Registration submitted: $ns. The state was $state" -Level Info
        }
        catch {
            Write-Log "The script could not submit the registration of the resource provider '$ns': $_" -Level Error
            throw
        }
    }

    foreach ($f in $Features) {
        $key = "$($f.Provider)/$($f.Feature)"
        if ($script:ProviderRegistrations[$key] -eq 'Registered') { $alreadyRegistered++; continue }
        try {
            $state = (Get-AzProviderFeature -ProviderNamespace $f.Provider -FeatureName $f.Feature -ErrorAction Stop).RegistrationState
            if ($state -eq 'Registered') {
                $script:ProviderRegistrations[$key] = 'Registered'
                $alreadyRegistered++
                continue
            }
            if ($state -notin @('Registering', 'Pending')) {
                Register-AzProviderFeature -ProviderNamespace $f.Provider -FeatureName $f.Feature -ErrorAction Stop | Out-Null
            }
            $script:ProviderRegistrations[$key] = 'Requested'
            $submitted++
            Write-Log "Registration of preview feature submitted: $key. The state was $state" -Level Info
        }
        catch {
            Write-Log "The script could not submit the registration of the preview feature '$key': $_" -Level Error
            throw
        }
    }

    Save-Checkpoint -Label 'ProvidersRequested'
    Write-Host "  Resource providers: $submitted registrations submitted, $alreadyRegistered already registered." -ForegroundColor Gray
    Write-Host "  Azure completes the registrations. The script confirms each registration before the script needs it." -ForegroundColor Gray
    Write-Log "Resource provider registrations submitted: $submitted. Already registered: $alreadyRegistered" -Level Success
}

function Wait-ResourceProviderRegistration {
    <#
    .SYNOPSIS
        Confirms that the given resource providers and preview features are
        registered. The function checks all entries together.
    .DESCRIPTION
        The function returns the entries that are still not registered at the end of
        the wait. The function returns no entry when every entry is confirmed. The
        function records the returned entries in the checkpoint.

        When Azure reports an entry as not registered, the function submits the entry
        once more. When a preview feature becomes registered, the function registers
        the resource provider again. The preview feature then becomes active on the
        resource provider.
    #>
    [CmdletBinding()]
    param(
        [string[]]$Providers = @(),
        [hashtable[]]$Features = @(),
        [int]$TimeoutSeconds = 600,
        [int]$IntervalSeconds = 15
    )

    $pendingProviders = [System.Collections.Generic.List[string]]::new()
    foreach ($ns in $Providers) {
        if ($script:ProviderRegistrations[$ns] -ne 'Registered') { $pendingProviders.Add($ns) }
    }
    $pendingFeatures = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($f in $Features) {
        if ($script:ProviderRegistrations["$($f.Provider)/$($f.Feature)"] -ne 'Registered') { $pendingFeatures.Add($f) }
    }
    if ($pendingProviders.Count -eq 0 -and $pendingFeatures.Count -eq 0) { return @() }

    Write-Log "Waiting for $($pendingProviders.Count) resource providers and $($pendingFeatures.Count) preview features. The wait ends after ${TimeoutSeconds} seconds..." -Level Info
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $resubmitted = @{}

    while ($true) {
        $changed = $false

        foreach ($ns in @($pendingProviders)) {
            try {
                $state = (Get-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Select-Object -First 1).RegistrationState
            }
            catch {
                Write-Log "The script could not read the state of the resource provider '$ns': $_" -Level Warning
                continue
            }
            if ($state -eq 'Registered') {
                $script:ProviderRegistrations[$ns] = 'Registered'
                $pendingProviders.Remove($ns) | Out-Null
                $changed = $true
                Write-Log "Resource provider registered: $ns" -Level Success
            }
            elseif ($state -ne 'Registering' -and -not $resubmitted[$ns]) {
                Write-Log "Resource provider '$ns' reports the state $state. The script submits the registration again" -Level Warning
                $resubmitted[$ns] = $true
                try { Register-AzResourceProvider -ProviderNamespace $ns -ErrorAction Stop | Out-Null }
                catch { Write-Log "The second registration of the resource provider '$ns' failed: $_" -Level Warning }
            }
        }

        foreach ($f in @($pendingFeatures)) {
            $key = "$($f.Provider)/$($f.Feature)"
            try {
                $state = (Get-AzProviderFeature -ProviderNamespace $f.Provider -FeatureName $f.Feature -ErrorAction Stop).RegistrationState
            }
            catch {
                Write-Log "The script could not read the state of the preview feature '$key': $_" -Level Warning
                continue
            }
            if ($state -eq 'Registered') {
                try { Register-AzResourceProvider -ProviderNamespace $f.Provider -ErrorAction Stop | Out-Null }
                catch { Write-Log "The second registration of the resource provider failed, after the preview feature '$key' registered: $_" -Level Warning }
                $script:ProviderRegistrations[$key] = 'Registered'
                $pendingFeatures.Remove($f) | Out-Null
                $changed = $true
                Write-Log "Preview feature registered: $key" -Level Success
            }
            elseif ($state -notin @('Registering', 'Pending') -and -not $resubmitted[$key]) {
                Write-Log "Preview feature '$key' reports the state $state. The script submits the registration again" -Level Warning
                $resubmitted[$key] = $true
                try { Register-AzProviderFeature -ProviderNamespace $f.Provider -FeatureName $f.Feature -ErrorAction Stop | Out-Null }
                catch { Write-Log "The second registration of the preview feature '$key' failed: $_" -Level Warning }
            }
        }

        if ($changed) { Save-Checkpoint -Label 'ProvidersConfirmed' }
        if ($pendingProviders.Count -eq 0 -and $pendingFeatures.Count -eq 0) { break }
        if ((Get-Date) -ge $deadline) { break }
        Write-Host "  Registrations still in progress: $($pendingProviders.Count + $pendingFeatures.Count)..." -ForegroundColor Gray
        Start-Sleep -Seconds $IntervalSeconds
    }

    $remaining = @($pendingProviders) + @($pendingFeatures | ForEach-Object { "$($_.Provider)/$($_.Feature)" })
    if ($remaining.Count -gt 0) {
        foreach ($key in $remaining) { $script:ProviderRegistrations[$key] = 'TimedOut' }
        Save-Checkpoint -Label 'ProvidersTimedOut'
    }
    return $remaining
}

function Confirm-ResourceProviderReady {
    <#
    .SYNOPSIS
        Confirms that the named resource providers are registered, before the script
        creates a resource of that type. Step 5c submitted the registrations. The
        function stops the run with a clear message when a resource provider is still
        registering.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Namespaces
    )

    $remaining = Wait-ResourceProviderRegistration -Providers $Namespaces -TimeoutSeconds 600
    if ($remaining.Count -eq 0) {
        Write-Log "Resource providers confirmed: $($Namespaces -join ', ')" -Level Info
        return
    }
    Write-Host ""
    Write-Host "  Resource providers that the script needs are still registering: $($remaining -join ', ')" -ForegroundColor Yellow
    Write-Host "  Azure completes the registration without further action. Wait a few minutes. Then run the script" -ForegroundColor Yellow
    Write-Host "  again and choose Y to resume. The script does not repeat a confirmed registration." -ForegroundColor Yellow
    Write-Host ""
    throw "Resource providers still registering: $($remaining -join ', '). Run the script again and resume when the registrations are complete."
}

function Complete-ResourceProviderRegistration {
    <#
    .SYNOPSIS
        Confirms every resource provider and every preview feature in the list, before
        the script writes the configuration file. The function reports each entry
        that is still in progress and records the entry in the configuration file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ProviderList
    )

    Write-Log "Confirming every resource provider in the list..." -Level Info
    $remaining = Wait-ResourceProviderRegistration -Providers $ProviderList.Providers -Features $ProviderList.Features -TimeoutSeconds 600
    $script:ConfigData['ResourceProvidersPending'] = @($remaining)
    if ($remaining.Count -eq 0) {
        Write-Log "All $($ProviderList.Providers.Count) resource providers and $($ProviderList.Features.Count) preview features are registered" -Level Success
        Write-Host "  Resource providers: all $($ProviderList.Providers.Count) resource providers and $($ProviderList.Features.Count) preview features are registered." -ForegroundColor Green
        return
    }
    Write-Host ""
    Write-Host "  These registrations are not yet complete. Azure completes the registrations without further action:" -ForegroundColor Yellow
    $remaining | ForEach-Object { Write-Host "     - $_" -ForegroundColor Yellow }
    Write-Host "  Before the deployment, run Register-NeologikResourceProviders.ps1 on this subscription to confirm the registrations." -ForegroundColor Gray
    Write-Host "  The configuration file lists the registrations under ResourceProvidersPending." -ForegroundColor Gray
    Write-Host ""
    Write-Log "Resource provider registrations still in progress: $($remaining -join ', ')" -Level Warning
}

#endregion

#region Storage Account

function New-NeologikStorageAccount {
    <#
    .SYNOPSIS
        Creates the deployment storage account and the containers of the deployment
        storage account.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [array]$SecurityGroups
    )

    Write-Log "Creating the storage account..." -Level Info

    try {
        Import-Module Az.Storage -ErrorAction Stop

        # Confirm the resource provider Microsoft.Storage before the creation. Step 5c submitted the registration
        Confirm-ResourceProviderReady -Namespaces @('Microsoft.Storage')

        # Check whether the storage account exists
        $existingSa = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue

        if ($existingSa) {
            Write-Log "Storage account '$StorageAccountName' already exists" -Level Info
            $storageAccount = $existingSa
        }
        else {
            Write-Log "Creating the storage account $StorageAccountName..." -Level Info
            
            # The script applies the tags at creation. The value is empty when the administrator chooses no tags.
            $tagParams = @{}
            $resourceTags = Get-NeologikResourceTags
            if ($resourceTags) { $tagParams['Tag'] = $resourceTags }
            $storageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName `
                -Name $StorageAccountName `
                -Location $Location `
                -SkuName Standard_LRS `
                -Kind StorageV2 `
                -AllowBlobPublicAccess $false `
                @tagParams `
                -ErrorAction Stop

            Write-Log "Storage account created" -Level Success
        }

        # Turn off shared key access. The storage account then accepts Microsoft Entra ID authentication only
        Write-Log "Setting the storage account to Microsoft Entra authentication..." -Level Info
        Set-AzStorageAccount -ResourceGroupName $ResourceGroupName `
            -Name $StorageAccountName `
            -AllowSharedKeyAccess $false `
            -ErrorAction Stop | Out-Null
        
        Write-Log "The storage account uses Microsoft Entra authentication. Shared key access is turned off" -Level Success

        # Create the containers through Azure Resource Manager. A call to the storage service needs a
        # storage token. A sign-in made with an access token cannot obtain a storage token, and shared
        # key access is turned off above.
        $certContainerName = "certificate"
        $jsonContainerName = "json"
        $logsContainerName = "logs"

        foreach ($containerName in @($certContainerName, $jsonContainerName, $logsContainerName)) {
            Write-Log "Creating the container '$containerName'..." -Level Info
            $existingContainer = Get-AzRmStorageContainer -ResourceGroupName $ResourceGroupName `
                -StorageAccountName $StorageAccountName `
                -ContainerName $containerName `
                -ErrorAction SilentlyContinue

            if ($existingContainer) {
                Write-Log "Container '$containerName' already exists" -Level Info
            }
            else {
                New-AzRmStorageContainer -ResourceGroupName $ResourceGroupName `
                    -StorageAccountName $StorageAccountName `
                    -ContainerName $containerName `
                    -PublicAccess None -ErrorAction Stop | Out-Null
                Write-Log "Container '$containerName' created" -Level Success
            }
        }

        # The scope of the role assignments: the resource group
        $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction Stop
        $rgScope = $resourceGroup.ResourceId

        # Assign Storage Blob Data Contributor to the signed-in user first, so that the script can upload the log and the configuration file
        Write-Log "Assigning the role Storage Blob Data Contributor to the signed-in user..." -Level Info
        if ($script:ConfigData['CurrentUserId']) {
            $existingUserAssignment = Test-NeologikRoleAssigned -ObjectId $script:ConfigData['CurrentUserId'] -RoleName 'Storage Blob Data Contributor' -Scope $rgScope -ErrorAction SilentlyContinue

            if (-not $existingUserAssignment) {
                New-AzRoleAssignment -ObjectId $script:ConfigData['CurrentUserId'] `
                    -RoleDefinitionName 'Storage Blob Data Contributor' `
                    -Scope $rgScope `
                    -ErrorAction Stop | Out-Null
                Write-Log "Role Storage Blob Data Contributor assigned to the signed-in user" -Level Success
                
                # Wait until the role assignment is active
                Write-Log "Waiting 15 seconds until the role assignment is active..." -Level Info
                Start-Sleep -Seconds 15
            }
            else {
                Write-Log "The signed-in user already holds the role Storage Blob Data Contributor" -Level Info
            }
        }

        # Assign Storage Blob Data Contributor to the Admin User Group, on the resource group
        $adminGroup = $SecurityGroups | Where-Object { $_.Name -like 'Neologik Admin User Group*' }
        
        if ($adminGroup) {
            Write-Log "Assigning the role Storage Blob Data Contributor to $($adminGroup.Name) on the resource group..." -Level Info
            
            $existingAssignment = Test-NeologikRoleAssigned -ObjectId $adminGroup.Id -RoleName 'Storage Blob Data Contributor' -Scope $rgScope -ErrorAction SilentlyContinue

            if ($existingAssignment) {
                Write-Log "Storage Blob Data Contributor role already assigned to $($adminGroup.Name) on the resource group" -Level Info
            }
            else {
                New-AzRoleAssignment -ObjectId $adminGroup.Id `
                    -RoleDefinitionName 'Storage Blob Data Contributor' `
                    -Scope $rgScope `
                    -ErrorAction Stop | Out-Null

                Write-Log "Storage Blob Data Contributor role assigned to $($adminGroup.Name) on the resource group" -Level Success
            }
        }

        $script:ConfigData['StorageAccount'] = @{
            Name = $storageAccount.StorageAccountName
            ResourceId = $storageAccount.Id
            BlobEndpoint = $storageAccount.PrimaryEndpoints.Blob
            CertificateContainerName = $certContainerName
            JsonContainerName = $jsonContainerName
            LogsContainerName = $logsContainerName
        }

        return $storageAccount
    }
    catch {
        Write-Log "The script could not create the storage account: $_" -Level Error
        throw
    }
}

#endregion

#region Managed Identity

function New-NeologikManagedIdentities {
    <#
    .SYNOPSIS
        Creates the three user-assigned managed identities and assigns the roles of
        each.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $false)]
        [string]$OrganizationCode = "",

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentType = "",

        [Parameter(Mandatory = $false)]
        [string]$EnvironmentIndex = "",

        [Parameter(Mandatory = $false)]
        [string]$ScriptRunnerIdentityName = "",

        [Parameter(Mandatory = $false)]
        [string]$SqlIdentityName = "",

        [Parameter(Mandatory = $false)]
        [string]$DirectoryIdentityName = "",

        [Parameter(Mandatory = $false)]
        [string]$SystemTaskIdentityName = ""
    )

    Write-Log "Creating the managed identities..." -Level Info

    try {
        Import-Module Az.ManagedServiceIdentity -ErrorAction Stop

        # Confirm the resource provider Microsoft.ManagedIdentity before the creation. Step 5c submitted the registration
        Confirm-ResourceProviderReady -Namespaces @('Microsoft.ManagedIdentity')

        # The last part of the name of each managed identity is the short name.
        $shortName = if (-not [string]::IsNullOrWhiteSpace([string]$script:ConfigData['SolutionShortName'])) { [string]$script:ConfigData['SolutionShortName'] }
                     elseif ([string]::IsNullOrWhiteSpace($OrganizationCode)) { "" }
                     else { "neo$($OrganizationCode.ToLower())$EnvironmentIndex" }
        $nameSuffix = if ([string]::IsNullOrWhiteSpace($shortName)) { "" } else { "-$shortName" }
        $displaySuffix = if ([string]::IsNullOrWhiteSpace($shortName)) { "" } else { " - $shortName" }

        # The script decided the names of the managed identities when the script collected the configuration.
        # When a checkpoint holds no name, the script uses the standard name.
        $scriptRunnerName = if (-not [string]::IsNullOrWhiteSpace($ScriptRunnerIdentityName)) { $ScriptRunnerIdentityName.Trim() } else { "neologik-script-runner-service-connection$nameSuffix" }
        $sqlIdentityName = if (-not [string]::IsNullOrWhiteSpace($SqlIdentityName)) { $SqlIdentityName.Trim() } else { "neologik-sql-managed-identity$nameSuffix" }
        $directoryIdentityName = if (-not [string]::IsNullOrWhiteSpace($DirectoryIdentityName)) { $DirectoryIdentityName.Trim() } else { "neologik-directory-managed-identity$nameSuffix" }
        $systemTaskIdentityName = if (-not [string]::IsNullOrWhiteSpace($SystemTaskIdentityName)) { $SystemTaskIdentityName.Trim() } else { "neologik-system-task-managed-identity$nameSuffix" }

        $managedIdentities = @(
            @{
                Name = $scriptRunnerName
                DisplayName = "Neologik Script Runner Service Connection$displaySuffix"
                # The deployment runs scripts inside Azure as this managed identity. The scripts read the cluster and
                # the runner virtual machine. The scripts read and write secrets in the Key Vault. Every one of these
                # resources is in the resource group. The managed identity holds no role on the subscription.
                Roles = @()
                RGRoles = @('Reader', 'Key Vault Secrets Officer', 'Azure Bot Service Contributor Role')
                # The script runner identity receives no Microsoft Graph application permission.
            },
            @{
                Name = $sqlIdentityName
                DisplayName = "Neologik SQL Managed Identity$displaySuffix"
                Roles = @()
                EntraRole = 'Directory Readers'
            },
            @{
                Name = $directoryIdentityName
                DisplayName = "Neologik Agent Registration Identity$displaySuffix"
                # From version 5.2 of the Neologik Platform, this managed identity creates and changes the application
                # registrations of Neologik agents from inside the environment, and records each Neologik agent in the
                # agent registry of the Microsoft 365 admin center with a named owner. Application.ReadWrite.OwnedBy
                # changes only the application registrations that the managed identity owns. AgentRegistration.ReadWrite.All
                # writes the agent registry entries of the Neologik agents. The managed identity holds no Azure role.
                # Nothing can sign in as the managed identity until a deployment by Neologik adds the sign-in credential.
                Roles = @()
                GraphAppRoles = @('Application.ReadWrite.OwnedBy', 'AgentRegistration.ReadWrite.All')
            },
            @{
                Name = $systemTaskIdentityName
                DisplayName = "Neologik System Task Managed Identity$displaySuffix"
                # From version 5.2 of the Neologik Platform, this managed identity creates the identities and role
                # assignments of Neologik agents from inside the environment. The condition at the top of this script
                # limits the role. Nothing can sign in as the managed identity until a deployment by Neologik adds the
                # sign-in credential.
                Roles = @()
                ResourceGroupRoleStandard = $true
            }
        )

        $createdIdentities = @()

        # The script applies the tags at creation. The value is empty when the administrator chooses no tags.
        $tagParams = @{}
        $resourceTags = Get-NeologikResourceTags
        if ($resourceTags) { $tagParams['Tag'] = $resourceTags }

        foreach ($miDef in $managedIdentities) {
            $displayName = if ($miDef.DisplayName) { $miDef.DisplayName } else { $miDef.Name }
            Write-Log "Looking for the managed identity $displayName..." -Level Info

            # Look for the managed identity
            $existingMI = Get-AzUserAssignedIdentity -ResourceGroupName $ResourceGroupName -Name $miDef.Name -ErrorAction SilentlyContinue

            if ($existingMI) {
                Write-Log "Managed identity '$displayName' already exists, principal id $($existingMI.PrincipalId)" -Level Info
                $mi = $existingMI
            }
            else {
                Write-Log "Creating the managed identity $displayName..." -Level Info
                
                try {
                    $mi = New-AzUserAssignedIdentity -ResourceGroupName $ResourceGroupName `
                        -Name $miDef.Name `
                        -Location $Location `
                        @tagParams `
                        -ErrorAction Stop

                    Write-Log "Managed identity created, principal id $($mi.PrincipalId)" -Level Success
                }
                catch {
                    Write-Log "ERROR: the script could not create the managed identity '$displayName'" -Level Error
                    Write-Log "Error details: $($_.Exception.Message)" -Level Error
                    if ($_.Exception.InnerException) {
                        Write-Log "Inner exception: $($_.Exception.InnerException.Message)" -Level Error
                    }
                    throw
                }
            }

            # Assign the roles on the subscription
            foreach ($roleName in $miDef.Roles) {
                Write-Log "Assigning the role $roleName to $displayName on the subscription..." -Level Info

                $existingAssignment = Test-NeologikRoleAssigned -ObjectId $mi.PrincipalId -RoleName $roleName -Scope "/subscriptions/$SubscriptionId" -ErrorAction SilentlyContinue

                if ($existingAssignment) {
                    Write-Log "$roleName role already assigned" -Level Info
                }
                else {
                    $retryCount = 0
                    $maxRetries = 10
                    $assigned = $false

                    while (-not $assigned -and $retryCount -lt $maxRetries) {
                        try {
                            New-AzRoleAssignment -ObjectId $mi.PrincipalId `
                                -RoleDefinitionName $roleName `
                                -Scope "/subscriptions/$SubscriptionId" `
                                -ErrorAction Stop | Out-Null
                            $assigned = $true
                            Write-Log "$roleName role assigned" -Level Success
                        }
                        catch {
                            $retryCount++
                            if ($retryCount -lt $maxRetries) {
                                Write-Log "The script tries the role assignment again in 10 seconds. Attempt $retryCount of $maxRetries" -Level Warning
                                Start-Sleep -Seconds 10
                            }
                            else {
                                throw
                            }
                        }
                    }
                }
            }

            # Assign the roles on the resource group
            if ($miDef.RGRoles) {
                $rgScope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"
                foreach ($roleName in $miDef.RGRoles) {
                    Write-Log "Assigning the role $roleName to $displayName on the resource group..." -Level Info

                    $existingAssignment = Test-NeologikRoleAssigned -ObjectId $mi.PrincipalId -RoleName $roleName -Scope $rgScope -ErrorAction SilentlyContinue

                    if ($existingAssignment) {
                        Write-Log "$roleName role already assigned on the resource group" -Level Info
                    }
                    else {
                        $retryCount = 0
                        $maxRetries = 10
                        $assigned = $false

                        while (-not $assigned -and $retryCount -lt $maxRetries) {
                            try {
                                New-AzRoleAssignment -ObjectId $mi.PrincipalId `
                                    -RoleDefinitionName $roleName `
                                    -Scope $rgScope `
                                    -ErrorAction Stop | Out-Null
                                $assigned = $true
                                Write-Log "$roleName role assigned on the resource group" -Level Success
                            }
                            catch {
                                $retryCount++
                                if ($retryCount -lt $maxRetries) {
                                    Write-Log "The script tries the role assignment again in 10 seconds. Attempt $retryCount of $maxRetries" -Level Warning
                                    Start-Sleep -Seconds 10
                                }
                                else {
                                    throw
                                }
                            }
                        }
                    }
                }
            }

            # Assign the Microsoft Entra directory role
            if ($miDef.EntraRole) {
                Write-Log "Assigning the directory role $($miDef.EntraRole) in Microsoft Entra ID..." -Level Info
                
                Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop
                
                $entraRole = Get-MgDirectoryRole -Filter "displayName eq '$($miDef.EntraRole)'" -ErrorAction SilentlyContinue
                
                if (-not $entraRole) {
                    # directoryRoleTemplates accepts no filter. The script therefore lists the templates and finds the
                    # match here. This branch runs only in a tenant where the role was never
                    # activated.
                    $roleTemplate = Get-MgDirectoryRoleTemplate -All -ErrorAction Stop |
                        Where-Object { $_.DisplayName -eq $miDef.EntraRole } | Select-Object -First 1
                    if (-not $roleTemplate) {
                        throw "Directory role template '$($miDef.EntraRole)' not found in tenant $($script:ConfigData['TenantId'])."
                    }
                    Write-Log "Activating the directory role '$($miDef.EntraRole)' from the role template. This tenant uses the directory role for the first time..." -Level Info
                    $entraRole = New-MgDirectoryRole -RoleTemplateId $roleTemplate.Id -ErrorAction Stop
                }

                if ($entraRole) {
                    # A new managed identity takes time to reach every server of Microsoft Entra ID. Try again until then
                    $retryCount = 0
                    $maxRetries = 10
                    $roleAssigned = $false

                    while (-not $roleAssigned -and $retryCount -lt $maxRetries) {
                        try {
                            # Look for an existing membership
                            $existingRoleMember = Get-MgDirectoryRoleMember -DirectoryRoleId $entraRole.Id -ErrorAction SilentlyContinue | Where-Object { $_.Id -eq $mi.PrincipalId }

                            if ($existingRoleMember) {
                                Write-Log "$($miDef.EntraRole) role already assigned" -Level Info
                                $roleAssigned = $true
                            }
                            else {
                                # Add the member
                                $body = @{
                                    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($mi.PrincipalId)"
                                }
                                New-MgDirectoryRoleMemberByRef -DirectoryRoleId $entraRole.Id -BodyParameter $body -ErrorAction Stop
                                Write-Log "$($miDef.EntraRole) role assigned" -Level Success
                                $roleAssigned = $true
                            }
                        }
                        catch {
                            # The managed identity is already a member
                            if ($_.Exception.Message -match "already exist") {
                                Write-Log "$($miDef.EntraRole) role already assigned. Microsoft Graph reported the existing membership" -Level Info
                                $roleAssigned = $true
                            }
                            # The managed identity has not yet reached every server of Microsoft Entra ID
                            elseif ($_.Exception.Message -match "does not exist" -or $_.Exception.Message -match "NotFound") {
                                $retryCount++
                                if ($retryCount -lt $maxRetries) {
                                    Write-Log "Microsoft Entra ID does not yet show the new managed identity. The script tries again in 10 seconds. Attempt $retryCount of $maxRetries" -Level Warning
                                    Start-Sleep -Seconds 10
                                }
                                else {
                                    throw
                                }
                            }
                            else {
                                throw
                            }
                        }
                    }
                }
            }

            # The role that lets the managed identity assign roles inside the resource group
            if ($miDef.ResourceGroupRoleStandard) {
                Set-NeologikConditionedRole -ObjectId $mi.PrincipalId `
                    -Scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName" `
                    -Condition $script:ResourceGroupRoleCondition `
                    -Description 'limited so that the identity cannot assign Owner, User Access Administrator or this role'
            }

            # Grant the Microsoft Graph application permissions defined for the identity, if any
            if ($miDef.GraphAppRoles) {
                Grant-GraphAppRolePermissions -PrincipalId $mi.PrincipalId `
                    -PrincipalDescription "Managed Identity '$($miDef.Name)'" `
                    -AppRoles $miDef.GraphAppRoles
            }

            $createdIdentities += @{
                Name = $mi.Name
                PrincipalId = $mi.PrincipalId
                ClientId = $mi.ClientId
                ResourceId = $mi.Id
                SubscriptionRoles = $miDef.Roles
                RGRoles = $miDef.RGRoles
                EntraRole = $miDef.EntraRole
                GraphAppRoles = $miDef.GraphAppRoles
                GroupMemberships = @()  # The script adds no managed identity to a security group
            }
        }

        $script:ConfigData['ManagedIdentities'] = $createdIdentities
        return $createdIdentities
    }
    catch {
        Write-Log "The script could not create the managed identities: $_" -Level Error
        throw
    }
}

#endregion

#region Output and Reporting

function Copy-NeologikFileToStorage {
    <#
    .SYNOPSIS
        Uploads a file to a container of the storage account. The function reads the
        blob to confirm the upload. Returns $true or $false. The function tries again
        until the role assignment is active.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [int]$MaxRetries = 12
    )

    $blobName = Split-Path -Leaf $FilePath
    try {
        # A storage session that uses Microsoft Entra ID authentication
        $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
    }
    catch {
        Write-Log "The script could not open a storage session for '$StorageAccountName': $_" -Level Warning
        return $false
    }

    $retryCount = 0
    while ($retryCount -lt $MaxRetries) {
        try {
            Set-AzStorageBlobContent -File $FilePath `
                -Container $ContainerName `
                -Blob $blobName `
                -Context $ctx `
                -Force `
                -ErrorAction Stop | Out-Null
            # Read the blob. Success then means that the file is in the container
            $null = Get-AzStorageBlob -Container $ContainerName -Blob $blobName -Context $ctx -ErrorAction Stop
            Write-Log "$Description uploaded to the storage account: $StorageAccountName/$ContainerName/$blobName" -Level Success
            return $true
        }
        catch {
            $retryCount++
            if ($retryCount -lt $MaxRetries) {
                Write-Log "The role assignment for the storage account is not yet active. The script tries again in 20 seconds. Attempt $retryCount of $MaxRetries" -Level Warning
                Start-Sleep -Seconds 20
            }
            else {
                Write-Log "The script could not upload $Description to the storage account after $MaxRetries attempts. The file remains on the workstation at ${FilePath}: $_" -Level Warning
            }
        }
    }
    return $false
}

function Export-ConfigurationData {
    <#
    .SYNOPSIS
        Writes the configuration file and shows the completion summary.
    #>
    [CmdletBinding()]
    param()

    Write-Log "Writing the configuration file..." -Level Info

    try {
        # After a resumed run, the custom tags can be an object. Write the custom tags in the
        # same form. The value is an empty object when the administrator chooses no tags.
        $exportCustomTags = if ($null -ne $script:ConfigData['ResourceTagsCustom']) { $script:ConfigData['ResourceTagsCustom'] } else { @{} }

        # The output. The order of the fields is fixed
        $orderedConfig = [ordered]@{
            'ScriptVersion' = $script:Version
            'KitVersion' = $script:KitVersion
            'GeneratedAt' = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            'OrganizationName' = $script:OrganizationName
            'OrganizationCode' = $script:OrganizationCode
            'TenantName' = $script:ConfigData['TenantName']
            'TenantId' = $script:ConfigData['TenantId']
            'SubscriptionName' = $script:ConfigData['SubscriptionName']
            'SubscriptionId' = $script:ConfigData['SubscriptionId']
            'ResourceGroupName' = $script:ConfigData['ResourceGroupName']
            'SolutionName' = $script:ConfigData['SolutionName']
            'SolutionShortName' = $script:ConfigData['SolutionShortName']
            'UserAccount' = $script:ConfigData['UserAccount']
            'AzureRegion' = $script:ConfigData['AzureRegion']
            'HostName' = $script:ConfigData['HostName']
            'ResourceProvidersPending' = @($script:ConfigData['ResourceProvidersPending'])
            'ResourceTagsEnabled' = [bool]$script:ConfigData['ResourceTagsEnabled']
            'ResourceTagsCustom' = $exportCustomTags
            'InvitedGuestUsers' = $script:ConfigData['InvitedGuestUsers']
            'ExistingAccountsAdded' = $script:ConfigData['ExistingAccountsAdded']
            'SecurityGroups' = $script:ConfigData['SecurityGroups']
            'AppRegistration' = $script:ConfigData['AppRegistration']
            'NceAuthApp' = $script:ConfigData['NceAuthApp']
            'AgentBlueprint' = $script:ConfigData['AgentBlueprint']
            'DeploymentCredential' = $script:ConfigData['DeploymentCredential']
            'KeyVault' = $script:ConfigData['KeyVault']
            'StorageAccount' = $script:ConfigData['StorageAccount']
            'ManagedIdentities' = $script:ConfigData['ManagedIdentities']
            'RoleAssignments' = $script:ConfigData['RoleAssignments']
        }

        # Write the JSON file
        $orderedConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:OutputFile -Encoding UTF8
        Write-Log "Configuration file written: $script:OutputFile" -Level Success

        # Upload the configuration file and the log, and record the result. Neologik reads the
        # configuration file from the container 'json'. The completion summary therefore shows
        # a failed upload. An unattended run tries the upload once, because a sign-in made with
        # an access token cannot authenticate the upload.
        $uploadRetries = if ($script:NonInteractiveMode) { 1 } else { 12 }
        $script:ConfigData['ConfigUploadedToStorage'] = $false
        $script:ConfigData['LogUploadedToStorage'] = $false
        if ($script:ConfigData['StorageAccount']) {
            Write-Log "Uploading the configuration file to the storage account..." -Level Info
            $script:ConfigData['ConfigUploadedToStorage'] = Copy-NeologikFileToStorage `
                -FilePath $script:OutputFile `
                -StorageAccountName $script:ConfigData['StorageAccount'].Name `
                -ContainerName $script:ConfigData['StorageAccount'].JsonContainerName `
                -Description "Configuration file" `
                -MaxRetries $uploadRetries

            Write-Log "Uploading the log to the storage account..." -Level Info
            $script:ConfigData['LogUploadedToStorage'] = Copy-NeologikFileToStorage `
                -FilePath $script:LogFile `
                -StorageAccountName $script:ConfigData['StorageAccount'].Name `
                -ContainerName $script:ConfigData['StorageAccount'].LogsContainerName `
                -Description "Log file" `
                -MaxRetries $uploadRetries
        }

        # Show the summary
        Write-Host "`n" -NoNewline
        Write-Host "+===============================================================+" -ForegroundColor Green
        Write-Host "|                                                               |" -ForegroundColor Green
        Write-Host "|          NEOLOGIK ONBOARDING COMPLETED SUCCESSFULLY           |" -ForegroundColor Green
        Write-Host "|                                                               |" -ForegroundColor Green
        Write-Host "+===============================================================+" -ForegroundColor Green
        Write-Host "`n"

        Write-Host "Configuration Summary:" -ForegroundColor Cyan
        Write-Host "=======================" -ForegroundColor Cyan
        Write-Host ""

        # Tenant
        Write-Host "Tenant Information:" -ForegroundColor Yellow
        Write-Host "  Tenant ID: $($script:ConfigData['TenantId'])"
        Write-Host "  Tenant Name: $($script:ConfigData['TenantName'])"
        Write-Host ""

        # Subscription
        Write-Host "Subscription Information:" -ForegroundColor Yellow
        Write-Host "  Subscription Name: $($script:ConfigData['SubscriptionName'])"
        Write-Host "  Subscription ID: $($script:ConfigData['SubscriptionId'])"
        Write-Host ""

        # Resource Group
        Write-Host "Resource Group:" -ForegroundColor Yellow
        Write-Host "  Name: $($script:ConfigData['ResourceGroupName'])"
        Write-Host "  Region: $($script:ConfigData['AzureRegion'])"
        Write-Host ""

        # Security Groups
        Write-Host "Security Groups:" -ForegroundColor Yellow
        foreach ($group in $script:ConfigData['SecurityGroups']) {
            Write-Host "  - $($group.Name)"
            Write-Host "    ID: $($group.Id)"
        }
        Write-Host ""

        # Deployment identity
        if ($script:ConfigData['AppRegistration']) {
            Write-Host "App Registration:" -ForegroundColor Yellow
            Write-Host "  Name: $($script:ConfigData['AppRegistration'].Name)"
            Write-Host "  Client ID: $($script:ConfigData['AppRegistration'].ClientId)"
            if ($script:ConfigData['AppRegistration'].RolesConfirmedAt) {
                Write-Host "  Roles on the subscription, confirmed:   $(@($script:ConfigData['AppRegistration'].SubscriptionRoles) -join ', ')"
                Write-Host "  Roles on the resource group, confirmed: $(@($script:ConfigData['AppRegistration'].RGRoles) -join ', ')"
            }
            Write-Host ""
        }

        # Key Vault
        if ($script:ConfigData['KeyVault']) {
            Write-Host "Key Vault:" -ForegroundColor Yellow
            Write-Host "  Name: $($script:ConfigData['KeyVault'].Name)"
            Write-Host "  Vault URI: $($script:ConfigData['KeyVault'].VaultUri)"
            Write-Host "  Secret Name: $($script:ConfigData['KeyVault'].SecretName)"
            Write-Host ""
        }

        # Storage Account
        if ($script:ConfigData['StorageAccount']) {
            Write-Host "Storage Account:" -ForegroundColor Yellow
            Write-Host "  Name: $($script:ConfigData['StorageAccount'].Name)"
            Write-Host "  Blob Endpoint: $($script:ConfigData['StorageAccount'].BlobEndpoint)"
            Write-Host "  Certificate Container: $($script:ConfigData['StorageAccount'].CertificateContainerName)"
            Write-Host "  JSON Container: $($script:ConfigData['StorageAccount'].JsonContainerName)"
            Write-Host "  Logs Container: $($script:ConfigData['StorageAccount'].LogsContainerName)"
            Write-Host ""
        }

        # Managed Identities
        Write-Host "Managed Identities:" -ForegroundColor Yellow
        foreach ($mi in $script:ConfigData['ManagedIdentities']) {
            Write-Host "  - $($mi.Name)"
            Write-Host "    Principal ID: $($mi.PrincipalId)"
        }
        Write-Host ""

        Write-Host "Output Files:" -ForegroundColor Yellow
        Write-Host "  Configuration file on the workstation:     $script:OutputFile" -ForegroundColor Cyan
        if ($script:ConfigData['ConfigUploadedToStorage']) {
            Write-Host "  Configuration file in the storage account: $($script:ConfigData['StorageAccount'].Name)/$($script:ConfigData['StorageAccount'].JsonContainerName)/$(Split-Path -Leaf $script:OutputFile)" -ForegroundColor Cyan
        }
        Write-Host "  Log on the workstation:                    $script:LogFile" -ForegroundColor Cyan
        if ($script:ConfigData['LogUploadedToStorage']) {
            Write-Host "  Log in the storage account:                $($script:ConfigData['StorageAccount'].Name)/$($script:ConfigData['StorageAccount'].LogsContainerName)/$(Split-Path -Leaf $script:LogFile)" -ForegroundColor Cyan
        }
        if ($script:ConfigData['StorageAccount'] -and -not $script:ConfigData['ConfigUploadedToStorage']) {
            Write-Host ""
            Write-Host "  [!]  The script did NOT upload the configuration file. Neologik reads the configuration file from the storage account." -ForegroundColor Red
            Write-Host "      Upload the configuration file in the Azure portal: open '$($script:ConfigData['StorageAccount'].Name)', then Containers, then '$($script:ConfigData['StorageAccount'].JsonContainerName)', then Upload" -ForegroundColor Yellow
        }
        Write-Host ""

        Write-Host "[!]  Next Steps:" -ForegroundColor Yellow
        if ($script:ConfigData['ConfigUploadedToStorage']) {
            Write-Host "  1. Read the configuration file. The file is on the workstation and in the storage account"
        }
        else {
            Write-Host "  1. Read the configuration file. The file is on the workstation only. See the upload warning above"
        }
        Write-Host "  2. Check that the Key Vault $($script:ConfigData['KeyVault'].Name) holds the client secret of the deployment identity"
        Write-Host "     Secret name: $($script:ConfigData['KeyVault'].SecretName)"
        Write-Host "  3. Provide your TLS certificate: a Neologik-managed certificate, or your own."
        Write-Host "     Neologik-managed: tell Neologik. Neologik obtains a certificate for the host name"
        Write-Host "       from the certificate authority ZeroSSL and renews it every 60 days. Nothing to import."
        Write-Host "       When your DNS zone publishes CAA records, add one that allows sectigo.com."
        Write-Host "     Your own certificate, by ONE of two methods:"
        Write-Host "     docs\PFX-CERT-GUIDE.md describes how to create the .pfx file."
        Write-Host "     Method 1: import the .pfx file into the Key Vault as a certificate."
        Write-Host "       In the Azure portal, portal.azure.com, open the Key Vault"
        Write-Host "       '$($script:ConfigData['KeyVault'].Name)', then Certificates, then Generate/Import."
        Write-Host "       Select Import and name the certificate 'keyvault-neo-ingress'. Select the"
        Write-Host "       .pfx file and enter the password of the .pfx file."
        Write-Host "       The Key Vault uses the password for the import only. Do not send the password to Neologik."
        Write-Host "     Method 2: upload the .pfx file to the storage account."
        Write-Host "       When you cannot produce a .pfx file, upload the private key, the server"
        Write-Host "       certificate and the certificate authority bundle:"
        Write-Host "       Storage Account: $($script:ConfigData['StorageAccount'].Name)"
        Write-Host "       Container:       $($script:ConfigData['StorageAccount'].CertificateContainerName)"
        Write-Host "       Authentication:  Microsoft Entra ID, with your Azure account"
        Write-Host "  4. After method 2 with a .pfx file: store the password of the .pfx file"
        Write-Host "     in the Key Vault '$($script:ConfigData['KeyVault'].Name)', as a secret with this name:"
        Write-Host "     neologik-deployment-certificate-pfx-secret"
        Write-Host ""
    }
    catch {
        Write-Log "The script could not write the configuration file: $_" -Level Error
        throw
    }
}

#endregion

#region Main Execution

function Import-AnswerFile {
    <#
    .SYNOPSIS
        Reads the answer file. Each value becomes the default value of the matching
        question.
    .DESCRIPTION
        The function reads the file that -AnswerFile names, or 'inputs.json' in the
        folder of the script. The function reads the configuration only. The script
        always asks the administrator to accept the terms, to agree to the
        installation of modules and to sign in.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    $script:Answers = @{}
    $script:AnswerFilePath = $null

    $candidate = $null
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        if (-not (Test-Path -Path $Path)) {
            throw "Answer file not found: $Path"
        }
        $candidate = (Resolve-Path -Path $Path).Path
    }
    else {
        $p = Join-Path $PSScriptRoot 'inputs.json'
        if (Test-Path -Path $p) { $candidate = $p }
    }

    if (-not $candidate) {
        Write-Log "No answer file found. The script asks every question." -Level Info
        return
    }

    try {
        $json = Get-Content -Path $candidate -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "The script could not read the answer file '$candidate': $_"
    }

    foreach ($prop in $json.PSObject.Properties) {
        if ($prop.Name -eq '_readme') { continue }
        $script:Answers[$prop.Name] = $prop.Value
    }
    $script:AnswerFilePath = $candidate

    Write-Host ""
    Write-Host "  [OK] Answer file read: $([System.IO.Path]::GetFileName($candidate))" -ForegroundColor Green
    Write-Host "    Each value appears as the default value of a question below. Press Enter to accept a value, or type another value." -ForegroundColor Gray
    Write-Log "Answer file read: $candidate" -Level Info
}

function Get-Answer {
    <#
    .SYNOPSIS
        Returns the answer for a key. Returns $null when the key is absent or blank.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if ($null -eq $script:Answers -or -not $script:Answers.ContainsKey($Key)) { return $null }
    $val = $script:Answers[$Key]
    if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { return $null }
    return $val
}

function Get-AnswerBool {
    <#
    .SYNOPSIS
        Returns a boolean for a key of the answer file. The function accepts a JSON
        boolean and the strings true, false, yes, no, 1 and 0. The function returns
        $null when the key is absent, blank or holds another value.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $val = Get-Answer $Key
    if ($null -eq $val) { return $null }
    if ($val -is [bool]) { return [bool]$val }
    if ("$val" -match '^(true|yes|y|1)$') { return $true }
    if ("$val" -match '^(false|no|n|0)$') { return $false }
    Write-Host "  [!] The answer file holds the value '$val' for '$Key'. The value must be true or false. The script ignores the value" -ForegroundColor Yellow
    return $null
}

function Get-PromptLabel {
    <#
    .SYNOPSIS
        Chooses the label for the value that a question shows. The label is
        "Pre-filled: " when the value came from the answer file and differs from the
        default value. Otherwise the label is "Default: ".
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]$Effective,
        [Parameter(Mandatory = $false)]$Builtin
    )

    if ("$Effective" -ne "$Builtin") { return "Pre-filled: " }
    return "Default: "
}

function Test-ResourceGroupNameError {
    # Returns $null when the name of the resource group is valid. Otherwise returns an error message.
    param([string]$Name)
    if ($Name.Length -lt 1 -or $Name.Length -gt 90) { return "The name of the resource group must hold 1 to 90 characters." }
    if ($Name -notmatch '^[\w\-\.\(\)]+$') { return "The name of the resource group can hold letters, digits, underscores, hyphens, full stops and round brackets only." }
    if ($Name -match '\.$') { return "The name of the resource group cannot end with a full stop." }
    return $null
}

function Test-KeyVaultNameError {
    # Returns $null when the name of the Key Vault is valid. Otherwise returns an error message.
    param([string]$Name)
    if ($Name.Length -lt 3 -or $Name.Length -gt 24) { return "The name of the Key Vault must hold 3 to 24 characters." }
    if ($Name -notmatch '^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$') { return "The name of the Key Vault must begin with a letter and end with a letter or a digit. The name can hold letters, digits and hyphens only." }
    if ($Name -match '--') { return "The name of the Key Vault cannot hold two hyphens together." }
    return $null
}

function Test-StorageAccountNameError {
    # Returns $null when the name of the storage account is valid. Otherwise returns an error message.
    param([string]$Name)
    if ($Name.Length -lt 3 -or $Name.Length -gt 24) { return "The name of the storage account must hold 3 to 24 characters." }
    if ($Name -cnotmatch '^[a-z0-9]+$') { return "The name of the storage account can hold lower-case letters and digits only." }
    return $null
}

function Test-ManagedIdentityNameError {
    # Returns $null when the name of the managed identity is valid. Otherwise returns an error message.
    param([string]$Name)
    if ($Name.Length -lt 3 -or $Name.Length -gt 128) { return "The name of the managed identity must hold 3 to 128 characters." }
    if ($Name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]*$') { return "The name of the managed identity must begin with a letter or a digit. The name can hold letters, digits, hyphens and underscores only." }
    return $null
}

function Read-NameWithDefault {
    <#
    .SYNOPSIS
        Asks for the name of a resource. The question shows the standard name, or the
        name from the answer file. Enter accepts the name shown. The function asks
        again until the name passes the given check. Returns the accepted name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$DefaultValue,
        [Parameter(Mandatory = $true)][scriptblock]$Validator,
        [string]$LabelPrefix = 'Default: '
    )

    while ($true) {
        Write-Host ""
        Write-Host "${Title}:" -ForegroundColor Cyan
        Write-Host "  $LabelPrefix" -NoNewline -ForegroundColor Gray
        Write-Host $DefaultValue -ForegroundColor Yellow
        Write-Host "  Press Enter to accept the value, or type another value: " -NoNewline -ForegroundColor Gray
        $entered = Read-Host

        $candidate = if ([string]::IsNullOrWhiteSpace($entered)) { $DefaultValue } else { $entered.Trim() }
        $err = & $Validator $candidate
        if ($err) {
            Write-Host "  [X] $err Try again." -ForegroundColor Red
            continue
        }
        Write-Host "  [OK] Using: $candidate" -ForegroundColor Green
        return $candidate
    }
}

function Test-AnswerFileComplete {
    <#
    .SYNOPSIS
        Returns true when the answer file holds every value that has no default
        value. The script can then show the configuration as a summary and ask no
        question.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $script:Answers -or $script:Answers.Count -eq 0) { return $false }

    # The answer file must hold each value that has no default value.
    foreach ($key in @('organizationCode', 'organizationName', 'fqdn')) {
        if (-not (Get-Answer $key)) { return $false }
    }

    # Onboarding collects no information about agents.
    return $true
}

function Get-CafRegionCodes {
    <#
    .SYNOPSIS
        The short forms of the Azure regions, from the Microsoft Cloud Adoption Framework.
        Reference: https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations
    #>
    return @{
        # Americas
        'eastus' = 'eus'; 'eastus2' = 'eus2'; 'westus' = 'wus'; 'westus2' = 'wus2'; 'westus3' = 'wus3'
        'centralus' = 'cus'; 'northcentralus' = 'ncus'; 'southcentralus' = 'scus'; 'westcentralus' = 'wcus'
        'canadacentral' = 'cac'; 'canadaeast' = 'cae'; 'brazilsouth' = 'brs'; 'brazilsoutheast' = 'brse'
        'brazilus' = 'bru'; 'mexicocentral' = 'mxc'; 'chilecentral' = 'clc'
        # Europe
        'northeurope' = 'neu'; 'westeurope' = 'weu'; 'uksouth' = 'uks'; 'ukwest' = 'ukw'
        'francecentral' = 'frc'; 'francesouth' = 'frs'; 'germanywestcentral' = 'gwc'; 'germanynorth' = 'gno'
        'norwayeast' = 'noe'; 'norwaywest' = 'now'; 'swedencentral' = 'sdc'; 'swedensouth' = 'sds'
        'switzerlandnorth' = 'szn'; 'switzerlandwest' = 'szw'; 'italynorth' = 'itn'; 'polandcentral' = 'plc'
        'spaincentral' = 'spc'; 'austriaeast' = 'ate'; 'belgiumcentral' = 'bec'
        # Asia Pacific
        'eastasia' = 'eas'; 'southeastasia' = 'seas'; 'australiaeast' = 'aue'; 'australiasoutheast' = 'ause'
        'australiacentral' = 'auc'; 'australiacentral2' = 'auc2'; 'japaneast' = 'jpe'; 'japanwest' = 'jpw'
        'koreacentral' = 'krc'; 'koreasouth' = 'krs'; 'centralindia' = 'inc'; 'southindia' = 'ins'
        'westindia' = 'inw'; 'jioindiawest' = 'jiw'; 'jioindiacentral' = 'jic'; 'indonesiacentral' = 'idc'
        'malaysiawest' = 'myw'; 'newzealandnorth' = 'nzn'
        # Middle East & Africa
        'southafricanorth' = 'san'; 'southafricawest' = 'saw'; 'uaenorth' = 'uan'; 'uaecentral' = 'uac'
        'qatarcentral' = 'qac'; 'israelcentral' = 'ilc'
        # China
        'chinanorth' = 'cnn'; 'chinanorth2' = 'cnn2'; 'chinanorth3' = 'cnn3'
        'chinaeast' = 'cne'; 'chinaeast2' = 'cne2'; 'chinaeast3' = 'cne3'
        # Government
        'usgovvirginia' = 'ugv'; 'usgovarizona' = 'uga'; 'usgovtexas' = 'ugt'; 'usdodeast' = 'ude'; 'usdodcentral' = 'udc'
        # Early access
        'centraluseuap' = 'cuse'; 'eastus2euap' = 'eus2e'
        # Geographic groups. Azure returns these groups, but a geographic group is not a region for a deployment
        'asia' = 'asia'; 'asiapacific' = 'apac'; 'australia' = 'au'; 'brazil' = 'br'; 'canada' = 'ca'
        'europe' = 'eu'; 'france' = 'fr'; 'germany' = 'de'; 'global' = 'global'; 'india' = 'in'
        'indonesia' = 'id'; 'israel' = 'il'; 'italy' = 'it'; 'japan' = 'jp'; 'korea' = 'kr'
        'malaysia' = 'my'; 'mexico' = 'mx'; 'newzealand' = 'nz'; 'norway' = 'no'; 'poland' = 'pl'
        'qatar' = 'qa'; 'singapore' = 'sg'; 'southafrica' = 'za'; 'spain' = 'es'; 'sweden' = 'se'
        'switzerland' = 'ch'; 'taiwan' = 'tw'; 'unitedstates' = 'us'
    }
}

function Set-ConfigFromAnswerFile {
    <#
    .SYNOPSIS
        Takes the whole configuration from the answer file without a question, and
        checks each value. The function builds the names from the table of short
        forms of the Azure regions and makes no call to Azure. The function throws
        when a value is not valid. The caller can then ask the questions. Returns the
        short form of the Azure region.
    #>
    [CmdletBinding()]
    param()

    # Organisation code. No default value
    $oc = ([string](Get-Answer 'organizationCode')).Trim().ToLower()
    if ($oc -notmatch '^[a-z0-9]{3}$') { throw "organizationCode '$oc' must hold exactly 3 lower-case letters or digits." }
    $script:OrganizationCode = $oc

    # Environment type. The default value comes from -EnvironmentType and is 'dev'. The accepted
    # values are the values of the parameter -EnvironmentType.
    $et = [string](Get-Answer 'environmentType')
    if ([string]::IsNullOrWhiteSpace($et)) { $et = $EnvironmentType }
    $et = $et.ToLower()
    if (@('dev', 'prd', 'dmo', 'test', 'stg') -notcontains $et) { throw "environmentType '$et' must be one of 'dev', 'prd', 'dmo', 'test', 'stg'." }
    $script:EnvironmentType = $et

    # Organisation name. No default value
    $on = ([string](Get-Answer 'organizationName')).Trim()
    if ([string]::IsNullOrWhiteSpace($on)) { throw "organizationName is required." }
    $script:OrganizationName = $on

    # Host name. No default value
    $fq = ([string](Get-Answer 'fqdn')).Trim().ToLower()
    $fq = $fq -replace '^[a-z]+://', ''
    $fq = ($fq -split '/')[0]
    $fq = $fq.Trim('.')
    if ($fq -notmatch '\.' -or $fq -notmatch '^[a-z0-9]([a-z0-9\-\.]*[a-z0-9])?$') { throw "fqdn '$fq' is not a valid fully qualified host name." }
    $script:HostName = $fq
    $script:ConfigData['HostName'] = $script:HostName

    # Azure region. The default value comes from -AzureRegion and is 'uksouth'. The short form comes from the table.
    $script:MicrosoftCAFRegionCodes = Get-CafRegionCodes
    $script:AzureRegionCodes = $script:MicrosoftCAFRegionCodes
    $rg = [string](Get-Answer 'azureRegion')
    if ([string]::IsNullOrWhiteSpace($rg)) { $rg = $AzureRegion }
    $rg = $rg.ToLower()
    if (-not $script:MicrosoftCAFRegionCodes.ContainsKey($rg)) {
        throw "azureRegion '$rg' is not a known Azure region. Run the script with questions to check the Azure region against Azure."
    }
    $script:AzureRegion = $rg
    $regionAbbrev = ([string]$script:MicrosoftCAFRegionCodes[$rg]).ToLower()

    # Environment index. The default value is '01'
    $ei = [string](Get-Answer 'environmentIndex')
    if ([string]::IsNullOrWhiteSpace($ei)) { $ei = '01' }
    if ($ei -notmatch '^\d+$' -or [int]$ei -lt 1 -or [int]$ei -gt 99) { throw "environmentIndex '$ei' must be between 01 and 99." }
    $script:EnvironmentIndex = ([int]$ei).ToString('00')

    # Set the name of the configuration file. The organisation code, the environment type and the environment index are now known
    Initialize-ConfigurationFile

    # Build the solution name and the short name first. Each comes from the answer file or from the
    # standard pattern. Every other standard name holds the short name.
    #   SolutionName      neo-<org><env>-<region>-<index>   for example neo-abcprd-uks-01
    #   SolutionShortName <org><env><index>                 for example abcprd01
    $snAns = [string](Get-Answer 'solutionName')
    $script:ConfigData['SolutionName'] = if (-not [string]::IsNullOrWhiteSpace($snAns)) { $snAns.Trim().ToLower() }
                                         else { "neo-$($script:OrganizationCode)$($script:EnvironmentType.ToLower())-$regionAbbrev-$($script:EnvironmentIndex)" }
    $ssnAns = [string](Get-Answer 'solutionShortName')
    $script:ConfigData['SolutionShortName'] = if (-not [string]::IsNullOrWhiteSpace($ssnAns)) { $ssnAns.Trim().ToLower() }
                                              else { "$($script:OrganizationCode)$($script:EnvironmentType.ToLower())$($script:EnvironmentIndex)" }

    # The name of the resource group, from the answer file or the standard name.
    $rgComputed = "rg-$($script:ConfigData['SolutionName'])"
    $rgAns = [string](Get-Answer 'resourceGroupName')
    $script:ResourceGroupName = if (-not [string]::IsNullOrWhiteSpace($rgAns)) { $rgAns.Trim() } else { $rgComputed }
    $rgErr = Test-ResourceGroupNameError $script:ResourceGroupName
    if ($rgErr) { throw "resourceGroupName '$($script:ResourceGroupName)': $rgErr" }

    # The name of the Key Vault, from -KeyVaultName, from the answer file or the standard name.
    $kvComputed = "kv$($script:ConfigData['SolutionShortName'])"
    $kvAns = [string](Get-Answer 'keyVaultName')
    $script:KeyVaultNameOverride = if ($script:KeyVaultNameFromCli -and -not [string]::IsNullOrWhiteSpace($KeyVaultName)) { $KeyVaultName.Trim() }
                                   elseif (-not [string]::IsNullOrWhiteSpace($kvAns)) { $kvAns.Trim() }
                                   else { $kvComputed }
    $kvErr = Test-KeyVaultNameError $script:KeyVaultNameOverride
    if ($kvErr) { throw "keyVaultName '$($script:KeyVaultNameOverride)': $kvErr" }

    # The name of the deployment storage account, from the answer file or the standard name. The script cuts the standard name to 24 characters.
    $saComputed = "stneodeploy$($script:OrganizationCode)$($script:EnvironmentType.ToLower())$regionAbbrev$($script:EnvironmentIndex)"
    if ($saComputed.Length -gt 24) { $saComputed = $saComputed.Substring(0, 24) }
    $saAns = [string](Get-Answer 'storageAccountName')
    $script:ConfigData['DeployStorageAccountName'] = if (-not [string]::IsNullOrWhiteSpace($saAns)) { $saAns.Trim().ToLower() } else { $saComputed }
    $saErr = Test-StorageAccountNameError $script:ConfigData['DeployStorageAccountName']
    if ($saErr) { throw "storageAccountName '$($script:ConfigData['DeployStorageAccountName'])': $saErr" }

    # The name of the script runner managed identity, from the answer file or the standard name.
    $sriComputed = "neologik-script-runner-service-connection-$($script:ConfigData['SolutionShortName'])"
    $sriAns = [string](Get-Answer 'scriptRunnerIdentityName')
    $script:ConfigData['ScriptRunnerIdentityName'] = if (-not [string]::IsNullOrWhiteSpace($sriAns)) { $sriAns.Trim() } else { $sriComputed }
    $sriErr = Test-ManagedIdentityNameError $script:ConfigData['ScriptRunnerIdentityName']
    if ($sriErr) { throw "scriptRunnerIdentityName '$($script:ConfigData['ScriptRunnerIdentityName'])': $sriErr" }

    # The name of the SQL managed identity, from the answer file or the standard name.
    $sqlComputed = "neologik-sql-managed-identity-$($script:ConfigData['SolutionShortName'])"
    $sqlAns = [string](Get-Answer 'sqlIdentityName')
    $script:ConfigData['SqlIdentityName'] = if (-not [string]::IsNullOrWhiteSpace($sqlAns)) { $sqlAns.Trim() } else { $sqlComputed }
    $sqlErr = Test-ManagedIdentityNameError $script:ConfigData['SqlIdentityName']
    if ($sqlErr) { throw "sqlIdentityName '$($script:ConfigData['SqlIdentityName'])': $sqlErr" }

    # The name of the agent registration identity, from the answer file or the standard name.
    $dirComputed = "neologik-directory-managed-identity-$($script:ConfigData['SolutionShortName'])"
    $dirAns = [string](Get-Answer 'directoryIdentityName')
    $script:ConfigData['DirectoryIdentityName'] = if (-not [string]::IsNullOrWhiteSpace($dirAns)) { $dirAns.Trim() } else { $dirComputed }
    $dirErr = Test-ManagedIdentityNameError $script:ConfigData['DirectoryIdentityName']
    if ($dirErr) { throw "directoryIdentityName '$($script:ConfigData['DirectoryIdentityName'])': $dirErr" }

    # The name of the system task managed identity, from the answer file or the standard name.
    $taskComputed = "neologik-system-task-managed-identity-$($script:ConfigData['SolutionShortName'])"
    $taskAns = [string](Get-Answer 'systemTaskIdentityName')
    $script:ConfigData['SystemTaskIdentityName'] = if (-not [string]::IsNullOrWhiteSpace($taskAns)) { $taskAns.Trim() } else { $taskComputed }
    $taskErr = Test-ManagedIdentityNameError $script:ConfigData['SystemTaskIdentityName']
    if ($taskErr) { throw "systemTaskIdentityName '$($script:ConfigData['SystemTaskIdentityName'])': $taskErr" }

    # The name of the environment in the Neologik deployment, from the answer file or from the
    # organisation code and the environment type. The federated credential of the deployment identity names the environment.
    $environmentNameAns = [string](Get-Answer 'environmentName')
    $script:ConfigData['EnvironmentName'] = if (-not [string]::IsNullOrWhiteSpace($environmentNameAns)) { $environmentNameAns.Trim().ToLower() } else { "$($script:OrganizationCode)$($script:EnvironmentType)".ToLower() }
    if ($script:ConfigData['EnvironmentName'] -notmatch '^[a-z0-9]{2,32}$') { throw "environmentName '$($script:ConfigData['EnvironmentName'])': the name must be 2 to 32 lower-case letters and digits" }

    # A platform operator creates agents and channels in the Neologik Admin Tool after the deployment.

    # Tags. The answer file can hold a boolean, whose default value is to apply the tags. The answer file
    # can also hold custom tags, as an object or as a string of key=value pairs separated by commas. The
    # function throws when a value is not valid. The caller can then ask the questions.
    $rtAns = Get-Answer 'applyResourceTags'
    if ($null -eq $rtAns) { $script:ConfigData['ResourceTagsEnabled'] = $true }
    elseif ($rtAns -is [bool]) { $script:ConfigData['ResourceTagsEnabled'] = [bool]$rtAns }
    elseif ("$rtAns" -match '^(true|yes|y|1)$') { $script:ConfigData['ResourceTagsEnabled'] = $true }
    elseif ("$rtAns" -match '^(false|no|n|0)$') { $script:ConfigData['ResourceTagsEnabled'] = $false }
    else { throw "applyResourceTags '$rtAns' must be true or false." }

    $script:ConfigData['ResourceTagsCustom'] = @{}
    if ($script:ConfigData['ResourceTagsEnabled']) {
        $rtcAns = Get-Answer 'resourceTagsCustom'
        if ($null -ne $rtcAns) {
            try { $script:ConfigData['ResourceTagsCustom'] = ConvertTo-NeologikCustomTags $rtcAns }
            catch { throw "resourceTagsCustom: $($_.Exception.Message)" }
        }
    }

    # The top of this function built the solution name and the short name.

    return $regionAbbrev
}

function Start-NeologikOnboarding {
    <#
    .SYNOPSIS
        Runs the onboarding, one step at a time.
    #>
    [CmdletBinding()]
    param()

    try {
        $resuming = $false
        Write-ScriptHeader

        # Read the answer file. The file is the file that -AnswerFile names, or inputs.json in the folder
        # of the script. Each value becomes the default value of a question below.
        Import-AnswerFile -Path $AnswerFile

        # An unattended run requires a complete answer file. Stop now when the answer file is not complete,
        # before the script reaches a question.
        if ($script:NonInteractiveMode -and -not (Test-AnswerFileComplete)) {
            throw "An unattended run requires an answer file that holds organizationCode, organizationName and fqdn. Give -AnswerFile, or add the missing keys."
        }

        # Look for a checkpoint and ask whether to resume
        $existingCheckpoint = Find-LatestCheckpoint
        if ($existingCheckpoint -and $script:FreshRunMode) {
            # -FreshRun: delete the checkpoint without a question and start again.
            Write-Log "FreshRun: deleting the checkpoint $($existingCheckpoint.Name)" -Level Warning
            Remove-Item -Path $existingCheckpoint.FullName -Force -ErrorAction SilentlyContinue
            $existingCheckpoint = $null
        }
        if ($existingCheckpoint -and $script:NonInteractiveMode) {
            # An unattended run does not expect a checkpoint of an earlier run. A resumed run could
            # use an old configuration, and the script can ask no question. Stop.
            throw "A checkpoint of an earlier run exists: $($existingCheckpoint.Name). Run the script again with -FreshRun to delete the checkpoint, or resume in a run with questions."
        }
        if ($existingCheckpoint) {
            $age = (Get-Date) - $existingCheckpoint.LastWriteTime
            $ageStr = if ($age.TotalDays -ge 1) { "$([int]$age.TotalDays) days ago" }
                      elseif ($age.TotalHours -ge 1) { "$([int]$age.TotalHours) hours ago" }
                      else { "$([int]$age.TotalMinutes) minutes ago" }

            Write-Host "`n+===============================================================+" -ForegroundColor Yellow
            Write-Host "|                                                               |" -ForegroundColor Yellow
            Write-Host "|                  RESUME PREVIOUS RUN?                         |" -ForegroundColor Yellow
            Write-Host "|                                                               |" -ForegroundColor Yellow
            Write-Host "+===============================================================+" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  The script found a checkpoint, saved ${ageStr}:" -ForegroundColor Gray
            Write-Host "  $($existingCheckpoint.Name)" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  Resume from this checkpoint? (Y/N, default: Y): " -NoNewline -ForegroundColor Yellow
            $resumeChoice = Read-Host

            if ([string]::IsNullOrWhiteSpace($resumeChoice) -or $resumeChoice -eq 'Y' -or $resumeChoice -eq 'y') {
                $restored = Restore-Checkpoint -Path $existingCheckpoint.FullName
                if ($restored -eq $false) { $resuming = $false }
                else { $resuming = $true }

                Write-Host "`n  [OK] Checkpoint read." -ForegroundColor Green
                Write-Host "    Org: $($script:OrganizationCode)  |  Env: $($script:EnvironmentType)  |  Region: $($script:AzureRegion)" -ForegroundColor Cyan
                Write-Host "    Resource Group: $($script:ResourceGroupName)" -ForegroundColor Cyan
                $unconfirmed = @($script:ProviderRegistrations.GetEnumerator() | Where-Object { $_.Value -ne 'Registered' })
                if ($unconfirmed.Count -gt 0) {
                    Write-Host "    Provider registrations still to confirm: $($unconfirmed.Count)" -ForegroundColor Yellow
                }
                Write-Host ""
                Write-Log "Resuming from checkpoint: $($existingCheckpoint.FullName)" -Level Info
            }
            else {
                Write-Host "`n  Starting a new run..." -ForegroundColor Green
                Write-Host ""
            }
        }

        # Step 0: Show the terms. A resumed run skips this step, because the administrator accepted the terms in the earlier run
        if (-not $resuming) {
            $termsAccepted = Show-TermsAndConditions
            if (-not $termsAccepted) {
                Write-Log "The administrator did not accept the terms. The script stops" -Level Warning
                exit 0
            }
        }
        else {
            Write-Log "Resumed run: the administrator accepted the terms in the earlier run" -Level Info
        }

        # Step 1: Check the PowerShell version
        if (-not $SkipPowerShellUpdate) {
            $psVersionOk = Test-PowerShellVersion
            if (-not $psVersionOk) {
                Write-Host ""
                Write-Host "The script requires PowerShell 7.4 or later." -ForegroundColor Yellow
                Write-Host "Update PowerShell now? (Y/N): " -NoNewline -ForegroundColor Cyan
                $update = Read-Host
                if ($update -eq 'Y' -or $update -eq 'y' -or [string]::IsNullOrWhiteSpace($update)) {
                    Install-PowerShellLatest
                }
                else {
                    throw "The script requires PowerShell 7.4 or later. Update PowerShell and run this script again."
                }
            }
        }

        # Step 2: Check the modules and install each module that is missing
        if (-not $SkipModuleInstall) {
            $missingModules = Test-RequiredModules
            if ($missingModules.Count -gt 0) {
                Write-Log "The script must install these modules:" -Level Warning
                $missingModules | ForEach-Object { Write-Log "  - $($_.Name) >= $($_.MinVersion)" -Level Info }
                
                Write-Host ""
                Write-Host "Install the missing modules now? (Y/N): " -NoNewline -ForegroundColor Cyan
                $install = Read-Host
                if ($install -eq 'Y' -or $install -eq 'y' -or [string]::IsNullOrWhiteSpace($install)) {
                    Install-RequiredModules -Modules $missingModules
                }
                else {
                    throw "Required modules are missing. Install the modules and run this script again."
                }
            }
        }

        # Step 3: Ask whether to sign in again
        $currentContext = Get-AzContext -ErrorAction SilentlyContinue

        if ($currentContext -and $currentContext.Account -and $script:NonInteractiveMode) {
            # In an unattended run, the caller has signed in to Azure and to Microsoft Graph.
            # The script always uses both sessions.
            Write-Log "Unattended run: the script uses the existing Azure session, account $($currentContext.Account.Id)" -Level Info
            $script:ForceReAuth = $false
        }
        elseif ($currentContext -and $currentContext.Account) {
            Write-Host "`n+===============================================================+" -ForegroundColor Yellow
            Write-Host "|                                                               |" -ForegroundColor Yellow
            Write-Host "|                  CURRENT AZURE CONNECTION                     |" -ForegroundColor Yellow
            Write-Host "|                                                               |" -ForegroundColor Yellow
            Write-Host "+===============================================================+" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "You are signed in as:" -ForegroundColor Gray
            Write-Host "  User:         " -NoNewline -ForegroundColor Gray
            Write-Host "$($currentContext.Account.Id)" -ForegroundColor Cyan
            Write-Host "  Tenant:       " -NoNewline -ForegroundColor Gray
            Write-Host "$($currentContext.Tenant.Id)" -ForegroundColor Cyan
            if ($currentContext.Subscription) {
                Write-Host "  Subscription: " -NoNewline -ForegroundColor Gray
                Write-Host "$($currentContext.Subscription.Name)" -ForegroundColor Cyan
            }
            Write-Host ""
            Write-Host "Sign in to Azure again? (default: N)" -ForegroundColor Yellow
            Write-Host "  Your choice (N/Y): " -NoNewline -ForegroundColor Yellow
            $reauth = Read-Host
            
            if ($reauth -eq 'Y' -or $reauth -eq 'y') {
                Write-Host "The script now asks you to sign in to Azure..." -ForegroundColor Green
                # End the existing sessions
                Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
                Clear-AzContext -Scope CurrentUser -Force -ErrorAction SilentlyContinue
                Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
                # Record that a new sign-in is required
                $script:ForceReAuth = $true
            }
            else {
                Write-Host "Continuing with the existing sign-in..." -ForegroundColor Green
                $script:ForceReAuth = $false
            }
            Write-Host ""
        }

        # Step 3b: Read resource-providers.txt before the sign-in. A missing file or a line with
        # the wrong form then stops the run immediately.
        $script:ProviderList = Get-PlatformResourceProviderList

        # Step 4: Sign in to Azure. The sign-in gives the tenant and the subscription
        Write-Host "`n+===============================================================+" -ForegroundColor Magenta
        Write-Host "|                                                               |" -ForegroundColor Magenta
        Write-Host "|                     AZURE AUTHENTICATION                      |" -ForegroundColor Magenta
        Write-Host "|                                                               |" -ForegroundColor Magenta
        Write-Host "+===============================================================+" -ForegroundColor Magenta
        Write-Host ""
        
        $null = Connect-AzureEnvironment -TenantId $TenantId

        # Step 5: Select the subscription
        # A resumed run uses the subscription from the checkpoint. Otherwise the script selects
        # the subscription that -SubscriptionName names, and the run stops when the
        # account cannot see the subscription. Without the parameter, the script uses the subscription of the
        # sign-in.
        $subscriptionSource = 'your login'
        if ($resuming -and $script:ConfigData['SubscriptionId']) {
            Set-AzContext -SubscriptionId $script:ConfigData['SubscriptionId'] -ErrorAction Stop | Out-Null
            Write-Log "Selected the subscription from the checkpoint: $($script:ConfigData['SubscriptionId'])" -Level Info
            $subscriptionSource = 'the checkpoint'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($SubscriptionName)) {
            $requested = @(Get-AzSubscription -SubscriptionName $SubscriptionName -ErrorAction SilentlyContinue) | Select-Object -First 1
            if (-not $requested) {
                throw "Subscription '$SubscriptionName' not found for this sign-in. Give the name of a subscription that the account can see, or give no -SubscriptionName to use the subscription of the sign-in."
            }
            Set-AzContext -SubscriptionId $requested.Id -ErrorAction Stop | Out-Null
            Write-Log "Selected the subscription from -SubscriptionName: $($requested.Name), id $($requested.Id)" -Level Info
            $subscriptionSource = '-SubscriptionName'
        }

        $currentContext = Get-AzContext
        if (-not $currentContext -or -not $currentContext.Subscription) {
            throw "No Azure subscription found. Sign in with an account that can use a subscription."
        }

        $script:ConfigData['SubscriptionName'] = $currentContext.Subscription.Name
        $script:ConfigData['SubscriptionId'] = $currentContext.Subscription.Id
        
        Write-Host "`n+===============================================================+" -ForegroundColor Cyan
        Write-Host "|                                                               |" -ForegroundColor Cyan
        Write-Host "|                   SUBSCRIPTION INFORMATION                    |" -ForegroundColor Cyan
        Write-Host "|                                                               |" -ForegroundColor Cyan
        Write-Host "+===============================================================+" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Using subscription from ${subscriptionSource}:" -ForegroundColor Yellow
        Write-Host "  Name: $($currentContext.Subscription.Name)" -ForegroundColor Gray
        Write-Host "  ID:   $($currentContext.Subscription.Id)" -ForegroundColor Gray
        Write-Host ""
        
        Write-Log "Using the subscription $($currentContext.Subscription.Name), id $($currentContext.Subscription.Id)" -Level Success

        # Step 5b: Check the roles before the first question
        Write-Log "Checking the required roles..." -Level Info
        $null = Test-RequiredPermissions -SubscriptionId $script:ConfigData['SubscriptionId']

        # Step 5c: Submit the registration of the five resource providers that the script needs: the resource group,
        # the Key Vault, the storage account and the managed identities. Azure completes the registrations while the
        # script continues. The script confirms each resource provider before the creation of the resource. Step 15b
        # submits every other resource provider and every preview feature, and confirms the whole list before the export.
        Start-ResourceProviderRegistration -Providers $script:ProviderList.OnboardingProviders

        # Step 6: Collect the configuration. A resumed run skips this step when the checkpoint
        # holds the configuration. The first checkpoint is written before the questions, so a run
        # resumed from the first checkpoint asks the questions.
        $configurationRestored = $resuming -and ($script:CompletedSteps.Contains('ConfigGathered') -or -not [string]::IsNullOrWhiteSpace([string]$script:OrganizationCode))
        if (-not $configurationRestored) {

        Write-Host "`n+===============================================================+" -ForegroundColor Magenta
        Write-Host "|                                                               |" -ForegroundColor Magenta
        Write-Host "|                   CONFIGURATION SETUP                         |" -ForegroundColor Magenta
        Write-Host "|      Please review and confirm the following settings         |" -ForegroundColor Magenta
        Write-Host "|                                                               |" -ForegroundColor Magenta
        Write-Host "+===============================================================+" -ForegroundColor Magenta

        # When the answer file holds every value that has no default value, take the configuration
        # from the answer file and show the summary. Otherwise ask each question. When the administrator chooses
        # to edit at the summary, the script asks each question.
        $answerComplete = Test-AnswerFileComplete
        $editing = $false
        while ($true) {
            if ($answerComplete -and -not $editing) {
                # The answer file is complete. Use the answer file and show the summary.
                try {
                    $regionAbbrev = Set-ConfigFromAnswerFile
                }
                catch {
                    # An unattended run can ask no question. Stop with the error.
                    if ($script:NonInteractiveMode) {
                        throw "The answer file is not valid, and an unattended run cannot ask for a correction: $($_.Exception.Message)"
                    }
                    Write-Host ""
                    Write-Host "  [!] inputs.json: $($_.Exception.Message)" -ForegroundColor Yellow
                    Write-Host "  The script now asks each question..." -ForegroundColor Yellow
                    $editing = $true
                    continue
                }
            }
            else {

        # Organisation code. No default value. The question shows the value from the answer file or from
        # -OrganizationCode.
        $orgCodePrefill = Get-Answer 'organizationCode'
        if (-not $orgCodePrefill -and -not [string]::IsNullOrWhiteSpace($OrganizationCode)) {
            $orgCodePrefill = $OrganizationCode
        }
        $orgCodeValid = $false
        while (-not $orgCodeValid) {
            Write-Host ""
            Write-Host "Organization Code:" -ForegroundColor Cyan
            if ($orgCodePrefill) {
                Write-Host "  Pre-filled: " -NoNewline -ForegroundColor Gray
                Write-Host $orgCodePrefill -ForegroundColor Yellow
                Write-Host "  Press Enter to accept the value from the answer file, or type another value: " -NoNewline -ForegroundColor Gray
            }
            else
            {
                Write-Host "  Example: " -NoNewLine -ForegroundColor Gray
                Write-Host "abc" -ForegroundColor Yellow
                Write-Host "  Rules: exactly 3 characters, lower-case letters and digits only" -ForegroundColor Gray
                Write-Host "  Enter organization code: " -NoNewline -ForegroundColor Gray
            }
            if ($orgCodePrefill) {
            }
            else {
            }
            $orgInput = Read-Host

            if ([string]::IsNullOrWhiteSpace($orgInput)) {
                if ($orgCodePrefill) {
                    $script:OrganizationCode = ([string]$orgCodePrefill).Trim().ToLower()
                }
                else {
                    Write-Host "  [X] Organization code is required. Enter a value." -ForegroundColor Red
                    continue
                }
            }
            else {
                $script:OrganizationCode = $orgInput.Trim().ToLower()
            }

            # Check the length
            if ($script:OrganizationCode.Length -ne 3) {
                Write-Host "  [X] Organization code must hold exactly 3 characters. Try again." -ForegroundColor Red
                continue
            }

            # Check that the code holds lower-case letters and digits only
            if ($script:OrganizationCode -notmatch '^[a-z0-9]{3}$') {
                Write-Host "  [X] Organization code must hold lower-case letters and digits only. Try again." -ForegroundColor Red
                continue
            }

            $orgCodeValid = $true
            Write-Host "  [OK] Using: $($script:OrganizationCode)" -ForegroundColor Green
        }

        # Environment type.
        # The question shows a valid environmentType from the answer file.
        $envBuiltin = $EnvironmentType
        $envAnswer = Get-Answer 'environmentType'
        if ($envAnswer) {
            if (@('dev', 'prd') -contains ([string]$envAnswer).ToLower()) {
                $EnvironmentType = ([string]$envAnswer).ToLower()
            }
            else {
                Write-Host "  [!] The answer file holds the environmentType '$envAnswer'. The value must be dev or prd. The script ignores the value." -ForegroundColor Yellow
            }
        }
        $envLabel = Get-PromptLabel $EnvironmentType $envBuiltin
        $envTypeValid = $false
        while (-not $envTypeValid) {
            Write-Host ""
            Write-Host "Environment Type:" -ForegroundColor Cyan
            Write-Host "  $envLabel" -NoNewline -ForegroundColor Gray
            Write-Host $EnvironmentType -ForegroundColor Yellow
            Write-Host "  Valid values: dev, prd" -ForegroundColor Gray
            Write-Host "  Press Enter to accept the default value, or type another value: " -NoNewline -ForegroundColor Gray
            $envInput = Read-Host

            # The script also accepts the values that Neologik reserves for environments that Neologik operates.
            $allowedEnvTypes = @('dev', 'prd', 'dmo', 'test', 'stg')

            if ([string]::IsNullOrWhiteSpace($envInput)) {
                $script:EnvironmentType = $EnvironmentType.ToLower()
                $envTypeValid = $true
                Write-Host "  [OK] Using the default value: $($script:EnvironmentType)" -ForegroundColor Green
            }
            elseif ($allowedEnvTypes -contains $envInput.ToLower()) {
                $script:EnvironmentType = $envInput.ToLower()
                $envTypeValid = $true
                Write-Host "  [OK] Using: $($script:EnvironmentType)" -ForegroundColor Green
            }
            else {
                Write-Host "  [X] The environment type is not valid. Enter 'dev' or 'prd'. Try again." -ForegroundColor Red
            }
        }

        # Organisation name
        $orgNamePrefill = Get-Answer 'organizationName'
        Write-Host ""
        Write-Host "Organization Name, the full name of the organisation:" -ForegroundColor Cyan
        if ($orgNamePrefill) {
            Write-Host "  Pre-filled: " -NoNewline -ForegroundColor Gray
            Write-Host $orgNamePrefill -ForegroundColor Yellow
            Write-Host "  Press Enter to accept the value from the answer file, or type another value: " -NoNewline -ForegroundColor Gray
        }
        else {
            Write-Host "  Example: " -NoNewLine -ForegroundColor Gray
            Write-Host "Contoso Ltd" -ForegroundColor Yellow
            Write-Host "  Enter organization name: " -NoNewline -ForegroundColor Gray
        }
        $orgNameInput = Read-Host
        if ([string]::IsNullOrWhiteSpace($orgNameInput) -and $orgNamePrefill) {
            $orgNameInput = [string]$orgNamePrefill
        }

        while ([string]::IsNullOrWhiteSpace($orgNameInput)) {
            Write-Host "  Organization name is required. Enter a name: " -NoNewline -ForegroundColor Yellow
            $orgNameInput = Read-Host
        }

        $script:OrganizationName = $orgNameInput.Trim()
        Write-Host "  [OK] Using: " -NoNewline -ForegroundColor Green
        Write-Host $script:OrganizationName -ForegroundColor White

        # The fully qualified host name of the environment, for example neologik.contoso.com. The script
        # holds the host name as one value and never divides the host name into host and domain.
        $fqdnPrefill = Get-Answer 'fqdn'
        Write-Host ""
        Write-Host "Host name of the environment, fully qualified:" -ForegroundColor Cyan
        if ($fqdnPrefill) {
            Write-Host "  Pre-filled: " -NoNewline -ForegroundColor Gray
            Write-Host $fqdnPrefill -ForegroundColor Yellow
            Write-Host "  Press Enter to accept the value from the answer file, or type another value: " -NoNewline -ForegroundColor Gray
        }
        else {
            Write-Host "  Example: " -NoNewLine -ForegroundColor Gray
            Write-Host "neologik.contoso.com" -ForegroundColor Yellow
            Write-Host "  Enter the full host name: " -NoNewline -ForegroundColor Gray
        }
        $fqdnInput = Read-Host
        if ([string]::IsNullOrWhiteSpace($fqdnInput) -and $fqdnPrefill) {
            $fqdnInput = [string]$fqdnPrefill
        }

        $fqdnValid = $false
        while (-not $fqdnValid) {
            while ([string]::IsNullOrWhiteSpace($fqdnInput)) {
                Write-Host "  The host name is required. Enter the fully qualified host name: " -NoNewline -ForegroundColor Yellow
                $fqdnInput = Read-Host
            }

            # Remove the scheme and the path, convert to lower case, and remove each full stop at the start and at the end.
            $normalizedFqdn = $fqdnInput.Trim().ToLower()
            $normalizedFqdn = $normalizedFqdn -replace '^[a-z]+://', ''
            $normalizedFqdn = ($normalizedFqdn -split '/')[0]
            $normalizedFqdn = $normalizedFqdn.Trim('.')

            # Require a fully qualified host name, with a host and a domain.
            if ($normalizedFqdn -notmatch '\.' -or $normalizedFqdn -notmatch '^[a-z0-9]([a-z0-9\-\.]*[a-z0-9])?$') {
                Write-Host "  [X] Enter a valid fully qualified host name, for example neologik.contoso.com" -ForegroundColor Red
                $fqdnInput = ""
                continue
            }

            $script:HostName = $normalizedFqdn
            $fqdnValid = $true
        }

        $script:ConfigData['HostName'] = $script:HostName
        Write-Host "  [OK] Using: " -NoNewline -ForegroundColor Green
        Write-Host $script:HostName -ForegroundColor White

        # Azure region. The script checks the Azure region against the regions that the subscription can use
        # Read the available regions from Azure
        Write-Host ""
        Write-Host "Reading the available Azure regions..." -ForegroundColor Gray
        
        # The short forms of the Azure regions come from the table in Get-CafRegionCodes.
        $script:MicrosoftCAFRegionCodes = Get-CafRegionCodes
        
        try {
            $azureLocations = Get-AzLocation | Sort-Object Location
            
            # Build the table of short forms
            $script:AzureRegionCodes = @{}
            $script:AzureRegionDisplayNames = @{}
            
            foreach ($location in $azureLocations) {
                $locationName = $location.Location.ToLower()
                $displayName = $location.DisplayName
                
                # Use the short form from the table when the table holds the region
                if ($script:MicrosoftCAFRegionCodes.ContainsKey($locationName)) {
                    $code = $script:MicrosoftCAFRegionCodes[$locationName]
                } else {
                    # For a region that the table does not hold, build a short form
                    Write-Log "The table of short forms does not hold the region '$locationName'. The script builds a short form" -Level Info
                    if ($locationName -match '([a-z]+)([0-9]+)') {
                        $base = $Matches[1]
                        $num = $Matches[2]
                        $code = ($base.Substring(0, [Math]::Min(3, $base.Length)) + $num).ToLower()
                    } else {
                        $code = $locationName.Substring(0, [Math]::Min(3, $locationName.Length)).ToLower()
                    }
                }
                
                $script:AzureRegionCodes[$locationName] = $code
                $script:AzureRegionDisplayNames[$locationName] = $displayName
            }
            
            $locationCount = $azureLocations.Count
            $cafCount = ($azureLocations | Where-Object { $script:MicrosoftCAFRegionCodes.ContainsKey($_.Location.ToLower()) }).Count
            Write-Host "[OK] Azure regions read: $locationCount. Regions with a short form from the Microsoft Cloud Adoption Framework: $cafCount" -ForegroundColor Green
        }
        catch {
            Write-Log "Warning: the script could not read the regions from Azure. The script checks the region against the table of short forms." -Level Warning
            Write-Host "  [!] The script could not read the regions from Azure. Azure checks the region at the creation of the resource group." -ForegroundColor Yellow
            $azureLocations = $null
            # Use the table when the script cannot read the regions from Azure
            $script:AzureRegionCodes = $script:MicrosoftCAFRegionCodes
        }
        
        # The question shows the region from the answer file. The script checks the region below.
        $regionBuiltin = $AzureRegion
        $regionAnswer = Get-Answer 'azureRegion'
        if ($regionAnswer) { $AzureRegion = ([string]$regionAnswer).ToLower() }
        $regionLabel = Get-PromptLabel $AzureRegion $regionBuiltin

        $regionValid = $false

        while (-not $regionValid) {
            Write-Host ""
            Write-Host "Azure Region:" -ForegroundColor Cyan
            Write-Host "  $regionLabel" -NoNewline -ForegroundColor Gray
            Write-Host $AzureRegion -ForegroundColor Yellow
            
            if ($azureLocations) {
                # Show some common regions
                $commonRegions = $azureLocations | Where-Object { 
                    $_.Location -in @('uksouth', 'ukwest', 'eastus', 'westus', 'northeurope', 'westeurope', 'switzerlandnorth')
                } | Select-Object -First 7
                
                if ($commonRegions) {
                    Write-Host "  Common regions: " -NoNewline -ForegroundColor Gray
                    Write-Host ($commonRegions.Location -join ', ') -ForegroundColor Gray
                }
                Write-Host "  Type 'list' to see every available region" -ForegroundColor Gray
            } else {
                Write-Host "  Example: " -NoNewLine -ForegroundColor Gray
                Write-Host "uksouth, ukwest, eastus, westus, northeurope, westeurope" -ForegroundColor Yellow
            }
            
            Write-Host "  Press Enter to accept the default value, or type another value: " -NoNewline -ForegroundColor Gray
            $regionInput = Read-Host

            # The command that lists every region
            if ($regionInput.ToLower() -eq 'list' -and $azureLocations) {
                Write-Host ""
                Write-Host "Available Azure Regions:" -ForegroundColor Cyan
                Write-Host "------------------------" -ForegroundColor Cyan
                foreach ($loc in $azureLocations) {
                    $code = if ($script:AzureRegionCodes.ContainsKey($loc.Location.ToLower())) { 
                        $script:AzureRegionCodes[$loc.Location.ToLower()] 
                    } else { 
                        'N/A' 
                    }
                    Write-Host ("  {0,-25} {1,-35} ({2})" -f $loc.Location, $loc.DisplayName, $code) -ForegroundColor Gray
                }
                Write-Host ""
                continue
            }

            if ([string]::IsNullOrWhiteSpace($regionInput)) {
                $script:AzureRegion = $AzureRegion.ToLower()
                # Check the default region
                if ($azureLocations) {
                    $validLocation = $azureLocations | Where-Object { $_.Location.ToLower() -eq $script:AzureRegion }
                    if ($validLocation) {
                        $regionValid = $true
                        $code = $script:AzureRegionCodes[$script:AzureRegion]
                        $displayName = $script:AzureRegionDisplayNames[$script:AzureRegion]
                        Write-Host "  [OK] Using the default value: $($script:AzureRegion), $displayName, short form $code" -ForegroundColor Green
                    } else {
                        Write-Host "  [X] The default region '$($script:AzureRegion)' is not available in this subscription." -ForegroundColor Red
                        continue
                    }
                } else {
                    # Without the list from Azure, check the default region against the table
                    if ($script:MicrosoftCAFRegionCodes.ContainsKey($script:AzureRegion)) {
                        $regionValid = $true
                        $code = $script:MicrosoftCAFRegionCodes[$script:AzureRegion]
                        Write-Host "  [OK] Using the default value: $($script:AzureRegion), short form $code" -ForegroundColor Green
                        Write-Host "  [!] Note: the script checked the region against the table of short forms only. Azure checks the region at the creation of the resource group." -ForegroundColor Yellow
                    } else {
                        Write-Host "  [X] The table of short forms does not hold the default region '$($script:AzureRegion)'." -ForegroundColor Red
                        Write-Host "  Enter a valid Azure region." -ForegroundColor Gray
                        continue
                    }
                }
            }
            else {
                $normalizedInput = $regionInput.ToLower()
                if ($azureLocations) {
                    $validLocation = $azureLocations | Where-Object { $_.Location.ToLower() -eq $normalizedInput }
                    if ($validLocation) {
                        $script:AzureRegion = $normalizedInput
                        $regionValid = $true
                        $code = $script:AzureRegionCodes[$script:AzureRegion]
                        $displayName = $script:AzureRegionDisplayNames[$script:AzureRegion]
                        Write-Host "  [OK] Using: $($script:AzureRegion), $displayName, short form $code" -ForegroundColor Green
                    } else {
                        Write-Host "  [X] The Azure region '$regionInput' is not valid. The region is not available in this subscription." -ForegroundColor Red
                        Write-Host "  Type 'list' to see every available region" -ForegroundColor Gray
                    }
                } else {
                    # Without the list from Azure, check the region against the table
                    if ($script:MicrosoftCAFRegionCodes.ContainsKey($normalizedInput)) {
                        $script:AzureRegion = $normalizedInput
                        $regionValid = $true
                        $code = $script:MicrosoftCAFRegionCodes[$normalizedInput]
                        Write-Host "  [OK] Using: $($script:AzureRegion), short form $code" -ForegroundColor Green
                        Write-Host "  [!] Note: the script checked the region against the table of short forms only. Azure checks the region at the creation of the resource group." -ForegroundColor Yellow
                    } else {
                        Write-Host "  [X] The Azure region '$regionInput' is not valid. The table of short forms does not hold the region." -ForegroundColor Red
                        Write-Host "  Common regions: uksouth, ukwest, eastus, westus, northeurope, westeurope, switzerlandnorth" -ForegroundColor Gray
                        Write-Host "  Enter the name of a valid Azure region." -ForegroundColor Gray
                    }
                }
            }
        }

        # Environment index
        # The question shows a valid environment index from the answer file, from 1 to 99.
        $indexDefault = Get-Answer 'environmentIndex'
        if ($indexDefault -and "$indexDefault" -match '^\d+$' -and [int]"$indexDefault" -ge 1 -and [int]"$indexDefault" -le 99) {
            $indexDefault = ([int]"$indexDefault").ToString("00")
        }
        elseif ($indexDefault) {
            Write-Host "  [!] The answer file holds the environmentIndex '$indexDefault'. The value must be from 01 to 99. The script ignores the value." -ForegroundColor Yellow
            $indexDefault = "01"
        }
        else {
            $indexDefault = "01"
        }
        $indexLabel = Get-PromptLabel $indexDefault "01"
        $indexValid = $false
        while (-not $indexValid) {
            Write-Host ""
            Write-Host "Environment Index Number:" -ForegroundColor Cyan
            Write-Host "  $indexLabel" -NoNewline -ForegroundColor Gray
            Write-Host $indexDefault -ForegroundColor Yellow
            Write-Host "  The number separates two environments of the same type: 01, 02, 03" -ForegroundColor Gray
            Write-Host "  Press Enter to accept the default value, or type another value: " -NoNewline -ForegroundColor Gray
            $indexInput = Read-Host

            if ([string]::IsNullOrWhiteSpace($indexInput)) {
                $script:EnvironmentIndex = $indexDefault
                $indexValid = $true
                Write-Host "  [OK] Using the default value: $($script:EnvironmentIndex)" -ForegroundColor Green
            }
            else {
                # Check that the environment index is a number
                if ($indexInput -match '^\d+$') {
                    $indexNumber = [int]$indexInput
                    
                    # Check that the environment index is between 01 and 99
                    if ($indexNumber -ge 1 -and $indexNumber -le 99) {
                        $script:EnvironmentIndex = $indexNumber.ToString("00")
                        $indexValid = $true
                        Write-Host "  [OK] Using: $($script:EnvironmentIndex)" -ForegroundColor Green
                    }
                    else {
                        Write-Host "  [X] The environment index must be between 01 and 99. Try again." -ForegroundColor Red
                    }
                }
                else {
                    Write-Host "  [X] The environment index must be a number. Try again." -ForegroundColor Red
                }
            }
        }

        # Set the name of the configuration file. The organisation code, the environment type and the environment index are now known
        Initialize-ConfigurationFile

        # Build the name of the resource group
        # The short form of the region comes from the table built above
        $regionAbbrev = if ($script:AzureRegionCodes -and $script:AzureRegionCodes.ContainsKey($script:AzureRegion.ToLower())) {
            $script:AzureRegionCodes[$script:AzureRegion.ToLower()].ToLower()
        } else {
            # Without an entry in the table, build a short form from the name of the region
            Write-Log "Building a short form for the region '$($script:AzureRegion)'" -Level Info
            if ($script:AzureRegion -match '([a-z]+)([0-9]+)') {
                $base = $Matches[1]
                $num = $Matches[2]
                ($base.Substring(0, [Math]::Min(3, $base.Length)) + $num).ToLower()
            } else {
                $script:AzureRegion.ToLower().Substring(0, [Math]::Min(3, $script:AzureRegion.Length))
            }
        }
        
        # The names of the resource group, the Key Vault, the storage account and the managed
        # identities. Each question shows the name from the answer file, or the standard name.
        # Press Enter to accept the name, or type another name. The script checks each name
        # against the naming rules of Azure.

        # The name of the resource group.
        # Build the solution name and the short name first. Each comes from the answer file or from the
        # standard pattern. Every other standard name holds the short name.
        $snAns = [string](Get-Answer 'solutionName')
        $script:ConfigData['SolutionName'] = if (-not [string]::IsNullOrWhiteSpace($snAns)) { $snAns.Trim().ToLower() }
                                             else { "neo-$($script:OrganizationCode.ToLower())$($script:EnvironmentType.ToLower())-$regionAbbrev-$($script:EnvironmentIndex)" }
        $ssnAns = [string](Get-Answer 'solutionShortName')
        $script:ConfigData['SolutionShortName'] = if (-not [string]::IsNullOrWhiteSpace($ssnAns)) { $ssnAns.Trim().ToLower() }
                                                  else { "$($script:OrganizationCode.ToLower())$($script:EnvironmentType.ToLower())$($script:EnvironmentIndex)" }

        $rgComputed = "rg-$($script:ConfigData['SolutionName'])"
        $rgAns = [string](Get-Answer 'resourceGroupName')
        $rgDefault = if (-not [string]::IsNullOrWhiteSpace($rgAns)) { $rgAns.Trim() } else { $rgComputed }
        $script:ResourceGroupName = Read-NameWithDefault -Title 'Resource Group Name' `
            -DefaultValue $rgDefault -Validator ${function:Test-ResourceGroupNameError} `
            -LabelPrefix (Get-PromptLabel $rgDefault $rgComputed)

        # The name of the Key Vault. The question shows the value from -KeyVaultName, then from the answer file, then the standard name.
        $kvComputed = "kv$($script:ConfigData['SolutionShortName'])"
        $kvAns = [string](Get-Answer 'keyVaultName')
        $kvDefault = if ($script:KeyVaultNameFromCli -and -not [string]::IsNullOrWhiteSpace($KeyVaultName)) { $KeyVaultName.Trim() }
                     elseif (-not [string]::IsNullOrWhiteSpace($kvAns)) { $kvAns.Trim() }
                     else { $kvComputed }
        $script:KeyVaultNameOverride = Read-NameWithDefault -Title 'Key Vault Name' `
            -DefaultValue $kvDefault -Validator ${function:Test-KeyVaultNameError} `
            -LabelPrefix (Get-PromptLabel $kvDefault $kvComputed)

        # The name of the deployment storage account. The deployment storage account holds the container 'certificate'.
        $saComputed = "stneodeploy$($script:OrganizationCode.ToLower())$($script:EnvironmentType.ToLower())$regionAbbrev$($script:EnvironmentIndex)"
        if ($saComputed.Length -gt 24) { $saComputed = $saComputed.Substring(0, 24) }
        $saAns = [string](Get-Answer 'storageAccountName')
        $saDefault = if (-not [string]::IsNullOrWhiteSpace($saAns)) { $saAns.Trim().ToLower() } else { $saComputed }
        $script:ConfigData['DeployStorageAccountName'] = Read-NameWithDefault -Title 'Deployment Storage Account Name' `
            -DefaultValue $saDefault -Validator ${function:Test-StorageAccountNameError} `
            -LabelPrefix (Get-PromptLabel $saDefault $saComputed)

        # The name of the script runner managed identity.
        $sriComputed = "neologik-script-runner-service-connection-$($script:ConfigData['SolutionShortName'])"
        $sriAns = [string](Get-Answer 'scriptRunnerIdentityName')
        $sriDefault = if (-not [string]::IsNullOrWhiteSpace($sriAns)) { $sriAns.Trim() } else { $sriComputed }
        $script:ConfigData['ScriptRunnerIdentityName'] = Read-NameWithDefault -Title 'Script Runner Managed Identity Name' `
            -DefaultValue $sriDefault -Validator ${function:Test-ManagedIdentityNameError} `
            -LabelPrefix (Get-PromptLabel $sriDefault $sriComputed)

        # The name of the SQL managed identity.
        $sqlComputed = "neologik-sql-managed-identity-$($script:ConfigData['SolutionShortName'])"
        $sqlAns = [string](Get-Answer 'sqlIdentityName')
        $sqlDefault = if (-not [string]::IsNullOrWhiteSpace($sqlAns)) { $sqlAns.Trim() } else { $sqlComputed }
        $script:ConfigData['SqlIdentityName'] = Read-NameWithDefault -Title 'SQL Managed Identity Name' `
            -DefaultValue $sqlDefault -Validator ${function:Test-ManagedIdentityNameError} `
            -LabelPrefix (Get-PromptLabel $sqlDefault $sqlComputed)

        # The name of the agent registration identity.
        $dirComputed = "neologik-directory-managed-identity-$($script:ConfigData['SolutionShortName'])"
        $dirAns = [string](Get-Answer 'directoryIdentityName')
        $dirDefault = if (-not [string]::IsNullOrWhiteSpace($dirAns)) { $dirAns.Trim() } else { $dirComputed }
        $script:ConfigData['DirectoryIdentityName'] = Read-NameWithDefault -Title 'Agent Registration Identity Name' `
            -DefaultValue $dirDefault -Validator ${function:Test-ManagedIdentityNameError} `
            -LabelPrefix (Get-PromptLabel $dirDefault $dirComputed)

        # The name of the system task managed identity.
        $taskComputed = "neologik-system-task-managed-identity-$($script:ConfigData['SolutionShortName'])"
        $taskAns = [string](Get-Answer 'systemTaskIdentityName')
        $taskDefault = if (-not [string]::IsNullOrWhiteSpace($taskAns)) { $taskAns.Trim() } else { $taskComputed }
        $script:ConfigData['SystemTaskIdentityName'] = Read-NameWithDefault -Title 'System Task Managed Identity Name' `
            -DefaultValue $taskDefault -Validator ${function:Test-ManagedIdentityNameError} `
            -LabelPrefix (Get-PromptLabel $taskDefault $taskComputed)

        # The name of the environment in the Neologik deployment, from the answer file or from the
        # organisation code and the environment type. The federated credential of the deployment identity names the environment.
        $environmentNameAns = [string](Get-Answer 'environmentName')
        $script:ConfigData['EnvironmentName'] = if (-not [string]::IsNullOrWhiteSpace($environmentNameAns)) { $environmentNameAns.Trim().ToLower() } else { "$($script:OrganizationCode)$($script:EnvironmentType)".ToLower() }
        if ($script:ConfigData['EnvironmentName'] -notmatch '^[a-z0-9]{2,32}$') { throw "environmentName '$($script:ConfigData['EnvironmentName'])': the name must be 2 to 32 lower-case letters and digits" }

        # A platform operator creates agents and channels in the Neologik Admin Tool after the
        # deployment. A channel uses the standard security group for users that this script creates, or an existing
        # security group that an administrator names. The Neologik Platform creates no security group.

        # Ask whether to tag the Azure resources that the script creates. An Azure Policy in a tenant can
        # refuse a resource without tags. The script therefore applies the tags at the creation of each resource. The
        # question shows the values of the keys 'applyResourceTags' and
        # 'resourceTagsCustom' in the answer file. The default value is to apply the tags.
        $tagsDefault = $true
        $tagsAns = Get-AnswerBool 'applyResourceTags'
        if ($null -ne $tagsAns) { $tagsDefault = $tagsAns }
        $tagsDefaultText = if ($tagsDefault) { 'true' } else { 'false' }
        $tagsValid = $false
        while (-not $tagsValid) {
            Write-Host ""
            Write-Host "Apply Azure resource tags to created resources? (true/false)" -ForegroundColor Cyan
            Write-Host "  The tags are Vendor, ApplicationName, ManagedBy, Environment, Solution and" -ForegroundColor Gray
            Write-Host "  DeploymentDate. The script applies the tags at the creation of each resource." -ForegroundColor Gray
            Write-Host "  Choose true when an Azure Policy refuses a resource without tags." -ForegroundColor Gray
            Write-Host "  Default: " -NoNewline -ForegroundColor Gray
            Write-Host $tagsDefaultText -ForegroundColor Yellow
            Write-Host "  Press Enter to accept the default value, or type true or false: " -NoNewline -ForegroundColor Gray
            $tagsInput = Read-Host

            if ([string]::IsNullOrWhiteSpace($tagsInput)) {
                $script:ConfigData['ResourceTagsEnabled'] = $tagsDefault
                $tagsValid = $true
            }
            elseif ($tagsInput.Trim() -match '^(true|yes|y|1)$') {
                $script:ConfigData['ResourceTagsEnabled'] = $true
                $tagsValid = $true
            }
            elseif ($tagsInput.Trim() -match '^(false|no|n|0)$') {
                $script:ConfigData['ResourceTagsEnabled'] = $false
                $tagsValid = $true
            }
            else {
                Write-Host "  The value is not valid. Enter true or false. Try again." -ForegroundColor Red
            }
        }
        if ($script:ConfigData['ResourceTagsEnabled']) {
            Write-Host "  Using: true. The script tags each resource at creation" -ForegroundColor Green
        }
        else {
            Write-Host "  Using: false. The script applies no tags" -ForegroundColor Green
        }

        # Custom tags. The script asks only when the administrator chooses tags. The format is
        # key=value pairs separated by commas. A custom tag replaces a standard tag of the same name.
        $script:ConfigData['ResourceTagsCustom'] = @{}
        if ($script:ConfigData['ResourceTagsEnabled']) {
            $customPrefill = ''
            $customAns = Get-Answer 'resourceTagsCustom'
            if ($null -ne $customAns) {
                try {
                    $prefillTags = ConvertTo-NeologikCustomTags $customAns
                    $customPrefill = (@($prefillTags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ',')
                }
                catch {
                    Write-Host "  The answer file holds a value for resourceTagsCustom that is not valid. The script ignores the value: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
            $customValid = $false
            while (-not $customValid) {
                Write-Host ""
                Write-Host "Custom resource tags:" -ForegroundColor Cyan
                Write-Host "  Enter key=value pairs separated by commas. A key can hold letters, digits, '.', '_'" -ForegroundColor Gray
                Write-Host "  and '-'. A custom tag replaces a standard tag of the same name." -ForegroundColor Gray
                Write-Host "  Example: " -NoNewline -ForegroundColor Gray
                Write-Host "CostCentre=IT123,Owner=Platform Team" -ForegroundColor Yellow
                if ($customPrefill) {
                    Write-Host "  Pre-filled: " -NoNewline -ForegroundColor Gray
                    Write-Host $customPrefill -ForegroundColor Yellow
                    Write-Host "  Press Enter to accept the value from the answer file, type 'none' for no custom tags, or type new pairs: " -NoNewline -ForegroundColor Gray
                }
                else {
                    Write-Host "  Press Enter for no custom tags, or type key=value pairs: " -NoNewline -ForegroundColor Gray
                }
                $customInput = Read-Host

                if ([string]::IsNullOrWhiteSpace($customInput)) {
                    $customInput = $customPrefill
                }
                elseif ($customInput.Trim() -match '^(none)$') {
                    $customInput = ''
                }

                try {
                    $script:ConfigData['ResourceTagsCustom'] = ConvertTo-NeologikCustomTags $customInput
                    $customValid = $true
                }
                catch {
                    Write-Host "  $($_.Exception.Message) Try again." -ForegroundColor Red
                    continue
                }

                if ($script:ConfigData['ResourceTagsCustom'].Count -gt 0) {
                    $customSummary = (@($script:ConfigData['ResourceTagsCustom'].GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')
                    Write-Host "  Using custom tags: $customSummary" -ForegroundColor Green
                }
                else {
                    Write-Host "  No custom tags" -ForegroundColor Green
                }
            }
        }

        # The script built the solution name and the short name before the questions about the resource names.
            }

        # The script makes three decisions before the summary: guest invitation, existing accounts and the
        # deployment service principal. The summary then shows the decisions, and the administrator confirms the
        # decisions with the configuration. For each decision, a parameter decides first, then the answer file,
        # then the question. Steps 8 and 11 act on the decisions and ask no question. The script holds the client
        # secret of a deployment service principal that you created in a script variable, not in ConfigData. The
        # checkpoint and the configuration file therefore never hold the client secret.

        # Guest invitation. The script adds the addresses typed at the prompt to the addresses in NeologikGuestUsers.txt.
        # The list of typed addresses starts empty, so that the summary and step 8 can read the list.
        $script:ConfigData['AdditionalGuestEmails'] = @()
        if ($script:SkipGuestInvitationFromCli) {
            $script:ConfigData['SkipGuestInvitation'] = [bool]$SkipGuestInvitation
        }
        else {
            $sgAns = Get-AnswerBool 'skipGuestInvitation'
            if ($null -ne $sgAns) {
                $script:ConfigData['SkipGuestInvitation'] = $sgAns
            }
            else {
                Write-Host ""
                # Find NeologikGuestUsers.txt first, when the file is not in the folder of the script.
                if ($script:NeologikGuestUsers.Count -eq 0 -and -not (Test-Path $script:GuestUsersFile) -and -not $script:NonInteractiveMode) {
                    Resolve-GuestUsersFile | Out-Null
                }
                Write-Host "Invite Neologik guest users into this tenant?" -ForegroundColor Cyan
                if ($script:NeologikGuestUsers.Count -gt 0) {
                    Write-Host "  The script invites these $($script:NeologikGuestUsers.Count) addresses from NeologikGuestUsers.txt:" -ForegroundColor Gray
                    $script:NeologikGuestUsers | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
                }
                else {
                    Write-Host "  NeologikGuestUsers.txt is empty or missing. Choose Y to type the addresses" -ForegroundColor Gray
                    Write-Host "  to invite, or N to invite nobody." -ForegroundColor Gray
                }
                Write-Host "  (Y/n, default: Y - invite): " -NoNewline -ForegroundColor Yellow
                $inviteAns = Read-Host
                # Enter accepts invitation. Only N or no declines invitation.
                $script:ConfigData['SkipGuestInvitation'] = ($inviteAns -match '^(n|no)$')

                # The administrator accepted invitation. Ask whether to add typed addresses to the addresses in the file.
                # When the file is empty or missing, ask for the whole list. An unattended run uses
                # the file only.
                if (-not $script:ConfigData['SkipGuestInvitation']) {
                    $addMore = $false
                    if ($script:NeologikGuestUsers.Count -gt 0) {
                        Write-Host "  Add further addresses to invite? (y/N, default: N): " -NoNewline -ForegroundColor Yellow
                        $moreAns = Read-Host
                        $addMore = ($moreAns -match '^(y|yes)$')
                    }
                    else {
                        $addMore = $true
                        Write-Host "  Enter the addresses to invite." -ForegroundColor Gray
                    }
                    if ($addMore) {
                        Write-Host "  Type one address on each line. A line can hold several addresses separated by commas." -ForegroundColor Gray
                        Write-Host "  Press Enter on an empty line to finish." -ForegroundColor Gray
                        $combined = @(Read-EmailAddressList -Seed @($script:NeologikGuestUsers))
                        $additional = @($combined | Where-Object { $script:NeologikGuestUsers -notcontains $_ })
                        $script:ConfigData['AdditionalGuestEmails'] = $additional
                        if ($additional.Count -gt 0) {
                            Write-Host "  The script invites $($additional.Count) further addresses and the $($script:NeologikGuestUsers.Count) addresses from the file:" -ForegroundColor Gray
                            $additional | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
                        }
                        elseif ($script:NeologikGuestUsers.Count -eq 0) {
                            Write-Host "  No address entered. The script invites no guest." -ForegroundColor Yellow
                        }
                    }
                }
            }
        }

        # Existing accounts. The script asks only when the administrator declined invitation. You may have created
        # accounts for Neologik support staff, as guests or as members. The script can add those accounts
        # to the security groups and sends no invitation. The script reads the answer file first and then
        # asks the question. The addresses come from the key
        # 'existingAccountEmails' in the answer file, from NeologikGuestUsers.txt, or from the prompt.
        $script:ConfigData['AddExistingAccountsToGroups'] = $false
        $script:ConfigData['ExistingAccountEmails'] = @()
        if ($script:ConfigData['SkipGuestInvitation']) {
            $addAns = Get-AnswerBool 'addExistingAccountsToGroups'
            if ($null -ne $addAns) {
                $script:ConfigData['AddExistingAccountsToGroups'] = $addAns
                Write-Log "Decision from the answer file: addExistingAccountsToGroups=$addAns." -Level Info
            }
            elseif (-not $script:NonInteractiveMode) {
                Write-Host ""
                Write-Host "Add existing accounts to the security groups?" -ForegroundColor Cyan
                Write-Host "  Choose Y when you created accounts for Neologik support staff in this" -ForegroundColor Gray
                Write-Host "  tenant, as guests or as members, and want the script to add the accounts to the" -ForegroundColor Gray
                Write-Host "  security groups now. The script sends no invitation. NOTE: each account joins ALL" -ForegroundColor Gray
                Write-Host "  Neologik security groups. One of the groups is the Admin User Group, which holds Azure administration roles." -ForegroundColor Gray
                Write-Host "  List only the accounts that need Neologik administration and support access." -ForegroundColor Gray
                Write-Host "  (y/N, default: N): " -NoNewline -ForegroundColor Yellow
                $addAnswer = Read-Host
                $script:ConfigData['AddExistingAccountsToGroups'] = ($addAnswer -match '^(y|yes)$')
            }

            if ($script:ConfigData['AddExistingAccountsToGroups']) {
                $emails = @()
                $ansEmails = Get-Answer 'existingAccountEmails'
                if ($null -ne $ansEmails) {
                    foreach ($entry in @($ansEmails)) {
                        $emails += @(([string]$entry) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                    }
                    Write-Log "Addresses of existing accounts from the answer file: $($emails.Count)." -Level Info
                }
                elseif ($script:NonInteractiveMode) {
                    # An unattended run with no list in the answer file uses NeologikGuestUsers.txt.
                    $emails = @($script:NeologikGuestUsers)
                    Write-Log "Unattended run: the script takes the addresses of existing accounts from NeologikGuestUsers.txt, $($emails.Count) addresses." -Level Info
                }
                else {
                    $useFile = $false
                    if ($script:NeologikGuestUsers.Count -gt 0) {
                        Write-Host ""
                        Write-Host "  Which source holds the addresses of the accounts?" -ForegroundColor Cyan
                        Write-Host "  NeologikGuestUsers.txt holds $($script:NeologikGuestUsers.Count) addresses:" -ForegroundColor Gray
                        $script:NeologikGuestUsers | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
                        Write-Host "  [F] Use the file   [T] Type the addresses   (F/t, default: F): " -NoNewline -ForegroundColor Yellow
                        $srcAnswer = Read-Host
                        $useFile = ($srcAnswer -notmatch '^(t|type)$')
                    }
                    if ($useFile) {
                        $emails = @($script:NeologikGuestUsers)
                    }
                    else {
                        # The administrator types one address on each line. A line can hold several addresses, separated by
                        # commas. An empty line ends the entry.
                        Write-Host "  Enter the email addresses, one on each line. A line can hold several addresses" -ForegroundColor Gray
                        Write-Host "  separated by commas. Each address must match the mail address or the user" -ForegroundColor Gray
                        Write-Host "  principal name of the account exactly. Press Enter on an empty line to finish." -ForegroundColor Gray
                        $emails = @(Read-EmailAddressList)
                        if ($emails.Count -eq 0) {
                            Write-Host "  No address entered. The script adds no account to the security groups." -ForegroundColor Yellow
                        }
                        else {
                            Write-Host "  Addresses entered, $($emails.Count) in total:" -ForegroundColor Gray
                            $emails | ForEach-Object { Write-Host "    - $_" -ForegroundColor Gray }
                        }
                    }
                }
                $script:ConfigData['ExistingAccountEmails'] = $emails
            }
        }

        # A deployment service principal that you created.
        $spChoice = Read-ExistingServicePrincipalChoice `
            -CliObjectId $ExistingServicePrincipalObjectId `
            -CliSecret $ExistingServicePrincipalSecret `
            -AnswerUseExisting (Get-AnswerBool 'useExistingServicePrincipal') `
            -AnswerObjectId ([string](Get-Answer 'existingServicePrincipalObjectId')) `
            -AnswerSecret ([string](Get-Answer 'existingServicePrincipalSecret'))
        $script:ConfigData['UseExistingServicePrincipal'] = $spChoice.UseExisting
        $script:ConfigData['ExistingServicePrincipalObjectId'] = $spChoice.ObjectId
        $script:ExistingSpSecretResolved = $spChoice.Secret

        # Show the summary
        Write-Host "`n+===============================================================+" -ForegroundColor Cyan
        Write-Host "|                                                               |" -ForegroundColor Cyan
        Write-Host "|                   CONFIGURATION SUMMARY                       |" -ForegroundColor Cyan
        Write-Host "|                                                               |" -ForegroundColor Cyan
        Write-Host "+===============================================================+" -ForegroundColor Cyan
        Write-Host ""
        # One width for every label keeps the values in a column
        function Write-SummaryRow {
            param([string]$Label, [string]$Value)
            Write-Host ("  {0,-24}" -f ($Label + ':')) -NoNewline
            Write-Host $Value -ForegroundColor Yellow
        }
        Write-SummaryRow 'Signed-in user' $script:ConfigData['UserAccount']
        Write-SummaryRow 'Tenant ID' $script:ConfigData['TenantId']
        Write-SummaryRow 'Subscription Name' $script:ConfigData['SubscriptionName']
        Write-SummaryRow 'Organization Name' $script:OrganizationName
        Write-SummaryRow 'Host name' $script:HostName
        Write-SummaryRow 'Organization Code' $script:OrganizationCode
        Write-SummaryRow 'Environment Type' $script:EnvironmentType
        Write-SummaryRow 'Environment Index' $script:EnvironmentIndex
        Write-SummaryRow 'Azure Region' $script:AzureRegion
        Write-SummaryRow 'Resource Group Name' $script:ResourceGroupName
        Write-SummaryRow 'Key Vault Name' $script:KeyVaultNameOverride
        Write-SummaryRow 'Storage Account Name' $script:ConfigData['DeployStorageAccountName']
        Write-SummaryRow 'Script Runner Identity' $script:ConfigData['ScriptRunnerIdentityName']
        Write-SummaryRow 'SQL Managed Identity' $script:ConfigData['SqlIdentityName']
        Write-SummaryRow 'Agent Registration Identity' $script:ConfigData['DirectoryIdentityName']
    Write-SummaryRow 'System Task Managed Identity' $script:ConfigData['SystemTaskIdentityName']
        Write-SummaryRow 'Solution Name' $script:ConfigData['SolutionName']
        Write-SummaryRow 'Solution Short Name' $script:ConfigData['SolutionShortName']
        Write-SummaryRow 'Provider Registration' "$($script:ProviderList.Providers.Count) resource providers and $($script:ProviderList.Features.Count) preview features, from resource-providers.txt"
        $tagsSummary = if ($script:ConfigData['ResourceTagsEnabled']) {
            $customCount = @($script:ConfigData['ResourceTagsCustom'].Keys).Count
            if ($customCount -gt 0) { "Yes, with $customCount custom tags" } else { 'Yes' }
        }
        else { 'No' }
        Write-SummaryRow 'Apply Resource Tags' $tagsSummary
        $guestSummary = if (-not $script:ConfigData['SkipGuestInvitation']) {
                            $typedCount = @($script:ConfigData['AdditionalGuestEmails'] | Where-Object { $_ }).Count
                            if ($typedCount -gt 0) { "Yes: $($script:NeologikGuestUsers.Count) from the file and $typedCount typed" } else { 'Yes' }
                        }
                        elseif ($script:ConfigData['AddExistingAccountsToGroups']) { "No. The script adds $(@($script:ConfigData['ExistingAccountEmails']).Count) existing accounts to the security groups" }
                        else { 'No (skipped)' }
        Write-SummaryRow 'Invite Neologik Guests' $guestSummary
        if ($script:ConfigData['UseExistingServicePrincipal']) {
            Write-SummaryRow 'Deployment identity' "Created by you: $($script:ConfigData['ExistingServicePrincipalObjectId'])"
        }
        else {
            Write-SummaryRow 'Deployment identity' 'Create new'
        }
        Write-Host ""
        if ($answerComplete) {
            if ($script:NonInteractiveMode) {
                # The answer file is complete. The run continues without confirmation.
                Write-Log "Unattended run: the script continues with the settings from the answer file shown above" -Level Info
                break
            }
            # The script requires confirmation. The administrator types Y to continue or N to edit.
            $confirmChoice = ''
            while ($confirmChoice -notmatch '^[YyNn]$') {
                Write-Host ""
                Write-Host "Continue with these settings? Type Y to continue, or N to edit: " -NoNewline -ForegroundColor Yellow
                $confirmChoice = (Read-Host).Trim()
            }
            if ($confirmChoice -match '^[Nn]$') {
                Write-Host "`n  Edit: the script asks for each value and shows your earlier answer as the default value..." -ForegroundColor Cyan
                $editing = $true
                continue
            }
            break
        }
        else {
            Write-Host "Press Enter to continue with these settings, or Ctrl+C to stop..." -ForegroundColor Yellow
            Read-Host
            break
        }
        }

        # Save the confirmed configuration to the checkpoint. A later run can then resume
        # when a later step fails.
        $script:CheckpointRegionAbbrev = $regionAbbrev
        Complete-OnboardingStep 'ConfigGathered'

        } else {
            # A resumed run takes the short form of the region from the checkpoint.
            $regionAbbrev = $script:CheckpointRegionAbbrev

            # Tags: when the checkpoint holds no choice, the script applies no tags.
            if (-not $script:ConfigData.ContainsKey('ResourceTagsEnabled')) {
                $script:ConfigData['ResourceTagsEnabled'] = $false
                $script:ConfigData['ResourceTagsCustom'] = @{}
            }
            # Decisions: when the checkpoint holds no decision, the default values apply. The checkpoint never
            # holds the client secret of a deployment service principal that you created. A resumed
            # run therefore cannot store the client secret. Add the client secret to the Key Vault.
            if (-not $script:ConfigData.ContainsKey('SkipGuestInvitation')) {
                $script:ConfigData['SkipGuestInvitation'] = $false
            }
            if (-not $script:ConfigData.ContainsKey('UseExistingServicePrincipal')) {
                $script:ConfigData['UseExistingServicePrincipal'] = $false
                $script:ConfigData['ExistingServicePrincipalObjectId'] = ''
            }

            Write-Host "`n  >> The script restored the configuration from the checkpoint and asks no question" -ForegroundColor Gray
            Write-Host "     Org: $($script:OrganizationCode)  |  Env: $($script:EnvironmentType)  |  Region: $($script:AzureRegion)" -ForegroundColor Cyan
            Write-Host "     Resource Group: $($script:ResourceGroupName)" -ForegroundColor Cyan
            Write-Host ""

            # A resumed run honours -SkipGuestInvitation from this command line. Without the
            # parameter, the answer of the earlier run stands.
            if ($script:SkipGuestInvitationFromCli) {
                $script:ConfigData['SkipGuestInvitation'] = [bool]$SkipGuestInvitation
            }
        }

        # Step 7: Create the resource group
        $null = New-NeologikResourceGroup -ResourceGroupName $script:ResourceGroupName -Location $script:AzureRegion

        # Step 8: Invite the guest users, unless the administrator declined invitation. When the administrator chose
        # to add existing accounts, the script looks up the accounts and invites nobody. The script reports an address
        # that matches no account and continues. The administrator made both decisions
        # in step 6.
        if ($script:ConfigData['SkipGuestInvitation']) {
            Write-Log "The configuration declines guest invitation. The script invites no guest user." -Level Info
            $guestUsers = @()
            if ($script:ConfigData['AddExistingAccountsToGroups']) {
                $guestUsers = @(Invoke-ExistingAccountResolution -Emails @($script:ConfigData['ExistingAccountEmails']))
            }
        }
        else {
            # The addresses from the file and the addresses typed at the prompt. The script uses an existing
            # account unchanged and invites the other addresses.
            $inviteEmails = @(@($script:NeologikGuestUsers) + @($script:ConfigData['AdditionalGuestEmails'] | Where-Object { $_ }) | Select-Object -Unique)
            $guestUsers = Invoke-GuestUserInvitation -GuestEmails $inviteEmails
        }

        # Step 9: Create the security groups, with the signed-in user and the guest users as members
        $securityGroups = New-NeologikSecurityGroups -GuestUsers $guestUsers -OrganizationCode $script:OrganizationCode -EnvironmentType $script:EnvironmentType -EnvironmentIndex $script:EnvironmentIndex

        # Step 10: Assign the Azure roles of the Admin User Group
        $null = Set-NeologikRoleAssignments -SecurityGroups $securityGroups -SubscriptionId $script:ConfigData['SubscriptionId'] -ResourceGroupName $script:ResourceGroupName

        # Step 11: The deployment identity. In step 6, the administrator decided whether the script creates the
        # deployment identity or uses a deployment service principal that you created. Both receive
        # the same Azure roles.
        if ($script:ConfigData['UseExistingServicePrincipal']) {
            $appReg = Get-NeologikExistingAppRegistration `
                -ServicePrincipalObjectId $script:ConfigData['ExistingServicePrincipalObjectId'] `
                -ProvidedSecret $script:ExistingSpSecretResolved
        }
        else {
            $appReg = New-NeologikAppRegistration -OrganizationCode $script:OrganizationCode -EnvironmentType $script:EnvironmentType -EnvironmentIndex $script:EnvironmentIndex
        }

        # Assign the Azure roles to the deployment identity.
        $null = Set-AppRegistrationRoles -ServicePrincipalId $appReg.ServicePrincipal.Id `
            -SubscriptionId $script:ConfigData['SubscriptionId'] `
            -ResourceGroupName $script:ResourceGroupName `
            -SecurityGroups $securityGroups

        # Step 12: Create the Key Vault and store the client secret
        if (-not [string]::IsNullOrWhiteSpace($script:KeyVaultNameOverride)) {
            # The script uses a Key Vault name of your choice unchanged. The name comes from -KeyVaultName on this run,
            # or from the checkpoint of a resumed run.
            $keyVaultName = $script:KeyVaultNameOverride
            Write-Log "Using the Key Vault name of your choice: $keyVaultName" -Level Info
        }
        else {
            $keyVaultName = "kv$($script:ConfigData['SolutionShortName'])"
        }

        # The name of a Key Vault holds 3 to 24 characters: letters, digits and hyphens
        if ($keyVaultName.Length -gt 24) {
            Write-Log "The name of the Key Vault is too long. The script cuts the name to 24 characters" -Level Warning
            $keyVaultName = $keyVaultName.Substring(0, 24)
        }
        
        $null = New-NeologikKeyVault -ResourceGroupName $script:ResourceGroupName `
            -Location $script:AzureRegion `
            -KeyVaultName $keyVaultName `
            -ClientSecret $appReg.Secret `
            -SecurityGroups $securityGroups `
            -SubscriptionId $script:ConfigData['SubscriptionId']

        # Step 12b: The Platform Sign-in application. The script creates the application here, signed in as a Global
        # Administrator. The script can then assign the security groups to the application at onboarding.
        $null = New-NeologikNceAuthApp -SecurityGroups $securityGroups `
            -DeploySpObjectId $appReg.ServicePrincipal.Id `
            -KeyVaultName $keyVaultName

        # Step 12c: The agent identity blueprint. The script creates the agent identity blueprint here, signed in as a Global
        # Administrator. The deployment identity therefore needs no permission to
        # create agent identity blueprints. The signed-in administrator is the sponsor of the agent identity blueprint. A Global Administrator can
        # change the sponsor in the Microsoft Entra admin centre. The deployment identity owns the agent identity blueprint.
        $null = New-NeologikAgentBlueprint -DeploySpObjectId $appReg.ServicePrincipal.Id `
            -SponsorUserId $script:ConfigData['CurrentUserId']

        # Step 12d: The federated credential of the deployment identity. Only a signed-in administrator can add the
        # federated credential, because the deployment identity does not own its own application registration.
        # A checkpoint from an earlier version holds no environment name, so the script works out the name here.
        $deploymentEnvironmentName = [string]$script:ConfigData['EnvironmentName']
        if ([string]::IsNullOrWhiteSpace($deploymentEnvironmentName)) { $deploymentEnvironmentName = "$($script:OrganizationCode)$($script:EnvironmentType)".ToLower() }
        $null = Set-NeologikDeploymentCredential -ClientId ([string]$appReg.Application.AppId) -EnvironmentName $deploymentEnvironmentName

        # The script has no step 13. Step 5c submits the resource provider registrations that the script needs.
        # Step 15b submits the other registrations and confirms every registration, before the script writes
        # the configuration file.

        # Step 14: Create the storage account and the containers. The administrator decided the name in
        # step 6. When a checkpoint holds no name, the script uses the standard name.
        $storageAccountName = [string]$script:ConfigData['DeployStorageAccountName']
        if ([string]::IsNullOrWhiteSpace($storageAccountName)) {
            $storageAccountName = "stneodeploy$($script:OrganizationCode.ToLower())$($script:EnvironmentType.ToLower())$regionAbbrev$($script:EnvironmentIndex)"
        }

        # The name of a storage account holds 3 to 24 characters: lower-case letters and digits
        if ($storageAccountName.Length -gt 24) {
            Write-Log "The name of the storage account is too long. The script cuts the name to 24 characters" -Level Warning
            $storageAccountName = $storageAccountName.Substring(0, 24)
        }

        $null = New-NeologikStorageAccount -ResourceGroupName $script:ResourceGroupName `
            -Location $script:AzureRegion `
            -StorageAccountName $storageAccountName `
            -SecurityGroups $securityGroups

        # Step 15: Create the managed identities
        $null = New-NeologikManagedIdentities -ResourceGroupName $script:ResourceGroupName `
            -Location $script:AzureRegion `
            -SubscriptionId $script:ConfigData['SubscriptionId'] `
            -OrganizationCode $script:OrganizationCode `
            -EnvironmentType $script:EnvironmentType `
            -EnvironmentIndex $script:EnvironmentIndex `
            -ScriptRunnerIdentityName ([string]$script:ConfigData['ScriptRunnerIdentityName']) `
            -SqlIdentityName ([string]$script:ConfigData['SqlIdentityName']) `
            -DirectoryIdentityName ([string]$script:ConfigData['DirectoryIdentityName']) `
            -SystemTaskIdentityName ([string]$script:ConfigData['SystemTaskIdentityName'])

        # Step 15b: Submit the registration of every other resource provider and every preview feature in the list.
        # The deployment of the Neologik Platform needs them. This run does not. Then confirm every resource provider
        # and every preview feature in the list. The script reports each entry that is still in progress, and writes
        # the entry to the configuration file as ResourceProvidersPending.
        Start-ResourceProviderRegistration -Providers $script:ProviderList.PlatformProviders -Features $script:ProviderList.Features
        Complete-ResourceProviderRegistration -ProviderList $script:ProviderList
        Complete-OnboardingStep 'ResourceProviders'

        # Step 15c: Record this version of the onboarding kit on the resource group. Every step of this version is now complete.
        Set-NeologikKitVersionTag -ResourceId "/subscriptions/$($script:ConfigData['SubscriptionId'])/resourceGroups/$($script:ResourceGroupName)"

        # Step 16: Write the configuration file
        Export-ConfigurationData

        # Delete the checkpoint when the run is complete
        if ($script:CheckpointFile -and (Test-Path $script:CheckpointFile)) {
            Remove-Item $script:CheckpointFile -ErrorAction SilentlyContinue
            Write-Log "The run is complete. The script deleted the checkpoint file" -Level Info
        }

        Write-Log "The Neologik onboarding script completed." -Level Success
    }
    catch {
        Write-Log "Onboarding failed: $_" -Level Error
        # The stack trace goes to the log file only.
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Info -LogFileOnly

        if ($_.Exception.Message -match "Insufficient permissions:|ERROR: Insufficient permissions") {
            Write-Host "`n[X] The onboarding script stopped: a permission is missing." -ForegroundColor Red
            Write-Host "   The error details above name the permission that the script requires." -ForegroundColor Yellow
            if ($script:CheckpointFile -and (Test-Path $script:CheckpointFile)) {
                Write-Host ""
                Write-Host "  [OK] The script saved your configuration as a checkpoint." -ForegroundColor Green
                Write-Host "    After you obtain the permission, run the script again and choose 'Y' to resume." -ForegroundColor Cyan
                Write-Host "    The script restores your answers." -ForegroundColor Cyan
            }
            Write-Host ""
            exit 2
        }
        else {
            Write-Host "`n[X] The onboarding script failed. The log file holds the details:" -ForegroundColor Red
            Write-Host "   $script:LogFile" -ForegroundColor Yellow
            if ($script:CheckpointFile -and (Test-Path $script:CheckpointFile)) {
                Write-Host ""
                Write-Host "  [OK] The script saved your configuration as a checkpoint." -ForegroundColor Green
                Write-Host "    Run the script again and choose 'Y' to resume." -ForegroundColor Cyan
            }
            Write-Host ""
            exit 1
        }
    }
}

# Run the onboarding. A test dot-sources the script to reach its functions and does not run it.
if ($MyInvocation.InvocationName -ne '.') {
    Start-NeologikOnboarding
}

#endregion
