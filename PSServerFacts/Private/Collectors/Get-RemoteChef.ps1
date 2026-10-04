function ConvertFrom-ChefClientRb {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)

    $out = [ordered]@{
        NodeName = $null; ChefServerUrl = $null; Environment = $null
        ValidationClient = $null; LogLevel = $null; LogLocation = $null
    }
    $patterns = @(
        @{ Re = '^\s*node_name\s+["''](?<v>[^"'']+)["'']';              Field = 'NodeName' },
        @{ Re = '^\s*chef_server_url\s+["''](?<v>[^"'']+)["'']';        Field = 'ChefServerUrl' },
        @{ Re = '^\s*environment\s+["''](?<v>[^"'']+)["'']';            Field = 'Environment' },
        @{ Re = '^\s*validation_client_name\s+["''](?<v>[^"'']+)["'']'; Field = 'ValidationClient' },
        @{ Re = '^\s*log_level\s+:?(?<v>\w+)';                          Field = 'LogLevel' },
        @{ Re = '^\s*log_location\s+["''](?<v>[^"'']+)["'']';           Field = 'LogLocation' }
    )
    foreach ($line in ($Content -split "(`r`n|`r|`n)")) {
        $trim = $line.Trim()
        if (-not $trim -or $trim.StartsWith('#')) { continue }
        foreach ($p in $patterns) {
            if ($trim -match $p.Re) { $out[$p.Field] = $matches['v']; break }
        }
    }
    [pscustomobject]$out
}

function ConvertFrom-ChefClientLog {
    # Parse a chef-client log tail for the most recent run-list line. The
    # client emits "Run List is [recipe[a], role[b], ...]" near the start of
    # every run; the cache JSONs only contain run lists when data-collector
    # reporting is enabled, so the log is the more reliable source on most
    # nodes. Returns the items split on entry boundaries, with surrounding
    # whitespace trimmed; returns @() if no match is found.
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) { return @() }

    $matchesAll = [regex]::Matches($Content, 'Run List is\s*\[(?<rl>[^\r\n]+?)\](?:\r|\n|$)')
    if ($matchesAll.Count -eq 0) { return @() }

    $inner = $matchesAll[$matchesAll.Count - 1].Groups['rl'].Value
    # Items themselves contain `[name]`, so we cannot split on commas naively.
    # Match the two known forms (recipe[…], role[…]) and any bare cookbook ids.
    $items = [regex]::Matches($inner, '(?:recipe|role)\[[^\]]+\]|[A-Za-z0-9_:\-\.]+')
    @($items | ForEach-Object { $_.Value.Trim() } | Where-Object { $_ })
}

function ConvertFrom-ChefLastRunReport {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path $Path)) { return $null }
    $rawJson = $null
    try {
        $rawJson = Get-Content -Raw -Path $Path -ErrorAction Stop
        $node = $rawJson | ConvertFrom-Json -ErrorAction Stop
    } catch { return $null }

    $keysOf = {
        param($obj)
        if ($null -eq $obj) { return @() }
        @($obj.PSObject.Properties.Name | Where-Object { $_ })
    }

    # Extract time fields as raw strings from JSON before ConvertFrom-Json auto-parses them as DateTime.
    $endTime = $null
    foreach ($prop in 'end_time','EndTime','last_run','LastRun') {
        if ($rawJson -match ('"' + $prop + '"\s*:\s*"(?<v>[^"]+)"')) {
            $endTime = $matches['v']; break
        }
    }

    [pscustomobject]@{
        RunList              = @($node.run_list)
        AttributeKeys        = [pscustomobject]@{
            default   = @(& $keysOf $node.default)
            normal    = @(& $keysOf $node.normal)
            override  = @(& $keysOf $node.override)
            automatic = @(& $keysOf $node.automatic)
        }
        LastSuccessfulRunUtc = $endTime
    }
}

function Get-RemoteChef {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    $probe = Invoke-Command -Session $Session -ScriptBlock {
        $registryHit = $false
        foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                          'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
            if (Test-Path $root) {
                $registryHit = [bool](Get-ChildItem $root -ErrorAction SilentlyContinue |
                    Get-ItemProperty -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -like 'Chef Infra Client*' -or $_.DisplayName -like 'Chef Client*' })
                if ($registryHit) { break }
            }
        }
        $clientRbPath = 'C:\chef\client.rb'
        $fileHit = Test-Path $clientRbPath
        if (-not $registryHit -and -not $fileHit) { return $null }

        $rbContent = if ($fileHit) { Get-Content -Raw -Path $clientRbPath -ErrorAction SilentlyContinue } else { $null }

        # The cache JSON is queried for AttributeKeys + LastSuccessfulRunUtc.
        # Priority order matters:
        #   1. nodes/<node>.json — the full cached node object (default/normal/
        #      override/automatic attribute trees, run_list, last run). Written
        #      after every successful chef-client run; this is the canonical
        #      local source.
        #   2. last_run_report.json — only present when a JSON report handler
        #      is configured. Contains a run report; fields vary by handler.
        #   3. data_collector_metadata.json — only contains a node_uuid hash;
        #      NO attributes, NO run_list. Skip — looking here was a bug.
        $cacheRoot   = 'C:\chef\cache'
        $cachePath   = $null
        $cacheSource = $null
        if (Test-Path $cacheRoot) {
            $node = Get-ChildItem (Join-Path $cacheRoot 'nodes') -Filter '*.json' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
            if ($node) {
                $cachePath   = $node.FullName
                $cacheSource = 'NodeCache'
            } else {
                $p = Join-Path $cacheRoot 'last_run_report.json'
                if (Test-Path $p) {
                    $cachePath   = $p
                    $cacheSource = 'LastRunReport'
                }
            }
        }

        # Read the most recent client log so the worker can fall back to log
        # parsing when cache JSONs lack the run list (common when
        # data-collector reporting is off). The "Run List is [...]" line is
        # emitted at the START of every run, so we read from the beginning of
        # the file (capped at 4 MB) rather than tailing — busy nodes can write
        # 100s of KB of converge output per run, pushing the start-of-run
        # marker out of any small tail window.
        #
        # chef-client may hold the log file open for append. We open with
        # FileShare = ReadWrite|Delete (most permissive) so a running daemon
        # cannot block the read. Status is captured so the caller can surface
        # why a read wasn't produced when the run list ends up empty.
        $logTail   = $null
        $logStatus = 'NoDir'
        $logPath   = $null
        $logRoot   = 'C:\chef\log'
        $maxBytes  = 4MB
        if (Test-Path $logRoot) {
            $logFiles = @(Get-ChildItem $logRoot -Filter '*.log' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTimeUtc -Descending)
            if ($logFiles.Count -eq 0) {
                $logStatus = 'NoFile'
            } else {
                # Walk newest → older until we either succeed at reading and
                # find a "Run List is" line, or exhaust candidates. Some sites
                # rotate to YYYYMMDD.log and start a fresh empty client.log;
                # the freshest mtime can be a near-empty file.
                foreach ($logFile in ($logFiles | Select-Object -First 4)) {
                    $logPath = $logFile.FullName
                    try {
                        $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
                        $fs = [System.IO.File]::Open($logFile.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
                        try {
                            $len = $fs.Length
                            if ($len -le 0) { $logStatus = 'Empty'; continue }
                            # If the file is bigger than our cap, read the LAST
                            # $maxBytes — late-run output is more useful than
                            # nothing, and we still try older files below.
                            $take = [Math]::Min($len, $maxBytes)
                            if ($len -gt $maxBytes) { $fs.Seek($len - $maxBytes, [System.IO.SeekOrigin]::Begin) | Out-Null }
                            $buf = New-Object byte[] $take
                            $read = $fs.Read($buf, 0, $take)
                            $content = [System.Text.Encoding]::UTF8.GetString($buf, 0, $read)
                        } finally { $fs.Dispose() }
                        if ($content -match 'Run List is\s*\[') {
                            $logTail = $content; $logStatus = 'OK'; break
                        }
                        # File was readable but no run-list marker — keep the
                        # content as a partial fallback and try older files.
                        if (-not $logTail) { $logTail = $content; $logStatus = 'OK-NoRunList' }
                    } catch {
                        $logStatus = "Error: $($_.Exception.Message)"
                    }
                }
            }
        }

        $version = $null
        $exe = Get-Command 'chef-client.exe' -ErrorAction SilentlyContinue
        if ($exe) {
            try {
                $job = Start-Job { & 'chef-client.exe' --version 2>$null }
                if (Wait-Job $job -Timeout 5) { $version = (Receive-Job $job) -join "`n" }
                Remove-Job $job -Force -ErrorAction SilentlyContinue
            } catch {}
        }

        [pscustomobject]@{
            Detected    = $true
            ClientRb    = $rbContent
            CachePath   = $cachePath
            CacheSource = $cacheSource
            LogPath     = $logPath
            LogTail     = $logTail
            LogStatus   = $logStatus
            Version     = $version
        }
    }

    if ($null -eq $probe) { return $null }

    $rb = if ($probe.ClientRb) { ConvertFrom-ChefClientRb -Content $probe.ClientRb } else {
        [pscustomobject]@{ NodeName=$null; ChefServerUrl=$null; Environment=$null; ValidationClient=$null }
    }

    $cacheJson = if ($probe.CachePath) {
        Invoke-Command -Session $Session -ArgumentList $probe.CachePath -ScriptBlock {
            param($p) Get-Content -Raw -Path $p -ErrorAction SilentlyContinue
        }
    } else { $null }

    $report = if ($cacheJson) {
        $tmp = New-TemporaryFile
        try {
            Set-Content -Path $tmp.FullName -Value $cacheJson -Encoding utf8
            ConvertFrom-ChefLastRunReport -Path $tmp.FullName
        } finally { Remove-Item -Path $tmp.FullName -Force -ErrorAction SilentlyContinue }
    } else { $null }

    # Fall back to the client log if the cache report didn't yield a run list.
    # The client always emits "Run List is [...]" near the start of every run,
    # so this is reliable even when data-collector reporting is off.
    $cacheRunList = if ($report) { @($report.RunList | Where-Object { $_ }) } else { @() }
    $logRunList   = if ($probe.LogTail) { @(ConvertFrom-ChefClientLog -Content $probe.LogTail) } else { @() }
    $runList      = if ($cacheRunList.Count -gt 0) { $cacheRunList } else { $logRunList }
    $runListSrc   = if ($cacheRunList.Count -gt 0) { 'CacheReport' }
                    elseif ($logRunList.Count -gt 0) { 'ClientLog' }
                    else { 'None' }

    # AttributeKeys: distinguish "no cache file" from "file present but empty"
    # so the report can say "(unavailable)" instead of misleading "(none)".
    $attrKeys = if ($report) { $report.AttributeKeys } else {
        [pscustomobject]@{ default=@(); normal=@(); override=@(); automatic=@() }
    }
    $attrStatus = if (-not $probe.CachePath) { 'NoCacheFile' }
                  elseif (-not $report)     { 'CacheUnreadable' }
                  else                       { 'OK' }

    [pscustomobject]@{
        Installed            = $true
        Version              = if ($probe.Version) { ($probe.Version | Out-String).Trim() } else { $null }
        NodeName             = $rb.NodeName
        ChefServerUrl        = $rb.ChefServerUrl
        Environment          = $rb.Environment
        ValidationClient     = $rb.ValidationClient
        RunList              = $runList
        RunListSource        = $runListSrc
        ClientLogPath        = $probe.LogPath
        ClientLogStatus      = $probe.LogStatus
        AttributeKeys        = $attrKeys
        AttributeSource      = $probe.CacheSource
        AttributeStatus      = $attrStatus
        AttributeCachePath   = $probe.CachePath
        LastSuccessfulRunUtc = if ($report) { $report.LastSuccessfulRunUtc } else { $null }
    }
}
