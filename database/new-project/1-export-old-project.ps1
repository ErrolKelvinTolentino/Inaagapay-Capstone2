# Step 1 — copy everything out of the OLD project.
#
#   powershell -ExecutionPolicy Bypass -File .\1-export-old-project.ps1
#
# Read only against the old project: it runs pg_dump and SELECTs, nothing else.
# Writes to .\export\old\ (gitignored). Safe to run again; a previous export is
# kept alongside, renamed with a timestamp.

. (Join-Path $PSScriptRoot 'common.ps1')

$settings = Read-Settings
$oldRef   = Get-Setting $settings 'OLD_PROJECT_REF'
Test-ProjectRef $oldRef 'OLD_PROJECT_REF'
$old      = ConvertFrom-PgUrl (Get-Setting $settings 'OLD_DB_URL') 'OLD project database'
if (($old.User + $old.Host) -notlike "*$oldRef*") {
    Stop-Migration "OLD_DB_URL does not mention $oldRef. Copy it from the OLD project's dashboard (Connect -> Session pooler)."
}

Write-Step 'Checking the PostgreSQL tools'
$pgDump = Find-PgTool 'pg_dump'
$psql   = Find-PgTool 'psql'
$dumpMajor = Get-PgToolMajor $pgDump
Write-Ok "pg_dump $dumpMajor at $pgDump"

Write-Step 'Connecting to the OLD project'
Add-Password $old
$serverMajor = [int](Get-PsqlValue $old "SELECT current_setting('server_version_num')::int / 10000")
Write-Ok "connected; the old database is PostgreSQL $serverMajor"
if ($dumpMajor -lt $serverMajor) {
    Stop-Migration "pg_dump $dumpMajor cannot dump a PostgreSQL $serverMajor database. Install the PostgreSQL $serverMajor command line tools."
}

# A fresh folder; an earlier export is kept, not overwritten.
$outDir = Join-Path $script:ExportDir 'old'
if (Test-Path -LiteralPath $outDir) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    Rename-Item -LiteralPath $outDir -NewName "old-$stamp"
    Write-Note "kept the previous export as export\old-$stamp"
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$logDir = Join-Path $script:ExportDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir ("export-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')

# ── The dumps ────────────────────────────────────────────────────────────────
# Only the public schema: that is all of this project. auth, storage,
# realtime and the rest are Supabase's own and come with the new project.
# --no-owner because objects are recreated by whoever runs the import.
# Privileges ARE kept: the app reaches every table through the anon role, and
# those grants are the whole of its access.

Write-Step 'Dumping the schema (tables, functions, triggers, policies, grants)'
$schemaFile = Join-Path $outDir 'schema.sql'
$code = Invoke-PgTool -Conn $old -Exe $pgDump -Log $log -Arguments @(
    '--schema-only', '--schema=public', '--no-owner', '--no-tablespaces',
    '--no-publications', '--no-subscriptions', '--file', $schemaFile)
if ($code -ne 0) { Stop-Migration "pg_dump of the schema failed. See $log" }
Write-Ok ("schema.sql, {0:N0} KB" -f ((Get-Item $schemaFile).Length / 1KB))

Write-Step 'Dumping the data (every row of every table)'
$dataFile = Join-Path $outDir 'data.sql'
$code = Invoke-PgTool -Conn $old -Exe $pgDump -Log $log -Arguments @(
    '--data-only', '--schema=public', '--no-owner', '--no-tablespaces',
    '--no-publications', '--no-subscriptions', '--file', $dataFile)
if ($code -ne 0) { Stop-Migration "pg_dump of the data failed. See $log" }
Write-Ok ("data.sql, {0:N1} MB" -f ((Get-Item $dataFile).Length / 1MB))

# ── What else the project has ────────────────────────────────────────────────

Write-Step 'Recording what the old project has (extensions, jobs, realtime, security)'
Export-Inventory $old $outDir
Write-Ok 'inventory written'

# ── Report ───────────────────────────────────────────────────────────────────

$summary = New-Object System.Collections.ArrayList
function Add-Line([string]$s) { [void]$summary.Add($s); Write-Info $s }

Write-Step 'Summary'
$objects = @(Import-CsvIfAny (Join-Path $outDir 'object_counts.csv'))
Add-Line (("PostgreSQL {0}; " -f $serverMajor) + (($objects | ForEach-Object { "$($_.total) $($_.kind)" }) -join ', '))
Add-Line ("{0:N0} rows across all tables" -f (Get-TotalRows (Join-Path $outDir 'row_counts.csv')))

$ext = @(Import-CsvIfAny (Join-Path $outDir 'extensions.csv'))
Add-Line ('Extensions: ' + (($ext | ForEach-Object { "$($_.name) ($($_.schema_name))" }) -join ', '))

$cron = @(Import-CsvIfAny (Join-Path $outDir 'cron_jobs.csv'))
if ($cron.Count) {
    Add-Line 'Scheduled jobs:'
    foreach ($j in $cron) { Add-Line ("  {0}  [{1}]  active={2}" -f $j.jobname, $j.schedule, $j.active) }
} else { Add-Line 'Scheduled jobs: none' }

$rt = @(Import-CsvIfAny (Join-Path $outDir 'realtime_tables.csv'))
Add-Line ('Realtime tables: ' + $(if ($rt.Count) { (($rt | ForEach-Object { $_.table_name }) -join ', ') } else { 'none' }))

$rlsOn = @(Import-CsvIfAny (Join-Path $outDir 'rls.csv') | Where-Object { $_.rls_enabled -eq 't' })
Add-Line ('Tables with row level security on: ' + $(if ($rlsOn.Count) { (($rlsOn | ForEach-Object { $_.table_name }) -join ', ') } else { 'none' }))

$warnings = New-Object System.Collections.ArrayList

$buckets = @(Import-CsvIfAny (Join-Path $outDir 'storage_buckets.csv'))
foreach ($b in $buckets) {
    if ([long]$b.objects -gt 0) {
        [void]$warnings.Add("Storage bucket '$($b.bucket)' holds $($b.objects) file(s). These scripts copy the database, not Storage files - download them from the old dashboard (Storage) before it shuts down.")
    }
}
$vault = @(Import-CsvIfAny (Join-Path $outDir 'vault_secret_names.csv'))
if ($vault.Count) {
    [void]$warnings.Add("Vault holds $($vault.Count) secret(s): " + (($vault | ForEach-Object { $_.name }) -join ', ') + ". Values cannot be exported; re-create them in the new project's Vault by hand.")
}
$ext2 = @(Import-CsvIfAny (Join-Path $outDir 'external_triggers.csv'))
foreach ($t in $ext2) {
    if ($t.calls -like 'supabase_functions.*') {
        [void]$warnings.Add("Table $($t.table_name) has a Database Webhook ($($t.trigger_name)). Enable Database Webhooks on the new project before importing.")
    }
}
$http = @(Import-CsvIfAny (Join-Path $outDir 'http_functions.csv'))
foreach ($h in $http) {
    foreach ($ref in ($h.project_refs -split ' ' | Where-Object { $_ })) {
        if ($ref -ne $oldRef) {
            [void]$warnings.Add("Function $($h.function_name)() calls a DIFFERENT Supabase project ($ref). It is copied exactly as it is; whatever it does today, it will keep doing.")
        }
    }
}

$jwts = Get-JwtsInFiles @($schemaFile, $dataFile)
foreach ($jwt in $jwts) {
    $c = Get-JwtClaims $jwt
    if ($null -ne $c) {
        $where = $(if ($c.Ref -eq $oldRef) { 'this project' } else { "project $($c.Ref)" })
        Add-Line ("Key inside the dump: role '{0}' for {1} - the import replaces this project's keys automatically" -f $c.Role, $where)
    }
}

$state = @(Import-CsvIfAny (Join-Path $outDir 'migration_state.csv'))
$missing = @($state | Where-Object { $_.status -eq 'MISSING' })
if ($state.Count) {
    Add-Line ("Repo migrations: {0} of {1} fully applied on the old project" -f ($state.Count - $missing.Count), $state.Count)
    foreach ($m in $missing) { Add-Line ("  not applied: {0}" -f $m.migration) }
}

if ($warnings.Count) {
    Write-Host ''
    foreach ($w in $warnings) { Write-Note $w; [void]$summary.Add("NOTE: $w") }
}

Write-Utf8 (Join-Path $outDir 'SUMMARY.txt') (($summary -join "`r`n") + "`r`n")

Write-Host ''
Write-Host 'Export complete.' -ForegroundColor Green
Write-Info "Files: $outDir"
Write-Info 'They contain every patient record. Keep them on this computer; do not commit, upload or share them.'
Write-Info 'Next: create the new project (README step 2), then run 2-import-new-project.ps1.'
