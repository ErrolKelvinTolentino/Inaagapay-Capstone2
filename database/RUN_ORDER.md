# Supabase run order — inventory & vaccine corrections

Verified against the live project `krooorixhjwygcsdoomg` on 2026-08-23 by probing
for each migration's own objects. There is no migration ledger in this project
(`supabase migration list` returns empty) — everything has been run by hand in
the SQL Editor, so this file is the record.

## Current state of the live database

| Migration | Detected by | Status |
|---|---|---|
| `20260821_mho_tier.sql` | `v_facility_tree`, `admin_portal_context`, `facility_subtree_ids` | applied |
| `20260821_inventory_and_td_fixes.sql` | `administer_maternal_td_dose` | applied |
| `20260822_dose_accounting.sql` | `inventory_transactions.dose_quantity` | applied |
| `20260823_prenatal_dispense_fixes.sql` | `deduct_prenatal_encounter_inventory` | applied |
| `20260824_inventory_integration_fixes.sql` | `announce_inventory_transfer` — **absent** | **not applied** |
| `20260825_vaccine_catalogue_corrections.sql` | IPV still reads 20 doses | **not applied** |
| `20260826_audit_trail_completeness.sql` | `audit_trail_detailed`, `audit_write` | **not applied** |
| `20260829_inventory_transfer_directions.sql` | `inventory_transfers.source_facility_id`, `cancel_inventory_transfer` | **not applied** |

## Run these, in this order

### 0. Take a backup first

Step 1 deletes every inventory item, batch, and ledger row. Supabase Dashboard →
Database → Backups.

### 1. `clean_and_seed_vaccines_supplements.sql`

Wipes and rebuilds the inventory catalogue and stock. What changed in it:

- IPV corrected to a 5-dose vial; Rotavirus added; `open_vial_shelf_hours` now
  stated for all 15 items instead of inheriting a wrong 6-hour default.
- Stock seeds to **three tiers** — Municipal Warehouse, each RHU depot, each
  BHC. The RHU rung was missing entirely, which is why every per-RHU figure in
  the municipal portal read zero.
- Quantities scale off each item's own threshold (25× / 8× / 3×) rather than a
  flat 500/100, which used to seed all five supplements below their minimum at
  all five health centres.
- The wipe no longer uses `TRUNCATE ... CASCADE`. That ignores `ON DELETE SET
  NULL` and was silently truncating `immunization_records` and
  `maternal_td_records` on every run.

### 2. `migrations/20260821_inventory_and_td_fixes.sql` — re-run

**This is the step that is easy to miss.** The seed contains its own older copy
of `deduct_immunization_stock`, so running the seed reverts the fixed version.
Re-running this migration puts it back. Nothing in it is destructive.

### 3. `migrations/20260823_prenatal_dispense_fixes.sql` — re-run

Same reason: the seed also carries an older `deduct_prenatal_encounter_inventory`.

### 4. `migrations/20260824_inventory_integration_fixes.sql` — first run

Never applied. Adds `announce_inventory_transfer`,
`tag_inventory_notification`, and `inventory_stock_requests.is_archived`.

### 5. `migrations/20260825_vaccine_catalogue_corrections.sql` — first run

Corrects IPV to 5 doses, archives the stray "Test" item, points MMR
immunizations at MMR stock instead of MR, and gives Rotavirus an inventory item.
Idempotent — safe to run again.

This must be the last of the *catalogue* steps: nothing after it rewrites dose
counts, so IPV stays at 5. Steps 6 and 7 only add audit and distribution
behaviour and never touch `inventory_items`.

### 6. `migrations/20260826_audit_trail_completeness.sql` — first run

Turns the audit trail from an action log into a record with an actor snapshot, a
module, a severity, a structured breakdown and a readable narrative, and moves
coverage from scattered hand-written inserts to triggers on the tables
themselves. Adds the `audit_trail_detailed` view the portal reads.

Requires step 4.

### 7. `migrations/20260829_inventory_transfer_directions.sql` — first run

Makes a transfer a movement between two named places instead of a delivery to
one, and lets stock travel back up the hierarchy.

- `inventory_transfers.source_facility_id` and `transfer_direction`, stamped by
  a trigger and backfilled for history. NULL source means the municipal
  warehouse, the same convention `inventory_batches.facility_id` uses.
- Upward (BHC → RHU, RHU → MHO) and lateral (BHC → BHC, RHU → RHU) transfers are
  first-class, for the brownout and cold-chain-failure cases where the point of
  moving stock is to have it used somewhere rather than spoil where it sits.
- A facility can no longer transfer to itself. The old guard compared raw
  facility ids and never fired for the depot sentinel; the new one compares
  *places*, so the municipal warehouse and the MHO facility row are correctly
  read as one shelf.
- Both ends of a transfer are now notified — issue, receipt and cancellation.
- `cancel_inventory_transfer()` does the cancel, the stock restore, the
  reversing ledger row and both notifications in one transaction. The portal
  used to do the first two as separate unguarded writes and never wrote the
  third, so the movement ledger showed stock leaving and never coming back.
- `update_inventory_transfer_delivery()` no longer requires `account_type =
  'admin'` exactly, so a municipal officer (`'mho'`) can finally re-plan the
  arrival of the dispatches they issue, and both ends are notified instead of
  only midwives at the destination — which told nobody at all when the
  destination was an RHU.

Requires step 6. Idempotent.

**Before running:** a transfer addressed to the municipal office now lands in
the warehouse (`facility_id IS NULL`) rather than against the MHO's
`health_facilities` row. If any RHU → MHO transfer was already created by hand,
check where its destination batch was filed.

## Why the order is what it is

The seed is not purely data: sections 7 and 8 define
`deduct_immunization_stock` and `deduct_prenatal_encounter_inventory`, and those
copies are older than the ones in the 2026-08-21 and 2026-08-23 migrations.
Running the seed **after** those migrations silently downgrades both functions.
Seed first, migrations after.

Step 5 is last of the catalogue steps for a different reason:
`migrations/20260819_fix_open_vial_deduction_and_linkage.sql` sets dose capacity
by name and matches IPV with `name ILIKE '%polio%'`, rewriting it to OPV's 20
doses. Nothing between 20260821 and 20260824 rewrites dose counts, so as long as
step 5 runs after them, IPV stays at 5. Steps 6 and 7 do not touch
`inventory_items` at all, so they are safe to run after it.

Steps 6 and 7 are in that order because 20260829 replaces two functions
20260826 defines — `announce_inventory_transfer` and `audit_inventory_transfer`
— and calls its helpers (`audit_write`, `audit_kv`, `audit_facility_label`).
Running them the other way round would leave the older definitions in place, and
20260829's preflight raises a clear message rather than failing halfway.

## Verify afterwards

```sql
-- Every vaccine's dose capacity and open-vial window
SELECT item_id, name, doses_per_unit, open_vial_shelf_hours, is_archived
  FROM public.inventory_items
 WHERE item_type = 'vaccine'
 ORDER BY name;
```

Expect BCG 20/6h, HepB 1/0, Penta 1/0, OPV 20/672h, **IPV 5/672h**, PCV 1/0,
Rotavirus 1/0, MR 10/6h, MMR 10/6h, Td 10/672h, and `Test` archived.

```sql
-- Every schedule row must resolve to an inventory item (no NULLs)
SELECT v.vaccine_id, v.vaccine_name, v.dose_number, i.name AS deducts_from
  FROM public.vaccines v
  LEFT JOIN public.inventory_items i ON i.item_id = v.inventory_item_id
 ORDER BY v.vaccine_id;
```

```sql
-- Stock must exist at all three tiers; RHU depot rows are the new ones
SELECT COALESCE(hf.facility_type, 'MHO WAREHOUSE') AS tier,
       COUNT(*) AS batches, SUM(b.quantity_remaining) AS units
  FROM public.inventory_batches b
  LEFT JOIN public.health_facilities hf ON hf.facility_id = b.facility_id
 GROUP BY 1 ORDER BY 1;
```

Expect 15 warehouse batches, 60 across the 4 RHU depots, 75 across the 5 BHCs —
150 total, where before there were 90 and no RHU rows at all.

```sql
-- Clinical history must survive the wipe
SELECT COUNT(*) AS immunization_records FROM public.immunization_records;
```

Non-zero. If this comes back 0, the old `TRUNCATE ... CASCADE` ran.

```sql
-- Every transfer names both ends and which way it went (step 7)
SELECT transfer_id, transfer_direction,
       public.audit_facility_label(source_facility_id)      AS moved_from,
       public.audit_facility_label(destination_facility_id) AS moved_to,
       quantity_issued, status
  FROM public.inventory_transfers
 ORDER BY transfer_id DESC LIMIT 20;
```

Nothing should read `internal` — that value exists only so the self-transfer
guard has something to name, and a real row carrying it means a self-transfer
was created before step 7 was applied.

## Note on the CLI

`supabase db push` expects migrations under `supabase/migrations/`; this project
keeps them in `database/migrations/` and has never used the CLI ledger. Running
these through the SQL Editor keeps that consistent. `supabase db dump` and
`db diff` need Docker Desktop, which is not installed on this machine.
