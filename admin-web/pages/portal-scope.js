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
      parent_facility_id: null,
      parent_facility_name: null,
      parent_facility_type: null,
    };
  }

  const session = readSession();
  const scope = Object.assign(fallbackScope(session), readCachedScope() || {});

  // facility_id -> ids of the facilities directly beneath it. Built from the
  // two lists the context RPC returns, and thrown away whenever the scope is
  // re-read so it can never describe a hierarchy that has since changed.
  let childIndexCache = null;

  // facility_id -> Set of every id in that branch. coversFacility is called
  // once per row per render — the stock matrix alone asks it 540 times — so the
  // walk is done once per branch and the answer kept, rather than rebuilt for
  // every batch. Dropped alongside childIndexCache whenever the scope changes.
  let subtreeCache = null;

  function childIndex() {
    if (childIndexCache) return childIndexCache;
    const index = {};
    const link = (parentId, childId) => {
      if (parentId === undefined || parentId === null) return;
      if (childId === undefined || childId === null) return;
      const key = String(parentId);
      const list = index[key] || (index[key] = []);
      const id = String(childId);
      if (!list.includes(id)) list.push(id);
    };
    // child_facilities carries no parent of its own: by definition those
    // facilities hang off the office this account runs.
    (scope.child_facilities || []).forEach((f) => link(scope.facility_id, f.facility_id));
    (scope.bhc_facilities || []).forEach((f) => link(f.parent_facility_id, f.facility_id));
    childIndexCache = index;
    return index;
  }

  function subtreeSet(facilityId) {
    if (!subtreeCache) subtreeCache = new Map();
    const key = String(facilityId);
    const cached = subtreeCache.get(key);
    if (cached) return cached;

    const index = childIndex();
    const seen = new Set();
    const queue = [key];
    while (queue.length > 0) {
      const id = queue.shift();
      if (seen.has(id)) continue;
      seen.add(id);
      (index[id] || []).forEach((childId) => {
        if (!seen.has(childId)) queue.push(childId);
      });
    }
    subtreeCache.set(key, seen);
    return seen;
  }

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

    /**
     * The office one rung above this one: the Municipal Health Office for an
     * RHU, nothing for the MHO itself.
     *
     * Stock moves upward as well as downward — a health centre with no power
     * sends its vaccines back up rather than watching them spoil — so the tier
     * above has to be nameable, not just the tiers below.
     */
    get parentFacilityId() { return scope.parent_facility_id; },
    get parentFacilityName() { return scope.parent_facility_name; },
    get parentFacilityType() { return scope.parent_facility_type; },
    get hasParent() {
      return scope.parent_facility_id !== null && scope.parent_facility_id !== undefined;
    },

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

    /**
     * Every facility id this one covers, itself included.
     *
     * Seen from the municipal office a Rural Health Unit is a branch, not a
     * shelf: stock sits in its own depot and in each barangay health centre
     * reporting to it. Filtering a page to one RHU therefore has to match the
     * whole branch, or the officer reads zero while four BHCs below are
     * stocked. An RHU account only ever selects leaf BHCs, where the subtree is
     * the facility itself and nothing changes.
     */
    subtreeIds(facilityId) {
      if (facilityId === undefined || facilityId === null || facilityId === "") return [];
      return Array.from(subtreeSet(facilityId));
    },

    /** True when a row filed against a facility sits under the given branch. */
    coversFacility(branchId, facilityId) {
      if (facilityId === undefined || facilityId === null || facilityId === 0 ||
          String(facilityId) === "null") {
        // Depot rows are reached through the "central" sentinel, never by
        // naming a facility below this office.
        return false;
      }
      return subtreeSet(branchId).has(String(facilityId));
    },

    /** Display name for a facility id, depot included. */
    facilityLabel(facilityId, facilities) {
      if (facilityId === undefined || facilityId === null || facilityId === 0) {
        return scope.depot_name;
      }
      // This office itself, and the office above it. Neither is in the child
      // lists, and both are now reachable as transfer endpoints.
      if (scope.depot_facility_id !== null &&
          String(facilityId) === String(scope.depot_facility_id)) {
        return scope.depot_name;
      }
      if (String(facilityId) === String(scope.facility_id)) {
        return scope.facility_name || scope.depot_name;
      }
      if (scope.parent_facility_id !== null &&
          String(facilityId) === String(scope.parent_facility_id)) {
        return scope.parent_facility_name || `Facility #${facilityId}`;
      }
      // The municipal office holds stock two levels down, so a batch can be
      // filed against a BHC that is not one of its own children. Searching the
      // leaves as well is what stops those rows reading "Facility #3".
      const pools = [facilities, scope.child_facilities, scope.bhc_facilities];
      for (const list of pools) {
        if (!Array.isArray(list)) continue;
        const hit = list.find(
          (f) => String(f.facility_id ?? f.bhc_id) === String(facilityId)
        );
        if (hit) return hit.name || hit.bhc_name || `Facility #${facilityId}`;
      }
      return `Facility #${facilityId}`;
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
        childIndexCache = null;
        subtreeCache = null;

        await loadParentFacility(dbInstance);

        localStorage.setItem(SCOPE_KEY, JSON.stringify(scope));
      } catch (e) {
        // PGRST202 / 42883 simply mean the MHO migration has not been run here.
        console.warn("Portal scope unavailable, using single-RHU defaults:", e.message || e);
      }
      return scope;
    },

    clear() {
      childIndexCache = null;
      subtreeCache = null;
      localStorage.removeItem(SCOPE_KEY);
    },

    /**
     * Label the chrome for the active tier and expose the MHO-only pages.
     * Safe to call before refresh(); call it again afterwards to fill in the
     * facility name once it is known.
     */
    applyChrome() {
      const portalLabel = PortalScope.isMho ? "MHO Portal" : "RHU Portal";
      const facilityName = String(scope.facility_name || "").trim();
      const isGenericName = !facilityName || facilityName === "Municipal Health Office" || facilityName === "Rural Health Unit";
      const headerLabel = scope.ready && !isGenericName
        ? `${PortalScope.isMho ? "MHO" : "RHU"} · ${facilityName}`
        : portalLabel;

      document.querySelectorAll(".header-badge").forEach((el) => {
        el.textContent = headerLabel;
        el.title = facilityName || portalLabel;
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

  /**
   * Fill in the office above this one.
   *
   * admin_portal_context predates upward stock movement and returns only the
   * facility and everything below it, so the parent is read separately rather
   * than by re-issuing that whole function in a later migration. v_facility_tree
   * already carries the parent's name; a database without it falls back to two
   * reads of health_facilities, and one without either simply leaves the parent
   * null — which reads as "this office has nothing above it", the correct answer
   * for the MHO and a harmless one for an un-migrated RHU.
   */
  async function loadParentFacility(dbInstance) {
    if (!scope.facility_id) return;

    try {
      const { data, error } = await dbInstance
        .from("v_facility_tree")
        .select("parent_facility_id, parent_name, parent_type")
        .eq("facility_id", scope.facility_id)
        .maybeSingle();
      if (error) throw error;
      if (data) {
        scope.parent_facility_id = data.parent_facility_id ?? null;
        scope.parent_facility_name = data.parent_name || null;
        scope.parent_facility_type = data.parent_type || null;
        return;
      }
    } catch (e) {
      // View absent (pre-20260821) or unreadable. Try the base table.
    }

    try {
      const { data: self } = await dbInstance
        .from("health_facilities")
        .select("parent_facility_id")
        .eq("facility_id", scope.facility_id)
        .maybeSingle();
      const parentId = self && self.parent_facility_id;
      if (!parentId) {
        scope.parent_facility_id = null;
        scope.parent_facility_name = null;
        scope.parent_facility_type = null;
        return;
      }
      const { data: parent } = await dbInstance
        .from("health_facilities")
        .select("facility_id, name, facility_type")
        .eq("facility_id", parentId)
        .maybeSingle();
      scope.parent_facility_id = parentId;
      scope.parent_facility_name = (parent && parent.name) || null;
      scope.parent_facility_type = (parent && parent.facility_type) || null;
    } catch (e) {
      console.warn("Parent facility lookup failed:", e.message || e);
    }
  }

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
