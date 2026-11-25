# File Integrity Manifests

Create a deterministic SHA-256 inventory of a directory and compare later contents against it. Verification distinguishes added, missing and changed files, including changes that keep the same file size.

```powershell
pwsh -File ./integrity.ps1 --help
pwsh -File ./integrity.ps1 create ./fixtures ./snapshot.json
pwsh -File ./integrity.ps1 verify ./fixtures ./snapshot.json
pwsh -File ./tests/run.ps1
```

Requires PowerShell 7.2 or later on Windows or Linux. Uses .NET hashing and PowerShell JSON support, with no external modules. Store the manifest outside the scanned root: otherwise it would include its own changing contents. `create` replaces an existing manifest at the explicitly supplied path. `verify` is read-only.

Manifests contain schema version, hash algorithm and ordinally sorted records with relative paths, byte lengths and lowercase SHA-256 digests. They contain no machine-specific root path or creation timestamp. UTF-8 encoding and LF line endings make unchanged inventories reproducible. Empty directories are not represented.

Discovery includes hidden files and uses literal paths, so spaces and wildcard characters in filenames do not change what is scanned. Links/junctions are rejected instead of followed. Empty/dot/parent path components, backslashes, colons and case-insensitive path collisions are rejected to keep inventories portable. The checker validates manifest records before comparing them.

Exit codes: **0** created or matching; **1** differences; **2** malformed input, unsafe path, link or I/O error. Results are JSON; diagnostics go to standard error. Files are read through streams rather than loaded entirely into memory. File sharing is restricted while hashing where the OS supports it, and size/modification time are checked afterward.

This is a content-change detector, not a signed attestation or atomic filesystem snapshot. A hostile process can race directory traversal; run it on a quiescent tree you control. It does not capture ACLs, alternate data streams, ownership, empty directories or the provenance of a trusted baseline. Anyone able to replace the manifest can replace the expected hashes.
