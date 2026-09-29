/* =====================================================
   InaAgapay Admin Web — Recommended Actions

   Reports has always been able to say what is true. It could not say what to
   do about it. An officer read "FIC 61%" across a municipality of 27 barangays
   and still had to work out, by hand, which barangay was dragging it down,
   which antigen those children were missing, whether there were doses on a
   shelf to give them, and which shelf.

   This module answers that. It takes the data the page has already loaded —
   nothing here issues a query — and returns a ranked list of findings, each
   with the action it implies and the evidence behind it.

   THE RULE IT FOLLOWS
   -------------------
   A recommendation is only worth printing if it is specific, sourced and
   actionable. So every one of them carries:

     where      the barangay or health centre, never "the municipality"
     finding    the number that triggered it, in plain words
     action     something a person can do on Monday morning
     evidence   the counts behind it, so the officer can check the reasoning
     feasible   whether the stock to carry out the action actually exists

   That last one is what stops this being a list of platitudes. Recommending a
   vaccination drive is easy; recommending one for the 18 children in Tarcan who
   are behind on Pentavalent, having checked that 20 doses are sitting in the
   Municipal Warehouse, is a decision. When the doses are not there the
   recommendation changes rather than disappears: request the stock first.

   THRESHOLDS
   ----------
   Not invented here. Immunisation targets are the DOH EPI/FHSIS figures the
   rest of the portal already quotes; the malnutrition cut-offs are the WHO
   prevalence thresholds used for public-health classification. Both are named
   at the point of use so a reviewer can check them.
   ===================================================== */

(function (root) {
  "use strict";

  /* ── Thresholds ──────────────────────────────────────────────────────── */

  const T = {
    // DOH national Fully Immunized Child target.
    FIC_TARGET: 95,
    // Below this a barangay is not lagging, it is failing.
    FIC_CRITICAL: 80,

    // WHO public-health significance thresholds for prevalence of stunting
    // (height-for-age < -2 SD) and underweight (weight-for-age < -2 SD).
    STUNTING_HIGH: 20,
    STUNTING_MEDIUM: 10,
    UNDERWEIGHT_HIGH: 20,
    UNDERWEIGHT_MEDIUM: 10,
    // Wasting is judged more strictly: it reflects acute, current malnutrition.
    WASTING_HIGH: 10,
    WASTING_MEDIUM: 5,

    // A barangay where more than a quarter of pregnancies are high-risk needs a
    // referral pathway looked at, not just more visits.
    HIGH_RISK_SHARE: 25,

    // Turnout below this means the invitations are not working.
    DRIVE_TURNOUT_LOW: 60,

    // Below this many children a percentage is noise, not a signal.
    MIN_COHORT: 3,

    // A barangay that is behind and has had no drive in this long is the
    // clearest case for scheduling one.
    DRIVE_STALE_DAYS: 120,
  };

  const SEVERITY_RANK = { critical: 0, warning: 1, advisory: 2 };

  /* ── Small helpers ───────────────────────────────────────────────────── */

  function pct(part, whole) {
    if (!whole) return null;
    return Math.round((part / whole) * 1000) / 10;
  }

  function plural(n, one, many) {
    return n === 1 ? one : (many || one + "s");
  }

  /** Normalises a vaccine or item name for matching across two catalogues. */
  function normalizeName(value) {
    return String(value || "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, " ")
      .trim();
  }

  /* ── Naming the same antigen in two catalogues ────────────────────────
     `vaccines` and `inventory_items` are separate tables filled in by
     different people, and they do not agree on what anything is called. The
     schedule says "Oral Polio Vaccine (OPV)"; the shelf says "bOPV". The
     schedule says "Pentavalent 2"; the shelf says "Pentavalent (DPT-HepB-Hib)".

     Substring matching on the full name therefore finds nothing, and an earlier
     version of this file reported "no matching item in the inventory catalogue"
     for antigens that were sitting in the warehouse in their thousands.

     Both sides are reduced to a canonical key instead. The patterns are ordered
     because some are prefixes of others — inactivated polio has to be tested
     before oral polio, or IPV matches "polio" first and reads as OPV.
  */
  const ANTIGEN_PATTERNS = [
    [/\bipv\b|inactivated\s*polio/, "polio-inactivated"],
    [/\bb?opv\b|oral\s*polio/, "polio-oral"],
    [/\bpcv\b|pneumococc/, "pneumococcal"],
    [/penta|dpt.*hepb|dtp.*hib/, "pentavalent"],
    [/\bmmr\b/, "mmr"],
    [/\bmcv\d?\b|measles|\bmr\b/, "measles"],
    [/\bbcg\b|calmette/, "bcg"],
    [/rota/, "rotavirus"],
    [/hep(atitis)?\s*b/, "hepatitis-b"],
    [/\btd\b|\btt\b|tetanus|diphther/, "tetanus"],
    [/influenza|\bflu\b/, "influenza"],
    [/vitamin\s*a|retinol/, "vitamin-a"],
    [/\bhpv\b|papilloma/, "hpv"],
  ];

  /**
   * The canonical antigen a name refers to, or null when it matches none of
   * the patterns above. Used on both the schedule side and the shelf side, so
   * the two can only ever be compared on equal terms.
   */
  function antigenKey(value) {
    // Drop a trailing dose number: "Pentavalent 2" and "Pentavalent 3" are the
    // same thing on a shelf.
    const cleaned = normalizeName(value).replace(/\s+\d+$/, "");
    if (!cleaned) return null;
    for (let i = 0; i < ANTIGEN_PATTERNS.length; i++) {
      if (ANTIGEN_PATTERNS[i][0].test(cleaned)) return ANTIGEN_PATTERNS[i][1];
    }
    return null;
  }

  /* ── Stock feasibility ───────────────────────────────────────────────────
     "Can we actually do this?" answered against InventoryStock, which already
     knows the batch, expiry and open-vial rules. Asked per antigen, because a
     drive that can give Pentavalent but not Measles is still worth holding —
     it just has a different invitation list.
  */

  /**
   * Doses of one item reachable for a given health centre: what sits on its own
   * shelf, plus what the depot above it could send down.
   *
   * `itemType` narrows the catalogue search. It matters because the names
   * overlap: searching the whole catalogue for "measles" is fine, but a
   * nutrition recommendation searching for "vitamin a" must not be restricted
   * to vaccines — which is exactly what an earlier version did, so every
   * stunting recommendation silently lost its supplement-stock check.
   */
  function dosesAvailableFor(antigen, facilityId, stock, itemType) {
    if (!stock || typeof stock.metricsFor !== "function") return null;
    if (!antigen) return null;
    const wanted = itemType === undefined ? "vaccine" : itemType;

    const items = (stock.items || []).filter(function (item) {
      if (item.is_archived) return false;
      if (wanted !== null && item.item_type && item.item_type !== wanted) return false;
      // Both sides through the same canonicaliser, so "bOPV" on the shelf and
      // "Oral Polio Vaccine (OPV)" on the schedule resolve to one key.
      const byName = antigenKey(item.name);
      if (byName && byName === antigen) return true;
      const byGeneric = antigenKey(item.generic_name);
      if (byGeneric && byGeneric === antigen) return true;
      // Supplements and anything else the patterns do not cover fall back to a
      // plain substring search, which is what they have always had.
      const text = normalizeName(item.name) + " " + normalizeName(item.generic_name);
      return text.indexOf(antigen.replace(/-/g, " ")) !== -1;
    });

    if (items.length === 0) return null;

    let atFacility = 0;
    let atDepot = 0;
    const itemNames = [];

    items.forEach(function (item) {
      itemNames.push(item.name);
      if (facilityId) {
        atFacility += stock.metricsFor(item.item_id, String(facilityId)).availableDoses || 0;
      }
      atDepot += stock.metricsFor(item.item_id, "central").availableDoses || 0;
    });

    return {
      itemNames: itemNames,
      atFacility: atFacility,
      atDepot: atDepot,
      total: atFacility + atDepot,
      depotName: (root.PortalScope && root.PortalScope.depotName) || "the depot",
    };
  }

  /* ── Signal 1: immunisation coverage per barangay ────────────────────── */

  function coverageFindings(ctx) {
    const out = [];
    const byFacility = new Map();

    (ctx.coverage || []).forEach(function (row) {
      const key = String(row.assigned_bhc_id || "unassigned");
      if (!byFacility.has(key)) {
        byFacility.set(key, { rows: [], eligible: 0, fic: 0, overdue: [], missing: new Map() });
      }
      const bucket = byFacility.get(key);
      bucket.rows.push(row);

      // Only children old enough to have finished the first-year schedule can
      // be counted for or against FIC. A four-month-old is not "behind".
      if (row.is_fully_immunized !== null && row.is_fully_immunized !== undefined) {
        bucket.eligible++;
        if (row.is_fully_immunized === true) bucket.fic++;
      }
      if (Number(row.doses_overdue) > 0) {
        bucket.overdue.push(row);
        String(row.missing_doses || "")
          .split(",")
          .map(function (s) { return s.trim(); })
          .filter(Boolean)
          .forEach(function (entry) {
            // An antigen the patterns do not recognise is still worth naming to
            // the officer; it simply cannot have its stock checked. Grouping it
            // under its own cleaned name keeps it in the list rather than
            // silently dropping a vaccine children are waiting for.
            const key2 = antigenKey(entry) || normalizeName(entry).replace(/\s+\d+$/, "");
            if (!key2) return;
            const seen = bucket.missing.get(key2) || { label: entry, children: 0, doses: 0 };
            seen.children++;
            seen.doses++;
            bucket.missing.set(key2, seen);
          });
      }
    });

    byFacility.forEach(function (bucket, facilityId) {
      if (facilityId === "unassigned") return;
      const place = ctx.placeName(facilityId);

      const rate = pct(bucket.fic, bucket.eligible);
      const behind = bucket.overdue.length;

      // Rank the antigens by how many children are waiting for each, so the
      // recommendation names the one that would do the most good.
      const antigens = [...bucket.missing.entries()]
        .map(function (pair) { return { key: pair[0], label: pair[1].label, children: pair[1].children }; })
        .sort(function (a, b) { return b.children - a.children; });

      /* Low FIC coverage — the headline finding, and the one that earns a drive. */
      if (rate !== null && bucket.eligible >= T.MIN_COHORT && rate < T.FIC_TARGET) {
        const severity = rate < T.FIC_CRITICAL ? "critical" : "warning";
        const top = antigens.slice(0, 3);

        // What it would take to run the drive, antigen by antigen.
        const supply = top.map(function (a) {
          const stock = dosesAvailableFor(a.key, facilityId, ctx.stock);
          return {
            antigen: a.label.replace(/\s+\d+$/, ""),
            needed: a.children,
            stock: stock,
            covered: stock ? stock.total >= a.children : null,
          };
        });

        // Three outcomes, not two. An antigen the catalogue has no item for is
        // neither covered nor short — nobody knows. Folding it in with "short"
        // produced a "Not enough stock:" panel listing nothing at all, which is
        // the one thing a feasibility check must never do.
        const ready = supply.filter(function (s) { return s.covered === true; });
        const short = supply.filter(function (s) { return s.covered === false; });
        const unknown = supply.filter(function (s) { return s.stock === null; });

        const readyLines = ready.map(function (s) {
          const where = s.stock.atFacility >= s.needed ? "on site" : "at " + s.stock.depotName;
          return s.antigen + " — " + s.needed + " " + plural(s.needed, "dose") +
                 " needed, " + s.stock.total + " available " + where;
        });
        const shortLines = short.map(function (s) {
          const gap = Math.max(0, s.needed - s.stock.total);
          return s.antigen + " — " + s.needed + " " + plural(s.needed, "dose") +
                 " needed, " + s.stock.total + " available, short by " + gap;
        });
        const unknownLines = unknown.map(function (s) {
          return s.antigen + " — no matching item in the inventory catalogue, check by hand";
        });

        let action;
        let feasibility;

        if (ready.length === 0 && short.length === 0) {
          // Nothing recognisable in the catalogue at all.
          action = "Schedule an immunization catch-up session at " + place +
                   " and confirm dose availability with the pharmacy before inviting families.";
          feasibility = {
            state: "unknown",
            note: "Stock could not be checked automatically:",
            lines: unknownLines,
          };
        } else if (short.length === 0) {
          action = unknown.length === 0
            ? "Run a vaccination drive at " + place + ". There is enough stock to cover it now."
            : "Run a vaccination drive at " + place + " — the doses that could be checked are " +
              "available. Confirm the rest with the pharmacy first.";
          feasibility = {
            state: "ready",
            note: "Doses on hand:",
            lines: readyLines.concat(unknownLines),
          };
        } else {
          action = ready.length > 0
            ? "Run a partial drive at " + place + " for " +
              ready.map(function (s) { return s.antigen; }).join(" and ") +
              ", and raise a stock request for " +
              short.map(function (s) { return s.antigen; }).join(" and ") +
              " before scheduling the remainder."
            : "Raise a stock request for " + place + " before scheduling a drive — " +
              "there are not enough doses to invite these families yet.";
          feasibility = {
            state: "short",
            note: "Not enough stock:",
            lines: shortLines.concat(unknownLines),
          };
        }

        out.push({
          id: "coverage:" + facilityId,
          severity: severity,
          domain: "Immunization",
          icon: "fa-syringe",
          place: place,
          headline: place + " is at " + rate + "% fully immunized",
          finding:
            bucket.fic + " of " + bucket.eligible + " children who have passed their first birthday " +
            "completed the schedule, against the " + T.FIC_TARGET + "% national target. " +
            (behind > 0
              ? behind + " " + plural(behind, "child", "children") + " " +
                (behind === 1 ? "is" : "are") + " currently overdue for a dose."
              : "No child is currently overdue, so the gap is in children who have already aged out."),
          action: action,
          feasibility: feasibility,
          evidence: [
            { label: "Fully immunized", value: rate + "%", tone: severity },
            { label: "Children behind", value: String(behind) },
            { label: "Most-missed antigen", value: antigens.length ? antigens[0].label : "—" },
          ],
          link: { href: "inventory.html?tab=catalog&subview=summary", text: "Check vaccine stock" },
          weight: (T.FIC_TARGET - rate) * Math.max(1, bucket.eligible),
        });
      }

      /* Overdue children in a barangay whose headline rate is acceptable.
         These are the ones a coverage percentage hides. */
      if (behind >= T.MIN_COHORT && (rate === null || rate >= T.FIC_TARGET)) {
        out.push({
          id: "overdue:" + facilityId,
          severity: "warning",
          domain: "Immunization",
          icon: "fa-user-clock",
          place: place,
          headline: behind + " " + plural(behind, "child", "children") + " overdue in " + place,
          finding:
            "Coverage here meets the target, but " + behind + " " +
            plural(behind, "child", "children") + " " + (behind === 1 ? "has" : "have") +
            " passed the recommended age for a dose they have not received" +
            (antigens.length ? ", most often " + antigens[0].label : "") + ".",
          action:
            "Give the list to the barangay health workers for home visits, and book the catch-up doses " +
            "into the next immunization day at " + place + ".",
          evidence: [
            { label: "Overdue children", value: String(behind), tone: "warning" },
            { label: "Coverage", value: rate === null ? "—" : rate + "%" },
          ],
          weight: behind * 8,
        });
      }
    });

    return out;
  }

  /* ── Signal 2: child growth per barangay ─────────────────────────────── */

  function growthFindings(ctx) {
    const out = [];
    const byFacility = new Map();

    (ctx.children || []).forEach(function (child) {
      const measurement = ctx.latestGrowth.get(String(child.child_id));
      if (!measurement) return;
      const key = String(child.assigned_bhc_id || "unassigned");
      if (!byFacility.has(key)) {
        byFacility.set(key, { assessed: 0, stunted: 0, severeStunted: 0, underweight: 0, wasted: 0 });
      }
      const bucket = byFacility.get(key);
      bucket.assessed++;

      const haz = Number(measurement.height_for_age_zscore);
      const waz = Number(measurement.weight_for_age_zscore);
      const whz = Number(measurement.bmi_for_age_zscore);

      if (Number.isFinite(haz) && haz < -2) {
        bucket.stunted++;
        if (haz < -3) bucket.severeStunted++;
      }
      if (Number.isFinite(waz) && waz < -2) bucket.underweight++;
      if (Number.isFinite(whz) && whz < -2) bucket.wasted++;
    });

    byFacility.forEach(function (bucket, facilityId) {
      if (facilityId === "unassigned" || bucket.assessed < T.MIN_COHORT) return;
      const place = ctx.placeName(facilityId);

      const stuntingRate = pct(bucket.stunted, bucket.assessed);
      const underweightRate = pct(bucket.underweight, bucket.assessed);
      const wastingRate = pct(bucket.wasted, bucket.assessed);

      /* Stunting — chronic. The action is a programme, not a clinic visit. */
      if (stuntingRate !== null && stuntingRate >= T.STUNTING_MEDIUM) {
        const severity = stuntingRate >= T.STUNTING_HIGH ? "critical" : "warning";
        const vitA = dosesAvailableFor("vitamin-a", facilityId, ctx.stock, "supplement");

        out.push({
          id: "stunting:" + facilityId,
          severity: severity,
          domain: "Child nutrition",
          icon: "fa-child-reaching",
          place: place,
          headline: stuntingRate + "% stunting in " + place,
          finding:
            bucket.stunted + " of " + bucket.assessed + " children measured here are short for their age " +
            "(height-for-age below -2 SD)" +
            (bucket.severeStunted > 0
              ? ", " + bucket.severeStunted + " of them severely (below -3 SD)"
              : "") +
            ". WHO classes " + (severity === "critical" ? "20% and above as high" : "10-19% as medium") +
            " public-health significance.",
          action:
            (bucket.severeStunted > 0
              ? "Refer the " + bucket.severeStunted + " severely stunted " +
                plural(bucket.severeStunted, "child", "children") +
                " for medical assessment, then run "
              : "Run ") +
            "a nutrition block in " + place + ": Vitamin A and iron supplementation for the measured " +
            "cohort, infant and young child feeding counselling for their mothers, and monthly " +
            "re-weighing until the next report.",
          feasibility: vitA
            ? {
                state: vitA.total >= bucket.stunted ? "ready" : "short",
                note: vitA.total >= bucket.stunted ? "Supplement stock on hand:" : "Supplement stock is short:",
                lines: [
                  vitA.itemNames[0] + " — " + vitA.total + " " + plural(vitA.total, "dose") +
                  " available, " + bucket.stunted + " " + plural(bucket.stunted, "child", "children") + " to cover",
                ],
              }
            : null,
          evidence: [
            { label: "Stunting", value: stuntingRate + "%", tone: severity },
            { label: "Children affected", value: String(bucket.stunted) },
            { label: "Severe", value: String(bucket.severeStunted), tone: bucket.severeStunted ? "critical" : null },
          ],
          link: { href: "#card-child-nutrition", text: "Open growth table" },
          weight: stuntingRate * Math.max(1, bucket.assessed) / 4,
        });
      }

      /* Wasting — acute, and the one that cannot wait for a programme. */
      if (wastingRate !== null && wastingRate >= T.WASTING_MEDIUM) {
        const severity = wastingRate >= T.WASTING_HIGH ? "critical" : "warning";
        out.push({
          id: "wasting:" + facilityId,
          severity: severity,
          domain: "Child nutrition",
          icon: "fa-weight-scale",
          place: place,
          headline: wastingRate + "% acute malnutrition in " + place,
          finding:
            bucket.wasted + " of " + bucket.assessed + " children measured are thin for their height " +
            "(BMI-for-age below -2 SD). Unlike stunting this reflects current, not past, nutrition — " +
            "it can change within weeks in either direction.",
          action:
            "Screen the " + bucket.wasted + " affected " + plural(bucket.wasted, "child", "children") +
            " with MUAC and check for oedema this month. Enrol the confirmed cases in outpatient " +
            "therapeutic feeding and re-measure fortnightly rather than at the next routine visit.",
          evidence: [
            { label: "Wasting", value: wastingRate + "%", tone: severity },
            { label: "Children affected", value: String(bucket.wasted) },
          ],
          weight: wastingRate * Math.max(1, bucket.assessed) / 3,
        });
      }

      /* Underweight, reported only where it is not already implied above. */
      if (
        underweightRate !== null &&
        underweightRate >= T.UNDERWEIGHT_MEDIUM &&
        stuntingRate < T.STUNTING_MEDIUM &&
        wastingRate < T.WASTING_MEDIUM
      ) {
        out.push({
          id: "underweight:" + facilityId,
          severity: underweightRate >= T.UNDERWEIGHT_HIGH ? "critical" : "warning",
          domain: "Child nutrition",
          icon: "fa-scale-unbalanced",
          place: place,
          headline: underweightRate + "% underweight in " + place,
          finding:
            bucket.underweight + " of " + bucket.assessed + " children measured are below -2 SD " +
            "weight-for-age, without a matching stunting or wasting signal — which usually points at " +
            "feeding practice rather than illness.",
          action:
            "Book infant and young child feeding counselling for these households and add a growth " +
            "monitoring session at " + place + " within the month.",
          evidence: [
            { label: "Underweight", value: underweightRate + "%" },
            { label: "Children affected", value: String(bucket.underweight) },
          ],
          weight: underweightRate * Math.max(1, bucket.assessed) / 5,
        });
      }
    });

    return out;
  }

  /* ── Signal 3: maternal risk concentration ───────────────────────────── */

  function maternalFindings(ctx) {
    const out = [];
    const byFacility = new Map();
    const motherFacility = new Map();

    (ctx.mothers || []).forEach(function (m) {
      motherFacility.set(String(m.mother_id), String(m.assigned_bhc_id || "unassigned"));
    });

    (ctx.ongoingPregnancies || []).forEach(function (p) {
      const key = motherFacility.get(String(p.mother_id)) || "unassigned";
      if (!byFacility.has(key)) byFacility.set(key, { total: 0, high: 0 });
      const bucket = byFacility.get(key);
      bucket.total++;
      if (String(p.pregnancy_risk_level || "").toLowerCase() === "high") bucket.high++;
    });

    byFacility.forEach(function (bucket, facilityId) {
      if (facilityId === "unassigned" || bucket.total < T.MIN_COHORT) return;
      const share = pct(bucket.high, bucket.total);
      if (share === null || share < T.HIGH_RISK_SHARE) return;
      const place = ctx.placeName(facilityId);

      out.push({
        id: "maternal:" + facilityId,
        severity: share >= 40 ? "critical" : "warning",
        domain: "Maternal care",
        icon: "fa-heart-pulse",
        place: place,
        headline: share + "% of pregnancies in " + place + " are high-risk",
        finding:
          bucket.high + " of " + bucket.total + " ongoing pregnancies at this centre are classified " +
          "high-risk — well above the share seen across the rest of the scope.",
        action:
          "Review the birth plan for each of these " + bucket.high + " " +
          plural(bucket.high, "mother") + " and confirm a named CEmONC referral facility is " +
          "recorded before 32 weeks. Where the midwife caseload allows, move them to fortnightly visits.",
        evidence: [
          { label: "High-risk share", value: share + "%", tone: share >= 40 ? "critical" : "warning" },
          { label: "High-risk mothers", value: String(bucket.high) },
          { label: "Ongoing pregnancies", value: String(bucket.total) },
        ],
        weight: share * Math.max(1, bucket.high) / 2,
      });
    });

    return out;
  }

  /* ── Signal 4: stock that is in the wrong place ──────────────────────── */

  function stockFindings(ctx) {
    const out = [];
    const stock = ctx.stock;
    if (!stock || typeof stock.shortages !== "function") return out;

    let shortages = [];
    try {
      shortages = stock.shortages("all", ctx.facilityCount) || [];
    } catch (e) {
      return out;
    }

    shortages.slice(0, 6).forEach(function (row) {
      const emptyNames = (row.emptyFacilities || []).map(function (f) { return f.name; });

      // The most actionable shortage of all: nothing at the front line, plenty
      // at the depot. Nobody has to buy anything — somebody has to move it.
      if (row.hasDepotStock && row.localOutCount > 0) {
        out.push({
          id: "stock-move:" + row.item.item_id,
          severity: "critical",
          domain: "Supply",
          icon: "fa-truck-ramp-box",
          place: emptyNames.slice(0, 2).join(", ") + (emptyNames.length > 2 ? " and others" : ""),
          headline: row.name + " has run out at " + row.localOutCount + " " +
                    plural(row.localOutCount, "health centre"),
          finding:
            "There is no usable " + row.name + " at " + emptyNames.slice(0, 3).join(", ") +
            (emptyNames.length > 3 ? " and " + (emptyNames.length - 3) + " more" : "") +
            ", while " + row.depotAvailableDoses + " " + plural(row.depotAvailableDoses, "dose") +
            " " + (row.depotAvailableDoses === 1 ? "sits" : "sit") + " at " + row.depotName + ".",
          action:
            "Allocate " + row.name + " from " + row.depotName + " to " +
            emptyNames.slice(0, 3).join(", ") + " now. This is a transfer, not a purchase — " +
            "the stock already exists.",
          feasibility: {
            state: "ready",
            note: "Available to move:",
            lines: [row.depotName + " — " + row.depotAvailableDoses + " " +
                    plural(row.depotAvailableDoses, "dose")],
          },
          evidence: [
            { label: "Centres with none", value: String(row.localOutCount), tone: "critical" },
            { label: "At " + row.depotName, value: String(row.depotAvailableDoses) },
          ],
          link: { href: "inventory.html?tab=requests&subview=transfers", text: "Open transfers" },
          weight: 400 + row.localOutCount * 20,
        });
        return;
      }

      // Nothing anywhere in scope. Only procurement fixes this one.
      if (row.status === "out") {
        out.push({
          id: "stock-out:" + row.item.item_id,
          severity: "critical",
          domain: "Supply",
          icon: "fa-box-open",
          place: "Whole scope",
          headline: row.name + " is out of stock everywhere",
          finding:
            "No usable " + row.name + " remains at any shelf in scope, including " + row.depotName + ".",
          action:
            root.PortalScope && root.PortalScope.isMho
              ? "Raise a procurement request with the Provincial Health Office and suspend any " +
                "session that depends on " + row.name + " until stock arrives."
              : "Raise a stock request to the Municipal Health Office for " + row.name + " today.",
          evidence: [
            { label: "Available", value: "0", tone: "critical" },
            { label: "Safety level", value: String(row.threshold) },
          ],
          link: { href: "inventory.html?tab=requests&subview=requests", text: "Raise a request" },
          weight: 380,
        });
        return;
      }

      // Low but not empty: a lead-time problem, worth flagging once.
      out.push({
        id: "stock-low:" + row.item.item_id,
        severity: "warning",
        domain: "Supply",
        icon: "fa-triangle-exclamation",
        place: "Whole scope",
        headline: row.name + " is below its safety level",
        finding:
          row.available + " " + row.unit + " remain against a safety level of " + row.threshold +
          ". At the standard 14-day replenishment lead time this is close to running out before " +
          "a new order could arrive.",
        action: "Order " + row.name + " now rather than at the next cycle.",
        evidence: [
          { label: "On hand", value: String(row.available) },
          { label: "Safety level", value: String(row.threshold) },
        ],
        weight: 120,
      });
    });

    return out;
  }

  /* ── Signal 5: drives that are not landing ───────────────────────────── */

  function driveFindings(ctx) {
    const out = [];
    const held = (ctx.drives || []).filter(function (d) { return d.drive_status !== "upcoming"; });
    if (held.length === 0) return out;

    const invited = held.reduce(function (t, d) { return t + (Number(d.invited_count) || 0); }, 0);
    const turnedUp = held.reduce(function (t, d) { return t + (Number(d.invited_attended) || 0); }, 0);
    const noShows = held.reduce(function (t, d) { return t + (Number(d.no_show_count) || 0); }, 0);
    const rate = pct(turnedUp, invited);

    if (rate !== null && rate < T.DRIVE_TURNOUT_LOW && invited >= 10) {
      out.push({
        id: "drive-turnout",
        severity: "warning",
        domain: "Outreach",
        icon: "fa-bullhorn",
        place: "Across held drives",
        headline: "Only " + rate + "% of invited families attended",
        finding:
          turnedUp + " of " + invited + " invited caretakers came to a drive, leaving " + noShows +
          " recorded no-" + plural(noShows, "show") + ". The sessions are being held; the " +
          "invitations are not converting.",
        action:
          "Send the SMS reminder the day before rather than the week before, and give the no-show " +
          "list to barangay health workers for follow-up within seven days — a missed drive dose " +
          "is a missed opportunity for vaccination, not a cancelled one.",
        evidence: [
          { label: "Turnout", value: rate + "%", tone: "warning" },
          { label: "No-shows", value: String(noShows) },
          { label: "Drives held", value: String(held.length) },
        ],
        weight: (T.DRIVE_TURNOUT_LOW - rate) * 6,
      });
    }

    return out;
  }

  /* ── Assembly ────────────────────────────────────────────────────────── */

  /**
   * Build the ranked list.
   *
   * `input` is whatever reports.html already has in memory after a render —
   * this never reads the database, so it costs nothing to recompute on every
   * filter change.
   */
  function build(input) {
    const ctx = {
      coverage: input.coverage || [],
      children: input.children || [],
      mothers: input.mothers || [],
      ongoingPregnancies: input.ongoingPregnancies || [],
      drives: input.drives || [],
      stock: input.stock || root.InventoryStock || null,
      latestGrowth: input.latestGrowth || new Map(),
      facilityCount: input.facilityCount || 1,
      placeName: input.placeName || function (id) { return "Facility #" + id; },
    };

    let findings = [];
    try { findings = findings.concat(coverageFindings(ctx)); } catch (e) { console.warn("coverage recommendations:", e); }
    try { findings = findings.concat(growthFindings(ctx)); } catch (e) { console.warn("growth recommendations:", e); }
    try { findings = findings.concat(maternalFindings(ctx)); } catch (e) { console.warn("maternal recommendations:", e); }
    try { findings = findings.concat(stockFindings(ctx)); } catch (e) { console.warn("stock recommendations:", e); }
    try { findings = findings.concat(driveFindings(ctx)); } catch (e) { console.warn("drive recommendations:", e); }

    findings.sort(function (a, b) {
      const rankA = SEVERITY_RANK[a.severity] ?? 3;
      const rankB = SEVERITY_RANK[b.severity] ?? 3;
      if (rankA !== rankB) return rankA - rankB;
      return (b.weight || 0) - (a.weight || 0);
    });

    return findings;
  }

  root.AnalyticsRecommendations = {
    build: build,
    thresholds: T,
  };
})(typeof window !== "undefined" ? window : globalThis);
