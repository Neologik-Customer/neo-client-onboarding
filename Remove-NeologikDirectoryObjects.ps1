#Requires -Version 7.4
<#
.SYNOPSIS
    Deletes the directory objects of one Neologik Platform environment from your
    Microsoft Entra tenant.

.DESCRIPTION
    This script is step 7 of the uninstall guide. Microsoft offers no screen that can
    delete an agent identity or an agent identity blueprint, so the uninstall guide
    uses this script for the directory.

    The script finds each object by the short name of the environment, shows you the
    list and deletes the objects only after you type DELETE. The script deletes in
    this order:
    1. Agent accounts
    2. Agent identities
    3. Applications, with each agent identity blueprint last
    4. Security groups

    The script acts only on these objects:
    - an agent account, agent identity, application or security group whose display
      name ends with " - <short name>"
    - an agent identity or an agent identity blueprint that Microsoft Foundry created
      for the AI account of the environment. The name of such an object starts with
      "ais-" and contains "AgentIdentity"

    Run the script with an account that holds the Global Administrator role. You can
    run the script any number of times. Each run lists only what remains. The script
    ends with exit code 1 when an object remains after the run.

.PARAMETER ShortName
    The short name of the environment, for example abcprd01. The short name is the
    last part of the name of each Neologik security group.

.PARAMETER TenantId
    The tenant to sign in to. Default: the home tenant of the account that signs in.

.EXAMPLE
    .\Remove-NeologikDirectoryObjects.ps1 -ShortName abcprd01

.NOTES
    Requires PowerShell 7.4 or later and the module Microsoft.Graph.Authentication.
    The script installs the module for your user account when the module is missing.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9-]{3,}$')]
    [string]$ShortName,

    [Parameter(Mandatory = $false)]
    [string]$TenantId
)

$ErrorActionPreference = 'Stop'

$script:Version = '1.0'
$script:Graph = 'https://graph.microsoft.com/v1.0'
$script:GraphBeta = 'https://graph.microsoft.com/beta'
$script:GraphScopes = @(
    'Application.ReadWrite.All',
    'Group.ReadWrite.All',
    'AgentIdentity.DeleteRestore.All',
    'AgentIdentityBlueprint.DeleteRestore.All',
    'AgentIdUser.ReadWrite.All'
)

Write-Host ""
Write-Host "Deleting the directory objects of the Neologik Platform environment $ShortName" -ForegroundColor Magenta
Write-Host "  Script version: $($script:Version)" -ForegroundColor Gray

# --- Sign in -------------------------------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-Host "Installing the module Microsoft.Graph.Authentication for your user account..." -ForegroundColor Cyan
    Install-Module -Name Microsoft.Graph.Authentication -Scope CurrentUser -Force
}
Import-Module Microsoft.Graph.Authentication

$connectParams = @{ Scopes = $script:GraphScopes; ContextScope = 'Process'; NoWelcome = $true }
if ($TenantId) { $connectParams['TenantId'] = $TenantId }
Connect-MgGraph @connectParams | Out-Null

$context = Get-MgContext
Write-Host "  Tenant:         $($context.TenantId)" -ForegroundColor Gray
Write-Host "  Signed in as:   $($context.Account)" -ForegroundColor Gray
Write-Host ""

# --- Find the objects ----------------------------------------------------------------------------
function Find-NeologikObject {
    param([string]$Kind)

    # The search finds each name that holds the short name. The filter keeps only the names that
    # belong to this environment.
    $uri = "$script:Graph/$Kind`?`$search=%22displayName:$ShortName%22&`$select=id,displayName&`$top=200"
    while ($uri) {
        $page = Invoke-MgGraphRequest -Method GET -Uri $uri -Headers @{ ConsistencyLevel = 'eventual' }
        $page.value | Where-Object { $_.displayName -like "* - $ShortName" -or $_.displayName -like 'ais-*AgentIdentity*' }
        $uri = $page['@odata.nextLink']
    }
}

$agentAccounts = @(Find-NeologikObject -Kind 'users' | Where-Object { $_['@odata.type'] -eq '#microsoft.graph.agentUser' })
$agentIdentities = @(Find-NeologikObject -Kind 'servicePrincipals' | Where-Object { $_['@odata.type'] -eq '#microsoft.graph.agentIdentity' })
$applications = @(Find-NeologikObject -Kind 'applications' | Sort-Object { $_['@odata.type'] -eq '#microsoft.graph.agentIdentityBlueprint' })
$groups = @(Find-NeologikObject -Kind 'groups' | Where-Object { $_.displayName -like "* - $ShortName" })

# The order of the list is the order of the deletions. An agent identity blueprint is the parent of
# the agent identities and the agent accounts, so the blueprint goes after them.
$removals = @(
    $agentAccounts | ForEach-Object { [pscustomobject]@{ Kind = 'Agent account'; Name = $_.displayName; Uri = "$script:GraphBeta/users/$($_.id)" } }
    $agentIdentities | ForEach-Object { [pscustomobject]@{ Kind = 'Agent identity'; Name = $_.displayName; Uri = "$script:GraphBeta/servicePrincipals/$($_.id)/microsoft.graph.agentIdentity" } }
    $applications | ForEach-Object { [pscustomobject]@{ Kind = 'Application'; Name = $_.displayName; Uri = "$script:Graph/applications/$($_.id)" } }
    $groups | ForEach-Object { [pscustomobject]@{ Kind = 'Security group'; Name = $_.displayName; Uri = "$script:Graph/groups/$($_.id)" } }
)

if ($removals.Count -eq 0) {
    Write-Host "Nothing is left to remove." -ForegroundColor Green
    exit 0
}

$removals | Format-Table Kind, Name -AutoSize | Out-Host

# --- Confirm and delete --------------------------------------------------------------------------
$answer = Read-Host "Type DELETE to remove these $($removals.Count) objects"
if ($answer -cne 'DELETE') {
    Write-Host "The script deleted nothing." -ForegroundColor Yellow
    exit 0
}

$remaining = 0
foreach ($item in $removals) {
    try {
        Invoke-MgGraphRequest -Method DELETE -Uri $item.Uri | Out-Null
        Write-Host "  Removed: $($item.Name)" -ForegroundColor Green
    }
    catch {
        # Microsoft Entra can list an object for a few minutes after the deletion.
        if ($_.Exception.Message -match 'NotFound') {
            Write-Host "  Already gone: $($item.Name)" -ForegroundColor DarkGray
            continue
        }
        $remaining++
        Write-Warning "Not removed: $($item.Name). $($_.Exception.Message)"
    }
}

Write-Host ""
if ($remaining -gt 0) {
    Write-Warning "$remaining of the $($removals.Count) objects remain. Read each warning above, then run this script again."
    exit 1
}

Write-Host "Done. Run this script again to confirm that nothing is left to remove." -ForegroundColor Green
exit 0
