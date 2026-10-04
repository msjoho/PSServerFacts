function Get-RemoteIis {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    $result = Invoke-Command -Session $Session -ScriptBlock {
        $feature = Get-WindowsFeature Web-Server -ErrorAction SilentlyContinue
        if (-not $feature -or -not $feature.Installed) { return $null }

        $version = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\InetStp' -ErrorAction SilentlyContinue).VersionString

        $sites = @(); $pools = @(); $errors = @()
        try {
            Import-Module IISAdministration -ErrorAction Stop
            $sites = Get-IISSite | ForEach-Object {
                $site = $_
                [pscustomobject]@{
                    Name = $site.Name; Id = $site.Id; State = [string]$site.State
                    PhysicalPath = ($site.Applications | Where-Object Path -eq '/').VirtualDirectories[0].PhysicalPath
                    Bindings = @($site.Bindings | ForEach-Object {
                        [pscustomobject]@{
                            Protocol            = $_.Protocol
                            BindingInformation  = $_.BindingInformation
                            CertificateThumbprint = if ($_.CertificateHash) { ($_.CertificateHash | ForEach-Object { $_.ToString('X2') }) -join '' } else { $null }
                            CertificateStoreName  = $_.CertificateStoreName
                        }
                    })
                    Applications = @($site.Applications | ForEach-Object {
                        [pscustomobject]@{
                            Path = $_.Path
                            PhysicalPath = $_.VirtualDirectories[0].PhysicalPath
                            AppPool = $_.ApplicationPoolName
                        }
                    })
                    VirtualDirectories = @($site.Applications.VirtualDirectories | ForEach-Object {
                        [pscustomobject]@{ Path = $_.Path; PhysicalPath = $_.PhysicalPath }
                    })
                }
            }
            $pools = Get-IISAppPool | ForEach-Object {
                $pool = $_
                $idType = $pool.ProcessModel.IdentityType
                $user   = if ($idType -eq 'SpecificUser') { $pool.ProcessModel.UserName } else { $null }
                [pscustomobject]@{
                    Name=$pool.Name; State=[string]$pool.State
                    ManagedRuntimeVersion=$pool.ManagedRuntimeVersion
                    ManagedPipelineMode=[string]$pool.ManagedPipelineMode
                    IdentityType=[string]$idType; Username=$user
                }
            }
        } catch { $errors += "IISAdministration failed: $($_.Exception.Message)" }

        [pscustomobject]@{
            Installed=$true; Version=$version
            Sites=@($sites); AppPools=@($pools)
            CollectionErrors=$errors
        }
    }

    if ($null -eq $result) { return $null }
    # Strip PSRemoting noise note properties (PSComputerName, RunspaceId, PSShowComputerName)
    # without losing the object — Select-Object on a non-array works fine.
    $result | Select-Object Installed, Version, Sites, AppPools, CollectionErrors
}
