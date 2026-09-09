# Neo Client Onboarding Scripts Version History

This document tracks the version history of the Neologik customer onboarding scripts deployed from the main branch, including significant changes, dependencies, and infrastructure requirements.

**Version Format**: `MAJOR.MINOR.PATCH` (currently: `1.9.x`)
- Major version: 1
- Minor version: 9
- Patch number: Incremented with each release

---

## Unreleased - The configuration summary records the two-role Graph set (project#2342)
**Date**: 2026-09-09

- `Install-NeologikEnvironment.ps1` still wrote `Application.Read.All` into
  the deployment identity's `GraphAppRoles` in the configuration summary
  (script-created and client-supplied service principals alike) and carried
  it as the `Grant-GraphAppRolePermissions` default, a remnant of the
  pre-project#2144 model. The grant call itself was already correct. The
  summary and the default now record the least-privilege set the script
  grants: `Application.ReadWrite.OwnedBy` and
  `AgentIdentityBlueprint.AddRemoveCreds.All`. No behaviour change in what
  is granted.
- https://github.com/Neologik-AI/project/issues/2342

## Unreleased - The directory-role checks read the identity's memberOf list (project#2297 dev03 finding)
**Date**: 2026-09-08

- Microsoft Graph's `directoryRoles/{id}/members` list omits service
  principals (verified on the development tenant: the Agent ID Administrator
  role listed no members while its typed service-principal list named the
  dev03 deployment identity). Steps 4c (Application Administrator) and 4f
  (every other directory role) of `Update-NeologikEnvironmentAccess.ps1`
  read that list and so reported "not held" and "none" for roles the
  identity holds. Both now read the identity's own `memberOf` list
  (`Get-MgServicePrincipalMemberOf`, the read step 4g already uses) through
  `Get-NeologikDirectoryRoleHeld`; a read failure is reported as FAILED,
  never as not held.
- Tests: the fake tenant's `memberOf` returns directory roles; the two
  role-list cmdlets throw if called; a case proves both steps find and
  remove the roles without them (Pester 131).

## Unreleased - Declared set or nothing: the pre-window run removes every undeclared role and membership (project#2297)
**Date**: 2026-09-08

- Owner decision 2026-09-08 (https://github.com/Neologik-AI/project/issues/2297):
  the deployment service principal holds the declared set and nothing else.
  `Update-NeologikEnvironmentAccess.ps1` step 4 gains three parts after the
  Admin User Group step: 4e removes every Azure role assignment the principal
  holds in the subscription outside the declared set (the narrow
  resource-group roles, the two retained subscription roles, and the declared
  resource-scoped Cognitive Services Content Understanding Contributor below
  the group); 4f removes every directory role other than Application
  Administrator (which keeps step 4c); 4g removes every group membership
  other than the Admin User Group (which keeps the guarded step 4d).
  `-Verify` reports each as a pending removal; the early returns of step 4
  report the three items as skipped. Found by the audit under project#2269:
  the neo-evals harness had been granting the principal Azure AI Developer,
  Foundry User, Reader and Search Index Data Reader on every run (it now runs
  as the test-runner identity), and dev03 carried a legacy Agent ID
  Administrator role, a Neologik Dev Team membership and subscription-scope
  leftovers.
- Quick reference: the declared table gains the Content Understanding row and
  the declared-set-or-nothing note.
- Pester: 130 passed (five new cases: compliant, removal with the declared
  resource-scoped role kept, verify-only pending changes, narrow set
  incomplete, refused group removal).

## Unreleased - Az modules import at their own versions (project#2269 dev03 finding)
**Date**: 2026-09-08

- The first dev03 `-Verify` run after the Admin User Group step failed its
  Azure half with "module 'Az.Accounts' with version '7.1.0' was not loaded":
  `Import-NeologikModuleSet` pins one common version across a module set,
  which is right for the Microsoft.Graph family and wrong for the Az family
  (Az.Accounts 5.5, Az.Resources 10.0 and Az.Sql 7.1 never share a
  version). The Az set now imports with `-Independent`: each module at its
  own highest available version, no common pin. Pester 125.

## Unreleased - The deployment principal leaves the Admin User Group; SQL access is the declared server administrator (project#2269)
**Date**: 2026-09-07

- Owner decision 2026-09-07 (option A on https://github.com/Neologik-AI/project/issues/2269): the deployment service
  principal is the SQL server's Microsoft Entra administrator, declared by
  the platform infrastructure deployment; the Admin User Group (the human
  administrators) is a `db_owner` contained user in every platform and App
  database, created by the platform deployments. The principal is never a
  member of the Admin User Group - a membership silently added every
  resource-group role the group holds to the deployment identity, and was
  the principal's only SQL access.
- `Install-NeologikEnvironment.ps1` no longer adds the service principal
  to the Admin User Group.
- `Update-NeologikEnvironmentAccess.ps1`: step 4d of the pre-window
  permission reduction removes an existing membership, and does so ONLY
  once every SQL server in the resource group names the deployment identity
  as its Entra administrator (Az.Sql reads; otherwise the membership is
  reported as HELD and kept, with the reason). The Admin User Group is read
  from the configuration file's SecurityGroups or the new `-AdminGroupId`
  parameter; with neither the item reads "Not checked" and needs no
  attention. `-Verify` reports the removal as a pending change. The
  pre-window run requests the delegated scope `GroupMember.ReadWrite.All`
  for the removal.
- Quick reference: section 5 "Group Membership" now states the rule.
- Pester: 124 passed (ten new cases: not held, held while a server still
  names the group, removed once every server names the identity, held with
  one of two servers, held with no server yet, verify-only pending change,
  not checked without an id, explicit `-AdminGroupId`, the requested
  scopes, refused removal).
  One fixture change: the missing-group test now uses an id no fake object
  carries, since the Admin User Group is a real group in the fake tenant.

## Unreleased - -UseAzureCliToken signs the Azure half in too (project#2234 follow-up)
**Date**: 2026-09-07

- `Update-NeologikEnvironmentAccess.ps1 -UseAzureCliToken` now also signs
  in to Azure with the Azure CLI session (an ARM token from
  `az account get-access-token --resource https://management.azure.com/`
  for the tenant and subscription, the account read from the token's
  claims), so an engineer's verify-only pre-window run needs no device-code
  prompt for the permission reduction. Found on the first dev03 verify run
  of the single-session model: the switch covered Microsoft Graph only and
  the Azure sign-in fell back to a device code that expired. The CLI token
  carries no MFA claims challenge, so the switch suits `-Verify` runs and
  verification passes; a role write the tenant refuses with a claims
  challenge means running again without the switch. Customers keep the
  device-code sign-ins. Pester: 114 passed (two new cases: the CLI-token
  Azure sign-in, and ACTION REQUIRED with the reduction skipped when the
  CLI has no token for the subscription).

## Unreleased - Global Administrator script: single-session migration model, verify-only switch, adopted email identities (project#2234)
**Date**: 2026-09-07

- `Update-NeologikEnvironmentAccess.ps1` has no `-Phase` parameter: the
  files given select the run
  (https://github.com/Neologik-AI/project/issues/2234, owner decisions
  2026-09-07). With no grants file it is the pre-window run every customer
  has once before its migration window: the agent identity blueprint and
  its principal role, the deployment identity's Graph roles, the NCE user
  group assignment, the sign-in consent check, the SharePoint
  `Sites.Selected` check (when the configuration file records
  `SharePointIngestion`; otherwise the summary notes that the check runs
  with the agent grants file, needing no attention) and then the guarded
  permission reduction - the narrow resource-group roles and the two
  retained subscription roles applied before the broad subscription roles
  and the Application Administrator directory role are removed, nothing
  removed if any narrow role failed. `RoleManagement.ReadWrite.Directory`
  joins the pre-window sign-in scopes; `-SubscriptionId` and
  `-ResourceGroupName` are required for the pre-window run when the
  configuration file does not carry them.
- With `-AgentGrantsFile` and/or `-MailboxGrantsFile` it is the post-window
  run, needed only once an agent or App works unattended in Microsoft 365:
  it applies exactly what the files list - agent-user delegated grants,
  declared component Graph roles, the SharePoint check the file asks for,
  mailbox grants - and nothing else. The header, the closing line and the
  JSON summary (`run`: `PreWindow` or `PostWindow`, file name
  `Neologik_EnvironmentAccess_<run>_<stamp>.json`) name the run.
- `-Verify`: every step reports what it would change as a `WOULD ...`
  summary item and nothing is written; exit code 1 when anything would
  change. The gate sits in the two write seams every write passes through
  (`Invoke-NeologikGraph` for non-GET requests, `Invoke-NeologikWrite` for
  every SDK write cmdlet), so no step can bypass it.
- The mailbox grants file may be an object with `grants` and
  `adoptedIdentityAppIds` (client ids of the v4 email monitor identities
  the v5 email channel adopted); `-RemoveLegacyGrantAppIds` skips those
  ids with the summary line "Identity adopted by the v5 email channel -
  assignment kept", and requires `-MailboxGrantsFile` so the adopted list
  is always consulted. The bare array shape is still accepted.
- Review points from https://github.com/Neologik-AI/project/issues/2217:
  the read-only `Directory.Read.All` and `User.Read` sign-in scopes stay
  and are explained in FINISHING-STEPS-GUIDE.md ("What the sign-in asks
  you to approve"); scope-set comparison stays case-insensitive; the
  consent URL keeps `client_id` only (the run happens on a v4 environment
  where the confirmation page does not exist).
- Documents: the script header, FINISHING-STEPS-GUIDE.md (the two runs and
  the sign-in consent table), README.md and TECHNICAL-REFERENCE.md. The
  PDF copies are not regenerated in this change.
- Pester harness: 112 tests, 0 failed (`pwsh -NoProfile -Command
  "Invoke-Pester -Path tests -CI"`): the pre-window run performs the
  checks then the reduction, a narrow-role failure leaves the broad
  grants, the post-window run touches nothing else, `-Verify` writes
  nothing and exits 1, adopted identities are kept, and the parameter set
  refuses `-Phase`. PSScriptAnalyzer: 0 findings.

## Unreleased - Global Administrator script: zero-error run, exhaustive review and test harness (project#2217)
**Date**: 2026-09-06

- `Update-NeologikEnvironmentAccess.ps1` no longer stops on the first
  problem: every item is verified or applied independently, a failing item
  is recorded in the summary as `FAILED - <reason>` (never a stack trace),
  dependent items are recorded as `SKIPPED`, the summary table and the JSON
  summary are always written, and the exit code is 1 whenever any item needs
  attention. Pre-flight problems (missing or malformed input files, ids that
  are not GUIDs, a grants file exported from another tenant, PowerShell
  below 7.4, a module that cannot be installed, a sign-in that did not
  complete or landed in the wrong tenant) end with an ACTION REQUIRED block
  naming the correction.
- Narrow before broad is now enforced on failure as well as in order: the
  retired Graph roles (step 1d) and the legacy subscription roles and
  Application Administrator membership (PostWindow) are removed only when
  every retained or narrow role is confirmed in place.
- Sign-in scopes gain `Directory.Read.All` and `User.Read`, the read scopes
  the group, consent and directory-role checks need on a tenant where no
  earlier consent exists.
- Agent-user grants are matched by client, principal AND resource
  (Microsoft Graph), so a grant to another resource is never patched; a
  privilege refusal stops the rotation retries and names the missing
  permission.
- Microsoft Graph requests retry throttling (429) and transient service
  errors (502/503/504) with `Retry-After` honoured, retry a not-found right
  after a create (replication delay), and follow `@odata.nextLink` on every
  collection read (owners, credentials, principals).
- Module handling installs and imports ONE consistent version of the
  Microsoft.Graph modules (2.x) and ExchangeOnlineManagement (3.x) - mixed
  versions fail at import on an administrator's workstation; the Exchange
  session is always disconnected; `-UseAzureCliToken` checks the CLI exists
  and no longer terminates on a non-zero exit code.
- The JSON summary falls back to the current folder, then the temp folder,
  when the script folder is not writable; `UNKNOWN` results count as
  attention.
- New Pester 5 harness under `tests/` (every Graph, Azure, Exchange and
  console call replaced by an in-memory tenant model that records writes):
  `pwsh -NoProfile -Command "Invoke-Pester -Path tests -CI"`.
  PSScriptAnalyzer (default rules and PSUseCompatibleSyntax 7.4) reports no
  findings.

## Unreleased - Sites.Selected check resolves the environment's own SharePoint app (project#2213 dev03 finding)
**Date**: 2026-09-06

- Step 3a looked up the SharePoint access app by the name prefix alone and took the first match, so in a tenant hosting several environments it tested another environment's app (dev03 reported "consent missing" against neodev01's app while its own app held the consent). The check now resolves `Neologik SharePoint Access - <SolutionShortName>` from the configuration file first, accepts the prefix search only when it yields exactly one app, and otherwise reports the ambiguity instead of a wrong answer.

## Unreleased - One Global Administrator script per migration: agent-user grants, component roles, SharePoint consent, JSON summary (project#2213)
**Date**: 2026-09-05

- `Update-NeologikEnvironmentAccess.ps1` gains `-AgentGrantsFile <json>` (the
  file the platform exports from `GET /nce-api/v5/environment/agent-grants`):
  step 3a creates or aligns the agent-user delegated grant of every agent
  and App with ENABLED agent-lane permission packs, with exactly the
  exported scope set (read back and compared as sets; rotated retry on a
  refused scope string), grants the declared component Graph roles the
  deployment identity could not (unscoped, tenant-scoped reads only; scoped
  ones reported for the Exchange or SharePoint administrator), and checks
  the SharePoint app's `Sites.Selected` consent only when the file says
  SharePoint ingestion is part of the solution (consent URL printed when
  missing). Least exposure: an agent or App with no packs is absent from the
  file and gets no grant. The Window phase adds
  `DelegatedPermissionGrant.ReadWrite.All` to the sign-in scopes only when a
  grants file is given. The convergence of the deployment identity to exactly
  `Application.ReadWrite.OwnedBy` + `AgentIdentityBlueprint.AddRemoveCreds.All`
  is unchanged. Every run ends with a machine-readable summary
  (`Neologik_EnvironmentAccess_<phase>_<stamp>.json` beside the script: the
  deployment identity's Graph roles, every consent and grant state) for the
  migration ticket (https://github.com/Neologik-AI/project/issues/2213).

## Unreleased - Least-privilege Graph model for the deployment SP (project#2144)
**Date**: 2026-09-03

- The deployment service principal now receives two Microsoft Graph
  application permissions instead of eight: `Application.ReadWrite.OwnedBy`
  (manage only the app registrations it owns) and
  `AgentIdentityBlueprint.AddRemoveCreds.All` (add the per-agent Kubernetes
  credentials to the environment's agent identity blueprint). The six
  tenant-wide roles it no longer holds: Application.Read.All,
  AgentIdentityBlueprint.Create, AgentIdentityBlueprint.UpdateAuthProperties.All,
  AgentIdentityBlueprintPrincipal.Create, AgentIdentity.Create.All,
  AgentIdUser.ReadWrite.All.
- New onboarding step (New-NeologikAgentBlueprint, after the Platform
  Sign-in app): creates the environment's Entra Agent ID blueprint
  `Neologik Agent Blueprint - default - <short-name>` and its principal under
  the Global Administrator, sets the deployment SP as owner of both, grants
  the principal `AgentIdUser.ReadWrite.IdentityParentedBy` (agent users under
  that blueprint only), and adds three GitHub OIDC flexible federated
  credentials (one per Neologik pipeline repository, bound to the repository
  id) through which the deployment pipeline acts as the blueprint to mint
  agent identities and users. Exported as `AgentBlueprint` in the
  Configuration JSON.
- `Update-NeologikEnvironmentAccess.ps1` phase Window retro-fits existing
  environments: adopts the pipeline-created blueprint (ownership, principal,
  principal role, GitHub credentials), ensures the two retained roles, then
  removes the six retired roles from the deployment SP (narrow before broad).
  `-BlueprintKey` targets a non-default blueprint archetype.
- `Update-NeologikEnvironmentAccess.ps1 -UseAzureCliToken` signs in to Graph with
  the Azure CLI session token instead of the device-code prompt (whose
  120-second window is too short for a chat-driven hand-off); for Neologik
  engineers, customers keep device code. Proven on the dev03 retro-fit.
- Graph delegated scopes requested by the scripts gain the Agent ID scopes
  (AgentIdentityBlueprint.Create, AgentIdentityBlueprint.AddRemoveCreds.All,
  AgentIdentityBlueprintPrincipal.Create).

## Unreleased - Email channel mailbox grants in the GA migration script (project#990)
**Date**: 2026-09-03

- Update-NeologikEnvironmentAccess.ps1 gains Window step 3b: with
  -MailboxGrantsFile (JSON exported from the platform's email channel
  registrations - IdentityAppId, IdentityObjectId, Mailbox, DisplayName) it
  grants each agent's channel identity Application Mail.Read /
  Mail.ReadWrite / Mail.Send in Exchange Online scoped to the one mailbox
  (RBAC for Applications; nothing in Entra ID), reusing an existing
  management scope that names the mailbox (Exchange refuses duplicate
  recipient filters - the retired email monitor's scope is the usual
  case) and verifying with Test-ServicePrincipalAuthorization.
  -RemoveLegacyGrantAppIds removes a retired identity's assignments and
  pointer (the monitor at its migration window, decision 6 on
  https://github.com/Neologik-AI/project/issues/990). Both optional;
  without them the script is unchanged. Exchange sign-in is device code,
  like the Graph sign-in. A PENDING mailbox grant (propagation) is an
  attention item (exit 1) until a re-run confirms InScope.

## Unreleased - Storage uploads verified and surfaced (project#1652 process item 4)
**Date**: 2026-08-21

- The configuration JSON and log uploads are verified (blob read back)
  and drive the completion output: blob paths are shown only for files
  that landed, and a failed configuration upload raises a prominent
  warning with manual portal upload instructions - Neologik retrieves
  the JSON from the json container, so a silent failure stalls
  onboarding. Upload code deduplicated into Copy-NeologikFileToStorage.
- Non-interactive runs attempt the upload once instead of skipping it;
  it succeeds when the CI login can authenticate data-plane calls.

## Unreleased - Fixes from the dev06 v5 run transcript (project#1652)
**Branch**: `bugfix/v5-run-findings`
**Ticket**: https://github.com/Neologik-AI/project/issues/1652
**Date**: 2026-08-20

- Global Administrator and user lookups now use Invoke-MgGraphRequest (REST
  on the established Graph connection) instead of Get-MgUser /
  Get-MgDirectoryRole*, whose submodule assemblies can conflict with the
  loaded Microsoft.Graph.Authentication version and crash the check (the
  operator then always got the proceed-at-own-risk prompt). The GA check
  reads the signed-in user's active roles by roleTemplateId and no longer
  needs the role-activation write. New shared helper
  Find-NeologikUserByEmail replaces both guest/existing-account lookups.
- Completion Next Steps corrected per the certificate-route decisions on
  the ticket: the client provides the TLS certificate one of two ways -
  import the PFX directly into the environment Key Vault as
  'keyvault-neo-ingress' (password consumed at import, never stored), or
  upload to the deployment Storage Account 'certificate' container (a
  ready-made PFX, or the raw certificate files - private key, server
  certificate, CA bundle - for Neologik to assemble when the client
  cannot produce a PFX). Only a PFX uploaded to the Storage Account needs
  its password stored, as the Key Vault secret
  neologik-deployment-certificate-pfx-secret. The configuration JSON
  reaches Neologik via the storage account's json container - no send
  step needed.
- Console output cleaned: stray 'True' lines from the resource-provider
  registration loop and the bare configuration-file path echoed after the
  Next Steps block.

## Unreleased - Invite list extendable at the prompt (project#1064)
**Branch**: `feature/agent-platform`
**Ticket**: https://github.com/Neologik-AI/project/issues/1064
**Date**: 2026-08-17

- Accepting guest invitations interactively now lists the file's
  addresses and asks "Do you want to add any more addresses to invite?" -
  typed via the shared line-by-line reader (one per Enter, blank line to
  finish, commas accepted within a line, duplicates removed). With an
  empty or missing NeologikGuestUsers.txt, answering Y goes straight to
  typed entry, so the whole invite list can be built by hand.
- Existing accounts among the combined list are matched (no email), the
  rest receive B2B invitations, and everyone joins the groups - the
  invitation flow itself is unchanged.
- Configuration summary shows "Yes (N from file + M typed)"; unattended
  (-NonInteractive) runs use the file only.

## Unreleased - Add existing accounts to groups when invitations are declined (project#1064)
**Branch**: `feature/agent-platform`
**Ticket**: https://github.com/Neologik-AI/project/issues/1064
**Date**: 2026-08-17

- Declining guest invitations now offers a follow-up question: "Add
  existing accounts to the security groups?". Yes resolves pre-created
  accounts (B2B guests or members) by mail/userPrincipalName and adds
  them to the groups with NO invitation sent - for clients who provision
  the Neologik team's accounts themselves.
- Address sources, in precedence order: answer-file
  `existingAccountEmails` (array or comma string), NeologikGuestUsers.txt,
  or addresses typed at the prompt ([F]ile / [T]ype choice). Typed entry
  is line-by-line: one address per Enter, blank line to finish, commas
  accepted within a line for pasting a list; duplicates removed and the
  collected list echoed back with a count. New answer-file key
  `addExistingAccountsToGroups` (true/false); in -NonInteractive mode
  the file is the default source.
- Unresolvable addresses are reported ("does not exist in this tenant -
  skipped, continuing") and never stop the run.
- Prompt and docs warn that accounts added this way join ALL Neologik
  groups including the Admin User Group; configuration JSON gains an
  `ExistingAccountsAdded` section.
- Docs: README, TECHNICAL-REFERENCE, QUICK-REFERENCE (+ PDF),
  PRE-ONBOARDING-INFO-GATHERING, inputs-example.json.

## Unreleased - v5 documentation alignment (project#1527)
**Branch**: `feature/agent-platform`
**Ticket**: https://github.com/Neologik-AI/project/issues/1527
**Date**: 2026-08-17

- Customer-facing docs aligned with the v5.0.0 script: TECHNICAL-REFERENCE
  rewritten (v5 naming convention, no bots at onboarding, Platform Sign-in
  app, client-provided SP, CI mode, Reader/Cost Management Contributor
  subscription roles, Agent ID Graph roles, `Neologik_<org><index>_...`
  config filename, correct repo URL); QUICK-REFERENCE and secure-overview
  brought to the same facts; README, PRE-ONBOARDING-INFO-GATHERING and
  FINISHING-STEPS-GUIDE purged of bot-count / per-bot-group flow.
- Script text-only fixes: the non-interactive answer-file error no longer
  demands `bots[]` (validation requires organizationCode, organizationName,
  fqdn only) and the `-KeyVaultName` help shows the v5 default name shape.
  No behaviour change.
- QUICK-REFERENCE.pdf and secure-overview.pdf regenerated from the updated
  markdown (markdown -> HTML -> Edge headless print-to-PDF, A4;
  text-verified).
- New CREATE-SP-GUIDE.md: customer step-by-step for creating their own
  deployment service principal (portal + az CLI), the
  enterprise-application-object-ID distinction, secret-rotation
  responsibility, and the what-you-do-NOT-need-to-do list; linked from
  README, PRE-ONBOARDING-INFO-GATHERING, QUICK-REFERENCE and
  TECHNICAL-REFERENCE.

## Unreleased - Group.Create removed from the deployment SP grant set (project#1519)
**Branch**: `feature/agent-platform`
**Ticket**: https://github.com/Neologik-AI/project/issues/1519
**Date**: 2026-08-17

- The Microsoft Graph `Group.Create` application permission is no longer
  granted to the deployment SP (owner decision 2026-08-17, amending the
  2026-07-14 dedicated-group decision). The platform never creates Entra
  groups: agent channels reuse the onboarding default user group, or an
  admin supplies an existing group id at channel attach
  (`awaiting_user_group` create-and-paste path). Grant now matches
  exercised capability, continuing the issue #774 least-privilege model.
- Script comments claiming channel provisioning creates per-agent groups
  corrected to the reuse/paste model.
- Tenants already granted `Group.Create` keep the assignment until revoked
  as a separate operational action (tracked on the ticket).

## Unreleased - Pooja Pandey added to Neologik guest users (project#1448)
**Branch**: `feature/agent-platform`
**Ticket**: https://github.com/Neologik-AI/project/issues/1448
**Date**: 2026-08-13

- Pooja.Pandey@neologik.ai added to `NeologikGuestUsers.txt`, matching the
  hotfix already landed on main (7f1363d) and develop (d648d2d).

## Unreleased - Recover a missing NeologikGuestUsers.txt interactively (project#1383)
**Branch**: `feature/agent-platform`
**Ticket**: https://github.com/Neologik-AI/project/issues/1383
**Date**: 2026-08-10

Customers who download only `Install-NeologikEnvironment.ps1` (instead of
unzipping the full onboarding package) previously got a single startup warning
and a run that silently invited no Neologik guest users. Interactive runs now
recover at the guest-invitation configuration prompt via the new
`Resolve-GuestUsersFile`:

- Explains that the file ships in the onboarding zip (one email per line) and
  offers: [B] browse (Windows file-open dialog, topmost so it cannot hide
  behind the console), typing the full path, or [S] explicitly skipping guest
  invitations.
- The selected file is validated (exists, contains at least one non-comment
  entry) before being accepted; invalid choices re-prompt.
- Startup warning reworded to say interactive runs will offer to locate the
  file. Non-interactive (CI) mode behaviour unchanged (warn and continue;
  governed by `-SkipGuestInvitation` / answer file).

## Unreleased - Azure mandatory MFA: claims-challenge handling (project#1381)
**Branch**: `feature/agent-platform`
**Ticket**: https://github.com/Neologik-AI/project/issues/1381
**Date**: 2026-08-10

Azure now enforces MFA at the ARM layer for all resource create/update/delete
operations (mandatory MFA Phase 2, enforced since 1 October 2025; postponement
window closed 1 July 2026). A cached or freshly minted token without MFA passes
sign-in but fails the first resource write - observed in the field as
"Failed to create/validate resource group: ... disallowed by Azure ...
without authenticating through MFA" during a v4.5.0 onboarding.

- Interactive sign-in (`Invoke-AzConnect`) now requests the ARM 'p1'
  authentication-context claim via `Connect-AzAccount -ClaimsChallenge`, so the
  first token satisfies the enforcement (browser and device-code paths).
- Cached-context reuse inspects the ARM access token (new
  `Get-ArmTokenMfaClaimStatus`) and re-authenticates up front when a user token
  carries neither 'acrs' p1 nor 'amr' mfa.
- Reactive backstop: resource group creation catches the ARM MFA
  claims-challenge error, re-authenticates and retries once.
- Non-interactive (CI) mode never re-authenticates; it logs a clear warning
  when the supplied user token lacks the claim. Service principal tokens are
  exempt from mandatory MFA and unaffected.
- Same proactive claims challenge applied to the standalone sign-ins in
  `Register-NeologikResourceProviders.ps1` and
  `Update-NeologikEnvironmentAccess.ps1`.
- Dependencies: `Az.Accounts` minimum raised 3.0.0 -> 5.2.0 (first version
  with `Connect-AzAccount -ClaimsChallenge`).

## Unreleased - NCE delegation model groups (project#1341)
**Branch**: `feature/agent-platform`
**Ticket**: https://github.com/Neologik-AI/project/issues/1341
**Date**: 2026-08-06

- Group creation (Step 10): the NCE group is now created as
  `Neologik NCE Contributors - {org}-{env}` (NCE contributor role); a
  pre-existing `Neologik NCE User Group`/legacy-named group is RENAMED in
  place (object id and memberships unchanged). New group
  `Neologik NCE Admins - {org}-{env}` (NCE admin role - Blueprints,
  Audit, Admin page), seeded with the current user + Neologik guests
  like the contributors group.
- Auth app (Step 14b): BOTH NCE role groups are assigned to the
  `Neologik Platform Sign-in` enterprise app so members' tokens carry
  the groups claim; `NceAuthApp.AssignedGroups` (list) replaces
  `AssignedGroup`.
- Post-onboarding: put the admins group object id in `NEO_NCE_ADMINS`
  and the contributors group id in `NEO_NCE_USERS` in the environment's
  neo-env-config variables file (bootstrap-if-empty seeding at database
  deploy).

## Unreleased
**Branch**: `feature/agent-platform`
**Ticket**: https://github.com/Neologik-AI/project/issues/1063

### Features
- **Non-interactive (CI) mode for Install-NeologikEnvironment.ps1**
  (cherry-picked from develop 4f0dcd9, where it bumped the script version to
  v1.11.0; on feature/agent-platform the script version remains v5.0.0, and
  the cherry-pick also restores Resolve-BudgetEmailRecipients, whose removal
  had left the answer-file budget-recipients path broken). Three new
  switches:
  - `-NonInteractive`: unattended mode for automation. Requires a fully
    populated answer file (verified up front); every interactive gate either
    resolves from switches/answer keys or throws instead of prompting. An
    Az/Graph context established by the caller (e.g.
    `Connect-AzAccount -AccessToken` / `Connect-MgGraph -AccessToken`) is
    always reused - no re-auth prompt. The configuration summary confirm is
    skipped; the Global-Administrator warn-and-prompt and the
    subscription-selection prompt fail hard instead.
  - `-AcceptTerms`: non-interactive acknowledgement of the Neologik Terms of
    Use and Privacy Policy (required with `-NonInteractive`; logged).
  - `-FreshRun`: discard a leftover checkpoint without prompting. In
    non-interactive mode a checkpoint without `-FreshRun` is an error.
  - Answer-file `environmentType` now accepts the same value set as the
    `-EnvironmentType` parameter (`dev`, `prd`, `dmo`, `test`, `stg`) instead
    of only `dev`/`prd`.
  - Interactive behaviour is unchanged when the new switches are not passed.

### Changes
- **Cost report emails move to the deployment pipeline; deployment SP
  gains subscription-scoped 'Cost Management Contributor' (project#1215,
  https://github.com/Neologik-AI/project/issues/1215)**:
  Install-NeologikEnvironment.ps1 no longer creates the subscription-
  scoped Cost Management scheduled email (Set-NeologikCostManagementEmail
  and onboarding step 13b removed; old checkpoints resume unaffected -
  the step list is record-only). Instead it assigns the deployment SP
  'Cost Management Contributor' at subscription scope alongside the
  existing Reader, and the infrastructure deployment creates and
  maintains the report (neo-infrastructure
  scripts/ensure-cost-report-emails.sh) - one owner of the resource
  definition, and recipient changes become an env-file edit plus
  redeploy instead of a manual subscription-Owner action. Onboarding
  still collects the recipients (Configuration JSON export unchanged).
  Update-NeologikEnvironmentAccess.ps1 -Phase PostWindow ensures both
  retained subscription-scoped roles (before removing the legacy broad
  grants) so existing environments pick the grant up at their v5
  migration. The role manages cost configuration only (budgets, views,
  scheduled actions), no resource control. secure-overview.md updated
  to document both subscription-scoped roles.
- **Update-NeologikEnvironmentAccess.ps1 - the single Global Administrator
  script for v5 migration windows (project#1258,
  https://github.com/Neologik-AI/project/issues/1258)**: idempotent,
  verification-first, run by the customer GA. `-Phase Window` (default):
  grants/verifies the deployment SP's 8 Microsoft Graph app roles, assigns
  the NCE user group to the 'Neologik Platform Sign-in' enterprise app
  (with direct-membership warning), verifies tenant-wide admin consent and
  prints the two-parameter consent URL when missing. `-Phase PostWindow`
  (pre-#774 environments, only after verified migration): ensures the
  7-role RG-scoped set first, then removes subscription-scoped
  Contributor + User Access Administrator and the Application
  Administrator directory role. Inputs from the onboarding Configuration
  JSON (`-ConfigurationFile`) or explicit parameters.
- **Sign-in app renamed 'Neologik Platform Sign-in - <shortname>'
  (owner decision 2026-08-02, project#1239)**: it fronts NCE and every
  bespoke App portal, so the NCE-specific name was misleading on
  Microsoft sign-in/consent screens. New-NeologikNceAuthApp now resolves
  an existing app by its immutable Graph uniqueName (`sp-admin-
  <solutionName>`) instead of display name - a display-name lookup would
  miss a pipeline-renamed app and attempt a duplicate - and renames a
  found app to the current standard. Cosmetic only: clientId, uniqueName,
  scopes and consent untouched.
- **Gated Azure resource tagging at onboarding (project#1173,
  https://github.com/Neologik-AI/project/issues/1173)**: new Step 6 prompt
  "Apply Azure resource tags to created resources? (true/false)", default
  true (answer-file keys `applyResourceTags` / `resourceTagsCustom`), with an
  optional follow-up prompt for customer tags as comma-separated key=value
  pairs (keys letters/digits/`._-`; keys and values must not contain `,` or
  `=`). When enabled, the resource group, Key Vault, deployment storage
  account and both user-assigned managed identities are tagged AT CREATION
  (`New-Az* -Tag`) with Vendor, ApplicationName, ManagedBy, Environment
  (`{org}{envtype}`), Solution (solution short name) and DeploymentDate,
  plus the custom pairs (custom overrides defaults on key collision) - so
  tenants whose Azure Policies DENY creation of untagged resources accept
  them. When disabled, the create calls pass no `-Tag` parameter at all
  (behaviour unchanged). Choices are exported as `ResourceTagsEnabled` /
  `ResourceTagsCustom` in the Configuration JSON for the later environment
  setup to carry forward, and participate in checkpoint/resume (checkpoints
  written before this feature default to disabled on resume). Entra objects
  (security groups, app registrations, service principals) are not taggable
  ARM resources and are untouched.
- **Naming convention alignment (project#1063)**: all computed names now follow
  the platform Neologik-standard convention; the environment type (dev/prd)
  NEVER appears in names (it only drives sizing/defaults). Canonical tokens:
  solution `neo-neo{org}-{region}-{index}` (e.g. `neo-neodmo-cus-01`), short
  name `neo{org}{index}` (e.g. `neodmo01`). Derived: RG `rg-{solution}`, KV
  `kv{short}`, deploy storage `stneodeployneo{org}{region}{index}`, MIs
  `neologik-script-runner-service-connection-{short}` /
  `neologik-sql-managed-identity-{short}`, groups and app registration
  suffixed `- {short}`, config file `Neologik_{org}{index}_...json`.
  Previously the script invented `{org}{env}{index}` composites (`dmodev01`,
  dmo01 dress rehearsal) matching neither of the two registered conventions
  (neo-env-config `naming/templates/`: neologik-standard, keolis).
- **Client-convention flexibility (design D6)**: `solutionName` and
  `solutionShortName` are now answer-file overridable (the short name drives
  every dependent suffix), and the SQL managed identity name gains the same
  override/prompt treatment as the script-runner identity (`sqlIdentityName`
  answer key + interactive prompt). Every script-created resource name is now
  individually overridable for client naming conventions.
- **ScriptVersion bumped to v5.0.0** (was stale at v1.9.0 on the v5 branch).
- **v5: NCE group renamed** - new onboardings create
  `Neologik Harness User Group - {org}{env}{index}` (was `Neologik NCE User
  Group`); consumption is by group ID (`NEO_NCE_USERS`), so existing
  environments keep their old-named groups unaffected.
- **v5: no bots created at onboarding** (Neologik Harness, agent/channel
  decoupling): removed the bot count / agent name / short name prompts,
  answer-file parsing (`botCount`/`bots` now ignored), per-bot user group
  creation, and bot fields from checkpoint/summary/config export. The script
  now creates ONE default user group (`Neologik User Group - {org}{env}{index}`)
  alongside the NCE and Admin groups, and grants the deployment SP the Graph
  `Group.Create` application permission (bf7b1a76-6e77-406b-b258-bf5c7720e98f)
  so Harness channel provisioning can create per-agent user groups at channel
  attach. Agents and channels are created post-deployment in the Harness
  admin tool.
- **Onboarding-kit zip builder moved out of this repo** (owner decision
  2026-07-16): this repository is customer-facing and carries no customer
  data - contents, history, or Actions. `prepare-onboarding-zip.yml`
  removed; the kit is now built by the same-named workflow in the internal
  `neo-env-config` repo, which checks this repository out. README gains the
  no-customer-data contributor rule. The dispatch inputs (workshop data),
  the run log's `inputs.json` echo, and the SAS download link were
  world-readable while the action lived here.
- **Script-runner managed identity name override** — new optional `scriptRunnerIdentityName`
  answer-file key, interactive prompt, and `prepare-onboarding-zip.yml` dispatch input, completing
  the client-naming override set (resource group, Key Vault, deployment storage account, and now
  the script-runner UAMI) for client-specific resource naming conventions. Blank/omitted keeps the
  computed Neologik-standard name (`neologik-script-runner-service-connection-{org}{env}{index}`).
  Validated against Azure managed-identity naming rules (3-128 chars, letters/digits/hyphens/
  underscores, starts with a letter or digit). Builds on PR #20
  (https://github.com/Neologik-Customer/neo-client-onboarding/pull/20), whose branch is merged in
  as this change's base.

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - resource tagging (project#1173): `Get-NeologikResourceTags` / `ConvertTo-NeologikCustomTags` helpers, Step 6 tagging prompts + summary line, `-Tag` splatting on the four create calls, `Set-ConfigFromAnswerFile` keys, checkpoint back-compat default, `ResourceTagsEnabled` / `ResourceTagsCustom` in the config export
- Modified: [inputs-example.json](inputs-example.json) - `applyResourceTags` / `resourceTagsCustom` keys + note (project#1173)
- Modified: [README.md](README.md) - resource-tags prompt documented in the script inputs list (project#1173)
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) — `Test-ManagedIdentityNameError` validator; answer-file + interactive resolution into `ConfigData['ScriptRunnerIdentityName']`; summary line; `New-NeologikManagedIdentities -ScriptRunnerIdentityName` parameter (falls back to the computed name for pre-existing checkpoints)
- Modified: [.github/workflows/prepare-onboarding-zip.yml](.github/workflows/prepare-onboarding-zip.yml) — `scriptRunnerIdentityName` input, validation, inputs.json emission
- Modified: [inputs-example.json](inputs-example.json) — `scriptRunnerIdentityName` field + naming note
- Modified: [VERSION_HISTORY.md](VERSION_HISTORY.md) — this entry

### Breaking Changes
- None

---

## Version NEXT - deployment SP owns the sign-in service principal (project#1579)

- Date: 2026-08-19
- Summary: The sign-in (NCE auth) app setup now adds the deployment SP as
  owner of the service principal object as well as the application object.
  Application.ReadWrite.OwnedBy only covers owned objects, so without this
  the pipeline's servicePrincipal updates were denied on every deploy.
  Idempotent - re-running onboarding backfills existing environments.

## Version NEXT - summary alignment (project#1577)

- Date: 2026-08-19
- Summary: The configuration summary renders every row through one
  label-padding helper (single 24-character label column); the value
  column previously drifted after the Azure Region row.

## Version NEXT - remove model quota pre-flight (project#1578)

- Date: 2026-08-19
- Summary: Test-QuotaRequirements removed (owner ruling). It warned on a
  hard-coded model (gpt-5.4-mini) in the environment's region with a stale
  supported-region list; v5 deploys no models at onboarding (zero-model is
  a first-class state) and the model region is chosen independently at the
  manual model-deployment step. vCPU guidance in QUICK-REFERENCE stays;
  the Azure OpenAI quota section there is removed.

## Version NEXT - naming formula fix (project#1576)

- Date: 2026-08-19
- Summary: Computed solution names now follow the estate formula
  neo-{org}{env}-{region}-{index} (short name {org}{env}{index}); the
  previous computation hard-coded neo-neo{org} and omitted the environment
  type, so the correct internal organisation code 'neo' produced
  rg-neo-neoneo-cus-01. Deployment storage account default follows suit
  (stneodeploy{org}{env}{region}{index}). Answer-file and CLI overrides
  unchanged. Docs updated (QUICK-REFERENCE, TECHNICAL-REFERENCE,
  secure-overview, inputs-example naming note); QUICK-REFERENCE.pdf not
  regenerated. Found live during the dev01 v5 onboarding.

## Version NEXT
**Branch**: `feature/ideas-agent`
**Status**: Pending

### Features
- **Microsoft Entra Agent ID permissions for the deployment SP** — the deployment service
  principal is now granted the granular Graph application permissions
  `AgentIdentityBlueprint.Create`, `AgentIdentityBlueprint.AddRemoveCreds.All`,
  `AgentIdentityBlueprint.UpdateAuthProperties.All`, `AgentIdentityBlueprintPrincipal.Create`,
  and `AgentIdUser.ReadWrite.All`, so it can provision agent identity blueprints (+ principal +
  FIC) **and mint each autonomous bot's agent identity + agent user** (e.g. the ideas agent).
  Chosen over the broad `Agent ID Administrator` directory role to stay consistent with the
  reduced-permission model (granular app perms, not directory roles).

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) — added the four
  `AgentIdentityBlueprint*` app role IDs plus `AgentIdUser.ReadWrite.All` to
  `Grant-GraphAppRolePermissions` and granted them to the deployment SP.

### ⚠️ Migration — already-onboarded environments
This grant only runs for **newly-onboarded** environments. Environments onboarded **before** this
change have a reduced deploy SP without these roles, and cannot self-grant. Before enabling an
autonomous bot (`BOT<N>_AUTONOMOUS=true`) on such an env, a Global Admin must perform a **one-off
backfill** of the Agent ID roles, or the first autonomous deploy fails. See
`neo-infrastructure/docs/agent-identity-blueprint.md` → *Backfilling an already-onboarded environment*.
dev03 was backfilled 2026-06-30.

---

## Version 1.10.1
**Built**: June 29, 2026  
**Git Tag**: v1.10.1

### Fixes
- **vCPU quota pre-flight check** — added `Az.Compute` to the required modules list so `Get-AzVMUsage` resolves. Previously the cmdlet was unavailable (its module was never installed), so the quota check silently degraded to a warning and never actually ran.

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) — added `Az.Compute` (min 7.0.0) to `$script:RequiredModules`
- Modified: [VERSION_HISTORY.md](VERSION_HISTORY.md) — this entry

### Breaking Changes
- None

---

## Version 1.10.0
**Built**: June 25, 2026  
**Git Tag**: v1.10.0  
**Ticket**: https://github.com/Neologik-AI/project/issues/847

### Major Changes
- **Reduce deployment & admin subscription-scoped permissions** — the deployment service
  connection and the Admin User Group no longer receive subscription-scoped Contributor. The
  subscription-scoped setup that required it is now performed here during onboarding (run as the
  subscription Owner), removing the standing grant from the deployment pipeline.

### Infrastructure Changes
- **Deploy service connection / GitHub service connection**: removed subscription roles
  (Contributor + Cost Management Contributor); added resource-group **Contributor**. Keeps the
  resource-group roles incl. Role Based Access Control Administrator. All deployment operations are
  now resource-group-scoped.
- **Admin User Group**: removed subscription-scoped Contributor; added resource-group
  **Contributor** + **Azure Kubernetes Service Cluster Admin Role** (admin kubeconfig) alongside
  the existing resource-group data-plane roles. (AKS control-plane start/stop/scale + the MC_ node
  resource group are covered by RG-scoped Contributor; the node RG is managed by AKS itself.)
- **Resource provider + preview-feature registration** performed here. New Step-6 prompt asks
  whether to register the full provider set now (**default: No** — registers a minimal set; the
  full set is then registered via the new `Register-NeologikResourceProviders.ps1`). Features
  registered: `Microsoft.Compute/EncryptionAtHost`, `Microsoft.ContainerService/AzureLinuxCVMPreview`.
- **Cost Management scheduled email** (daily cost report) created here (subscription-scoped, run as
  Owner) instead of by the infrastructure deployment. New Step-6 prompt collects recipient(s)
  (default `support_budget_alerts@neologik.ai`, or `none` to disable).

### New Files
- `Register-NeologikResourceProviders.ps1` — standalone full resource-provider + preview-feature
  registration, for use when the operator opts out of registering the full set during onboarding.

### Companion Change
- `neo-infrastructure` (v4.6.0): removes the subscription-scoped operations from the AKS
  deployment workflow and Bicep so they match this reduced-permission model.

---

## Version 1.9.1
**Built**: June 18, 2026  
**Git Tag**: v1.9.1

### Major Changes
- **Documentation Sync** - Aligned onboarding docs with the current `Install-NeologikEnvironment.ps1` reduced-permission model and bot-naming rules

### Infrastructure Changes
- **Reduced Permission Model** (documentation only — reflects existing script behaviour):
  - Deploy service principal / GitHub service connection: Microsoft Graph app roles `Application.Read.All` + `Application.ReadWrite.OwnedBy` (replacing the tenant-wide Application Administrator directory role); subscription roles Contributor + Cost Management Contributor; resource-group roles Key Vault Certificates Officer, Key Vault Secrets Officer, Storage Blob Data Contributor, Azure Kubernetes Service RBAC Cluster Admin, Monitoring Contributor, and Role Based Access Control Administrator (replacing the subscription-scoped User Access Administrator)
  - Script Runner UAMI: subscription Contributor; resource-group Key Vault Secrets Officer + Azure Bot Service Contributor Role; no Microsoft Graph app roles
- **Bot Naming Rules** (documentation only):
  - Short name: lowercase, 1–4 characters, must start with a letter, letters/numbers/dashes only
  - Full bot name: letters, numbers, spaces, dashes and underscores; no length limit

### Files Changed
- Modified: [README.md](README.md) - Bot name rules; checkpoint/resume note
- Modified: [QUICK-REFERENCE.md](QUICK-REFERENCE.md) - Bot name rules; reduced-permission role tables
- Modified: [TECHNICAL-REFERENCE.md](TECHNICAL-REFERENCE.md) - Reduced-permission model; operator prerequisite wording; JSON config example
- Modified: [PRE-ONBOARDING-INFO-GATHERING.md](PRE-ONBOARDING-INFO-GATHERING.md) - Bot name rules
- Modified: mcdev deployment reference docs - Script Runner UAMI permissions
- Modified: [VERSION_HISTORY.md](VERSION_HISTORY.md) - This entry

### Breaking Changes
- None (documentation only)

---

## Version 1.9.0
**Built**: January 15, 2026  
**Git Tag**: v1.9.0

### Major Changes
- **Real-time Azure Region Validation** - Dynamic region validation using Azure API with Microsoft CAF standards
- **Comprehensive Region Coverage** - Support for 90+ Azure regions with official abbreviations
- **Flexible Agent Name Validation** - Relaxed naming requirements for better user experience
- **Intelligent Fallback Validation** - Graceful handling when Azure API is unavailable

### Features Added
- **Azure Region Management**:
  - Real-time region validation using `Get-AzLocation` API
  - Microsoft Cloud Adoption Framework (CAF) standard abbreviations for all regions
  - Interactive 'list' command to display all available regions with codes
  - Validation against subscription-specific available regions
  - Fallback to CAF standards when API is unavailable with immediate validation
  - Display region names and abbreviation codes during selection
  
- **Region Code Coverage** (90+ regions):
  - Americas: All US, Canada, Brazil, Mexico, Chile regions
  - Europe: All EU regions including Austria, Belgium, Switzerland, Nordic countries
  - Asia Pacific: All APAC regions including Australia, Japan, Korea, India, Southeast Asia, Indonesia, Malaysia, New Zealand
  - Middle East & Africa: UAE, Qatar, Israel, South Africa
  - Government: US Gov and DoD regions
  - EUAP: Early Update Access Program regions
  - Geographic groups: Continental and country-level groupings
  - Abbreviations based on ISO 3166-1 alpha-2 country codes and Microsoft standards
  
- **Enhanced User Experience**:
  - Shows common regions by default (uksouth, ukwest, eastus, westus, northeurope, westeurope, switzerlandnorth)
  - Displays region display names and codes: "switzerlandnorth - Switzerland North (Code: szn)"
  - Type 'list' to see all available regions in formatted table
  - Region codes shown in lowercase for consistency
  - Immediate feedback on invalid region selection with helpful examples
  
- **Agent Name Flexibility**:
  - Allow upper and lowercase letters (A-Z, a-z)
  - Allow numbers (0-9)
  - Allow spaces for multi-word names (e.g., "Customer Service Bot")
  - Allow dashes (-) and underscores (_)
  - Removed lowercase-only restriction
  - Removed 7-character maximum length limit
  - Removed must-start-with-letter requirement
  - Updated validation regex to `^[A-Za-z0-9 \-_]+$`

### Technical Improvements
- **Dynamic Region Code Mapping**:
  - Builds region code mapping on script execution using Azure API
  - Applies Microsoft CAF standards where available
  - Generates smart fallback abbreviations for new regions
  - Tracks CAF coverage vs total regions (e.g., "90 using Microsoft CAF standards")
  
- **Validation Logic**:
  - Primary: Validate against subscription-available regions from `Get-AzLocation`
  - Fallback: Validate against Microsoft CAF standard region list
  - Smart abbreviation generation for regions not yet in CAF standards
  - Prevents wasted configuration time by validating before full setup
  - Loops back on invalid input in both normal and fallback modes
  
- **Error Handling**:
  - Graceful degradation when Azure API is unavailable
  - Clear warning messages for fallback validation mode
  - Helpful error messages with region examples
  - Prevents script failure from proceeding with invalid regions

### Infrastructure Changes
- **Configuration Output**:
  - Region codes now use official Microsoft CAF abbreviations
  - Resource group names use lowercase region codes (e.g., "rg-neo-abc-dev-szn-01")
  - Solution names include accurate region abbreviations
  
- **Resource Naming**:
  - All Azure resources use Microsoft-standard region codes
  - Consistent lowercase formatting across all resource names
  - Examples:
    - `switzerlandnorth` → `szn` (Microsoft CAF standard)
    - `uksouth` → `uks` (Microsoft CAF standard)
    - `eastus2` → `eus2` (Microsoft CAF standard)

### Dependencies
- **Azure PowerShell Module**: `Get-AzLocation` cmdlet for dynamic region retrieval
- **Network Connectivity**: Required for real-time region validation (falls back to CAF standards if unavailable)
- **No breaking changes** to existing resources or configurations
- **Backward compatible** with existing deployments

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Added real-time region validation, comprehensive region coverage, flexible agent name validation
- Modified: [VERSION_HISTORY.md](VERSION_HISTORY.md) - This update

### Breaking Changes
- None (backward compatible)

### Bug Fixes
- Fixed scenario where invalid regions were accepted when Azure API was unavailable
- Now validates against CAF standards even in fallback mode
- Prevents wasted user time by rejecting invalid regions immediately

---

## Version 1.8.0
**Built**: January 12, 2026  
**Git Tag**: v1.8.0

### Major Changes
- **External Guest User Management** - Guest user emails moved to external configuration file
- **Enhanced Configuration Collection** - Added hostname and domain name capture
- **Multi-Bot Support** - Support for configuring 1-10 bots with dedicated user groups
- **Input Normalization** - Automatic lowercase conversion for key configuration values

### Features Added
- `NeologikGuestUsers.txt` file for managing guest user email addresses
  - One email per line
  - Support for comments (lines starting with #)
  - Blank lines ignored
- Hostname and domain name collection during configuration
- Bot count selection (1-10 bots)
- Per-bot configuration:
  - Agent Name: Used in security group names (e.g., "Neologik User Group bot - abc-dev")
  - Short Name: Internal identifier for the bot
- Automatic lowercase conversion for:
  - Organization code
  - Hostname
  - Domain name
  - Environment type
  - Azure region
- Enhanced input validation:
  - Agent name: lowercase, max 7 characters, letters and dashes only
  - Short name: lowercase, max 7 characters, letters and dashes only
  - Duplicate name detection for both agent and short names

### Infrastructure Changes
- **Entra ID (Azure AD)**:
  - Security groups created per bot (one user group per bot)
  - Group naming: `Neologik User Group <agent-name> - {org}-{env}`
  - Example: `Neologik User Group bot - abc-dev`, `Neologik User Group support - abc-dev`
  
- **Configuration Output**:
  - Added `OrganizationName`, `Hostname`, `DomainName` to JSON output
  - Added `BotCount` and `Bots` array with `AgentName` and `ShortName` properties
  
### Dependencies
- **Guest User File**: `NeologikGuestUsers.txt` must be present in script directory
- **No breaking changes** to Azure resources or permissions
- **Backward compatible** with existing deployments (new fields are additions only)

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Multi-bot support, external guest users, input normalization
- New: [NeologikGuestUsers.txt](NeologikGuestUsers.txt) - Guest user email configuration
- Modified: [README.md](README.md) - Updated documentation for new features
- Modified: [QUICK-REFERENCE.md](QUICK-REFERENCE.md) - Updated for multi-bot groups
- Modified: [TECHNICAL-REFERENCE.md](TECHNICAL-REFERENCE.md) - Comprehensive feature documentation
- New: [VERSION_HISTORY.md](VERSION_HISTORY.md) - This file

### Breaking Changes
- None (backward compatible)

---

## Version 1.7.5
**Built**: November 17, 2025  
**Git Tag**: v1.7.5

### Major Changes
- **Resource Provider Registration Enhancement** - Added Microsoft.Compute provider registration before storage account creation

### Features Added
- Dedicated Microsoft.Compute resource provider registration step
- Improved resource provider management with dedicated section
- Enhanced logging for resource provider operations

### Bug Fixes
- Fixed storage account creation failures due to unregistered Microsoft.Compute provider
- Improved error messages for resource provider registration

### Infrastructure Changes
- **Azure Resource Providers**:
  - Microsoft.Compute: Now explicitly registered before storage account creation
  - Microsoft.Storage: Registered before storage account operations
  - Microsoft.KeyVault: Registered before Key Vault operations
  - Microsoft.ManagedIdentity: Registered before managed identity creation
  - Microsoft.Resources: Registered before resource group operations
  
### Dependencies
- **Azure Subscription**: Requires permissions to register resource providers
- **No breaking changes** to existing resources

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Resource provider registration enhancements
- Modified: [TECHNICAL-REFERENCE.md](TECHNICAL-REFERENCE.md) - Updated to v1.7.5

---

## Version 1.7.3
**Built**: November 17, 2025  
**Git Tag**: v1.7.3

### Major Changes
- **Microsoft Graph API Compatibility** - Fixed unsupported query operations

### Bug Fixes
- Fixed `Request_UnsupportedQuery` error when querying directory roles
- Removed unsupported `-Filter` parameters from directory role queries
- Implemented manual filtering using `Where-Object` for Graph API compatibility

### Infrastructure Changes
- **No Azure resource changes**
- **API Compatibility**: Updated to work with Microsoft Graph API limitations

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Graph API query fixes

---

## Version 1.7.2
**Built**: November 17, 2025  
**Git Tag**: v1.7.2

### Major Changes
- **Enhanced Error Reporting** - Show actual error messages instead of generic permission errors

### Features Added
- Detailed error messages for Application Administrator role assignment failures
- Improved diagnostics for troubleshooting permission issues
- Better error context in log files

### Bug Fixes
- Fixed misleading "insufficient permissions" messages
- Improved error logging for role assignment operations

### Infrastructure Changes
- **No Azure resource changes**
- **Improved observability** for deployment troubleshooting

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Error reporting improvements

---

## Version 1.7.1
**Built**: November 17, 2025  
**Git Tag**: v1.7.1

### Major Changes
- **Azure AD Replication Handling** - Improved handling of replication delays

### Bug Fixes
- Restored SilentlyContinue error handling for Application Administrator role operations
- Fixed script failures due to Azure AD replication delays
- Graceful handling of resources that haven't replicated yet

### Infrastructure Changes
- **No Azure resource changes**
- **Improved reliability** when dealing with newly created Azure AD resources

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Replication delay handling

---

## Version 1.7.0
**Built**: November 17, 2025  
**Git Tag**: v1.7.0

### Major Changes
- **Service Principal Group Membership Fix** - Fixed group membership checks for newly created service principals

### Bug Fixes
- Fixed service principal group membership verification
- Used SilentlyContinue for group membership checks to handle replication delays
- Prevented false failures when checking group memberships

### Infrastructure Changes
- **No Azure resource changes**
- **Improved reliability** for service principal operations

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Group membership check fixes

---

## Version 1.6.9
**Built**: November 17, 2025  
**Git Tag**: v1.6.9

### Major Changes
- **Guest User Handling Rollback** - Restored working guest invitation pattern

### Bug Fixes
- Rolled back to proven guest invitation and group membership code
- Fixed guest user addition failures
- Restored reliable pattern from v1.4.1

### Infrastructure Changes
- **No Azure resource changes**
- **Restored stability** for guest user operations

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Guest user handling rollback

---

## Version 1.6.8
**Built**: November 17, 2025  
**Git Tag**: v1.6.8

### Major Changes
- **User Type Logging** - Added logging to distinguish member users from guest users

### Features Added
- UserType property logging for better diagnostics
- Improved visibility into member vs. guest user processing

### Infrastructure Changes
- **No Azure resource changes**
- **Enhanced logging** for user operations

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - User type logging

---

## Version 1.6.7
**Built**: November 17, 2025  
**Git Tag**: v1.6.7

### Major Changes
- **Logging Improvements** - Fixed duplicate warning prefixes and adjusted replication delays

### Bug Fixes
- Fixed double "WARNING:" prefix in log messages
- Increased Azure AD replication delay tolerance
- Improved log message formatting

### Infrastructure Changes
- **No Azure resource changes**
- **Improved logging** quality and readability

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Logging improvements

---

## Version 1.6.6
**Built**: November 17, 2025  
**Git Tag**: v1.6.6

### Major Changes
- **Azure AD Replication Delay Handling** - Graceful handling of newly created groups

### Bug Fixes
- Fixed 404 errors when accessing newly created groups
- Implemented retry logic for group operations
- Better handling of Azure AD replication delays

### Infrastructure Changes
- **No Azure resource changes**
- **Improved reliability** for group operations

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Replication delay handling

---

## Version 1.6.5
**Built**: November 17, 2025  
**Git Tag**: v1.6.5

### Major Changes
- **Guest User Error Handling** - Graceful handling of non-existent guest users

### Bug Fixes
- Handle guest users that don't exist in tenant gracefully
- Prevent script failure when guest user lookup fails
- Improved error handling for user operations

### Infrastructure Changes
- **No Azure resource changes**
- **Improved robustness** for guest user processing

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Guest user error handling

---

## Version 1.4.2
**Built**: November 17, 2025  
**Git Tag**: v1.4.2

### Major Changes
- **Git Sync Configuration Fix** - Fixed remote configuration for customer repository synchronization

### Bug Fixes
- Fixed git remote configuration in sync workflow
- Improved repository synchronization reliability

### Infrastructure Changes
- **GitHub Actions**: Updated sync workflow configuration
- **No Azure resource changes**

### Files Changed
- Modified: [.github/workflows/sync-to-customer-repo.yml](.github/workflows/sync-to-customer-repo.yml) - Git remote fixes

---

## Version 1.4.1
**Built**: November 17, 2025  
**Git Tag**: v1.4.1

### Major Changes
- **Terms and Conditions URLs** - Added links to Neologik's Terms of Use and Privacy Policy

### Features Added
- Terms of Use URL: https://www.neologik.ai/terms-of-use
- Privacy Policy URL: https://www.neologik.ai/privacy-policy
- User must review both documents before proceeding

### Infrastructure Changes
- **No Azure resource changes**
- **Enhanced compliance** with legal requirements

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Terms and conditions URLs

---

## Version 1.4.0
**Built**: November 17, 2025  
**Git Tag**: v1.4.0

### Major Changes
- **Terms and Conditions Acceptance** - Added mandatory acceptance of terms before installation

### Features Added
- Terms and conditions acceptance prompt
- User must type "I ACCEPT" to proceed with installation
- Script exits if terms are not accepted

### Infrastructure Changes
- **No Azure resource changes**
- **Compliance feature** for legal requirements

### Files Changed
- Modified: [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Terms acceptance

---

## Version 1.2.3
**Built**: November 15, 2025  
**Git Tag**: v1.2.3

### Major Changes
- **Auto-Tagging Enhancement** - Updated sync workflow to automatically tag on release commits

### Features Added
- Automatic git tag creation on release commits
- Improved version tracking in customer repository

### Infrastructure Changes
- **GitHub Actions**: Enhanced sync workflow with auto-tagging
- **No Azure resource changes**

### Files Changed
- Modified: [.github/workflows/sync-to-customer-repo.yml](.github/workflows/sync-to-customer-repo.yml) - Auto-tagging

---

## Version 1.0.0
**Built**: November 15, 2025  
**Git Tag**: v1.0.0

### Major Changes
- **Initial Release** - First stable version of automated onboarding scripts

### Features Added
- PowerShell 7.4+ validation and auto-update
- Azure module dependency management
- Guest user invitation system (hardcoded list)
- Resource group creation
- Security group management
- App Registration (Service Principal) with secret storage
- Key Vault setup with RBAC
- Storage Account for certificate storage
- Managed Identity creation and configuration
- Role assignments (Contributor, User Access Administrator, Application Administrator)
- Comprehensive logging and error handling
- JSON configuration export

### Infrastructure Changes
- **Azure Resources Created**:
  - Resource Group: `rg-neo-{org}-{env}-{region}-{index}`
  - Key Vault: `kvneodeploy{org}{env}{region}{index}`
  - Storage Account: `stneodeploy{org}{env}{region}{index}`
  - Container: `certificate` (in storage account)
  - 3 Security Groups (User, NCE User, Admin)
  - 2 Managed Identities (Script Runner, SQL)
  - 1 App Registration (GitHub Service Connection)
  
- **Permissions Required**:
  - Owner role at subscription level
  - Global Administrator role in Entra ID

### Files Included
- [Install-NeologikEnvironment.ps1](Install-NeologikEnvironment.ps1) - Main installation script
- [README.md](README.md) - User guide
- [QUICK-REFERENCE.md](QUICK-REFERENCE.md) - Quick reference for IT/Security review
- [TECHNICAL-REFERENCE.md](TECHNICAL-REFERENCE.md) - Detailed technical documentation
- [PFX-CERT-GUIDE.md](PFX-CERT-GUIDE.md) - Certificate creation guide
- [FINISHING-STEPS-GUIDE.md](FINISHING-STEPS-GUIDE.md) - Post-deployment steps
- [LICENSE](LICENSE) - Apache 2.0 license

---

## Dependencies Reference

### Workload Dependencies
This script prepares the Azure environment for Neologik workload deployments. The following workloads depend on resources created by this script:

- **Neologik Bot Application**
  - Requires: Security groups created by this script
  - Requires: Key Vault for secrets
  - Requires: Storage Account for certificate
  - Uses: Managed identities for authentication

- **Neologik Admin Tool**
  - Requires: Security groups (Admin User Group)
  - Requires: Proper role assignments at resource group level

- **GitHub Actions Deployments**
  - Requires: Service Principal (App Registration) created by this script
  - Requires: Client secret stored in Key Vault
  - Requires: Contributor and User Access Administrator roles

### Infrastructure Dependencies

#### Azure Resources
- **Azure Subscription**
  - Active subscription with available quota
  - Owner role assignment required
  
- **Entra ID (Azure AD)**
  - Active tenant
  - Global Administrator role required
  - Guest user invitation capability enabled
  
- **Resource Group**
  - Naming: `rg-neo-{org}-{env}-{region}-{index}`
  - Location: User-specified Azure region
  
- **Key Vault**
  - Name: `kvneodeploy{org}{env}{region}{index}` (24 char max)
  - RBAC authorization enabled
  - Stores: Service principal secrets, certificate passwords
  - Access: Key Vault Secrets Officer role to Admin User Group
  
- **Storage Account**
  - Name: `stneodeploy{org}{env}{region}{index}` (24 char max)
  - Authentication: Microsoft Entra ID only (no shared keys)
  - Container: `certificate` (for TLS/SSL certificates)
  - Access: Storage Blob Data Contributor to Admin User Group
  
- **Security Groups** (Entra ID)
  - Per-bot user groups: `Neologik User Group <agent-name> - {org}-{env}` (v1.8.0+)
  - Legacy single user group: `Neologik User Group - {org}-{env}` (v1.0.0-v1.7.x)
  - NCE User Group: `Neologik NCE User Group - {org}-{env}`
  - Admin User Group: `Neologik Admin User Group - {org}-{env}`
  - Members: Logged-in user + Neologik guest users
  
- **App Registration** (Service Principal)
  - Name: `Neologik GitHub Service Connection - {org}-{env}`
  - Type: Multi-tenant
  - Secret: 365-day expiration, stored in Key Vault
  - Roles: Contributor, User Access Administrator (Subscription)
  - Entra Role: Application Administrator
  
- **Managed Identities**
  - Script Runner: `neologik-script-runner-service-connection-{org}-{env}`
  - SQL Identity: `neologik-sql-managed-identity-{org}-{env}`

#### Permissions Required

**Subscription Level**:
- Owner role (for RBAC assignments)

**Entra ID (Azure AD)**:
- Global Administrator role (for directory role assignments and guest invitations)
- OR Privileged Role Administrator (minimum for Application Administrator assignment)

#### Resource Providers
The script automatically registers these providers:
- Microsoft.Resources
- Microsoft.KeyVault
- Microsoft.Storage
- Microsoft.Compute (v1.7.5+)
- Microsoft.ManagedIdentity

---

## Version Numbering

- **Major** (1): Breaking changes, major architecture changes
- **Minor** (7): New features, backwards-compatible changes
- **Patch** (x): Bug fixes, minor improvements

---

## Maintenance Guidelines

### Updating This File
When creating a new release from main:

1. **Create new version section** at the top of the document
2. **Include**: Version number, build date, git tag
3. **Document changes**:
   - Major features and enhancements
   - Bug fixes
   - Breaking changes
   - Infrastructure changes (Azure resources, permissions, etc.)
   - Configuration file changes
   - Security group naming changes
4. **List dependencies**:
   - Changes to Azure resources
   - Permission requirement changes
   - External file dependencies (like NeologikGuestUsers.txt)
5. **Reference file changes**: Use relative links to modified files

### Tagging Releases
- Create git tags in format: `v{MAJOR}.{MINOR}.{PATCH}` (e.g., v1.8.0)
- Tag from main branch only
- Include version in commit message: `release v1.8.0 - Description`

### Breaking Changes
Mark breaking changes clearly and include migration guidance:
- Changes to security group naming
- Changes to required permissions
- Changes to configuration file format
- Changes to resource naming conventions

---

## Support & Contact

For questions about specific versions or deployment requirements:
- Email: support@neologik.ai
- Include: Version number, log file, configuration JSON file

**Last Updated**: January 12, 2026
