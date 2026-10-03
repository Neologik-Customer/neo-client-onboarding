#Requires -Version 7.4

<#
.SYNOPSIS
    Reduces the access of the Neologik deployment identity to the access that Neologik
    Platform version 5 needs. A Global Administrator runs the script.

.DESCRIPTION
    ENVIRONMENT-ACCESS-SCRIPT-GUIDE.md describes the script in full.

    The script reads the current state before each change. On an environment that
    already holds the correct access, the script changes nothing. A Global
    Administrator can run the script again at any time.

    With -Verify the script reports each change that a run would make. The script
    then writes nothing.

    The script does not stop at the first problem. The script checks each item
    separately. When an item fails, the script records the item and the reason in
    the summary.

    The run ends with a summary table and a summary file in JSON.

      Exit code  Meaning
      0          Every item is in the expected state.
      1          An item needs attention. With -Verify, a change is pending.

    The command selects the run.

      Command                                        Run
      No -AgentGrantsFile and no -MailboxGrantsFile  The first run
      -AgentGrantsFile or -MailboxGrantsFile         The later run

    THE FIRST RUN

    Step 1. The agent identity blueprint and the permissions of the deployment
    identity.
      The script confirms each object in this list. The script creates an object
      only when the object is absent.
        - The agent identity blueprint
          'Neologik Agent Blueprint - <key> - <short name>'.
        - The service principal of the agent identity blueprint.
        - The deployment identity as an owner of both objects.
        - The sponsor of the agent identity blueprint. The sponsor is the person
          who is accountable for the agents of the environment. The signed-in
          Global Administrator becomes the sponsor when the agent identity
          blueprint has no sponsor.
        - The permission AgentIdUser.ReadWrite.IdentityParentedBy on the service
          principal of the agent identity blueprint.
        - Three federated credentials. The Neologik deployment signs in as the
          agent identity blueprint through a federated credential.
      The script then confirms the two Microsoft Graph application permissions
      that the deployment identity keeps.
        - Application.ReadWrite.OwnedBy
        - AgentIdentityBlueprint.AddRemoveCreds.All
      When the deployment identity holds both permissions, the script removes
      seven Microsoft Graph application permissions from the deployment identity.
        - Application.Read.All
        - AgentIdentityBlueprint.Create
        - AgentIdentityBlueprint.UpdateAuthProperties.All
        - AgentIdentityBlueprintPrincipal.Create
        - AgentIdentity.Create.All
        - AgentIdUser.ReadWrite.All
        - Group.Create

    Step 2. The security groups, the Neologik guest users and the memberships.
      The script confirms the four security groups of version 5 in this tenant:
        - 'Neologik User Group - <short name>'
        - 'Neologik NCE Contributors - <short name>', the user group of the
          Neologik Context Engine under its version 5 name. The script renames
          'Neologik NCE User Group - <short name>'. The group keeps the id and
          the members.
        - 'Neologik NCE Admins - <short name>', the administrators of the
          Neologik Context Engine.
        - 'Neologik Admin User Group - <short name>'
      The script creates a group that is absent. The script then confirms that
      each Neologik support account in NeologikGuestUsers.txt is a guest of the
      tenant, and invites an account that is absent. Last, the script confirms
      that each guest and the signed-in administrator are direct members of
      every group, and adds a membership that is absent. The script removes no
      member.

    Step 3. The role groups of the Neologik Context Engine.
      The script assigns the user group that -NceUserGroupId names, and the
      group 'Neologik NCE Admins', to the enterprise application 'Neologik
      Platform Sign-in'. The Neologik Context Engine reads the groups claim of
      the sign-in token to authorise a user. The groups claim lists only the
      groups that are assigned to the enterprise application.

    Step 4. Administrator consent.
      The script confirms that the Platform Sign-in application has administrator
      consent for the whole tenant. When the consent is absent, the script prints
      the consent address. A Global Administrator opens the consent address, reads
      the permissions and gives the consent. The script never gives consent.

    Step 4a. SharePoint consent.
      The SharePoint application of the environment needs the Microsoft Graph
      application permission Sites.Selected. A consent belongs to one application.
      When the SharePoint application holds Sites.Selected, the script changes
      nothing. When an earlier SharePoint application of Neologik in the tenant
      holds a SharePoint permission, the script grants Sites.Selected to the
      SharePoint application of the environment. When the SharePoint application
      does not exist yet, run the script again after the deployment by Neologik.
      When no application holds a SharePoint permission, the script grants
      nothing. When the configuration file records SharePoint ingestion, the
      script then prints the consent address. A site administrator grants access
      to each SharePoint site separately.

    Step 4b. Ownership of the application registrations.
      The deployment identity can manage only an application registration that the
      deployment identity owns. The script changes only the application
      registrations that the command names by client id.

        Parameter               Application registration
        -SignInAppClientId      The Platform Sign-in application
        -SharePointAppClientId  The SharePoint application
        -BotAppClientIds        The application registration of each agent

      For each application registration, the script adds the deployment identity
      as an owner when the deployment identity is not an owner. The script sets the
      unique name of the Platform Sign-in application and of the SharePoint
      application when the unique name is empty.

      The summary lists every other application registration whose name begins
      'Neologik'. The script does not change those application registrations.

    Step 5. Permission reduction.
      The script first confirms that the deployment identity holds nine Azure
      roles: seven roles on the resource group and two roles on the subscription.
      The two roles on the subscription are Reader and Cost Management Contributor.
      The deployment uses Cost Management Contributor for the daily cost report.

      When the deployment identity holds all nine roles, the script removes the
      wider access from the deployment identity.
        - Contributor on the subscription.
        - User Access Administrator on the subscription.
        - The directory role Application Administrator.
        - The membership of the Admin User Group. The script removes the
          membership only when each SQL server in the resource group names the
          deployment identity as the Microsoft Entra administrator.
        - Every other Azure role in the subscription. The script keeps the role
          Cognitive Services Content Understanding Contributor on a resource in
          the resource group.
        - Every other directory role and every other group membership.
      When the script cannot assign one of the nine roles, the script removes
      nothing.

      Last, the script records the version of the onboarding kit on the resource
      group, in the tag NeologikOnboardingKit.

    THE LATER RUN

    The later run is needed only when an agent or an App works unattended in
    Microsoft 365. The later run applies the grants that the files list. The later
    run makes no other change.

    Step 5. Grants to agent users, with -AgentGrantsFile.
      For each agent and each App in the file, the script creates one delegated
      permission grant. The grant lets the agent identity act as the agent user of
      that agent identity. The grant holds exactly the permissions that the file
      lists.

      The file can also list Microsoft Graph application permissions for named
      workload identities. The script grants those permissions.

      The file records whether the solution uses SharePoint ingestion. When the
      solution uses SharePoint ingestion, the script checks the consent of the
      SharePoint application.

    Step 6. Mailbox grants, with -MailboxGrantsFile.
      For each email channel in the file, the script grants three Exchange Online
      roles to the identity of the email channel.
        - Application Mail.Read
        - Application Mail.ReadWrite
        - Application Mail.Send
      Each role is limited to the one mailbox of the email channel.

      With -RemoveLegacyGrantAppIds the script also removes the Exchange Online
      role assignments of an identity that the environment has stopped using.

      Step 6 needs the sign-in of an Exchange Administrator or of a Global
      Administrator.

    PERMISSIONS THAT THE SIGN-IN REQUESTS

    The sign-in to Microsoft Graph requests delegated permissions only. The script
    uses each permission with the account of the signed-in Global Administrator.

      Run                          Delegated permission
      Every run                    Application.ReadWrite.All
      Every run                    AppRoleAssignment.ReadWrite.All
      Every run                    Directory.Read.All
      Every run                    User.Read
      Every run                    DelegatedPermissionGrant.Read.All
      Every run                    AgentIdentityBlueprint.Create
      Every run                    AgentIdentityBlueprint.AddRemoveCreds.All
      Every run                    AgentIdentityBlueprintPrincipal.Create
      The first run                RoleManagement.ReadWrite.Directory
      The first run                GroupMember.ReadWrite.All
      The first run                AgentIdentityBlueprintPrincipal.ReadWrite.All
      A run with -AgentGrantsFile  DelegatedPermissionGrant.ReadWrite.All

    OUTPUT

    The script prints a summary table. The script also writes the summary file
    Neologik_EnvironmentAccess_<PreWindow|PostWindow>_<time stamp>.json. The name
    holds PreWindow for the first run and PostWindow for the later run.

    The script writes the summary file to the folder of the script. When the script
    cannot write to that folder, the script writes to the current folder. When the
    script cannot write to the current folder, the script writes to the temporary
    folder.

.PARAMETER ConfigurationFile
    The configuration file that Install-NeologikEnvironment.ps1 wrote at onboarding.
    The parameter is optional. The configuration file holds the tenant, the
    subscription, the resource group, the deployment identity, the Platform Sign-in
    application, the group ids and the solution names. The command from Neologik
    gives each value as a parameter, so the command needs no configuration file.

.PARAMETER Verify
    The script reports each change that the run would make as a 'WOULD' item in the
    summary. The script writes nothing. The sign-ins are the same as the sign-ins
    of a run that writes. The exit code is 1 when a change is pending or an item
    needs attention. Otherwise the exit code is 0.

.PARAMETER TenantId
    The id of your Microsoft Entra tenant. Required when the command names no
    configuration file.

.PARAMETER DeploySpClientId
    The client id of the deployment identity. The deployment identity is the
    application 'Neologik GitHub Service Connection'. Required when the command
    names no configuration file.

.PARAMETER SolutionName
    The solution name of the environment, for example neo-abcprd-uks-01. Required
    for the first run.

.PARAMETER SolutionShortName
    The short name of the environment, for example abcprd01. The name of the agent
    identity blueprint holds the short name. Required for the first run.

.PARAMETER SignInAppClientId
    The client id of the application 'Neologik Platform Sign-in'. Required for the
    first run.

.PARAMETER SharePointAppClientId
    The client id of the application 'Neologik SharePoint Access - <short name>'.
    Give the parameter when the environment uses SharePoint ingestion. Without the
    parameter the script changes no SharePoint application registration.

.PARAMETER BotAppClientIds
    The client id of the application registration of each agent that the Neologik
    Platform manages in this tenant. The script does not change an application
    registration that the parameter does not list.

.PARAMETER NceUserGroupId
    The object id of the security group whose members sign in to the Neologik
    Context Engine. Without the parameter the script skips step 2 and step 3.

.PARAMETER GuestUsersFile
    The file that lists the Neologik support accounts, one mail address per line.
    Without the parameter, the script reads NeologikGuestUsers.txt from the folder
    of the script. The onboarding kit ships the file with the script. The first run
    uses the file.

.PARAMETER AdminGroupId
    The object id of the Neologik Admin User Group. Without the parameter, and
    without a configuration file that names the group, the first run does not check
    the membership of the Admin User Group. The summary then reads 'Not checked'.

.PARAMETER AgentGrantsFile
    The JSON file of grants to agent users. Neologik exports the file from the
    Neologik Platform and sends the file to you. The parameter selects the later
    run. The tenant id in the file must be the tenant id of the run.

.PARAMETER MailboxGrantsFile
    The JSON file of mailbox grants. Neologik exports the file from the Neologik
    Platform and sends the file to you. The parameter selects the later run.

.PARAMETER RemoveLegacyGrantAppIds
    The application id of each identity that the environment has stopped using. The
    script removes the Exchange Online role assignments of each identity. The
    parameter requires -MailboxGrantsFile. The script keeps the role assignments of
    an identity that the mailbox grants file records as still in use.

.PARAMETER UseAzureCliToken
    The script signs in to Microsoft Graph and to Azure with the Azure CLI session
    of the workstation. The script shows no sign-in prompt. Neologik uses the
    parameter. Leave the parameter out of the command.

.PARAMETER SubscriptionId
    The id of the Azure subscription. Required for the first run when the command
    names no configuration file.

.PARAMETER ResourceGroupName
    The name of the Neologik resource group. Required for the first run when the
    command names no configuration file.

.PARAMETER BlueprintKey
    The key in the name of the agent identity blueprint. The default is 'default'.
    Change the value only when Neologik gives you another value.

.EXAMPLE
    ./Update-NeologikEnvironmentAccess.ps1 -TenantId <tenant id> -DeploySpClientId <deployment identity client id> -SolutionName neo-abcprd-uks-01 -SolutionShortName abcprd01 -SignInAppClientId <sign-in application client id> -SharePointAppClientId <SharePoint application client id> -BotAppClientIds <client id>,<client id> -NceUserGroupId <group object id> -AdminGroupId <group object id> -SubscriptionId <subscription id> -ResourceGroupName rg-neo-abcprd-uks-01

    The first run, with the command that Neologik sends.

.EXAMPLE
    ./Update-NeologikEnvironmentAccess.ps1 -TenantId <tenant id> -DeploySpClientId <client id> -SolutionName neo-abcprd-uks-01 -SolutionShortName abcprd01 -SignInAppClientId <client id> -BotAppClientIds <client id> -NceUserGroupId <group id> -SubscriptionId <subscription id> -ResourceGroupName rg-neo-abcprd-uks-01 -Verify

    The first run with -Verify. The script reports each pending change and writes nothing.

.EXAMPLE
    ./Update-NeologikEnvironmentAccess.ps1 -ConfigurationFile ./Neologik_abc01_Configuration_20260101_120000.json -AgentGrantsFile ./agent-grants-abcprd01.json

    The later run. The script applies the grants to agent users that the file lists.

.EXAMPLE
    ./Update-NeologikEnvironmentAccess.ps1 -ConfigurationFile ./Neologik_abc01_Configuration_20260101_120000.json -MailboxGrantsFile ./mailbox-grants-abcprd01.json -RemoveLegacyGrantAppIds 11111111-2222-3333-4444-555555555555

    The later run. The script applies the mailbox grants that the file lists. The script also removes the role assignments of one identity that the environment has stopped using.

.NOTES
    Requires PowerShell 7.4 or later.

    Sign-in. The script opens the sign-in page in the browser of this computer.
    Sign in as a Global Administrator. The script waits for 5 minutes at most. The
    script reports every 30 seconds that the script still waits.

    When the browser sign-in does not complete, the script prints a web address and
    a code. Open the web address in a browser on any device, enter the code and sign
    in. The script waits while the code is valid, for 15 minutes at most. Some
    organisations block this sign-in with a Conditional Access policy. The script
    then says so and tries the next method.

    When that sign-in does not complete either, the script tries the Azure CLI
    session of the workstation, when the workstation has an Azure CLI session. The
    script then tries the device code prompt of Microsoft Graph PowerShell.

    The sign-in to Azure and the sign-in to Exchange Online follow the same order.
    The browser signs in with the same account, so the browser does not usually ask
    again.

    Checks. Before the script changes anything, the script confirms three facts.
      1. The workstation can reach each Microsoft address that the script uses.
      2. The PowerShell modules load.
      3. The signed-in account holds an active Global Administrator role.
    Before step 5 changes an Azure role, the script confirms that the signed-in
    account holds Owner or User Access Administrator on the subscription.
#>

# The script writes to the console with Write-Host, because the person who runs the
# script reads the summary table and the consent addresses on screen.
# The script holds the Azure CLI token as a secure string, which Connect-MgGraph
# requires. The script writes the token nowhere.
# The script does not use ShouldProcess, because the script reads the current state
# before each write.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'The script runs in a console. The person who runs the script reads the summary table and the consent addresses on screen.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Connect-MgGraph requires a secure string. The script takes the token from the Azure CLI session and writes the token nowhere.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'The onboarding script uses the same function name. PowerShell 7 has no built-in command named Write-Log.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPositionalParameters', 'Get-NeologikProperty', Justification = 'Get-NeologikProperty takes the object, the name and the default value in that order. Named parameters would make each of the 60 calls three times as long.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The script reads the current state before each write. A second run changes nothing that the first run completed.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigurationFile,

    [Parameter(Mandatory = $false)]
    [switch]$Verify,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$DeploySpClientId,

    [Parameter(Mandatory = $false)]
    [string]$SolutionShortName,
    [string]$SolutionName,

    [Parameter(Mandatory = $false)]
    [string]$SignInAppClientId,

    [Parameter(Mandatory = $false)]
    [string]$SharePointAppClientId,

    [Parameter(Mandatory = $false)]
    [string[]]$BotAppClientIds,

    [Parameter(Mandatory = $false)]
    [string]$NceUserGroupId,

    [Parameter(Mandatory = $false)]
    [string]$AdminGroupId,

    [Parameter(Mandatory = $false)]
    [string]$GuestUsersFile,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$BlueprintKey = 'default',

    [Parameter(Mandatory = $false)]
    [string]$AgentGrantsFile,

    [Parameter(Mandatory = $false)]
    [string]$MailboxGrantsFile,

    [Parameter(Mandatory = $false)]
    [string[]]$RemoveLegacyGrantAppIds,

    [Parameter(Mandatory = $false)]
    [switch]$UseAzureCliToken
)

# The two Microsoft Graph application permissions that the deployment identity keeps.
# The script finds each permission by name on the service principal of Microsoft Graph.
# Install-NeologikEnvironment.ps1 grants the same two permissions.
$script:RequiredGraphRoles = @(
    'Application.ReadWrite.OwnedBy',
    'AgentIdentityBlueprint.AddRemoveCreds.All'
)
# The Microsoft Graph application permissions that the script removes from the
# deployment identity.
# The script removes the permissions only when the deployment identity holds the two
# permissions above.
$script:RetiredGraphRoles = @(
    'Application.Read.All',
    'AgentIdentityBlueprint.Create',
    'AgentIdentityBlueprint.UpdateAuthProperties.All',
    'AgentIdentityBlueprintPrincipal.Create',
    'AgentIdentity.Create.All',
    'AgentIdUser.ReadWrite.All',
    # The Neologik Platform creates no group. The script removes the permission to
    # create groups.
    'Group.Create'
)
# The permission of the service principal of the agent identity blueprint. The
# permission covers only the agent users of that agent identity blueprint.
$script:BlueprintPrincipalGraphRoles = @('AgentIdUser.ReadWrite.IdentityParentedBy')
# The repositories of the Neologik deployment that can obtain a token as the agent
# identity blueprint.
# Each entry holds the repository id, which never changes.
# Install-NeologikEnvironment.ps1 holds the same three repositories.
$script:PipelineRepositories = @(
    @{ Name = 'neo-infrastructure'; Id = '995398788' },
    @{ Name = 'neo-bot-service';    Id = '995400343' },
    @{ Name = 'neo-env-config';     Id = '995441655' }
)

# The seven roles of the deployment identity on the resource group.
# Install-NeologikEnvironment.ps1 assigns the same seven roles.
$script:RequiredRgRoles = @(
    'Contributor',
    'Key Vault Certificates Officer',
    'Key Vault Secrets Officer',
    'Storage Blob Data Contributor',
    'Azure Kubernetes Service RBAC Cluster Admin',
    'Monitoring Contributor',
    'Role Based Access Control Administrator'
)

# The two roles that the deployment identity keeps on the subscription.
# Install-NeologikEnvironment.ps1 assigns the same two roles.
# Reader: the deployment reads usage and quota. Azure holds usage and quota for the
# subscription and the region.
# Cost Management Contributor: the deployment maintains the daily cost report. The
# role manages cost configuration only. The role gives no control of a resource.
$script:RequiredSubRoles = @(
    'Reader',
    'Cost Management Contributor'
)

# The roles on the subscription that step 4 removes.
# Step 4 removes the roles only when the deployment identity holds the roles above.
$script:LegacySubRoles = @('Contributor', 'User Access Administrator')

# The deployment identity is not a member of the Admin User Group. The deployment
# identity reaches SQL as the Microsoft Entra administrator of the SQL server. The
# deployment by Neologik sets that administrator. The first run removes an existing
# membership only when each SQL server in the resource group names the deployment
# identity as the administrator.
# Before that, the membership is the only access of the deployment identity to SQL.
# The script finds the group by name in the SecurityGroups of the configuration file.
$script:AdminGroupNamePattern = 'Neologik Admin User Group*'

# The declared set. The deployment identity holds the roles above and one further
# role. The deployment by Neologik grants the further role on the Content
# Understanding account, at a scope below the resource group. The first run removes
# every other Azure role that the deployment identity holds in the subscription. The
# first run also removes every directory role and every group membership.
$script:DeclaredResourceRoles = @('Cognitive Services Content Understanding Contributor')

$script:GraphSpAppId = '00000003-0000-0000-c000-000000000000'
# The start of the name of the SharePoint application. The SharePoint application
# holds the permission Sites.Selected. The script checks the consent in the first
# run. The script also checks the consent in the later run, when the agent grants
# file records SharePoint ingestion. The script grants Sites.Selected when an
# earlier SharePoint application of Neologik holds a SharePoint permission.
$script:SharePointAppDisplayNamePrefix = 'Neologik SharePoint Access - '
$script:AppAdminRoleTemplateId = '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3'
$script:GraphV1 = 'https://graph.microsoft.com/v1.0'
$script:GraphBeta = 'https://graph.microsoft.com/beta'
$script:OdataHeaders = @{ 'OData-Version' = '4.0' }
$script:GuidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
# A summary result that matches this pattern needs attention and sets the exit code
# to 1. The pattern includes each 'WOULD' change that a run with -Verify reports.
$script:AttentionPattern = 'MISSING|SKIPPED|NOT FOUND|PENDING|FAILED|UNKNOWN|WOULD'

# Sign-in. The script runs the sign-in itself. The first method is a sign-in in the
# browser of this computer. The second method is a device code. The script prints what
# the script waits for, waits for a limited time, and tries the next method when a
# method fails. Many organisations block the device code with a Conditional Access
# policy, so the device code is not the first method. The sign-in uses the public
# client ids of two Microsoft applications: Microsoft Graph Command Line Tools for
# Microsoft Graph, and Microsoft Azure PowerShell for Azure Resource Manager. The
# sign-in uses no Neologik application.
$script:GraphPublicClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
$script:AzurePublicClientId = '1950a258-227b-4e31-a9cf-717495945fc2'
$script:LoginEndpoint = 'https://login.microsoftonline.com'
# Azure requires multi-factor authentication for each write. The script requests the
# authentication context claim 'p1' with each sign-in to Azure.
$script:AzureMfaClaims = '{"access_token":{"acrs":{"essential":true,"values":["p1"]}}}'
# The longest time that the script waits for the browser sign-in, in seconds.
$script:BrowserMaximumWaitSeconds = 300
# The longest time that the script waits for one device code, in seconds.
$script:DeviceCodeMaximumWaitSeconds = 900
# How often the script reports that the script still waits for a sign-in, in seconds.
$script:SignInReportEverySeconds = 30
# The role template of Global Administrator. The script checks the signed-in account
# against the role template.
$script:GlobalAdministratorTemplateId = '62e90394-69f5-4237-9190-012177145e10'
# The roles on the subscription that allow the signed-in account to write a role
# assignment.
$script:SubscriptionAdministratorRoles = @('Owner', 'User Access Administrator')
# Each address that the script uses. Each address must answer before the script
# changes anything.
$script:PreflightEndpoints = @(
    @{ Name = 'Microsoft Entra sign-in'; Uri = 'https://login.microsoftonline.com/' },
    @{ Name = 'Microsoft Graph'; Uri = 'https://graph.microsoft.com/' },
    @{ Name = 'Azure Resource Manager'; Uri = 'https://management.azure.com/' },
    @{ Name = 'PowerShell Gallery, for the PowerShell modules'; Uri = 'https://www.powershellgallery.com/' }
)
# The script requires Microsoft Graph PowerShell 2.0 or later and
# ExchangeOnlineManagement 3.0 or later.
$script:GraphModuleMinimumVersion = [version]'2.0.0'
$script:ExchangeModuleMinimumVersion = [version]'3.0.0'
$script:GraphModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Applications',
    'Microsoft.Graph.Groups',
    'Microsoft.Graph.Identity.DirectoryManagement'
)
$script:Summary = @()
# The state of the run: the inputs and the principals that the script found.
$script:State = @{}
# The version of the onboarding kit. The script records the version on the resource
# group, in the tag NeologikOnboardingKit, when the permission reduction is complete.
$script:KitVersion = 'v5.0.10'

# ----- Console and summary -----------------------------------------------------

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    $stamp = Get-Date -Format 'HH:mm:ss'
    $colour = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        default   { 'Gray' }
    }
    Write-Host "[$stamp] $Message" -ForegroundColor $colour
}

function Write-ActionRequired {
    # Prints one instruction for the person who runs the script: what to do and why.
    param([string]$Message)
    Write-Host ''
    Write-Host 'ACTION REQUIRED' -ForegroundColor Yellow
    foreach ($line in ($Message -split "`n")) {
        Write-Host "  $($line.TrimEnd())" -ForegroundColor Yellow
    }
    Write-Host ''
}

function Add-Summary {
    param([string]$Item, [string]$Result)
    $script:Summary += [pscustomobject]@{ Item = $Item; Result = $Result }
}

function Get-NeologikProperty {
    <#
    Reads a property from a JSON object or from a Microsoft Graph response. A JSON
    object is a PSCustomObject. A Microsoft Graph response is a hashtable. Strict
    mode throws on a missing property or key. A file from Neologik or a Microsoft
    Graph response can omit a property.
    #>
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function Test-NeologikProperty {
    # Returns whether an object holds a property or key. An empty array is still a
    # value. Get-NeologikProperty cannot tell an empty array from an absent property.
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) { return [bool]$Object.Contains($Name) }
    return ($null -ne $Object.PSObject.Properties[$Name])
}

function Test-NeologikGuid {
    param([string]$Value)
    return [bool]($Value -match $script:GuidPattern)
}

function Get-NeologikErrorText {
    <#
    Returns a reason on one line for the summary and the log. The reason is the
    exception message. The reason includes the error body of Microsoft Graph when
    the SDK attached the error body. The reason never holds a token or a stack
    trace.
    #>
    param($ErrorRecord)
    if ($null -eq $ErrorRecord) { return 'unknown error' }
    $text = ''
    $exception = Get-NeologikProperty $ErrorRecord 'Exception'
    if ($exception) { $text = [string](Get-NeologikProperty $exception 'Message' '') }
    elseif ($ErrorRecord -is [string]) { $text = $ErrorRecord }
    else { $text = [string]$ErrorRecord }
    $details = Get-NeologikProperty $ErrorRecord 'ErrorDetails'
    $detailText = if ($details) { [string](Get-NeologikProperty $details 'Message' '') } else { '' }
    if ($detailText -and $text -notlike "*$detailText*") { $text = "$text $detailText" }
    $text = ($text -split "`r?`n" | Where-Object { $_.Trim() }) -join ' '
    $text = $text -replace '(?i)bearer\s+[A-Za-z0-9\-_\.=]+', 'bearer <token>'
    if ($text.Length -gt 300) { $text = $text.Substring(0, 300) + '...' }
    if (-not $text) { $text = 'unknown error' }
    return $text
}

function Get-NeologikHttpStatus {
    # Returns the HTTP status of a failed Microsoft Graph call or SDK call. Returns 0
    # when the status is not known.
    param($ErrorRecord)
    $exception = Get-NeologikProperty $ErrorRecord 'Exception'
    while ($exception) {
        $status = Get-NeologikProperty $exception 'StatusCode'
        if ($null -ne $status -and "$status" -match '^\d+$') { return [int]$status }
        if ($null -ne $status) {
            try { return [int][System.Net.HttpStatusCode]$status } catch { Write-Verbose "The script ignores the error. $($_.Exception.Message)" }
        }
        $response = Get-NeologikProperty $exception 'Response'
        if ($response) {
            $status = Get-NeologikProperty $response 'StatusCode'
            if ($null -ne $status) { try { return [int]$status } catch { Write-Verbose "The script ignores the error. $($_.Exception.Message)" } }
        }
        $exception = Get-NeologikProperty $exception 'InnerException'
    }
    $text = Get-NeologikErrorText $ErrorRecord
    if ($text -match '(?i)Authorization_RequestDenied|Insufficient privileges|Forbidden') { return 403 }
    if ($text -match '(?i)Request_ResourceNotFound|does not exist|not found') { return 404 }
    if ($text -match '(?i)TooManyRequests|throttl') { return 429 }
    return 0
}

function Test-NeologikPrivilegeError {
    param($ErrorRecord)
    return ((Get-NeologikHttpStatus $ErrorRecord) -eq 403)
}

function Get-NeologikScopeSet {
    param([string]$Value)
    @(($Value -split '\s+') | Where-Object { $_ } | Sort-Object -Unique) -join ' '
}

# ----- Runs with -Verify --------------------------------------------------------
# With -Verify each step reports each change that a run would make, and the script
# writes nothing. Every write passes through one of two functions.
# Invoke-NeologikGraph sends each Microsoft Graph request. Invoke-NeologikWrite calls
# each SDK command that writes. Both functions refuse a write in a run with -Verify.
# Each step records a pending change as a 'WOULD' item in the summary. A 'WOULD' item
# needs attention and sets the exit code to 1.

function Test-NeologikVerifyOnly {
    return [bool](Get-NeologikProperty $script:State 'Verify' $false)
}

function Add-NeologikPendingChange {
    # Records one change that a run without -Verify would make.
    param([string]$Item, [string]$Change)
    Write-Log "  ${Item}: WOULD $Change. A run with -Verify writes nothing" -Level Warning
    Add-Summary $Item "WOULD $Change"
}

function Assert-NeologikWriteAllowed {
    param([string]$Description)
    if (Test-NeologikVerifyOnly) {
        throw [System.InvalidOperationException]::new("The run with -Verify refused the write '$Description'. Report this message to Neologik")
    }
}

function Invoke-NeologikWrite {
    <#
    Calls one SDK command that writes to Microsoft Graph, to Azure or to Exchange
    Online. The function refuses the call in a run with -Verify. Otherwise the
    function calls the command with -ErrorAction Stop and returns the output.
    #>
    param([Parameter(Mandatory)][string]$Command, [hashtable]$Parameters = @{})
    Assert-NeologikWriteAllowed -Description $Command
    return (& $Command @Parameters -ErrorAction Stop)
}

# ----- Modules, sign-in and processes -------------------------------------------
# Each function wraps one command that uses the workstation or the network. The
# functions hold no logic.

function Get-NeologikAvailableModuleVersion {
    param([string]$Name)
    return @(Get-Module -ListAvailable -Name $Name | ForEach-Object { [version]$_.Version })
}

function Get-NeologikLoadedModuleVersion {
    param([string]$Name)
    $loaded = @(Get-Module -Name $Name) | Select-Object -First 1
    if ($loaded) { return [version]$loaded.Version }
    return $null
}

function Install-NeologikModule {
    param([string]$Name, [version]$MinimumVersion)
    Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber -MinimumVersion $MinimumVersion -ErrorAction Stop
}

function Import-NeologikModule {
    param([string]$Name, [version]$RequiredVersion)
    if ($RequiredVersion) {
        Import-Module -Name $Name -RequiredVersion $RequiredVersion -ErrorAction Stop
    }
    else {
        Import-Module -Name $Name -ErrorAction Stop
    }
}

function Test-NeologikCommand {
    param([string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Invoke-NeologikAzureCli {
    <#
    Runs az with the given arguments. Returns the exit code and the lines of the
    standard output. PowerShell 7.4 can turn an exit code other than zero, or text
    on the error stream, into a terminating error. The two local preferences
    prevent that.
    #>
    param([string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $PSNativeCommandUseErrorActionPreference = $false
    $raw = @(& az @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $lines = @($raw | Where-Object { $_ -is [string] })
    return @{ ExitCode = $exitCode; Output = $lines }
}

function Invoke-NeologikTokenRequest {
    <#
    Sends one POST request to the Microsoft identity platform, to the device code
    endpoint or to the token endpoint. Returns the status code and the parsed body.
    The function never throws on an HTTP error, so the device code loop can read
    the answer authorization_pending.
    #>
    param([string]$Uri, [hashtable]$Body)
    $statusCode = 0
    $response = Invoke-RestMethod -Method POST -Uri $Uri -Body $Body -ContentType 'application/x-www-form-urlencoded' `
        -SkipHttpErrorCheck -StatusCodeVariable 'statusCode' -TimeoutSec 30 -ErrorAction Stop
    return @{ StatusCode = [int]$statusCode; Body = $response }
}

function Test-NeologikEndpoint {
    # Returns true when the workstation receives any HTTP answer from the address. An
    # answer with a 4xx status is still an answer. Returns false on a failure of DNS, of
    # the proxy or of the firewall, and when no answer arrives within 15 seconds.
    param([string]$Uri)
    try {
        $null = Invoke-WebRequest -Method Head -Uri $Uri -TimeoutSec 15 -SkipHttpErrorCheck -ErrorAction Stop
        return $true
    }
    catch { return $false }
}

function Get-NeologikTokenError {
    # Returns the reason that the Microsoft identity platform gives, on one line.
    param($Body)
    $description = [string](Get-NeologikProperty $Body 'error_description' '')
    $code = [string](Get-NeologikProperty $Body 'error' '')
    if ($description) { return (($description -split "`r?`n")[0]).Trim() }
    if ($code) { return $code }
    return 'The Microsoft identity platform gave no answer'
}

function Test-NeologikConditionalAccessBlock {
    # Returns true when the Microsoft identity platform refused a sign-in because of a
    # Conditional Access policy of the tenant. The error codes 53000 to 53099 name a
    # Conditional Access refusal. 53003 is the refusal that a block policy gives.
    param($Body)
    foreach ($code in @(Get-NeologikProperty $Body 'error_codes' @())) {
        if ([string]$code -match '^530\d\d$') { return $true }
    }
    $description = [string](Get-NeologikProperty $Body 'error_description' '')
    return ($description -match 'AADSTS530\d\d')
}

function Write-NeologikSignInFailure {
    # Logs why a sign-in did not complete, on one line. A refusal by a Conditional
    # Access policy gets its own line, so the administrator knows that a policy of the
    # tenant blocks the method. The caller then tries the next method.
    param([string]$Label, [string]$Method, $Body)
    if (Test-NeologikConditionalAccessBlock $Body) {
        Write-Log "A Conditional Access policy of the tenant refused the sign-in to $Label with $Method. $(Get-NeologikTokenError $Body)" -Level Warning
    }
    else {
        Write-Log "The sign-in to $Label did not complete. $(Get-NeologikTokenError $Body)" -Level Warning
    }
}

function Get-NeologikDeviceCodeToken {
    <#
    Runs the device code sign-in. The function prints the address and the code. The
    function waits while the code is valid, for DeviceCodeMaximumWaitSeconds at
    most. The function reports every 30 seconds that the script still waits.
    Returns the tokens. When the sign-in does not complete, the function logs the
    reason and returns $null. The caller then tries the next method.
    #>
    param([string]$ClientId, [string[]]$Scopes, [string]$Label, [string]$Claims)
    $state = $script:State
    $base = "$($script:LoginEndpoint)/$($state.TenantId)/oauth2/v2.0"
    $request = @{ client_id = $ClientId; scope = ($Scopes -join ' ') }
    if ($Claims) { $request['claims'] = $Claims }
    try {
        $start = Invoke-NeologikTokenRequest -Uri "$base/devicecode" -Body $request
        if ($start.StatusCode -ne 200 -and $Claims) {
            # Some tenants refuse the claims parameter on the device code request. The script
            # then sends the request again without the claims parameter. A later write can then
            # return a claims challenge.
            $request.Remove('claims')
            $start = Invoke-NeologikTokenRequest -Uri "$base/devicecode" -Body $request
        }
    }
    catch {
        Write-Log "The sign-in to $Label did not start. $(Get-NeologikErrorText $_)" -Level Warning
        return $null
    }
    if ($start.StatusCode -ne 200) {
        Write-Log "The sign-in to $Label did not start. $(Get-NeologikTokenError $start.Body)" -Level Warning
        return $null
    }
    $deviceCode = [string](Get-NeologikProperty $start.Body 'device_code' '')
    $userCode = [string](Get-NeologikProperty $start.Body 'user_code' '')
    $verificationUri = [string](Get-NeologikProperty $start.Body 'verification_uri' 'https://microsoft.com/devicelogin')
    $lifetime = [int](Get-NeologikProperty $start.Body 'expires_in' 900)
    $interval = [int](Get-NeologikProperty $start.Body 'interval' 5)
    if (-not $deviceCode -or -not $userCode) {
        Write-Log "The sign-in to $Label did not start. The Microsoft identity platform returned no device code" -Level Warning
        return $null
    }
    if ($lifetime -le 0) { $lifetime = 900 }
    if ($interval -le 0) { $interval = 5 }
    $lifetime = [Math]::Min($lifetime, $script:DeviceCodeMaximumWaitSeconds)
    $minutes = [int][Math]::Ceiling($lifetime / 60)
    Write-Host ''
    Write-Host "  Sign-in to $Label" -ForegroundColor Cyan
    Write-Host "  1. Open $verificationUri in a browser on any device."
    Write-Host "  2. Enter the code: $userCode" -ForegroundColor Yellow
    Write-Host '  3. Sign in as a Global Administrator. Approve the permissions when the browser lists permissions.'
    Write-Host "  The code is valid for $minutes minutes. The script waits for the sign-in and reports every $($script:SignInReportEverySeconds) seconds."
    Write-Host ''
    # The loop asks at once and then after each interval, until the lifetime of the code
    # ends. The count of intervals limits the loop. The loop reads no clock.
    $elapsed = 0
    $sinceReport = 0
    while ($true) {
        try {
            $poll = Invoke-NeologikTokenRequest -Uri "$base/token" -Body @{
                grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
                client_id   = $ClientId
                device_code = $deviceCode
            }
        }
        catch {
            Write-Log "The sign-in to $Label did not complete. $(Get-NeologikErrorText $_)" -Level Warning
            return $null
        }
        if ($poll.StatusCode -eq 200) {
            $accessToken = [string](Get-NeologikProperty $poll.Body 'access_token' '')
            if ($accessToken) {
                $account = Get-NeologikTokenAccountId -Token $accessToken
                Write-Log "The sign-in to $Label completed$(if ($account) { ", account $account" })" -Level Success
                return @{
                    AccessToken  = $accessToken
                    RefreshToken = [string](Get-NeologikProperty $poll.Body 'refresh_token' '')
                    Account      = $account
                }
            }
        }
        $reason = [string](Get-NeologikProperty $poll.Body 'error' '')
        if ($reason -eq 'authorization_pending') { }
        elseif ($reason -eq 'slow_down') { $interval += 5 }
        else {
            Write-NeologikSignInFailure -Label $Label -Method 'a device code' -Body $poll.Body
            return $null
        }
        if ($elapsed -ge $lifetime) { break }
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        $sinceReport += $interval
        if ($sinceReport -ge $script:SignInReportEverySeconds) {
            $left = [int][Math]::Ceiling(($lifetime - $elapsed) / 60)
            Write-Host "  The script still waits for the sign-in to $Label. Code $userCode. About $left minute(s) remain."
            $sinceReport = 0
        }
    }
    Write-Log "The sign-in to $Label did not complete. The code expired after $minutes minutes" -Level Warning
    return $null
}

function ConvertTo-NeologikBase64Url {
    # Encodes bytes as base64url without padding, as the proof key of the browser
    # sign-in requires.
    param([byte[]]$Bytes)
    return [System.Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-NeologikRandomValue {
    # Returns a random value of 32 bytes, encoded as base64url.
    $bytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    return (ConvertTo-NeologikBase64Url $bytes)
}

function ConvertFrom-NeologikQueryString {
    # Returns the parameters of a query string as a hashtable.
    param([string]$Query)
    $result = @{}
    foreach ($pair in ($Query.TrimStart('?') -split '&')) {
        if (-not $pair) { continue }
        $name, $value = $pair -split '=', 2
        $name = [System.Uri]::UnescapeDataString($name.Replace('+', ' '))
        $value = if ($null -ne $value) { [System.Uri]::UnescapeDataString($value.Replace('+', ' ')) } else { '' }
        $result[$name] = $value
    }
    return $result
}

function Start-NeologikLoopbackListener {
    <#
    Starts a listener on the loopback addresses of this computer, on a free port. The
    browser returns the result of the sign-in to the listener. Only this computer can
    reach a loopback address. The listener answers on 127.0.0.1 and, when this
    computer has IPv6, on ::1. A browser can resolve localhost to either address.
    Returns the port, the listeners and a Stop method.
    #>
    $ipv4 = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $ipv4.Start()
    $port = $ipv4.LocalEndpoint.Port
    $listeners = @($ipv4)
    if ([System.Net.Sockets.Socket]::OSSupportsIPv6) {
        try {
            $ipv6 = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::IPv6Loopback, $port)
            $ipv6.Start()
            $listeners += $ipv6
        }
        catch { Write-Verbose "The listener on ::1 did not start. $($_.Exception.Message)" }
    }
    $loopback = [pscustomobject]@{ Port = $port; Listeners = $listeners }
    $loopback | Add-Member -MemberType ScriptMethod -Name Stop -Value { foreach ($item in $this.Listeners) { $item.Stop() } }
    return $loopback
}

function Test-NeologikDesktop {
    # Returns true when this computer has a desktop on which a browser can open.
    return -not (($IsLinux -and -not $env:DISPLAY -and -not $env:WAYLAND_DISPLAY) -or -not [Environment]::UserInteractive)
}

function Open-NeologikBrowser {
    # Opens the address in the default browser of this computer. Returns $false when
    # this computer has no desktop or no browser opens.
    param([string]$Uri)
    if (-not (Test-NeologikDesktop)) {
        Write-Log '  This computer has no desktop, so the script cannot open a browser' -Level Info
        return $false
    }
    try {
        Start-Process -FilePath $Uri -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-Log "  The browser did not open. $(Get-NeologikErrorText $_)" -Level Info
        return $false
    }
}

function Read-NeologikLoopbackRequest {
    <#
    Reads one HTTP request from the browser and answers the request. Returns the
    parameters of the query string. The answer tells the administrator to return to
    the PowerShell window. A request with no result of the sign-in, for example a
    request for an icon, gets the answer 404 and an empty result.
    #>
    param($Client)
    $stream = $Client.GetStream()
    $stream.ReadTimeout = 5000
    $buffer = [byte[]]::new(16384)
    $received = [System.Text.StringBuilder]::new()
    while ($received.Length -lt 65536) {
        $count = $stream.Read($buffer, 0, $buffer.Length)
        if ($count -le 0) { break }
        [void]$received.Append([System.Text.Encoding]::ASCII.GetString($buffer, 0, $count))
        if ($received.ToString().Contains("`r`n`r`n")) { break }
    }
    $requestLine = ($received.ToString() -split "`r`n")[0]
    $query = @{}
    if ($requestLine -match '^GET\s+(\S+)\s+HTTP/') {
        $target = $Matches[1]
        $index = $target.IndexOf('?')
        if ($index -ge 0) { $query = ConvertFrom-NeologikQueryString $target.Substring($index + 1) }
    }
    if ($query.ContainsKey('code')) {
        $status = '200 OK'
        $text = 'The sign-in is complete. Return to the PowerShell window.'
    }
    elseif ($query.ContainsKey('error')) {
        $status = '200 OK'
        $text = 'The sign-in did not complete. Return to the PowerShell window.'
    }
    else {
        $status = '404 Not Found'
        $text = 'Not found.'
    }
    $html = "<!DOCTYPE html><html><head><meta charset=`"utf-8`"><title>Neologik sign-in</title></head><body><p>$text</p></body></html>"
    $body = [System.Text.Encoding]::UTF8.GetBytes($html)
    $header = "HTTP/1.1 $status`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
    $stream.Write($headerBytes, 0, $headerBytes.Length)
    $stream.Write($body, 0, $body.Length)
    $stream.Flush()
    return $query
}

function Wait-NeologikLoopbackRequest {
    <#
    Waits for the browser to return the result of the sign-in to the listener. The
    function waits for TimeoutSeconds at most. The function reports every 30 seconds
    that the script still waits. Returns the parameters of the query string, or $null
    when the time ends first.
    #>
    param($Listener, [int]$TimeoutSeconds, [string]$Label)
    $elapsed = 0
    $sinceReport = 0
    $sockets = @($Listener.Listeners)
    $accepts = [System.Threading.Tasks.Task[]]@($sockets | ForEach-Object { $_.AcceptTcpClientAsync() })
    while ($true) {
        $ready = [System.Threading.Tasks.Task]::WaitAny($accepts, 1000)
        if ($ready -ge 0) {
            $client = $accepts[$ready].Result
            $query = @{}
            try { $query = Read-NeologikLoopbackRequest -Client $client }
            catch { $query = @{} }
            finally { $client.Dispose() }
            if ($query.ContainsKey('code') -or $query.ContainsKey('error')) { return $query }
            $accepts[$ready] = $sockets[$ready].AcceptTcpClientAsync()
            continue
        }
        $elapsed += 1
        $sinceReport += 1
        if ($elapsed -ge $TimeoutSeconds) { return $null }
        if ($sinceReport -ge $script:SignInReportEverySeconds) {
            $left = [int][Math]::Ceiling(($TimeoutSeconds - $elapsed) / 60)
            Write-Host "  The script still waits for the sign-in to $Label in the browser. About $left minute(s) remain."
            $sinceReport = 0
        }
    }
}

function Get-NeologikBrowserToken {
    <#
    Runs the sign-in in the browser of this computer. The sign-in uses an
    authorisation code with a proof key, and a listener on the loopback address. The
    function prints what the function waits for. The function waits for
    BrowserMaximumWaitSeconds at most. Returns the tokens. When the sign-in does not
    complete, the function logs the reason and returns $null. The caller then tries
    the next method.
    #>
    param([string]$ClientId, [string[]]$Scopes, [string]$Label, [string]$Claims, [string]$LoginHint)
    $state = $script:State
    $base = "$($script:LoginEndpoint)/$($state.TenantId)/oauth2/v2.0"
    try { $listener = Start-NeologikLoopbackListener }
    catch {
        Write-Log "The sign-in to $Label in the browser did not start. The script could not open a port on this computer. $(Get-NeologikErrorText $_)" -Level Warning
        return $null
    }
    try {
        $redirectUri = "http://localhost:$($listener.Port)/"
        $verifier = New-NeologikRandomValue
        $challenge = ConvertTo-NeologikBase64Url ([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::ASCII.GetBytes($verifier)))
        $expectedState = New-NeologikRandomValue
        $parameters = [ordered]@{
            client_id             = $ClientId
            response_type         = 'code'
            redirect_uri          = $redirectUri
            response_mode         = 'query'
            scope                 = ($Scopes -join ' ')
            state                 = $expectedState
            code_challenge        = $challenge
            code_challenge_method = 'S256'
        }
        if ($LoginHint) { $parameters['login_hint'] = $LoginHint } else { $parameters['prompt'] = 'select_account' }
        if ($Claims) { $parameters['claims'] = $Claims }
        $query = ($parameters.Keys | ForEach-Object { "$_=$([System.Uri]::EscapeDataString([string]$parameters[$_]))" }) -join '&'
        $authorizeUri = "$base/authorize?$query"
        $minutes = [int][Math]::Ceiling($script:BrowserMaximumWaitSeconds / 60)
        Write-Host ''
        Write-Host "  Sign-in to $Label" -ForegroundColor Cyan
        Write-Host '  The script opens the sign-in page in the browser of this computer.'
        Write-Host '  Sign in as a Global Administrator. Approve the permissions when the browser lists permissions.'
        Write-Host "  The script waits for $minutes minutes at most and reports every $($script:SignInReportEverySeconds) seconds. The script then tries a device code."
        Write-Host ''
        if (-not (Open-NeologikBrowser -Uri $authorizeUri)) {
            Write-Log "The sign-in to $Label in the browser did not start. The script tries a device code" -Level Warning
            return $null
        }
        $result = Wait-NeologikLoopbackRequest -Listener $listener -TimeoutSeconds $script:BrowserMaximumWaitSeconds -Label $Label
    }
    catch {
        Write-Log "The sign-in to $Label in the browser did not complete. $(Get-NeologikErrorText $_)" -Level Warning
        return $null
    }
    finally { $listener.Stop() }
    if (-not $result) {
        Write-Log "The sign-in to $Label in the browser did not complete within $minutes minutes" -Level Warning
        return $null
    }
    if ([string](Get-NeologikProperty $result 'state' '') -ne $expectedState) {
        Write-Log "The sign-in to $Label in the browser returned an answer that this run did not request. The script ignores the answer" -Level Warning
        return $null
    }
    if ($result.ContainsKey('error')) {
        Write-NeologikSignInFailure -Label $Label -Method 'the browser' -Body $result
        return $null
    }
    $request = @{
        grant_type    = 'authorization_code'
        client_id     = $ClientId
        code          = [string]$result['code']
        redirect_uri  = $redirectUri
        code_verifier = $verifier
        scope         = ($Scopes -join ' ')
    }
    if ($Claims) { $request['claims'] = $Claims }
    try { $answer = Invoke-NeologikTokenRequest -Uri "$base/token" -Body $request }
    catch {
        Write-Log "The sign-in to $Label did not complete. $(Get-NeologikErrorText $_)" -Level Warning
        return $null
    }
    $accessToken = [string](Get-NeologikProperty $answer.Body 'access_token' '')
    if ($answer.StatusCode -ne 200 -or -not $accessToken) {
        Write-NeologikSignInFailure -Label $Label -Method 'the browser' -Body $answer.Body
        return $null
    }
    $account = Get-NeologikTokenAccountId -Token $accessToken
    Write-Log "The sign-in to $Label completed$(if ($account) { ", account $account" })" -Level Success
    return @{
        AccessToken  = $accessToken
        RefreshToken = [string](Get-NeologikProperty $answer.Body 'refresh_token' '')
        Account      = $account
    }
}

function Test-NeologikPreflightEndpoint {
    # Each address that the run uses must answer before the script changes anything.
    # Returns $true. Returns $false after the function names each address that did not
    # answer.
    $unreachable = @()
    foreach ($endpoint in $script:PreflightEndpoints) {
        if (Test-NeologikEndpoint -Uri $endpoint.Uri) {
            Write-Log "  $($endpoint.Name): reached" -Level Success
        }
        else {
            Write-Log "  $($endpoint.Name): NOT reached. Address $($endpoint.Uri)" -Level Error
            $unreachable += "$($endpoint.Name): $($endpoint.Uri)"
        }
    }
    if ($unreachable.Count -gt 0) {
        Write-ActionRequired "This workstation cannot reach:`n  $($unreachable -join "`n  ")`nAllow each address through the proxy or the firewall, or use a workstation that can reach each address.`nThen run the script again. The script changed nothing."
        return $false
    }
    return $true
}

function Invoke-NeologikGraphRaw {
    <#
    Sends one Microsoft Graph request through the SDK. The function returns an HTTP
    error and does not throw. Returns the status code, the response headers and the
    body.
    #>
    param([string]$Method, [string]$Uri, $Body, [hashtable]$Headers, [string]$ContentType)
    $statusCode = $null
    $responseHeaders = $null
    $request = @{
        Method                  = $Method
        Uri                     = $Uri
        SkipHttpErrorCheck      = $true
        StatusCodeVariable      = 'statusCode'
        ResponseHeadersVariable = 'responseHeaders'
    }
    if ($null -ne $Body) { $request['Body'] = $Body }
    if ($Headers -and $Headers.Count -gt 0) { $request['Headers'] = $Headers }
    if ($ContentType) { $request['ContentType'] = $ContentType }
    $response = Invoke-MgGraphRequest @request
    return @{ StatusCode = [int]$statusCode; Headers = $responseHeaders; Body = $response }
}

function Get-NeologikSummaryDirectory {
    # Returns the folders for the summary file, in order of preference.
    $candidates = @()
    if ($PSCommandPath) { $candidates += (Split-Path -Parent $PSCommandPath) }
    $candidates += (Get-Location).Path
    $candidates += [System.IO.Path]::GetTempPath()
    return @($candidates | Where-Object { $_ } | Select-Object -Unique)
}

# ----- Microsoft Graph requests -------------------------------------------------

function Get-NeologikRetryDelay {
    param($Headers, [int]$Attempt)
    $delay = [math]::Min(60, [math]::Pow(2, $Attempt))
    $retryAfter = $null
    if ($Headers -is [System.Collections.IDictionary]) {
        foreach ($key in @($Headers.Keys)) {
            if ("$key" -eq 'Retry-After') { $retryAfter = $Headers[$key]; break }
        }
    }
    if ($null -ne $retryAfter) {
        $value = [string](@($retryAfter) | Select-Object -First 1)
        if ($value -match '^\d+$') { $delay = [math]::Min(60, [math]::Max(1, [int]$value)) }
    }
    return [int]$delay
}

function Get-NeologikGraphErrorMessage {
    param([int]$StatusCode, [string]$Method, [string]$Uri, $Body)
    $path = $Uri
    try { $path = ([uri]$Uri).AbsolutePath } catch { Write-Verbose "The script ignores the error. $($_.Exception.Message)" }
    $detail = ''
    $graphError = Get-NeologikProperty $Body 'error'
    if ($graphError) {
        $code = [string](Get-NeologikProperty $graphError 'code' '')
        $message = [string](Get-NeologikProperty $graphError 'message' '')
        $detail = (@($code, $message) | Where-Object { $_ }) -join ': '
    }
    $text = "Microsoft Graph $Method $path returned HTTP $StatusCode"
    if ($detail) { $text = "$text. $detail" }
    return $text
}

function Invoke-NeologikGraph {
    <#
    Sends one Microsoft Graph request and tries again after a temporary error. The
    temporary errors are HTTP 429, 502, 503 and 504. The function waits for the time
    in the Retry-After header. With -RetryNotFound the function also tries again
    after HTTP 404. A caller uses -RetryNotFound directly after a create, because a
    new object takes time to replicate. The function throws every other failure as
    an HttpRequestException with the status code and the error text of Microsoft
    Graph. In a run with -Verify the function refuses every request other than GET.
    #>
    param(
        [string]$Method = 'GET',
        [Parameter(Mandatory)][string]$Uri,
        $Body,
        [hashtable]$Headers,
        [string]$ContentType = 'application/json',
        [switch]$RetryNotFound,
        [int]$MaxAttempts = 5
    )
    if ($Method -ne 'GET') { Assert-NeologikWriteAllowed -Description "$Method $Uri" }
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $result = Invoke-NeologikGraphRaw -Method $Method -Uri $Uri -Body $Body -Headers $Headers -ContentType $ContentType
        $status = [int]$result.StatusCode
        if ($status -ge 200 -and $status -lt 300) { return $result.Body }
        $transient = ($status -in @(429, 502, 503, 504)) -or ($RetryNotFound -and $status -eq 404)
        if ($transient -and $attempt -lt $MaxAttempts) {
            $delay = Get-NeologikRetryDelay -Headers $result.Headers -Attempt $attempt
            Write-Log "  Microsoft Graph returned HTTP $status. The script tries again in $delay seconds. Attempt $attempt of $MaxAttempts" -Level Warning
            Start-Sleep -Seconds $delay
            continue
        }
        $message = Get-NeologikGraphErrorMessage -StatusCode $status -Method $Method -Uri $Uri -Body $result.Body
        if ([enum]::IsDefined([System.Net.HttpStatusCode], $status)) {
            throw [System.Net.Http.HttpRequestException]::new($message, $null, [System.Net.HttpStatusCode]$status)
        }
        throw [System.Net.Http.HttpRequestException]::new($message)
    }
}

function Get-NeologikGraphCollection {
    # Reads a collection with GET. Follows @odata.nextLink to the last page.
    param([Parameter(Mandatory)][string]$Uri, [switch]$RetryNotFound, [int]$MaxPages = 200)
    $items = @()
    $next = $Uri
    $pages = 0
    while ($next -and $pages -lt $MaxPages) {
        $page = Invoke-NeologikGraph -Method GET -Uri $next -RetryNotFound:$RetryNotFound
        $items += @(Get-NeologikProperty $page 'value' @())
        $next = [string](Get-NeologikProperty $page '@odata.nextLink' '')
        $pages++
    }
    # The function returns the items one by one. The caller collects the items with @().
    # An array wrapped with a comma would arrive nested inside that @().
    return $items
}

function Get-NeologikGraphAppRole {
    param([string]$RoleName)
    return @($script:State.GraphSp.AppRoles | Where-Object { $_.Value -eq $RoleName }) | Select-Object -First 1
}

# ----- Inputs -------------------------------------------------------------------

function Read-NeologikJsonFile {
    # Reads and parses a JSON input file. Throws an input error that names the file
    # when the file is absent, empty or not valid JSON.
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw [System.ArgumentException]::new("The $Label does not exist: $Path")
    }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw [System.ArgumentException]::new("The $Label is empty: $Path")
    }
    try {
        $parsed = ConvertFrom-Json -InputObject $raw -NoEnumerate -ErrorAction Stop
        return , $parsed
    }
    catch {
        throw [System.ArgumentException]::new("The $Label is not valid JSON: $Path. $(Get-NeologikErrorText $_)")
    }
}

function Resolve-NeologikInput {
    <#
    Reads each input from the configuration file and from the parameters. Checks
    each id and each input file. Fills $script:State. Reports each problem as an
    ArgumentException that states the exact correction.
    #>
    param([hashtable]$Parameters)
    $state = $script:State
    foreach ($name in @('ConfigurationFile', 'TenantId', 'DeploySpClientId', 'SolutionShortName', 'SolutionName', 'SignInAppClientId', 'SharePointAppClientId',
            'NceUserGroupId', 'AdminGroupId', 'GuestUsersFile', 'SubscriptionId', 'ResourceGroupName', 'BlueprintKey', 'AgentGrantsFile', 'MailboxGrantsFile')) {
        $state[$name] = ([string](Get-NeologikProperty $Parameters $name '')).Trim()
    }
    # Agent registrations: one client id for each agent registration. One element can
    # hold several client ids, separated by commas.
    $state.BotAppClientIds = @(@(Get-NeologikProperty $Parameters 'BotAppClientIds' @()) | ForEach-Object { "$_" -split ',' } |
        ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    if (-not $state.BlueprintKey) { $state.BlueprintKey = 'default' }
    $state.RemoveLegacyGrantAppIds = @(Get-NeologikProperty $Parameters 'RemoveLegacyGrantAppIds' @() | Where-Object { $_ })
    $state.UseAzureCliToken = [bool](Get-NeologikProperty $Parameters 'UseAzureCliToken' $false)
    $state.Verify = [bool](Get-NeologikProperty $Parameters 'Verify' $false)
    # The command selects the run. A grants file of either kind selects the later run.
    # A command without a grants file selects the first run.
    $state.Run = if ($state.AgentGrantsFile -or $state.MailboxGrantsFile) { 'PostWindow' } else { 'PreWindow' }
    $state.Config = $null
    # The name of the agent identity blueprint holds the short name. The parameter comes
    # first, then the configuration file. The script never reads the short name from a
    # display name.
    $state.ShortName = $state.SolutionShortName.Trim()
    $state.ShortNameSource = if ($state.ShortName) { '-SolutionShortName' } else { '' }
    $state.AgentGrants = $null
    $state.MailboxGrants = @()
    $state.AdoptedIdentityAppIds = @()
    # The Neologik support accounts: the file that the command names, else the file
    # beside the script. The first run reads the file. A file that the command names
    # must exist.
    $state.GuestUserEmails = @()
    $state.NceContributorsGroupId = ''
    $state.NceAdminsGroupId = ''
    if ($state.GuestUsersFile) {
        if (-not (Test-Path -LiteralPath $state.GuestUsersFile)) {
            throw [System.ArgumentException]::new("The guest users file is not found: $($state.GuestUsersFile). Check the value of -GuestUsersFile.")
        }
    }
    else {
        $state.GuestUsersFile = Get-NeologikGuestUsersFileDefault
    }
    if ($state.Run -eq 'PreWindow' -and (Test-Path -LiteralPath $state.GuestUsersFile)) {
        $state.GuestUserEmails = @(Read-NeologikGuestUsersFile -Path $state.GuestUsersFile)
    }

    if ($state.ConfigurationFile) {
        $config = Read-NeologikJsonFile -Path $state.ConfigurationFile -Label 'configuration file'
        if ($config -is [System.Array] -or $null -eq $config) {
            throw [System.ArgumentException]::new("The configuration file is not the file that the onboarding script wrote: $($state.ConfigurationFile). The file must hold TenantId and AppRegistration.")
        }
        $state.Config = $config
        if (-not $state.TenantId) { $state.TenantId = [string](Get-NeologikProperty $config 'TenantId' '') }
        if (-not $state.SubscriptionId) { $state.SubscriptionId = [string](Get-NeologikProperty $config 'SubscriptionId' '') }
        if (-not $state.ResourceGroupName) { $state.ResourceGroupName = [string](Get-NeologikProperty $config 'ResourceGroupName' '') }
        if (-not $state.DeploySpClientId) {
            $state.DeploySpClientId = [string](Get-NeologikProperty (Get-NeologikProperty $config 'AppRegistration') 'ClientId' '')
        }
        if (-not $state.SignInAppClientId) {
            $state.SignInAppClientId = [string](Get-NeologikProperty (Get-NeologikProperty $config 'NceAuthApp') 'ClientId' '')
        }
        if (-not $state.NceUserGroupId) {
            $nceGroup = @(@(Get-NeologikProperty $config 'SecurityGroups' @()) | Where-Object {
                    [string](Get-NeologikProperty $_ 'Name' '') -match 'NCE Contributors|NCE User Group|Harness User Group'
                }) | Select-Object -First 1
            if ($nceGroup) { $state.NceUserGroupId = [string](Get-NeologikProperty $nceGroup 'Id' '') }
        }
        if (-not $state.AdminGroupId) {
            $adminGroup = @(@(Get-NeologikProperty $config 'SecurityGroups' @()) | Where-Object {
                    [string](Get-NeologikProperty $_ 'Name' '') -like $script:AdminGroupNamePattern
                }) | Select-Object -First 1
            if ($adminGroup) { $state.AdminGroupId = [string](Get-NeologikProperty $adminGroup 'Id' '') }
        }
        if (-not $state.ShortName) {
            $state.ShortName = ([string](Get-NeologikProperty $config 'SolutionShortName' '')).Trim()
            if ($state.ShortName) { $state.ShortNameSource = 'the configuration file' }
        }
        if (-not $state.SolutionName) { $state.SolutionName = ([string](Get-NeologikProperty $config 'SolutionName' '')).Trim() }
        Write-Log "The script read the configuration file. Organisation: $(Get-NeologikProperty $config 'OrganizationName' ''). Short name: $($state.ShortName)" -Level Info
    }

    foreach ($required in @(
            @{ Name = 'TenantId'; Value = $state.TenantId },
            @{ Name = 'DeploySpClientId'; Value = $state.DeploySpClientId })) {
        if (-not $required.Value) {
            throw [System.ArgumentException]::new("The command does not give $($required.Name). Add -$($required.Name) to the command, or add -ConfigurationFile.")
        }
    }
    $idChecks = @(
        @{ Name = 'TenantId'; Value = $state.TenantId },
        @{ Name = 'DeploySpClientId'; Value = $state.DeploySpClientId },
        @{ Name = 'SignInAppClientId'; Value = $state.SignInAppClientId },
        @{ Name = 'SharePointAppClientId'; Value = $state.SharePointAppClientId },
        @{ Name = 'NceUserGroupId'; Value = $state.NceUserGroupId },
        @{ Name = 'AdminGroupId'; Value = $state.AdminGroupId },
        @{ Name = 'SubscriptionId'; Value = $state.SubscriptionId })
    foreach ($botId in $state.BotAppClientIds) { $idChecks += @{ Name = 'BotAppClientIds'; Value = $botId } }
    foreach ($idCheck in $idChecks) {
        if ($idCheck.Value -and -not (Test-NeologikGuid $idCheck.Value)) {
            throw [System.ArgumentException]::new("$($idCheck.Name) must be a GUID. The value is '$($idCheck.Value)'.")
        }
    }
    if ($state.Run -eq 'PreWindow' -and (-not $state.SubscriptionId -or -not $state.ResourceGroupName)) {
        throw [System.ArgumentException]::new('The first run needs SubscriptionId and ResourceGroupName for the permission reduction. Add -SubscriptionId and -ResourceGroupName to the command, or add -ConfigurationFile.')
    }
    if ($state.Run -eq 'PreWindow' -and -not $state.ShortName) {
        # The name of the agent identity blueprint holds the short name. The script never
        # reads the short name from a display name.
        throw [System.ArgumentException]::new("The first run needs SolutionShortName. SolutionShortName is the short name of the environment, for example abcprd01. The name of the agent identity blueprint holds the short name. Add -SolutionShortName to the command, or add -ConfigurationFile.")
    }
    if ($state.Run -eq 'PreWindow' -and -not $state.SignInAppClientId) {
        # The client id names the Platform Sign-in application. The script never finds the
        # Platform Sign-in application by display name.
        throw [System.ArgumentException]::new("The first run needs SignInAppClientId. SignInAppClientId is the client id of the application registration 'Neologik Platform Sign-in'. Add -SignInAppClientId to the command, or add -ConfigurationFile.")
    }
    if ($state.Run -eq 'PreWindow' -and -not $state.SolutionName) {
        throw [System.ArgumentException]::new("The first run needs SolutionName. SolutionName is the solution name of the environment, for example neo-abcprd-uks-01. The unique name of the Platform Sign-in application is sp-admin-<solution name>. Add -SolutionName to the command, or add -ConfigurationFile.")
    }
    foreach ($legacyAppId in $state.RemoveLegacyGrantAppIds) {
        if (-not (Test-NeologikGuid $legacyAppId)) {
            throw [System.ArgumentException]::new("RemoveLegacyGrantAppIds must hold application ids, each a GUID. One value is '$legacyAppId'.")
        }
    }
    if ($state.RemoveLegacyGrantAppIds.Count -gt 0 -and -not $state.MailboxGrantsFile) {
        throw [System.ArgumentException]::new('RemoveLegacyGrantAppIds belongs to the later run. Add -MailboxGrantsFile to the command. The mailbox grants file lists each identity that an email channel still uses. The script never removes the role assignments of those identities.')
    }

    if ($state.AgentGrantsFile) {
        $grantsFile = Read-NeologikJsonFile -Path $state.AgentGrantsFile -Label 'agent grants file'
        if ($grantsFile -is [System.Array] -or $null -eq $grantsFile -or -not (Test-NeologikProperty $grantsFile 'grants')) {
            throw [System.ArgumentException]::new("The agent grants file is not the file that Neologik exports: $($state.AgentGrantsFile). The file must hold 'grants', 'componentGraphRoles' and 'sharePointIngestion'.")
        }
        $fileTenant = [string](Get-NeologikProperty $grantsFile 'tenantId' '')
        if ($fileTenant -and $fileTenant -ne $state.TenantId) {
            throw [System.ArgumentException]::new("The agent grants file belongs to tenant $fileTenant. This run is for tenant $($state.TenantId). Ask Neologik for the agent grants file of the environment in tenant $($state.TenantId).")
        }
        $entries = @(Get-NeologikProperty $grantsFile 'grants' @())
        foreach ($entry in $entries) {
            $name = [string](Get-NeologikProperty $entry 'name' 'no name')
            if ([string](Get-NeologikProperty $entry 'status' '') -ne 'ready') { continue }
            $clientId = [string](Get-NeologikProperty $entry 'identityClientId' '')
            $userId = [string](Get-NeologikProperty $entry 'agentUserObjectId' '')
            if (-not (Test-NeologikGuid $clientId) -or -not (Test-NeologikGuid $userId)) {
                throw [System.ArgumentException]::new("The agent grants file: identityClientId and agentUserObjectId must be GUIDs. Entry: $name.")
            }
            $scopes = @(@(Get-NeologikProperty $entry 'scopes' @()) | ForEach-Object { [string]$_ } | Where-Object { $_.Trim() })
            if ($scopes.Count -eq 0) {
                throw [System.ArgumentException]::new("The agent grants file: each entry with the status ready needs scopes. Entry: $name.")
            }
        }
        $state.AgentGrants = $grantsFile
        $componentRoles = @(Get-NeologikProperty $grantsFile 'componentGraphRoles' @())
        $sharePoint = [bool](Get-NeologikProperty $grantsFile 'sharePointIngestion' $false)
        Write-Log "The script read the agent grants file. Entries for agents and Apps: $($entries.Count). Application permissions for workload identities: $($componentRoles.Count). SharePoint ingestion: $sharePoint" -Level Info
        foreach ($warning in @(Get-NeologikProperty $grantsFile 'warnings' @() | Where-Object { $_ })) {
            Write-Log "  Warning in the agent grants file: $warning" -Level Warning
        }
    }

    if ($state.MailboxGrantsFile) {
        $mailboxFile = Read-NeologikJsonFile -Path $state.MailboxGrantsFile -Label 'mailbox grants file'
        # The file has one of two forms. The first form is a list of entries. The second
        # form is an object with 'grants' and 'adoptedIdentityAppIds'. 'grants' holds the
        # entries. 'adoptedIdentityAppIds' holds the client id of each identity that an email
        # channel still uses. -RemoveLegacyGrantAppIds never removes those identities.
        $rawEntries = @()
        $adopted = @()
        if ($mailboxFile -is [System.Array]) {
            $rawEntries = @($mailboxFile)
        }
        elseif ($null -ne $mailboxFile -and ((Test-NeologikProperty $mailboxFile 'grants') -or (Test-NeologikProperty $mailboxFile 'adoptedIdentityAppIds'))) {
            $fileTenant = [string](Get-NeologikProperty $mailboxFile 'tenantId' '')
            if ($fileTenant -and $fileTenant -ne $state.TenantId) {
                throw [System.ArgumentException]::new("The mailbox grants file belongs to tenant $fileTenant. This run is for tenant $($state.TenantId). Ask Neologik for the mailbox grants file of the environment in tenant $($state.TenantId).")
            }
            $rawEntries = @(Get-NeologikProperty $mailboxFile 'grants' @())
            $adopted = @(@(Get-NeologikProperty $mailboxFile 'adoptedIdentityAppIds' @()) | ForEach-Object { [string]$_ } | Where-Object { $_.Trim() })
        }
        else {
            throw [System.ArgumentException]::new("The mailbox grants file is not the file that Neologik exports: $($state.MailboxGrantsFile). The file must hold a list of entries, or 'grants' and 'adoptedIdentityAppIds'.")
        }
        foreach ($adoptedAppId in $adopted) {
            if (-not (Test-NeologikGuid $adoptedAppId)) {
                throw [System.ArgumentException]::new("The mailbox grants file: adoptedIdentityAppIds must hold application ids, each a GUID. One value is '$adoptedAppId'.")
            }
        }
        $mailboxEntries = @()
        foreach ($entry in $rawEntries) {
            foreach ($field in @('IdentityAppId', 'IdentityObjectId', 'Mailbox', 'DisplayName')) {
                if (-not [string](Get-NeologikProperty $entry $field '')) {
                    throw [System.ArgumentException]::new("The mailbox grants file: each entry needs $field.")
                }
            }
            $display = [string](Get-NeologikProperty $entry 'DisplayName')
            if (-not (Test-NeologikGuid ([string](Get-NeologikProperty $entry 'IdentityAppId'))) -or
                -not (Test-NeologikGuid ([string](Get-NeologikProperty $entry 'IdentityObjectId')))) {
                throw [System.ArgumentException]::new("The mailbox grants file: IdentityAppId and IdentityObjectId must be GUIDs. Entry: $display.")
            }
            $mailbox = [string](Get-NeologikProperty $entry 'Mailbox')
            if ($mailbox -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
                throw [System.ArgumentException]::new("The mailbox grants file: '$mailbox' is not a mailbox address.")
            }
            if ($display -match "[`"'`r`n]") {
                throw [System.ArgumentException]::new("The mailbox grants file: DisplayName '$display' must not contain a quotation mark.")
            }
            $mailboxEntries += [pscustomobject]@{
                IdentityAppId    = [string](Get-NeologikProperty $entry 'IdentityAppId')
                IdentityObjectId = [string](Get-NeologikProperty $entry 'IdentityObjectId')
                Mailbox          = $mailbox.Trim().ToLowerInvariant()
                DisplayName      = $display
            }
        }
        $state.MailboxGrants = $mailboxEntries
        $state.AdoptedIdentityAppIds = @($adopted)
        Write-Log "The script read the mailbox grants file. Email channels: $($mailboxEntries.Count). Identities that an email channel still uses: $($adopted.Count)" -Level Info
    }
}

function Test-NeologikPowerShellVersion {
    param([version]$Version = $PSVersionTable.PSVersion)
    if ($Version -lt [version]'7.4') {
        Write-ActionRequired "The script needs PowerShell 7.4 or later. This session runs version $Version.`nInstall PowerShell 7 from https://aka.ms/powershell. Then run the script in PowerShell 7, not in Windows PowerShell."
        return $false
    }
    return $true
}

function Write-NeologikHeader {
    $state = $script:State
    $runTitle = if ($state.Run -eq 'PostWindow') { 'later run' } else { 'first run' }
    if ($state.Verify) { $runTitle = "$runTitle with -Verify" }
    Write-Host ''
    Write-Host '=============================================================' -ForegroundColor Cyan
    Write-Host " Neologik environment access: $runTitle" -ForegroundColor Cyan
    Write-Host '=============================================================' -ForegroundColor Cyan
    if ($state.Run -eq 'PostWindow') {
        Write-Host '  The later run applies the grants that the grants files list. The later run makes no other change.'
    }
    else {
        Write-Host '  The first run confirms the directory objects, then reduces the access of the deployment identity.'
    }
    if ($state.Verify) { Write-Host '  -Verify: the script reports each change as WOULD and writes nothing.' -ForegroundColor Yellow }
    Write-Host "  Tenant:                                     $($state.TenantId)"
    Write-Host "  Deployment identity:                        $($state.DeploySpClientId)"
    if ($state.SignInAppClientId) { Write-Host "  Platform Sign-in application:               $($state.SignInAppClientId)" }
    if ($state.SharePointAppClientId) { Write-Host "  SharePoint application:                     $($state.SharePointAppClientId)" }
    if ($state.BotAppClientIds.Count -gt 0) { Write-Host "  Agent registrations:                        $($state.BotAppClientIds -join ', ')" }
    if ($state.NceUserGroupId) { Write-Host "  User group of the Neologik Context Engine:  $($state.NceUserGroupId)" }
    if ($state.AdminGroupId) { Write-Host "  Admin User Group:                           $($state.AdminGroupId)" }
    if ($state.AgentGrants) { Write-Host "  Agent grants file:                          $($state.AgentGrantsFile)" }
    if ($state.MailboxGrantsFile) { Write-Host "  Mailbox grants file:                        $($state.MailboxGrantsFile), $($state.MailboxGrants.Count) mailbox grant(s)" }
    if ($state.AdoptedIdentityAppIds.Count -gt 0) { Write-Host "  Identities that an email channel uses:      $($state.AdoptedIdentityAppIds -join ', ')" }
    if ($state.RemoveLegacyGrantAppIds.Count -gt 0) { Write-Host "  Mailbox grants to remove:                   $($state.RemoveLegacyGrantAppIds -join ', ')" }
    if ($state.Run -eq 'PreWindow') {
        Write-Host "  Subscription:                               $($state.SubscriptionId)"
        Write-Host "  Resource group:                             $($state.ResourceGroupName)"
    }
    Write-Host ''
}

# ----- Modules and sign-in ------------------------------------------------------

function Import-NeologikModuleSet {
    <#
    Installs each module of a set when the module is absent or older than the
    minimum version. Imports one version that every module of the set has. Microsoft
    Graph modules of different versions fail at import with an assembly conflict.
    That conflict is the most common cause of a failed run on a workstation.
    Returns $true. Returns $false after the function prints what to do.
    -Independent: each module has a version number separate from the other modules.
    The Az modules Az.Accounts, Az.Resources and Az.Sql never share a version
    number. The function imports each module at the highest version available.
    #>
    param([string[]]$Names, [version]$MinimumVersion, [string]$InstallHint, [switch]$Independent)
    try {
        foreach ($name in $Names) {
            $versions = @(Get-NeologikAvailableModuleVersion -Name $name | Where-Object { $_ -ge $MinimumVersion })
            if ($versions.Count -eq 0) {
                Write-Log "The script installs the PowerShell module $name for your user account" -Level Info
                Install-NeologikModule -Name $name -MinimumVersion $MinimumVersion
            }
        }
        if ($Independent) {
            foreach ($name in $Names) { Import-NeologikModule -Name $name }
            return $true
        }
        # A version that this session has already loaded decides the version. Otherwise the
        # function takes the highest version that every module of the set has.
        $target = $null
        foreach ($name in $Names) {
            $loaded = Get-NeologikLoadedModuleVersion -Name $name
            if ($loaded) { $target = $loaded; break }
        }
        if (-not $target) {
            $common = $null
            foreach ($name in $Names) {
                $versions = @(Get-NeologikAvailableModuleVersion -Name $name | Where-Object { $_ -ge $MinimumVersion })
                $common = if ($null -eq $common) { $versions } else { @($common | Where-Object { $versions -contains $_ }) }
            }
            $target = @($common | Sort-Object -Descending) | Select-Object -First 1
        }
        foreach ($name in $Names) {
            if ($target) { Import-NeologikModule -Name $name -RequiredVersion $target }
            else { Import-NeologikModule -Name $name }
        }
        return $true
    }
    catch {
        Write-Log "The script could not prepare the PowerShell modules. $(Get-NeologikErrorText $_)" -Level Error
        Write-ActionRequired "The script could not install or load the PowerShell modules that the script needs.`nOpen a new PowerShell 7 window and run this command:`n  $InstallHint`nThen run the script again."
        return $false
    }
}

function Get-NeologikGraphScope {
    $state = $script:State
    $scopes = @('Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'Directory.Read.All', 'User.Read',
        'DelegatedPermissionGrant.Read.All', 'AgentIdentityBlueprint.Create', 'AgentIdentityBlueprint.AddRemoveCreds.All',
        'AgentIdentityBlueprintPrincipal.Create')
    if ($state.AgentGrants) {
        # A grant to an agent user is an oAuth2PermissionGrant. Only a Global Administrator
        # can write an oAuth2PermissionGrant. The deployment identity cannot.
        $scopes += 'DelegatedPermissionGrant.ReadWrite.All'
    }
    if ($state.Run -eq 'PreWindow') {
        # The permission reduction removes the directory role Application Administrator
        # from the deployment identity. The permission reduction also removes the membership
        # of the Admin User Group, when the SQL server administrator is the deployment
        # identity.
        $scopes += 'RoleManagement.ReadWrite.Directory'
        $scopes += 'GroupMember.ReadWrite.All'
        # The security groups of version 5, created when absent, and the Neologik
        # support accounts, invited as guests when absent.
        $scopes += 'Group.ReadWrite.All'
        $scopes += 'User.Invite.All'
        # Microsoft Graph accepts a new owner on an existing service principal of an agent
        # identity blueprint only with this permission. Application.ReadWrite.All does not
        # cover that object.
        $scopes += 'AgentIdentityBlueprintPrincipal.ReadWrite.All'
    }
    return $scopes
}

function Connect-NeologikGraph {
    # Signs in to Microsoft Graph and checks that the session is for the expected
    # tenant. Returns $true. Returns $false after the function prints what to do.
    $state = $script:State
    $scopes = Get-NeologikGraphScope
    try {
        if ($state.UseAzureCliToken) {
            Write-Log 'The script signs in to Microsoft Graph with the token of the Azure CLI session' -Level Info
            if (-not (Test-NeologikCommand -Name 'az')) {
                Write-ActionRequired "The Azure CLI is not installed on this workstation.`nInstall the Azure CLI and sign in with this command:`n  az login --tenant $($state.TenantId)`nOr run the script without -UseAzureCliToken."
                return $false
            }
            $cli = Invoke-NeologikAzureCli -Arguments @('account', 'get-access-token', '--resource-type', 'ms-graph', '--tenant', $state.TenantId, '--query', 'accessToken', '-o', 'tsv')
            $cliToken = [string](@($cli.Output) | Where-Object { $_ -and $_.Trim() } | Select-Object -Last 1)
            if ($cli.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($cliToken)) {
                Write-ActionRequired "The Azure CLI gave no token for tenant $($state.TenantId).`nSign in with this command:`n  az login --tenant $($state.TenantId) --scope https://graph.microsoft.com//.default`nThen run the script again. Or run the script without -UseAzureCliToken, to sign in in the browser."
                return $false
            }
            Connect-MgGraph -AccessToken (ConvertTo-SecureString -String $cliToken.Trim() -AsPlainText -Force) -NoWelcome -ErrorAction Stop
        }
        else {
            # The order of the methods: the browser sign-in of the script, then the device code
            # of the script, then the Azure CLI session of the workstation, then the device code
            # prompt of Microsoft Graph PowerShell.
            $connected = $false
            Write-Log 'The script signs in to Microsoft Graph. Sign in as a Global Administrator' -Level Info
            $graphScopes = @(@($scopes) + @('openid', 'profile', 'offline_access'))
            $token = Get-NeologikBrowserToken -ClientId $script:GraphPublicClientId -Label 'Microsoft Graph' -Scopes $graphScopes
            if (-not $token) {
                $token = Get-NeologikDeviceCodeToken -ClientId $script:GraphPublicClientId -Label 'Microsoft Graph' -Scopes $graphScopes
            }
            if ($token) {
                # The sign-in to Azure names the same account, so the browser does not ask again.
                $state.SignInAccount = [string]$token.Account
                try {
                    Connect-MgGraph -AccessToken (ConvertTo-SecureString -String $token.AccessToken -AsPlainText -Force) -NoWelcome -ErrorAction Stop
                    $connected = $true
                }
                catch { Write-Log "The script could not open the Microsoft Graph session with the token of the sign-in. $(Get-NeologikErrorText $_)" -Level Warning }
            }
            if (-not $connected -and (Test-NeologikCommand -Name 'az')) {
                Write-Log 'The script now tries the Azure CLI session of this workstation' -Level Info
                $cli = Invoke-NeologikAzureCli -Arguments @('account', 'get-access-token', '--resource-type', 'ms-graph', '--tenant', $state.TenantId, '--query', 'accessToken', '-o', 'tsv')
                $cliToken = [string](@($cli.Output) | Where-Object { $_ -and $_.Trim() } | Select-Object -Last 1)
                if ($cli.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($cliToken)) {
                    try {
                        Connect-MgGraph -AccessToken (ConvertTo-SecureString -String $cliToken.Trim() -AsPlainText -Force) -NoWelcome -ErrorAction Stop
                        $connected = $true
                    }
                    catch { Write-Log "The script could not open the Microsoft Graph session with the token of the Azure CLI session. $(Get-NeologikErrorText $_)" -Level Warning }
                }
                else { Write-Log '  The Azure CLI has no session for this tenant' -Level Info }
            }
            if (-not $connected) {
                Write-Log 'The script now tries the device code prompt of Microsoft Graph PowerShell. The prompt waits 120 seconds' -Level Info
                # The SDK writes the device code text to the Information stream.
                $InformationPreference = 'Continue'
                Connect-MgGraph -TenantId $state.TenantId -Scopes $scopes -UseDeviceCode -NoWelcome -ErrorAction Stop
            }
        }
    }
    catch {
        Write-Log "The sign-in to Microsoft Graph failed. $(Get-NeologikErrorText $_)" -Level Error
        Write-ActionRequired "The sign-in to Microsoft Graph did not complete. The script tried four methods:`n  1. The browser of this computer.`n  2. The device code of the script.`n  3. The Azure CLI session.`n  4. The device code of Microsoft Graph PowerShell.`nRun the script again on a computer with a desktop and a browser.`nSign in as a Global Administrator of tenant $($state.TenantId) and approve the permissions."
        return $false
    }
    $context = $null
    try { $context = Get-MgContext -ErrorAction Stop } catch { $context = $null }
    if (-not $context) {
        Write-ActionRequired "The script has no Microsoft Graph session. Run the script again and complete the sign-in."
        return $false
    }
    $contextTenant = [string](Get-NeologikProperty $context 'TenantId' '')
    if ($contextTenant -and $contextTenant -ne $state.TenantId) {
        Write-ActionRequired "The sign-in is for tenant $contextTenant. The environment is in tenant $($state.TenantId).`nRun the command Disconnect-MgGraph. Then run the script again.`nSign in as a Global Administrator of tenant $($state.TenantId)."
        return $false
    }
    $account = [string](Get-NeologikProperty $context 'Account' '')
    if ($account) { Write-Log "Signed in as $account, tenant $($state.TenantId)" -Level Info }
    $granted = @(Get-NeologikProperty $context 'Scopes' @())
    if ($granted.Count -gt 0) {
        $missing = @($scopes | Where-Object { $granted -notcontains $_ })
        if ($missing.Count -gt 0) {
            Write-Log "  The session lacks the permission(s) $($missing -join ', '). The script reports each item that needs a missing permission as FAILED" -Level Warning
        }
    }
    return (Test-NeologikGlobalAdministrator)
}

function Test-NeologikGlobalAdministrator {
    <#
    Checks the signed-in account. The signed-in account must hold an active Global
    Administrator role before the script changes anything. A run that writes stops
    and prints one instruction. A run with -Verify warns and continues. The reads
    of a run with -Verify still work. The script reports each item that needs the
    role as FAILED. The function keeps the object id of the signed-in account for
    the check of the Azure roles.
    #>
    $state = $script:State
    $graph = $script:GraphV1
    try {
        $me = Invoke-NeologikGraph -Method GET -Uri "$graph/me?`$select=id,userPrincipalName"
        $state.SignedInObjectId = [string](Get-NeologikProperty $me 'id' '')
        $state.SignedInUpn = [string](Get-NeologikProperty $me 'userPrincipalName' '')
        $roles = @(Get-NeologikGraphCollection -Uri "$graph/me/memberOf/microsoft.graph.directoryRole?`$select=id,displayName,roleTemplateId")
    }
    catch {
        Write-Log "The script could not read the directory roles of the signed-in account. $(Get-NeologikErrorText $_). The script continues. The script reports each item that needs Global Administrator as FAILED" -Level Warning
        return $true
    }
    $isGlobalAdministrator = @($roles | Where-Object { [string](Get-NeologikProperty $_ 'roleTemplateId' '') -eq $script:GlobalAdministratorTemplateId }).Count -gt 0
    if ($isGlobalAdministrator) {
        Write-Log '  The signed-in account holds an active Global Administrator role' -Level Success
        return $true
    }
    $who = if ($state.SignedInUpn) { $state.SignedInUpn } else { 'The signed-in account' }
    if (Test-NeologikVerifyOnly) {
        Write-Log "  $who does not hold an active Global Administrator role. The run with -Verify continues. The script reports each item that needs the role as FAILED" -Level Warning
        return $true
    }
    Write-Log "$who does not hold an active Global Administrator role" -Level Error
    Write-ActionRequired "$who does not hold an active Global Administrator role in tenant $($state.TenantId).`nActivate the role in the Microsoft Entra admin centre: Identity governance > Privileged Identity Management > My roles.`nOr sign in with an account that holds the role.`nThen run the script again. The script changed nothing."
    return $false
}

function Resolve-NeologikPrincipal {
    # Reads the deployment identity and the service principal of Microsoft Graph. The
    # script can check nothing without both objects.
    $state = $script:State
    try {
        $deploySp = @(Get-MgServicePrincipal -Filter "appId eq '$($state.DeploySpClientId)'" -ErrorAction Stop) | Select-Object -First 1
    }
    catch {
        Write-Log "The script could not read the deployment identity. $(Get-NeologikErrorText $_)" -Level Error
        Add-Summary 'Deployment identity' "FAILED: $(Get-NeologikErrorText $_)"
        return $false
    }
    if (-not $deploySp) {
        Write-Log "Tenant $($state.TenantId) holds no service principal with the client id $($state.DeploySpClientId)" -Level Error
        Add-Summary 'Deployment identity' 'MISSING: the tenant holds no service principal with this client id'
        Write-ActionRequired "The deployment identity with the client id $($state.DeploySpClientId) does not exist in tenant $($state.TenantId).`nAsk Neologik to confirm the value of -DeploySpClientId. Then run the script again."
        return $false
    }
    $state.DeploySp = $deploySp
    Write-Log "Deployment identity: '$($deploySp.DisplayName)'" -Level Info
    try {
        $graphSp = @(Get-MgServicePrincipal -Filter "appId eq '$script:GraphSpAppId'" -ErrorAction Stop) | Select-Object -First 1
    }
    catch {
        Write-Log "The script could not read the service principal of Microsoft Graph. $(Get-NeologikErrorText $_)" -Level Error
        Add-Summary 'Service principal of Microsoft Graph' "FAILED: $(Get-NeologikErrorText $_)"
        return $false
    }
    if (-not $graphSp) {
        Add-Summary 'Service principal of Microsoft Graph' 'MISSING: report to Neologik'
        Write-Log 'This tenant holds no service principal of Microsoft Graph. Report this message to Neologik' -Level Error
        return $false
    }
    $state.GraphSp = $graphSp
    return $true
}

# ----- Microsoft Graph application permissions ----------------------------------

function Grant-NeologikGraphAppRole {
    <#
    Grants a set of Microsoft Graph application permissions to one principal. The
    function checks and grants each permission separately. The result records the
    number of permissions that the function granted. The result also records
    whether the principal now holds every permission.
    #>
    param([string]$PrincipalId, [string]$Label, [string[]]$RoleNames)
    $graphSp = $script:State.GraphSp
    $outcome = @{ Granted = 0; Pending = 0; Failed = 0; Complete = $true }
    $existing = @()
    try {
        $existing = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalId -All -ErrorAction Stop |
            Where-Object { $_.ResourceId -eq $graphSp.Id })
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  The script could not read the Microsoft Graph application permissions of: $Label. $reason" -Level Error
        foreach ($roleName in $RoleNames) { Add-Summary "$Label permission: $roleName" "FAILED: $reason" }
        $outcome.Failed = $RoleNames.Count
        $outcome.Complete = $false
        return $outcome
    }
    foreach ($roleName in $RoleNames) {
        $role = Get-NeologikGraphAppRole -RoleName $roleName
        if (-not $role) {
            Write-Log "  Microsoft Graph does not publish the permission '$roleName' in this cloud. Report this message to Neologik" -Level Warning
            Add-Summary "$Label permission: $roleName" 'NOT FOUND: report to Neologik'
            $outcome.Complete = $false
            continue
        }
        if (@($existing | Where-Object { $_.AppRoleId -eq $role.Id }).Count -gt 0) {
            Write-Log "  ${roleName}: already granted" -Level Success
            Add-Summary "$Label permission: $roleName" 'Already granted'
            continue
        }
        if (Test-NeologikVerifyOnly) {
            Add-NeologikPendingChange "$Label permission: $roleName" 'GRANT'
            $outcome.Pending++
            continue
        }
        try {
            Invoke-NeologikWrite -Command 'New-MgServicePrincipalAppRoleAssignment' -Parameters @{
                ServicePrincipalId = $PrincipalId; PrincipalId = $PrincipalId; ResourceId = $graphSp.Id; AppRoleId = $role.Id
            } | Out-Null
            Write-Log "  ${roleName}: granted" -Level Success
            Add-Summary "$Label permission: $roleName" 'Granted'
            $outcome.Granted++
        }
        catch {
            $reason = Get-NeologikErrorText $_
            if ($reason -match '(?i)already exists|Permission being assigned already exists') {
                Write-Log "  ${roleName}: already granted" -Level Success
                Add-Summary "$Label permission: $roleName" 'Already granted'
                continue
            }
            if (Test-NeologikPrivilegeError $_) {
                $reason = 'insufficient privileges. Sign in as a Global Administrator'
            }
            Write-Log "  ${roleName}: FAILED. $reason" -Level Error
            Add-Summary "$Label permission: $roleName" "FAILED: $reason"
            $outcome.Failed++
            $outcome.Complete = $false
        }
    }
    return $outcome
}

# ----- Grants to agent users ----------------------------------------------------

function Get-NeologikAgentUserGrant {
    # Returns the one delegated permission grant from the client to the agent user on
    # Microsoft Graph.
    param([string]$IdentityObjectId, [string]$AgentUserObjectId)
    $graphSp = $script:State.GraphSp
    $uri = "$script:GraphV1/oauth2PermissionGrants?`$filter=clientId eq '$IdentityObjectId' and principalId eq '$AgentUserObjectId' and resourceId eq '$($graphSp.Id)'"
    return @(Get-NeologikGraphCollection -Uri $uri) | Select-Object -First 1
}

function Grant-NeologikAgentUserAccess {
    <#
    Creates one delegated permission grant for each agent or App.
      client     The agent identity, by client id.
      principal  The agent user, by object id.
      resource   Microsoft Graph.
      scope      Exactly the permissions in the file.
    The function creates the grant, or changes the grant when the scope differs. The
    function then reads the grant back and compares the scope. The grant counts
    only after that comparison. Microsoft Entra ID refuses some scope strings for a
    short time. The function tries a refused write again with the same permissions
    in another order.
    #>
    param(
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$IdentityClientId,
        [Parameter(Mandatory)][string]$AgentUserObjectId,
        [Parameter(Mandatory)][string[]]$Scopes
    )
    $label = "Grant to agent user: $Kind $Name"
    $graphSp = $script:State.GraphSp
    try {
        $identity = @(Get-NeologikGraphCollection -Uri "$script:GraphBeta/servicePrincipals?`$filter=appId eq '$IdentityClientId'&`$select=id") | Select-Object -First 1
        if (-not $identity) {
            Write-Log "  $Kind '$Name': this tenant holds no agent identity with the client id $IdentityClientId. Tell Neologik. Run the script again after Neologik confirms the agent identity" -Level Warning
            Add-Summary $label 'MISSING: the tenant holds no agent identity with this client id'
            return
        }
        $identityId = [string](Get-NeologikProperty $identity 'id')
        $desired = Get-NeologikScopeSet ($Scopes -join ' ')
        $existing = Get-NeologikAgentUserGrant -IdentityObjectId $identityId -AgentUserObjectId $AgentUserObjectId
        if ($existing -and (Get-NeologikScopeSet ([string](Get-NeologikProperty $existing 'scope' ''))) -eq $desired) {
            Write-Log "  $Kind '$Name': the grant already exists with the permissions $desired" -Level Success
            Add-Summary $label 'Already granted'
            return
        }
        if (Test-NeologikVerifyOnly) {
            Add-NeologikPendingChange $label $(if ($existing) { "UPDATE: $desired" } else { "GRANT: $desired" })
            return
        }
        $words = @($desired -split ' ' | Where-Object { $_ })
        $applied = $false
        $denied = $false
        for ($attempt = 0; $attempt -lt 3 -and -not $applied -and -not $denied; $attempt++) {
            $k = if ($words.Count -gt 0) { $attempt % $words.Count } else { 0 }
            $rotated = @($words[$k..($words.Count - 1)])
            if ($k -gt 0) { $rotated += @($words[0..($k - 1)]) }
            $scopeTry = ($rotated | Where-Object { $_ }) -join ' '
            try {
                if ($existing) {
                    $null = Invoke-NeologikGraph -Method PATCH -Uri "$script:GraphV1/oauth2PermissionGrants/$(Get-NeologikProperty $existing 'id')" `
                        -Body (@{ scope = $scopeTry } | ConvertTo-Json -Compress)
                }
                else {
                    $body = @{ clientId = $identityId; consentType = 'Principal'; principalId = $AgentUserObjectId
                               resourceId = $graphSp.Id; scope = $scopeTry } | ConvertTo-Json -Compress
                    $null = Invoke-NeologikGraph -Method POST -Uri "$script:GraphV1/oauth2PermissionGrants" -Body $body
                }
                $applied = $true
            }
            catch {
                if (Test-NeologikPrivilegeError $_) {
                    $denied = $true
                    Write-Log "  $Kind '$Name': Microsoft Entra ID refused the write. $(Get-NeologikErrorText $_)" -Level Error
                }
                else {
                    Write-Log "  Attempt $($attempt + 1): Microsoft Entra ID refused the permissions '$scopeTry'. $(Get-NeologikErrorText $_)" -Level Warning
                }
            }
        }
        if ($denied) {
            Add-Summary $label 'FAILED: insufficient privileges. Sign in as a Global Administrator and approve DelegatedPermissionGrant.ReadWrite.All'
            return
        }
        $readback = Get-NeologikAgentUserGrant -IdentityObjectId $identityId -AgentUserObjectId $AgentUserObjectId
        if ($readback -and (Get-NeologikScopeSet ([string](Get-NeologikProperty $readback 'scope' ''))) -eq $desired) {
            Write-Log "  $Kind '$Name': granted the permissions $desired" -Level Success
            Add-Summary $label $(if ($existing) { "Updated: $desired" } else { "Granted: $desired" })
        }
        else {
            Write-Log "  $Kind '$Name': Microsoft Entra ID did not accept the permissions '$desired' in 3 attempts. Report the permissions to Neologik" -Level Error
            Add-Summary $label 'PENDING: Microsoft Entra ID refused the permissions. Report to Neologik'
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  $Kind '$Name': FAILED. $reason" -Level Error
        Add-Summary $label "FAILED: $reason"
    }
}

function Grant-NeologikComponentGraphRole {
    <#
    Grants one Microsoft Graph application permission from the agent grants file to
    a named workload identity. The function grants only a permission that has no
    limit to one mailbox or one site. The function reports a permission with such a
    limit. An Exchange Administrator or a SharePoint Administrator grants that
    permission.
    #>
    param(
        [Parameter(Mandatory)][string]$App,
        [Parameter(Mandatory)][string]$IdentityName,
        [Parameter(Mandatory)][string]$RoleName,
        [string]$ScopeType
    )
    $label = "App $App permission: $RoleName"
    if ($ScopeType) {
        Write-Log "  $App '$RoleName': the permission is limited to one $ScopeType. Grant the permission in Exchange Online or in SharePoint. Grant the permission for the mailbox or the site that the App uses" -Level Warning
        Add-Summary $label "SKIPPED: the permission is limited to one $ScopeType. An administrator grants the permission in Exchange Online or in SharePoint"
        return
    }
    try {
        $escaped = $IdentityName -replace "'", "''"
        $sp = @(Get-NeologikGraphCollection -Uri "$script:GraphV1/servicePrincipals?`$filter=displayName eq '$escaped'&`$select=id") | Select-Object -First 1
        if (-not $sp) {
            Write-Log "  This tenant holds no workload identity with the name '$IdentityName'. Neologik creates the workload identity when Neologik installs the App" -Level Warning
            Add-Summary $label 'MISSING: the tenant holds no workload identity with this name'
            return
        }
        $null = Grant-NeologikGraphAppRole -PrincipalId ([string](Get-NeologikProperty $sp 'id')) -Label "App $App" -RoleNames @($RoleName)
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  $App '$RoleName': FAILED. $reason" -Level Error
        Add-Summary $label "FAILED: $reason"
    }
}

# ----- Mailbox grants for email channels ----------------------------------------

function Get-NeologikExchangeServicePrincipal {
    param([string]$Identity)
    try { return (Get-ServicePrincipal -Identity $Identity -ErrorAction SilentlyContinue) } catch { return $null }
}

function Grant-NeologikMailboxAccess {
    <#
    Grants access to one mailbox with the role based access control for
    applications of Exchange Online. The grant has three parts.
      1. The Exchange service principal of the identity of the email channel.
      2. A management scope whose recipient filter names the mailbox.
      3. The roles Application Mail.Read, Application Mail.ReadWrite and
         Application Mail.Send on that management scope.
    Exchange Online refuses a second management scope with the same recipient
    filter. The function uses an existing management scope that names the mailbox,
    whatever the name of the management scope.
    #>
    param(
        [Parameter(Mandatory)][string]$IdentityAppId,
        [Parameter(Mandatory)][string]$IdentityObjectId,
        [Parameter(Mandatory)][string]$Mailbox,
        [Parameter(Mandatory)][string]$DisplayName
    )
    $label = "Mailbox grant: $Mailbox for $DisplayName"
    $verify = Test-NeologikVerifyOnly
    try {
        # In a run with -Verify the function reports every pending part as one item.
        $pending = @()
        $sp = Get-NeologikExchangeServicePrincipal -Identity $IdentityAppId
        if (-not $sp) {
            if ($verify) { $pending += 'Exchange service principal' }
            else {
                $sp = Invoke-NeologikWrite -Command 'New-ServicePrincipal' -Parameters @{ AppId = $IdentityAppId; ObjectId = $IdentityObjectId; DisplayName = $DisplayName }
                Write-Log "  The script created the Exchange service principal of $DisplayName" -Level Success
            }
        }
        $scopeName = "Scope-$DisplayName"
        $scope = $null
        try { $scope = Get-ManagementScope -Identity $scopeName -ErrorAction SilentlyContinue } catch { $scope = $null }
        if (-not $scope) {
            $scope = @(Get-ManagementScope -ErrorAction Stop | Where-Object { [string](Get-NeologikProperty $_ 'RecipientFilter' '') -like "*$Mailbox*" }) | Select-Object -First 1
            if ($scope) { Write-Log "  The script uses the existing management scope '$($scope.Name)'. The management scope has the same recipient filter" -Level Info }
        }
        if (-not $scope) {
            if ($verify) { $pending += "management scope $scopeName" }
            else {
                $scope = Invoke-NeologikWrite -Command 'New-ManagementScope' -Parameters @{ Name = $scopeName; RecipientRestrictionFilter = "PrimarySmtpAddress -eq '$Mailbox'" }
                Write-Log "  The script created the management scope $scopeName" -Level Success
            }
        }
        $granted = 0
        foreach ($role in @(
                @{ Suffix = 'MailRead';      Role = 'Application Mail.Read' },
                @{ Suffix = 'MailReadWrite'; Role = 'Application Mail.ReadWrite' },
                @{ Suffix = 'MailSend';      Role = 'Application Mail.Send' })) {
            $assignmentName = "Assignment-$DisplayName-$($role.Suffix)"
            $assignment = $null
            try { $assignment = Get-ManagementRoleAssignment -Identity $assignmentName -ErrorAction SilentlyContinue } catch { $assignment = $null }
            if ($assignment) { continue }
            if ($verify) { $pending += "role assignment $assignmentName"; continue }
            Invoke-NeologikWrite -Command 'New-ManagementRoleAssignment' -Parameters @{
                Name = $assignmentName; App = $IdentityObjectId; Role = $role.Role; CustomResourceScope = $scope.Name
            } | Out-Null
            $granted++
        }
        if ($verify -and $pending.Count -gt 0) {
            Add-NeologikPendingChange $label "GRANT: $($pending -join ', ')"
            return
        }
        $inScope = @()
        try {
            $inScope = @(Test-ServicePrincipalAuthorization -Identity $IdentityObjectId -Resource $Mailbox -ErrorAction Stop |
                Where-Object { [bool](Get-NeologikProperty $_ 'InScope' $false) })
        }
        catch {
            Write-Log "  $Mailbox for ${DisplayName}: the script added $granted role(s). Exchange Online could not yet test the access. $(Get-NeologikErrorText $_). Run the script again to confirm the mailbox grant" -Level Warning
            Add-Summary $label 'PENDING: run the script again to confirm the mailbox grant'
            return
        }
        if ($inScope.Count -ge 3) {
            Write-Log "  $Mailbox for ${DisplayName}: Exchange Online confirms $($inScope.Count) role(s) for the mailbox" -Level Success
            Add-Summary $label $(if ($granted -gt 0) { "Granted: $granted role(s) added" } else { 'Already granted' })
        }
        else {
            Write-Log "  $Mailbox for ${DisplayName}: the script added $granted role(s). Exchange Online confirms $($inScope.Count) role(s) for the mailbox. Exchange Online can take two hours to apply a role. Run the script again to confirm the mailbox grant" -Level Warning
            Add-Summary $label 'PENDING: run the script again to confirm the mailbox grant'
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  $Mailbox for ${DisplayName}: FAILED. $reason" -Level Error
        Add-Summary $label "FAILED: $reason"
    }
}

function Get-NeologikExchangeAssignment {
    # Returns every Exchange role assignment that an Exchange service principal holds.
    param($ServicePrincipal)
    $assignments = @()
    try {
        $assignments = @(Get-ManagementRoleAssignment -RoleAssignee $ServicePrincipal.Identity -ErrorAction Stop)
    }
    catch {
        $assignments = @()
    }
    if ($assignments.Count -eq 0) {
        # The first read found no role assignment. The function now matches the assignee
        # against each identifier of the Exchange service principal.
        $ids = @(
            [string](Get-NeologikProperty $ServicePrincipal 'ObjectId' ''),
            [string](Get-NeologikProperty $ServicePrincipal 'AppId' ''),
            [string](Get-NeologikProperty $ServicePrincipal 'DisplayName' ''),
            [string](Get-NeologikProperty $ServicePrincipal 'Identity' '')
        ) | Where-Object { $_ }
        $assignments = @(Get-ManagementRoleAssignment -ErrorAction Stop | Where-Object {
                $ids -contains [string](Get-NeologikProperty $_ 'RoleAssigneeName' '')
            })
    }
    return $assignments
}

function Remove-NeologikMailboxAccess {
    <#
    Removes the Exchange role assignments and the Exchange service principal of an
    identity that the environment has stopped using. The function keeps the
    management scope. The mailbox grant of the email channel uses the same
    management scope.
    #>
    param([Parameter(Mandatory)][string]$LegacyAppId)
    $label = "Mailbox grant to remove: $LegacyAppId"
    try {
        $sp = Get-NeologikExchangeServicePrincipal -Identity $LegacyAppId
        if (-not $sp) {
            Write-Log "  Identity ${LegacyAppId}: Exchange Online holds no Exchange service principal of the identity. The script removes nothing" -Level Success
            Add-Summary $label 'Not present'
            return
        }
        $assignments = @(Get-NeologikExchangeAssignment -ServicePrincipal $sp)
        if (Test-NeologikVerifyOnly) {
            Add-NeologikPendingChange $label "REMOVE: $($assignments.Count) role assignment(s) and the Exchange service principal"
            return
        }
        foreach ($assignment in $assignments) {
            Invoke-NeologikWrite -Command 'Remove-ManagementRoleAssignment' -Parameters @{ Identity = $assignment.Name; Confirm = $false } | Out-Null
        }
        Invoke-NeologikWrite -Command 'Remove-ServicePrincipal' -Parameters @{ Identity = $sp.Identity; Confirm = $false } | Out-Null
        Write-Log "  Identity ${LegacyAppId}: the script removed $($assignments.Count) role assignment(s) and the Exchange service principal" -Level Success
        Add-Summary $label "Removed: $($assignments.Count) role assignment(s)"
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  Identity ${LegacyAppId}: FAILED. $reason" -Level Error
        Add-Summary $label "FAILED: $reason"
    }
}

# ----- The steps: 1 to 4 in the first run, 5 and 6 in the later run --------------

function Set-NeologikAgentBlueprint {
    <#
    Steps 1a to 1c: the agent identity blueprint, the owner, the service principal,
    the permission of the service principal and the federated credentials. When the
    agent identity blueprint exists, the function checks each item separately. When
    the function cannot find or create the agent identity blueprint, the function
    records each dependent item as SKIPPED.
    #>
    $state = $script:State
    $deploySp = $state.DeploySp
    $graph = $script:GraphV1
    $graphBeta = $script:GraphBeta

    Write-Log 'Step 1a of 5: the agent identity blueprint' -Level Info
    # The short name comes from the configuration file or from -SolutionShortName. The
    # script never reads the short name from a display name. The name of the agent
    # identity blueprint is 'Neologik Agent Blueprint - <key> - <short name>'.
    $shortName = $state.ShortName
    $blueprintName = "Neologik Agent Blueprint - $($state.BlueprintKey) - $shortName"
    Write-Log "  Name of the agent identity blueprint: '$blueprintName'. Short name '$shortName' from $($state.ShortNameSource)" -Level Info
    $escaped = $blueprintName -replace "'", "''"
    $blueprint = $null
    $created = $false
    try {
        $blueprint = @(Get-NeologikGraphCollection -Uri "$graph/applications?`$filter=displayName eq '$escaped'&`$select=id,appId") | Select-Object -First 1
        if (-not $blueprint) {
            # The deployment identity can already own one agent identity blueprint with another
            # short name. That agent identity blueprint belongs to the environment. The script
            # uses that agent identity blueprint and creates no second one. When the deployment
            # identity owns several, the script cannot choose. The script stops and names each
            # one.
            $prefix = "Neologik Agent Blueprint - $($state.BlueprintKey) - "
            $prefixEscaped = $prefix -replace "'", "''"
            $owned = @()
            foreach ($candidate in @(Get-NeologikGraphCollection -Uri "$graph/applications?`$filter=startswith(displayName,'$prefixEscaped')&`$select=id,appId,displayName")) {
                $candidateId = [string](Get-NeologikProperty $candidate 'id' '')
                $candidateOwners = @(Get-NeologikGraphCollection -Uri "$graph/applications/$candidateId/owners?`$select=id" |
                    ForEach-Object { [string](Get-NeologikProperty $_ 'id' '') })
                if ($candidateOwners -contains $deploySp.Id) { $owned += $candidate }
            }
            if ($owned.Count -eq 1) {
                $blueprint = $owned[0]
                $adoptedName = [string](Get-NeologikProperty $blueprint 'displayName' '')
                Write-Log "  The agent identity blueprint '$adoptedName' exists, and the deployment identity is an owner. The script uses '$adoptedName'. The short name in that name differs from '$shortName'. Check the short name in the command" -Level Warning
                Add-Summary 'Agent identity blueprint' "Present: the script uses '$adoptedName'"
                $blueprintName = $adoptedName
            }
            elseif ($owned.Count -gt 1) {
                $names = @($owned | ForEach-Object { [string](Get-NeologikProperty $_ 'displayName' '') })
                Write-Log "  The agent identity blueprint '$blueprintName': FAILED. The deployment identity owns $($owned.Count) agent identity blueprints with other short names: $($names -join ', '). Give -SolutionShortName the short name that the environment uses" -Level Error
                Add-Summary 'Agent identity blueprint' "FAILED: the deployment identity owns several agent identity blueprints: $($names -join ', ')"
                foreach ($item in @('Agent identity blueprint owner', 'Agent identity blueprint sponsor', 'Agent identity blueprint service principal', 'Agent identity blueprint service principal owner', 'Agent identity blueprint service principal permission', 'Agent identity blueprint credentials')) {
                    Add-Summary $item 'SKIPPED: the agent identity blueprint is not available'
                }
                return
            }
        }
        elseif ($blueprint) {
            Write-Log "  The agent identity blueprint '$blueprintName' exists, client id $(Get-NeologikProperty $blueprint 'appId')" -Level Success
            Add-Summary 'Agent identity blueprint' 'Present'
        }
        if ($blueprint) { }
        elseif (Test-NeologikVerifyOnly) {
            # Every item below depends on the agent identity blueprint. The function reports
            # the items as one set.
            Add-NeologikPendingChange 'Agent identity blueprint' "CREATE: $blueprintName"
            Add-NeologikPendingChange 'Agent identity blueprint owner' 'ADD at creation'
            Add-NeologikPendingChange 'Agent identity blueprint sponsor' 'SET at creation: the signed-in administrator'
            Add-NeologikPendingChange 'Agent identity blueprint service principal' 'CREATE'
            Add-NeologikPendingChange 'Agent identity blueprint service principal owner' 'ADD at creation'
            foreach ($roleName in $script:BlueprintPrincipalGraphRoles) { Add-NeologikPendingChange "Agent identity blueprint service principal permission: $roleName" 'GRANT' }
            foreach ($repo in $script:PipelineRepositories) { Add-NeologikPendingChange "Agent identity blueprint credential: github-oidc-$($repo.Name)" 'ADD' }
            return
        }
        else {
            $sponsor = [string](Get-NeologikProperty (Invoke-NeologikGraph -Method GET -Uri "$graph/me?`$select=id") 'id' '')
            if (-not $sponsor) { throw 'The script could not read the id of the signed-in user. The signed-in user is the sponsor of the agent identity blueprint' }
            $body = @{
                '@odata.type'         = 'Microsoft.Graph.AgentIdentityBlueprint'
                displayName           = $blueprintName
                'sponsors@odata.bind' = @("$graph/users/$sponsor")
                'owners@odata.bind'   = @("$graph/directoryObjects/$($deploySp.Id)")
            } | ConvertTo-Json -Depth 5 -Compress
            $blueprint = Invoke-NeologikGraph -Method POST -Uri "$graph/applications/microsoft.graph.agentIdentityBlueprint" `
                -Headers $script:OdataHeaders -Body $body
            $created = $true
            Write-Log "  The script created the agent identity blueprint '$blueprintName', client id $(Get-NeologikProperty $blueprint 'appId'). The sponsor is the signed-in user" -Level Success
            Add-Summary 'Agent identity blueprint' 'Created'
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        if (Test-NeologikPrivilegeError $_) { $reason = "insufficient privileges. $reason" }
        Write-Log "  The agent identity blueprint '$blueprintName': FAILED. $reason" -Level Error
        Add-Summary 'Agent identity blueprint' "FAILED: $reason"
        $blueprint = $null
    }
    if (-not $blueprint) {
        foreach ($item in @('Agent identity blueprint owner', 'Agent identity blueprint sponsor', 'Agent identity blueprint service principal', 'Agent identity blueprint service principal owner', 'Agent identity blueprint service principal permission', 'Agent identity blueprint credentials')) {
            Add-Summary $item 'SKIPPED: the agent identity blueprint is not available'
        }
        return
    }
    $blueprintObjectId = [string](Get-NeologikProperty $blueprint 'id')
    $blueprintAppId = [string](Get-NeologikProperty $blueprint 'appId')

    # The deployment identity as an owner of the agent identity blueprint.
    try {
        $owners = @(Get-NeologikGraphCollection -Uri "$graph/applications/$blueprintObjectId/owners?`$select=id" -RetryNotFound:$created)
        if (@($owners | ForEach-Object { [string](Get-NeologikProperty $_ 'id' '') }) -contains $deploySp.Id) {
            Write-Log '  The deployment identity is already an owner of the agent identity blueprint' -Level Success
            Add-Summary 'Agent identity blueprint owner' 'Already an owner'
        }
        elseif (Test-NeologikVerifyOnly) {
            Add-NeologikPendingChange 'Agent identity blueprint owner' 'ADD'
        }
        else {
            $ref = @{ '@odata.id' = "$graph/directoryObjects/$($deploySp.Id)" } | ConvertTo-Json -Compress
            try {
                $null = Invoke-NeologikGraph -Method POST -Uri "$graph/applications/$blueprintObjectId/owners/`$ref" -Body $ref -RetryNotFound:$created
                Write-Log '  The script added the deployment identity as an owner of the agent identity blueprint' -Level Success
                Add-Summary 'Agent identity blueprint owner' 'Added'
            }
            catch {
                if ((Get-NeologikErrorText $_) -match '(?i)already exist') {
                    Write-Log '  The deployment identity is already an owner of the agent identity blueprint' -Level Success
                    Add-Summary 'Agent identity blueprint owner' 'Already an owner'
                }
                else { throw }
            }
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  The owner of the agent identity blueprint: FAILED. $reason" -Level Error
        Add-Summary 'Agent identity blueprint owner' "FAILED: $reason"
    }

    # The sponsor of the agent identity blueprint. The sponsor is the person who is
    # accountable for the agents of the environment. Each agent identity that the
    # Neologik Platform creates takes the sponsor of the agent identity blueprint.
    # Microsoft Entra ID creates no agent identity without a sponsor. The signed-in
    # Global Administrator becomes the sponsor when the agent identity blueprint has
    # no sponsor.
    try {
        $sponsorsUri = "$graph/applications/$blueprintObjectId/microsoft.graph.agentIdentityBlueprint/sponsors"
        $sponsors = @(Get-NeologikGraphCollection -Uri "$sponsorsUri`?`$select=id,displayName" -RetryNotFound:$created)
        if ($sponsors.Count -gt 0) {
            $names = @($sponsors | ForEach-Object {
                    $name = [string](Get-NeologikProperty $_ 'displayName' '')
                    if ($name) { $name } else { [string](Get-NeologikProperty $_ 'id' '') }
                })
            Write-Log "  The sponsor of the agent identity blueprint: $($names -join ', ')" -Level Success
            Add-Summary 'Agent identity blueprint sponsor' "Present: $($names -join ', ')"
        }
        elseif (Test-NeologikVerifyOnly) {
            Add-NeologikPendingChange 'Agent identity blueprint sponsor' 'ADD: the signed-in administrator'
        }
        else {
            $me = Invoke-NeologikGraph -Method GET -Uri "$graph/me?`$select=id,displayName"
            $meId = [string](Get-NeologikProperty $me 'id' '')
            if (-not $meId) { throw 'The script could not read the id of the signed-in user' }
            $meName = [string](Get-NeologikProperty $me 'displayName' '')
            if (-not $meName) { $meName = $meId }
            $ref = @{ '@odata.id' = "$graph/directoryObjects/$meId" } | ConvertTo-Json -Compress
            $null = Invoke-NeologikGraph -Method POST -Uri "$sponsorsUri/`$ref" -Body $ref
            Write-Log "  The script added the signed-in administrator, $meName, as the sponsor of the agent identity blueprint" -Level Success
            Add-Summary 'Agent identity blueprint sponsor' "Added: $meName"
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  The sponsor of the agent identity blueprint: FAILED. $reason" -Level Error
        Add-Summary 'Agent identity blueprint sponsor' "FAILED: $reason"
    }

    # The service principal of the agent identity blueprint. The function reads the
    # service principal by appId and creates the service principal when absent.
    # Microsoft Entra ID rejects the create until the new agent identity blueprint has
    # replicated.
    $principal = $null
    $principalCreated = $false
    $principalPending = $false
    try {
        $principal = @(Get-NeologikGraphCollection -Uri "$graph/servicePrincipals?`$filter=appId eq '$blueprintAppId'&`$select=id") | Select-Object -First 1
        if ($principal) {
            Write-Log '  The service principal of the agent identity blueprint exists' -Level Success
            Add-Summary 'Agent identity blueprint service principal' 'Present'
        }
        elseif (Test-NeologikVerifyOnly) {
            $principalPending = $true
            Add-NeologikPendingChange 'Agent identity blueprint service principal' 'CREATE'
            Add-NeologikPendingChange 'Agent identity blueprint service principal owner' 'ADD at creation'
            foreach ($roleName in $script:BlueprintPrincipalGraphRoles) { Add-NeologikPendingChange "Agent identity blueprint service principal permission: $roleName" 'GRANT' }
        }
        else {
            # The request binds the deployment identity as an owner. Microsoft Graph accepts
            # an owner in the request that creates the service principal.
            $body = @{ appId = $blueprintAppId; 'owners@odata.bind' = @("$graph/directoryObjects/$($deploySp.Id)") } | ConvertTo-Json -Compress
            for ($attempt = 1; $attempt -le 10; $attempt++) {
                try {
                    $principal = Invoke-NeologikGraph -Method POST -Uri "$graph/servicePrincipals/microsoft.graph.agentIdentityBlueprintPrincipal" `
                        -Headers $script:OdataHeaders -Body $body
                    break
                }
                catch {
                    $status = Get-NeologikHttpStatus $_
                    if ($attempt -lt 10 -and (($status -in @(400, 404)) -or ((Get-NeologikErrorText $_) -match 'local tenant|does not exist'))) {
                        Write-Log "  Microsoft Entra ID has not yet replicated the agent identity blueprint. The script tries again in 15 seconds. Attempt $attempt of 10" -Level Warning
                        Start-Sleep -Seconds 15
                        continue
                    }
                    throw
                }
            }
            $principalCreated = $true
            Write-Log '  The script created the service principal of the agent identity blueprint' -Level Success
            Add-Summary 'Agent identity blueprint service principal' 'Created'
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  The service principal of the agent identity blueprint: FAILED. $reason" -Level Error
        Add-Summary 'Agent identity blueprint service principal' "FAILED: $reason"
        $principal = $null
    }
    if ($principal) {
        $principalId = [string](Get-NeologikProperty $principal 'id')
        try {
            $spOwners = @(Get-NeologikGraphCollection -Uri "$graph/servicePrincipals/$principalId/owners?`$select=id" -RetryNotFound:$principalCreated)
            if (@($spOwners | ForEach-Object { [string](Get-NeologikProperty $_ 'id' '') }) -contains $deploySp.Id) {
                Write-Log '  The deployment identity is already an owner of the service principal of the agent identity blueprint' -Level Success
                Add-Summary 'Agent identity blueprint service principal owner' 'Already an owner'
            }
            elseif (Test-NeologikVerifyOnly) {
                Add-NeologikPendingChange 'Agent identity blueprint service principal owner' 'ADD'
            }
            else {
                $ref = @{ '@odata.id' = "$graph/directoryObjects/$($deploySp.Id)" } | ConvertTo-Json -Compress
                try {
                    $null = Invoke-NeologikGraph -Method POST -Uri "$graph/servicePrincipals/$principalId/owners/`$ref" -Body $ref -RetryNotFound:$principalCreated
                    Write-Log '  The script added the deployment identity as an owner of the service principal of the agent identity blueprint' -Level Success
                    Add-Summary 'Agent identity blueprint service principal owner' 'Added'
                }
                catch {
                    if ((Get-NeologikErrorText $_) -match '(?i)already exist') {
                        Write-Log '  The deployment identity is already an owner of the service principal of the agent identity blueprint' -Level Success
                        Add-Summary 'Agent identity blueprint service principal owner' 'Already an owner'
                    }
                    else { throw }
                }
            }
        }
        catch {
            $reason = Get-NeologikErrorText $_
            Write-Log "  The owner of the service principal of the agent identity blueprint: FAILED. $reason" -Level Error
            Add-Summary 'Agent identity blueprint service principal owner' "FAILED: $reason"
        }

        Write-Log 'Step 1b of 5: the permission of the service principal of the agent identity blueprint' -Level Info
        $null = Grant-NeologikGraphAppRole -PrincipalId $principalId -Label 'Agent identity blueprint service principal' -RoleNames $script:BlueprintPrincipalGraphRoles
    }
    elseif (-not $principalPending) {
        Add-Summary 'Agent identity blueprint service principal owner' 'SKIPPED: the service principal of the agent identity blueprint is not available'
        Add-Summary 'Agent identity blueprint service principal permission' 'SKIPPED: the service principal of the agent identity blueprint is not available'
    }

    Write-Log 'Step 1c of 5: the federated credentials of the agent identity blueprint' -Level Info
    $existingNames = $null
    try {
        $existingCreds = @(Get-NeologikGraphCollection -Uri "$graphBeta/applications/$blueprintObjectId/federatedIdentityCredentials?`$select=name" -RetryNotFound:$created)
        $existingNames = @($existingCreds | ForEach-Object { [string](Get-NeologikProperty $_ 'name' '') })
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  The federated credentials of the agent identity blueprint: FAILED. The script could not read the federated credentials. $reason" -Level Error
        Add-Summary 'Agent identity blueprint credentials' "FAILED: $reason"
    }
    if ($null -ne $existingNames) {
        foreach ($repo in $script:PipelineRepositories) {
            $credName = "github-oidc-$($repo.Name)"
            if ($existingNames -contains $credName) {
                Write-Log "  ${credName}: present" -Level Success
                Add-Summary "Agent identity blueprint credential: $credName" 'Present'
                continue
            }
            if (Test-NeologikVerifyOnly) {
                Add-NeologikPendingChange "Agent identity blueprint credential: $credName" 'ADD'
                continue
            }
            $expression = "claims['sub'] matches 'repo:Neologik-AI/$($repo.Name):*' and claims['repository_id'] eq '$($repo.Id)'"
            $body = @{
                name                     = $credName
                issuer                   = 'https://token.actions.githubusercontent.com'
                audiences                = @('api://AzureADTokenExchange')
                description              = "Neologik deployment pipeline ($($repo.Name)) acts as this blueprint to mint agent identities and users"
                claimsMatchingExpression = @{ value = $expression; languageVersion = 1 }
            } | ConvertTo-Json -Depth 5 -Compress
            try {
                $null = Invoke-NeologikGraph -Method POST -Uri "$graphBeta/applications/$blueprintObjectId/federatedIdentityCredentials" -Body $body -RetryNotFound:$created
                Write-Log "  ${credName}: added" -Level Success
                Add-Summary "Agent identity blueprint credential: $credName" 'Added'
            }
            catch {
                $reason = Get-NeologikErrorText $_
                if ($reason -match '(?i)already exist') {
                    Write-Log "  ${credName}: present" -Level Success
                    Add-Summary "Agent identity blueprint credential: $credName" 'Present'
                    continue
                }
                Write-Log "  ${credName}: FAILED. $reason" -Level Error
                Add-Summary "Agent identity blueprint credential: $credName" "FAILED: $reason"
            }
        }
    }
}

function Set-NeologikDeploymentGraphRole {
    <#
    Step 1d: the Microsoft Graph application permissions of the deployment
    identity. The function first confirms the two permissions that the deployment
    identity keeps. The function removes the other permissions only when the
    deployment identity holds both.
    #>
    $state = $script:State
    $deploySp = $state.DeploySp
    $graphSp = $state.GraphSp
    Write-Log 'Step 1d of 5: the Microsoft Graph application permissions of the deployment identity' -Level Info
    $outcome = Grant-NeologikGraphAppRole -PrincipalId $deploySp.Id -Label 'Deployment identity' -RoleNames $script:RequiredGraphRoles
    if (-not $outcome.Complete) {
        Write-Log '  The deployment identity does not hold both permissions that the deployment identity keeps. The script removes no permission' -Level Warning
        foreach ($roleName in $script:RetiredGraphRoles) {
            Add-Summary "Deployment identity permission to remove: $roleName" 'SKIPPED: the deployment identity does not hold both permissions that the deployment identity keeps'
        }
        return
    }
    $assignments = @()
    try {
        $assignments = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $deploySp.Id -All -ErrorAction Stop |
            Where-Object { $_.ResourceId -eq $graphSp.Id })
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  The permissions of the deployment identity: FAILED. The script could not read the permissions. $reason" -Level Error
        foreach ($roleName in $script:RetiredGraphRoles) { Add-Summary "Deployment identity permission to remove: $roleName" "FAILED: $reason" }
        return
    }
    foreach ($roleName in $script:RetiredGraphRoles) {
        $role = Get-NeologikGraphAppRole -RoleName $roleName
        $assignment = if ($role) { @($assignments | Where-Object { $_.AppRoleId -eq $role.Id }) | Select-Object -First 1 } else { $null }
        if (-not $assignment) {
            Write-Log "  ${roleName}: not held. The script removes nothing" -Level Success
            Add-Summary "Deployment identity permission to remove: $roleName" 'Not held'
            continue
        }
        if (Test-NeologikVerifyOnly) {
            Add-NeologikPendingChange "Deployment identity permission to remove: $roleName" 'REMOVE'
            continue
        }
        try {
            Invoke-NeologikWrite -Command 'Remove-MgServicePrincipalAppRoleAssignment' -Parameters @{ ServicePrincipalId = $deploySp.Id; AppRoleAssignmentId = $assignment.Id } | Out-Null
            Write-Log "  ${roleName}: removed" -Level Success
            Add-Summary "Deployment identity permission to remove: $roleName" 'Removed'
        }
        catch {
            $reason = Get-NeologikErrorText $_
            if ((Get-NeologikHttpStatus $_) -eq 404) {
                Write-Log "  ${roleName}: not held. The script removes nothing" -Level Success
                Add-Summary "Deployment identity permission to remove: $roleName" 'Not held'
                continue
            }
            if (Test-NeologikPrivilegeError $_) { $reason = 'insufficient privileges. Sign in as a Global Administrator' }
            Write-Log "  ${roleName}: FAILED. $reason" -Level Error
            Add-Summary "Deployment identity permission to remove: $roleName" "FAILED: $reason"
        }
    }
    Write-Log "Step 1d is complete. Permissions that the script granted: $($outcome.Granted)" -Level Info
}

# ----- Security groups, Neologik guest users and memberships ----------------------

function Get-NeologikGuestUsersFileDefault {
    # The file beside the script. The onboarding kit ships the file with the script.
    return (Join-Path $PSScriptRoot 'NeologikGuestUsers.txt')
}

function Read-NeologikGuestUsersFile {
    # Returns the mail addresses in the file: one address per line, a line that
    # starts with # is a comment, blank lines and duplicates are dropped.
    param([string]$Path)
    $emails = @()
    foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction Stop)) {
        $text = [string]$line
        if ($null -eq $text) { continue }
        $text = $text.Trim()
        if (-not $text -or $text.StartsWith('#')) { continue }
        if ($text -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
            throw [System.ArgumentException]::new("The guest users file holds a line that is not a mail address: '$text'. File: $Path.")
        }
        $emails += $text.ToLowerInvariant()
    }
    return @($emails | Select-Object -Unique)
}

function Get-NeologikGroupByName {
    # Returns the security group with the exact display name, or $null.
    param([string]$DisplayName)
    $safe = $DisplayName -replace "'", "''"
    $filter = [uri]::EscapeDataString("displayName eq '$safe'")
    $items = @(Get-NeologikGraphCollection -Uri "$script:GraphV1/groups?`$filter=$filter&`$select=id,displayName")
    return (@($items) | Select-Object -First 1)
}

function Find-NeologikUserByEmail {
    # Returns the account whose mail address or user principal name is the address,
    # or $null. A guest account keeps the invited address in the mail property.
    param([string]$Email)
    $safe = $Email -replace "'", "''"
    $filter = [uri]::EscapeDataString("mail eq '$safe' or userPrincipalName eq '$safe'")
    $items = @(Get-NeologikGraphCollection -Uri "$script:GraphV1/users?`$filter=$filter&`$select=id,displayName,userPrincipalName,userType")
    return (@($items) | Select-Object -First 1)
}

function Set-NeologikSecurityGroup {
    <#
    Step 2 of the first run. The security groups of version 5 of the Neologik
    Platform exist in this tenant, the Neologik support accounts are guests of the
    tenant, each guest and the signed-in administrator are members of every group,
    and the two role groups of the Neologik Context Engine are known for step 3.
    The onboarding script does the same work for a new environment. An environment
    that was set up before version 5 has two of the four groups, so this step
    creates the other two, renames the user group of the Neologik Context Engine
    and fills the memberships. The step changes no group that already matches.
    #>
    $state = $script:State
    Write-Log 'Step 2 of 5: the security groups of the environment, the Neologik guest users and the memberships' -Level Info
    $graph = $script:GraphV1
    $suffix = " - $($state.ShortName)"
    $definitions = @(
        @{ Key = 'UserGroup'; Name = "Neologik User Group$suffix"
           Description = 'Default Neologik users group - assign to agent channels created in the NCE'; PreviousNames = @(); GivenId = '' },
        @{ Key = 'Contributors'; Name = "Neologik NCE Contributors$suffix"
           Description = 'NCE contributor role - create and change platform configuration in the Neologik Context Engine'
           PreviousNames = @("Neologik NCE User Group$suffix", "Neologik Harness User Group$suffix"); GivenId = $state.NceUserGroupId },
        @{ Key = 'Admins'; Name = "Neologik NCE Admins$suffix"
           Description = 'NCE admin role - full access including Blueprints, Audit and the Admin page'; PreviousNames = @(); GivenId = '' },
        @{ Key = 'AdminUserGroup'; Name = "Neologik Admin User Group$suffix"
           Description = 'Users who will administer and support the resources'; PreviousNames = @(); GivenId = $state.AdminGroupId }
    )

    # ----- the four groups --------------------------------------------------------
    $groups = @{}
    $present = @()
    $created = @()
    $renamed = @()
    $pendingCreate = @()
    $failed = @()
    foreach ($definition in $definitions) {
        $group = $null
        try {
            if ($definition.GivenId) {
                # The command names the group by id. The id decides, whatever the name.
                $group = Invoke-NeologikGraph -Method GET -Uri "$graph/groups/$($definition.GivenId)?`$select=id,displayName"
            }
            if (-not $group) { $group = Get-NeologikGroupByName -DisplayName $definition.Name }
            if (-not $group) {
                foreach ($previousName in $definition.PreviousNames) {
                    $group = Get-NeologikGroupByName -DisplayName $previousName
                    if ($group) { break }
                }
            }
        }
        catch {
            $reason = Get-NeologikErrorText $_
            Write-Log "  $($definition.Name): FAILED. The script could not read the group. $reason" -Level Error
            $failed += "$($definition.Name): $reason"
            continue
        }
        if ($group) {
            $groupId = [string](Get-NeologikProperty $group 'id' '')
            $currentName = [string](Get-NeologikProperty $group 'displayName' '')
            if ($currentName -ne $definition.Name) {
                # The group keeps the id and the members. The display name moves to the
                # version 5 name.
                if (Test-NeologikVerifyOnly) {
                    Write-Log "  '$currentName': WOULD RENAME to '$($definition.Name)'" -Level Warning
                    $renamed += "WOULD RENAME '$currentName'"
                }
                else {
                    try {
                        $body = @{ displayName = $definition.Name; description = $definition.Description } | ConvertTo-Json -Compress
                        $null = Invoke-NeologikGraph -Method PATCH -Uri "$graph/groups/$groupId" -Body $body
                        Write-Log "  Renamed the group '$currentName' to '$($definition.Name)'. The group keeps the id $groupId and the members" -Level Success
                        $renamed += $definition.Name
                    }
                    catch {
                        $reason = Get-NeologikErrorText $_
                        Write-Log "  '$currentName': FAILED. The script could not rename the group. $reason" -Level Error
                        $failed += "$($definition.Name): $reason"
                    }
                }
            }
            else {
                Write-Log "  '$($definition.Name)' exists, id $groupId" -Level Info
                $present += $definition.Name
            }
            $groups[$definition.Key] = @{ Id = $groupId; Name = $definition.Name }
            continue
        }
        if (Test-NeologikVerifyOnly) {
            Write-Log "  '$($definition.Name)': WOULD CREATE" -Level Warning
            $pendingCreate += $definition.Name
            continue
        }
        try {
            $body = @{
                displayName     = $definition.Name
                description     = $definition.Description
                mailEnabled     = $false
                securityEnabled = $true
                mailNickname    = ($definition.Name -replace '\s', '')
            } | ConvertTo-Json -Compress
            $newGroup = Invoke-NeologikGraph -Method POST -Uri "$graph/groups" -Body $body
            $groupId = [string](Get-NeologikProperty $newGroup 'id' '')
            Write-Log "  Created the group '$($definition.Name)', id $groupId" -Level Success
            $created += $definition.Name
            $groups[$definition.Key] = @{ Id = $groupId; Name = $definition.Name; New = $true }
        }
        catch {
            $reason = Get-NeologikErrorText $_
            $status = Get-NeologikHttpStatus $_
            if ($status -eq 403) { $reason = 'insufficient privileges. Sign in as a Global Administrator' }
            Write-Log "  '$($definition.Name)': FAILED. The script could not create the group. $reason" -Level Error
            $failed += "$($definition.Name): $reason"
        }
    }
    $parts = @()
    if ($present.Count -gt 0) { $parts += "Present: $($present.Count)" }
    if ($created.Count -gt 0) { $parts += "Created: $($created -join ', ')" }
    if ($renamed.Count -gt 0) { $parts += "Renamed: $($renamed -join ', ')" }
    if ($pendingCreate.Count -gt 0) { $parts += "WOULD CREATE: $($pendingCreate -join ', ')" }
    if ($failed.Count -gt 0) { $parts += "FAILED: $($failed -join '; ')" }
    Add-Summary 'Security groups' ($parts -join '. ')

    # The two role groups of the Neologik Context Engine, for step 3 and for the
    # summary file. The Admin User Group, for the permission reduction.
    if ($groups.ContainsKey('Contributors')) {
        $state.NceContributorsGroupId = $groups['Contributors'].Id
        if (-not $state.NceUserGroupId) { $state.NceUserGroupId = $groups['Contributors'].Id }
    }
    if ($groups.ContainsKey('Admins')) {
        $state.NceAdminsGroupId = $groups['Admins'].Id
        Add-Summary 'NCE Admins group' "Present, id $($groups['Admins'].Id). Neologik records this id for the environment"
    }
    elseif ($pendingCreate -contains "Neologik NCE Admins$suffix") {
        Add-Summary 'NCE Admins group' 'WOULD CREATE'
    }
    else {
        Add-Summary 'NCE Admins group' 'MISSING: the group could not be read or created. Read the item Security groups'
    }
    if ($groups.ContainsKey('AdminUserGroup') -and -not $state.AdminGroupId) { $state.AdminGroupId = $groups['AdminUserGroup'].Id }

    # ----- the Neologik guest users ---------------------------------------------
    $guestIds = @()
    if (-not $state.GuestUsersFile -or -not (Test-Path -LiteralPath $state.GuestUsersFile)) {
        $where = if ($state.GuestUsersFile) { $state.GuestUsersFile } else { 'NeologikGuestUsers.txt beside the script' }
        Write-Log "  The guest users file is not found: $where. The script cannot confirm the Neologik support accounts. Download the onboarding kit and run the script from the folder of the kit, or add -GuestUsersFile" -Level Warning
        Add-Summary 'Neologik guest users' 'SKIPPED: the guest users file is not found. Run the script from the folder of the onboarding kit, or add -GuestUsersFile'
    }
    else {
        $guestPresent = @()
        $guestInvited = @()
        $guestPending = @()
        $guestFailed = @()
        foreach ($email in @($state.GuestUserEmails)) {
            try {
                $user = Find-NeologikUserByEmail -Email $email
                if ($user) {
                    $guestIds += [string](Get-NeologikProperty $user 'id' '')
                    $guestPresent += $email
                    continue
                }
                if (Test-NeologikVerifyOnly) {
                    Write-Log "  $($email): WOULD INVITE as a guest" -Level Warning
                    $guestPending += $email
                    continue
                }
                $body = @{ invitedUserEmailAddress = $email; inviteRedirectUrl = 'https://portal.azure.com'; sendInvitationMessage = $true } | ConvertTo-Json -Compress
                $invitation = Invoke-NeologikGraph -Method POST -Uri "$graph/invitations" -Body $body
                $invitedId = [string](Get-NeologikProperty (Get-NeologikProperty $invitation 'invitedUser') 'id' '')
                Write-Log "  Invited $email as a guest, id $invitedId" -Level Success
                if ($invitedId) { $guestIds += $invitedId }
                $guestInvited += $email
            }
            catch {
                $reason = Get-NeologikErrorText $_
                Write-Log "  $($email): FAILED. $reason" -Level Error
                $guestFailed += "$($email): $reason"
            }
        }
        $parts = @()
        if ($guestPresent.Count -gt 0) { $parts += "Present: $($guestPresent.Count)" }
        if ($guestInvited.Count -gt 0) { $parts += "Invited: $($guestInvited -join ', ')" }
        if ($guestPending.Count -gt 0) { $parts += "WOULD INVITE: $($guestPending -join ', ')" }
        if ($guestFailed.Count -gt 0) { $parts += "FAILED: $($guestFailed -join '; ')" }
        if ($parts.Count -eq 0) { $parts += 'None listed in the guest users file' }
        Add-Summary 'Neologik guest users' ($parts -join '. ')
    }

    # ----- the memberships --------------------------------------------------------
    # Each guest and the signed-in administrator are direct members of every group.
    # The Neologik Context Engine reads direct memberships only.
    $members = @()
    foreach ($guestId in $guestIds) { $members += @{ Id = $guestId; Label = 'guest' } }
    $signedIn = [string](Get-NeologikProperty $state 'SignedInObjectId' '')
    if ($signedIn) { $members += @{ Id = $signedIn; Label = 'signed-in administrator' } }
    $membershipPresent = 0
    $membershipAdded = @()
    $membershipPending = 0
    $membershipFailed = @()
    $administratorGroups = @()
    foreach ($key in @('UserGroup', 'Contributors', 'Admins', 'AdminUserGroup')) {
        if (-not $groups.ContainsKey($key)) { continue }
        $group = $groups[$key]
        $existing = @()
        try {
            # A group created a moment ago takes time to replicate.
            $isNew = [bool](Get-NeologikProperty $group 'New' $false)
            $existing = @(Get-NeologikGraphCollection -Uri "$graph/groups/$($group.Id)/members?`$select=id" -RetryNotFound:$isNew |
                ForEach-Object { ([string](Get-NeologikProperty $_ 'id' '')).ToLowerInvariant() })
        }
        catch {
            $reason = Get-NeologikErrorText $_
            Write-Log "  '$($group.Name)': FAILED. The script could not read the members. $reason" -Level Error
            $membershipFailed += "$($group.Name): $reason"
            continue
        }
        foreach ($member in $members) {
            if ($existing -contains $member.Id.ToLowerInvariant()) {
                $membershipPresent++
                if ($member.Label -eq 'signed-in administrator') { $administratorGroups += $group.Name }
                continue
            }
            if (Test-NeologikVerifyOnly) {
                Write-Log "  '$($group.Name)': WOULD ADD the $($member.Label) $($member.Id)" -Level Warning
                $membershipPending++
                continue
            }
            try {
                $ref = @{ '@odata.id' = "$graph/directoryObjects/$($member.Id)" } | ConvertTo-Json -Compress
                $null = Invoke-NeologikGraph -Method POST -Uri "$graph/groups/$($group.Id)/members/`$ref" -Body $ref -RetryNotFound:$isNew
                Write-Log "  Added the $($member.Label) $($member.Id) to '$($group.Name)'" -Level Success
                $membershipAdded += "$($member.Label) to $($group.Name)"
                if ($member.Label -eq 'signed-in administrator') { $administratorGroups += $group.Name }
            }
            catch {
                $reason = Get-NeologikErrorText $_
                Write-Log "  '$($group.Name)': FAILED. The script could not add the $($member.Label) $($member.Id). $reason" -Level Error
                $membershipFailed += "$($group.Name): $reason"
            }
        }
    }
    $parts = @()
    if ($membershipPresent -gt 0) { $parts += "Present: $membershipPresent" }
    if ($membershipAdded.Count -gt 0) { $parts += "Added: $($membershipAdded -join ', ')" }
    if ($membershipPending -gt 0) { $parts += "WOULD ADD: $membershipPending membership(s)" }
    if ($membershipFailed.Count -gt 0) { $parts += "FAILED: $($membershipFailed -join '; ')" }
    if ($parts.Count -eq 0) { $parts += 'Not checked: no guest and no signed-in account to check' }
    Add-Summary 'Group memberships' ($parts -join '. ')
    if (-not $signedIn) {
        Add-Summary 'Signed-in administrator membership' 'UNKNOWN: the script could not read the id of the signed-in account. Add the account to the group Neologik NCE Admins in the Microsoft Entra admin centre'
    }
    elseif ($membershipPending -gt 0 -and $administratorGroups.Count -lt $groups.Count) {
        Add-Summary 'Signed-in administrator membership' 'WOULD ADD'
    }
    elseif ($administratorGroups.Count -ge $groups.Count -and $groups.Count -gt 0) {
        Add-Summary 'Signed-in administrator membership' "Present in every group ($($administratorGroups.Count))"
    }
    else {
        Add-Summary 'Signed-in administrator membership' 'FAILED: the signed-in account is not a member of every group. Read the item Group memberships'
    }
}

function Set-NeologikSignInGroupAssignment {
    # Steps 3 and 4: the assignment of the two role groups of the Neologik Context
    # Engine to the Platform Sign-in application, and the check of the administrator
    # consent.
    $state = $script:State
    Write-Log 'Step 3 of 5: the assignment of the role groups of the Neologik Context Engine to the Platform Sign-in application' -Level Info
    $adminsGroupId = [string](Get-NeologikProperty $state 'NceAdminsGroupId' '')
    if (-not $state.SignInAppClientId -or -not $state.NceUserGroupId) {
        Write-Log '  SKIPPED. The command gives no SignInAppClientId or no NceUserGroupId. The command from Neologik holds both values' -Level Warning
        Add-Summary 'User group assignment' 'SKIPPED: the command gives no SignInAppClientId or no NceUserGroupId'
        if ($adminsGroupId) { Add-Summary 'Admin group assignment' 'SKIPPED: the command gives no SignInAppClientId' }
        return
    }
    $signInSp = $null
    try {
        $signInSp = @(Get-MgServicePrincipal -Filter "appId eq '$($state.SignInAppClientId)'" -ErrorAction Stop) | Select-Object -First 1
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  The Platform Sign-in application: FAILED. The script could not read the Platform Sign-in application. $reason" -Level Error
        Add-Summary 'User group assignment' "FAILED: $reason"
        if ($adminsGroupId) { Add-Summary 'Admin group assignment' "FAILED: $reason" }
        Add-Summary 'Administrator consent' 'SKIPPED: the script could not read the Platform Sign-in application'
        return
    }
    if (-not $signInSp) {
        Write-Log "  This tenant holds no service principal of the Platform Sign-in application with the client id $($state.SignInAppClientId). Ask Neologik to confirm the client id" -Level Error
        Add-Summary 'User group assignment' 'MISSING: the tenant holds no Platform Sign-in application with this client id'
        if ($adminsGroupId) { Add-Summary 'Admin group assignment' 'MISSING: the tenant holds no Platform Sign-in application with this client id' }
        Add-Summary 'Administrator consent' 'SKIPPED: the tenant holds no Platform Sign-in application with this client id'
        return
    }
    Write-Log "  Platform Sign-in application: '$($signInSp.DisplayName)'" -Level Info
    # The user group of the command (the contributors), then the NCE Admins group that
    # step 2 found or created. Each assignment is independent of the other.
    $targets = @(@{ Item = 'User group assignment'; GroupId = $state.NceUserGroupId; Label = 'the user group'; Parameter = '-NceUserGroupId' })
    if ($adminsGroupId -and $adminsGroupId -ne $state.NceUserGroupId) {
        $targets += @{ Item = 'Admin group assignment'; GroupId = $adminsGroupId; Label = 'the NCE Admins group'; Parameter = 'the NCE Admins group' }
    }
    foreach ($target in $targets) {
        try {
            $assignments = @(Get-MgGroupAppRoleAssignment -GroupId $target.GroupId -All -ErrorAction Stop |
                Where-Object { $_.ResourceId -eq $signInSp.Id })
            if ($assignments.Count -gt 0) {
                Write-Log "  $($target.Label) is already assigned to the Platform Sign-in application" -Level Success
                Add-Summary $target.Item 'Already assigned'
            }
            elseif (Test-NeologikVerifyOnly) {
                Add-NeologikPendingChange $target.Item 'ASSIGN'
            }
            else {
                Invoke-NeologikWrite -Command 'New-MgGroupAppRoleAssignment' -Parameters @{
                    GroupId = $target.GroupId; PrincipalId = $target.GroupId; ResourceId = $signInSp.Id
                    AppRoleId = '00000000-0000-0000-0000-000000000000'
                } | Out-Null
                Write-Log "  The script assigned $($target.Label) to the Platform Sign-in application. The sign-in token now holds the groups claim" -Level Success
                Add-Summary $target.Item 'Assigned'
            }
        }
        catch {
            $reason = Get-NeologikErrorText $_
            $status = Get-NeologikHttpStatus $_
            if ($status -eq 404) {
                Write-Log "  This tenant holds no group with the id $($target.GroupId). Check the value of $($target.Parameter)" -Level Error
                Add-Summary $target.Item "MISSING: the tenant holds no group with this id. Check the value of $($target.Parameter)"
            }
            elseif ($status -eq 403) {
                Write-Log "  Microsoft Graph refused the assignment of $($target.Label). Sign in as a Global Administrator" -Level Error
                Add-Summary $target.Item 'FAILED: insufficient privileges. Sign in as a Global Administrator'
            }
            else {
                Write-Log "  The assignment of $($target.Label): FAILED. $reason" -Level Error
                Add-Summary $target.Item "FAILED: $reason"
            }
        }
    }
    try {
        $group = Get-MgGroup -GroupId $state.NceUserGroupId -ErrorAction Stop
        $memberCount = @(Get-MgGroupMember -GroupId $state.NceUserGroupId -All -ErrorAction Stop).Count
        if ($memberCount -eq 0) {
            Write-Log "  WARNING: the group '$($group.DisplayName)' has no members. A user must be a direct member of the group to sign in. A member of a nested group cannot sign in" -Level Warning
        }
        else {
            Write-Log "  The group '$($group.DisplayName)' has $memberCount direct member(s)" -Level Info
        }
    }
    catch {
        Write-Log "  The script could not read the members of the group. $(Get-NeologikErrorText $_). Check that the group has direct members" -Level Warning
    }

    # ----- Step 4: administrator consent ----------------------------------
    Write-Log 'Step 4 of 5: the administrator consent of the Platform Sign-in application' -Level Info
    try {
        $grants = @(Get-MgServicePrincipalOauth2PermissionGrant -ServicePrincipalId $signInSp.Id -All -ErrorAction Stop |
            Where-Object { $_.ConsentType -eq 'AllPrincipals' })
        if ($grants.Count -gt 0) {
            Write-Log '  The administrator consent for the whole tenant exists' -Level Success
            Add-Summary 'Administrator consent' 'Present'
        }
        else {
            $consentUrl = "https://login.microsoftonline.com/$($state.TenantId)/adminconsent?client_id=$($state.SignInAppClientId)"
            Write-Log '  The administrator consent for the whole tenant does NOT exist. Open this address in a browser, sign in as a Global Administrator and give the consent:' -Level Warning
            Write-Host ''
            Write-Host "    $consentUrl" -ForegroundColor Cyan
            Write-Host ''
            Write-Log '  Then run the script again to confirm the consent' -Level Warning
            Add-Summary 'Administrator consent' 'MISSING: the script printed the consent address'
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  The administrator consent: FAILED. The script could not read the consent. $reason" -Level Error
        Add-Summary 'Administrator consent' "FAILED: $reason"
    }
}

function Get-NeologikSharePointApplication {
    <#
    Finds the service principal of the SharePoint application of this environment.
    The function looks first for the client id that the command names. One tenant
    can hold several environments. The function then looks for the exact name of the
    SharePoint application of this environment. The function last looks for the start
    of the name, and accepts the result only when one application matches. The result
    records the service principal, and whether the tenant holds several candidates.
    #>
    $state = $script:State
    $graph = $script:GraphV1
    $result = @{ Sp = $null; Ambiguous = $false }
    $clientId = [string](Get-NeologikProperty $state 'SharePointAppClientId' '')
    if ($clientId) {
        $result.Sp = @(Get-NeologikGraphCollection -Uri "$graph/servicePrincipals?`$filter=appId eq '$clientId'&`$select=id,appId,displayName") | Select-Object -First 1
        if ($result.Sp) { return $result }
    }
    if ($state.ShortName) {
        $exact = ("$script:SharePointAppDisplayNamePrefix$($state.ShortName)") -replace "'", "''"
        $result.Sp = @(Get-NeologikGraphCollection -Uri "$graph/servicePrincipals?`$filter=displayName eq '$exact'&`$select=id,appId,displayName") | Select-Object -First 1
    }
    if (-not $result.Sp) {
        $prefix = $script:SharePointAppDisplayNamePrefix -replace "'", "''"
        $candidates = @(Get-NeologikGraphCollection -Uri "$graph/servicePrincipals?`$filter=startswith(displayName,'$prefix')&`$select=id,appId,displayName")
        if ($candidates.Count -eq 1) { $result.Sp = $candidates[0] }
        elseif ($candidates.Count -gt 1) { $result.Ambiguous = $true }
    }
    return $result
}

function Get-NeologikEarlierSharePointApplication {
    <#
    Finds each earlier SharePoint application of Neologik that holds a SharePoint
    permission of Microsoft Graph. An earlier SharePoint application is a service
    principal whose name begins 'Neologik' and holds the word 'SharePoint'. The
    function leaves out the SharePoint application of every environment. The result
    lists each earlier application with the SharePoint permissions that the
    application holds.
    #>
    param([string]$ExcludeId)
    $graph = $script:GraphV1
    $graphSp = $script:State.GraphSp
    $siteRoles = @{}
    foreach ($role in @($graphSp.AppRoles | Where-Object { [string]$_.Value -like 'Sites.*' })) {
        $siteRoles[[string]$role.Id] = [string]$role.Value
    }
    $earlier = @()
    if ($siteRoles.Count -eq 0) { return $earlier }
    foreach ($candidate in @(Get-NeologikGraphCollection -Uri "$graph/servicePrincipals?`$filter=startswith(displayName,'Neologik')&`$select=id,appId,displayName")) {
        $name = [string](Get-NeologikProperty $candidate 'displayName' '')
        $id = [string](Get-NeologikProperty $candidate 'id' '')
        if ($id -eq $ExcludeId -or $name -notmatch '(?i)sharepoint' -or $name -like "$script:SharePointAppDisplayNamePrefix*") { continue }
        $held = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $id -All -ErrorAction Stop |
            Where-Object { $_.ResourceId -eq $graphSp.Id -and $siteRoles.ContainsKey([string]$_.AppRoleId) } |
            ForEach-Object { $siteRoles[[string]$_.AppRoleId] })
        if ($held.Count -gt 0) {
            $earlier += @{ Name = $name; AppId = [string](Get-NeologikProperty $candidate 'appId' ''); Roles = @($held | Sort-Object -Unique) }
        }
    }
    return $earlier
}

function Test-NeologikSharePointConsent {
    <#
    Checks the consent for Sites.Selected of the SharePoint application of this
    environment. A consent belongs to one application. An earlier SharePoint
    application of Neologik that holds a SharePoint permission shows that the
    solution uses SharePoint ingestion. The function then grants Sites.Selected to
    the SharePoint application of this environment. -IngestionRecorded states that
    a file records SharePoint ingestion. The function then prints the consent
    address when no application holds a SharePoint permission.
    #>
    param([switch]$IngestionRecorded)
    $state = $script:State
    $graphSp = $state.GraphSp
    $item = 'SharePoint Sites.Selected consent'
    try {
        $found = Get-NeologikSharePointApplication
        if ($found.Ambiguous) {
            Write-Log '  This tenant holds several SharePoint applications. The script cannot choose without the short name of the environment. Add -SolutionShortName or -ConfigurationFile to the command' -Level Warning
            Add-Summary $item 'UNKNOWN: the tenant holds several SharePoint applications. Add -SolutionShortName or -ConfigurationFile to the command'
            return
        }
        $spApp = $found.Sp
        $spName = [string](Get-NeologikProperty $spApp 'displayName' '')
        $spId = [string](Get-NeologikProperty $spApp 'id' '')
        $sitesSelected = Get-NeologikGraphAppRole -RoleName 'Sites.Selected'
        if ($spApp -and $sitesSelected) {
            $held = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $spId -All -ErrorAction Stop |
                Where-Object { $_.ResourceId -eq $graphSp.Id -and $_.AppRoleId -eq $sitesSelected.Id })
            if ($held.Count -gt 0) {
                Write-Log "  '$spName' holds Sites.Selected and the consent exists. A site administrator grants access to each site separately" -Level Success
                Add-Summary $item 'Present'
                return
            }
        }
        $earlier = @(Get-NeologikEarlierSharePointApplication -ExcludeId $spId)
        if ($earlier.Count -gt 0) {
            $earlierNames = @($earlier | ForEach-Object { "'$($_.Name)'" }) -join ', '
            Write-Log "  An earlier SharePoint application of Neologik holds a SharePoint permission: $earlierNames. The solution uses SharePoint ingestion" -Level Info
            if (-not $spApp) {
                Write-Log '  The SharePoint application of this environment does not exist. The deployment by Neologik creates the SharePoint application. Run the script again after the deployment' -Level Warning
                Add-Summary $item "MISSING: the SharePoint application of this environment does not exist. The earlier application $earlierNames holds a SharePoint permission. Run the script again after the deployment by Neologik"
                return
            }
            if (-not $sitesSelected) {
                Write-Log "  Microsoft Graph does not publish the permission 'Sites.Selected' in this cloud. Report this message to Neologik" -Level Warning
                Add-Summary $item 'NOT FOUND: report to Neologik'
                return
            }
            Write-Log "  '$spName' does not hold Sites.Selected. A consent belongs to one application. The consent of the earlier application does not reach '$spName'" -Level Info
            if (Test-NeologikVerifyOnly) {
                Add-NeologikPendingChange $item "GRANT Sites.Selected to '$spName'"
                return
            }
            Invoke-NeologikWrite -Command 'New-MgServicePrincipalAppRoleAssignment' -Parameters @{
                ServicePrincipalId = $spId; PrincipalId = $spId; ResourceId = $graphSp.Id; AppRoleId = $sitesSelected.Id
            } | Out-Null
            Write-Log "  Sites.Selected: granted to '$spName'. A site administrator grants access to each site separately" -Level Success
            Add-Summary $item "Granted to '$spName'"
            return
        }
        if (-not $IngestionRecorded) {
            Write-Log '  No SharePoint application of Neologik holds a SharePoint permission. The solution does not use SharePoint ingestion. The script grants nothing' -Level Info
            Add-Summary $item 'Not needed. No SharePoint application of Neologik holds a SharePoint permission'
            return
        }
        if (-not $spApp) {
            Write-Log '  This tenant holds no SharePoint application. The deployment by Neologik creates the SharePoint application' -Level Warning
            Add-Summary $item 'MISSING: the tenant holds no SharePoint application'
            return
        }
        $spConsentUrl = "https://login.microsoftonline.com/$($state.TenantId)/adminconsent?client_id=$(Get-NeologikProperty $spApp 'appId')"
        Write-Log '  The consent for Sites.Selected does NOT exist. Open this address in a browser, sign in as a Global Administrator and give the consent:' -Level Warning
        Write-Host ''
        Write-Host "    $spConsentUrl" -ForegroundColor Cyan
        Write-Host ''
        Add-Summary $item 'MISSING: the script printed the consent address'
    }
    catch {
        $reason = Get-NeologikErrorText $_
        if (Test-NeologikPrivilegeError $_) { $reason = 'insufficient privileges. Sign in as a Global Administrator' }
        Write-Log "  The consent for Sites.Selected: FAILED. $reason" -Level Error
        Add-Summary $item "FAILED: $reason"
    }
}

function Test-NeologikPreWindowSharePointConsent {
    <#
    Step 4a of the first run. The configuration file can record whether the
    solution uses SharePoint ingestion, in the field "SharePointIngestion". When
    the configuration file does not hold the field, the script reads the SharePoint
    permissions in the directory. An earlier SharePoint application of Neologik
    that holds a SharePoint permission shows that the solution uses SharePoint
    ingestion.
    #>
    $state = $script:State
    Write-Log 'Step 4a of 5: the consent of the SharePoint application for Sites.Selected' -Level Info
    if (-not $state.Config -or -not (Test-NeologikProperty $state.Config 'SharePointIngestion')) {
        Write-Log '  No file records whether the solution uses SharePoint ingestion. The script reads the SharePoint permissions in the directory' -Level Info
        Test-NeologikSharePointConsent
        return
    }
    if ([bool](Get-NeologikProperty $state.Config 'SharePointIngestion' $false)) {
        Write-Log '  The solution uses SharePoint ingestion. The script checks the consent for Sites.Selected' -Level Info
        Test-NeologikSharePointConsent -IngestionRecorded
    }
    else {
        Write-Log '  The solution does not use SharePoint ingestion. The script does not check the consent for Sites.Selected' -Level Info
        Add-Summary 'SharePoint Sites.Selected consent' 'Not needed'
    }
}

function Set-NeologikPlatformAppOwnership {
    <#
    Step 4b of the first run. The deployment identity must own each application
    registration that the Neologik Platform manages in this tenant, and the service
    principal of each. Each application registration must hold the unique name by
    which the deployment finds the application registration. The function changes
    nothing else on an application registration.
    #>
    $state = $script:State
    $deploySp = $state.DeploySp
    $graph = $script:GraphV1
    Write-Log 'Step 4b of 5: the ownership of the application registrations by the deployment identity' -Level Info
    $shortName = $state.ShortName
    if (-not $shortName) {
        Write-Log '  The command gives no SolutionShortName. The script cannot find the application registrations' -Level Warning
        Add-Summary 'Application registrations' 'SKIPPED: the command gives no SolutionShortName'
        return
    }
    $select = 'id,appId,displayName,uniqueName,passwordCredentials'
    $targets = @()
    $listed = @{}

    # The client id names each application registration: the Platform Sign-in
    # application, the SharePoint application where the environment has one, and each
    # agent registration. The function never chooses an application registration by
    # display name.
    $entries = @(@{ AppId = $state.SignInAppClientId; Kind = 'Platform Sign-in application'; Item = 'Platform Sign-in application registration'
            ExpectedUniqueName = "sp-admin-$($state.SolutionName)"; OwnSecret = 'auth'; RemovesAll = $true })
    if ($state.SharePointAppClientId) {
        $entries += @{ AppId = $state.SharePointAppClientId; Kind = 'SharePoint application'; Item = 'SharePoint application registration'
            ExpectedUniqueName = "sp-neologik-sharepoint-$shortName"; OwnSecret = 'sharepoint-access'; RemovesAll = $false }
    }
    else {
        Write-Log '  The command gives no SharePointAppClientId. The deployment creates the SharePoint application when the environment uses SharePoint ingestion' -Level Info
        Add-Summary 'SharePoint application registration' 'Not listed. The deployment creates the SharePoint application when the environment uses SharePoint ingestion'
    }
    if ($state.BotAppClientIds.Count -eq 0) {
        Write-Log '  The command gives no BotAppClientIds. The script changes no agent registration. The command from Neologik lists each agent registration' -Level Warning
        Add-Summary 'Agent registrations' 'None listed. The script changes no agent registration. The command from Neologik lists each agent registration'
    }
    foreach ($botId in $state.BotAppClientIds) {
        $entries += @{ AppId = $botId; Kind = 'Agent registration'; Item = "Agent registration $botId"; ExpectedUniqueName = ''; OwnSecret = 'auth'; RemovesAll = $true }
    }
    foreach ($entry in $entries) {
        $listed[$entry.AppId.ToLowerInvariant()] = $true
        try {
            $app = @(Get-NeologikGraphCollection -Uri "$graph/applications?`$filter=appId eq '$($entry.AppId)'&`$select=$select") | Select-Object -First 1
            if ($app) {
                $targets += @{ App = $app; Kind = $entry.Kind; ExpectedUniqueName = $entry.ExpectedUniqueName; OwnSecret = $entry.OwnSecret; RemovesAll = $entry.RemovesAll }
            }
            else {
                Write-Log "  $($entry.Kind): this tenant holds no application registration with the client id $($entry.AppId). The deployment identity cannot own an application registration of another tenant" -Level Error
                Add-Summary $entry.Item 'NOT FOUND: this tenant holds no application registration with this client id. Ask Neologik to confirm the client id. The deployment identity cannot own an application registration of another tenant'
            }
        }
        catch {
            Add-Summary $entry.Item "FAILED: $(Get-NeologikErrorText $_)"
        }
    }
    # The function reports every other application registration in this tenant whose
    # name begins 'Neologik', and changes none. The agent identity blueprint has a
    # separate step.
    try {
        foreach ($found in @(Get-NeologikGraphCollection -Uri "$graph/applications?`$filter=startswith(displayName,'Neologik')&`$select=id,appId,displayName")) {
            $name = [string](Get-NeologikProperty $found 'displayName' '')
            $appId = [string](Get-NeologikProperty $found 'appId' '')
            if ($listed.ContainsKey($appId.ToLowerInvariant()) -or $name -like 'Neologik Agent Blueprint*' -or $name -like 'Neologik Autonomous Agent Blueprint*') { continue }
            Write-Log "  The command does not name '$name', client id $appId. The script does not change the application registration" -Level Info
            Add-Summary "Registration not on the list: '$name'" "Review: the command does not name $appId. The script did not change the application registration. Tell Neologik when the Neologik Platform uses the application registration"
        }
    }
    catch {
        Add-Summary 'Search for other registrations' "FAILED: $(Get-NeologikErrorText $_)"
    }
    Write-Log "  Application registrations to check: $($targets.Count)" -Level Info

    foreach ($target in $targets) {
        $app = $target.App
        $objectId = [string](Get-NeologikProperty $app 'id' '')
        $appId = [string](Get-NeologikProperty $app 'appId' '')
        $displayName = [string](Get-NeologikProperty $app 'displayName' '')
        $prefix = "Registration '$displayName'"
        Write-Log "  $($target.Kind) '$displayName', client id $appId" -Level Info

        # The owner of the application registration.
        Set-NeologikDirectoryObjectOwner -Item "$prefix owner" -Uri "$graph/applications/$objectId" -OwnerId $deploySp.Id

        # The owner of the service principal. The deployment creates a missing service
        # principal.
        try {
            $principal = @(Get-NeologikGraphCollection -Uri "$graph/servicePrincipals?`$filter=appId eq '$appId'&`$select=id") | Select-Object -First 1
            if ($principal) {
                Set-NeologikDirectoryObjectOwner -Item "$prefix service principal owner" -Uri "$graph/servicePrincipals/$([string](Get-NeologikProperty $principal 'id' ''))" -OwnerId $deploySp.Id
            }
            else {
                Add-Summary "$prefix service principal owner" 'Not present. The deployment creates the service principal'
            }
        }
        catch {
            Add-Summary "$prefix service principal owner" "FAILED: $(Get-NeologikErrorText $_)"
        }

        # uniqueName: the deployment finds the application registration by this value.
        $current = [string](Get-NeologikProperty $app 'uniqueName' '')
        $expected = [string]$target.ExpectedUniqueName
        $item = "$prefix unique name"
        try {
            if ($expected) {
                if ($current -eq $expected) { Add-Summary $item 'Already set' }
                elseif (-not $current) {
                    if (Test-NeologikVerifyOnly) { Add-NeologikPendingChange $item "SET $expected" }
                    else {
                        $null = Invoke-NeologikGraph -Method PATCH -Uri "$graph/applications/$objectId" -Body (@{ uniqueName = $expected } | ConvertTo-Json -Compress)
                        Write-Log "  The script set the unique name of '$displayName' to '$expected'" -Level Success
                        Add-Summary $item "Set: $expected"
                    }
                }
                else {
                    Write-Log "  The unique name of '$displayName' is '$current'. The deployment expects '$expected'" -Level Error
                    Add-Summary $item "FAILED: the unique name is '$current'. The deployment expects '$expected'. Agree the unique name with Neologik before the upgrade"
                }
            }
            elseif ($current) { Add-Summary $item "Already set: $current" }
            else { Add-Summary $item 'Not required. The deployment finds an agent registration by the client id' }
        }
        catch {
            Add-Summary $item "FAILED: $(Get-NeologikErrorText $_)"
        }

        # The client secrets that the deployment did not create.
        $foreign = @(@(Get-NeologikProperty $app 'passwordCredentials' @()) | Where-Object {
                [string](Get-NeologikProperty $_ 'displayName' '') -ne $target.OwnSecret })
        $item = "$prefix client secrets"
        if ($foreign.Count -eq 0) { Add-Summary $item 'None from another source' }
        else {
            $names = @($foreign | ForEach-Object { $n = [string](Get-NeologikProperty $_ 'displayName' ''); if ($n) { $n } else { 'no name' } }) -join ', '
            if ($target.RemovesAll) {
                Write-Log "  '$displayName' holds $($foreign.Count) client secret(s) that the deployment did not create: $names. The deployment removes every client secret of this application registration" -Level Warning
                Add-Summary $item "PENDING: $($foreign.Count) client secret(s) that the deployment did not create: $names. The deployment removes every client secret of this application registration. Confirm that nothing else uses the client secret(s)"
            }
            else {
                Write-Log "  '$displayName' holds $($foreign.Count) client secret(s) that the deployment did not create: $names. The client secret(s) stay unchanged" -Level Info
                Add-Summary $item "Review: $($foreign.Count) client secret(s) that the deployment did not create: $names. The client secret(s) stay unchanged"
            }
        }
    }
}

function Set-NeologikDirectoryObjectOwner {
    # Adds one owner to an application registration or to a service principal. A run
    # with -Verify records the change. The caller gives the name of the summary item.
    param([Parameter(Mandatory)][string]$Item, [Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string]$OwnerId)
    $graph = $script:GraphV1
    try {
        $owners = @(Get-NeologikGraphCollection -Uri "$Uri/owners?`$select=id")
        if (@($owners | ForEach-Object { [string](Get-NeologikProperty $_ 'id' '') }) -contains $OwnerId) {
            Add-Summary $Item 'Already an owner'
            return
        }
        if (Test-NeologikVerifyOnly) { Add-NeologikPendingChange $Item 'ADD'; return }
        $ref = @{ '@odata.id' = "$graph/directoryObjects/$OwnerId" } | ConvertTo-Json -Compress
        try {
            $null = Invoke-NeologikGraph -Method POST -Uri "$Uri/owners/`$ref" -Body $ref
            Write-Log "  ${Item}: added" -Level Success
            Add-Summary $Item 'Added'
        }
        catch {
            if ((Get-NeologikErrorText $_) -match '(?i)already exist') { Add-Summary $Item 'Already an owner' }
            else { throw }
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  ${Item}: FAILED. $reason" -Level Error
        Add-Summary $Item "FAILED: $reason"
    }
}

function Set-NeologikAgentUserGrant {
    # Step 6 of the later run: the grants to agent users, the application permissions
    # and the check of the SharePoint consent.
    $state = $script:State
    $grantsFile = $state.AgentGrants
    Write-Log 'Step 6 of 7: the grants to agent users from the agent grants file' -Level Info
    foreach ($entry in @(Get-NeologikProperty $grantsFile 'grants' @())) {
        $kind = [string](Get-NeologikProperty $entry 'kind' 'agent')
        $name = [string](Get-NeologikProperty $entry 'name' 'no name')
        if ([string](Get-NeologikProperty $entry 'status' '') -ne 'ready') {
            Write-Log "  $kind '$name': the agent grants file marks the entry as not ready. Ask Neologik for a new agent grants file" -Level Warning
            Add-Summary "Grant to agent user: $kind $name" 'SKIPPED: the agent grants file marks the entry as not ready'
            continue
        }
        $scopes = @(@(Get-NeologikProperty $entry 'scopes' @()) | ForEach-Object { [string]$_ } | Where-Object { $_.Trim() })
        Grant-NeologikAgentUserAccess -Kind $kind -Name $name `
            -IdentityClientId ([string](Get-NeologikProperty $entry 'identityClientId')) `
            -AgentUserObjectId ([string](Get-NeologikProperty $entry 'agentUserObjectId')) `
            -Scopes $scopes
    }
    foreach ($role in @(Get-NeologikProperty $grantsFile 'componentGraphRoles' @())) {
        $app = [string](Get-NeologikProperty $role 'app' 'no name')
        $roleName = [string](Get-NeologikProperty $role 'roleName' '')
        $resource = [string](Get-NeologikProperty $role 'resource' '')
        $identityName = [string](Get-NeologikProperty $role 'identityName' '')
        if ($resource -and $resource -ne 'graph') {
            Write-Log "  $app '$roleName': the role belongs to $resource, not to Microsoft Graph. An administrator grants the role in $resource" -Level Warning
            Add-Summary "App $app permission: $roleName" "SKIPPED: the role belongs to $resource, not to Microsoft Graph"
            continue
        }
        if (-not $roleName -or -not $identityName) {
            Write-Log "  ${app}: an entry in the agent grants file lacks roleName or identityName. Ask Neologik for a new agent grants file" -Level Warning
            Add-Summary "App $app permission: $roleName" 'SKIPPED: the entry in the agent grants file is incomplete'
            continue
        }
        Grant-NeologikComponentGraphRole -App $app -IdentityName $identityName `
            -RoleName $roleName -ScopeType ([string](Get-NeologikProperty $role 'scopeType' ''))
    }
    if ([bool](Get-NeologikProperty $grantsFile 'sharePointIngestion' $false)) {
        Write-Log '  The solution uses SharePoint ingestion. The script checks the consent for Sites.Selected' -Level Info
        Test-NeologikSharePointConsent -IngestionRecorded
    }
    else {
        Write-Log '  The solution does not use SharePoint ingestion. The script does not check the consent for Sites.Selected' -Level Info
        Add-Summary 'SharePoint Sites.Selected consent' 'Not needed'
    }
}

function Set-NeologikMailboxGrant {
    <#
    Step 7 of the later run: the Exchange Online mailbox grants of the email
    channels. The function also removes the role assignments of each identity that
    the environment has stopped using. An identity that the file lists under
    adoptedIdentityAppIds keeps the role assignments.
    #>
    $state = $script:State
    Write-Log 'Step 7 of 7: the Exchange Online mailbox grants of the email channels' -Level Info
    $legacyToRemove = @()
    foreach ($legacyAppId in $state.RemoveLegacyGrantAppIds) {
        if ($state.AdoptedIdentityAppIds -contains $legacyAppId) {
            Write-Log "  Identity ${legacyAppId}: an email channel still uses the identity. The script keeps the role assignments" -Level Success
            Add-Summary "Mailbox grant to remove: $legacyAppId" 'Kept. An email channel still uses the identity'
            continue
        }
        $legacyToRemove += $legacyAppId
    }
    $items = @()
    foreach ($grant in $state.MailboxGrants) { $items += "Mailbox grant: $($grant.Mailbox) for $($grant.DisplayName)" }
    foreach ($legacyAppId in $legacyToRemove) { $items += "Mailbox grant to remove: $legacyAppId" }
    if ($items.Count -eq 0) {
        Write-Log '  The run has no mailbox grant to apply and no identity to remove. The script does not contact Exchange Online' -Level Info
        return
    }
    if (-not (Import-NeologikModuleSet -Names @('ExchangeOnlineManagement') -MinimumVersion $script:ExchangeModuleMinimumVersion `
                -InstallHint 'Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force')) {
        foreach ($item in $items) { Add-Summary $item 'SKIPPED: the Exchange Online module is not available' }
        return
    }
    # The order of the methods: the browser sign-in of the Exchange Online module, then the
    # device code of the Exchange Online module. Many organisations block the device code
    # with a Conditional Access policy, so the device code is not the first method.
    $connected = $false
    if (Test-NeologikDesktop) {
        try {
            Write-Log '  The script signs in to Exchange Online in the browser of this computer. Sign in as an Exchange Administrator or as a Global Administrator' -Level Info
            $exchangeParameters = @{ ShowBanner = $false; ErrorAction = 'Stop' }
            $signInAccount = [string](Get-NeologikProperty $state 'SignInAccount' '')
            if ($signInAccount) { $exchangeParameters['UserPrincipalName'] = $signInAccount }
            Connect-ExchangeOnline @exchangeParameters
            $connected = $true
        }
        catch {
            Write-Log "  The sign-in to Exchange Online in the browser did not complete. $(Get-NeologikErrorText $_). The script tries a device code" -Level Warning
        }
    }
    if (-not $connected) {
        try {
            Write-Log '  The script signs in to Exchange Online with a device code. Sign in as an Exchange Administrator or as a Global Administrator' -Level Info
            Connect-ExchangeOnline -Device -ShowBanner:$false -ErrorAction Stop
            $connected = $true
        }
        catch {
            Write-Log "  The sign-in to Exchange Online failed. $(Get-NeologikErrorText $_)" -Level Error
            Write-ActionRequired "The sign-in to Exchange Online did not complete. The script tried the browser of this computer and a device code.`nRun the script again on a computer with a desktop and a browser. Sign in as an Exchange Administrator or as a Global Administrator of tenant $($state.TenantId)."
            foreach ($item in $items) { Add-Summary $item 'SKIPPED: the sign-in to Exchange Online failed' }
            return
        }
    }
    try {
        try {
            $organisation = Get-OrganizationConfig -ErrorAction Stop
            if ([bool](Get-NeologikProperty $organisation 'IsDehydrated' $false)) {
                if (Test-NeologikVerifyOnly) {
                    Add-NeologikPendingChange 'Exchange organisation customisation' 'ENABLE'
                }
                else {
                    Write-Log '  The script enables organisation customisation in Exchange Online. Exchange Online needs the setting once. The script then waits 60 seconds' -Level Info
                    Invoke-NeologikWrite -Command 'Enable-OrganizationCustomization' | Out-Null
                    Start-Sleep -Seconds 60
                }
            }
        }
        catch {
            Write-Log "  The script could not read the organisation customisation of Exchange Online. $(Get-NeologikErrorText $_). The script continues" -Level Warning
        }
        foreach ($grant in $state.MailboxGrants) {
            Grant-NeologikMailboxAccess -IdentityAppId $grant.IdentityAppId -IdentityObjectId $grant.IdentityObjectId `
                -Mailbox $grant.Mailbox -DisplayName $grant.DisplayName
        }
        foreach ($legacyAppId in $legacyToRemove) {
            Remove-NeologikMailboxAccess -LegacyAppId $legacyAppId
        }
    }
    finally {
        if ($connected) {
            try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction Stop | Out-Null } catch { Write-Verbose "The script ignores the error. $($_.Exception.Message)" }
        }
    }
}

# ----- First run, step 4: permission reduction ----------------------------------

function Get-NeologikTokenAccountId {
    # Returns the account that an access token names. The function reads the claim upn,
    # unique_name or preferred_username. Connect-AzAccount needs the account with
    # -AccessToken. Returns '' when the token is not a JWT that the function can read.
    param([string]$Token)
    try {
        $parts = $Token.Split('.')
        if ($parts.Count -lt 2) { return '' }
        $payload = $parts[1].Replace('-', '+').Replace('_', '/')
        switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
        $claims = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload)) | ConvertFrom-Json
        foreach ($name in @('upn', 'unique_name', 'preferred_username', 'appid')) {
            $value = [string](Get-NeologikProperty $claims $name '')
            if ($value) { return $value }
        }
        return ''
    }
    catch { return '' }
}

function Connect-NeologikAzure {
    # Signs in to Azure, to read and write role assignments. Returns $true. Returns
    # $false after the function prints what to do. With -UseAzureCliToken the Azure CLI
    # session gives the token for Azure Resource Manager. The same Azure CLI session
    # signed in to Microsoft Graph. Without -UseAzureCliToken the function uses the
    # browser sign-in, then the device code. Each method requests the multi-factor
    # authentication claim that a role assignment needs.
    $state = $script:State
    if ($state.UseAzureCliToken) {
        Write-Log 'The script signs in to Azure with the token of the Azure CLI session' -Level Info
        # The command gives --subscription only. az finds the account and the tenant from the
        # subscription. az refuses --tenant together with --subscription.
        $cli = Invoke-NeologikAzureCli -Arguments @('account', 'get-access-token', '--resource', 'https://management.azure.com/',
            '--subscription', $state.SubscriptionId, '--query', 'accessToken', '-o', 'tsv')
        $cliToken = if ($cli.ExitCode -eq 0) { [string]($cli.Output | Select-Object -Last 1) } else { '' }
        if (-not $cliToken.Trim()) {
            Write-Log 'The sign-in to Azure failed. The Azure CLI gave no token for the subscription' -Level Error
            Write-ActionRequired "The Azure CLI gave no token for subscription $($state.SubscriptionId) in tenant $($state.TenantId).`nSign in with this command:`n  az login --tenant $($state.TenantId)`nThen run the script again. Or run the script without -UseAzureCliToken, to sign in in the browser."
            return $false
        }
        $accountId = Get-NeologikTokenAccountId -Token $cliToken.Trim()
        if (-not $accountId) { $accountId = 'azure-cli' }
        try {
            Connect-AzAccount -AccessToken $cliToken.Trim() -AccountId $accountId -Tenant $state.TenantId -Subscription $state.SubscriptionId -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Log "The sign-in to Azure failed. $(Get-NeologikErrorText $_)" -Level Error
            Write-ActionRequired "The sign-in to Azure with the token of the Azure CLI session did not complete.`nSign in with this command:`n  az login --tenant $($state.TenantId)`nThen run the script again. Or run the script without -UseAzureCliToken, to sign in in the browser."
            return $false
        }
        Write-Log '  The token of the Azure CLI session holds no multi-factor authentication claim. When Azure refuses a role assignment with a claims error, run the script again without -UseAzureCliToken' -Level Info
    }
    else {
        # The order of the methods: the browser sign-in of the script, then the device code of
        # the script, each with the claim that a role assignment needs, then the Azure CLI
        # session of the workstation, then the device code prompt of Az PowerShell.
        $connected = $false
        Write-Log 'The script signs in to Azure. Sign in with the same account' -Level Info
        $azureScopes = @('https://management.azure.com/.default', 'openid', 'profile', 'offline_access')
        $token = Get-NeologikBrowserToken -ClientId $script:AzurePublicClientId -Label 'Azure' -Claims $script:AzureMfaClaims `
            -Scopes $azureScopes -LoginHint ([string](Get-NeologikProperty $state 'SignInAccount' ''))
        if (-not $token) {
            $token = Get-NeologikDeviceCodeToken -ClientId $script:AzurePublicClientId -Label 'Azure' -Claims $script:AzureMfaClaims -Scopes $azureScopes
        }
        if ($token) {
            $accountId = if ($token.Account) { $token.Account } else { 'device-code' }
            try {
                Connect-AzAccount -AccessToken $token.AccessToken -AccountId $accountId -Tenant $state.TenantId -Subscription $state.SubscriptionId -ErrorAction Stop | Out-Null
                $connected = $true
            }
            catch { Write-Log "The script could not open the Azure session with the token of the sign-in. $(Get-NeologikErrorText $_)" -Level Warning }
        }
        if (-not $connected -and (Test-NeologikCommand -Name 'az')) {
            Write-Log 'The script now tries the Azure CLI session of this workstation' -Level Info
            $cli = Invoke-NeologikAzureCli -Arguments @('account', 'get-access-token', '--resource', 'https://management.azure.com/',
                '--subscription', $state.SubscriptionId, '--query', 'accessToken', '-o', 'tsv')
            $cliToken = if ($cli.ExitCode -eq 0) { [string]($cli.Output | Select-Object -Last 1) } else { '' }
            if ($cliToken.Trim()) {
                $accountId = Get-NeologikTokenAccountId -Token $cliToken.Trim()
                if (-not $accountId) { $accountId = 'azure-cli' }
                try {
                    Connect-AzAccount -AccessToken $cliToken.Trim() -AccountId $accountId -Tenant $state.TenantId -Subscription $state.SubscriptionId -ErrorAction Stop | Out-Null
                    $connected = $true
                    Write-Log '  The token of the Azure CLI session holds no multi-factor authentication claim. When Azure refuses a role assignment with a claims error, run the script again and complete the sign-in in the browser' -Level Info
                }
                catch { Write-Log "The script could not open the Azure session with the token of the Azure CLI session. $(Get-NeologikErrorText $_)" -Level Warning }
            }
            else { Write-Log '  The Azure CLI has no session for this subscription' -Level Info }
        }
        if (-not $connected) {
            Write-Log 'The script now tries the device code prompt of Az PowerShell' -Level Info
            try {
                $connectParams = @{ Tenant = $state.TenantId; Subscription = $state.SubscriptionId; UseDeviceAuthentication = $true }
                # Azure requires multi-factor authentication for each write. The sign-in requests the
                # authentication context claim 'p1', so that Azure accepts the role assignments.
                # The value decodes to {"access_token":{"acrs":{"essential":true,"values":["p1"]}}}. Requires Az.Accounts 5.2.0 or later.
                if ((Get-Command Connect-AzAccount -ErrorAction Stop).Parameters.ContainsKey('ClaimsChallenge')) {
                    $connectParams['ClaimsChallenge'] = 'eyJhY2Nlc3NfdG9rZW4iOnsiYWNycyI6eyJlc3NlbnRpYWwiOnRydWUsInZhbHVlcyI6WyJwMSJdfX19'
                }
                $InformationPreference = 'Continue'
                Connect-AzAccount @connectParams -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Log "The sign-in to Azure failed. $(Get-NeologikErrorText $_)" -Level Error
                Write-ActionRequired "The sign-in to Azure did not complete. The script tried four methods:`n  1. The browser of this computer.`n  2. The device code of the script.`n  3. The Azure CLI session.`n  4. The device code of Az PowerShell.`nRun the script again on a computer with a desktop and a browser.`nSign in with an account that holds Owner or User Access Administrator on subscription $($state.SubscriptionId) in tenant $($state.TenantId)."
                return $false
            }
        }
    }
    try {
        $context = Get-AzContext -ErrorAction Stop
        $contextSub = [string](Get-NeologikProperty (Get-NeologikProperty $context 'Subscription') 'Id' '')
        if ($contextSub -and $contextSub -ne $state.SubscriptionId) {
            Write-ActionRequired "The sign-in to Azure selected subscription $contextSub. The run needs subscription $($state.SubscriptionId).`nConfirm that the account can use subscription $($state.SubscriptionId). Then run the script again."
            return $false
        }
    }
    catch {
        Write-Log "The script could not read the Azure context. $(Get-NeologikErrorText $_). The script continues" -Level Warning
    }
    return (Test-NeologikSubscriptionAdministrator)
}

function Test-NeologikSubscriptionAdministrator {
    <#
    Checks the signed-in account. The signed-in account must hold Owner or User
    Access Administrator on the subscription before the script writes a role
    assignment. A direct role assignment and an inherited role assignment both
    count. A run that writes stops and prints one instruction. A run with -Verify
    warns and continues. The function warns and makes no check when the object id
    of the signed-in account is not known, or when the read fails.
    #>
    $state = $script:State
    $objectId = [string](Get-NeologikProperty $state 'SignedInObjectId' '')
    $subScope = "/subscriptions/$($state.SubscriptionId)"
    if (-not $objectId) {
        Write-Log '  The script does not know the signed-in account. The script does not check the roles of the signed-in account on the subscription' -Level Warning
        return $true
    }
    try {
        $held = @(Get-AzRoleAssignment -ObjectId $objectId -Scope $subScope -ErrorAction Stop |
            ForEach-Object { [string](Get-NeologikProperty $_ 'RoleDefinitionName' '') })
    }
    catch {
        Write-Log "The script could not read the roles of the signed-in account on the subscription. $(Get-NeologikErrorText $_). The script continues. The script reports each role assignment that Azure refuses" -Level Warning
        return $true
    }
    # One name for each role. An inherited role assignment at several scopes counts once.
    $administrator = @($held | Where-Object { $script:SubscriptionAdministratorRoles -contains $_ } | Select-Object -Unique)
    if ($administrator.Count -gt 0) {
        Write-Log "  The signed-in account holds $($administrator -join ', ') on the subscription" -Level Success
        return $true
    }
    $who = if ($state.SignedInUpn) { $state.SignedInUpn } else { 'The signed-in account' }
    if (Test-NeologikVerifyOnly) {
        Write-Log "  $who holds neither Owner nor User Access Administrator on subscription $($state.SubscriptionId). The run with -Verify continues. Azure refuses each role assignment of a run without -Verify" -Level Warning
        return $true
    }
    Write-Log "$who holds neither Owner nor User Access Administrator on subscription $($state.SubscriptionId)" -Level Error
    Write-ActionRequired "$who holds neither Owner nor User Access Administrator on subscription $($state.SubscriptionId).`nAssign one of the two roles to the account in the Azure portal: Subscriptions > Access control (IAM).`nOr activate the role in Privileged Identity Management.`nThen run the script again. The script changed nothing in Azure."
    return $false
}

function Set-NeologikAzureRoleAssignment {
    # Assigns one role to the deployment identity at one scope, when the role assignment
    # is absent. Returns $true when the deployment identity holds the role assignment.
    param([string]$RoleName, [string]$Scope, [string]$Label)
    $deploySp = $script:State.DeploySp
    try {
        $assignment = @(Get-AzRoleAssignment -ObjectId $deploySp.Id -RoleDefinitionName $RoleName -Scope $Scope -ErrorAction Stop |
            Where-Object { $_.Scope -eq $Scope })
        if ($assignment.Count -gt 0) {
            Write-Log "  $Label role '$RoleName': already assigned" -Level Success
            Add-Summary "$Label role: $RoleName" 'Already assigned'
            return $true
        }
        if (Test-NeologikVerifyOnly) {
            # In a run with -Verify a pending role counts as held. The report then shows what a
            # run without -Verify would remove after the run assigned the role.
            Add-NeologikPendingChange "$Label role: $RoleName" 'ASSIGN'
            return $true
        }
        try {
            Invoke-NeologikWrite -Command 'New-AzRoleAssignment' -Parameters @{ ObjectId = $deploySp.Id; RoleDefinitionName = $RoleName; Scope = $Scope } | Out-Null
        }
        catch {
            if ((Get-NeologikErrorText $_) -match '(?i)RoleAssignmentExists|already exists') {
                Write-Log "  $Label role '$RoleName': already assigned" -Level Success
                Add-Summary "$Label role: $RoleName" 'Already assigned'
                return $true
            }
            throw
        }
        Write-Log "  $Label role '$RoleName': assigned" -Level Success
        Add-Summary "$Label role: $RoleName" 'Assigned'
        return $true
    }
    catch {
        $reason = Get-NeologikErrorText $_
        if ($reason -match '(?i)AuthorizationFailed|does not have authorization|Forbidden') {
            $reason = 'insufficient privileges. The signed-in account needs Owner or User Access Administrator on the subscription'
        }
        Write-Log "  $Label role '$RoleName': FAILED. $reason" -Level Error
        Add-Summary "$Label role: $RoleName" "FAILED: $reason"
        return $false
    }
}

function Remove-NeologikAzureRoleAssignment {
    param([string]$RoleName, [string]$Scope, [string]$Label)
    $deploySp = $script:State.DeploySp
    try {
        $assignment = @(Get-AzRoleAssignment -ObjectId $deploySp.Id -RoleDefinitionName $RoleName -Scope $Scope -ErrorAction Stop |
            Where-Object { $_.Scope -eq $Scope })
        if ($assignment.Count -eq 0) {
            Write-Log "  $Label role '$RoleName': not held. The script removes nothing" -Level Success
            Add-Summary "$Label role to remove: $RoleName" 'Not held'
            return
        }
        if (Test-NeologikVerifyOnly) {
            Add-NeologikPendingChange "$Label role to remove: $RoleName" 'REMOVE'
            return
        }
        Invoke-NeologikWrite -Command 'Remove-AzRoleAssignment' -Parameters @{ ObjectId = $deploySp.Id; RoleDefinitionName = $RoleName; Scope = $Scope } | Out-Null
        Write-Log "  $Label role '$RoleName': removed" -Level Success
        Add-Summary "$Label role to remove: $RoleName" 'Removed'
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  $Label role '$RoleName': the removal FAILED. $reason" -Level Error
        Add-Summary "$Label role to remove: $RoleName" "FAILED: $reason"
    }
}

function Get-NeologikDirectoryRoleHeld {
    # Returns the directory roles that the deployment identity holds. The function reads
    # the memberships of the deployment identity. The list of members of a directory role
    # omits service principals, so that list would wrongly report a role as not held.
    # Returns Id, RoleTemplateId and DisplayName for each role. A failed read throws, so
    # that no caller reads a failure as an empty list.
    $deploySp = $script:State.DeploySp
    return @(Get-MgServicePrincipalMemberOf -ServicePrincipalId $deploySp.Id -All -ErrorAction Stop | ForEach-Object {
            $extra = Get-NeologikProperty $_ 'AdditionalProperties' @{}
            if (([string]$extra['@odata.type']) -eq '#microsoft.graph.directoryRole') {
                [pscustomobject]@{ Id = $_.Id; RoleTemplateId = [string]$extra['roleTemplateId']; DisplayName = [string]$extra['displayName'] }
            }
        })
}

function Remove-NeologikAppAdminRole {
    # Step 4c: the membership of the directory role Application Administrator.
    $deploySp = $script:State.DeploySp
    try {
        $appAdminRole = @(Get-NeologikDirectoryRoleHeld | Where-Object { $_.RoleTemplateId -eq $script:AppAdminRoleTemplateId }) | Select-Object -First 1
        $isMember = $null -ne $appAdminRole
        if ($isMember -and (Test-NeologikVerifyOnly)) {
            Add-NeologikPendingChange 'Application Administrator role' 'REMOVE'
        }
        elseif ($isMember) {
            Invoke-NeologikWrite -Command 'Remove-MgDirectoryRoleMemberDirectoryObjectByRef' -Parameters @{ DirectoryRoleId = $appAdminRole.Id; DirectoryObjectId = $deploySp.Id } | Out-Null
            Write-Log '  The directory role Application Administrator: removed' -Level Success
            Add-Summary 'Application Administrator role' 'Removed'
        }
        else {
            Write-Log '  The directory role Application Administrator: not held. The script removes nothing' -Level Success
            Add-Summary 'Application Administrator role' 'Not held'
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        if (Test-NeologikPrivilegeError $_) { $reason = 'insufficient privileges. Sign in as a Global Administrator or as a Privileged Role Administrator' }
        Write-Log "  The directory role Application Administrator: FAILED. $reason" -Level Error
        Add-Summary 'Application Administrator role' "FAILED: $reason"
    }
}

function Test-NeologikSqlAdministratorIsDeployIdentity {
    # Each SQL server in the resource group must name the deployment identity as the
    # Microsoft Entra administrator before the script removes the membership of the Admin
    # User Group. Returns $true. Returns $false after the function logs the reason. The
    # function only reads.
    $state = $script:State
    $deploySp = $state.DeploySp
    $servers = @(Get-AzSqlServer -ResourceGroupName $state.ResourceGroupName -ErrorAction Stop)
    if ($servers.Count -eq 0) {
        Write-Log '  The resource group holds no SQL server yet. Neologik has not yet deployed the environment' -Level Warning
        return $false
    }
    foreach ($server in $servers) {
        $serverName = [string](Get-NeologikProperty $server 'ServerName' '')
        $admin = Get-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $state.ResourceGroupName -ServerName $serverName -ErrorAction Stop
        $adminId = [string](Get-NeologikProperty $admin 'ObjectId' '')
        if ($adminId.ToLowerInvariant() -ne ([string]$deploySp.Id).ToLowerInvariant()) {
            $adminName = [string](Get-NeologikProperty $admin 'DisplayName' '')
            Write-Log "  SQL server ${serverName}: the Microsoft Entra administrator is '$adminName', id $adminId. The Microsoft Entra administrator is not the deployment identity. The deployment by Neologik sets the administrator" -Level Warning
            return $false
        }
    }
    return $true
}

function Remove-NeologikAdminGroupMembership {
    # Step 4d: the membership of the Admin User Group. The function removes the
    # membership only when the SQL server administrator is the deployment identity.
    # Before that, the membership is the only access of the deployment identity to SQL.
    $state = $script:State
    $deploySp = $state.DeploySp
    $label = 'Admin User Group membership'
    if (-not $state.AdminGroupId) {
        Write-Log '  The membership of the Admin User Group: not checked. The command gives no AdminGroupId, and no configuration file names the Admin User Group' -Level Warning
        Add-Summary $label 'Not checked. The command gives no AdminGroupId'
        return
    }
    try {
        $isMember = @(Get-MgGroupMember -GroupId $state.AdminGroupId -All -ErrorAction Stop |
            Where-Object { $_.Id -eq $deploySp.Id }).Count -gt 0
        if (-not $isMember) {
            Write-Log '  The membership of the Admin User Group: not held. The script removes nothing' -Level Success
            Add-Summary $label 'Not held'
            return
        }
        if (-not (Test-NeologikSqlAdministratorIsDeployIdentity)) {
            Write-Log '  The membership of the Admin User Group: HELD. The script keeps the membership. The membership is the only access of the deployment identity to SQL. The script removes the membership when each SQL server names the deployment identity as the Microsoft Entra administrator' -Level Warning
            Add-Summary $label 'HELD. The script keeps the membership until each SQL server names the deployment identity as the Microsoft Entra administrator. The deployment by Neologik sets the administrator'
            return
        }
        if (Test-NeologikVerifyOnly) {
            Add-NeologikPendingChange $label 'REMOVE'
            return
        }
        Invoke-NeologikWrite -Command 'Remove-MgGroupMemberByRef' -Parameters @{ GroupId = $state.AdminGroupId; DirectoryObjectId = $deploySp.Id } | Out-Null
        Write-Log '  The membership of the Admin User Group: removed. The deployment identity reaches SQL as the Microsoft Entra administrator of the SQL server' -Level Success
        Add-Summary $label 'Removed'
    }
    catch {
        $reason = Get-NeologikErrorText $_
        if (Test-NeologikPrivilegeError $_) { $reason = 'insufficient privileges. Sign in as a Global Administrator or as an owner of the group' }
        Write-Log "  The membership of the Admin User Group: FAILED. $reason" -Level Error
        Add-Summary $label "FAILED: $reason"
    }
}

function ConvertTo-NeologikScopeLabel {
    # Returns a short name of the scope for the summary: 'subscription', 'resource
    # group', or the name of the resource below the resource group.
    param([string]$Scope)
    if ($Scope -match '^/subscriptions/[^/]+$') { return 'subscription' }
    if ($Scope -match '^/subscriptions/[^/]+/resourceGroups/[^/]+$') { return 'resource group' }
    return ($Scope -split '/')[-1]
}

function Test-NeologikDeclaredAzureRole {
    # Returns whether the role assignment belongs to the declared set.
    param([string]$RoleName, [string]$Scope, [string]$RgScope, [string]$SubScope)
    if ($Scope -eq $RgScope) { return [bool]($script:RequiredRgRoles -contains $RoleName) }
    if ($Scope -eq $SubScope) { return [bool]($script:RequiredSubRoles -contains $RoleName) }
    if ($Scope.StartsWith("$RgScope/", [System.StringComparison]::OrdinalIgnoreCase)) {
        return [bool]($script:DeclaredResourceRoles -contains $RoleName)
    }
    return $false
}

function Remove-NeologikUndeclaredAzureRole {
    # Step 4e: the function removes every Azure role assignment of the deployment
    # identity in the subscription that is outside the declared set. The declared set is
    # the seven roles on the resource group, the two roles on the subscription and the
    # declared role below the resource group.
    $state = $script:State
    $deploySp = $state.DeploySp
    $rgScope = "/subscriptions/$($state.SubscriptionId)/resourceGroups/$($state.ResourceGroupName)"
    $subScope = "/subscriptions/$($state.SubscriptionId)"
    try {
        $assignments = @(Get-AzRoleAssignment -ObjectId $deploySp.Id -ErrorAction Stop)
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  Other Azure roles: FAILED. The script could not list the Azure roles of the deployment identity. $reason" -Level Error
        Add-Summary 'Other Azure roles' "FAILED: $reason"
        return
    }
    $undeclared = @($assignments | Where-Object {
            -not (Test-NeologikDeclaredAzureRole -RoleName ([string]$_.RoleDefinitionName) -Scope ([string]$_.Scope) -RgScope $rgScope -SubScope $subScope)
        })
    if ($undeclared.Count -eq 0) {
        Write-Log '  Other Azure roles: none' -Level Success
        Add-Summary 'Other Azure roles' 'None'
        return
    }
    foreach ($assignment in $undeclared) {
        $roleName = [string]$assignment.RoleDefinitionName
        $scope = [string]$assignment.Scope
        $label = "Other Azure role: $roleName on $(ConvertTo-NeologikScopeLabel $scope)"
        if (Test-NeologikVerifyOnly) {
            Add-NeologikPendingChange $label 'REMOVE'
            continue
        }
        try {
            Invoke-NeologikWrite -Command 'Remove-AzRoleAssignment' -Parameters @{ ObjectId = $deploySp.Id; RoleDefinitionName = $roleName; Scope = $scope } | Out-Null
            Write-Log "  ${label}: removed" -Level Success
            Add-Summary $label 'Removed'
        }
        catch {
            $reason = Get-NeologikErrorText $_
            Write-Log "  ${label}: FAILED. $reason" -Level Error
            Add-Summary $label "FAILED: $reason"
        }
    }
}

function Remove-NeologikUndeclaredDirectoryRole {
    # Step 4f: the deployment identity holds no directory role. Step 4c removes
    # Application Administrator. This step removes every other directory role. The
    # function reads the memberships of the deployment identity.
    $deploySp = $script:State.DeploySp
    try {
        $held = @(Get-NeologikDirectoryRoleHeld | Where-Object { $_.RoleTemplateId -ne $script:AppAdminRoleTemplateId })
        if ($held.Count -eq 0) {
            Write-Log '  Other directory roles: none' -Level Success
            Add-Summary 'Other directory roles' 'None'
            return
        }
        foreach ($role in $held) {
            $name = [string](Get-NeologikProperty $role 'DisplayName' '')
            if (-not $name) { $name = [string]$role.RoleTemplateId }
            $label = "Other directory role: $name"
            if (Test-NeologikVerifyOnly) {
                Add-NeologikPendingChange $label 'REMOVE'
                continue
            }
            Invoke-NeologikWrite -Command 'Remove-MgDirectoryRoleMemberDirectoryObjectByRef' -Parameters @{ DirectoryRoleId = $role.Id; DirectoryObjectId = $deploySp.Id } | Out-Null
            Write-Log "  ${label}: removed" -Level Success
            Add-Summary $label 'Removed'
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        if (Test-NeologikPrivilegeError $_) { $reason = 'insufficient privileges. Sign in as a Global Administrator or as a Privileged Role Administrator' }
        Write-Log "  Other directory roles: FAILED. $reason" -Level Error
        Add-Summary 'Other directory roles' "FAILED: $reason"
    }
}

function Remove-NeologikUndeclaredGroupMembership {
    # Step 4g: the deployment identity is a member of no group. Step 4d covers the Admin
    # User Group. This step removes every other group membership.
    $state = $script:State
    $deploySp = $state.DeploySp
    try {
        $groups = @(Get-MgServicePrincipalMemberOf -ServicePrincipalId $deploySp.Id -All -ErrorAction Stop | Where-Object {
                $extra = Get-NeologikProperty $_ 'AdditionalProperties' @{}
                ([string]$extra['@odata.type']) -eq '#microsoft.graph.group' -and $_.Id -ne $state.AdminGroupId
            })
        if ($groups.Count -eq 0) {
            Write-Log '  Other group memberships: none' -Level Success
            Add-Summary 'Other group memberships' 'None'
            return
        }
        foreach ($group in $groups) {
            $extra = Get-NeologikProperty $group 'AdditionalProperties' @{}
            $name = [string]$extra['displayName']
            if (-not $name) { $name = [string]$group.Id }
            $label = "Other group membership: $name"
            if (Test-NeologikVerifyOnly) {
                Add-NeologikPendingChange $label 'REMOVE'
                continue
            }
            Invoke-NeologikWrite -Command 'Remove-MgGroupMemberByRef' -Parameters @{ GroupId = $group.Id; DirectoryObjectId = $deploySp.Id } | Out-Null
            Write-Log "  ${label}: removed" -Level Success
            Add-Summary $label 'Removed'
        }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        if (Test-NeologikPrivilegeError $_) { $reason = 'insufficient privileges. Sign in as a Global Administrator or as an owner of the group' }
        Write-Log "  Other group memberships: FAILED. $reason" -Level Error
        Add-Summary 'Other group memberships' "FAILED: $reason"
    }
}

function Set-NeologikKitVersionTag {
    # Step 4h: the version of the onboarding kit, in the tag NeologikOnboardingKit on the
    # resource group. The Neologik Platform reads the tag before an upgrade. The function
    # writes the tag last, merges the tag with the existing tags, and writes only a
    # changed value.
    param([Parameter(Mandatory)][string]$ResourceId)
    $label = 'Onboarding kit version tag'
    try {
        $rg = Get-AzResourceGroup -Name $script:State.ResourceGroupName -ErrorAction Stop
        $tags = Get-NeologikProperty $rg 'Tags' @{}
        if ($null -eq $tags) { $tags = @{} }
        $current = [string](Get-NeologikProperty $tags 'NeologikOnboardingKit' '')
        if ($current -eq $script:KitVersion) {
            Write-Log "  ${label}: already set to $current" -Level Success
            Add-Summary $label "Already set: $current"
            return
        }
        if (Test-NeologikVerifyOnly) {
            Add-NeologikPendingChange $label "SET $($script:KitVersion). The current value is '$current'"
            return
        }
        Invoke-NeologikWrite -Command 'Update-AzTag' -Parameters @{ ResourceId = $ResourceId; Tag = @{ NeologikOnboardingKit = $script:KitVersion }; Operation = 'Merge' } | Out-Null
        $was = if ($current) { ". The earlier value was $current" } else { '' }
        Write-Log "  ${label}: set to $($script:KitVersion)$was" -Level Success
        Add-Summary $label "Set: $($script:KitVersion)"
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "  ${label}: FAILED. $reason" -Level Error
        Add-Summary $label "FAILED: $reason"
    }
}

function Invoke-NeologikPermissionReduction {
    <#
    Step 5 of the first run: the permission reduction. The function first assigns
    the seven roles on the resource group and the two roles on the subscription. The
    function removes nothing unless the deployment identity holds all nine roles.
    #>
    $state = $script:State
    Write-Log 'Step 5 of 5: the permission reduction of the deployment identity' -Level Info

    $azureItems = @()
    foreach ($roleName in $script:RequiredRgRoles) { $azureItems += "Resource group role: $roleName" }
    foreach ($roleName in $script:RequiredSubRoles) { $azureItems += "Subscription role: $roleName" }
    foreach ($roleName in $script:LegacySubRoles) { $azureItems += "Subscription role to remove: $roleName" }
    if (-not (Import-NeologikModuleSet -Names @('Az.Accounts', 'Az.Resources', 'Az.Sql') -MinimumVersion ([version]'2.0.0') -Independent `
                -InstallHint 'Install-Module Az.Accounts, Az.Resources, Az.Sql -Scope CurrentUser -Force')) {
        foreach ($item in $azureItems) { Add-Summary $item 'SKIPPED: the Az modules are not available' }
        Add-Summary 'Application Administrator role' 'SKIPPED: the script did not confirm the Azure roles of the deployment identity'
        Add-Summary 'Admin User Group membership' 'SKIPPED: the script did not confirm the Azure roles of the deployment identity'
        foreach ($item in @('Other Azure roles', 'Other directory roles', 'Other group memberships')) { Add-Summary $item 'SKIPPED: the script did not confirm the Azure roles of the deployment identity' }
        return
    }
    if (-not (Connect-NeologikAzure)) {
        foreach ($item in $azureItems) { Add-Summary $item 'SKIPPED: the sign-in to Azure failed' }
        Add-Summary 'Application Administrator role' 'SKIPPED: the script did not confirm the Azure roles of the deployment identity'
        Add-Summary 'Admin User Group membership' 'SKIPPED: the script did not confirm the Azure roles of the deployment identity'
        foreach ($item in @('Other Azure roles', 'Other directory roles', 'Other group memberships')) { Add-Summary $item 'SKIPPED: the script did not confirm the Azure roles of the deployment identity' }
        return
    }

    $rgScope = "/subscriptions/$($state.SubscriptionId)/resourceGroups/$($state.ResourceGroupName)"
    $subScope = "/subscriptions/$($state.SubscriptionId)"

    # Step 4a: the roles on the resource group come first, so that the deployment never
    # loses access.
    $narrowComplete = $true
    foreach ($roleName in $script:RequiredRgRoles) {
        if (-not (Set-NeologikAzureRoleAssignment -RoleName $roleName -Scope $rgScope -Label 'Resource group')) { $narrowComplete = $false }
    }

    # Step 4a, second part: the two roles on the subscription, before any removal.
    foreach ($roleName in $script:RequiredSubRoles) {
        if (-not (Set-NeologikAzureRoleAssignment -RoleName $roleName -Scope $subScope -Label 'Subscription')) { $narrowComplete = $false }
    }

    if (-not $narrowComplete) {
        Write-Log '  The deployment identity does not hold all nine Azure roles. The script removes no access' -Level Warning
        foreach ($roleName in $script:LegacySubRoles) { Add-Summary "Subscription role to remove: $roleName" 'SKIPPED: the deployment identity does not hold all nine Azure roles' }
        Add-Summary 'Application Administrator role' 'SKIPPED: the deployment identity does not hold all nine Azure roles'
        Add-Summary 'Admin User Group membership' 'SKIPPED: the deployment identity does not hold all nine Azure roles'
        foreach ($item in @('Other Azure roles', 'Other directory roles', 'Other group memberships')) { Add-Summary $item 'SKIPPED: the deployment identity does not hold all nine Azure roles' }
        return
    }

    # Step 4b: remove the two roles on the subscription that the deployment identity
    # does not need.
    foreach ($roleName in $script:LegacySubRoles) {
        Remove-NeologikAzureRoleAssignment -RoleName $roleName -Scope $subScope -Label 'Subscription'
    }

    # Step 4c: remove the directory role Application Administrator.
    Remove-NeologikAppAdminRole

    # Step 4d: remove the membership of the Admin User Group, only when the SQL server
    # administrator is the deployment identity.
    Remove-NeologikAdminGroupMembership

    # Steps 4e to 4g: remove every other Azure role assignment, directory role and
    # group membership.
    Remove-NeologikUndeclaredAzureRole
    Remove-NeologikUndeclaredDirectoryRole
    Remove-NeologikUndeclaredGroupMembership

    # Step 4h: record the version of the onboarding kit, after every step above.
    Set-NeologikKitVersionTag -ResourceId $rgScope
}

# ----- The two runs --------------------------------------------------------------

function Invoke-NeologikPreWindowRun {
    # The first run: the checks and the grants, then the permission reduction.
    Set-NeologikAgentBlueprint
    Set-NeologikDeploymentGraphRole
    Set-NeologikSecurityGroup
    Set-NeologikSignInGroupAssignment
    Test-NeologikPreWindowSharePointConsent
    Set-NeologikPlatformAppOwnership
    Invoke-NeologikPermissionReduction
}

function Invoke-NeologikPostWindowRun {
    # The later run: the grants that the files list, and nothing else.
    $state = $script:State
    if ($state.AgentGrants) { Set-NeologikAgentUserGrant }
    if ($state.MailboxGrantsFile) { Set-NeologikMailboxGrant }
}

# ----- Summary ------------------------------------------------------------------

function Get-NeologikHeldGraphRole {
    # Returns the Microsoft Graph application permissions that the deployment identity
    # holds now.
    $state = $script:State
    if (-not $state.ContainsKey('DeploySp') -or -not $state.DeploySp -or -not $state.ContainsKey('GraphSp') -or -not $state.GraphSp) { return @() }
    $graphSp = $state.GraphSp
    $held = @(Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $state.DeploySp.Id -All -ErrorAction Stop |
        Where-Object { $_.ResourceId -eq $graphSp.Id } |
        ForEach-Object { $roleId = $_.AppRoleId; @($graphSp.AppRoles | Where-Object { $_.Id -eq $roleId } | ForEach-Object { $_.Value }) })
    return @($held | Where-Object { $_ })
}

function Write-NeologikSummary {
    # Prints the summary table and writes the summary file. Returns the exit code: 0
    # when no item needs attention, otherwise 1.
    $state = $script:State
    Write-Host ''
    Write-Host '============================ SUMMARY ============================' -ForegroundColor Cyan
    if ($script:Summary.Count -gt 0) {
        $script:Summary | Format-Table -AutoSize | Out-String | Write-Host
    }
    else {
        Write-Host '  The script checked no item. Read the messages above'
    }
    $attention = @($script:Summary | Where-Object { $_.Result -match $script:AttentionPattern })
    $pending = @($script:Summary | Where-Object { $_.Result -like 'WOULD *' })
    $runName = if ((Get-NeologikProperty $state 'Run' '') -eq 'PostWindow') { 'The later run' } else { 'The first run' }
    # The summary file in JSON. The summary file holds the Microsoft Graph application
    # permissions that the deployment identity holds now, and every item of the run. The
    # function writes the summary file to the folder of the script. The summary file
    # holds no secret.
    try {
        $heldRoles = @()
        try { $heldRoles = @(Get-NeologikHeldGraphRole) }
        catch { Write-Log "The script could not read the permissions of the deployment identity for the summary. $(Get-NeologikErrorText $_)" -Level Warning }
        $json = [pscustomobject]@{
            tenantId             = [string](Get-NeologikProperty $state 'TenantId' '')
            deploymentIdentity   = [string](Get-NeologikProperty $state 'DeploySpClientId' '')
            run                  = [string](Get-NeologikProperty $state 'Run' '')
            verifyOnly           = [bool](Get-NeologikProperty $state 'Verify' $false)
            ranAt                = (Get-Date).ToUniversalTime().ToString('o')
            deploymentGraphRoles = @($heldRoles)
            expectedGraphRoles   = @($script:RequiredGraphRoles)
            agentGrantsFile      = [string](Get-NeologikProperty $state 'AgentGrantsFile' '')
            # The two role groups of the Neologik Context Engine (first run). Neologik
            # records the NCE Admins group for the environment.
            nceContributorsGroupId = [string](Get-NeologikProperty $state 'NceContributorsGroupId' '')
            nceAdminsGroupId     = [string](Get-NeologikProperty $state 'NceAdminsGroupId' '')
            items                = @($script:Summary)
            attentionCount       = $attention.Count
            pendingChangeCount   = $pending.Count
        } | ConvertTo-Json -Depth 5
        $fileName = 'Neologik_EnvironmentAccess_{0}_{1}.json' -f [string](Get-NeologikProperty $state 'Run' 'PreWindow'), (Get-Date -Format 'yyyyMMdd_HHmmss')
        $written = $null
        foreach ($directory in @(Get-NeologikSummaryDirectory)) {
            $summaryPath = Join-Path $directory $fileName
            try {
                Set-Content -LiteralPath $summaryPath -Value $json -Encoding UTF8 -ErrorAction Stop
                $written = $summaryPath
                break
            }
            catch {
                Write-Log "The script could not write the summary file to $directory. $(Get-NeologikErrorText $_). The script tries the next folder" -Level Warning
            }
        }
        if ($written) { Write-Log "The script wrote the summary file to $written. Send the summary file to Neologik" -Level Info }
        else { Write-Log 'The script could not write the summary file to any folder. Send the summary table to Neologik' -Level Warning }
    }
    catch {
        Write-Log "The script could not write the summary file. $(Get-NeologikErrorText $_)" -Level Warning
    }
    if ($attention.Count -gt 0) {
        if ($pending.Count -gt 0) {
            Write-Log "A run without -Verify would make $($pending.Count) change(s). The script wrote nothing" -Level Warning
        }
        Write-Log "$($attention.Count) item(s) need attention. Read the summary above" -Level Warning
        return 1
    }
    if (Get-NeologikProperty $state 'Verify' $false) {
        Write-Log "$runName with -Verify is complete. A run without -Verify would change nothing. The environment access is in the expected state" -Level Success
    }
    else {
        Write-Log "$runName is complete. The environment access is in the expected state" -Level Success
    }
    return 0
}

# ----- Main entry ---------------------------------------------------------------

function Invoke-NeologikEnvironmentAccess {
    <#
    Runs the script. Returns the exit code: 0 when every item is in the expected
    state, 1 when an item needs attention. The function never throws. The function
    reports each failure together with the action to take.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [string]$ConfigurationFile,
        [switch]$Verify,
        [string]$TenantId,
        [string]$DeploySpClientId,
        [string]$SolutionShortName,
        [string]$SolutionName,
        [string]$SignInAppClientId,
        [string]$SharePointAppClientId,
        [string[]]$BotAppClientIds,
        [string]$NceUserGroupId,
        [string]$AdminGroupId,
        [string]$GuestUsersFile,
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        [string]$BlueprintKey = 'default',
        [string]$AgentGrantsFile,
        [string]$MailboxGrantsFile,
        [string[]]$RemoveLegacyGrantAppIds,
        [switch]$UseAzureCliToken
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $script:Summary = @()
    $script:State = @{}

    if (-not (Test-NeologikPowerShellVersion)) { return 1 }

    try {
        Resolve-NeologikInput -Parameters @{
            ConfigurationFile       = $ConfigurationFile
            Verify                  = [bool]$Verify
            TenantId                = $TenantId
            DeploySpClientId        = $DeploySpClientId
            SolutionShortName       = $SolutionShortName
            SolutionName            = $SolutionName
            SignInAppClientId       = $SignInAppClientId
            SharePointAppClientId   = $SharePointAppClientId
            BotAppClientIds         = @($BotAppClientIds)
            NceUserGroupId          = $NceUserGroupId
            AdminGroupId            = $AdminGroupId
            GuestUsersFile          = $GuestUsersFile
            SubscriptionId          = $SubscriptionId
            ResourceGroupName       = $ResourceGroupName
            BlueprintKey            = $BlueprintKey
            AgentGrantsFile         = $AgentGrantsFile
            MailboxGrantsFile       = $MailboxGrantsFile
            RemoveLegacyGrantAppIds = @($RemoveLegacyGrantAppIds)
            UseAzureCliToken        = [bool]$UseAzureCliToken
        }
    }
    catch [System.ArgumentException] {
        Write-Log $_.Exception.Message -Level Error
        Write-ActionRequired $_.Exception.Message
        return 1
    }
    catch {
        Write-Log "The script could not read the inputs. $(Get-NeologikErrorText $_)" -Level Error
        Write-ActionRequired "The script could not read the inputs. $(Get-NeologikErrorText $_)"
        return 1
    }

    Write-NeologikHeader

    # Each address that the run uses must answer before the script changes anything.
    Write-Log 'The script checks that this workstation can reach each Microsoft address' -Level Info
    if (-not (Test-NeologikPreflightEndpoint)) { return 1 }

    if (-not (Import-NeologikModuleSet -Names $script:GraphModules -MinimumVersion $script:GraphModuleMinimumVersion `
                -InstallHint 'Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Applications, Microsoft.Graph.Groups, Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser -Force')) {
        return 1
    }
    if (-not (Connect-NeologikGraph)) { return 1 }
    if (-not (Resolve-NeologikPrincipal)) { return (Write-NeologikSummary) }

    try {
        if ($script:State.Run -eq 'PostWindow') { Invoke-NeologikPostWindowRun }
        else { Invoke-NeologikPreWindowRun }
    }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "An unexpected error stopped the run. $reason" -Level Error
        Add-Summary 'Run' "FAILED: unexpected error. $reason"
    }
    return (Write-NeologikSummary)
}

# When a caller loads the script with a dot, PowerShell defines the functions and
# runs nothing.
if ($MyInvocation.InvocationName -ne '.') {
    $neologikExitCode = Invoke-NeologikEnvironmentAccess @PSBoundParameters
    exit ([int](@($neologikExitCode)[-1]))
}
