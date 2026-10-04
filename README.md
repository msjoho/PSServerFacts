# PSServerFacts

PowerShell 7+ module for capturing point-in-time configuration facts for one or more Windows Servers. From a jumphost, it scans targets in parallel over WinRM, normalizes the results across collectors, and emits per-server JSON + Markdown plus a cross-server summary.

Common use cases:
- **Documentation / baseline** — record the current state of production servers for compliance, audit trails, or change-management evidence.
- **IaC migration input** — the JSON shape is structured around what an IaC author (Terraform / Ansible / Bicep / Helm) needs to recreate the server: services, scheduled tasks with their RunAs identities, custom shares with NTFS ACLs, IIS bindings + app pool identities, etc.
- **Drift detection** — diff two runs (same server, different times) or two servers (same role) to spot configuration deviations.
- **Incident triage** — capture a single comprehensive artifact in one shot rather than running a dozen ad-hoc cmdlets remotely.

Coverage spans OS / hardware / disks / network, installed software (registry uninstall keys + Chocolatey + Windows Features), local privileged groups expanded recursively to ultimate AD members across forest trusts, custom services / shares / scheduled tasks (Windows defaults filtered out via curated, editable data files), local accounts, firewall rules, IIS sites + app pools with cert thumbprints, and the LocalMachine certificate stores, Chef Infra Client state (run list, environment, node attributes), SQL Server (instances, databases, logins, jobs, backup history), pending reboot flags, TLS / SChannel protocol enablement, SMB hardening config, User Rights Assignment, the active power plan, the page file + crash-dump config, and Microsoft Defender engine + exclusions. Output is deterministic, schema-validated, and diff-friendly. Per-server and section-level isolation means a single failed collector or unreachable target doesn't fail the whole run.

> **New to this module?** Start with **[USAGE.md](USAGE.md)** for a getting-started guide and common scenarios, then come back here for the full reference. Both public functions also ship comment-based help — try `Get-Help Export-ServerFacts -Full`.

## Install

From PSGallery (once published):

```powershell
Install-Module PSServerFacts -Scope CurrentUser
```

From a local clone (development):

```powershell
Import-Module .\PSServerFacts\PSServerFacts.psd1 -Force
```

## Prerequisites

**Jumphost (where the script runs):**
- PowerShell 7+
- `ActiveDirectory` module (RSAT)
- `NTFSSecurity` module (`Install-Module NTFSSecurity`)
- WinRM reachability to all targets
- Calling identity must be able to read AD (default: current user's Kerberos context)

**Target server:**
- WinRM enabled
- Calling identity has admin privilege on the target
- PowerShell 5.1 or higher

**Optional soft prerequisites:**
- `dbatools` module (`Install-Module dbatools`) — required for full SQL Server live-query data. If absent on both jumphost and target, `SqlServer` section returns registry-only facts with a section warning.
- `chef-client.exe` on PATH on the target — used only to capture the Chef client version. Optional; absence is silent.

## Usage

```powershell
Import-Module .\PSServerFacts\PSServerFacts.psd1 -Force

# Basic — current user creds
Export-ServerFacts -ComputerName srv01,srv02,srv03 -OutputRoot .\output

# Explicit cred (e.g. a different admin)
$cred = Get-Credential
Export-ServerFacts -ComputerName srv01 -Credential $cred -OutputRoot .\output

# Deeper NTFS inspection on shares (Root | Children | Recursive)
Export-ServerFacts -ComputerName srv01 -NtfsDepth Children -OutputRoot .\output

# NTFSSecurity provisioning on the target (Auto | Install | None)
Export-ServerFacts -ComputerName srv01 -NtfsSecurityProvisioning Install -OutputRoot .\output

# Limit to specific sections (faster, focused)
Export-ServerFacts -ComputerName srv01 -IncludeSection Services,Shares,ScheduledTasks -OutputRoot .\output

# Skip noisy sections
Export-ServerFacts -ComputerName srv01 -ExcludeSection InstalledApplications,Certificates -OutputRoot .\output

# Show defaults too (bypass the filter for one or more categories)
Export-ServerFacts -ComputerName srv01 -IncludeAllServices -IncludeAllShares -OutputRoot .\output

# SQL Server collection with explicit SQL credential (Windows auth used by default)
$sqlCred = Get-Credential
Export-ServerFacts -ComputerName srv01 -SqlCredential $sqlCred -IncludeSection SqlServer -OutputRoot .\output

# Emit advisories into JSON output (always shown in Markdown)
Export-ServerFacts -ComputerName srv01 -AdvisoryJson -OutputRoot .\output

# Skip advisory evaluation entirely
Export-ServerFacts -ComputerName srv01 -SkipAdvisories -OutputRoot .\output

# Resolve AD principals from an untrusted forest with a dedicated credential
$partnerCred = Get-Credential -UserName 'PARTNER\readonly-svc'
Export-ServerFacts -ComputerName srv01 -ExpandGroupMembers `
    -DomainCredential @{ 'partner.example.net' = $partnerCred } -OutputRoot .\output
```

### Advisories

The module evaluates advisory rules after collection. Each advisory has a `Severity` of `Note`, `Warning`, or `Critical` and is included in the per-server Markdown report. Pass `-AdvisoryJson` to also include advisories in the JSON output; pass `-SkipAdvisories` to bypass advisory evaluation altogether.

## Sections collected

The 24 directly-collectable sections, plus one cross-cutting derived view:

| Section | What it captures |
|---|---|
| `System` | OS caption / version / build, install + last-boot dates, last hotfix, domain, time zone, WinRM HTTPS cert thumbprint |
| `Hardware` | CPU model, sockets, logical cores, total RAM |
| `Disks` | Fixed disks (`DriveType=3`) — drive letter, label, FS, total/free/used GB |
| `Network` | Hostname, FQDN, physical adapters with IPv4/IPv6, MAC, DHCP state, gateway, DNS servers/suffix |
| `InstalledApplications` | Registry uninstall keys (HKLM + WOW6432Node + per-user hives). Skips `SystemComponent=1` entries |
| `ChocolateyPackages` | `choco list -lo -r` output if `choco.exe` is on PATH |
| `WindowsFeatures` | `Get-WindowsFeature \| Where Installed` (Server SKUs only) |
| `Permissions` | `Administrators`, `Remote Desktop Users`, `Remote Management Users` — AD groups expanded recursively, members across forest trusts resolved with `-Server <domain FQDN>` |
| `Services` | `Win32_Service` filtered against `data/DefaultServices.psd1` (curated baseline + path heuristic). Returns Name, DisplayName, State, StartMode, RunAs, Path, Description |
| `Shares` | Custom SMB shares with share-level permissions and NTFS ACLs at the configured depth |
| `ScheduledTasks` | Tasks under any path other than `\Microsoft\*` — RunAs, triggers, actions |
| `LocalUsers` | Local accounts excluding well-known RIDs 500/501/503/504 |
| `FirewallRules` | Enabled rules whose `Group` field doesn't match Microsoft-shipped prefixes |
| `Iis` | Sites + bindings (with cert thumbprints) + app pools (with `IdentityType` and `Username`). `null` if IIS isn't installed |
| `Certificates` | `LocalMachine\My`, `WebHosting`, `TrustedPublisher` (all certs) + `Root`, `CA` (filtered against the public-CA / Microsoft baseline). Includes SAN DNS names and Enhanced Key Usage |
| `Chef` | Chef Infra Client state — node identity, environment, Chef Server URL, resolved run list, top-level attribute keys (no values), version. `null` if Chef isn't installed |
| `SqlServer` | Per-instance SQL Server config — version, edition, build, collation, features, updates, service accounts, configuration, server logins with database access, linked servers, databases with file layout, disk-role layout, Always On AGs, Agent jobs with schedules, backup history, BackupDirectory with non-inherited NTFS ACEs. `null` if no SQL instances detected |
| `PendingReboot` | Pending-reboot flags from CBS, Windows Update, file-rename queue, and SCCM client |
| `PowerPlan` | Active power plan name and GUID |
| `PageFile` | Page file location, size, and crash-dump configuration |
| `Tls` | TLS / SChannel protocol enablement state per protocol and role (client/server) |
| `Smb` | SMB hardening configuration — signing, encryption, SMBv1 state |
| `Defender` | Microsoft Defender engine status, definition versions, real-time protection state, and configured exclusions |
| `UserRightsAssignment` | Configured User Rights Assignment privileges and the principals holding each right |

**Cross-cutting:**
- `ServiceAccounts` — domain accounts (incl. gMSAs) used as `RunAs` across services / scheduled tasks / IIS app pools, deduplicated. Auto-derived from whichever of `Services`, `ScheduledTasks`, `Iis` were collected.

## Output

A timestamped folder under `./output/` (override with `-OutputRoot`) per run:

```
output/2026-04-30_154113_287/
├── <server>.json         # structured per-server inventory
├── <server>.md           # human-readable per-server report
├── _summary.md           # cross-server overview, aggregate service accounts, expiring certs
├── _run.json             # parameters + per-server status
└── _errors.log           # orchestrator-level errors (rare)
```

**Per-server JSON shape**:
- Top-level fields: `Computer`, `ScannedAtUtc`, `ScannedBy`, `Status` (`Success`/`PartialSuccess`/`Failed`), `DurationSeconds`, `CollectedSections`, `Errors`
- One field per collected section (omitted if not in `CollectedSections`)
- Schema: `tests/schemas/server-assessment.schema.json`

**Per-server Markdown**:
- One `## Heading` per collected section
- Filtered-count summaries on Services / Shares / ScheduledTasks / Firewall headings
- ✅ / ⚠️ / ❌ status indicators
- Cert table includes a "Used for" column showing FriendlyName or SAN DNS list

## Exit codes

`Export-ServerFacts` writes the run status to `$LASTEXITCODE` (it does not emit it to the pipeline, so interactive runs don't print a stray `0`).

| `$LASTEXITCODE` | Meaning |
|---|---|
| 0 | All servers `Success` |
| 1 | One or more `PartialSuccess` |
| 2 | One or more `Failed` |
| 3 | Jumphost prereq missing or invalid parameter (thrown before scanning) |

## Architecture

- **`Export-ServerFacts`** — entry point. Validates jumphost prereqs, pre-populates a NetBIOS→FQDN domain cache from forest + trusts, loads default-filter data files once, fans out via `ForEach-Object -Parallel` (default `-ThrottleLimit 8`).
- **Per-server worker** — opens a single `New-PSSession`, runs all enabled collectors, applies orchestrator-side filters, resolves AD principals (cross-domain), normalizes NTFS ACEs, formats scheduled-task triggers, derives `ServiceAccounts`, builds the final result.
- **Per-server isolation** — each worker runs in try/catch. A single failed server gets `Status: "Failed"` with the exception captured; other servers continue.
- **Section-level isolation** — within a server, each collector runs in its own try/catch. A single failed section gets pushed to `Errors[]` and `Status` becomes `"PartialSuccess"`; other sections continue.
- **Cross-domain AD resolution** — `Get-ADUser` / `Get-ADGroup` are called with `-Server <domain FQDN>` based on each principal's home domain. NetBIOS→FQDN map is cached (synchronized hashtable) to avoid repeated trust lookups across runspaces.

## NTFS provisioning

`-NtfsSecurityProvisioning` controls how the worker reads NTFS ACLs on share paths:

| Mode | Behavior |
|---|---|
| `Auto` *(default)* | Use `NTFSSecurity` if present on target; else temp-copy the module to `$env:TEMP` for the session, clean up in `finally`; on failure, fall back to `Get-Acl` with a warning |
| `Install` | Use if present; else `Install-Module NTFSSecurity -Scope AllUsers -Force` on target; fall back to `Get-Acl` on failure |
| `None` | Use if present, else `Get-Acl` directly |

Either reader's output is normalized into the same `NtfsPermissions.Entries` shape.

## Customizing default-filter lists

Edit `data/*.psd1` — no code changes needed:

- `DefaultServices.psd1` — `KnownDefaults` (~244 Windows Server default service names) + `KnownCustomFalsePositives` (services in `%SystemRoot%` that should NOT be classified as default)
- `DefaultShares.psd1` — share names to hide (admin shares `<Letter>$`, `ADMIN$`, `IPC$`, `print$`, `NETLOGON`, `SYSVOL`, etc.)
- `DefaultTaskPaths.psd1` — scheduled-task path glob patterns (`\Microsoft\*` by default)
- `DefaultCertIssuers.psd1` — Issuer substring fragments considered Microsoft / public-CA defaults
- `DefaultFirewallGroupPrefixes.psd1` — Firewall rule `Group` prefixes considered Windows-shipped (`@FirewallAPI.dll`, `@%SystemRoot%\`, `@%ProgramFiles%`)

## Tests

```powershell
# Unit tests
Invoke-Pester ./tests

# Integration smoke test against localhost (validates output JSON against schema)
./tests/Invoke-SmokeTest.ps1
```
