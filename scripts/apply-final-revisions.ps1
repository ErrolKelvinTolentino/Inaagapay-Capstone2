param(
    [switch]$IncludeDemoActivity
)

# Uses the existing project's secure local password prompt. Never place a
# database password in chat or a command argument.
. (Join-Path $PSScriptRoot '..\database\new-project\common.ps1')
$revisionSettings = Read-Settings
$revisionConnection = ConvertFrom-PgUrl (Get-Setting $revisionSettings 'NEW_DB_URL') 'current InaAgapay database'
Add-Password $revisionConnection

try {
    $revisionReady = Get-PsqlValue $revisionConnection @'
SELECT CASE WHEN to_regprocedure('public.item_dose_presentation(bigint)') IS NOT NULL
  AND to_regprocedure('public.dispense_stock_doses(bigint,integer,bigint,text)') IS NOT NULL
  THEN 'ready' ELSE 'missing' END;
'@
    if ($revisionReady -ne 'ready') {
        Stop-Migration 'The dose presentation/dispensing functions are missing. Install the inventory prerequisites first.'
    }

    Write-Step 'Save the public-schema database backup before removing QA fixtures'
    $revisionBackupDir = Join-Path $script:RepoRoot ('database\backups\final-revisions-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path $revisionBackupDir | Out-Null
    $revisionBackup = Join-Path $revisionBackupDir 'before-revisions.dump'
    $revisionCode = Invoke-PgTool -Conn $revisionConnection -Exe (Find-PgTool 'pg_dump') -Arguments @('-Fc','--schema=public','--no-owner','--no-acl','-f',$revisionBackup)
    if ($revisionCode -ne 0) { Stop-Migration 'The backup failed; no QA cleanup was run.' }

    Write-Step 'Remove explicit QA fixtures and their dependent activity'
    $revisionCode = Invoke-PsqlFile -Conn $revisionConnection -Files @(
        (Join-Path $script:RepoRoot 'database\seed\20_remove_qa_fixtures.sql'),
        (Join-Path $script:RepoRoot 'database\seed\22_remove_qa_facilities.sql'),
        (Join-Path $script:RepoRoot 'database\seed\23_remove_qa_history.sql')
    )
    if ($revisionCode -ne 0) { Stop-Migration 'QA cleanup failed. Each file is its own transaction; earlier completed files remain applied. Review the reported cross-link or foreign key.' }

    Write-Step 'Require acknowledged disposal before dispensing an expired open-vial batch'
    $revisionCode = Invoke-PsqlFile -Conn $revisionConnection -Files @(Join-Path $script:RepoRoot 'database\migrations\20261007_require_open_vial_disposal.sql')
    if ($revisionCode -ne 0) { Stop-Migration 'Manual-disposal guard installation failed.' }

    if ($IncludeDemoActivity) {
        Write-Step 'Add the repeatable capstone dispensing scenario'
        $revisionCode = Invoke-PsqlFile -Conn $revisionConnection -Files @(Join-Path $script:RepoRoot 'database\seed\21_admin_consumption_activity.sql')
        if ($revisionCode -ne 0) { Stop-Migration 'Demo activity failed and its transaction rolled back.' }
    }

    Write-Ok 'Requested database revisions applied. Reload the admin page to refresh its cached data.'
    Write-Info "Backup: $revisionBackup"
} finally {
    $revisionConnection.Password = $null
}
