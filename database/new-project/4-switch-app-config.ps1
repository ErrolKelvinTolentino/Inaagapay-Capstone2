# Step 4 — point the app, the portal and the tooling at the NEW project.
#
#   powershell -ExecutionPolicy Bypass -File .\4-switch-app-config.ps1 -DryRun
#   powershell -ExecutionPolicy Bypass -File .\4-switch-app-config.ps1
#
# Replaces, in every file that holds them:
#   the old project URL       -> NEW_SUPABASE_URL
#   the old anon key          -> NEW_PUBLISHABLE_KEY
#   the old project ref       -> NEW_PROJECT_REF   (the portal's security header,
#                                                   the CLI config, the backup script)
#
# Files: inaagapay_flutter_v2\.env, every page and script under admin-web\,
# both vercel.json files, supabase\config.toml, database\backups\backup.js.
# -DryRun lists what would change and writes nothing.

param([switch]$DryRun)

. (Join-Path $PSScriptRoot 'common.ps1')

$settings       = Read-Settings
$oldRef         = Get-Setting $settings 'OLD_PROJECT_REF'
$newRef         = Get-Setting $settings 'NEW_PROJECT_REF'
$newUrl         = (Get-Setting $settings 'NEW_SUPABASE_URL').TrimEnd('/')
$publishableKey = Get-Setting $settings 'NEW_PUBLISHABLE_KEY'
Test-ProjectRef $oldRef 'OLD_PROJECT_REF'
Test-ProjectRef $newRef 'NEW_PROJECT_REF'
if ($newUrl -ne "https://$newRef.supabase.co") { Stop-Migration "NEW_SUPABASE_URL should be https://$newRef.supabase.co." }
if (-not $publishableKey.StartsWith('sb_publishable_')) { Stop-Migration 'NEW_PUBLISHABLE_KEY should start with sb_publishable_.' }

$root = $script:RepoRoot
$targets = New-Object System.Collections.ArrayList
foreach ($rel in @('inaagapay_flutter_v2\.env', 'vercel.json', 'admin-web\vercel.json', 'supabase\config.toml', 'database\backups\backup.js')) {
    $p = Join-Path $root $rel
    if (Test-Path -LiteralPath $p) { [void]$targets.Add($p) }
}
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $root 'admin-web') -Recurse -File -Include '*.html', '*.js', '*.json')) {
    if (-not $targets.Contains($f.FullName)) { [void]$targets.Add($f.FullName) }
}

$appEnv = Join-Path $root 'inaagapay_flutter_v2\.env'
if (-not (Test-Path -LiteralPath $appEnv)) {
    Stop-Migration 'inaagapay_flutter_v2\.env does not exist. Copy .env.example to .env there first.'
}

Write-Step ($(if ($DryRun) { 'What would change (dry run)' } else { 'Switching to the new project' }))
$jwts = Get-JwtsInFiles @($targets)
$rewrite = New-ProjectRewrite -OldRef $oldRef -NewRef $newRef -NewUrl $newUrl `
    -PublishableKey $publishableKey -SecretKey $null -Jwts $jwts
foreach ($u in $rewrite.Unresolved) {
    if ($u -like 'old service_role key*') {
        Write-Note 'a SERVICE ROLE key for the old project is sitting in one of these files. It is left untouched; remove it by hand - it should never be in the repo.'
    }
}

$changedFiles = 0
foreach ($path in $targets) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [IO.File]::ReadAllText($path, $script:Utf8NoBom)
    $counts = @{}
    $new = Update-TextWithRewrite $text $rewrite $counts
    if ($new -eq $text) { continue }
    $changedFiles++
    $rel = $path.Substring($root.Length + 1)
    Write-Ok ("{0}: {1}" -f $rel, (($counts.Keys | Sort-Object | ForEach-Object { "$($counts[$_]) x $_" }) -join '; '))
    if (-not $DryRun) {
        $enc = $(if ($hasBom) { New-Object System.Text.UTF8Encoding($true) } else { $script:Utf8NoBom })
        [IO.File]::WriteAllText($path, $new, $enc)
    }
}

# The app's .env must end up with both lines, whatever it held before.
$envText = [IO.File]::ReadAllText($appEnv, $script:Utf8NoBom)
if (-not $DryRun) {
    $envText = Update-TextWithRewrite $envText $rewrite $null
    foreach ($pair in @(@('SUPABASE_URL', $newUrl), @('SUPABASE_ANON_KEY', $publishableKey))) {
        $re = '(?m)^' + $pair[0] + '=.*$'
        if ([regex]::IsMatch($envText, $re)) { $envText = [regex]::Replace($envText, $re, $pair[0] + '=' + $pair[1]) }
        else { $envText = $envText.TrimEnd() + "`r`n" + $pair[0] + '=' + $pair[1] + "`r`n" }
    }
    Write-Utf8 $appEnv $envText
}

if ($changedFiles -eq 0) { Write-Ok 'nothing references the old project any more' }

# Anything left that still names the old project, outside history and docs.
Write-Step 'Looking for anything still pointing at the old project'
$skipDirs = '\\(\.git|node_modules|build|\.dart_tool|export|backups\\[^\\]+)\\'
$leftovers = @()
$oldAnon = @($rewrite.Pairs | Where-Object { $_[2] -like 'old anon key*' } | ForEach-Object { $_[0] })
foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File -Include '*.html', '*.js', '*.json', '*.dart', '*.ts', '*.toml', '*.env', '.env', '*.yaml', '*.ps1' -ErrorAction SilentlyContinue)) {
    if ($f.FullName -match $skipDirs) { continue }
    if ($f.FullName -like (Join-Path $script:NewProjectDir '*')) { continue }
    $t = [IO.File]::ReadAllText($f.FullName)
    if ($t.Contains($oldRef) -or ($oldAnon | Where-Object { $t.Contains($_) })) {
        $leftovers += $f.FullName.Substring($root.Length + 1)
    }
}
if ($DryRun) {
    Write-Info '(dry run: the files listed above would be changed; nothing was written)'
} elseif ($leftovers.Count) {
    foreach ($l in $leftovers) { Write-Note "still names the old project: $l" }
} else {
    Write-Ok 'no app, portal or config file names the old project'
}

Write-Host ''
if ($DryRun) {
    Write-Host 'Dry run complete. Run again without -DryRun to make the changes.' -ForegroundColor Green
} else {
    Write-Host 'Switched. The app and the portal now point at the new project.' -ForegroundColor Green
    Write-Info 'Next: deploy the portal and rebuild the APK (README step 5), then run 5-verify.ps1 (step 6).'
}
