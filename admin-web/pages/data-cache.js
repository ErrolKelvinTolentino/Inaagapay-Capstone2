/* =====================================================
   InaAgapay Admin Web — Shared Read Layer

   Every protected page used to answer "what is on this screen?" the same way:
   pull the whole table with select("*"), then throw most of it away in
   JavaScript. Reports alone read mothers, accounts, pregnancies, children,
   immunization_records, child_growth_records, inventory_items and
   inventory_batches in full — and AdminLiveRefresh re-ran the lot once a
   minute, per open tab. That is what put the project over its Supabase egress
   allowance; it was never the number of users.

   Three things fix it, and they live here so no page has to remember them:

     columns   — a named projection per table. A mother row is far smaller when
                 the query names the dozen columns a report actually reads. The
                 account projection also stops password_hash, reset_code and
                 last_login_token from ever leaving the database, which was a
                 worse problem than the bytes.

     scoping   — .in("assigned_bhc_id", ids) instead of fetching the whole
                 municipality and filtering client-side. An RHU reading its own
                 reports downloaded every other RHU's patients to discard them.

     caching   — one in-flight promise and one short-lived result per query key.
                 A realtime tick on `accounts` no longer re-reads every batch in
                 the warehouse; only caches that name `accounts` as a source are
                 dropped.

   Pages call read()/rows() and get plain arrays back. Nothing here changes what
   a page displays — only how much of the database it has to move to display it.
   ===================================================== */

(function (root) {
  "use strict";

  // Long enough that a realtime burst (five row changes in one save) collapses
  // into a single read, short enough that a human clicking Refresh sees fresh
  // data. Realtime invalidation is what actually keeps pages current; the TTL
  // is only a floor under repeated reads.
  const DEFAULT_TTL_MS = 45 * 1000;

  // PostgREST builds one URL per request and servers cap its length. A BHC id
  // list is small, but the child/mother id lists used to narrow a second table
  // are not, so those are chunked rather than sent whole.
  const IN_CHUNK_SIZE = 150;

  // key -> { at, ttl, value, promise, tables }
  const cache = new Map();

  /* ── Column projections ──────────────────────────────────────────────
     One place that answers "which columns does the portal actually read?".
     Anything not listed here is not displayed anywhere, and paying egress for
     it is waste. Add a column when a page starts showing it, not before.
  */
  const COLUMNS = {
    // No password_hash, no reset_code, no verification_code, no
    // last_login_token. Those must never reach a browser, and select("*") was
    // sending all four on every account read.
    accounts:
      "account_id, first_name, middle_name, last_name, extension_name, " +
      "email_address, phone_number, account_type, status, is_verified, " +
      "is_temporary_password, created_at, last_login_at",

    accounts_min: "account_id, first_name, last_name, account_type, status",

    mothers:
      "mother_id, account_id, assigned_bhc_id, birthdate, barangay, " +
      "philhealth_status, philhealth_number, is_four_ps, status, " +
      "gravida, para, living_children",

    midwives: "midwife_id, account_id, assigned_bhc_id, license_number, position",

    // expected_date_of_delivery, not expected_due_date. Report code has been
    // reading the latter — a column that exists in no migration — so the
    // trimester split fell back to 0 weeks and filed every ongoing pregnancy
    // as first trimester. last_menstrual_period is here because it dates a
    // pregnancy when the EDD has not been recorded.
    pregnancies:
      "pregnancy_id, mother_id, status, pregnancy_risk_level, " +
      "expected_date_of_delivery, last_menstrual_period, created_at",

    // added_at, not created_at: `children` predates the convention.
    children:
      "child_id, child_number, mother_id, assigned_bhc_id, first_name, " +
      "last_name, sex, added_at",

    child_growth_records:
      "child_details_id, child_id, measurement_date, child_weight, child_height, " +
      "weight_for_age_zscore, height_for_age_zscore, bmi_for_age_zscore",

    immunization_records:
      "immunization_record_id, child_id, vaccine_id, vaccination_date, " +
      "dose_number, status",

    inventory_items:
      "item_id, name, generic_name, item_type, unit_of_measure, " +
      "doses_per_unit, open_vial_shelf_hours, minimum_stock_threshold, is_archived",

    inventory_batches:
      "batch_id, item_id, facility_id, quantity_remaining, " +
      "doses_remaining_in_open_vial, vial_opened_at, expiration_date, status",

    vaccines:
      "vaccine_id, vaccine_name, dose_number, recommended_age_months, " +
      "target_recipients, inventory_item_id",

    child_immunization_coverage:
      "child_id, child_number, mother_id, assigned_bhc_id, sex, age_months, " +
      "age_band, birthdate, coverage_status, doses_required, doses_received, doses_overdue, " +
      "is_fully_immunized, has_bcg, has_penta1, has_penta3, has_mcv1, " +
      "missing_doses, last_dose_on",

    health_facilities:
      "facility_id, name, facility_type, facility_code, barangay, " +
      "address_street, address_detail, parent_facility_id, is_active",
  };

  /** The projection for a table, or "*" when the table has no entry yet. */
  function columns(table) {
    if (degraded.has(table)) return "*";
    return COLUMNS[table] || "*";
  }

  /* ── Projection fail-safe ────────────────────────────────────────────
     This database has no migration ledger — every file in database/migrations
     has been applied by hand, and RUN_ORDER.md records that several never were.
     So the live schema and the migrations do not always agree, and a projection
     naming a column that is missing here fails the whole query with 42703,
     which would turn a bandwidth optimisation into a blank page.

     The first time a table's projection is rejected, that table is marked
     degraded and re-read with select("*") — the exact behaviour it had before
     this file existed. The page keeps working; only the saving is lost, and the
     console says which column to correct.
  */
  const degraded = new Set();

  function isMissingColumn(error) {
    if (!error) return false;
    const code = String(error.code || "");
    if (code === "42703" || code === "PGRST204") return true;
    return /column .* does not exist|does not exist on table/i.test(
      String(error.message || "")
    );
  }

  function markDegraded(table, error) {
    if (degraded.has(table)) return;
    degraded.add(table);
    console.warn(
      "AdminData: the column list for `" + table + "` does not match this " +
      "database, so it will be read with select(\"*\"). Correct COLUMNS." +
      table + " in data-cache.js to get the saving back. " +
      (error && error.message ? error.message : "")
    );
  }

  /* ── Scope helpers ───────────────────────────────────────────────────
     PortalScope already knows which barangay health centres this office
     covers. Until now every page used it as a client-side filter, after the
     rows had already crossed the wire. These push the same rule into the query.
  */

  /** The BHC ids this office may read, or null when the scope is unresolved. */
  function bhcIds() {
    const scope = root.PortalScope;
    if (!scope || scope.ready !== true) return null;
    const list = scope.bhcFacilities || [];
    if (list.length === 0) return null;
    return list.map(function (f) { return String(f.facility_id); });
  }

  /** Every facility id in scope — BHCs, this office, and anything between. */
  function facilityIds() {
    const scope = root.PortalScope;
    if (!scope || scope.ready !== true) return null;
    const ids = scope.scopeFacilityIds || [];
    if (ids.length === 0) return null;
    return ids.map(String);
  }

  /**
   * Narrow a query to this office's health centres.
   *
   * Rows with no centre recorded have always been kept — dropping them would
   * quietly lose a patient whose assignment has not been filed yet — so the
   * filter is "mine OR unfiled", expressed as a PostgREST `or`.
   *
   * An unresolved scope returns the query untouched, which reproduces the
   * behaviour on a database that has not run 20260821_mho_tier.sql.
   */
  function scopeByBhc(query, column) {
    const ids = bhcIds();
    if (!ids) return query;
    const col = column || "assigned_bhc_id";
    return query.or(col + ".in.(" + ids.join(",") + ")," + col + ".is.null");
  }

  /** Same idea for tables keyed on a facility rather than a health centre. */
  function scopeByFacility(query, column) {
    const ids = facilityIds();
    if (!ids) return query;
    const col = column || "facility_id";
    return query.or(col + ".in.(" + ids.join(",") + ")," + col + ".is.null");
  }

  /**
   * Read a table narrowed to a list of ids, in chunks small enough for a URL.
   * Used where one already-scoped roster narrows the next table — children for
   * growth records, mothers for pregnancies — so the second read never pulls
   * the municipality either.
   */
  async function readIn(db, table, column, values, opts) {
    const options = opts || {};
    const list = [...new Set((values || []).map(String))];
    if (list.length === 0) return [];

    let select = options.select || columns(table);
    const out = [];
    for (let i = 0; i < list.length; i += IN_CHUNK_SIZE) {
      const chunk = list.slice(i, i + IN_CHUNK_SIZE);
      const run = (cols) => {
        let q = db.from(table).select(cols).in(column, chunk);
        if (options.order) {
          q = q.order(options.order, { ascending: options.ascending !== false });
        }
        return q;
      };

      let res = await run(select);
      if (res.error && isMissingColumn(res.error) && select !== "*") {
        markDegraded(table, res.error);
        select = "*";
        res = await run(select);
      }
      if (res.error) throw res.error;
      out.push(...(res.data || []));
    }
    return out;
  }

  /* ── Cache ───────────────────────────────────────────────────────────── */

  function fresh(entry) {
    return entry && entry.value !== undefined && Date.now() - entry.at < entry.ttl;
  }

  /**
   * Run `build(db)` at most once per key per TTL window.
   *
   * `tables` names what the answer depends on, so a realtime change to one
   * table drops exactly the caches built from it. Without that the page either
   * serves stale rows or re-reads everything — the two failure modes this whole
   * file exists to avoid.
   */
  function read(db, key, build, opts) {
    const options = opts || {};
    const entry = cache.get(key);

    if (fresh(entry)) return Promise.resolve(entry.value);
    if (entry && entry.promise) return entry.promise;

    const record = {
      at: 0,
      ttl: Number.isFinite(options.ttl) ? options.ttl : DEFAULT_TTL_MS,
      value: undefined,
      promise: null,
      tables: (options.tables || []).map(String),
    };
    cache.set(key, record);

    record.promise = Promise.resolve()
      .then(function () { return build(db); })
      .then(function (value) {
        record.value = value;
        record.at = Date.now();
        record.promise = null;
        return value;
      })
      .catch(function (err) {
        // A failed read must not be remembered as an empty answer, or the page
        // shows "no patients" for a whole TTL window after one dropped request.
        cache.delete(key);
        throw err;
      });

    return record.promise;
  }

  /** The common case: one scoped, projected table read, cached. */
  function rows(db, table, opts) {
    const options = opts || {};
    const select = options.select || columns(table);
    // The projection itself, not its length: two different column lists of the
    // same length would otherwise share a cache entry and serve each other's
    // rows. Callers that pass an explicit `key` never reach this.
    const key = options.key || table + ":" + (options.scope || "none") + ":" + select;

    return read(
      db,
      key,
      async function () {
        const run = (cols) => {
          let q = db.from(table).select(cols);
          if (options.scope === "bhc") q = scopeByBhc(q, options.scopeColumn);
          else if (options.scope === "facility") q = scopeByFacility(q, options.scopeColumn);
          if (options.eq) {
            Object.keys(options.eq).forEach(function (col) { q = q.eq(col, options.eq[col]); });
          }
          if (options.gte) {
            Object.keys(options.gte).forEach(function (col) { q = q.gte(col, options.gte[col]); });
          }
          if (options.order) {
            q = q.order(options.order, { ascending: options.ascending !== false });
          }
          if (options.limit) q = q.limit(options.limit);
          return q;
        };

        let res = await run(select);
        if (res.error && isMissingColumn(res.error) && select !== "*") {
          markDegraded(table, res.error);
          res = await run("*");
        }
        if (res.error) throw res.error;
        return res.data || [];
      },
      { ttl: options.ttl, tables: options.tables || [table] }
    );
  }

  /** A count without the rows. The cheapest question the database answers. */
  async function count(db, table, build) {
    let q = db.from(table).select("*", { count: "exact", head: true });
    if (typeof build === "function") q = build(q) || q;
    const res = await q;
    if (res.error) throw res.error;
    return res.count || 0;
  }

  /** Forget every cache built from any of these tables. */
  function invalidateTables(tables) {
    const names = new Set((tables || []).map(String));
    if (names.size === 0) return;
    cache.forEach(function (entry, key) {
      if ((entry.tables || []).some(function (t) { return names.has(t); })) cache.delete(key);
    });
  }

  function invalidate(prefix) {
    if (!prefix) { cache.clear(); return; }
    cache.forEach(function (entry, key) {
      if (key.indexOf(prefix) === 0) cache.delete(key);
    });
  }

  root.AdminData = {
    COLUMNS: COLUMNS,
    columns: columns,
    bhcIds: bhcIds,
    facilityIds: facilityIds,
    scopeByBhc: scopeByBhc,
    scopeByFacility: scopeByFacility,
    readIn: readIn,
    read: read,
    rows: rows,
    count: count,
    invalidate: invalidate,
    invalidateTables: invalidateTables,
    get size() { return cache.size; },
  };
})(typeof window !== "undefined" ? window : globalThis);
