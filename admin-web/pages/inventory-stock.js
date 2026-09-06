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
  let facilities = [];

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
    if (window.PortalScope && typeof window.PortalScope.isDepot === "function") {
      return window.PortalScope.isDepot(batch.facility_id);
    }
    const id = batch.facility_id;
    return id === null || id === undefined || id === 0 || String(id) === "null";
  }

  // A named facility means its whole branch. From the municipal office a Rural
  // Health Unit is not a shelf but a subtree: its own depot plus the barangay
  // health centres it supplies. Matching only the RHU's own facility_id made
  // dashboard and report figures read zero for an RHU that had distributed its
  // stock downward. For an RHU account the children are leaves, so the subtree
  // is the facility itself and nothing changes.
  function matchesFacility(batch, facilityFilter) {
    if (facilityFilter === "central") return isDepotBatch(batch);
    if (facilityFilter === "all" || facilityFilter === "" ||
        facilityFilter === null || facilityFilter === undefined) return true;
    if (window.PortalScope) return window.PortalScope.coversFacility(facilityFilter, batch.facility_id);
    return String(batch.facility_id) === String(facilityFilter);
  }

  const InventoryStock = {
    get items() { return items; },
    get batches() { return batches; },
    get facilities() { return facilities; },

    /** Allow pages to explicitly provide their already-resolved BHC facility roster. */
    setFacilities(list) {
      if (!Array.isArray(list)) return;
      facilities = list.map((f) => ({
        id: String(f.bhc_id ?? f.facility_id ?? f.id),
        name: f.bhc_name ?? f.name ?? `Facility #${f.bhc_id ?? f.facility_id}`,
        facilityType: f.facility_type || "BHC",
      }));
    },

    /** Read the catalogue, every batch in scope, and register health facilities. */
    async load(db) {
      const [itemRes, batchRes] = await Promise.all([
        db.from("inventory_items").select("*").order("name"),
        db.from("inventory_batches").select("*").order("expiration_date"),
      ]);

      if (itemRes.error) throw itemRes.error;
      if (batchRes.error) throw batchRes.error;

      items = itemRes.data || [];
      batches = (batchRes.data || []).filter((b) => inScope(b.facility_id));

      // Resolve facilities in scope if not already set
      if (facilities.length === 0) {
        if (window.PortalScope && Array.isArray(window.PortalScope.bhcFacilities) && window.PortalScope.bhcFacilities.length > 0) {
          facilities = window.PortalScope.bhcFacilities.map((f) => ({
            id: String(f.facility_id),
            name: f.name || f.bhc_name || `Facility #${f.facility_id}`,
            facilityType: f.facility_type || "BHC",
          }));
        } else {
          try {
            const { data: facData } = await db
              .from("health_facilities")
              .select("facility_id, name, facility_type")
              .order("name");
            if (facData && facData.length > 0) {
              facilities = facData
                .filter((f) => inScope(f.facility_id) && f.facility_type === "BHC")
                .map((f) => ({
                  id: String(f.facility_id),
                  name: f.name,
                  facilityType: f.facility_type,
                }));
            }
          } catch (e) {
            // Legacy schema fallback
            try {
              const { data: bhcData } = await db.from("bhc").select("bhc_id, bhc_name").order("bhc_name");
              if (bhcData) {
                facilities = bhcData.map((b) => ({
                  id: String(b.bhc_id),
                  name: b.bhc_name,
                  facilityType: "BHC",
                }));
              }
            } catch (e2) {}
          }
        }
      }

      return { items, batches, facilities };
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
     * Inspects stock across each individual facility in scope plus depot.
     * Prevents the "Depot Illusion" where high central stock hides empty BHCs.
     */
    facilityHealthFor(itemId) {
      const item = items.find((i) => String(i.item_id) === String(itemId));
      const baseMin = (item && item.minimum_stock_threshold) || 50;
      const depotName = (window.PortalScope && window.PortalScope.depotName) || "Central Depot";

      const depotMetrics = InventoryStock.metricsFor(itemId, "central");

      const outFacilities = [];
      const lowFacilities = [];

      facilities.forEach((fac) => {
        const m = InventoryStock.metricsFor(itemId, fac.id);
        if (m.availableDoses === 0) {
          outFacilities.push({
            id: fac.id,
            name: fac.name,
            available: 0,
            availableDoses: 0,
          });
        } else if (m.available <= baseMin) {
          lowFacilities.push({
            id: fac.id,
            name: fac.name,
            available: m.available,
            availableDoses: m.availableDoses,
          });
        }
      });

      return {
        depotName,
        depotAvailable: depotMetrics.available,
        depotAvailableDoses: depotMetrics.availableDoses,
        hasDepotStock: depotMetrics.availableDoses > 0,
        outFacilities,
        outCount: outFacilities.length,
        lowFacilities,
        lowCount: lowFacilities.length,
        hasLocalShortage: outFacilities.length > 0 || lowFacilities.length > 0,
        hasLocalStockout: outFacilities.length > 0,
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
     * "out" when no dose can be given anywhere in scope.
     * "local_out" in combined views when 1+ front-line BHCs have 0 doses.
     * "low" at or below threshold (or 1+ facilities below safety minimum).
     * "ok" otherwise.
     */
    statusFor(item, facilityFilter, facilityCount) {
      const isCombined = facilityFilter === "all" || facilityFilter === "" ||
                         facilityFilter === null || facilityFilter === undefined;
      const m = InventoryStock.metricsFor(item.item_id, facilityFilter);
      const min = InventoryStock.thresholdFor(item, facilityFilter, facilityCount);

      if (isCombined) {
        // Complete municipal/scope out
        if (m.availableDoses === 0) return "out";

        if (facilities.length > 0) {
          const fHealth = InventoryStock.facilityHealthFor(item.item_id);
          if (fHealth.outCount > 0) return "local_out";
          if (m.available <= min || fHealth.lowCount > 0) return "low";
        } else {
          if (m.available <= min) return "low";
        }
        return "ok";
      }

      // Single facility view
      if (m.availableDoses === 0) return "out";
      if (m.available <= min) return "low";
      return "ok";
    },

    /** Catalogue-wide tally for a chart or a KPI. */
    summarize(facilityFilter, facilityCount) {
      const tally = { ok: 0, low: 0, out: 0, localOut: 0, total: 0 };
      items.forEach((item) => {
        if (item.is_archived) return;
        tally.total++;
        const st = InventoryStock.statusFor(item, facilityFilter, facilityCount);
        if (st === "local_out") {
          tally.localOut++;
          // In standard 3-category scorecards (Available vs Low vs Out),
          // local BHC stockout belongs with shortages (low/critical), NEVER in "ok"
          tally.low++;
        } else if (tally[st] !== undefined) {
          tally[st]++;
        }
      });
      return tally;
    },

    /**
     * Items at or below threshold or with local stockouts, each with the
     * numbers a table needs, worst first so a truncated list still shows what matters.
     */
    shortages(facilityFilter, facilityCount) {
      const isCombined = facilityFilter === "all" || facilityFilter === "" ||
                         facilityFilter === null || facilityFilter === undefined;
      return items
        .filter((item) => !item.is_archived)
        .map((item) => {
          const status = InventoryStock.statusFor(item, facilityFilter, facilityCount);
          if (status === "ok") return null;
          const m = InventoryStock.metricsFor(item.item_id, facilityFilter);
          const fHealth = (isCombined && facilities.length > 0)
            ? InventoryStock.facilityHealthFor(item.item_id)
            : null;

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
            // Clinical breakdown for point-of-care visibility
            fHealth,
            emptyFacilities: fHealth ? fHealth.outFacilities : [],
            localOutCount: fHealth ? fHealth.outCount : 0,
            lowFacilities: fHealth ? fHealth.lowFacilities : [],
            depotAvailable: fHealth ? fHealth.depotAvailable : 0,
            depotAvailableDoses: fHealth ? fHealth.depotAvailableDoses : 0,
            depotName: fHealth ? fHealth.depotName : "Depot",
            hasDepotStock: fHealth ? fHealth.hasDepotStock : false,
          };
        })
        .filter(Boolean)
        .sort((a, b) => {
          const rank = { out: 0, local_out: 1, low: 2 };
          const rA = rank[a.status] ?? 3;
          const rB = rank[b.status] ?? 3;
          if (rA !== rB) return rA - rB;
          return (a.availableDoses - b.availableDoses) || a.name.localeCompare(b.name);
        });
    },

    /** "8 vials (78 doses)" for a multi-dose item, "8 tablets" for the rest. */
    describe(row) {
      if (row.dosesPerUnit <= 1) return `${row.available} ${row.unit}`;
      return `${row.available} ${row.unit} (${row.availableDoses} dose${row.availableDoses === 1 ? "" : "s"})`;
    },

    /**
     * Public Health Logistics Reorder Point (ROP) and Lead-Time Buffer Projection.
     * Compliant with DOH AO No. 2020-0017 (Health Logistics Management).
     *
     * Formulations:
     * - Average Daily Consumption (ADC) = monthlyDispensed / 30 (or base threshold / 30 fallback)
     * - Lead Time Demand (LTD) = ADC * leadTimeDays (standard 14 days)
     * - Safety Stock Buffer (SS) = ADC * safetyDays (standard 7 days)
     * - Reorder Point (ROP) = LTD + SS = ADC * 21 days
     * - Days of Cover (DOC) = availableStock / ADC
     */
    reorderProjectionFor(item, facilityFilter, facilityCount, monthlyDispensed = 0) {
      const m = InventoryStock.metricsFor(item.item_id, facilityFilter);
      const minThreshold = InventoryStock.thresholdFor(item, facilityFilter, facilityCount);
      const leadTimeDays = 14; // Typical DOH / PHO supply replenishment lead time
      const safetyDays = 7;    // Buffer to absorb demand spikes & transit delays
      const bufferDays = leadTimeDays + safetyDays; // 21 days

      // Average Daily Consumption (ADC)
      let adc = 0;
      if (typeof monthlyDispensed === "number" && monthlyDispensed > 0) {
        adc = monthlyDispensed / 30;
      } else {
        adc = Math.max(0.33, minThreshold / 30);
      }

      // Reorder Point (ROP): minimum units that must be present to survive replenishment cycle
      const reorderPoint = Math.max(minThreshold, Math.ceil(adc * bufferDays));
      const available = m.available;
      const daysOfCover = adc > 0 ? (available / adc) : 999;

      const isCriticalLeadTime = daysOfCover <= leadTimeDays; // Will deplete before standard order arrives
      const isReorderNeeded = available <= reorderPoint || daysOfCover <= bufferDays;

      // Recommended Reorder Quantity targeting a 60-day maximum operating stock buffer
      const targetStockLevel = Math.ceil(adc * 60);
      const recommendedOrderQty = Math.max(0, targetStockLevel - available);

      const leadTimeDeficitDays = Math.max(0, leadTimeDays - daysOfCover);

      let urgency = "ok";
      if (available === 0 || m.availableDoses === 0) {
        urgency = "stockout";
      } else if (isCriticalLeadTime) {
        urgency = "critical";
      } else if (isReorderNeeded) {
        urgency = "warning";
      }

      return {
        itemId: item.item_id,
        name: item.name,
        genericName: item.generic_name || item.name,
        unit: item.unit_of_measure || "units",
        available,
        availableDoses: m.availableDoses,
        minThreshold,
        adc: parseFloat(adc.toFixed(2)),
        leadTimeDays,
        safetyDays,
        bufferDays,
        reorderPoint,
        daysOfCover: parseFloat(daysOfCover.toFixed(1)),
        isReorderNeeded,
        isCriticalLeadTime,
        leadTimeDeficitDays: parseFloat(leadTimeDeficitDays.toFixed(1)),
        targetStockLevel,
        recommendedOrderQty,
        urgency,
      };
    },

    /**
     * Projections for all active catalogue items given a monthly usage map.
     */
    reorderProjections(facilityFilter, facilityCount, usageMap = {}) {
      return items
        .filter((item) => !item.is_archived)
        .map((item) => {
          const dispensed = usageMap[item.item_id] ?? usageMap[item.name] ?? 0;
          return InventoryStock.reorderProjectionFor(item, facilityFilter, facilityCount, dispensed);
        })
        .sort((a, b) => {
          const rank = { stockout: 0, critical: 1, warning: 2, ok: 3 };
          const rA = rank[a.urgency] ?? 4;
          const rB = rank[b.urgency] ?? 4;
          if (rA !== rB) return rA - rB;
          return a.daysOfCover - b.daysOfCover;
        });
    },
  };

  window.InventoryStock = InventoryStock;
})();
