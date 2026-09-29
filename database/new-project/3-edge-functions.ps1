# Step 3 — the Edge Functions: copy them off the OLD project, deploy them to
# the NEW one, and set their secrets.
#
#   powershell -ExecutionPolicy Bypass -File .\3-edge-functions.ps1
#   powershell -ExecutionPolicy Bypass -File .\3-edge-functions.ps1 -DownloadOnly
#   powershell -ExecutionPolicy Bypass -File .\3-edge-functions.ps1 -DeployOnly
#
# -DownloadOnly  do just the OLD-project half. Do this before the old project
#                shuts down: send-email only exists there.
# -DeployOnly    do just the NEW-project half, from an earlier download.
#
# Uses the Supabase CLI through npx (Node.js is already installed here), with
# --use-api so no Docker is needed. Each half asks for a personal access token
# for that account, because the two projects belong to different accounts.

param([switch]$DownloadOnly, [switch]$DeployOnly)

. (Join-Path $PSScriptRoot 'common.ps1')

$settings = Read-Settings
$oldRef   = Get-Setting $settings 'OLD_PROJECT_REF'
Test-ProjectRef $oldRef 'OLD_PROJECT_REF'
if (-not $DownloadOnly) {
    $newRef = Get-Setting $settings 'NEW_PROJECT_REF'
    Test-ProjectRef $newRef 'NEW_PROJECT_REF'
}

$npxCmd = Get-Command 'npx.cmd' -ErrorAction SilentlyContinue
if (-not $npxCmd) { Stop-Migration 'npx was not found. Install Node.js LTS from https://nodejs.org and open a new terminal.' }
$npx = $npxCmd.Source

$fnDir      = Join-Path $script:ExportDir 'functions'
$downloadWd = Join-Path $fnDir 'old'
New-Item -ItemType Directory -Force -Path (Join-Path $downloadWd 'supabase') | Out-Null
$cfg = Join-Path $downloadWd 'supabase\config.toml'
if (-not (Test-Path -LiteralPath $cfg)) { Write-Utf8 $cfg "project_id = `"downloaded-functions`"`n" }

# Functions whose source the repo keeps, and the --workdir to deploy them from.
# These are deployed from the repo because they carry the changes that make
# them work with the new sb_secret_ keys. send-email is deliberately absent:
# the repo's copy is commented out, and the working one only exists deployed.
$repoFunctions = @{
    'send-reminders' = $script:RepoRoot
    'send-sms'       = $script:RepoRoot
    'send-push'      = (Join-Path $script:RepoRoot 'inaagapay_flutter_v2')
}
$knownFunctions = @('send-email', 'send-push', 'send-reminders', 'send-sms')

function Invoke-Supabase([string]$Token, [string[]]$Arguments, [switch]$Capture) {
    $saved = $env:SUPABASE_ACCESS_TOKEN
    $env:SUPABASE_ACCESS_TOKEN = $Token
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $all = @('--yes', 'supabase@latest') + $Arguments
        if ($Capture) {
            $out = & $npx @all 2>&1 | ForEach-Object { "$_" }
            return @{ Code = $LASTEXITCODE; Output = ($out -join "`n") }
        }
        & $npx @all 2>&1 | ForEach-Object { "$_" } | Out-Host
        return @{ Code = $LASTEXITCODE; Output = '' }
    } finally {
        $ErrorActionPreference = $eap
        $env:SUPABASE_ACCESS_TOKEN = $saved
    }
}

# One column of the CLI's pretty table ("ID | NAME | SLUG | ...").
function Get-TableColumn([string]$Text, [string]$Column) {
    $values = @()
    $index = -1
    foreach ($line in ($Text -split "`n")) {
        if ($line -notmatch '\|') { continue }
        $cells = @($line -split '\|' | ForEach-Object { $_.Trim() })
        if ($index -lt 0) {
            for ($i = 0; $i -lt $cells.Count; $i++) { if ($cells[$i] -eq $Column) { $index = $i } }
            continue
        }
        if ($index -lt $cells.Count -and $cells[$index] -and $cells[$index] -notmatch '^-+$') { $values += $cells[$index] }
    }
    return $values
}

# One field of every item in a CLI listing. The CLI prints JSON when its output
# is piped, as it is here (either a bare array or {"functions": [...]}), and a
# table when it is not, so read either.
function Get-ListedNames([string]$Text, [string]$Field, [string]$Column) {
    $lines = @($Text -split "`n")
    $first = -1; $last = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = $lines[$i].Trim()
        if ($first -lt 0 -and $t -match '^[\[{]') { $first = $i }
        if ($t -match '[\]}]$') { $last = $i }
    }
    if ($first -ge 0 -and $last -ge $first) {
        try {
            $data = ($lines[$first..$last] -join "`n") | ConvertFrom-Json
            $items = @($data)
            if ($items.Count -eq 1 -and $null -eq $items[0].$Field) {
                $inner = @($items[0].PSObject.Properties | Where-Object { $_.Value -is [array] } | Select-Object -First 1)
                $items = $(if ($inner.Count) { @($inner[0].Value) } else { @() })
            }
            return @($items | ForEach-Object { $_.$Field } | Where-Object { $_ })
        } catch { }
    }
    return @(Get-TableColumn $Text $Column)
}

# Lets the browser send an apikey header to a downloaded function. The portal
# now sends one (a publishable key is only accepted as a bearer alongside a
# matching apikey), and a CORS allow-list without it would fail the preflight.
function Add-ApikeyToCors([string]$Dir) {
    $changed = @()
    $pattern = '([''"]Access-Control-Allow-Headers[''"]\s*[:,]\s*)([''"])([^''"]*)([''"])'
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        if ($m.Groups[3].Value -match '(?i)\bapikey\b') { return $m.Value }
        return $m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value + ', apikey' + $m.Groups[4].Value
    }
    foreach ($file in (Get-ChildItem -LiteralPath $Dir -Recurse -File -Include '*.ts', '*.js', '*.mjs', '*.tsx')) {
        $text = [IO.File]::ReadAllText($file.FullName, $script:Utf8NoBom)
        $new = [regex]::Replace($text, $pattern, $evaluator)
        if ($new -ne $text) { Write-Utf8 $file.FullName $new; $changed += $file.Name }
    }
    return $changed
}

# ── OLD project: list, record, download ──────────────────────────────────────

if (-not $DeployOnly) {
    Write-Step 'Signing in to the OLD project''s account'
    Write-Info 'Sign in to supabase.com with the account that owns the OLD project, open'
    Write-Info 'https://supabase.com/dashboard/account/tokens, generate a token, and paste it here.'
    $oldToken = Read-Secret 'OLD account access token (typing is hidden)'

    Write-Step 'Listing the OLD project''s functions'
    $r = Invoke-Supabase $oldToken @('functions', 'list', '--project-ref', $oldRef, '-o', 'json') -Capture
    if ($r.Code -ne 0) { Write-Host $r.Output; Stop-Migration 'Could not list the old project''s functions. Check the token and that it belongs to the old project''s account.' }
    $slugs = @(Get-ListedNames $r.Output 'slug' 'SLUG')
    if (-not $slugs.Count) { $slugs = $knownFunctions; Write-Note 'could not read the list; using the four this repo knows about' }
    Write-Utf8 (Join-Path $fnDir 'old-functions.txt') (($slugs -join "`r`n") + "`r`n")
    Write-Ok ('functions: ' + ($slugs -join ', '))

    Write-Step 'Recording the OLD project''s secret names (values cannot be read back)'
    $r = Invoke-Supabase $oldToken @('secrets', 'list', '--project-ref', $oldRef, '-o', 'json') -Capture
    $secretNames = @(Get-ListedNames $r.Output 'name' 'NAME' | Where-Object { $_ -notlike 'SUPABASE_*' })
    Write-Utf8 (Join-Path $fnDir 'old-secret-names.txt') (($secretNames -join "`r`n") + "`r`n")
    Write-Ok ('secrets: ' + $(if ($secretNames.Count) { $secretNames -join ', ' } else { '(none read)' }))

    Write-Step 'Downloading the deployed code of every function'
    foreach ($slug in $slugs) {
        $r = Invoke-Supabase $oldToken @('functions', 'download', $slug, '--project-ref', $oldRef, '--use-api', '--workdir', $downloadWd)
        $dest = Join-Path $downloadWd "supabase\functions\$slug"
        if ($r.Code -eq 0 -and (Test-Path -LiteralPath $dest)) {
            Write-Ok "$slug -> export\functions\old\supabase\functions\$slug"
            if ($repoFunctions.ContainsKey($slug)) {
                $repoIndex = Join-Path $repoFunctions[$slug] "supabase\functions\$slug\index.ts"
                $oldIndex  = Join-Path $dest 'index.ts'
                if ((Test-Path -LiteralPath $repoIndex) -and (Test-Path -LiteralPath $oldIndex)) {
                    $a = ([IO.File]::ReadAllText($repoIndex) -replace '\s+', ' ').Trim()
                    $b = ([IO.File]::ReadAllText($oldIndex) -replace '\s+', ' ').Trim()
                    if ($a -ne $b) { Write-Note "$slug in the repo differs from what was deployed. The repo version is the one deployed to the new project; the old one is kept in export\functions\old for comparison." }
                }
            }
        } else {
            Write-Note "$slug could not be downloaded. Open it in the OLD dashboard (Edge Functions -> $slug -> Code), and save its files into export\functions\old\supabase\functions\$slug\ by hand."
        }
    }
}

if ($DownloadOnly) {
    Write-Host ''
    Write-Host 'Download complete.' -ForegroundColor Green
    Write-Info 'Run this script again with -DeployOnly once the new project exists.'
    exit 0
}

# ── NEW project: secrets, then functions ─────────────────────────────────────

$secretsFile = Join-Path $script:NewProjectDir 'functions.secrets.env'
if (-not (Test-Path -LiteralPath $secretsFile)) {
    Write-Step 'Preparing functions.secrets.env'
    $template = [IO.File]::ReadAllLines((Join-Path $script:NewProjectDir 'functions.secrets.example.env'), $script:Utf8NoBom)
    $appEnv = @{}
    $appEnvPath = Join-Path $script:RepoRoot 'inaagapay_flutter_v2\.env'
    if (Test-Path -LiteralPath $appEnvPath) {
        foreach ($line in [IO.File]::ReadAllLines($appEnvPath, $script:Utf8NoBom)) {
            $i = $line.IndexOf('=')
            if ($i -gt 0 -and -not $line.TrimStart().StartsWith('#')) { $appEnv[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1) }
        }
    }
    $out = New-Object System.Collections.ArrayList
    $present = @{}
    foreach ($line in $template) {
        $i = $line.IndexOf('=')
        if ($i -gt 0 -and -not $line.TrimStart().StartsWith('#')) {
            $key = $line.Substring(0, $i).Trim()
            $present[$key] = $true
            if ($line.Substring($i + 1).Trim() -eq '' -and $appEnv.ContainsKey($key) -and $appEnv[$key].Trim() -ne '') {
                [void]$out.Add("$key=$($appEnv[$key])"); continue
            }
        }
        [void]$out.Add($line)
    }
    $namesFile = Join-Path $fnDir 'old-secret-names.txt'
    if (Test-Path -LiteralPath $namesFile) {
        $extra = @(Get-Content -LiteralPath $namesFile | Where-Object { $_ -and -not $present.ContainsKey($_) })
        if ($extra.Count) {
            [void]$out.Add('')
            [void]$out.Add('# Also set on the OLD project. Fill in what the old functions used:')
            foreach ($n in $extra) { [void]$out.Add("$n=") }
        }
    }
    Write-Utf8 $secretsFile (($out -join "`r`n") + "`r`n")
    Write-Host ''
    Write-Host "Created $secretsFile" -ForegroundColor Yellow
    Write-Info 'Values found in inaagapay_flutter_v2\.env were filled in. Check every line,'
    Write-Info 'fill in the empty ones you know, then run this script again with -DeployOnly.'
    exit 0
}

Write-Step 'Signing in to the NEW project''s account'
Write-Info 'Sign in to supabase.com with the NEW account, open'
Write-Info 'https://supabase.com/dashboard/account/tokens, generate a token, and paste it here.'
$newToken = Read-Secret 'NEW account access token (typing is hidden)'

Write-Step 'Setting the function secrets on the NEW project'
$toSet = @()
$empty = @()
foreach ($line in [IO.File]::ReadAllLines($secretsFile, $script:Utf8NoBom)) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $i = $t.IndexOf('=')
    if ($i -lt 1) { continue }
    $key = $t.Substring(0, $i).Trim()
    if ($key -like 'SUPABASE_*') { Write-Note "$key is reserved by Supabase; skipped"; continue }
    if ($t.Substring($i + 1).Trim() -in @('', '""', "''")) { $empty += $key; continue }
    $toSet += $t
}
if ($toSet.Count) {
    $tmp = Join-Path $fnDir 'secrets-to-set.env'
    try {
        Write-Utf8 $tmp (($toSet -join "`n") + "`n")
        $r = Invoke-Supabase $newToken @('secrets', 'set', '--env-file', $tmp, '--project-ref', $newRef)
        if ($r.Code -ne 0) { Stop-Migration 'Setting the secrets failed. Check the token belongs to the new project''s account.' }
    } finally {
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
    }
    Write-Ok ("set: " + (($toSet | ForEach-Object { $_.Substring(0, $_.IndexOf('=')) }) -join ', '))
}
if ($empty.Count) { Write-Note ("left unset (empty in functions.secrets.env): " + ($empty -join ', ')) }

Write-Step 'Deploying the functions to the NEW project (JWT verification off)'
# Exactly what the old project had. The four known names are only the fallback
# for when that list was never read: the old project turned out to have just
# send-sms and send-reminders (email goes out through a database trigger, and
# nothing calls send-push).
$slugs = $knownFunctions
$listFile = Join-Path $fnDir 'old-functions.txt'
if (Test-Path -LiteralPath $listFile) {
    $listed = @(Get-Content -LiteralPath $listFile | Where-Object { $_ })
    if ($listed.Count) { $slugs = $listed }
}
$deployed = @(); $skipped = @()
foreach ($slug in $slugs) {
    if ($repoFunctions.ContainsKey($slug)) {
        $wd = $repoFunctions[$slug]
        $from = 'repo'
    } else {
        $dir = Join-Path $downloadWd "supabase\functions\$slug"
        if (-not (Test-Path -LiteralPath $dir)) {
            $skipped += $slug
            Write-Note "$slug was not downloaded, so it cannot be deployed. Run -DownloadOnly while the old project is still up, or copy its code from the old dashboard."
            continue
        }
        $patched = Add-ApikeyToCors $dir
        if ($patched.Count) { Write-Ok "$slug : added apikey to its CORS allow-list ($($patched -join ', '))" }
        $wd = $downloadWd
        $from = 'old project'
    }
    $r = Invoke-Supabase $newToken @('functions', 'deploy', $slug, '--project-ref', $newRef, '--no-verify-jwt', '--use-api', '--workdir', $wd)
    if ($r.Code -eq 0) { $deployed += $slug; Write-Ok "$slug deployed (from the $from)" }
    else { $skipped += $slug; Write-Note "$slug failed to deploy; see the output above" }
}

Write-Step 'Functions now on the NEW project'
[void](Invoke-Supabase $newToken @('functions', 'list', '--project-ref', $newRef))

Write-Host ''
if ($skipped.Count) {
    Write-Host ("Deployed: {0}. NOT deployed: {1}." -f ($deployed -join ', '), ($skipped -join ', ')) -ForegroundColor Yellow
} else {
    Write-Host ("All functions deployed: {0}." -f ($deployed -join ', ')) -ForegroundColor Green
}
Write-Info 'Next: 4-switch-app-config.ps1 (README step 5).'
