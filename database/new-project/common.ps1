# Shared helpers for the new-project scripts. Dot-sourced by them; not run on
# its own. Written for Windows PowerShell 5.1, which is what a stock Windows
# machine runs, so no PowerShell 7 syntax.

$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 may still default to TLS 1.0 for web requests.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$script:NewProjectDir = $PSScriptRoot
$script:RepoRoot      = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:ExportDir     = Join-Path $PSScriptRoot 'export'
$script:SqlDir        = Join-Path $PSScriptRoot 'sql'
$script:Utf8NoBom     = New-Object System.Text.UTF8Encoding($false)
$script:JwtRegex      = [regex]'eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'

# ── Output ───────────────────────────────────────────────────────────────────

function Write-Step([string]$Text) {
    Write-Host ''
    Write-Host "==> $Text" -ForegroundColor Cyan
}
function Write-Ok([string]$Text)   { Write-Host "    ok   $Text" -ForegroundColor Green }
function Write-Note([string]$Text) { Write-Host "    note $Text" -ForegroundColor Yellow }
function Write-Info([string]$Text) { Write-Host "         $Text" }

function Stop-Migration([string]$Text) {
    Write-Host ''
    Write-Host "STOPPED: $Text" -ForegroundColor Red
    Write-Host 'Nothing after this point was run. Fix the above and run the same script again.' -ForegroundColor Red
    exit 1
}

# ── Settings ─────────────────────────────────────────────────────────────────

function Read-Settings {
    $path = Join-Path $script:NewProjectDir 'settings.env'
    if (-not (Test-Path -LiteralPath $path)) {
        Stop-Migration "settings.env not found in $script:NewProjectDir. Copy settings.example.env to settings.env and fill it in."
    }
    $settings = @{}
    foreach ($line in [IO.File]::ReadAllLines($path, $script:Utf8NoBom)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        $key = $t.Substring(0, $i).Trim()
        $val = $t.Substring($i + 1).Trim()
        if ($val.Length -ge 2 -and (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'")))) {
            $val = $val.Substring(1, $val.Length - 2)
        }
        $settings[$key] = $val
    }
    return $settings
}

function Get-Setting($Settings, [string]$Name) {
    if (-not $Settings.ContainsKey($Name)) {
        Stop-Migration "$Name is missing from settings.env. See settings.example.env."
    }
    $v = [string]$Settings[$Name]
    if ([string]::IsNullOrWhiteSpace($v) -or $v -match 'REPLACE') {
        Stop-Migration "$Name in settings.env still has a placeholder. See settings.example.env for where to find it."
    }
    return $v
}

function Test-ProjectRef([string]$Ref, [string]$Name) {
    if ($Ref -notmatch '^[a-z0-9]{20}$') {
        Stop-Migration "$Name '$Ref' does not look like a Supabase project ref (20 lowercase letters and digits)."
    }
}

# ── Secrets typed at the prompt ──────────────────────────────────────────────

function Read-Secret([string]$Prompt) {
    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# ── PostgreSQL tools ─────────────────────────────────────────────────────────

function Find-PgTool([string]$Name) {
    $cmd = Get-Command "$Name.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $roots = @('C:\Program Files\PostgreSQL', 'C:\Program Files (x86)\PostgreSQL')
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $dirs = Get-ChildItem -LiteralPath $root -Directory |
            Sort-Object { [int]('0' + ($_.Name -replace '[^0-9].*$', '')) } -Descending
        foreach ($d in $dirs) {
            $p = Join-Path $d.FullName "bin\$Name.exe"
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    Stop-Migration "$Name.exe was not found. Install the PostgreSQL 17 command line tools first (README, step 0)."
}

function Get-PgToolMajor([string]$Exe) {
    $out = (& $Exe --version) | Out-String
    if ($out -match '\)\s*(\d+)') { return [int]$Matches[1] }
    if ($out -match '(\d+)\.\d+') { return [int]$Matches[1] }
    return 0
}

# postgresql://USER[:PASSWORD]@HOST[:PORT]/DATABASE[?...]
function ConvertFrom-PgUrl([string]$Url, [string]$Label) {
    $m = [regex]::Match($Url, '^postgres(?:ql)?://([^:@/]+)(?::([^@]*))?@([^:/?]+)(?::(\d+))?/([^?]+)')
    if (-not $m.Success) {
        Stop-Migration "$Label is not a postgresql:// connection string. Copy it from the dashboard: Connect -> Session pooler."
    }
    $conn = @{
        User     = $m.Groups[1].Value
        Host     = $m.Groups[3].Value
        Port     = $(if ($m.Groups[4].Success) { $m.Groups[4].Value } else { '5432' })
        Database = $m.Groups[5].Value
        Password = $null
        Label    = $Label
    }
    $inline = $m.Groups[2].Value
    if ($inline -and $inline -notmatch '^\[.*\]$') {
        $conn.Password = [Uri]::UnescapeDataString($inline)
    }
    if ($conn.Port -eq '6543') {
        Stop-Migration "$Label uses port 6543, the Transaction pooler. pg_dump needs a session: use Connect -> Session pooler (port 5432)."
    }
    if ($conn.Host -like 'db.*.supabase.co') {
        Write-Note "$Label is the Direct connection, which is IPv6-only on the free plan. If the connection times out, use Connect -> Session pooler instead."
    }
    return $conn
}

function Add-Password($Conn) {
    if (-not $Conn.Password) {
        $Conn.Password = Read-Secret "Database password for the $($Conn.Label) (typing is hidden)"
    }
    if ([string]::IsNullOrEmpty($Conn.Password)) { Stop-Migration "No password given for the $($Conn.Label)." }
}

# Runs a native PostgreSQL tool against one database. The connection travels in
# PG* environment variables for this process only, so the password is never on
# a command line and never on disk. Output goes to the screen and to $Log.
function Invoke-PgTool {
    param(
        [Parameter(Mandatory = $true)] $Conn,
        [Parameter(Mandatory = $true)] [string]$Exe,
        [Parameter(Mandatory = $true)] [string[]]$Arguments,
        [string]$Log
    )
    $vars = @{
        PGHOST = $Conn.Host; PGPORT = $Conn.Port; PGUSER = $Conn.User; PGDATABASE = $Conn.Database
        PGPASSWORD = $Conn.Password; PGSSLMODE = 'require'; PGCLIENTENCODING = 'UTF8'
        PGCONNECT_TIMEOUT = '30'; PGAPPNAME = 'inaagapay-new-project'
    }
    $saved = @{}
    foreach ($k in $vars.Keys) {
        $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process')
        [Environment]::SetEnvironmentVariable($k, $vars[$k], 'Process')
    }
    # PowerShell 5.1 turns a native tool's stderr into error records, and with
    # 'Stop' in force the first NOTICE psql prints would abort the script.
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($Log) {
            & $Exe @Arguments 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $Log -Append | Out-Host
        } else {
            & $Exe @Arguments 2>&1 | ForEach-Object { "$_" } | Out-Host
        }
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $eap
        foreach ($k in $vars.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') }
    }
}

# One psql run of one or more files. SQL always goes through a file: Windows
# PowerShell mangles double quotes inside arguments to native programs.
function Invoke-PsqlFile {
    param($Conn, [string[]]$Files, [switch]$SingleTransaction, [string[]]$Before, [string]$Log)
    $psql = Find-PgTool 'psql'
    # -q: no "GRANT" / "CREATE TABLE" line for each of thousands of statements.
    # Errors, warnings and notices still print, and success is the exit code.
    $psqlArgs = @('-X', '-q', '-v', 'ON_ERROR_STOP=1')
    if ($SingleTransaction) { $psqlArgs += '--single-transaction' }
    foreach ($c in $Before) { $psqlArgs += @('-c', $c) }
    foreach ($f in $Files) { $psqlArgs += @('-f', $f) }
    return (Invoke-PgTool -Conn $Conn -Exe $psql -Arguments $psqlArgs -Log $Log)
}

# Runs a query file and writes its result as CSV.
function Export-PsqlCsv($Conn, [string]$SqlFile, [string]$OutFile) {
    $psql = Find-PgTool 'psql'
    $code = Invoke-PgTool -Conn $Conn -Exe $psql -Arguments @('-X', '-q', '-v', 'ON_ERROR_STOP=1', '--csv', '-o', $OutFile, '-f', $SqlFile)
    if ($code -ne 0) { Stop-Migration "Query $([IO.Path]::GetFileName($SqlFile)) failed against the $($Conn.Label)." }
}

# A single value from a query given as text (written to a temp file first).
function Get-PsqlValue($Conn, [string]$Sql) {
    $psql = Find-PgTool 'psql'
    $tmp = [IO.Path]::GetTempFileName()
    $outFile = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($tmp, $Sql, $script:Utf8NoBom)
        $code = Invoke-PgTool -Conn $Conn -Exe $psql -Arguments @('-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1', '-o', $outFile, '-f', $tmp)
        if ($code -ne 0) { Stop-Migration "Could not query the $($Conn.Label). Check the connection string and password." }
        return ([IO.File]::ReadAllText($outFile, $script:Utf8NoBom)).Trim()
    } finally {
        Remove-Item -LiteralPath $tmp, $outFile -ErrorAction SilentlyContinue
    }
}

# Runs the read-only inventory queries into $OutDir as CSV files. psql's \o
# takes plain file names there, so it runs with $OutDir as its working
# directory: a Windows path inside a psql meta-command would be read as more
# meta-commands at every backslash. PowerShell starts native programs in its
# own location (Push-Location), not in [Environment]::CurrentDirectory.
function Export-Inventory($Conn, [string]$OutDir) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $psql = Find-PgTool 'psql'
    Push-Location -LiteralPath $OutDir
    try {
        $files = @('inventory-core.sql')
        if ((Get-PsqlValue $Conn "SELECT to_regclass('cron.job') IS NOT NULL") -eq 't') { $files += 'inventory-cron.sql' }
        else { Write-Utf8 (Join-Path $OutDir 'cron_jobs.csv') '' }
        if ((Get-PsqlValue $Conn "SELECT to_regclass('storage.buckets') IS NOT NULL AND to_regclass('storage.objects') IS NOT NULL") -eq 't') { $files += 'inventory-storage.sql' }
        else { Write-Utf8 (Join-Path $OutDir 'storage_buckets.csv') '' }
        if ((Get-PsqlValue $Conn "SELECT to_regclass('vault.secrets') IS NOT NULL") -eq 't') { $files += 'inventory-vault.sql' }
        else { Write-Utf8 (Join-Path $OutDir 'vault_secret_names.csv') '' }

        foreach ($f in $files) {
            $code = Invoke-PgTool -Conn $Conn -Exe $psql -Arguments @('-X', '-q', '-v', 'ON_ERROR_STOP=1', '--csv', '-f', (Join-Path $script:SqlDir $f))
            if ($code -ne 0) { Stop-Migration "Inventory query $f failed against the $($Conn.Label)." }
        }

        # The repo's own "which migrations are applied" checker, for comparison.
        $checker = Join-Path $script:RepoRoot 'database\migrations\00_check_migration_state.sql'
        if (Test-Path -LiteralPath $checker) {
            $code = Invoke-PgTool -Conn $Conn -Exe $psql -Arguments @('-X', '-q', '-v', 'ON_ERROR_STOP=1', '--csv', '-o', (Join-Path $OutDir 'migration_state.csv'), '-f', $checker)
            if ($code -ne 0) { Write-Note "The migration checker did not run against the $($Conn.Label); continuing without it." }
        }
    } finally {
        Pop-Location
    }
}

# The finishing SQL for the new project, built from the old project's
# inventory: realtime publication, row level security and API grants exactly as
# they were, and the scheduled jobs with their commands rewritten. Idempotent.
# Returns @{ Sql = text; Notes = messages for the operator }.
function New-PostImportSql([string]$OldDir, $Rewrite) {
    $notes = New-Object System.Collections.ArrayList
    $post = New-Object System.Text.StringBuilder
    [void]$post.AppendLine('-- Generated by 2-import-new-project.ps1 from export\old\. Safe to re-run.')
    [void]$post.AppendLine('BEGIN;')

    # Realtime: tables whose changes the app and the portal subscribe to.
    [void]$post.AppendLine("DO `$pub`$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN CREATE PUBLICATION supabase_realtime; END IF; END `$pub`$;")
    foreach ($t in (Import-CsvIfAny (Join-Path $OldDir 'realtime_tables.csv'))) {
        if ($t.schema_name -ne 'public') { [void]$notes.Add("realtime table $($t.schema_name).$($t.table_name) is outside public; add it by hand if you need it"); continue }
        $lit = ConvertTo-SqlLiteral $t.table_name
        $qual = 'public.' + (ConvertTo-SqlIdent $t.table_name)
        [void]$post.AppendLine("DO `$rt`$ BEGIN IF to_regclass($(ConvertTo-SqlLiteral $qual)) IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = $lit) THEN ALTER PUBLICATION supabase_realtime ADD TABLE $qual; END IF; END `$rt`$;")
    }

    # Row level security exactly as it was. A new project may be set to switch RLS
    # on for every new table; with the app connecting as anon, that would turn
    # every read into an empty result.
    foreach ($t in (Import-CsvIfAny (Join-Path $OldDir 'rls.csv'))) {
        $qual = 'public.' + (ConvertTo-SqlIdent $t.table_name)
        $en = $(if ($t.rls_enabled -eq 't') { 'ENABLE' } else { 'DISABLE' })
        $fo = $(if ($t.rls_forced -eq 't') { 'FORCE' } else { 'NO FORCE' })
        [void]$post.AppendLine("ALTER TABLE $qual $en ROW LEVEL SECURITY, $fo ROW LEVEL SECURITY;")
    }

    # Grants for the three API roles, exactly as they were.
    foreach ($p in (Import-CsvIfAny (Join-Path $OldDir 'privileges.csv'))) {
        $qual = 'public.' + (ConvertTo-SqlIdent $p.table_name)
        $role = ConvertTo-SqlIdent $p.role_name
        foreach ($pair in @(@('can_select', 'SELECT'), @('can_insert', 'INSERT'), @('can_update', 'UPDATE'), @('can_delete', 'DELETE'))) {
            if ($p.($pair[0]) -eq 't') { [void]$post.AppendLine("GRANT $($pair[1]) ON $qual TO $role;") }
            else { [void]$post.AppendLine("REVOKE $($pair[1]) ON $qual FROM $role;") }
        }
    }

    # Scheduled jobs, same names, same schedules, same state.
    $jobs = @(Import-CsvIfAny (Join-Path $OldDir 'cron_jobs.csv'))
    if ($jobs.Count) {
        [void]$post.AppendLine('DO $cron$')
        [void]$post.AppendLine('BEGIN')
        [void]$post.AppendLine("  IF to_regclass('cron.job') IS NULL THEN")
        [void]$post.AppendLine("    RAISE WARNING 'pg_cron is not enabled, so $($jobs.Count) scheduled job(s) were not created. Enable pg_cron under Database -> Extensions and run this script again.';")
        [void]$post.AppendLine('    RETURN;')
        [void]$post.AppendLine('  END IF;')
        foreach ($j in $jobs) {
            $cmd = Update-TextWithRewrite ([string]$j.command) $Rewrite $null
            if ([string]::IsNullOrEmpty($j.jobname)) {
                [void]$post.AppendLine("  PERFORM cron.schedule($(ConvertTo-SqlLiteral $j.schedule), $(ConvertTo-DollarQuoted $cmd));")
            } else {
                $name = ConvertTo-SqlLiteral $j.jobname
                [void]$post.AppendLine("  PERFORM cron.schedule($name, $(ConvertTo-SqlLiteral $j.schedule), $(ConvertTo-DollarQuoted $cmd));")
                $active = $(if ($j.active -eq 't') { 'true' } else { 'false' })
                [void]$post.AppendLine("  PERFORM cron.alter_job(job_id := (SELECT jobid FROM cron.job WHERE jobname = $name ORDER BY jobid DESC LIMIT 1), active := $active);")
            }
        }
        [void]$post.AppendLine('END')
        [void]$post.AppendLine('$cron$;')
    }
    [void]$post.AppendLine('COMMIT;')
    return @{ Sql = $post.ToString(); Notes = $notes }
}

function Get-TotalRows([string]$RowCountsCsv) {
    $total = [long]0
    foreach ($r in (Import-CsvIfAny $RowCountsCsv)) { $total += [long]$r.row_count }
    return $total
}

# ── Files ────────────────────────────────────────────────────────────────────

function Write-Utf8([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, $script:Utf8NoBom)
}

function Import-CsvIfAny([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    if ((Get-Item -LiteralPath $Path).Length -eq 0) { return @() }
    return @(Import-Csv -LiteralPath $Path -Encoding UTF8)
}

# SQL string literal.
function ConvertTo-SqlLiteral([string]$Text) {
    return "'" + $Text.Replace("'", "''") + "'"
}

# SQL identifier.
function ConvertTo-SqlIdent([string]$Text) {
    return '"' + $Text.Replace('"', '""') + '"'
}

# Dollar-quoted body with a tag that cannot occur inside it.
function ConvertTo-DollarQuoted([string]$Text) {
    $n = 0
    do { $tag = '$q' + $n + '$'; $n++ } while ($Text.Contains($tag))
    return $tag + $Text + $tag
}

# ── Keys and project references ──────────────────────────────────────────────

# The claims of a Supabase JWT (ref, role), or $null for anything else.
function Get-JwtClaims([string]$Token) {
    $parts = $Token.Split('.')
    if ($parts.Count -ne 3) { return $null }
    $p = $parts[1].Replace('-', '+').Replace('_', '/')
    switch ($p.Length % 4) { 2 { $p += '==' } 3 { $p += '=' } 1 { return $null } }
    try {
        $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
    } catch { return $null }
    $ref  = $null; $role = $null
    if ($json.PSObject.Properties['ref'])  { $ref  = [string]$json.ref }
    if ($json.PSObject.Properties['role']) { $role = [string]$json.role }
    return @{ Ref = $ref; Role = $role }
}

# Every distinct JWT in the given files.
function Get-JwtsInFiles([string[]]$Paths) {
    $found = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($path in $Paths) {
        $reader = New-Object System.IO.StreamReader($path, $script:Utf8NoBom)
        try {
            while ($null -ne ($line = $reader.ReadLine())) {
                if ($line.IndexOf('eyJ') -lt 0) { continue }
                foreach ($m in $script:JwtRegex.Matches($line)) { [void]$found.Add($m.Value) }
            }
        } finally { $reader.Dispose() }
    }
    return ,$found
}

# The ordered list of text substitutions that turns references to the old
# project into references to the new one. JWTs first (they are opaque), then
# the full URL, then the bare ref for anything else (wss://, pooler users).
#
# Returns @{ Pairs = list of @(old, new, label); Unresolved = list of strings }
function New-ProjectRewrite {
    param(
        [string]$OldRef, [string]$NewRef, [string]$NewUrl,
        [string]$PublishableKey, [string]$SecretKey,
        $Jwts
    )
    $pairs = New-Object System.Collections.ArrayList
    $unresolved = New-Object System.Collections.ArrayList
    foreach ($jwt in $Jwts) {
        $claims = Get-JwtClaims $jwt
        if ($null -eq $claims) { continue }
        if ($claims.Ref -eq $OldRef -and $claims.Role -eq 'anon') {
            [void]$pairs.Add(@($jwt, $PublishableKey, 'old anon key -> new publishable key'))
        } elseif ($claims.Ref -eq $OldRef -and $claims.Role -eq 'service_role') {
            if ($SecretKey) {
                [void]$pairs.Add(@($jwt, $SecretKey, 'old service_role key -> new secret key'))
            } else {
                [void]$unresolved.Add("old service_role key (no new secret key given)")
            }
        } else {
            [void]$unresolved.Add("a key for project '$($claims.Ref)' with role '$($claims.Role)' - left as it was")
        }
    }
    $newUrl = $NewUrl.TrimEnd('/')
    [void]$pairs.Add(@("https://$OldRef.supabase.co", $newUrl, 'old project URL -> new project URL'))
    [void]$pairs.Add(@($OldRef, $NewRef, 'old project ref -> new project ref'))
    return @{ Pairs = $pairs; Unresolved = $unresolved }
}

function Update-TextWithRewrite([string]$Text, $Rewrite, $Counts) {
    foreach ($pair in $Rewrite.Pairs) {
        $old = $pair[0]
        if ($Text.IndexOf($old) -ge 0) {
            $n = ([regex]::Matches($Text, [regex]::Escape($old))).Count
            if ($Counts) { $Counts[$pair[2]] = [int]$Counts[$pair[2]] + $n }
            $Text = $Text.Replace($old, $pair[1])
        }
    }
    return $Text
}

# Copies a (possibly large) SQL file line by line, applying the rewrite and
# dropping lines $Skip matches. Returns the substitution counts.
function Copy-SqlWithRewrite([string]$Source, [string]$Destination, $Rewrite, [scriptblock]$Skip) {
    $counts = @{}
    $reader = New-Object System.IO.StreamReader($Source, $script:Utf8NoBom)
    $writer = New-Object System.IO.StreamWriter($Destination, $false, $script:Utf8NoBom)
    # LF, as pg_dump wrote it. WriteLine would otherwise use Windows' CRLF,
    # and a stray \r inside COPY data is a change to the data.
    $writer.NewLine = "`n"
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if ($Skip -and (& $Skip $line)) { $writer.WriteLine("-- (removed for the new project) $line"); continue }
            $writer.WriteLine((Update-TextWithRewrite $line $Rewrite $counts))
        }
    } finally {
        $reader.Dispose(); $writer.Dispose()
    }
    return $counts
}
