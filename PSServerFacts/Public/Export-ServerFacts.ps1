function Export-ServerFacts {
    <#
    .SYNOPSIS
        Capture point-in-time configuration facts for one or more Windows Servers and write them to disk.

    .DESCRIPTION
        Export-ServerFacts is the entry point of the PSServerFacts module. From a jumphost,
        it opens a WinRM PSSession to each target in parallel, runs a configurable set of
        collectors (System, Hardware, Disks, Network, InstalledApplications, ChocolateyPackages,
        WindowsFeatures, Permissions, Services, Shares, ScheduledTasks, LocalUsers,
        FirewallRules, Iis, Certificates, PendingReboot, PowerPlan, PageFile, Tls, Smb, Chef,
        SqlServer, Defender, UserRightsAssignment) and emits a per-server JSON + Markdown plus
        a cross-server summary into a timestamped run folder under -OutputRoot.

        Each collector runs in its own try/catch so a single failure degrades the server's
        Status to PartialSuccess rather than aborting the run. The whole worker is wrapped
        likewise so one unreachable server doesn't fail the rest.

        Default-filter data files under PSServerFacts/data/*.psd1 trim Windows-shipped
        services, shares, scheduled tasks, firewall groups, cert issuers, and user-right
        principals from the output. Bypass per category with the matching -IncludeAll*
        switches.

        Optional advisory rules under Private/Advisors/ evaluate the collected data and
        emit Note / Warning / Critical entries. Advisories appear inline in the Markdown
        report by default; pass -AdvisoryJson to also embed them in the JSON, or
        -SkipAdvisories to bypass evaluation.

    .PARAMETER ComputerName
        One or more target server names (NetBIOS, FQDN, or IP). Each is scanned in parallel
        subject to -ThrottleLimit.

    .PARAMETER Credential
        PSCredential used for the WinRM PSSession. Omit to use the calling user's Kerberos
        context. The supplied identity must have local admin rights on every target.

    .PARAMETER SqlCredential
        PSCredential used by the SqlServer collector to authenticate to SQL Server instances.
        Omit for Windows authentication (default). Ignored if SqlServer is not collected.

    .PARAMETER OutputRoot
        Root folder under which a timestamped subfolder is created for this run. Defaults
        to ./output relative to the current location. The folder receives per-server
        <name>.json, <name>.md, _summary.md, _run.json, and _errors.log.

    .PARAMETER ThrottleLimit
        Maximum number of targets scanned concurrently via ForEach-Object -Parallel.
        Default: 8.

    .PARAMETER NtfsDepth
        How deep the Shares collector walks NTFS ACLs on each share path:
          Root       - the share root only (fastest, default)
          Children   - root + immediate children
          Recursive  - the full subtree (slowest, largest output)

    .PARAMETER NtfsSecurityProvisioning
        How the worker obtains the NTFSSecurity module on the target:
          Auto    - use if present, else stage to %TEMP% for the session, fall back to
                    Get-Acl on failure (default)
          Install - use if present, else Install-Module NTFSSecurity -Scope AllUsers -Force
                    on the target, fall back to Get-Acl on failure
          None    - use if present, else Get-Acl directly (no install / stage)

    .PARAMETER IncludeAllServices
        Disable the default-services filter (data/DefaultServices.psd1). Without this, only
        services whose binary lives outside %SystemRoot% AND whose name is not in
        KnownDefaults are returned.

    .PARAMETER IncludeAllShares
        Disable the default-shares filter (data/DefaultShares.psd1). Without this, admin
        shares (ADMIN$, C$, etc.), IPC$, NETLOGON, SYSVOL, and print$ are hidden.

    .PARAMETER IncludeAllScheduledTasks
        Disable the default-task-path filter (data/DefaultTaskPaths.psd1). Without this,
        tasks under \Microsoft\* are hidden.

    .PARAMETER IncludeAllCertStores
        Include the full contents of LocalMachine\Root and LocalMachine\CA. Without this,
        public-CA and Microsoft-shipped issuers (data/DefaultCertIssuers.psd1) are filtered
        out of those two stores. My, WebHosting, and TrustedPublisher are always included
        in full.

    .PARAMETER IncludeAllFirewallRules
        Disable the default-firewall-group filter (data/DefaultFirewallGroupPrefixes.psd1).
        Without this, rules whose Group field begins with a Microsoft-shipped prefix
        (e.g. @FirewallAPI.dll, @%SystemRoot%\, AppX/UWP package groups) are hidden.

    .PARAMETER IncludeBackupDirectoryRoot
        For the SqlServer collector, include the root ACL of the SQL backup directory.
        Without this only non-inherited ACEs (where the directory deviates from its parent)
        are emitted.

    .PARAMETER ExpandGroupMembers
        For the Permissions collector, recursively expand AD groups inside Administrators,
        Remote Desktop Users, and Remote Management Users to their ultimate user leaves
        (resolved across forest trusts). Without this, AD group members are listed as
        groups, not users.

    .PARAMETER SkipDefaultGroupExpansion
        When -ExpandGroupMembers is set, do not recurse INTO well-known default AD groups
        (Domain Admins, Enterprise Admins, etc.). The group is still listed; its members
        are not enumerated. Useful when those groups are very large.

    .PARAMETER IncludeAllUserRights
        For the UserRightsAssignment collector, emit every privilege/principal pair.
        Without this, the collector hides pairs whose principal matches the Windows
        Server default for that privilege (data/DefaultUserRights.psd1).

    .PARAMETER ExpandUserRightsMembers
        For each user-right principal that is an AD or BUILTIN group, emit an
        EffectiveMembers field with the recursively-expanded user leaves. Off by default
        because effective-member sets can be large.

    .PARAMETER AdvisoryJson
        Embed the computed advisories in the per-server JSON output under an Advisories
        top-level field. Advisories are always included inline in the Markdown report
        unless -SkipAdvisories is set.

    .PARAMETER SkipAdvisories
        Do not evaluate advisory rules. The Markdown report will not include the advisory
        summary block or inline advisories; the JSON will not include them either,
        regardless of -AdvisoryJson.

    .PARAMETER IncludeSection
        Restrict collection to the listed sections (whitelist). When omitted, every
        section runs.

    .PARAMETER ExcludeSection
        Skip the listed sections (blacklist). Applied after -IncludeSection. If the
        combination produces an empty set, the function throws.

    .PARAMETER DomainCredential
        Optional hashtable mapping domain names to PSCredential objects, used when
        Resolve-AdPrincipal / Expand-AdGroupMember need to read AD for principals
        in domains where the current Kerberos context is insufficient — typically
        untrusted forests, or a different forest the caller has a separate account
        in.

        Keys may be FQDNs (recommended; e.g. 'partner.example.net') or NetBIOS
        names (e.g. 'PARTNER'). At startup each key is validated by a real
        Get-ADDomain call — a wrong password fails the whole run before any
        target is touched. FQDN keys work for both trusted and untrusted forests;
        NetBIOS keys only work where the partner DC is already locatable (trusted
        forest, but you want a different account).

        Domains not in the map use the caller's current Kerberos context as
        before. Has no effect on collectors that do not resolve AD principals.

    .EXAMPLE
        $partnerCred = Get-Credential -UserName 'PARTNER\readonly-svc' `
                                       -Message 'Partner forest read-only account'
        Export-ServerFacts -ComputerName srv01 -ExpandGroupMembers `
            -DomainCredential @{ 'partner.example.net' = $partnerCred }

        Scan srv01 and recursively expand the local Administrators group; when a
        member belongs to the untrusted PARTNER forest, read that forest with the
        supplied credential instead of failing with Type=Unresolved.

    .EXAMPLE
        Export-ServerFacts -ComputerName srv01

        Scan a single server with the current user's Kerberos context. Output lands in
        ./output/<timestamp>/ under the current working directory.

    .EXAMPLE
        $cred = Get-Credential
        Export-ServerFacts -ComputerName srv01,srv02,srv03 -Credential $cred `
            -OutputRoot D:\serverfacts

        Scan three servers in parallel under explicit credentials and write the run folder
        under D:\serverfacts\.

    .EXAMPLE
        Export-ServerFacts -ComputerName srv01 `
            -IncludeSection Services,Shares,ScheduledTasks,UserRightsAssignment

        Run only the four named collectors. Useful for fast, focused runs.

    .EXAMPLE
        Export-ServerFacts -ComputerName srv01 -IncludeAllServices -IncludeAllShares `
            -IncludeAllFirewallRules

        Emit every service, share, and firewall rule including Windows-shipped defaults.
        Useful when you need a full inventory and not a customizations-only view.

    .EXAMPLE
        $sqlCred = Get-Credential
        Export-ServerFacts -ComputerName sql01 -SqlCredential $sqlCred `
            -IncludeSection SqlServer -IncludeBackupDirectoryRoot

        Collect only SQL Server data using a SQL login, and include the backup directory's
        root ACL in addition to non-inherited ACEs.

    .EXAMPLE
        Export-ServerFacts -ComputerName srv01 -ExpandGroupMembers `
            -SkipDefaultGroupExpansion -IncludeAllUserRights -ExpandUserRightsMembers

        Get fully-expanded permissions and user-rights data without recursing into the
        very large default AD groups (Domain Admins, etc.). Useful for compliance
        evidence packages.

    .EXAMPLE
        Export-ServerFacts -ComputerName srv01,srv02 -SkipAdvisories -AdvisoryJson

        Note that -SkipAdvisories wins: advisories are not evaluated and -AdvisoryJson
        has no effect. To get advisories in JSON, drop -SkipAdvisories.

    .OUTPUTS
        None. The function writes files and progress to the host; it does not
        emit anything to the pipeline. The exit-code-style status is published
        to $LASTEXITCODE:
          0 - all servers Success
          1 - one or more PartialSuccess
          2 - one or more Failed

        File output (in <OutputRoot>/<runId>/):
          <server>.json    - structured per-server inventory
          <server>.md      - human-readable per-server report
          _summary.md      - cross-server overview
          _run.json        - parameters + per-server status
          _errors.log      - orchestrator-level errors (rare)

    .NOTES
        Prerequisites on the jumphost:
          - PowerShell 7+
          - ActiveDirectory module (RSAT)
          - NTFSSecurity module (Install-Module NTFSSecurity)
          - WinRM reachability to all targets
        Prerequisites on each target:
          - WinRM enabled
          - Caller has local admin rights
          - PowerShell 5.1 or higher
        Optional on target:
          - chef-client.exe on PATH (used only to capture Chef Infra Client version)
          - dbatools module (full SQL Server live-query data)

        See docs/USAGE.md for the new-user getting-started guide.

    .LINK
        ConvertTo-ServerFactsMarkdown

    .LINK
        https://github.com/martin-joho/PSServerFacts
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)][string[]]$ComputerName,
        [pscredential]$Credential,
        [pscredential]$SqlCredential,
        [string]$OutputRoot,
        [int]$ThrottleLimit = 8,
        [ValidateSet('Root','Children','Recursive')][string]$NtfsDepth = 'Root',
        [ValidateSet('Auto','Install','None')][string]$NtfsSecurityProvisioning = 'Auto',
        [switch]$IncludeAllServices,
        [switch]$IncludeAllShares,
        [switch]$IncludeAllScheduledTasks,
        [switch]$IncludeAllCertStores,
        [switch]$IncludeAllFirewallRules,
        [switch]$IncludeBackupDirectoryRoot,
        [switch]$ExpandGroupMembers,
        [switch]$SkipDefaultGroupExpansion,
        [switch]$IncludeAllUserRights,
        [switch]$ExpandUserRightsMembers,
        [switch]$AdvisoryJson,
        [switch]$SkipAdvisories,
        [hashtable]$DomainCredential,

        [ValidateSet('System','Hardware','Disks','Network','InstalledApplications',
                     'ChocolateyPackages','WindowsFeatures','Permissions','Services','Shares',
                     'ScheduledTasks','LocalUsers','FirewallRules','Iis','Certificates','PendingReboot','PowerPlan','PageFile','Tls','Smb','Chef','SqlServer','Defender','UserRightsAssignment')]
        [string[]]$IncludeSection,

        [ValidateSet('System','Hardware','Disks','Network','InstalledApplications',
                     'ChocolateyPackages','WindowsFeatures','Permissions','Services','Shares',
                     'ScheduledTasks','LocalUsers','FirewallRules','Iis','Certificates','PendingReboot','PowerPlan','PageFile','Tls','Smb','Chef','SqlServer','Defender','UserRightsAssignment')]
        [string[]]$ExcludeSection
    )

    if (-not $OutputRoot) { $OutputRoot = Join-Path (Get-Location).Path 'output' }
    $moduleRoot = Split-Path $PSScriptRoot -Parent

    Test-JumphostPrerequisite

    $allSections = @('System','Hardware','Disks','Network','InstalledApplications',
                     'ChocolateyPackages','WindowsFeatures','Permissions','Services','Shares',
                     'ScheduledTasks','LocalUsers','FirewallRules','Iis','Certificates','PendingReboot','PowerPlan','PageFile','Tls','Smb','Chef','SqlServer','Defender','UserRightsAssignment')

    $activeSections = if ($IncludeSection) { @($IncludeSection) } else { $allSections }
    if ($ExcludeSection) {
        $activeSections = @($activeSections | Where-Object { $_ -notin $ExcludeSection })
    }
    if ($activeSections.Count -eq 0) {
        throw 'No sections to collect — Include/Exclude combination produces empty set.'
    }

    $domainCache = [hashtable]::Synchronized(@{})
    try {
        $current = (Get-ADDomain).NetBIOSName
        $domainCache[$current.ToUpperInvariant()] = (Get-ADDomain).DNSRoot
        foreach ($trust in (Get-ADTrust -Filter * -ErrorAction SilentlyContinue)) {
            $domainCache[$trust.Name.ToUpperInvariant()] = $trust.Target
        }
    } catch { Write-Verbose "Domain cache pre-population failed: $($_.Exception.Message)" }

    # Normalize -DomainCredential into an FQDN(upper) → PSCredential map and
    # seed the netbios→fqdn cache so untrusted-forest principals are reachable.
    # Keys may be FQDN (recommended) or NetBIOS. Each is validated by a real
    # Get-ADDomain call up-front so a bad credential fails fast, before any
    # target scan starts. Failures here raise — they're a config problem.
    $domainCredentialMap = [hashtable]::Synchronized(@{})
    if ($DomainCredential -and $DomainCredential.Count -gt 0) {
        foreach ($k in @($DomainCredential.Keys)) {
            $cred = $DomainCredential[$k]
            if ($cred -isnot [pscredential]) {
                throw "DomainCredential['$k']: value must be a [pscredential]; got [$($cred.GetType().FullName)]."
            }
            try {
                $dom = if ($k -like '*.*') {
                    Get-ADDomain -Server $k -Credential $cred -ErrorAction Stop
                } else {
                    Get-ADDomain -Identity $k -Credential $cred -ErrorAction Stop
                }
            } catch {
                throw "DomainCredential['$k']: cannot reach AD with the supplied credential — $($_.Exception.Message)"
            }
            $domainCache[$dom.NetBIOSName.ToUpperInvariant()] = $dom.DNSRoot
            $domainCredentialMap[$dom.DNSRoot.ToUpperInvariant()] = $cred
        }
    }

    $dataFiles = @{
        DefaultServices              = Import-PowerShellDataFile -Path "$moduleRoot/data/DefaultServices.psd1"
        DefaultShares                = Import-PowerShellDataFile -Path "$moduleRoot/data/DefaultShares.psd1"
        DefaultTaskPaths             = Import-PowerShellDataFile -Path "$moduleRoot/data/DefaultTaskPaths.psd1"
        DefaultCertIssuers           = Import-PowerShellDataFile -Path "$moduleRoot/data/DefaultCertIssuers.psd1"
        DefaultFirewallGroupPrefixes = Import-PowerShellDataFile -Path "$moduleRoot/data/DefaultFirewallGroupPrefixes.psd1"
        DefaultUserRights            = Import-PowerShellDataFile -Path "$moduleRoot/data/DefaultUserRights.psd1"
    }

    $runFolder  = New-RunFolder -Root $OutputRoot
    $runId      = Split-Path $runFolder -Leaf
    $startedUtc = (Get-Date).ToUniversalTime().ToString('o')

    Write-Host "PSServerFacts run $runId — output: $runFolder"

    $paramSnapshot = [ordered]@{
        ComputerName               = $ComputerName
        Credential                 = if ($Credential)    { $Credential.UserName }    else { 'currentUser' }
        SqlCredential              = if ($SqlCredential) { $SqlCredential.UserName } else { '' }
        ThrottleLimit              = $ThrottleLimit
        NtfsDepth                  = $NtfsDepth
        NtfsSecurityProvisioning   = $NtfsSecurityProvisioning
        IncludeAllServices         = [bool]$IncludeAllServices
        IncludeAllShares           = [bool]$IncludeAllShares
        IncludeAllScheduledTasks   = [bool]$IncludeAllScheduledTasks
        IncludeAllCertStores       = [bool]$IncludeAllCertStores
        IncludeAllFirewallRules    = [bool]$IncludeAllFirewallRules
        IncludeBackupDirectoryRoot = [bool]$IncludeBackupDirectoryRoot
        ExpandGroupMembers         = [bool]$ExpandGroupMembers
        SkipDefaultGroupExpansion  = [bool]$SkipDefaultGroupExpansion
        IncludeAllUserRights       = [bool]$IncludeAllUserRights
        ExpandUserRightsMembers    = [bool]$ExpandUserRightsMembers
        AdvisoryJson               = [bool]$AdvisoryJson
        SkipAdvisories             = [bool]$SkipAdvisories
        DomainCredentialFqdns      = @($domainCredentialMap.Keys)
        Sections                   = $activeSections
    }

    $results = $ComputerName | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        Import-Module (Join-Path $using:moduleRoot 'PSServerFacts.psd1') -Force -ErrorAction Stop
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
        Import-Module NTFSSecurity   -ErrorAction SilentlyContinue
        # dbatools is only used by the SqlServer collector and prints a noisy
        # encryption-defaults banner on import. Skip it entirely when SqlServer
        # is not in scope; swallow all output streams (`*>$null`) when it is.
        if ('SqlServer' -in $using:activeSections) {
            Import-Module dbatools -ErrorAction SilentlyContinue *>$null
        }

        $workerArgs = @{
            ComputerName               = $_
            DomainCache                = $using:domainCache
            DataFiles                  = $using:dataFiles
            NtfsDepth                  = $using:NtfsDepth
            NtfsSecurityProvisioning   = $using:NtfsSecurityProvisioning
            IncludeAllServices         = [bool]$using:IncludeAllServices
            IncludeAllShares           = [bool]$using:IncludeAllShares
            IncludeAllScheduledTasks   = [bool]$using:IncludeAllScheduledTasks
            IncludeAllCertStores       = [bool]$using:IncludeAllCertStores
            IncludeAllFirewallRules    = [bool]$using:IncludeAllFirewallRules
            IncludeBackupDirectoryRoot = [bool]$using:IncludeBackupDirectoryRoot
            ExpandGroupMembers         = [bool]$using:ExpandGroupMembers
            SkipDefaultGroupExpansion  = [bool]$using:SkipDefaultGroupExpansion
            IncludeAllUserRights       = [bool]$using:IncludeAllUserRights
            ExpandUserRightsMembers    = [bool]$using:ExpandUserRightsMembers
            AdvisoryJson               = [bool]$using:AdvisoryJson
            SkipAdvisories             = [bool]$using:SkipAdvisories
            DomainCredential           = $using:domainCredentialMap
            Section                    = $using:activeSections
        }
        if ($using:Credential)    { $workerArgs['Credential']    = $using:Credential }
        if ($using:SqlCredential) { $workerArgs['SqlCredential'] = $using:SqlCredential }

        Get-ServerFacts @workerArgs
    }

    foreach ($r in $results) {
        $safeName = ($r.Computer -replace '[^A-Za-z0-9._-]', '_')
        $jsonPath = Join-Path $runFolder "$safeName.json"
        $mdPath   = Join-Path $runFolder "$safeName.md"
        $r | ConvertTo-Json -Depth 12 | Set-Content -Path $jsonPath -Encoding utf8
        ConvertTo-ServerFactsMarkdown -Result $r | Set-Content -Path $mdPath -Encoding utf8
    }

    $finishedUtc = (Get-Date).ToUniversalTime().ToString('o')

    $run = [ordered]@{
        RunId       = $runId
        StartedUtc  = $startedUtc
        FinishedUtc = $finishedUtc
        Parameters  = $paramSnapshot
        Servers     = @($results | ForEach-Object { [ordered]@{ Name=$_.Computer; Status=$_.Status; DurationSeconds=$_.DurationSeconds } })
    }
    $run | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $runFolder '_run.json') -Encoding utf8

    try {
        Format-RunSummary -Results $results -StartedUtc $startedUtc -FinishedUtc $finishedUtc |
            Set-Content -Path (Join-Path $runFolder '_summary.md') -Encoding utf8
    } catch {
        "_summary.md generation failed: $($_.Exception.Message)" | Add-Content -Path (Join-Path $runFolder '_errors.log')
    }

    foreach ($r in $results) {
        Write-Host ("  {0}: {1} {2} {3:F1}s" -f $r.Computer, $r.Status, [char]0x00B7, $r.DurationSeconds)
    }

    $failed  = @($results | Where-Object Status -eq 'Failed').Count
    $partial = @($results | Where-Object Status -eq 'PartialSuccess').Count
    # Don't emit the exit code as a pipeline value — it would print "0" at the
    # interactive prompt. Set $LASTEXITCODE so CI scripts can still inspect it.
    $global:LASTEXITCODE = if     ($failed  -gt 0) { 2 }
                           elseif ($partial -gt 0) { 1 }
                           else                    { 0 }
    return
}
