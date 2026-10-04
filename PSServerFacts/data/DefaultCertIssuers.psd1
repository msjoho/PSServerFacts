@{
    # Match if the cert's Issuer string contains any of these substrings (CN/O fragments).
    # Curated list of well-known public CA + Microsoft root issuers.
    Issuers = @(
        'Microsoft Root','Microsoft Authority','Microsoft Authenticode',
        'Microsoft Time-Stamp','Microsoft Time Stamping','Microsoft Trust Network',
        'Microsoft Code Signing','Microsoft RSA','Microsoft ECC',
        'Microsoft Identity Verification Root','Microsoft Trusted Root',
        'Microsoft IT TLS','Windows Phone Root',
        'Symantec Enterprise Mobile Root for Microsoft',
        'DigiCert','GeoTrust','GlobalSign','Sectigo','Comodo','Entrust',
        "Let's Encrypt",'ISRG Root','Baltimore CyberTrust','Thawte','VeriSign',
        'USERTrust','AddTrust','QuoVadis','IdenTrust','GoDaddy','Go Daddy','Starfield',
        'Amazon','Google Trust Services','GTS Root','GTS CA','Apple Root','SwissSign',
        'Buypass','Actalis','Certum','SecureTrust','AffirmTrust','D-TRUST'
    )
}
