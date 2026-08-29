# Inventory seed

Wipes the inventory and lays down a clean catalogue with stock on every shelf.
**Inventory only** — facilities, accounts, midwives, mothers, pregnancies,
encounters and immunisation records are not touched by any file here.

## Run in order

| File | Does |
|------|------|
| `00_reset_inventory.sql` | Clears items, batches, ledger, transfers, requests |
| `01_items_vaccines.sql` | Full DOH EPI series plus maternal Td, and relinks the schedule |
| `02_items_supplements.sql` | Prenatal and child supplements |
| `03_allocations.sql` | Stock at the warehouse, every RHU depot and every health centre, with its receipt ledger |

Each file ends with a `SELECT` showing what it did. Run it and read it.

## What the reset costs

Not nothing. The movement ledger **is** the audit trail for stock, so clearing
it discards every receipt, dispatch and dispense this database has ever held —
including the prenatal deductions and the 150-unit reconciliation.

Clinical records survive: a checkup still says which tablets were handed over.
But their link to stock is cut (`given_medications.inventory_batch_id` and
`maternal_td_records.inventory_batch_id` are set to null, because those foreign
keys are `RESTRICT` and `NO ACTION` respectively and would otherwise block the
delete outright). The stock side of that history cannot be rebuilt.

Fine for a demo database or one being prepared for a defence. Not something to
run against a live health centre.

## The three tiers

Stock flows Municipal Warehouse → RHU depot → barangay health centre, and
`03_allocations.sql` fills all three. The middle rung is the one that gets
forgotten — fill only the warehouse and the health centres and every per-RHU
figure in the municipal portal reads zero while the stock apparently teleports
past them.

| Tier | Stock |
|---|---|
| Municipal Warehouse (`facility_id IS NULL`) | 25× threshold |
| Rural Health Unit depot | 8× threshold |
| Barangay health centre | 3× threshold |

Quantities scale off each item's own `minimum_stock_threshold` rather than a
flat number. A flat 100 at a health centre sits *below* the 150–200 threshold of
every supplement, so the database would open with all five reading LOW at all
five centres and the alert hub full of warnings about stock nobody has touched.
Scaling keeps every tier above its own line, and stays right if a threshold is
edited later.

Received dates step down the chain (60 / 40 / 20 days ago) so the ledger reads
in the order the stock travelled.

**No fabricated transfers.** Each tier gets a *receipt*, not a dispatch from the
tier above. A transfer asserts that somebody issued it, somebody confirmed it,
and a source batch was drawn down to pay for it — inventing that chain would put
five facilities' worth of fictional paperwork in the audit trail.

## Re-running

`01`–`03` are all re-runnable. Items upsert on `name`; allocations are matched
by their generated `batch_number` and refreshed in place rather than stacked.

One thing to know: re-running `03` puts every seeded batch back to **full**. On a
demo database being reset that is the point, but it means running it alone
discards whatever has since been dispensed. Only batches this file created are
touched — the `MW-` / `RHU` / `BHC` prefixes are the marker — so anything
received through the portal is left alone.

## Two things worth not breaking

- **`deduct_prenatal_encounter_inventory` finds supplements by name**, matching
  `'%ferrous%'` and `'%calcium%'`. `Ferrous Sulfate + Folic Acid` and
  `Calcium Carbonate` must keep those words. Rename either and prenatal
  deduction stops finding it — the checkup still saves, the tablets still leave
  the shelf, and the count never moves. It fails silently, which is how it went
  unnoticed for the entire life of the feature.
- **`doses_per_unit` and `open_vial_shelf_hours` are load-bearing.** Leave
  `doses_per_unit` at 1 on a 20-dose BCG vial and giving one dose destroys the
  whole vial: nineteen doses leave with no record they existed. That is what
  `20260831_dose_presentation_single_source.sql` exists to prevent. The
  shelf-life figures are DOH policy — 6 hours for BCG/MR/MMR/Rotavirus, 672
  (28 days) for OPV/IPV/Td, 0 for single-dose presentations.

## Requires

The facility hierarchy must exist — `03_allocations.sql` aborts with a clear
message if `health_facilities` holds no RHU or BHC rows. Run
`migrations/20260821_mho_tier.sql` first on a database that has never had it.
