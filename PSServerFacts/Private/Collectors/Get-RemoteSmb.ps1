function Get-RemoteSmb {
    # Pulls Get-SmbServerConfiguration on the target. SMB1 client feature is
    # a separate read via Get-WindowsOptionalFeature (Windows 10/Server 2016+)
    # falling back to Get-WindowsFeature (older Server SKUs).
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        $cfg = $null
        try { $cfg = Get-SmbServerConfiguration -ErrorAction Stop } catch { }
        $clientFeat = $false
        try {
            $f = Get-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -ErrorAction Stop
            $clientFeat = $f.State -eq 'Enabled'
        } catch {
            try {
                $f = Get-WindowsFeature -Name 'FS-SMB1' -ErrorAction Stop
                $clientFeat = $f.Installed
            } catch { }
        }
        [pscustomobject]@{
            Smb1Enabled              = if ($cfg) { [bool]$cfg.EnableSMB1Protocol } else { $null }
            Smb2Enabled              = if ($cfg) { [bool]$cfg.EnableSMB2Protocol } else { $null }
            SigningRequired          = if ($cfg) { [bool]$cfg.RequireSecuritySignature } else { $null }
            SigningEnabled           = if ($cfg) { [bool]$cfg.EnableSecuritySignature  } else { $null }
            EncryptData              = if ($cfg) { [bool]$cfg.EncryptData              } else { $null }
            RejectUnencryptedAccess  = if ($cfg) { [bool]$cfg.RejectUnencryptedAccess  } else { $null }
            AuditSmb1Access          = if ($cfg) { [bool]$cfg.AuditSmb1Access          } else { $null }
            Smb1ClientInstalled      = $clientFeat
        }
    }
}
