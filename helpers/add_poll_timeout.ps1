# Adds "server-poll-timeout 10" after the last "remote" line of every *.ovpn in the current directory.
# Idempotent: files that already have the line are skipped.
$enc = New-Object System.Text.UTF8Encoding($false)   # UTF-8 without BOM
foreach ($f in Get-ChildItem -Filter *.ovpn -File) {
    $lines = [System.IO.File]::ReadAllLines($f.FullName)
    if ($lines -match '^\s*server-poll-timeout\s') { "SKIP (already has it): $($f.Name)"; continue }
    $last = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*remote\s') { $last = $i } }
    if ($last -lt 0) { "SKIP (no remote line): $($f.Name)"; continue }
    $out = $lines[0..$last] + 'server-poll-timeout 10' + $(if ($last + 1 -lt $lines.Count) { $lines[($last + 1)..($lines.Count - 1)] })
    [System.IO.File]::WriteAllLines($f.FullName, $out, $enc)
    "OK: $($f.Name)"
}
