@{
    # Known Windows Server default service names (path heuristic catches most;
    # this list ensures a clean filter even when binaries live outside %SystemRoot%).
    KnownDefaults = @(
        'AJRouter','ALG','AppHostSvc','AppIDSvc','Appinfo','AppMgmt','AppReadiness',
        'AppXSvc','AssignedAccessManagerSvc','AudioEndpointBuilder','Audiosrv',
        'autotimesvc','AxInstSV','BFE','BITS','BluetoothUserService','BrokerInfrastructure',
        'Browser','BTAGService','BthAvctpSvc','bthserv','camsvc','CaptureService',
        'cbdhsvc','CDPSvc','CDPUserSvc','CertPropSvc','ClipSVC','COMSysApp',
        'ConsentUxUserSvc','CoreMessagingRegistrar','CryptSvc','CscService','DcomLaunch',
        'defragsvc','DeviceAssociationBrokerSvc','DeviceAssociationService','DeviceInstall',
        'DevicePickerUserSvc','DevicesFlowUserSvc','DevQueryBroker','Dhcp','diagnosticshub.standardcollector.service',
        'DiagTrack','DispBrokerDesktopSvc','DisplayEnhancementService','DmEnrollmentSvc',
        'dmwappushservice','DNS','Dnscache','DoSvc','dot3svc','DPS','DsmSvc','DsRoleSvc',
        'DsSvc','DusmSvc','EapHost','EFS','embeddedmode','EntAppSvc','EventLog','EventSystem',
        'fdPHost','FDResPub','fhsvc','FontCache','FrameServer','FrameServerMonitor','FtpSrv',
        'GraphicsPerfSvc','gpsvc','hidserv','HvHost','icssvc',
        'IISADMIN','IKEEXT','InstallService','iphlpsvc','IpxlatCfgSvc','KeyIso','KPSSVC',
        'KtmRm','LanmanServer','LanmanWorkstation','lfsvc','LicenseManager','lltdsvc',
        'lmhosts','LSM','LxpSvc','MapsBroker','McpManagementService','MessagingService',
        'MicrosoftEdgeElevationService','mpssvc','MSDTC','MSiSCSI','msiserver','napagent',
        'NaturalAuthentication','NcaSvc','NcbService','NcdAutoSetup','Netlogon','Netman',
        'netprofm','NetSetupSvc','NetTcpPortSharing','NgcCtnrSvc','NgcSvc','NlaSvc',
        'nsi','OneSyncSvc','P9RdrService','PcaSvc','PeerDistSvc','PerfHost','PhoneSvc',
        'pla','PlugPlay','PolicyAgent','Power','PrintNotify','PrintWorkflowUserSvc',
        'ProfSvc','PushToInstall','QWAVE','RasAuto','RasMan','RemoteAccess','RemoteRegistry',
        'RetailDemo','RmSvc','RpcEptMapper','RpcLocator','RpcSs','RSoPProv','sacsvr',
        'SamSs','SCardSvr','ScDeviceEnum','Schedule','SCPolicySvc','SDRSVC','seclogon',
        'SecurityHealthService','SEMgrSvc','SENS','Sense','SensorDataService','SensorService',
        'SensrSvc','SessionEnv','SgrmBroker','SharedAccess','SharedRealitySvc','ShellHWDetection',
        'shpamsvc','SmsRouter','SNMPTRAP','Spooler','sppsvc','SSDPSRV','SstpSvc','StateRepository',
        'stisvc','StorSvc','svsvc','swprv','SysMain','SystemEventsBroker','TabletInputService',
        'TapiSrv','TermService','TextInputManagementService','Themes','TieringEngineService',
        'TimeBroker','TimeBrokerSvc','TokenBroker','TrkWks','TrustedInstaller','tzautoupdate',
        'UALSVC','UI0Detect','UmRdpService','UnistoreSvc','upnphost','UserDataSvc',
        'UserManager','UsoSvc','VaultSvc','vds','vmcompute','vmicguestinterface',
        'vmicheartbeat','vmickvpexchange','vmicrdv','vmicshutdown','vmictimesync',
        'vmicvmsession','vmicvss','vmms','VSS','W32Time','WaaSMedicSvc','WalletService',
        'WarpJITSvc','wbengine','WbioSrvc','Wcmsvc','wcncsvc','WdiServiceHost',
        'WdiSystemHost','WdNisSvc','WebClient','Wecsvc','WEPHOSTSVC','wercplsupport',
        'WerSvc','WiaRpc','WinDefend','WinHttpAutoProxySvc','Winmgmt','WinRM','wisvc',
        'wlidsvc','wlpasvc','WManSvc','wmiApSrv','workfolderssvc','WPDBusEnum','WMPNetworkSvc',
        'WpnService','WpnUserService','wscsvc','WSearch','wuauserv','wudfsvc','XblAuthManager',
        'XblGameSave','XboxGipSvc','XboxNetApiSvc'
    )
    # Services whose binaries live in %SystemRoot% but are NOT defaults — un-hide these.
    KnownCustomFalsePositives = @()
}
