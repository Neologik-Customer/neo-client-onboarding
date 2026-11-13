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
    Before the script imports a module that the script installed, the script checks
    the signature of each file of the module.
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

$script:Version = '1.1'
$script:Graph = 'https://graph.microsoft.com/v1.0'
$script:GraphBeta = 'https://graph.microsoft.com/beta'
$script:GraphScopes = @(
    'Application.ReadWrite.All',
    'Group.ReadWrite.All',
    'AgentIdentity.DeleteRestore.All',
    'AgentIdentityBlueprint.DeleteRestore.All',
    'AgentIdUser.ReadWrite.All'
)

# --- Signature check -----------------------------------------------------------------------------
# The file types that the signature check of a module reads. Microsoft Corporation publishes each
# module that the script installs, and signs each script file of the module. A module also holds
# libraries that other publishers sign, for example Json.NET. A library needs a valid signature of
# any publisher.
$script:ModuleScriptExtensions = @('.ps1', '.psm1', '.psd1', '.ps1xml', '.cdxml')
$script:ModuleLibraryExtensions = @('.dll', '.exe')

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
        assembly.
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

        # .NET refuses to run the code of a reference assembly, so a reference assembly with no signature passes.
        if ($isLibrary -and
            [string](Get-AuthenticodeSignature -LiteralPath $file.FullName).Status -eq 'NotSigned' -and
            (Test-NeologikReferenceAssembly -Path $file.FullName)) {
            Write-Host "The library $($file.FullName) of the module $Name $Version is a reference assembly with no signature. .NET runs no code of a reference assembly" -ForegroundColor Gray
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

    Write-Host "Checking the signature of each file of the installed modules..." -ForegroundColor Gray
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
                Write-Warning "The module $($spec['ModuleName']), which the module $($current.Name) requires, is not installed. The script checks no file of that module"
            }
        }
    }

    if ($problems.Count -eq 0) {
        Write-Host "Each file of the installed modules has a valid signature" -ForegroundColor Green
        return
    }

    foreach ($problem in $problems) {
        Write-Host "The signature check failed for $problem" -ForegroundColor Red
    }
    foreach ($module in $installed) {
        try {
            Remove-Item -LiteralPath $module.ModuleBase -Recurse -Force -ErrorAction Stop
            Write-Warning "Removed the module $($module.Name) $($module.Version), which the script installed in this run"
        }
        catch {
            Write-Warning "The script could not remove the folder $($module.ModuleBase). Delete the folder before the next run: $($_.Exception.Message)"
        }
    }
    throw "A PowerShell module failed the signature check. The script removed the module, imported no module and stops. The messages above name each file that failed the check. Run the script again later. When the check fails again, email a copy of the messages to support@neologik.ai."
}

Write-Host ""
Write-Host "Deleting the directory objects of the Neologik Platform environment $ShortName" -ForegroundColor Magenta
Write-Host "  Script version: $($script:Version)" -ForegroundColor Gray

# --- Sign in -------------------------------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    Write-Host "Installing the module Microsoft.Graph.Authentication for your user account..." -ForegroundColor Cyan
    Install-Module -Name Microsoft.Graph.Authentication -Scope CurrentUser -Force
    # Check the signature of each file that the download brought, before the script imports the module.
    try {
        Assert-NeologikModuleSignature -Modules @(@{ Name = 'Microsoft.Graph.Authentication'; MinVersion = '' })
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
}
Import-Module Microsoft.Graph.Authentication

$connectParams = @{ Scopes = $script:GraphScopes; ContextScope = 'Process'; NoWelcome = $true }
if ($TenantId) { $connectParams['TenantId'] = $TenantId }
try {
    Connect-MgGraph @connectParams | Out-Null
}
catch {
    # Some terminals give the Windows sign-in window nothing to attach to. A device code works in every terminal.
    Write-Host "The sign-in window could not open in this terminal. Open the web address below in a browser, enter the code and sign in." -ForegroundColor Yellow
    # Microsoft Graph PowerShell writes the web address and the code to the information stream.
    $InformationPreference = 'Continue'
    Connect-MgGraph @connectParams -UseDeviceCode | Out-Null
}

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
