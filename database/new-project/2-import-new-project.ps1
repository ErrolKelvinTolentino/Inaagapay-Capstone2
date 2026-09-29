# Step 2 — rebuild the old project inside the NEW one.
#
#   powershell -ExecutionPolicy Bypass -File .\2-import-new-project.ps1
#   powershell -ExecutionPolicy Bypass -File .\2-import-new-project.ps1 -Reset
#
# Reads .\export\old\ (from step 1) and writes only to the NEW project.
#
# Safe to run again. It looks at what the new project already has and carries
# on from there: an empty project gets everything; a project whose schema went
# in on an earlier run gets the data; a project that has both only gets the
# finishing steps again. Each load runs in a single transaction, so a failure
# leaves nothing half-written.
#
# -Reset empties the new project's public schema first, for starting over.

param([switch]$Reset)

. (Join-Path $PSScriptRoot 'common.ps1')

$settings       = Read-Settings
$oldRef         = Get-Setting $settings 'OLD_PROJECT_REF'
$newRef         = Get-Setting $settings 'NEW_PROJECT_REF'
$newUrl         = (Get-Setting $settings 'NEW_SUPABASE_URL').TrimEnd('/')
$publishableKey = Get-Setting $settings 'NEW_PUBLISHABLE_KEY'
Test-ProjectRef $oldRef 'OLD_PROJECT_REF'
Test-ProjectRef $newRef 'NEW_PROJECT_REF'
if ($newRef -eq $oldRef) { Stop-Migration 'NEW_PROJECT_REF is the same as OLD_PROJECT_REF.' }
if ($newUrl -ne "https://$newRef.supabase.co") {
    Stop-Migration "NEW_SUPABASE_URL should be https://$newRef.supabase.co (it is $newUrl)."
}
if (-not $publishableKey.StartsWith('sb_publishable_')) {
    Stop-Migration 'NEW_PUBLISHABLE_KEY should start with sb_publishable_. Copy the Publishable key from Project Settings -> API Keys.'
}
$new = ConvertFrom-PgUrl (Get-Setting $settings 'NEW_DB_URL') 'NEW project database'
if (($new.User + $new.Host) -notlike "*$newRef*") {
    Stop-Migration "NEW_DB_URL does not mention $newRef. Copy it from the NEW project's dashboard (Connect -> Session pooler)."
}

$oldDir = Join-Path $script:ExportDir 'old'
foreach ($f in @('schema.sql', 'data.sql', 'object_counts.csv', 'row_counts.csv', 'extensions.csv')) {
    if (-not (Test-Path -LiteralPath (Join-Path $oldDir $f))) {
        Stop-Migration "export\old\$f is missing. Run 1-export-old-project.ps1 first."
    }
}
$rwDir  = Join-Path $script:ExportDir 'rewritten'
$newDir = Join-Path $script:ExportDir 'new'
$logDir = Join-Path $script:ExportDir 'logs'
foreach ($d in @($rwDir, $newDir, $logDir)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
$log = Join-Path $logDir ("import-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')

Write-Step 'Checking the PostgreSQL tools'
$psql = Find-PgTool 'psql'
Write-Ok "psql $(Get-PgToolMajor $psql) at $psql"

Write-Step 'Connecting to the NEW project'
Add-Password $new
$serverMajor = [int](Get-PsqlValue $new "SELECT current_setting('server_version_num')::int / 10000")
Write-Ok "connected; the new database is PostgreSQL $serverMajor"
$oldMajor = [int](@(Import-CsvIfAny (Join-Path $oldDir 'server.csv'))[0].major)
if ($serverMajor -lt $oldMajor) {
    Stop-Migration "The new project runs PostgreSQL $serverMajor, older than the old project's $oldMajor. Create the new project on the latest version."
}

# The secret key replaces the old service_role key wherever the database kept
# it (the daily reminder job's settings). Typed, never saved.
Write-Info ''
Write-Info 'The new project''s SECRET key: Project Settings -> API Keys -> Secret keys -> "default" (reveal, copy).'
$secretKey = Read-Secret 'Secret key (starts with sb_secret_; typing is hidden)'
if (-not $secretKey.StartsWith('sb_secret_')) { Stop-Migration 'That does not look like a secret key (it should start with sb_secret_).' }

# ── Optional reset ───────────────────────────────────────────────────────────

if ($Reset) {
    Write-Step "Emptying the NEW project's public schema"
    Write-Host "    This deletes every table in project $newRef." -ForegroundColor Yellow
    $typed = Read-Host "    Type the new project ref ($newRef) to confirm"
    if ($typed -ne $newRef) { Stop-Migration 'Reset not confirmed.' }
    $code = Invoke-PsqlFile -Conn $new -Files @((Join-Path $script:SqlDir 'reset-new-project.sql')) -Log $log
    if ($code -ne 0) { Stop-Migration "The reset failed. See $log" }
    Write-Ok 'public schema emptied'
}

# ── Where are we? ────────────────────────────────────────────────────────────

$oldObjects = @{}
foreach ($r in (Import-CsvIfAny (Join-Path $oldDir 'object_counts.csv'))) { $oldObjects[$r.kind] = [int]$r.total }
$tablesNow = [int](Get-PsqlValue $new "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind IN ('r','p')")

$doSchema = $false; $doData = $false
if ($tablesNow -eq 0) {
    $doSchema = $true; $doData = $true
    Write-Ok 'the new project is empty: loading schema and data'
} elseif ($tablesNow -eq $oldObjects['tables']) {
    $rowsNow = [long](Get-PsqlValue $new @"
SELECT COALESCE(sum((xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM public.%I', c.relname), false, true, '')))[1]::text::bigint), 0)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('r','p')
"@)
    if ($rowsNow -eq 0) {
        $doData = $true
        Write-Ok 'the schema is already in from an earlier run: loading the data'
    } else {
        Write-Ok "schema and data are already in from an earlier run ($rowsNow rows): re-applying the finishing steps only"
    }
} else {
    Stop-Migration ("The new project already has $tablesNow table(s) in public, but the old one has $($oldObjects['tables']). " +
        'This is not a fresh project nor an earlier run of this script. Run again with -Reset to empty it first.')
}

# ── Rewrite the dumps for the new project ────────────────────────────────────

Write-Step 'Pointing the dumps at the new project (URL, keys)'
$schemaIn = Join-Path $oldDir 'schema.sql'
$dataIn   = Join-Path $oldDir 'data.sql'
$jwts = Get-JwtsInFiles @($schemaIn, $dataIn)
$rewrite = New-ProjectRewrite -OldRef $oldRef -NewRef $newRef -NewUrl $newUrl `
    -PublishableKey $publishableKey -SecretKey $secretKey -Jwts $jwts

# Lines that cannot run on a fresh Supabase project: the public schema exists
# already, and transaction_timeout is unknown to a server older than 17. The
# default privileges of supabase_admin (Supabase's own superuser) are ones the
# postgres login is not allowed to change on a new project ("permission denied
# to change default privileges"), and a new project already has them.
$skip = {
    param($line)
    ($line -match '^\s*CREATE SCHEMA public;\s*$') -or
    ($line -match '^\s*COMMENT ON SCHEMA public IS') -or
    ($line -match '^\s*SET transaction_timeout\s*=') -or
    ($line -match '^\s*ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin\b')
}
$schemaOut = Join-Path $rwDir 'schema.sql'
$dataOut   = Join-Path $rwDir 'data.sql'
$c1 = Copy-SqlWithRewrite $schemaIn $schemaOut $rewrite $skip
$c2 = Copy-SqlWithRewrite $dataIn   $dataOut   $rewrite $skip
foreach ($k in (@($c1.Keys) + @($c2.Keys) | Sort-Object -Unique)) {
    Write-Ok ("{0}: {1} place(s)" -f $k, ([int]$c1[$k] + [int]$c2[$k]))
}
foreach ($u in $rewrite.Unresolved) { Write-Note "not replaced: $u" }

# ── Preflight on the new project ─────────────────────────────────────────────

Write-Step 'Checking the new project can take the schema'

# Every role a GRANT or REVOKE names must exist there.
$schemaText = [IO.File]::ReadAllText($schemaOut, $script:Utf8NoBom)
$roles = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($m in [regex]::Matches($schemaText, '(?m)^(?:GRANT|REVOKE)\b[^;]*?\b(?:TO|FROM)\s+([^;]+);')) {
    foreach ($r in ($m.Groups[1].Value -split ',')) {
        $name = ($r.Trim() -replace '\s+WITH GRANT OPTION$', '' -replace '^GROUP\s+', '').Trim('"', ' ')
        if ($name -and $name -ne 'PUBLIC') { [void]$roles.Add($name) }
    }
}
if ($roles.Count) {
    $list = ($roles | ForEach-Object { ConvertTo-SqlLiteral $_ }) -join ','
    $missingRoles = Get-PsqlValue $new "SELECT string_agg(r, ', ') FROM unnest(ARRAY[$list]) r WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r)"
    if ($missingRoles) { Stop-Migration "The schema grants to role(s) the new project does not have: $missingRoles" }
}
Write-Ok "all $($roles.Count) roles named in grants exist"

if ($schemaText.Contains('supabase_functions.')) {
    $hasHooks = Get-PsqlValue $new "SELECT to_regnamespace('supabase_functions') IS NOT NULL"
    if ($hasHooks -ne 't') {
        Stop-Migration 'The old project used Database Webhooks. In the new project open Database -> Webhooks and click "Enable webhooks", then run this again.'
    }
}

# ── Extensions ───────────────────────────────────────────────────────────────

Write-Step 'Enabling the extensions the old project had'
$haveExt = @{}
foreach ($line in ((Get-PsqlValue $new "SELECT string_agg(extname, ',') FROM pg_extension") -split ',')) { if ($line) { $haveExt[$line] = $true } }
foreach ($e in (Import-CsvIfAny (Join-Path $oldDir 'extensions.csv'))) {
    if ($haveExt.ContainsKey($e.name)) { Write-Ok "$($e.name) already on"; continue }
    $tmp = Join-Path $rwDir "ext-$($e.name).sql"
    Write-Utf8 $tmp ("CREATE EXTENSION IF NOT EXISTS {0} WITH SCHEMA {1};`n" -f (ConvertTo-SqlIdent $e.name), (ConvertTo-SqlIdent $e.schema_name))
    $code = Invoke-PsqlFile -Conn $new -Files @($tmp) -Log $log
    if ($code -eq 0) { Write-Ok "$($e.name) enabled in $($e.schema_name)" }
    else { Write-Note "$($e.name) could not be enabled here; if the schema load then fails on it, enable it under Database -> Extensions" }
}

# ── Schema ───────────────────────────────────────────────────────────────────

if ($doSchema) {
    Write-Step 'Loading the schema (one transaction)'
    $code = Invoke-PsqlFile -Conn $new -Files @($schemaOut) -SingleTransaction -Log $log
    if ($code -ne 0) {
        Stop-Migration "The schema did not load, and nothing of it was kept. The first ERROR line above says why; the full output is in $log"
    }
    Write-Ok 'schema loaded'
}

# ── Data ─────────────────────────────────────────────────────────────────────
# Triggers must not fire while old rows go back in: the audit triggers would
# log every row a second time, and the notification trigger would send a push
# for every notification ever written. session_replication_role = replica
# switches every trigger off for this session, foreign-key checks included, so
# table order does not matter either.

if ($doData) {
    Write-Step 'Loading the data (one transaction, triggers off)'
    $probe = Join-Path $rwDir 'probe-replica.sql'
    Write-Utf8 $probe "SET session_replication_role = replica;`n"
    $replicaOk = (Invoke-PsqlFile -Conn $new -Files @($probe) -Log $log) -eq 0

    if ($replicaOk) {
        $code = Invoke-PsqlFile -Conn $new -Files @($dataOut) -SingleTransaction -Before @('SET session_replication_role = replica') -Log $log
    } else {
        # Fallback: switch off this project's own triggers table by table.
        # Foreign keys stay on, and pg_dump already orders the data for them.
        Write-Note 'replica mode is not allowed here; switching triggers off table by table instead'
        $tables = (Get-PsqlValue $new "SELECT string_agg(format('%I', c.relname), ',') FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind = 'r'") -split ','
        $off = Join-Path $rwDir 'triggers-off.sql'
        $on  = Join-Path $rwDir 'triggers-on.sql'
        Write-Utf8 $off ((($tables | Where-Object { $_ }) | ForEach-Object { "ALTER TABLE public.$_ DISABLE TRIGGER USER;" }) -join "`n")
        Write-Utf8 $on  ((($tables | Where-Object { $_ }) | ForEach-Object { "ALTER TABLE public.$_ ENABLE TRIGGER USER;" }) -join "`n")
        $code = Invoke-PsqlFile -Conn $new -Files @($off, $dataOut, $on) -SingleTransaction -Log $log
    }
    if ($code -ne 0) {
        Stop-Migration "The data did not load, and none of it was kept. The first ERROR line above says why; the full output is in $log"
    }
    Write-Ok 'data loaded'
}

# ── Finishing steps (safe to repeat) ─────────────────────────────────────────

Write-Step 'Restoring realtime, row level security, grants and scheduled jobs'
$postSql = New-PostImportSql -OldDir $oldDir -Rewrite $rewrite
foreach ($n in $postSql.Notes) { Write-Note $n }

$postFile = Join-Path $rwDir 'post-import.sql'
Write-Utf8 $postFile $postSql.Sql
$code = Invoke-PsqlFile -Conn $new -Files @($postFile) -Log $log
if ($code -ne 0) { Stop-Migration "The finishing steps failed. See $log (the SQL is in $postFile)." }
Write-Ok 'realtime, row level security, grants and jobs restored'

Write-Step 'Making the database''s calls to Edge Functions work with the new keys'
$code = Invoke-PsqlFile -Conn $new -Files @((Join-Path $script:SqlDir 'post-import-apikey.sql')) -Log $log
if ($code -ne 0) { Stop-Migration "Could not update the functions that call Edge Functions. See $log" }
Write-Ok 'done'

# ── Compare with the old project ─────────────────────────────────────────────
# Before the storage migration below, which changes the files table on
# purpose and would otherwise show up here as a difference.

Write-Step 'Comparing the new project with the old one'
if (Test-Path -LiteralPath $newDir) { Remove-Item -LiteralPath $newDir -Recurse -Force }
Export-Inventory $new $newDir

$problems = New-Object System.Collections.ArrayList
$report   = New-Object System.Collections.ArrayList
function Add-Report([string]$s) { [void]$report.Add($s); Write-Info $s }

# Rows, table by table.
$oldRows = @{}; foreach ($r in (Import-CsvIfAny (Join-Path $oldDir 'row_counts.csv'))) { $oldRows[$r.table_name] = [long]$r.row_count }
$newRows = @{}; foreach ($r in (Import-CsvIfAny (Join-Path $newDir 'row_counts.csv'))) { $newRows[$r.table_name] = [long]$r.row_count }
$rowMismatch = 0
foreach ($t in ($oldRows.Keys | Sort-Object)) {
    $n = $(if ($newRows.ContainsKey($t)) { $newRows[$t] } else { -1 })
    if ($n -ne $oldRows[$t]) {
        $rowMismatch++
        [void]$problems.Add("rows in $($t): old $($oldRows[$t]), new $(if ($n -lt 0) { 'table missing' } else { $n })")
    }
}
Add-Report ("Rows: {0:N0} old, {1:N0} new, {2} table(s) differ" -f (Get-TotalRows (Join-Path $oldDir 'row_counts.csv')), (Get-TotalRows (Join-Path $newDir 'row_counts.csv')), $rowMismatch)

# Objects.
$newObjects = @{}; foreach ($r in (Import-CsvIfAny (Join-Path $newDir 'object_counts.csv'))) { $newObjects[$r.kind] = [int]$r.total }
foreach ($k in ($oldObjects.Keys | Sort-Object)) {
    $line = "{0}: old {1}, new {2}" -f $k, $oldObjects[$k], $newObjects[$k]
    Add-Report $line
    if ($oldObjects[$k] -ne $newObjects[$k]) { [void]$problems.Add($line) }
}

# Row level security and grants.
function Compare-CsvRows([string]$Name, [scriptblock]$KeyExpr) {
    $a = @{}; foreach ($r in (Import-CsvIfAny (Join-Path $oldDir $Name))) { $a[(& $KeyExpr $r)] = (($r.PSObject.Properties | ForEach-Object { $_.Value }) -join '|') }
    $b = @{}; foreach ($r in (Import-CsvIfAny (Join-Path $newDir $Name))) { $b[(& $KeyExpr $r)] = (($r.PSObject.Properties | ForEach-Object { $_.Value }) -join '|') }
    $diff = @()
    foreach ($k in $a.Keys) { if ($a[$k] -ne $b[$k]) { $diff += $k } }
    return $diff
}
foreach ($d in (Compare-CsvRows 'rls.csv' { param($r) $r.table_name })) { [void]$problems.Add("row level security differs on $d") }
foreach ($d in (Compare-CsvRows 'privileges.csv' { param($r) "$($r.table_name)/$($r.role_name)" })) { [void]$problems.Add("grants differ on $d") }
foreach ($d in (Compare-CsvRows 'realtime_tables.csv' { param($r) "$($r.schema_name).$($r.table_name)" })) { [void]$problems.Add("realtime missing $d") }
foreach ($d in (Compare-CsvRows 'cron_jobs.csv' { param($r) "$($r.jobname)" })) {
    # jobid always differs; compare what matters.
    $o = @(Import-CsvIfAny (Join-Path $oldDir 'cron_jobs.csv') | Where-Object { $_.jobname -eq $d })
    $n = @(Import-CsvIfAny (Join-Path $newDir 'cron_jobs.csv') | Where-Object { $_.jobname -eq $d })
    if (-not $n.Count) { [void]$problems.Add("scheduled job '$d' is missing") }
    elseif ($o[0].schedule -ne $n[0].schedule -or $o[0].active -ne $n[0].active) { [void]$problems.Add("scheduled job '$d' differs") }
}
$jobsNew = @(Import-CsvIfAny (Join-Path $newDir 'cron_jobs.csv'))
Add-Report ("Scheduled jobs: " + $(if ($jobsNew.Count) { (($jobsNew | ForEach-Object { "$($_.jobname) [$($_.schedule)]" }) -join ', ') } else { 'none' }))

# Anything still pointing at the old project, or calling out without apikey.
foreach ($h in (Import-CsvIfAny (Join-Path $newDir 'http_functions.csv'))) {
    if ($h.project_refs -match $oldRef) { [void]$problems.Add("$($h.function_name)() still names the old project") }
    foreach ($ref in ($h.project_refs -split ' ' | Where-Object { $_ -and $_ -ne $newRef -and $_ -ne $oldRef })) {
        Write-Note "$($h.function_name)() calls another Supabase project ($ref), exactly as it did before the move."
    }
    if ($h.calls_pg_net -eq 't' -and $h.sends_apikey -ne 't') {
        [void]$problems.Add("$($h.function_name)() calls an Edge Function without an apikey header")
    }
}

# What the daily reminder job will use, keys masked.
if ((Get-PsqlValue $new "SELECT to_regclass('public.job_settings') IS NOT NULL") -eq 't') {
    $js = Get-PsqlValue $new "SELECT string_agg(key || ' = ' || CASE WHEN key ILIKE '%key%' THEN left(value, 14) || '...' ELSE value END, '; ' ORDER BY key) FROM public.job_settings"
    Add-Report "job_settings: $js"
    if ($js -match 'REPLACE-ME') { Write-Note 'job_settings still holds placeholders, as it did on the old project: the daily reminder job sends nothing until they are filled in (README, "Daily reminders").' }
}

# Migrations: nothing that was applied on the old project may be missing here.
# Except the storage migration, which is applied right below this comparison.
$oldState = @{}; foreach ($r in (Import-CsvIfAny (Join-Path $oldDir 'migration_state.csv'))) { $oldState[$r.migration] = $r.status }
foreach ($r in (Import-CsvIfAny (Join-Path $newDir 'migration_state.csv'))) {
    if ($r.migration -eq '20260929_profile_photo_storage.sql') { continue }
    if ($oldState[$r.migration] -eq 'OK' -and $r.status -ne 'OK') {
        [void]$problems.Add("migration $($r.migration) was complete on the old project but not here: $($r.what_is_missing)")
    }
}

# ── Profile photo storage ────────────────────────────────────────────────────
# Migration 20260929: the public "files" bucket, its policies, and the files
# table opened to the app. Never ran on the old project, so it is the one
# deliberate difference from it.

Write-Step 'Profile photo storage (migration 20260929)'
$storageMigration = Join-Path $script:RepoRoot 'database\migrations\20260929_profile_photo_storage.sql'
if (Test-Path -LiteralPath $storageMigration) {
    $code = Invoke-PsqlFile -Conn $new -Files @($storageMigration) -Log $log
    if ($code -ne 0) { [void]$problems.Add("the storage migration 20260929 did not apply (see $log); run that file in the SQL Editor") }
    else { Write-Ok 'public "files" bucket and its policies are in place' }
} else {
    Write-Note 'database\migrations\20260929_profile_photo_storage.sql not found; skipped'
}

# The REST API, the way the app and the portal will reach it.
Write-Step 'Calling the new project''s API with the publishable key'
try {
    $resp = Invoke-WebRequest -UseBasicParsing -Method Get `
        -Uri "$newUrl/rest/v1/accounts?select=account_id&limit=1" `
        -Headers @{ apikey = $publishableKey; Authorization = "Bearer $publishableKey"; Prefer = 'count=exact' }
    $range = [string]$resp.Headers['Content-Range']
    Write-Ok "REST answered $($resp.StatusCode); accounts: $range"
    if ($range -match '/(\d+)$' -and $oldRows.ContainsKey('accounts') -and [long]$Matches[1] -ne $oldRows['accounts']) {
        [void]$problems.Add("the API sees $($Matches[1]) accounts but the database has $($oldRows['accounts']): check grants and row level security on accounts")
    }
} catch {
    [void]$problems.Add("the REST API call failed: $($_.Exception.Message)")
}

# ── Result ───────────────────────────────────────────────────────────────────

$reportFile = Join-Path $script:ExportDir 'IMPORT-REPORT.txt'
$body = ($report -join "`r`n") + "`r`n"
if ($problems.Count) { $body += "`r`nDIFFERENCES:`r`n" + (($problems | ForEach-Object { "  - $_" }) -join "`r`n") + "`r`n" }
Write-Utf8 $reportFile $body

Write-Host ''
if ($problems.Count) {
    Write-Host "Import finished with $($problems.Count) difference(s) from the old project:" -ForegroundColor Yellow
    foreach ($p in $problems) { Write-Host "  - $p" -ForegroundColor Yellow }
    Write-Info "Report: $reportFile. Log: $log"
} else {
    Write-Host 'Import complete: the new project matches the old one table for table.' -ForegroundColor Green
    Write-Info "Report: $reportFile"
}
Write-Info 'Next: 3-edge-functions.ps1 (README step 4).'
