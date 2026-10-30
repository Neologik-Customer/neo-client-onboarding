#Requires -Version 7.4

<#
.SYNOPSIS
    Applies the grants that agents and Apps of a Neologik Platform environment
    need to work unattended in Microsoft 365. A Global Administrator runs the
    script with the files that the Neologik Context Engine exports.

.DESCRIPTION
    docs\GRANT-AGENT-ACCESS-SCRIPT-GUIDE.md describes the script in full.

    The script applies two files. Each file comes from the Neologik Context Engine
    of the environment. Neologik sends the files, or a platform operator downloads
    the files from the Admin page.

      File                 Parameter           What the script applies
      Agent grants file    -AgentGrantsFile    The grants to agent users, the
                                               Microsoft Graph application
                                               permissions of workload
                                               identities and the check of the
                                               SharePoint consent
      Mailbox grants file  -MailboxGrantsFile  The Exchange Online mailbox
                                               grants of the email channels

    The command names one file or both. The script reads the current state before
    each change. On an environment that already holds every grant, the script
    changes nothing. A Global Administrator can run the script again at any time,
    and runs the script again whenever the Neologik Context Engine exports a new
    file.

    With -Verify the script reports each change that a run would make. The script
    then writes nothing.

    The script does not stop at the first problem. The script checks each item
    separately. When an item fails, the script records the item and the reason in
    the summary.

    The run ends with a summary table, a summary file in JSON and a log file. The
    script writes the log file from the first line of the run, so that a failed run
    leaves a full record.

      Exit code  Meaning
      0          Every grant is in the expected state.
      1          An item needs attention. With -Verify, a change is pending.

    STEP 1. GRANTS TO AGENT USERS, WITH -AgentGrantsFile

    An agent or an App that works unattended has an agent identity and an agent
    user account in your directory. For each agent and each App in the file, the
    script creates one delegated permission grant. The grant lets the agent
    identity act as the agent user of that agent identity. The grant holds exactly
    the permissions that the file lists. The grant names one agent user. The grant
    is not a grant for the whole tenant.

    The file can also list Microsoft Graph application permissions for named
    workload identities. The script grants those permissions.

    The file records whether the environment uses SharePoint ingestion. When the
    environment uses SharePoint ingestion, the script checks the consent of the
    SharePoint application for the Microsoft Graph application permission
    Sites.Selected. A consent belongs to one application. When an earlier
    SharePoint application of Neologik in the tenant holds a SharePoint
    permission, the script grants Sites.Selected to the SharePoint application of
    the environment. Otherwise the script prints the consent address when the
    consent is absent. A site administrator grants access to each SharePoint site
    separately.

    STEP 2. MAILBOX GRANTS, WITH -MailboxGrantsFile

    For each email channel in the file, the script grants three Exchange Online
    roles to the identity of the email channel.
      - Application Mail.Read
      - Application Mail.ReadWrite
      - Application Mail.Send
    Each role is limited to the one mailbox of the email channel.

    With -RemoveLegacyGrantAppIds the script also removes the Exchange Online role
    assignments of an identity that the environment has stopped using. An identity
    that the file records as still in use keeps the role assignments.

    Step 2 needs the sign-in of an Exchange Administrator or of a Global
    Administrator.

    PERMISSIONS THAT THE SIGN-IN REQUESTS

    The sign-in to Microsoft Graph requests delegated permissions only. The script
    uses each permission with the account of the signed-in Global Administrator.

      Run                          Delegated permission
      Every run                    Directory.Read.All
      Every run                    User.Read
      Every run                    AppRoleAssignment.ReadWrite.All
      A run with -AgentGrantsFile  DelegatedPermissionGrant.ReadWrite.All

    OUTPUT

    The script prints a summary table. The script also writes two files.
      - The log file NeologikAgentAccess_<time stamp>.log, from the first line of
        the run: every message, each failed request to Microsoft Graph with its
        status and request id, and the summary table.
      - The summary file Neologik_AgentAccess_<time stamp>.json: every item of the
        run. The script writes the summary file on every exit, a run that stopped
        before its steps included.

    No file holds a secret. The script writes the files to the folder of the
    script. When the script cannot write to that folder, the script writes to the
    current folder. When the script cannot write to the current folder, the script
    writes to the temporary folder. The run ends with the list FILES TO SEND TO
    NEOLOGIK.

.PARAMETER AgentGrantsFile
    The JSON file of grants to agent users. The Neologik Context Engine exports
    the file. The file names the tenant and the environment.

.PARAMETER MailboxGrantsFile
    The JSON file of mailbox grants. The Neologik Context Engine exports the file.

.PARAMETER RemoveLegacyGrantAppIds
    The application id of each identity that the environment has stopped using. The
    script removes the Exchange Online role assignments of each identity. The
    parameter requires -MailboxGrantsFile. The script keeps the role assignments of
    an identity that the mailbox grants file records as still in use.

.PARAMETER TenantId
    The id of your Microsoft Entra tenant. The agent grants file names the tenant,
    so the command needs the parameter only with a mailbox grants file alone that
    names no tenant. A file of another tenant stops the run.

.PARAMETER SolutionShortName
    The short name of the environment, for example abcprd01. The agent grants file
    names the environment, so the command needs the parameter only when the file
    does not. The script finds the SharePoint application of the environment by
    the short name.

.PARAMETER SharePointAppClientId
    The client id of the application 'Neologik SharePoint Access - <short name>'.
    Optional. With the parameter the script finds the SharePoint application by
    the client id.

.PARAMETER Verify
    The script reports each change that the run would make as a 'WOULD' item in the
    summary. The script writes nothing. The sign-ins are the same as the sign-ins
    of a run that writes. The exit code is 1 when a change is pending or an item
    needs attention. Otherwise the exit code is 0.

.PARAMETER UseAzureCliToken
    The script signs in to Microsoft Graph with the Azure CLI session of the
    workstation. The script shows no sign-in prompt. Neologik uses the parameter.
    Leave the parameter out of the command.

.EXAMPLE
    ./Grant-NeologikAgentAccess.ps1 -AgentGrantsFile ./agent-grants-abcprd01.json

    The script applies the grants to agent users that the file lists.

.EXAMPLE
    ./Grant-NeologikAgentAccess.ps1 -AgentGrantsFile ./agent-grants-abcprd01.json -MailboxGrantsFile ./mailbox-grants-abcprd01.json

    The script applies both files in one run.

.EXAMPLE
    ./Grant-NeologikAgentAccess.ps1 -MailboxGrantsFile ./mailbox-grants-abcprd01.json -RemoveLegacyGrantAppIds 11111111-2222-3333-4444-555555555555

    The script applies the mailbox grants that the file lists. The script also removes the role assignments of one identity that the environment has stopped using.

.EXAMPLE
    ./Grant-NeologikAgentAccess.ps1 -AgentGrantsFile ./agent-grants-abcprd01.json -Verify

    The script reports each pending grant and writes nothing.

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

    The sign-in to Exchange Online follows the same order. The browser signs in
    with the same account, so the browser does not usually ask again.

    Checks. Before the script changes anything, the script confirms three facts.
      1. The workstation can reach each Microsoft address that the script uses.
      2. The PowerShell modules load.
      3. The signed-in account holds an active Global Administrator role.
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
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPositionalParameters', 'Get-NeologikProperty', Justification = 'Get-NeologikProperty takes the object, the name and the default value in that order. Named parameters would make each call three times as long.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The script reads the current state before each write. A second run changes nothing that the first run completed.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AgentGrantsFile,

    [Parameter(Mandatory = $false)]
    [string]$MailboxGrantsFile,

    [Parameter(Mandatory = $false)]
    [string[]]$RemoveLegacyGrantAppIds,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$SolutionShortName,

    [Parameter(Mandatory = $false)]
    [string]$SharePointAppClientId,

    [Parameter(Mandatory = $false)]
    [switch]$Verify,

    [Parameter(Mandatory = $false)]
    [switch]$UseAzureCliToken
)

$script:GraphSpAppId = '00000003-0000-0000-c000-000000000000'
# The start of the name of the SharePoint application. The SharePoint application
# holds the permission Sites.Selected. The script checks the consent when the agent
# grants file records SharePoint ingestion. The script grants Sites.Selected when an
# earlier SharePoint application of Neologik holds a SharePoint permission.
$script:SharePointAppDisplayNamePrefix = 'Neologik SharePoint Access - '
$script:GraphV1 = 'https://graph.microsoft.com/v1.0'
$script:GraphBeta = 'https://graph.microsoft.com/beta'
$script:GuidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
# A summary result that matches this pattern needs attention and sets the exit code
# to 1. The pattern includes each 'WOULD' change that a run with -Verify reports.
$script:AttentionPattern = 'MISSING|SKIPPED|NOT FOUND|PENDING|FAILED|UNKNOWN|WOULD'

# Sign-in. The script runs the sign-in itself. The first method is a sign-in in the
# browser of this computer. The second method is a device code. The script prints what
# the script waits for, waits for a limited time, and tries the next method when a
# method fails. Many organisations block the device code with a Conditional Access
# policy, so the device code is not the first method. The sign-in uses the public
# client id of one Microsoft application: Microsoft Graph Command Line Tools. The
# sign-in uses no Neologik application.
$script:GraphPublicClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
$script:LoginEndpoint = 'https://login.microsoftonline.com'
# The longest time that the script waits for the browser sign-in, in seconds.
$script:BrowserMaximumWaitSeconds = 300
# The longest time that the script waits for one device code, in seconds.
$script:DeviceCodeMaximumWaitSeconds = 900
# How often the script reports that the script still waits for a sign-in, in seconds.
$script:SignInReportEverySeconds = 30
# The role template of Global Administrator. The script checks the signed-in account
# against the role template.
$script:GlobalAdministratorTemplateId = '62e90394-69f5-4237-9190-012177145e10'
# Each address that the script uses. Each address must answer before the script
# changes anything. A run with a mailbox grants file adds Exchange Online.
$script:PreflightEndpoints = @(
    @{ Name = 'Microsoft Entra sign-in'; Uri = 'https://login.microsoftonline.com/' },
    @{ Name = 'Microsoft Graph'; Uri = 'https://graph.microsoft.com/' },
    @{ Name = 'PowerShell Gallery, for the PowerShell modules'; Uri = 'https://www.powershellgallery.com/' }
)
$script:ExchangeEndpoint = @{ Name = 'Exchange Online'; Uri = 'https://outlook.office365.com/' }
# The script requires Microsoft Graph PowerShell 2.0 or later and
# ExchangeOnlineManagement 3.0 or later.
$script:GraphModuleMinimumVersion = [version]'2.0.0'
$script:ExchangeModuleMinimumVersion = [version]'3.0.0'
$script:GraphModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Applications'
)
$script:Summary = @()
# The state of the run: the inputs and the principals that the script found.
$script:State = @{}
# The version of the onboarding kit that ships the script. The header, the log file
# and the summary file name the version.
$script:KitVersion = 'v5.1.1'
# The log file of the run. The script writes every message to the log file from the
# first line. The reason a run ended before its steps, for the summary file.
$script:LogFile = $null
$script:ExitReason = ''
# The summary file of the run.
$script:SummaryFile = $null

# ----- Console, log file and summary ---------------------------------------------

function Start-NeologikLogFile {
    # Creates the log file of the run in the first folder that accepts a file: the folder
    # of the script, else the current folder, else the temporary folder. The log file
    # holds every message of the run and no secret. A run without a log file continues.
    $fileName = 'NeologikAgentAccess_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss')
    $first = "Neologik agent access script, onboarding kit $($script:KitVersion). The run started at $((Get-Date).ToUniversalTime().ToString('o'))"
    foreach ($directory in @(Get-NeologikSummaryDirectory)) {
        $path = Join-Path $directory $fileName
        try {
            Set-Content -LiteralPath $path -Value $first -Encoding UTF8 -ErrorAction Stop
            $script:LogFile = $path
            return
        }
        catch { continue }
    }
    $script:LogFile = $null
    Write-Host 'The script could not create the log file in any folder. The script continues without the log file' -ForegroundColor Yellow
}

function Add-NeologikLogText {
    # Appends one line to the log file. A failure to write never stops the run.
    param([string]$Text)
    if (-not $script:LogFile) { return }
    try { Add-Content -LiteralPath $script:LogFile -Value $Text -Encoding UTF8 -ErrorAction Stop }
    catch {
        $script:LogFile = $null
        Write-Host "The script could not write to the log file. The script continues without the log file. $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

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
    Add-NeologikLogText "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
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
    Add-NeologikLogText "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [ActionRequired] $(($Message -split "`n" | ForEach-Object { $_.Trim() }) -join ' ')"
}

function Add-Summary {
    param([string]$Item, [string]$Result)
    $script:Summary += [pscustomobject]@{ Item = $Item; Result = $Result }
    Add-NeologikLogText "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [Summary] ${Item}: $Result"
}

function Exit-NeologikRun {
    # Ends a run that stopped before its steps. The function records the reason as the
    # item 'Run', writes the summary file and returns the exit code 1, so that the
    # administrator always has a summary file and a log file to send.
    param([string]$Reason)
    $script:ExitReason = $Reason
    Add-Summary 'Run' "FAILED: $Reason"
    $code = Write-NeologikSummary
    Write-NeologikFileList
    return $code
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
    # A run with a mailbox grants file contacts Exchange Online, so that address must
    # answer too.
    $endpoints = @($script:PreflightEndpoints)
    if ($script:State.MailboxGrantsFile) { $endpoints += @($script:ExchangeEndpoint) }
    foreach ($endpoint in $endpoints) {
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

function Get-NeologikHeaderValue {
    # Reads one response header by name, whatever the case of the name. Returns an
    # empty string when the header is absent.
    param($Headers, [string]$Name)
    if ($Headers -is [System.Collections.IDictionary]) {
        foreach ($key in @($Headers.Keys)) {
            if ("$key" -eq $Name) { return [string](@($Headers[$key]) | Select-Object -First 1) }
        }
    }
    return ''
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
        # The log file records every failed request in full: method, address, status,
        # the request id of Microsoft Graph and the error text. The request id lets
        # Microsoft find the request. The body of a request is never logged.
        Add-NeologikLogText "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [Graph] $Method $Uri returned HTTP $status. request-id $(Get-NeologikHeaderValue -Headers $result.Headers -Name 'request-id'). $(Get-NeologikGraphErrorMessage -StatusCode $status -Method $Method -Uri $Uri -Body $result.Body)"
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
    Reads each input from the two files and from the parameters. Checks each id
    and each input file. Fills $script:State. Reports each problem as an
    ArgumentException that states the exact correction. The agent grants file
    names the tenant and the environment, so a command needs no other value.
    #>
    param([hashtable]$Parameters)
    $state = $script:State
    foreach ($name in @('AgentGrantsFile', 'MailboxGrantsFile', 'TenantId', 'SolutionShortName', 'SharePointAppClientId')) {
        $state[$name] = ([string](Get-NeologikProperty $Parameters $name '')).Trim()
    }
    $state.RemoveLegacyGrantAppIds = @(Get-NeologikProperty $Parameters 'RemoveLegacyGrantAppIds' @() | Where-Object { $_ })
    $state.UseAzureCliToken = [bool](Get-NeologikProperty $Parameters 'UseAzureCliToken' $false)
    $state.Verify = [bool](Get-NeologikProperty $Parameters 'Verify' $false)
    $state.ShortName = $state.SolutionShortName
    $state.ShortNameSource = if ($state.ShortName) { '-SolutionShortName' } else { '' }
    $state.TenantIdSource = if ($state.TenantId) { '-TenantId' } else { '' }
    $state.AgentGrants = $null
    $state.MailboxGrants = @()
    $state.AdoptedIdentityAppIds = @()

    if (-not $state.AgentGrantsFile -and -not $state.MailboxGrantsFile) {
        throw [System.ArgumentException]::new('The command names no grants file. Add -AgentGrantsFile, -MailboxGrantsFile or both. The Neologik Context Engine exports each file.')
    }
    if ($state.TenantId -and -not (Test-NeologikGuid $state.TenantId)) {
        throw [System.ArgumentException]::new("TenantId must be a GUID. The value is '$($state.TenantId)'.")
    }
    if ($state.SharePointAppClientId -and -not (Test-NeologikGuid $state.SharePointAppClientId)) {
        throw [System.ArgumentException]::new("SharePointAppClientId must be a GUID. The value is '$($state.SharePointAppClientId)'.")
    }
    foreach ($legacyAppId in $state.RemoveLegacyGrantAppIds) {
        if (-not (Test-NeologikGuid $legacyAppId)) {
            throw [System.ArgumentException]::new("RemoveLegacyGrantAppIds must hold application ids, each a GUID. One value is '$legacyAppId'.")
        }
    }
    if ($state.RemoveLegacyGrantAppIds.Count -gt 0 -and -not $state.MailboxGrantsFile) {
        throw [System.ArgumentException]::new('RemoveLegacyGrantAppIds needs the mailbox grants file. Add -MailboxGrantsFile to the command. The mailbox grants file lists each identity that an email channel still uses. The script never removes the role assignments of those identities.')
    }

    if ($state.AgentGrantsFile) {
        $grantsFile = Read-NeologikJsonFile -Path $state.AgentGrantsFile -Label 'agent grants file'
        if ($grantsFile -is [System.Array] -or $null -eq $grantsFile -or -not (Test-NeologikProperty $grantsFile 'grants')) {
            throw [System.ArgumentException]::new("The agent grants file is not the file that the Neologik Context Engine exports: $($state.AgentGrantsFile). The file must hold 'grants', 'componentGraphRoles' and 'sharePointIngestion'.")
        }
        $fileTenant = ([string](Get-NeologikProperty $grantsFile 'tenantId' '')).Trim()
        if ($fileTenant -and -not (Test-NeologikGuid $fileTenant)) {
            throw [System.ArgumentException]::new("The agent grants file names a tenant that is not a GUID: '$fileTenant'. Ask for a new agent grants file.")
        }
        if ($fileTenant -and $state.TenantId -and $fileTenant -ne $state.TenantId) {
            throw [System.ArgumentException]::new("The agent grants file belongs to tenant $fileTenant. This run is for tenant $($state.TenantId). Ask for the agent grants file of the environment in tenant $($state.TenantId).")
        }
        if ($fileTenant -and -not $state.TenantId) {
            $state.TenantId = $fileTenant
            $state.TenantIdSource = 'the agent grants file'
        }
        $fileEnvironment = ([string](Get-NeologikProperty $grantsFile 'environment' '')).Trim()
        if ($fileEnvironment -and -not $state.ShortName) {
            $state.ShortName = $fileEnvironment
            $state.ShortNameSource = 'the agent grants file'
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
            $fileTenant = ([string](Get-NeologikProperty $mailboxFile 'tenantId' '')).Trim()
            if ($fileTenant -and -not (Test-NeologikGuid $fileTenant)) {
                throw [System.ArgumentException]::new("The mailbox grants file names a tenant that is not a GUID: '$fileTenant'. Ask for a new mailbox grants file.")
            }
            if ($fileTenant -and $state.TenantId -and $fileTenant -ne $state.TenantId) {
                throw [System.ArgumentException]::new("The mailbox grants file belongs to tenant $fileTenant. This run is for tenant $($state.TenantId). Ask for the mailbox grants file of the environment in tenant $($state.TenantId).")
            }
            if ($fileTenant -and -not $state.TenantId) {
                $state.TenantId = $fileTenant
                $state.TenantIdSource = 'the mailbox grants file'
            }
            $rawEntries = @(Get-NeologikProperty $mailboxFile 'grants' @())
            $adopted = @(@(Get-NeologikProperty $mailboxFile 'adoptedIdentityAppIds' @()) | ForEach-Object { [string]$_ } | Where-Object { $_.Trim() })
        }
        else {
            throw [System.ArgumentException]::new("The mailbox grants file is not the file that the Neologik Context Engine exports: $($state.MailboxGrantsFile). The file must hold a list of entries, or 'grants' and 'adoptedIdentityAppIds'.")
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

    if (-not $state.TenantId) {
        throw [System.ArgumentException]::new('The command does not give TenantId, and no file names the tenant. Add -TenantId to the command.')
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
    $runTitle = 'the grants run'
    if ($state.Verify) { $runTitle = "$runTitle with -Verify" }
    # The header goes to the console and to the log file.
    $lines = @('', '=============================================================', " Neologik agent access: $runTitle",
        '=============================================================', "  Onboarding kit:                             $($script:KitVersion)",
        '  The run applies the grants that the files list. The run makes no other change.')
    if ($state.Verify) { $lines += '  -Verify: the script reports each change as WOULD and writes nothing.' }
    $lines += "  Tenant:                                     $($state.TenantId), from $($state.TenantIdSource)"
    if ($state.ShortName) { $lines += "  Short name of the environment:              $($state.ShortName), from $($state.ShortNameSource)" }
    if ($state.SharePointAppClientId) { $lines += "  SharePoint application:                     $($state.SharePointAppClientId)" }
    if ($state.AgentGrants) { $lines += "  Agent grants file:                          $($state.AgentGrantsFile)" }
    if ($state.MailboxGrantsFile) { $lines += "  Mailbox grants file:                        $($state.MailboxGrantsFile), $($state.MailboxGrants.Count) mailbox grant(s)" }
    if ($state.AdoptedIdentityAppIds.Count -gt 0) { $lines += "  Identities that an email channel uses:      $($state.AdoptedIdentityAppIds -join ', ')" }
    if ($state.RemoveLegacyGrantAppIds.Count -gt 0) { $lines += "  Mailbox grants to remove:                   $($state.RemoveLegacyGrantAppIds -join ', ')" }
    if ($script:LogFile) { $lines += "  Log file:                                   $($script:LogFile)" }
    $lines += ''
    foreach ($line in $lines) {
        $colour = if ($line -match '^(=| Neologik agent access)') { 'Cyan' } elseif ($line -match '^\s+-Verify') { 'Yellow' } else { 'Gray' }
        if ($line) { Write-Host $line -ForegroundColor $colour } else { Write-Host '' }
    }
    Add-NeologikLogText (($lines | Where-Object { $_ }) -join "`n")
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
    # Directory.Read.All reads the service principals and the directory roles of the
    # signed-in account. AppRoleAssignment.ReadWrite.All grants the Microsoft Graph
    # application permissions of workload identities and Sites.Selected.
    $scopes = @('Directory.Read.All', 'User.Read', 'AppRoleAssignment.ReadWrite.All')
    if ($state.AgentGrants) {
        # A grant to an agent user is an oAuth2PermissionGrant. Only a Global Administrator
        # can write an oAuth2PermissionGrant. The deployment identity cannot.
        $scopes += 'DelegatedPermissionGrant.ReadWrite.All'
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
    # Reads the service principal of Microsoft Graph. The script finds each
    # application permission by name on that service principal, and can grant
    # nothing without the object.
    $state = $script:State
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


# ----- The SharePoint consent ------------------------------------------------------

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
    the agent grants file records SharePoint ingestion. The function then prints
    the consent address when no application holds a SharePoint permission.
    #>
    param([switch]$IngestionRecorded)
    $state = $script:State
    $graphSp = $state.GraphSp
    $item = 'SharePoint Sites.Selected consent'
    try {
        $found = Get-NeologikSharePointApplication
        if ($found.Ambiguous) {
            Write-Log '  This tenant holds several SharePoint applications. The script cannot choose without the short name of the environment. Add -SolutionShortName or -SharePointAppClientId to the command' -Level Warning
            Add-Summary $item 'UNKNOWN: the tenant holds several SharePoint applications. Add -SolutionShortName or -SharePointAppClientId to the command'
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

# ----- The two steps ---------------------------------------------------------------

function Set-NeologikAgentUserGrant {
    # Step 1: the grants to agent users, the application permissions and the check of
    # the SharePoint consent.
    $state = $script:State
    $grantsFile = $state.AgentGrants
    Write-Log 'Step 1: the grants to agent users from the agent grants file' -Level Info
    foreach ($entry in @(Get-NeologikProperty $grantsFile 'grants' @())) {
        $kind = [string](Get-NeologikProperty $entry 'kind' 'agent')
        $name = [string](Get-NeologikProperty $entry 'name' 'no name')
        if ([string](Get-NeologikProperty $entry 'status' '') -ne 'ready') {
            Write-Log "  $kind '$name': the agent grants file marks the entry as not ready. Export a new agent grants file when the entry is ready" -Level Warning
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
            Write-Log "  ${app}: an entry in the agent grants file lacks roleName or identityName. Report the entry to Neologik" -Level Warning
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
    Step 2: the Exchange Online mailbox grants of the email channels. The function
    also removes the role assignments of each identity that the environment has
    stopped using. An identity that the file lists under adoptedIdentityAppIds keeps
    the role assignments.
    #>
    $state = $script:State
    Write-Log 'Step 2: the Exchange Online mailbox grants of the email channels' -Level Info
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


# ----- The run, the summary and the file list ------------------------------------

function Invoke-NeologikGrantsRun {
    # The grants run: the agent grants file, then the mailbox grants file.
    $state = $script:State
    if ($state.AgentGrants) { Set-NeologikAgentUserGrant }
    if ($state.MailboxGrantsFile) { Set-NeologikMailboxGrant }
}

function Get-NeologikRunFile {
    # The files of the run that exist: the log file and the summary file, in that
    # order.
    return @(@($script:LogFile, $script:SummaryFile) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) })
}

function Write-NeologikFileList {
    # Prints and logs the files of the run for the administrator to send to Neologik.
    $files = @(Get-NeologikRunFile)
    $lines = @('', 'FILES TO SEND TO NEOLOGIK')
    if ($files.Count -eq 0) { $lines += '  The run wrote no file. Send the text on screen' }
    foreach ($file in $files) { $lines += "  $file" }
    $lines += ''
    foreach ($line in $lines) { if ($line) { Write-Host $line -ForegroundColor Cyan } else { Write-Host '' } }
    Add-NeologikLogText (($lines | Where-Object { $_ }) -join "`n")
}

function Write-NeologikSummary {
    # Prints the summary table and writes the summary file. Returns the exit code: 0
    # when no item needs attention, otherwise 1.
    $state = $script:State
    Write-Host ''
    Write-Host '============================ SUMMARY ============================' -ForegroundColor Cyan
    if ($script:Summary.Count -gt 0) {
        $table = $script:Summary | Format-Table -AutoSize | Out-String
        Write-Host $table
        Add-NeologikLogText "SUMMARY`n$table"
    }
    else {
        Write-Host '  The script checked no item. Read the messages above'
    }
    $attention = @($script:Summary | Where-Object { $_.Result -match $script:AttentionPattern })
    # A step that checks several things reports the item as one line, with the word
    # WOULD inside the line. The count takes each item that reports a change.
    $pending = @($script:Summary | Where-Object { $_.Result -match '\bWOULD ' })
    # The summary file in JSON: every item of the run. The function writes the summary
    # file to the folder of the script. The summary file holds no secret.
    try {
        $json = [pscustomobject]@{
            kitVersion              = $script:KitVersion
            tenantId                = [string](Get-NeologikProperty $state 'TenantId' '')
            solutionShortName       = [string](Get-NeologikProperty $state 'ShortName' '')
            signedInAccount         = [string](Get-NeologikProperty $state 'SignedInUpn' '')
            verifyOnly              = [bool](Get-NeologikProperty $state 'Verify' $false)
            ranAt                   = (Get-Date).ToUniversalTime().ToString('o')
            # The log file of the run, and the reason when the run ended before its steps.
            logFile                 = [string]$script:LogFile
            exitReason              = [string]$script:ExitReason
            agentGrantsFile         = [string](Get-NeologikProperty $state 'AgentGrantsFile' '')
            mailboxGrantsFile       = [string](Get-NeologikProperty $state 'MailboxGrantsFile' '')
            removeLegacyGrantAppIds = @(Get-NeologikProperty $state 'RemoveLegacyGrantAppIds' @())
            items                   = @($script:Summary)
            attentionCount          = $attention.Count
            pendingChangeCount      = $pending.Count
        } | ConvertTo-Json -Depth 5
        $fileName = 'Neologik_AgentAccess_{0}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss')
        $written = $null
        foreach ($directory in @(Get-NeologikSummaryDirectory)) {
            $summaryPath = Join-Path $directory $fileName
            try {
                Set-Content -LiteralPath $summaryPath -Value $json -Encoding UTF8 -ErrorAction Stop
                $written = $summaryPath
                $script:SummaryFile = $summaryPath
                break
            }
            catch {
                Write-Log "The script could not write the summary file to $directory. $(Get-NeologikErrorText $_). The script tries the next folder" -Level Warning
            }
        }
        $logNote = if ($script:LogFile) { " and the log file $($script:LogFile)" } else { '' }
        if ($written) { Write-Log "The script wrote the summary file to $written. Send the summary file$logNote to Neologik" -Level Info }
        else { Write-Log "The script could not write the summary file to any folder. Send the summary table$logNote to Neologik" -Level Warning }
    }
    catch {
        Write-Log "The script could not write the summary file. $(Get-NeologikErrorText $_)" -Level Warning
    }
    if ($attention.Count -gt 0) {
        if ($pending.Count -gt 0) {
            Write-Log "A run without -Verify would change $($pending.Count) item(s). The script wrote nothing" -Level Warning
        }
        Write-Log "$($attention.Count) item(s) need attention. Read the summary above" -Level Warning
        return 1
    }
    if (Get-NeologikProperty $state 'Verify' $false) {
        Write-Log 'The grants run with -Verify is complete. A run without -Verify would change nothing. Every grant is in the expected state' -Level Success
    }
    else {
        Write-Log 'The grants run is complete. Every grant is in the expected state' -Level Success
    }
    return 0
}

# ----- Main entry ---------------------------------------------------------------

function Invoke-NeologikAgentAccess {
    <#
    Runs the script. Returns the exit code: 0 when every grant is in the expected
    state, 1 when an item needs attention. The function never throws. The function
    reports each failure together with the action to take.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [string]$AgentGrantsFile,
        [string]$MailboxGrantsFile,
        [string[]]$RemoveLegacyGrantAppIds,
        [string]$TenantId,
        [string]$SolutionShortName,
        [string]$SharePointAppClientId,
        [switch]$Verify,
        [switch]$UseAzureCliToken
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $script:Summary = @()
    $script:State = @{}
    $script:ExitReason = ''
    $script:SummaryFile = $null
    # The log file comes first, so that the log file holds every message of the run.
    Start-NeologikLogFile

    if (-not (Test-NeologikPowerShellVersion)) { return (Exit-NeologikRun 'the version of PowerShell is too old. Read the messages above') }

    try {
        Resolve-NeologikInput -Parameters @{
            AgentGrantsFile         = $AgentGrantsFile
            MailboxGrantsFile       = $MailboxGrantsFile
            RemoveLegacyGrantAppIds = @($RemoveLegacyGrantAppIds)
            TenantId                = $TenantId
            SolutionShortName       = $SolutionShortName
            SharePointAppClientId   = $SharePointAppClientId
            Verify                  = [bool]$Verify
            UseAzureCliToken        = [bool]$UseAzureCliToken
        }
    }
    catch [System.ArgumentException] {
        Write-Log $_.Exception.Message -Level Error
        Write-ActionRequired $_.Exception.Message
        return (Exit-NeologikRun "an input is wrong. $($_.Exception.Message)")
    }
    catch {
        Write-Log "The script could not read the inputs. $(Get-NeologikErrorText $_)" -Level Error
        Write-ActionRequired "The script could not read the inputs. $(Get-NeologikErrorText $_)"
        return (Exit-NeologikRun "the script could not read the inputs. $(Get-NeologikErrorText $_)")
    }

    Write-NeologikHeader

    # Each address that the run uses must answer before the script changes anything.
    Write-Log 'The script checks that this workstation can reach each Microsoft address' -Level Info
    if (-not (Test-NeologikPreflightEndpoint)) { return (Exit-NeologikRun 'a Microsoft address did not answer. Read the messages above') }

    if (-not (Import-NeologikModuleSet -Names $script:GraphModules -MinimumVersion $script:GraphModuleMinimumVersion `
                -InstallHint 'Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Applications -Scope CurrentUser -Force')) {
        return (Exit-NeologikRun 'the Microsoft Graph modules did not load. Read the messages above')
    }
    if (-not (Connect-NeologikGraph)) { return (Exit-NeologikRun 'the sign-in to Microsoft Graph did not complete, or the signed-in account is not a Global Administrator. Read the messages above') }
    if (-not (Resolve-NeologikPrincipal)) { return (Exit-NeologikRun 'the Microsoft Graph service principal was not found. Read the messages above') }

    try { Invoke-NeologikGrantsRun }
    catch {
        $reason = Get-NeologikErrorText $_
        Write-Log "An unexpected error stopped the run. $reason" -Level Error
        Add-Summary 'Run' "FAILED: unexpected error. $reason"
    }
    $code = Write-NeologikSummary
    Write-NeologikFileList
    return $code
}

# When a caller loads the script with a dot, PowerShell defines the functions and
# runs nothing.
if ($MyInvocation.InvocationName -ne '.') {
    $neologikExitCode = Invoke-NeologikAgentAccess @PSBoundParameters
    exit ([int](@($neologikExitCode)[-1]))
}
