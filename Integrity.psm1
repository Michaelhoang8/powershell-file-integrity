Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RootPath([string]$Root) {
    $item = Get-Item -LiteralPath $Root -Force
    if (-not $item.PSIsContainer) { throw 'Root must be a directory.' }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Root may not be a symbolic link or junction.' }
    return [IO.Path]::TrimEndingDirectorySeparator($item.FullName)
}

function Assert-PortablePath([string]$Path) {
    if ([string]::IsNullOrEmpty($Path) -or $Path.StartsWith('/') -or $Path.Contains('\') -or $Path.Contains(':')) { throw 'Manifest paths must be relative slash-separated paths.' }
    if (@($Path.Split('/') | Where-Object { $_ -in '', '.', '..' }).Count) { throw 'Empty, dot and parent path components are forbidden.' }
}

function Get-IntegrityRecords([string]$Root) {
    $rootPath = Get-RootPath $Root
    $stack = [Collections.Generic.Stack[string]]::new()
    $stack.Push($rootPath)
    $paths = [Collections.Generic.List[string]]::new()
    $unique = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while ($stack.Count) {
        $directory = $stack.Pop()
        foreach ($item in Get-ChildItem -LiteralPath $directory -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Links are not followed: $($item.FullName)" }
            if ($item.PSIsContainer) { $stack.Push($item.FullName); continue }
            $relative = [IO.Path]::GetRelativePath($rootPath, $item.FullName).Replace([IO.Path]::DirectorySeparatorChar, '/')
            Assert-PortablePath $relative
            if (-not $unique.Add($relative)) { throw "Case-insensitive path collision: $relative" }
            $paths.Add($relative)
        }
    }
    $paths.Sort([StringComparer]::Ordinal)
    foreach ($relative in $paths) {
        $full = Join-Path $rootPath $relative
        $before = Get-Item -LiteralPath $full -Force
        $stream = [IO.File]::Open($full, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            $length = $stream.Length
            $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant()
        } finally { $stream.Dispose() }
        $after = Get-Item -LiteralPath $full -Force
        if ($before.LastWriteTimeUtc -ne $after.LastWriteTimeUtc -or $length -ne $after.Length) { throw "File changed while hashing: $relative" }
        [ordered]@{ path = $relative; bytes = $length; sha256 = $hash }
    }
}

function Assert-ExternalManifest([string]$Root, [string]$Manifest) {
    $rootPath = Get-RootPath $Root
    $manifestPath = [IO.Path]::GetFullPath($Manifest)
    $prefix = $rootPath + [IO.Path]::DirectorySeparatorChar
    if ($manifestPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Store the manifest outside the scanned root to avoid self-inclusion.' }
    return $manifestPath
}

function New-IntegrityManifest {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Manifest)
    $destination = Assert-ExternalManifest $Root $Manifest
    $records = @(Get-IntegrityRecords $Root)
    $document = [ordered]@{ schemaVersion = 1; algorithm = 'SHA-256'; files = $records }
    $json = ConvertTo-Json -InputObject $document -Depth 6
    [IO.File]::WriteAllText($destination, $json.Replace("`r`n", "`n") + "`n", [Text.UTF8Encoding]::new($false))
    return [ordered]@{ files = $records.Count; manifest = $destination }
}

function Test-IntegrityManifest {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Manifest)
    $source = Assert-ExternalManifest $Root $Manifest
    $document = Get-Content -LiteralPath $source -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    if ($null -eq $document -or $document.schemaVersion -ne 1 -or $document.algorithm -ne 'SHA-256' -or $document.files -isnot [array]) { throw 'Unsupported manifest schema.' }
    $expected = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $unique = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $document.files) {
        if ($entry -isnot [Collections.IDictionary] -or $entry.path -isnot [string] -or $entry.sha256 -isnot [string] -or $entry.sha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Malformed manifest entry.' }
        Assert-PortablePath $entry.path
        if (($entry.bytes -isnot [long] -and $entry.bytes -isnot [int]) -or $entry.bytes -lt 0) { throw 'File size must be a nonnegative integer.' }
        if (-not $unique.Add($entry.path)) { throw "Duplicate or case-colliding manifest path: $($entry.path)" }
        $expected.Add($entry.path, $entry)
    }
    $actual = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($entry in @(Get-IntegrityRecords $Root)) { $actual.Add($entry.path, $entry) }
    $missing = @($expected.Keys | Where-Object { -not $actual.ContainsKey($_) })
    $added = @($actual.Keys | Where-Object { -not $expected.ContainsKey($_) })
    $changed = @($expected.Keys | Where-Object { $actual.ContainsKey($_) -and ($actual[$_].sha256 -cne $expected[$_].sha256 -or $actual[$_].bytes -ne $expected[$_].bytes) })
    [Array]::Sort($missing, [StringComparer]::Ordinal)
    [Array]::Sort($added, [StringComparer]::Ordinal)
    [Array]::Sort($changed, [StringComparer]::Ordinal)
    return [ordered]@{ matches = ($missing.Count + $added.Count + $changed.Count -eq 0); checked = $actual.Count; missing = $missing; added = $added; changed = $changed }
}

Export-ModuleMember -Function New-IntegrityManifest, Test-IntegrityManifest
