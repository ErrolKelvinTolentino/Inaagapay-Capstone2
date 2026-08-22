/* =====================================================
   InaAgapay Admin Web — Shared Stock Reader

   One place that answers "how much of this item is actually on the shelf".

   Stock has never lived on `inventory_items`. Quantities sit in
   `inventory_batches`, and what counts as usable depends on the batch status,
   its expiration date, and — for a multi-dose vial — how many doses are left in
   a seal that is already broken. The inventory page has always known this;
   dashboard.html and reports.html did not, and read two columns
   (`current_quantity`, `minimum_reorder_level`) that do not exist on the table.
   Reports therefore counted every item in the catalogue as a shortage and
   dashboard drew an empty chart.

   Pages register nothing and own nothing here: they call load(), then ask.
   Rows are narrowed to the caller's portal scope, so an RHU never sees another
   RHU's stock in its own reports.
   ===================================================== */

(function () {
  "use strict";

  let items = [];
  let batches = [];

  function inScope(facilityId) {
    if (!window.PortalScope) return true;
    return window.PortalScope.inScope(facilityId);
  }

  function dosesPerUnit(item) {
    return Math.max(1, parseInt(item && item.doses_per_unit, 10) || 1);
  }

  /** Doses sitting in vials at this batch whose seal is already broken. */
  function openDoses(batch) {
    return Math.max(0, parseInt(batch && batch.doses_remaining_in_open_vial, 10) || 0);
  }

  function isExpired(batch) {
    if (!batch || !batch.expiration_date) return false;
    const exp = new Date(batch.expiration_date); exp.setHours(0, 0, 0, 0);
    const today = new Date(); today.setHours(0, 0, 0, 0);
    return exp <= today;
  }

  function isDepotBatch(batch) {
    const id = batch.facility_id;
    return id === null || id === undefined || id === 0 || String(id) === "null";
  }

  function matchesFacility(batch, facilityFilter) {
    if (facilityFilter === "central") return isDepotBatch(batch);
    if (facilityFilter === "all" || facilityFilter === "" ||
        facilityFilter === null || facilityFilter === undefined) return true;
    return String(batch.facility_id) === String(facilityFilter);
  }

  const InventoryStock = {
    get items() { return items; },
    get batches() { return batches; },

    /** Read the catalogue and every batch this portal may see. */
    async load(db) {
      const [itemRes, batchRes] = await Promise.all([
        db.from("inventory_items").select("*").order("name"),
        db.from("inventory_batches").select("*").order("expiration_date"),
      ]);

      if (itemRes.error) throw itemRes.error;
      if (batchRes.error) throw batchRes.error;

      items = itemRes.data || [];
      batches = (batchRes.data || []).filter((b) => inScope(b.facility_id));
      return { items, batches };
    },

    /**
     * Usable stock for one item.
     *
     * `available` counts sealed units; `availableDoses` adds the doses left in
     * already-open vials, which quantity_remaining no longer includes — an item
     * can read 0 units and still have patients' worth of stock.
     */
    metricsFor(itemId, facilityFilter) {
      const item = items.find((i) => String(i.item_id) === String(itemId));
      const per = dosesPerUnit(item);

      const usable = batches.filter((b) =>
        String(b.item_id) === String(itemId) &&
        matchesFacility(b, facilityFilter) &&
        b.status === "active" &&
        !isExpired(b));

      const available = usable.reduce((sum, b) => sum + (b.quantity_remaining || 0), 0);
      const open = usable.reduce((sum, b) => sum + openDoses(b), 0);

      return {
        available,
        openDoses: open,
        availableDoses: available * per + open,
        dosesPerUnit: per,
        batchCount: usable.length,
      };
    },

    /**
     * The threshold this item is judged against.
     *
     * A combined view spans several shelves, so the per-facility minimum is
     * scaled by how many of them the caller is looking at.
     */
    thresholdFor(item, facilityFilter, facilityCount) {
      const base = (item && item.minimum_stock_threshold) || 50;
      const combined = facilityFilter === "all" || facilityFilter === "" ||
                       facilityFilter === null || facilityFilter === undefined;
      if (!combined) return base;
      return base * Math.max(1, facilityCount || 1);
    },

    /**
     * "out" when no dose can be given from this shelf at all, "low" at or below
     * the threshold, "ok" otherwise. Out is judged on doses, not sealed units,
     * because a location holding only an open vial can still vaccinate.
     */
    statusFor(item, facilityFilter, facilityCount) {
      const m = InventoryStock.metricsFor(item.item_id, facilityFilter);
      const min = InventoryStock.thresholdFor(item, facilityFilter, facilityCount);
      if (m.availableDoses === 0) return "out";
      if (m.available <= min) return "low";
      return "ok";
    },

    /** Catalogue-wide tally for a chart or a KPI. */
    summarize(facilityFilter, facilityCount) {
      const tally = { ok: 0, low: 0, out: 0, total: 0 };
      items.forEach((item) => {
        if (item.is_archived) return;
        tally.total++;
        tally[InventoryStock.statusFor(item, facilityFilter, facilityCount)]++;
      });
      return tally;
    },

    /**
     * Items at or below threshold, each with the numbers a table needs, worst
     * first so a truncated list still shows what matters.
     */
    shortages(facilityFilter, facilityCount) {
      return items
        .filter((item) => !item.is_archived)
        .map((item) => {
          const status = InventoryStock.statusFor(item, facilityFilter, facilityCount);
          if (status === "ok") return null;
          const m = InventoryStock.metricsFor(item.item_id, facilityFilter);
          return {
            item,
            status,
            name: item.name || "Unnamed item",
            itemType: item.item_type || "supply",
            unit: item.unit_of_measure || "units",
            available: m.available,
            availableDoses: m.availableDoses,
            dosesPerUnit: m.dosesPerUnit,
            threshold: InventoryStock.thresholdFor(item, facilityFilter, facilityCount),
          };
        })
        .filter(Boolean)
        .sort((a, b) => (a.availableDoses - b.availableDoses) || a.name.localeCompare(b.name));
    },

    /** "8 vials (78 doses)" for a multi-dose item, "8 tablets" for the rest. */
    describe(row) {
      if (row.dosesPerUnit <= 1) return `${row.available} ${row.unit}`;
      return `${row.available} ${row.unit} (${row.availableDoses} dose${row.availableDoses === 1 ? "" : "s"})`;
    },
  };

  window.InventoryStock = InventoryStock;
})();
