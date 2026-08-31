# Seeds

Three unrelated seeds live here. They share nothing, and only the two Tarcan
files depend on each other — `11` needs the mothers `10` creates.

| Seed | Files |
|------|-------|
| **Inventory** — a clean catalogue with stock on every shelf | `00_` … `03_` |
| **Tarcan vaccination drives** — ten families and a year of drives, for the drive analytics | `10_tarcan_drive_scenario.sql` |
| **Tarcan child immunization** — older siblings with complete and incomplete histories, for the coverage rate | `11_tarcan_child_immunization.sql` |

---

# Inventory seed  (`00_` … `03_`)

Wipes the inventory and lays down a clean catalogue with stock on every shelf.
**Inventory only** — facilities, accounts, midwives, mothers, pregnancies,
encounters and immunisation records are not touched by any of the numbered `0x`
files.

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

---

# Tarcan vaccination drives  (`10_tarcan_drive_scenario.sql`)

Ten mothers and their infants at Tarcan BHC, and five vaccination drives —
four already held and one still to come — so that **Reports & Analytics →
Vaccination Drive Analytics** has real turnout to report rather than an empty
table.

Every child is at least six weeks old on the date of the first drive, so all
ten are genuinely eligible for the vaccine that drive offers. Two of the drives
have no-shows, one has a walk-in, and one is a maternal Td drive, so the
turnout, no-show and walk-in columns each show something.

Doses are administered by the existing `midwife.tarcan@inaagapay.com` account.
**No account is created for the portal.**

## Stock really moves

Every dose goes through `deduct_immunization_stock()` or
`administer_maternal_td_dose()` — the same functions the midwife's phone calls —
rather than being written straight into the table, so the drive analytics and
the inventory ledger agree with each other. A dose that cannot be paid for
raises and rolls the whole seed back.

The file lays down its own delivery first: three `DRIVE-TARCAN-` batches
received **1 Jun 2026**, before the first drive. Tarcan already holds 100 units
of everything from `03_allocations.sql`, but those arrived 20 days ago and the
June and July drives predate them — the ledger would show a June dose drawn
from August stock. The new batches carry an earlier expiry so FEFO consumes
them first, and the `03_allocations.sql` batches are left alone. That also
survives a re-run of `03`, which only refills `MW-` / `RHU` / `BHC` batches.

Expect afterwards: Pentavalent 30 → 12, PCV 20 → 11, Td 5 vials → 4 with **3
doses left in an open vial dated 24 Aug**.

Both deduction functions hardcode `NOW()` for `logged_at` and `vial_opened_at`,
because they were written for a midwife recording a dose she has just given.
Section 7 of the file moves both back to the day of the drive — nothing else
the functions did is touched. The `audit_trail` rows are deliberately **not**
backdated: the audit trail records when a row was written, and those rows really
were written the day you ran the file.

One consequence: an opened Td vial has a 28-day shelf life. Run this more than
28 days after 24 Aug 2026 and the next Td dose at Tarcan will correctly
auto-discard the 3 doses left in that vial, and say so in the ledger.

## Requires

- `migrations/20260817_drive_invitations.sql`
- `migrations/20260821_inventory_and_td_fixes.sql` — the two deduction functions
- `migrations/20260912_vaccination_drive_analytics.sql`
- `migrations/20260913_fix_audit_account_change_type_mismatch.sql` — without it
  the audit trigger raises `42804` on every account write and not one mother can
  be created
- `seed_redesigned_accounts.sql`, for the Tarcan midwife and Tarcan BHC itself

The script aborts with a clear message if any of them is missing, and running
it twice is safe — everything is matched on a natural key and skipped when it
is already there, and a second deduction of the same record reports
`already_deducted` rather than drawing stock twice.

## Removing it

The commented block at the foot of the file deletes the ten seeded families
(their e-mail addresses all end `.tarcan@inaagapay.internal`), then the five
drives, then the `DRIVE-TARCAN-` batches. **Run them in that order** — a Td
record still pointing at a batch blocks the batch delete, because
`maternal_td_records.inventory_batch_id` has no `ON DELETE` clause. Deleting the
families does not by itself put the stock back; dropping the batches is what
does. Demo databases only.

---

# Tarcan child immunization  (`11_tarcan_child_immunization.sql`)

Gives six of the ten Tarcan mothers an **older** child, so the Immunization Rate
scorecard has children it can actually ask the question of.

## Why older children are needed

"Fully immunized" is a question about a child who has **reached twelve months**.
The ten infants from file 10 were born in March–April 2026 and are about five
months old — asking it of them would count every newborn in the barangay as an
immunization failure. These six were born in 2025 and are 14–19 months old.

| Child | Age | Sex | Doses | Status |
|---|---|---|---|---|
| Diwata Bituin | 19 mo | F | 17/17 | fully immunized |
| Emman Cuenca | 18 mo | M | 17/17 | fully immunized |
| Kiara Dalisay | 17 mo | F | 17/17 | fully immunized |
| Tomas Espiritu | 17 mo | M | 6/17 | Pentavalent dropout |
| Bianca Fajardo | 15 mo | F | 15/17 | measles gap |
| Ismael Gatchalian | 15 mo | M | 2/17 | never came back |

3 of 6 fully immunized — **50%**. The three shortfalls are deliberately
different: a dropout is a follow-up problem, a child who never returned after
his birth doses is an access problem, and a measles gap is the one that causes
outbreaks. Three boys and three girls, which with the ten infants leaves Tarcan
at eight of each so the sex breakdown is not an artefact of the seed.

## These doses draw no stock, on purpose

Every dose is `source = 'outside'` with `evidence = 'immunization_card'` — the
history a mother brings in on the child's card when she enrols. Inventing ninety
units of 2025 stock movement to pay for them would corrupt every inventory
figure on the portal to no purpose, and this is exactly the case
`20260806_immunization_record_source.sql` was written for. It also puts the
distinction the RHU reports on the screen: **coverage** counts every dose
wherever given, **doses administered** counts only what this centre delivered.
File 10 is the second number and really does move stock; this one is the first.

Dose dates are computed from each child's birthdate and the catalogue's own
`recommended_age_months`, so a "complete" history is complete by the same rule
the coverage view checks rather than by a list typed out by hand.

## Requires

- `seed/10_tarcan_drive_scenario.sql` — the ten mothers
- `migrations/20260914_immunization_coverage_and_drive_demographics.sql` — not
  needed to insert the rows, but nothing reads them until it is run

## A note on the ten infants

They stay **behind for their age**, and that is correct: they have only ever
attended drives, so they have Pentavalent and PCV and nothing else. That is a
real follow-up worklist, and it is what makes the "Behind for their age" slice
of the Infant Immunization Status chart non-empty.
