# Runs a command outside the GitHub Actions runner's job object and returns
# its exit code.
#
# Every step on the Windows runner runs inside a job that does not allow
# breakaway, so the daemon's `launch` (CREATE_BREAKAWAY_FROM_JOB) fails there.
# A process created through WMI is in no job (spike 1.3,
# docs/spikes/m1-process-model.md). WMI does not pass on the step's
# environment, so this script saves it and the inner script restores it.
#
# Usage: pwsh tool/ci/outside-job.ps1 -Run '<PowerShell command>' [-TimeoutMinutes 40]
param(
    [Parameter(Mandatory)][string]$Run,
    [int]$TimeoutMinutes = 40
)
$ErrorActionPreference = 'Stop'

$work = Join-Path ([IO.Path]::GetTempPath()) "outside-job-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory $work | Out-Null
$envFile = Join-Path $work 'env.json'
$cmdFile = Join-Path $work 'command.json'
$outFile = Join-Path $work 'out.log'
$exitFile = Join-Path $work 'exit.txt'
$inner = Join-Path $work 'inner.ps1'

$vars = @{}
Get-ChildItem env: | ForEach-Object { $vars[$_.Name] = $_.Value }
$vars | ConvertTo-Json | Set-Content -Encoding utf8 $envFile
@{ cwd = (Get-Location).Path; run = $Run } | ConvertTo-Json | Set-Content -Encoding utf8 $cmdFile

@'
param($Work)
$vars = Get-Content -Raw (Join-Path $Work 'env.json') | ConvertFrom-Json
foreach ($p in $vars.PSObject.Properties) { [Environment]::SetEnvironmentVariable($p.Name, $p.Value) }
$c = Get-Content -Raw (Join-Path $Work 'command.json') | ConvertFrom-Json
Set-Location $c.cwd
$code = 1
try {
    $global:LASTEXITCODE = 0
    Invoke-Expression $c.run *>&1 | ForEach-Object { "$_" | Out-File -Append -Encoding utf8 (Join-Path $Work 'out.log') }
    $code = $LASTEXITCODE
} catch {
    "$_" | Out-File -Append -Encoding utf8 (Join-Path $Work 'out.log')
}
# Publish the status atomically: the parent treats the file's existence as
# completion, so it must never see it empty.
$tmp = Join-Path $Work 'exit.tmp'
Set-Content $tmp "$code"
Move-Item $tmp (Join-Path $Work 'exit.txt')
'@ | Set-Content -Encoding utf8 $inner

$pwsh = (Get-Process -Id $PID).Path
$created = Invoke-CimMethod Win32_Process -MethodName Create -Arguments @{
    CommandLine      = "`"$pwsh`" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$inner`" -Work `"$work`""
    CurrentDirectory = (Get-Location).Path
}
if ($created.ReturnValue -ne 0) { throw "Win32_Process.Create failed: $($created.ReturnValue)" }
Write-Host "outside-job: pid $($created.ProcessId): $Run"

# Stream the output while the command runs.
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$shown = 0
while ($true) {
    $done = Test-Path $exitFile
    if (Test-Path $outFile) {
        $lines = @(Get-Content $outFile)
        if ($lines.Length -gt $shown) {
            $lines[$shown..($lines.Length - 1)] | ForEach-Object { Write-Host $_ }
            $shown = $lines.Length
        }
    }
    if ($done) { break }
    if ((Get-Date) -gt $deadline) {
        Write-Host "outside-job: timed out after $TimeoutMinutes minutes"
        taskkill /PID $created.ProcessId /T /F | Out-Null
        exit 124
    }
    Start-Sleep -Milliseconds 500
}
$status = (Get-Content -Raw $exitFile)
$code = 0
if ($null -eq $status -or -not [int]::TryParse($status.Trim(), [ref]$code)) {
    Write-Host "outside-job: invalid exit status '$status'"
    exit 125
}
Write-Host "outside-job: exit $code"
exit $code
