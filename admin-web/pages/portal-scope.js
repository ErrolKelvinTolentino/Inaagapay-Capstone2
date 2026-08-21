/* =====================================================
   InaAgapay Admin Web — Portal Scope

   One set of pages serves two tiers:

     Municipal Health Office  (account_type = "mho")
       depot   : the municipal warehouse, inventory_batches.facility_id IS NULL
       children: the four Rural Health Units
       reach   : every facility in the municipality

     Rural Health Unit        (account_type = "admin")
       depot   : that RHU's own facility_id
       children: the barangay health centres reporting to it
       reach   : itself and its BHCs

   Everything either tier can do is the same; what differs is the depot it draws
   from, the facilities it hands stock to, and the rows it may see. Pages read
   that from window.PortalScope rather than hardcoding "Central Warehouse" and
   "BHC".
   ===================================================== */

(function () {
  "use strict";

  const SESSION_KEY = "inaagapay_admin_session";
  const SCOPE_KEY = "inaagapay_portal_scope";

  function readSession() {
    try {
      return JSON.parse(localStorage.getItem(SESSION_KEY));
    } catch (e) {
      return null;
    }
  }

  function readCachedScope() {
    try {
      return JSON.parse(localStorage.getItem(SCOPE_KEY));
    } catch (e) {
      return null;
    }
  }

  // Used before the context RPC has answered, and on a database that has not run
  // 20260821_mho_tier.sql yet. Treating an un-migrated database as a single RHU
  // whose depot is the old central warehouse reproduces the previous behaviour
  // exactly, so the portal keeps working either way.
  function fallbackScope(session) {
    const isMho = session && session.account_type === "mho";
    return {
      ready: false,
      role: isMho ? "mho" : "rhu",
      account_type: (session && session.account_type) || "admin",
      account_id: session ? session.account_id : null,
      facility_id: null,
      facility_name: isMho ? "Municipal Health Office" : "Rural Health Unit",
      facility_code: null,
      facility_type: isMho ? "MHO" : "RHU",
      depot_facility_id: null,
      depot_name: isMho ? "Municipal Warehouse" : "Central Warehouse",
      child_facility_type: isMho ? "RHU" : "BHC",
      child_facilities: [],
      bhc_facilities: [],
      scope_facility_ids: [],
    };
  }

  const session = readSession();
  const scope = Object.assign(fallbackScope(session), readCachedScope() || {});

  const PortalScope = {
    get role() { return scope.role; },
    get accountType() { return scope.account_type; },
    get isMho() { return scope.role === "mho"; },
    get isRhu() { return scope.role === "rhu"; },
    get ready() { return scope.ready === true; },

    /** The facility this account runs: the MHO, or one RHU. */
    get facilityId() { return scope.facility_id; },
    get facilityName() { return scope.facility_name; },
    get facilityCode() { return scope.facility_code; },

    /**
     * Where this portal's own stock sits.
     * null for the MHO, whose depot is the municipal warehouse — the same rows
     * the page has always shown as "Central Warehouse".
     */
    get depotFacilityId() { return scope.depot_facility_id; },
    get depotName() { return scope.depot_name; },

    /** "RHU" for the municipal office, "BHC" for a Rural Health Unit. */
    get childType() { return scope.child_facility_type; },
    get childTypeLabel() {
      return scope.child_facility_type === "RHU" ? "Rural Health Unit" : "Barangay Health Center";
    },
    get childTypeLabelPlural() {
      return scope.child_facility_type === "RHU" ? "Rural Health Units" : "Barangay Health Centers";
    },

    /** Facilities this portal allocates stock to. */
    get childFacilities() { return scope.child_facilities || []; },

    /** Every facility this account may read, itself included. */
    get scopeFacilityIds() { return scope.scope_facility_ids || []; },

    /**
     * The barangay health centres beneath this office, however deep — every BHC
     * in the municipality for the MHO, only its own for an RHU. Patient, midwife
     * and report screens key off `assigned_bhc_id`, so they need the leaves of
     * the tree rather than this office's immediate children.
     */
    get bhcFacilities() { return scope.bhc_facilities || []; },

    /** True when a BHC-level record belongs to this office. */
    coversBhc(bhcId) {
      if (bhcId === undefined || bhcId === null || bhcId === "") return false;
      const list = scope.bhc_facilities || [];
      if (list.length === 0) return true; // un-migrated database: show everything
      return list.some((f) => String(f.facility_id) === String(bhcId));
    },

    /**
     * Narrows a page's own {bhc_id, bhc_name} list down to this office. Pages
     * keep loading it however they already do; this only removes what is out of
     * scope, so an un-migrated database is left untouched.
     */
    filterBhcList(list) {
      if (!Array.isArray(list)) return [];
      if ((scope.bhc_facilities || []).length === 0) return list;
      return list.filter((b) => PortalScope.coversBhc(b.bhc_id ?? b.facility_id));
    },

    /** True when a batch, transaction or request belongs to this portal's depot. */
    isDepot(facilityId) {
      if (facilityId === undefined || facilityId === null || facilityId === 0) {
        return scope.depot_facility_id === null;
      }
      return String(facilityId) === String(scope.depot_facility_id);
    },

    /** True when this portal may see rows for the given facility. */
    inScope(facilityId) {
      if (facilityId === undefined || facilityId === null || facilityId === 0) {
        // Depot rows. The municipal warehouse belongs to the MHO alone.
        return scope.depot_facility_id === null;
      }
      const ids = scope.scope_facility_ids || [];
      if (ids.length === 0) return true; // un-migrated database: show everything
      return ids.map(String).includes(String(facilityId));
    },

    /** Display name for a facility id, depot included. */
    facilityLabel(facilityId, facilities) {
      if (facilityId === undefined || facilityId === null || facilityId === 0) {
        return scope.depot_name;
      }
      const list = facilities || scope.child_facilities || [];
      const hit = list.find(
        (f) => String(f.facility_id ?? f.bhc_id) === String(facilityId)
      );
      return (hit && (hit.name || hit.bhc_name)) || `Facility #${facilityId}`;
    },

    /**
     * The {bhc_id, bhc_name, barangay} list the patient, midwife and report
     * screens expect, already narrowed to this office.
     *
     * The pages used to read `health_facilities` with no type filter, which was
     * harmless while every row was a BHC. Now that the table also holds the
     * municipal office and four RHUs, the filter matters.
     */
    async loadBhcList(dbInstance) {
      const scoped = PortalScope.bhcFacilities;
      if (scoped.length > 0) {
        return scoped.map((f) => ({
          bhc_id: f.facility_id,
          bhc_name: f.name,
          barangay: f.barangay || null,
        }));
      }

      try {
        const { data } = await dbInstance
          .from("health_facilities")
          .select("facility_id, name, barangay")
          .eq("facility_type", "BHC")
          .order("name");
        if (data && data.length > 0) {
          return data.map((f) => ({
            bhc_id: f.facility_id,
            bhc_name: f.name,
            barangay: f.barangay || null,
          }));
        }
      } catch (e) {
        console.warn("health_facilities read failed:", e.message || e);
      }

      // Legacy schema, before facilities were unified.
      try {
        const { data } = await dbInstance.from("bhc").select("bhc_id, bhc_name, barangay").order("bhc_name");
        return data || [];
      } catch (e) {
        return [];
      }
    },

    raw() { return scope; },

    /**
     * Ask the database who this account is and what sits under it.
     * Falls back silently when 20260821_mho_tier.sql has not been applied.
     */
    async refresh(dbInstance) {
      if (!dbInstance || !session || !session.account_id) return scope;
      try {
        const { data, error } = await dbInstance.rpc("admin_portal_context", {
          p_account_id: session.account_id,
        });
        if (error) throw error;
        if (!data || data.success !== true) return scope;

        Object.assign(scope, data, { ready: true });
        localStorage.setItem(SCOPE_KEY, JSON.stringify(scope));
      } catch (e) {
        // PGRST202 / 42883 simply mean the MHO migration has not been run here.
        console.warn("Portal scope unavailable, using single-RHU defaults:", e.message || e);
      }
      return scope;
    },

    clear() {
      localStorage.removeItem(SCOPE_KEY);
    },

    /**
     * Label the chrome for the active tier and expose the MHO-only pages.
     * Safe to call before refresh(); call it again afterwards to fill in the
     * facility name once it is known.
     */
    applyChrome() {
      const portalLabel = PortalScope.isMho ? "MHO Portal" : "RHU Portal";

      document.querySelectorAll(".header-badge").forEach((el) => {
        el.textContent = portalLabel;
      });

      // Footers and body copy that name the tier in prose, rather than the
      // header chip that .header-badge already covers.
      document.querySelectorAll("[data-portal-label]").forEach((el) => {
        el.textContent = portalLabel;
      });

      document.querySelectorAll("[data-portal-facility]").forEach((el) => {
        el.textContent = scope.facility_name || portalLabel;
      });
      document.querySelectorAll("[data-portal-depot]").forEach((el) => {
        el.textContent = scope.depot_name;
      });
      document.querySelectorAll("[data-portal-child-plural]").forEach((el) => {
        el.textContent = PortalScope.childTypeLabelPlural;
      });

      // Facilities management belongs to the municipal office.
      document.querySelectorAll("[data-mho-only]").forEach((el) => {
        el.style.display = PortalScope.isMho ? "" : "none";
      });
      document.querySelectorAll("[data-rhu-only]").forEach((el) => {
        el.style.display = PortalScope.isRhu ? "" : "none";
      });

      injectFacilitiesNav();
    },
  };

  // The Facilities page only makes sense for the municipal office, and adding it
  // here keeps the eight page sidebars identical.
  function injectFacilitiesNav() {
    if (!PortalScope.isMho) return;
    const inventoryLink = document.querySelector('.sidebar-nav a[href="inventory.html"]');
    if (!inventoryLink) return;
    const list = inventoryLink.closest("ul");
    if (!list || list.querySelector('a[href="facilities.html"]')) return;

    const li = document.createElement("li");
    li.innerHTML =
      '<a href="facilities.html"><i class="fa-solid fa-hospital"></i> Rural Health Units</a>';
    list.insertBefore(li, inventoryLink.closest("li").nextSibling);

    if (window.location.pathname.endsWith("facilities.html")) {
      li.querySelector("a").classList.add("active");
    }
  }

  window.PortalScope = PortalScope;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => PortalScope.applyChrome());
  } else {
    PortalScope.applyChrome();
  }
})();
