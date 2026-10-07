# Final revision status

Source: `C:/Users/errol/Downloads/InaAgapay Final Revisions.pdf`.
Changes are implemented in this checkout. QA cleanup was applied to Supabase
on 2026-10-07 using the authenticated CLI, after a live rollback trial. The
dispensing guard and optional demonstration activity remain pending.

| Revision | Result |
|---|---|
| Remove duplicate Get App link | Login retains the Download InaAgapay App button. |
| Revise dashboard PDF | Exports scoped operations, pregnancy risk, patient load, registration trends and inventory status, with tables and charts. Audit logs are omitted. |
| Simplify movement receipt | Removed Connected System Records and Official Certification & Accountability from the receipt dialog and its print view. Movement route and quantity details remain. |
| Remaining batch quantities | Separates actual remaining units from received units. Allocation seed reruns preserve consumed stock instead of refilling it. |
| Excel borders | All shared workbook tables have cell borders, styled headers and wrapped content. |
| Inventory activity export | Replaced its CSV with an XLSX workbook containing Activity log and Event details sheets. |
| Long activity summaries | Added a visible View details button in the Summary column. |
| Remove raw audit display | Removed Show raw stored record from the general audit dialog. |
| Remove Detailed PDF button | Removed the page-wide Detailed PDF export; the individual-record PDF extract remains. |
| Expired open vials | A spoiled open vial holds its whole batch from admin dispensing until manual disposal is recorded. Use is hidden, the batch is excluded from the picker, and old form/direct-use actions are guarded. The Alert Hub and discard dialog retain the spoiled dose count. A local clock updates controls at expiry without new database polling. The prepared RPC guard prevents silent automatic write-offs; manual disposal logs the officer, reason/witness and wasted doses while preserving sealed stock. No cron job is used. |
| Infant immunization status | Restored birthdate and coverage_status to the cached query; classification no longer falls into missing-data status because the selected field was omitted. Existing inspected birthdate rows were populated. |
| Drive chart label overlap | Twelve drive values remain; short numbered dates, at most six visible axis labels and full hover details keep the small chart readable. |
| General QA cleanup | Applied on 2026-10-07: removed the 14 approved @qa.test accounts, 3 Codex QA catalogue items, 77 QA batches, 9 QA requests and 5 QA transfers with their dependent fixtures. All 32 other accounts were verified present, and transaction assertions verified ordinary stock rows unchanged. Unrelated children are retained regardless of their name. |
| QA facilities | Applied on 2026-10-07: removed the five Codex QA facilities (11, 12, 13, 14, 16) from both `bhc` and `health_facilities`, plus 75 unused synthetic revision batches and their receipts at those facilities. All 32 accounts and other facilities/stock were preserved. The reusable `22_remove_qa_facilities.sql` guards operational dependencies and consumed stock. |
| Remaining QA history | Applied on 2026-10-07: inspected all 63 public tables, Auth users and Storage; removed 172 explicitly marked QA audit entries and 3 sent emails to QA addresses. The final scan found no meaningful QA/Codex markers. Embedded image data and credentials were excluded from marker matching. A live rollback trial and commit verified all other public rows unchanged, except normal audit refresh notifications. All 32 accounts, 11 facilities, 16 lab-test rows and 10 ultrasound rows remain. |

## Database application

Run from the repository root in your own PowerShell terminal:

```powershell
.\scripts\apply-final-revisions.ps1 -IncludeDemoActivity
```

The password prompt hides typing. A public-schema backup is taken before cleanup.
The activity option adds fictional dispensing through the existing RPC without
creating patient visits. Omit `-IncludeDemoActivity` to apply cleanup and the disposal guard
without the extra demonstration stock.

The user chose mandatory manual disposal instead of background automation.
The proposed expiry job was never activated, and its setup files were removed.
This revision adds no scheduled database reads or Edge Function calls. Ordinary
data refreshes and the user's confirmed discard still use the existing database
workflows. Healthy batches of the same item remain usable; only the affected
batch is held. Once its discard is confirmed, sealed stock is released for use.

## Validation completed

- Admin regression suite, including exports, audit redaction, alerts, transfers,
  download preparation, responsive navigation and expiry calculations.
- Actual XLSX serialization checked with OpenXML/openpyxl for four-sided borders,
  wrapped newlines, numeric quantities and preserved leading-zero identifiers.
- Revised turnout chart rendered in headless Edge at 1440 px and 800 px.
- Actual dashboard PDF generated, text checked and all three sample pages rendered.
- Actual manual-disposal SQL tested for preserved permissions, exact expiry
  limits, blocked use without silent write-offs, valid-dose dispensing, required
  officer/reason, sealed-stock preservation, repeat safety and ledger rollback.
- Local expiry timer tested for blocking an already-open form without network
  access or automatic stock changes.
- Batch countdown sorting and the open-vial monitor put spoiled or unverified
  open doses first. Expired filters include these pools even when sealed stock
  expires later; upcoming-expiry filters use the earlier vial/batch deadline.
  Regression checks cover exact limits, pagination, facility scope, normal
  column sorting and release from the priority group after confirmed discard.
- The batch Discarded filter includes recorded open-dose and stock losses as
  well as fully discarded batches. Rows identify the loss and link to the
  latest discard details while retaining the correct sealed-stock status.
  The ledger's All Discards & Disposals filter and Stock Out include dose-only
  losses with zero sealed-unit movement; legacy vial losses retain dose units.
- Actual cleanup/activity SQL executed in isolated PostgreSQL: protects non-QA
  records, preserves existing quantities, skips repeated events, reconciles ledger
  balances and creates a definite previous-month consumption peak.
- QA history cleanup tested for nested markers, image/credential exclusions,
  preserved ordinary records, repeat safety and blocked downstream foreign keys.

The QA cleanup is complete; the dispensing guard and optional demonstration
activity remain pending. The scoped QA inventory snapshot is saved locally
under the gitignored `database/backups/qa-cleanup-20261007/` directory. It is
an inventory snapshot, not a complete clinical or account backup.
The same directory contains a metadata-only review snapshot of the selected QA
audit/email entries; it does not contain full email bodies or clinical images.
