# Step 5 — check the NEW project works the way the app and the portal use it.
#
#   powershell -ExecutionPolicy Bypass -File .\5-verify.ps1
#
# Sends nothing to anyone: the SMS check uses an invalid number, the email
# check is a CORS preflight only, and the reminder check is a dry run that
# counts who would be reminded.

param([switch]$SkipDatabase)

. (Join-Path $PSScriptRoot 'common.ps1')

$settings       = Read-Settings
$newRef         = Get-Setting $settings 'NEW_PROJECT_REF'
$newUrl         = (Get-Setting $settings 'NEW_SUPABASE_URL').TrimEnd('/')
$publishableKey = Get-Setting $settings 'NEW_PUBLISHABLE_KEY'
Test-ProjectRef $newRef 'NEW_PROJECT_REF'

$pass = 0; $fail = 0
function Pass([string]$s) { $script:pass++; Write-Ok $s }
function Fail([string]$s) { $script:fail++; Write-Host "    FAIL $s" -ForegroundColor Red }

# Invoke-WebRequest throws on 4xx/5xx in Windows PowerShell; this returns the
# status and body either way.
function Invoke-Http([string]$Method, [string]$Uri, [hashtable]$Headers, [string]$Body) {
    try {
        $params = @{ UseBasicParsing = $true; Method = $Method; Uri = $Uri; Headers = $Headers }
        if ($Body) { $params.Body = $Body; $params.ContentType = 'application/json' }
        $r = Invoke-WebRequest @params
        return @{ Status = [int]$r.StatusCode; Body = [string]$r.Content; Headers = $r.Headers }
    } catch [System.Net.WebException] {
        $resp = $_.Exception.Response
        if ($null -eq $resp) { return @{ Status = 0; Body = $_.Exception.Message; Headers = @{} } }
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $body = $reader.ReadToEnd(); $reader.Dispose()
        return @{ Status = [int]$resp.StatusCode; Body = $body; Headers = $resp.Headers }
    }
}

$pub = @{ apikey = $publishableKey; Authorization = "Bearer $publishableKey" }

Write-Step 'Database API (what the app and the portal read through)'
$r = Invoke-Http 'GET' "$newUrl/rest/v1/accounts?select=account_id&limit=1" ($pub + @{ Prefer = 'count=exact' }) $null
if ($r.Status -eq 200) {
    $range = [string]$r.Headers['Content-Range']
    if ($range -match '/(\d+)$' -and [long]$Matches[1] -gt 0) { Pass "accounts readable with the publishable key ($($Matches[1]) accounts)" }
    else { Fail "accounts answered 200 but with no rows ($range): check row level security and grants on accounts" }
} else { Fail "accounts: HTTP $($r.Status) $($r.Body)" }

Write-Step 'Storage (profile photos)'
$r = Invoke-Http 'GET' "$newUrl/storage/v1/object/public/files/__verify_does_not_exist__.jpg" @{} $null
if ($r.Body -match 'Bucket not found') { Fail 'the public "files" bucket is missing: run database\migrations\20260929_profile_photo_storage.sql' }
else { Pass 'the public "files" bucket exists' }

Write-Step 'Edge Functions'
# send-sms checks its own configuration before the number, so an invalid number
# tells the two apart without texting anybody.
$r = Invoke-Http 'POST' "$newUrl/functions/v1/send-sms" $pub '{"number":"000","message":"verify"}'
switch ($r.Status) {
    400 { Pass 'send-sms is deployed, reachable with the publishable key, and has its SMS key' }
    503 { Fail 'send-sms runs but SEMAPHORE_API_KEY is not set (functions.secrets.env, then 3-edge-functions.ps1 -DeployOnly)' }
    401 { Fail 'send-sms rejected the publishable key: it was deployed with JWT verification on. Re-run 3-edge-functions.ps1 -DeployOnly' }
    404 { Fail 'send-sms is not deployed' }
    default { Fail "send-sms: HTTP $($r.Status) $($r.Body)" }
}

# The portal's browser call must pass CORS with the apikey header it now sends.
$r = Invoke-Http 'OPTIONS' "$newUrl/functions/v1/send-email" @{
    Origin = 'https://example.com'
    'Access-Control-Request-Method' = 'POST'
    'Access-Control-Request-Headers' = 'apikey,authorization,content-type'
} $null
$allow = [string]$r.Headers['Access-Control-Allow-Headers']
if ($r.Status -eq 404) { Fail 'send-email is not deployed' }
elseif ($r.Status -ge 200 -and $r.Status -lt 300 -and ($allow -match '(?i)apikey' -or $allow -eq '*')) { Pass 'send-email is deployed and accepts the portal''s headers' }
else { Fail "send-email preflight: HTTP $($r.Status), allowed headers '$allow'" }

$r = Invoke-Http 'OPTIONS' "$newUrl/functions/v1/send-push" @{ Origin = 'https://example.com'; 'Access-Control-Request-Method' = 'POST' } $null
if ($r.Status -eq 404) { Fail 'send-push is not deployed' } else { Pass 'send-push is deployed' }

Write-Info ''
Write-Info 'send-reminders is checked with the SECRET key (the one the daily job uses).'
$secretKey = Read-Secret 'Secret key (sb_secret_...; typing is hidden)'
$sec = @{ apikey = $secretKey; Authorization = "Bearer $secretKey" }
$r = Invoke-Http 'POST' "$newUrl/functions/v1/send-reminders" $sec '{"dry_run":true}'
if (($r.Status -eq 200 -or $r.Status -eq 207) -and $r.Body -match '"dry_run"\s*:\s*true') {
    Pass "send-reminders dry run answered $($r.Status)"
    Write-Info ("         " + $(if ($r.Body.Length -gt 300) { $r.Body.Substring(0, 300) + '...' } else { $r.Body }))
} elseif ($r.Status -eq 401) {
    Fail 'send-reminders refused the secret key. Make sure the repo version (which reads SUPABASE_SECRET_KEYS) was deployed.'
} else { Fail "send-reminders: HTTP $($r.Status) $($r.Body)" }

$r = Invoke-Http 'POST' "$newUrl/functions/v1/send-reminders" $pub '{"dry_run":true}'
if ($r.Status -eq 401) { Pass 'send-reminders refuses the public key, as it should' }
else { Fail "send-reminders accepted the PUBLIC key (HTTP $($r.Status)); anyone could trigger SMS" }

if (-not $SkipDatabase) {
    Write-Step 'The daily reminder job, from inside the database (dry run)'
    $new = ConvertFrom-PgUrl (Get-Setting $settings 'NEW_DB_URL') 'NEW project database'
    Add-Password $new
    $has = Get-PsqlValue $new "SELECT to_regprocedure('public.preview_daily_reminders(date)') IS NOT NULL AND to_regclass('net._http_response') IS NOT NULL"
    if ($has -ne 't') {
        Write-Note 'preview_daily_reminders() or pg_net is not in this database, so there is no daily reminder job to test (the old project had none either if this matches it).'
    } else {
        $settingsState = Get-PsqlValue $new "SELECT count(*) FROM public.job_settings WHERE value LIKE '%REPLACE-ME%'"
        if ([int]$settingsState -gt 0) {
            Write-Note 'job_settings still holds placeholders (as on the old project): the job is off. README, "Daily reminders", explains how to turn it on.'
        } else {
            $before = Get-PsqlValue $new 'SELECT COALESCE(max(id), 0) FROM net._http_response'
            [void](Get-PsqlValue $new 'SELECT public.preview_daily_reminders()')
            $result = ''
            for ($i = 0; $i -lt 15 -and -not $result; $i++) {
                Start-Sleep -Seconds 2
                $result = Get-PsqlValue $new "SELECT status_code || ' ' || left(COALESCE(content, error_msg, ''), 200) FROM net._http_response WHERE id > $before ORDER BY id DESC LIMIT 1"
            }
            if ($result -match '^(200|207) ') { Pass "the database reached send-reminders: $result" }
            elseif ($result) { Fail "the database called send-reminders and got: $result" }
            else { Fail 'no answer from send-reminders within 30 seconds (check Edge Functions -> send-reminders -> Logs)' }
        }
    }
}

Write-Host ''
if ($fail) {
    Write-Host "$pass passed, $fail FAILED." -ForegroundColor Red
} else {
    Write-Host "All $pass checks passed." -ForegroundColor Green
}
Write-Info 'Then test by hand (README step 6): sign in on the portal and on the rebuilt app, record something, watch it appear.'
