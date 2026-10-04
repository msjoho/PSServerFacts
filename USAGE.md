# PSServerFacts — Usage Guide

A getting-started guide for people who've just installed the module. For the full sections reference, output schema, architecture, NTFS provisioning, and customization tables, see [../README.md](../README.md).

---

## 1. Install

**From PSGallery** (once published):

```powershell
Install-Module PSServerFacts -Scope CurrentUser
```

**From a local clone** (development):

```powershell
Import-Module .\PSServerFacts\PSServerFacts.psd1 -Force
```

Sanity check:

```powershell
Get-Command -Module PSServerFacts
# Export-ServerFacts
# ConvertTo-ServerFactsMarkdown
```

Both functions ship full comment-based help:

```powershell
Get-Help Export-ServerFacts -Full
Get-Help Export-ServerFacts -Examples
Get-Help Export-ServerFacts -Parameter ExpandUserRightsMembers
```

---

## 2. Prerequisites

**On the jumphost** (the machine you run the command from):

- PowerShell 7 or higher
- `ActiveDirectory` module (RSAT)
- `NTFSSecurity` module
- WinRM reachability to every target you intend to scan
- A Kerberos context that can read AD (typically the current user)

**On every target server:**

- WinRM enabled and listening
- The identity you scan with must be a local administrator
- PowerShell 5.1 or higher

**Optional soft prerequisites** (silent if absent):

- `dbatools` on jumphost or target — without it the `SqlServer` section returns registry-only facts with a section warning
- `chef-client.exe` on the target's `PATH` — used only to capture the Chef Infra Client version

Quick prereq check on the jumphost:

```powershell
$PSVersionTable.PSVersion         # 7.x expected
Get-Module ActiveDirectory -ListAvailable
Get-Module NTFSSecurity   -ListAvailable
Get-Module dbatools       -ListAvailable   # optional
Test-WSMan -ComputerName srv01             # WinRM reachable?
```

---

## 3. Your first run

Scan a single server with the current Kerberos context:

```powershell
Export-ServerFacts -ComputerName srv01
```

Output lands under `./output/<timestamp>/` relative to your current working directory. You'll see something like:

```
output/2026-05-20_103045_001/
├── srv01.json         # structured per-server inventory
├── srv01.md           # human-readable per-server report
├── _summary.md        # cross-server overview
├── _run.json          # parameters + per-server status
└── _errors.log        # orchestrator-level errors (rare, often absent)
```

Open `srv01.md` in any Markdown viewer. The report opens with:

1. A banner line with status (`Success` / `PartialSuccess` / `Failed`), scan duration, and the identity that ran it
2. An advisory summary block (if any rules fired)
3. One `## <Section>` heading per collected section, with inline advisory blockquotes where applicable

If the run-level status is `PartialSuccess`, look at the per-section error list inside the report and at `<server>.json` → `.Errors[]` for details.

---

## 4. Common scenarios

### 4.1 Many servers in parallel

```powershell
Export-ServerFacts -ComputerName srv01,srv02,srv03,srv04 -ThrottleLimit 4
```

Default `-ThrottleLimit` is 8. Each parallel runspace opens its own PSSession, so set the limit based on the jumphost's CPU/RAM and WinRM throughput, not the target count.

### 4.2 A different admin credential

```powershell
$cred = Get-Credential
Export-ServerFacts -ComputerName srv01 -Credential $cred -OutputRoot D:\serverfacts
```

The supplied identity must be a local admin on every named target.

### 4.3 Focused, fast scans

When you don't need a full inventory, restrict by section:

```powershell
# Only the four "deployment-shaped" sections
Export-ServerFacts -ComputerName srv01 `
    -IncludeSection Services,Shares,ScheduledTasks,Iis
```

```powershell
# Everything except the noisiest sections
Export-ServerFacts -ComputerName srv01 `
    -ExcludeSection InstalledApplications,Certificates,FirewallRules
```

`-ExcludeSection` is applied *after* `-IncludeSection`. If the combination produces an empty set the command throws before scanning.

### 4.4 Full inventory including Windows defaults

By default the collectors hide Windows-shipped services, shares, scheduled tasks, firewall rules, public-CA certificate issuers, and default user-right principals. To see them too:

```powershell
Export-ServerFacts -ComputerName srv01 `
    -IncludeAllServices `
    -IncludeAllShares `
    -IncludeAllScheduledTasks `
    -IncludeAllFirewallRules `
    -IncludeAllCertStores `
    -IncludeAllUserRights
```

You almost never want all six together — it produces huge output. Pick the categories that matter for the task at hand.

### 4.5 Deep NTFS on shares

```powershell
Export-ServerFacts -ComputerName srv01 -NtfsDepth Children
Export-ServerFacts -ComputerName srv01 -NtfsDepth Recursive
```

`Recursive` walks the full subtree of every custom share and can be slow on large file servers. Start with `Children` if you're unsure.

If `NTFSSecurity` isn't installed on the target, `-NtfsSecurityProvisioning Auto` (the default) stages it to `%TEMP%` for the session and removes it after. Use `Install` to install it persistently with `-Scope AllUsers`, or `None` to fall back to `Get-Acl` immediately.

### 4.6 Permissions with recursive AD expansion

```powershell
# Resolve AD group members in Administrators / RDP Users / WinRM Users
# down to ultimate user leaves across forest trusts
Export-ServerFacts -ComputerName srv01 -ExpandGroupMembers

# Same, but don't recurse into well-known huge default groups
# (Domain Admins, Enterprise Admins, etc.) — they're listed as groups
Export-ServerFacts -ComputerName srv01 -ExpandGroupMembers -SkipDefaultGroupExpansion
```

`-SkipDefaultGroupExpansion` is recommended for environments where Domain Admins is large or contains nested groups you don't want enumerated.

### 4.7 User Rights Assignment — custom view + effective members

The default view shows every privilege/principal pair *except* the ones that match the Windows Server default for that privilege. To see everything:

```powershell
Export-ServerFacts -ComputerName srv01 -IncludeAllUserRights
```

To also expand AD/BUILTIN group principals down to their user leaves (an "Effective members" block per right):

```powershell
Export-ServerFacts -ComputerName srv01 -ExpandUserRightsMembers
```

Effective-member sets can be very large; this is off by default. Combine with `-SkipDefaultGroupExpansion` for the same reason as 4.6.

### 4.8 SQL Server with explicit SQL credentials

```powershell
$sqlCred = Get-Credential
Export-ServerFacts -ComputerName sql01 `
    -SqlCredential $sqlCred `
    -IncludeSection SqlServer `
    -IncludeBackupDirectoryRoot
```

Windows authentication is the default. `-IncludeBackupDirectoryRoot` includes the SQL backup directory's root ACL on top of the non-inherited ACEs that are always collected.

For full live-query data (logins, jobs, AGs, backup history), install `dbatools` on either the jumphost or the target. Without it the section returns only registry-derived facts and emits a section warning.

### 4.9 Chef

The `Chef` collector runs unconditionally and returns `null` if Chef Infra isn't installed on the target. To capture the client version too, make sure `chef-client.exe` is on the target's `PATH`. Everything else (node identity, environment, server URL, run list, top-level attribute keys) comes from the client.rb / first-boot.json / node-cache files and works without the binary on `PATH`.

### 4.10 Advisories

Advisory rules evaluate the collected data and emit `Note`, `Warning`, or `Critical` items. They appear in the Markdown report by default — both as a summary block after the banner and inline under the section they apply to.

```powershell
# Include the advisories in <server>.json too (off by default)
Export-ServerFacts -ComputerName srv01 -AdvisoryJson

# Skip advisory evaluation entirely (both Markdown and JSON)
Export-ServerFacts -ComputerName srv01 -SkipAdvisories
```

`-SkipAdvisories` wins over `-AdvisoryJson`: passing both gets you no advisories in either format.

### 4.11 Cross-domain / cross-forest resolution

Both `-ExpandGroupMembers` (Permissions) and `-ExpandUserRightsMembers` (User Rights Assignment) recursively resolve AD principals. By default that uses your current Kerberos context — which works fine for the jumphost's home forest and any forests it trusts.

For **untrusted forests** or domains where you need a **different account** (e.g. a read-only service principal in a partner forest), pass `-DomainCredential` — a hashtable mapping domain names to PSCredential objects:

```powershell
$partnerCred = Get-Credential -UserName 'PARTNER\readonly-svc' `
                              -Message 'Partner forest read-only account'

Export-ServerFacts -ComputerName srv01 `
    -ExpandGroupMembers -ExpandUserRightsMembers `
    -DomainCredential @{
        'partner.example.net' = $partnerCred
        'lab.contoso.local'   = $labCred
    }
```

**Key format:**

- **FQDN** (recommended) — works for trusted *and* untrusted forests. The credential is also used to discover the domain's NetBIOS name so principals arriving as `PARTNER\jdoe` get resolved.
- **NetBIOS** — works only when the partner DC is already locatable (trusted forest, but you want a different account). For untrusted forests, use the FQDN.

```powershell
# Trusted partner, different account — NetBIOS is OK
-DomainCredential @{ 'PARTNER' = $cred }

# Untrusted forest — must use FQDN
-DomainCredential @{ 'partner.example.net' = $cred }
```

**Validation:** every entry is checked with a real `Get-ADDomain` call at startup. A wrong password fails the whole run before any target is scanned — you won't waste a long parallel sweep on a credential typo.

**Scope:** the credential applies only to AD calls for principals from that domain. Domains not in the map continue to use the caller's current Kerberos context. The credential has no effect on collectors that don't resolve AD principals (services, shares, certs, etc.).

**What it doesn't do:** it doesn't auto-discover forests. If a principal from a domain *not* in the map (and not reachable via current Kerberos) shows up, it still comes back as `Type: Unresolved` — you need to add that domain to the map explicitly.

---

## 5. Reading the output

### 5.1 Per-server Markdown (`<server>.md`)

- **Banner** — server name, status icon, scan time (UTC), duration, identity that ran the scan.
- **Advisory summary** — a single block listing every advisory grouped by severity. Absent if `-SkipAdvisories` is set or no rule fired.
- **Sections** — one `## <Section>` heading per collected section. Tables for list-shaped data (services, shares, certs, etc.); definition-list rows for scalar-shaped data (system, hardware). Filtered sections show their count in the heading, e.g. `## Services (n=12, filtered from 211)`.
- **Inline advisories** — blockquotes under the section heading they apply to.

### 5.2 Per-server JSON (`<server>.json`)

Top-level fields on every result:

| Field | Meaning |
|---|---|
| `Computer` | The name as you passed it |
| `ScannedAtUtc` | ISO 8601 UTC timestamp |
| `ScannedBy` | The Kerberos / explicit identity that ran the scan |
| `Status` | `Success`, `PartialSuccess`, or `Failed` |
| `DurationSeconds` | Wall-clock time for this server's worker |
| `CollectedSections` | Sections that were enabled for the run |
| `Errors` | `[]` on full success; one item per failed section on `PartialSuccess`; a single item on `Failed` |
| `Advisories` | Present only when `-AdvisoryJson` is set and `-SkipAdvisories` is not |
| *(one per collected section)* | Section-name → section payload |

A section is omitted from JSON when it wasn't in `CollectedSections`; it appears with value `null` when the collector ran but the host has nothing to report (e.g. `Iis` on a non-IIS box).

Schema lives at [`tests/schemas/server-assessment.schema.json`](../tests/schemas/server-assessment.schema.json).

### 5.3 Run-level files

- `_summary.md` — cross-server overview: one line per server with status and duration, aggregate service-account list, expiring-certs roll-up.
- `_run.json` — the run id, start / finish UTC, parameter snapshot, per-server status table. Useful for CI.
- `_errors.log` — orchestrator-level errors (rare; usually empty or absent). Per-section errors live inside the per-server JSON's `Errors[]`.

### 5.4 Exit codes

`Export-ServerFacts` publishes its run status to `$LASTEXITCODE` and does not emit anything to the pipeline. That keeps interactive runs quiet (no stray `0` at the prompt) and gives CI a familiar shell-style check.

| `$LASTEXITCODE` | Meaning |
|---|---|
| 0 | All servers `Success` |
| 1 | One or more `PartialSuccess` |
| 2 | One or more `Failed` |
| 3 | Jumphost prereq missing or invalid parameter (thrown before scanning) |

Example CI gate:

```powershell
Export-ServerFacts -ComputerName $servers -OutputRoot $env:WORKSPACE\reports
if ($LASTEXITCODE -gt 0) { throw "Export-ServerFacts returned $LASTEXITCODE" }
```

---

## 6. Customizing default-filter lists

The collectors filter against editable PowerShell data files under `PSServerFacts/data/`. Edit them directly — no code change required.

For example, to suppress a custom service you ship that lives in `%SystemRoot%` (and therefore looks "default" to the path heuristic), add it to `KnownCustomFalsePositives` in `DefaultServices.psd1`:

```powershell
# PSServerFacts/data/DefaultServices.psd1
@{
    KnownDefaults              = @( 'wuauserv', 'WinRM', ... )
    KnownCustomFalsePositives  = @( 'MyCustomSvc' )   # <-- add here
}
```

The full table of data files, what they filter, and the matching `-IncludeAll*` switch is in [../README.md](../README.md#customizing-default-filter-lists).

---

## 7. Troubleshooting

### "I edited the module and nothing changed"

The most common issue. PowerShell modules are imported once per session and are not auto-reloaded. If you have a system-scope install at `C:\Program Files\PowerShell\7\Modules\PSServerFacts\`, it shadows your local clone.

```powershell
# In the same elevated session, to refresh the system-scope copy:
Get-Module PSServerFacts | Remove-Module -Force -ErrorAction SilentlyContinue
Copy-Item -Path 'C:\path\to\clone\PSServerFacts\*' `
          -Destination 'C:\Program Files\PowerShell\7\Modules\PSServerFacts\' `
          -Recurse -Force
```

For active development, install to user scope instead so refresh is just a re-import:

```powershell
Get-Module PSServerFacts | Remove-Module -Force
Import-Module .\PSServerFacts\PSServerFacts.psd1 -Force
```

### WinRM authentication failures

```
[srv01] Connecting to remote server srv01 failed with the following error message:
The user name or password is incorrect.
```

- Make sure you can `Test-WSMan srv01` first.
- For Kerberos, the jumphost and the target must agree on names — prefer the FQDN over a short name.
- If the calling identity is wrong, pass an explicit `-Credential`.
- If you need to scan via IP or across an untrusted forest, you'll need either explicit `-Credential` plus a TrustedHosts entry, or CredSSP. Single-hop is fine; double-hop (e.g. the worker invoking AD on a third box) needs Kerberos delegation.

### `Chef` section is `null` but Chef is installed

The collector looks for the standard config files (`C:\chef\client.rb`, etc.). Make sure they exist and that the target has been bootstrapped at least once. If the version field is empty but the rest is populated, `chef-client.exe` isn't on the target's `PATH` — that's the only thing the binary is used for.

### `SqlServer` section has only registry facts

`dbatools` isn't available to the worker. Install it on the jumphost (`Install-Module dbatools -Scope CurrentUser`) or on the target. The section warning in the report will name the host that's missing it.

### `LocalUsers` shows up as `null` instead of a table

Expected — that means there are no non-system local accounts (well-known RIDs 500/501/503/504 are filtered out). If you do have custom local accounts and still see `null`, check the worker error list in the per-server JSON.

### `Crash dump > Dedicated: *(none)*`

Expected — `DedicatedDumpFile` is unset, meaning the system uses the default dump location instead of a dedicated file. Not a problem.

### `UserRightsAssignment` effective-member lists are empty

The `EffectiveMembers` field is only emitted when you pass `-ExpandUserRightsMembers`. Without that switch, the principal is listed but not expanded.

### `Status: PartialSuccess`

One or more collectors threw. Look at:

1. `<server>.md` → "Errors" block at the bottom
2. `<server>.json` → `.Errors[]` for the full exception message + stack
3. `_run.json` for the aggregate parameters that were in effect

### `Status: Failed`

The whole worker aborted — typically the PSSession could not be established or threw immediately. Check `_errors.log` and the per-server JSON; `Errors[0]` will hold the exception.

---

## 8. Where to go next

- **[../README.md](../README.md)** — sections reference, full output schema, architecture, NTFS provisioning, customization tables, tests.
- **[../tests/schemas/server-assessment.schema.json](../tests/schemas/server-assessment.schema.json)** — JSON shape (canonical).
- **`Get-Help Export-ServerFacts -Full`** — every parameter, every example.
- **`Get-Help ConvertTo-ServerFactsMarkdown -Full`** — re-rendering stored JSON to Markdown.
- **../docs/superpowers/specs/** — design history. Useful when you want to understand why a collector is shaped the way it is.
