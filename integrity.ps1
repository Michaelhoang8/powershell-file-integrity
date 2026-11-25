Import-Module (Join-Path $PSScriptRoot 'Integrity.psm1') -Force
if ($args.Count -eq 1 -and $args[0] -in '--help', '-Help') {
    'Usage: pwsh -File integrity.ps1 create|verify ROOT MANIFEST'
    'Create SHA-256 inventories or verify changed, missing and added files.'
    'Store MANIFEST outside ROOT. Links and case-colliding names are rejected.'
    'Exit: 0 success/match; 1 differences; 2 invalid input or I/O error.'
    exit 0
}
try {
    if ($args.Count -ne 3 -or $args[0] -notin 'create', 'verify') { throw 'Expected create|verify ROOT MANIFEST. Use --help.' }
    if ($args[0] -eq 'create') { $result = New-IntegrityManifest -Root $args[1] -Manifest $args[2] }
    else { $result = Test-IntegrityManifest -Root $args[1] -Manifest $args[2] }
    ConvertTo-Json -InputObject $result -Depth 6
    if ($args[0] -eq 'verify' -and -not $result.matches) { exit 1 }
    exit 0
} catch { [Console]::Error.WriteLine($_.Exception.Message); exit 2 }
