# Admin web capstone demonstration data plan

Status: planning only. No seed has been executed and no connected database has been inspected or changed for this plan. Numbers below are proposed fixture targets, not verified current totals.

## Presentation story and scope

Use an RHU administrator with Tarcan BHC and two other existing BHCs under the SAME RHU. Resolve their IDs and parent relationships from health_facilities; do not assume IDs or create a contradictory hierarchy. If Tarcan's RHU has fewer than three BHCs, adapt the comparison or choose another existing RHU. A Municipal Health Officer can additionally demonstrate the municipal warehouse and RHU comparison.

The main story: Tarcan has strong recorded demand for prenatal supplements, is almost out of iron tablets, and has a pending replenishment request. The RHU has sufficient stock. Review the request, approve it, dispatch stock, explain pending receipt, and show a previously received transfer or confirm receipt through the authorized receiving account. Then inspect movement history and analytics.

Keep independent examples for expiry, vaccine wastage, growth monitoring, and staff assignment so completing the main scenario does not remove every useful record.

## Dates and filters

For a defense on 7 October 2026:

- Full reporting month: 1–30 September 2026. Use this for consumption and reorder discussion.
- Recent activity: 1–7 October 2026. Include dispensing so the default October view is populated.
- Enrollment trend: April–September 2026, plus a few October records. Verify the six-month chart's actual window at rehearsal.
- Use Asia/Manila (+08:00), matching Asia/Singapore, for seed timestamps and rehearsal browser timezone. Spread dispensing between 08:00 and 16:30, with a clear 09:00–11:00 peak.
- Avoid local midnight and month boundaries: the UI filters raw logged_at strings by YYYY-MM but plots dates/hours in local browser time.
- Anchor live alerts to the actual defense date. Recalculate upcoming expiry, overdue delivery, and opened-vial ages if the defense moves.

## Why charts can remain zero

Inventory Daily Peak Consumption sums abs(quantity) for transaction_type = 'dispense' in the selected month/facility/item. Receipts, stock additions, requests and transfers do not populate it. The hourly chart counts dispensing transaction rows by hour; its label is visits, but it does not deduplicate multiple item rows belonging to the same clinical encounter.

Single-dose vaccines and tablets provide straightforward unit examples. Multi-dose vaccines can legitimately have quantity = 0 when a dose comes from a previously opened vial; dose_quantity can still be nonzero. Preserve this distinction. Do not change quantity to invent unit consumption. Use Ferrous Sulfate + Folic Acid for the daily consumption demonstration and dose_quantity for vaccine administration/wastage.

Monthly projections use selected-month dispensing / 30 and CURRENT available stock. They are simple run-rate estimates, not a trained forecasting model or a reconstructed month-end stock figure. The implementation uses a 14-day lead time, a seven-day safety buffer, and a 60-day target. If usage is absent it falls back to the threshold; a projection in that case does not prove historical dispensing exists.

Inventory Analytics' month/facility controls do not govern every subpanel. Open-vial/wastage uses the global inventory facility selector and loaded movement history, without a selected-month filter. Pediatric demographics queries child records separately without applying the analytics selector. Check each panel's actual scope before claiming that a filter changes it.

## Clinical and workforce fixture targets

Targets apply to an isolated demo scope; existing records would change totals.

| Metric | Tarcan | BHC B | BHC C | Total |
|---|---:|---:|---:|---:|
| Registered mothers | 28 | 20 | 12 | 60 |
| Ongoing pregnancies | 18 | 12 | 6 | 36 |
| High-risk ongoing pregnancies | 6 | 3 | 1 | 10 |
| Children | 20 | 16 | 12 | 48 |
| Children eligible for full-immunization metric | 12 | 8 | 4 | 24 |
| Fully immunized eligible children | 9 | 4 | 3 | 16 |
| Assigned active midwives | 2 | 1 | 1 | 4 |

Keep one extra active midwife unassigned for the live assignment demonstration. Mothers can have older children and a current pregnancy; model those relationships rather than equating child count to mother count. Set pregnancy trimester dates, risk classification and account/facility relationships consistently.

For immunization, birthdates and required vaccine schedules must produce eligibility in the actual coverage view. This implementation excludes children younger than 12 months from the full-immunization denominator. Construct complete histories from the current vaccine schedule, and incomplete histories with understandable gaps. The fixture's expected 16/24 = 66.7% is conditional on those exact eligible records and the selected scope.

Historical doses documented on an external immunization card should use the supported outside-source history path and should not consume present stock. Doses administered in the demo facility must use the clinical inventory deduction workflow.

Distribute patient enrollment across months and facilities. Include varying trimester, age, PhilHealth and 4Ps categories. Keep clinic visit dates after enrollment and within the associated pregnancy or child's lifetime.

Give each child at least one valid growth measurement; give about twelve children three measurements to show monitoring history. Include several flagged growth cases and mostly normal cases. Derive z-scores using the app's existing age/sex reference calculation; do not invent z-scores independently of weight and height. Growth flags can overlap in one child, so their counts should not be added as mutually exclusive groups.

## Inventory fixtures and expected results

### Main reproducible iron-tablet scenario

Use the existing catalogue name Ferrous Sulfate + Folic Acid and actual tablet units. Preserve its threshold and clinical name matching.

- A Tarcan batch received on 31 August: 2,130 tablets, expiring comfortably after the defense.
- September: 30 recorded dispensing events of 60 tablets each, totaling 1,800 tablets. These are synthetic recorded quantities for a demo, not prescribing guidance.
- September 15: six events, totaling 360 tablets; spread the other 24 events across eleven other clinic dates, with no day exceeding five events. This creates a definite daily peak.
- October 1, 2 and 6: one event each of 60 tablets, totaling 180 tablets.
- Current Tarcan balance: 2,130 - 1,800 - 180 = 150 tablets, below the existing 200-tablet catalogue threshold.
- RHU depot: 6,000 usable tablets available before the demonstration, backed by receipts and balances.
- Pending Tarcan request: 1,200 tablets, submitted October 6 with a clear replenishment reason.

At Tarcan with September selected, the existing run-rate formula should yield 1,800 / 30 = 60 tablets/day; current coverage 150 / 60 = 2.5 days; reorder point max(200, 60 x 21) = 1,260; target stock 60 x 60 = 3,600; recommended order 3,600 - 150 = 3,450. This reorder recommendation and the 1,200-tablet internal transfer are different quantities serving different horizons.

After dispatch, the depot should hold 4,800 tablets; 1,200 should be pending receipt; Tarcan should still hold 150. After receipt, Tarcan should hold 1,350, or 22.5 days at the September run rate. Use supported transfer receipt logic; do not count pending supplies as available at the destination.

These quantities are TOTAL desired facility/item balances. Adding a small special batch to a facility already holding thousands of tablets will not create a shortage because the portal sums all usable batches. Inspect existing data first. Build a separate controlled demo database/scope where necessary; do not silently reduce unrelated stock or reset a shared database.

### Supporting inventory stories

| Fixture | Purpose |
|---|---|
| Calcium dispensing across at least ten September clinic dates and several October dates | A second item with real usage, healthy current cover and a readable item filter |
| One item at zero usable doses in BHC B, while the RHU has stock | Demonstrates a local shortage despite healthy combined totals |
| Healthy items at BHC C | Makes facility comparisons meaningful |
| One usable batch expiring 10–20 days after defense | Near-expiry alert and prioritization |
| One expired batch awaiting recorded disposal | Independent disposal demonstration; not counted as usable |
| One previously completed disposal with reason and dose/unit effects | Movement and disposal history |
| One transfer awaiting receipt within its expected arrival | Normal in-transit tracking |
| One transfer overdue by at least two days, with a still-usable batch | Delayed-transfer alert |
| One received transfer and one rejected request | Completed and alternative workflow states |
| One open Td vial within its configured lifetime | Open-vial tracking with usable remaining doses |
| A separate open vial past its configured lifetime | Alert and discard demonstration; recalculate relative to rehearsal time |
| One recorded cold-chain excursion | Show a recorded safety flag and dispatch restriction; do not claim live temperature sensing |
| One posted physical count, system 100 vs counted 98 on a separate supplies batch | Explains a -2 variance and the recorded adjustment |

For a small vaccine-wastage fixture, administer 18 Td doses from two configured ten-dose vials and record the two remaining doses as an end-of-session discard through the supported workflow. In an isolated Td fixture, 2 / (18 + 2) = 10% wastage. Other vaccine movements change the broader displayed rate; compute the expected aggregate instead of promising 10% everywhere. Preserve doses_per_unit, opened-vial timestamps, sealed-unit balance and dose balance.

## Vaccination drives

Prepare two completed child drives and one upcoming drive, plus a completed maternal drive if useful. Example child drive: ten invited, eight invited attendees, two no-shows, one walk-in; nine vaccinated recipients if each received the offered vaccine. Choose age-appropriate vaccines and intervals from the existing schedule. Invitations, actual recipients, dose records and stock deductions must agree. Attendance is not interchangeable with vaccination coverage.

## Implementation order

1. Inventory the existing demo environment and take a baseline of counts, batches, balances, relationships and installed migrations. This plan has not performed that audit.
2. Choose one RHU scope; resolve facilities and actor accounts. Tag every new fixture with a unique DEMO-DEFENSE namespace and produce an ID manifest.
3. Add/reuse synthetic families, pregnancies, children and registrations without creating duplicate accounts or moving existing patients between facilities.
4. Record initial receipts before clinical use. Ensure the available receipt quantity can pay for every planned deduction.
5. Process historical clinical visits chronologically through existing deduction functions. Some functions use NOW(); any demo-only backdating must be limited to identified fixture movements and vial times, with clinical dates agreeing. Keep audit creation timestamps as the actual time the seed was run.
6. Add current requests, transfers, disposals and count sessions using the supported portal/RPC workflows. Do not write stock balances and ledger rows independently.
7. Add older external immunization histories, computed growth measurements, invitations and drives with consistent eligibility and dates.
8. Verify all expected totals and record the exact screen filters in a rehearsal checklist.

Make any eventual seed repeatable: unique fixture keys, skip already processed clinical doses, and abort on missing prerequisites. Do not rerun baseline allocation scripts over consumed seeded batches. Do not call 00_reset_inventory.sql as an automatic preparation step.

## Existing seed reuse

- 10_tarcan_drive_scenario.sql already creates linked clinical dose and inventory activity, but uses June–August 2026 drive dates. It will not fill October consumption simply by existing.
- 11_tarcan_child_immunization.sql demonstrates complete/incomplete outside-source histories. Reuse its approach to schedule-based coverage.
- 20260916_seed_tarcan_child_growth.sql derives consistent measurements and z-scores. Reuse its calculation approach; resolve its fixture identities before adapting dates.
- scripts/replenish-inventory.mjs adds large receipt quantities. It does not create consumption and can remove low-stock/reorder scenarios if applied to the chosen demo scope.
- 00_reset_inventory.sql deletes movement history and disconnects clinical inventory links; 03_allocations.sql refills its own seeded batches. Neither should be blindly rerun to improve analytics.

## Rehearsal acceptance checklist

- September + Tarcan + iron item: 1,800 dispensed and 360 at the September 15 peak in the isolated fixture.
- October + Tarcan + iron item: 180 dispensed before the live demonstration; no future-dated dispensing.
- Hour chart has several populated time slots and a clear morning peak. Explain it as dispensing records, since the implementation counts rows.
- Tarcan current iron stock is 150 before dispatch/receipt; depot stock is sufficient.
- September-based Tarcan iron coverage is about 2.5 days before receipt and 22.5 days after receiving 1,200, if no extra movement occurs.
- Facility comparisons show different patient loads, immunization histories and stock situations.
- Coverage and growth totals agree with eligible patients and latest valid measurements in the chosen scope.
- Every receipt, issue, receipt confirmation, dispense, discard and count has consistent quantities and actor/reference details.
- All stock remains nonnegative; transfers conserve stock including the in-transit bucket; sealed units and open doses reconcile separately.
- Alerts exist immediately before the defense, and disposal/approval demos do not consume every other useful scenario.
- Reloading and exporting preserve the selected reporting scope; PDF/Excel figures match the screen.

Zero is valid on dates without activity and on categories with no case. The goal is coherent evidence for the workflows being demonstrated, not a nonzero value in every cell.
