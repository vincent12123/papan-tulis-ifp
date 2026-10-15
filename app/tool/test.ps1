# Runs `flutter test` per file. On this Windows machine flutter_tester 3.47
# sometimes crashes with an access violation (exit 0xC0000005) even for
# trivial tests; such a crash is retried up to 6 times. A real test failure
# is never retried and fails the run.
param([string[]]$Files)

$ErrorActionPreference = 'Continue'
if (-not $Files) { $Files = Get-ChildItem -Path test -Filter *_test.dart -Recurse | ForEach-Object { $_.FullName } }
$failed = @()
foreach ($file in $Files) {
  for ($attempt = 1; $attempt -le 6; $attempt++) {
    $out = & flutter test $file 2>&1 | Out-String
    $crashed = ($out -match 'did not complete|Connection closed before test suite loaded') -and
      ($out -notmatch 'Expected:|EXCEPTION CAUGHT')
    if (-not $crashed) { break }
    Write-Host "flutter_tester crash di $file (percobaan $attempt), diulang..."
  }
  $last = ($out.Trim() -split "`r?`n")[-1]
  Write-Host "$([IO.Path]::GetFileName($file)): $last"
  if ($last -notmatch 'All tests passed') { $failed += $file; Write-Host $out }
}
if ($failed.Count -gt 0) { Write-Host "GAGAL: $($failed -join ', ')"; exit 1 }
Write-Host 'Semua test lolos.'
