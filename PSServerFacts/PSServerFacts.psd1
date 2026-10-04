@{
    RootModule        = 'PSServerFacts.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '03c667ff-fe90-43b7-990b-2b60f2296019'
    Author            = 'Martin Joho'
    CompanyName       = 'Yendico'
    Copyright         = '(c) 2026 Martin Joho. MIT.'
    Description       = 'Point-in-time configuration facts of Windows Servers — runs from a jumphost over WinRM, produces JSON + Markdown per server plus a run-level summary with optional advisory notes.'
    PowerShellVersion = '7.0'
    # Wildcard during development so tests can call private helpers directly.
    # Tighten to @('Export-ServerFacts','ConvertTo-ServerFactsMarkdown') before publishing to PSGallery.
    FunctionsToExport = '*'
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    RequiredModules   = @()
    PrivateData = @{
        PSData = @{
            Tags         = @('Windows','Server','Inventory','Audit','WinRM','AD','SQL','Chef')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/martin-joho/PSServerFacts'
            ReleaseNotes = '0.1.0 — initial release.'
        }
    }
}
