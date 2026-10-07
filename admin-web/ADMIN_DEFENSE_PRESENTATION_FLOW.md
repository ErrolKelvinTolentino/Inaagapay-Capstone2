# Admin web capstone demonstration

Use one story throughout: an officer reviews community needs, manages supplies,
acts on alerts, and checks the resulting records. Rehearse with the same office
and facility scope; explain when you change that scope.

1. **Start at the Dashboard: show why the admin needs the system.**
   Show mothers, ongoing pregnancies, children, assigned midwives and health
   centers, then the risk, patient-load, registration and stock charts.
   Say: “This is the officer's overview of the facilities under this office.
   These charts help us identify where patient demand and supply problems need
   attention.” Point to one actual finding instead of reading every number.

2. **Go to Inventory Management → Analytics: connect demand to supplies.**
   Select Tarcan, the previous month and Ferrous Sulfate + Folic Acid. Show daily
   consumption, the busiest recorded dispensing periods and the stock projection.
   Say: “Recorded dispensing gives the officer evidence for replenishment. We
   can identify a consumption peak and estimate how long current stock will last.”
   Change the item to calcium to demonstrate the filter. Explain that projections
   are run-rate estimates and the hour chart counts dispensing records.

3. **Open Stock Catalog, then Active Batches: explain what is actually held.**
   Show the catalogue's item type, unit, threshold and dose presentation. Open
   batches for the demonstrated item and compare received quantities with actual
   remaining quantities, facility location and expiry. Say: “The catalogue
   describes the item; each batch tells us where it is and how much remains.
   Dispensing reduces the batch balance and creates a movement record.”

4. **Open the Alert Hub: demonstrate an expired open-vial scenario.**
   Select the open-vial alerts and open a prepared demo batch. Show its spoiled
   dose count and that Use is unavailable, including when sealed stock remains.
   Say: “The system identifies the expired open vial and holds this batch until
   an officer records its disposal. Other healthy batches remain available.”
   Open Discard, show the reason and witnessing-officer fields, and confirm the
   discard on the prepared demo record. Show that the spoiled doses disappear
   and the remaining valid sealed stock becomes usable. Explain that this is
   an acknowledged action rather than a background write-off.

5. **Go to Distribution: demonstrate a replenishment request.**
   Open a prepared pending request and show the requesting facility, item,
   quantity and reason. Review/approve it, select a usable source batch, and
   show the destination and expected arrival. Say: “An approval authorizes
   replenishment. Dispatch and receipt are separate steps, so supplies in
   transit are distinguishable from supplies already available at the center.”
   Show a prepared pending-receipt transfer and, if rehearsed, confirm its receipt.

6. **Go to Audit & Disposal Log: prove that the actions are traceable.**
   Find the demonstrated dispense, transfer or discard. Use View details to show
   the full written account, officer, timestamp, quantities and movement route.
   Say: “The action has a permanent record, so the officer can explain the stock
   change and review who performed it.” Export the Activity Excel workbook and
   show the separate summary and details sheets with readable table borders.

7. **Go to Reports & Analytics: explain community outcomes.**
   Show maternal risk and child immunization status, then open vaccination-drive
   analytics. Compare invited attendees, actual turnout, no-shows and walk-ins;
   hover a drive to show its complete date, facility and vaccine information.
   Say: “These reports help us identify follow-up needs and assess outreach.
   Attendance measures a drive's participation; immunization coverage measures
   recorded dose completion for eligible children.” Point to a specific gap and
   explain the corresponding follow-up scenario.

8. **Show Midwife Assignment and Account Management: connect findings to staff.**
   Show which midwives cover each facility and compare that with patient load.
   Use a prepared staff record if demonstrating reassignment. Show account roles
   and status controls. Say: “The officer can organize staffing and manage who
   has access to the platform, based on the needs shown in the reports.”

9. **Return to the Dashboard and export the System Summary.**
   Show that the PDF contains scoped health and operations indicators with tables
   and charts. Say: “We have followed one complete administrative workflow:
   review needs, manage stock, act on alerts, and verify the resulting records.
   The officer can now use this summary for reporting and planning.”

## Rehearsal data

Apply the prepared database revisions before expecting the live values to change.
The targeted cleanup removes explicit QA fixtures. The optional activity seed
adds fictional dispensing without asserting patient visits or resetting stock.
For an October 2026 rehearsal, its Tarcan iron fixture supplies 1,800 September
units, a 360-unit September 15 peak and 180 October units after October 6.
Existing movements contribute to the displayed totals too.

Prepare one expired open vial, one healthy comparison batch, one pending request
and one pending-receipt transfer. Use only the rehearsed demo records for actions
that change stock. After disposal, that expired-vial example is consumed; use a
fresh prepared example for the next rehearsal. Check the exact filters and actual
totals before speaking, and explain zero values when no activity occurred.
