$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../Integrity.psm1') -Force
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$temporary = Join-Path $project ('.test-work-' + [guid]::NewGuid())
$root = Join-Path $temporary 'files'
$manifest = Join-Path $temporary 'manifest.json'
$second = Join-Path $temporary 'second.json'
$checks = 0
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message }; $script:checks++ }
function Throws([scriptblock]$Action, [string]$Message) { $failed = $false; try { & $Action | Out-Null } catch { $failed = $true }; Assert $failed $Message }
function Write-Text($Path, $Text) { [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false)) }
try {
    New-Item -ItemType Directory -Path $root | Out-Null
    New-IntegrityManifest $root $manifest | Out-Null
    Assert ((Test-IntegrityManifest $root $manifest).matches) 'empty directories should match'
    New-Item -ItemType Directory -Path (Join-Path $root 'nested space') | Out-Null
    Write-Text (Join-Path $root 'nested space/[file].txt') 'alpha'
    Write-Text (Join-Path $root '.hidden') ''
    New-IntegrityManifest $root $manifest | Out-Null
    New-IntegrityManifest $root $second | Out-Null
    Assert ((Get-Content -LiteralPath $manifest -Raw) -ceq (Get-Content -LiteralPath $second -Raw)) 'manifest must be deterministic'
    $saved = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    Assert ($saved.files.Count -eq 2) 'hidden and bracketed files must be included'
    Assert ($saved.files[0].sha256 -eq 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') 'empty file hash differs from known SHA-256'
    Assert ((Test-IntegrityManifest $root $manifest).matches) 'unchanged tree should match'
    Write-Text (Join-Path $root 'nested space/[file].txt') 'bravo'
    $result = Test-IntegrityManifest $root $manifest
    Assert ($result.changed.Count -eq 1 -and $result.changed[0] -ceq 'nested space/[file].txt') 'same-length changes must be detected'
    Remove-Item -LiteralPath (Join-Path $root '.hidden') -Force
    Write-Text (Join-Path $root 'extra') 'new'
    $result = Test-IntegrityManifest $root $manifest
    Assert ($result.missing.Count -eq 1 -and $result.added.Count -eq 1) 'missing and added paths must be distinct'
    Throws { New-IntegrityManifest $root (Join-Path $root 'self.json') } 'self-inclusion should fail'
    $saved.files[0].path = '../escape'
    $saved | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $second
    Throws { Test-IntegrityManifest $root $second } 'parent traversal should fail'
    $saved.files[0].path = $saved.files[1].path.ToUpperInvariant()
    $saved | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $second
    Throws { Test-IntegrityManifest $root $second } 'case-colliding entries should fail'
    $saved.files[0].path = 'valid'; $saved.files[0].sha256 = 'not-a-hash'
    $saved | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $second
    Throws { Test-IntegrityManifest $root $second } 'malformed hashes should fail'
    $link = Join-Path $root 'link'
    try { New-Item -ItemType SymbolicLink -Path $link -Target (Join-Path $root 'extra') -ErrorAction Stop | Out-Null; $linked = $true } catch { $linked = $false; 'SKIP: symbolic-link creation unavailable on this host' }
    if ($linked) { Throws { New-IntegrityManifest $root $second } 'links must not be followed' }
    "PASS: $checks integrity assertions"
} finally {
    $resolved = [IO.Path]::GetFullPath($temporary)
    if (-not $resolved.StartsWith($project + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
