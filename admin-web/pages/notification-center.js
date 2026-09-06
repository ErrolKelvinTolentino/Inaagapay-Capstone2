/* =====================================================
   InaAgapay Admin Web — Notification Centre

   The portal writes notifications and has never read one.

   `inventory_notify_facility()` has been putting rows in `notifications` for
   every transfer issued, received and cancelled since 20260824, the midwife
   app shows them, and on this side they have gone nowhere at all. The only
   alerts an officer has ever seen are the ones inventory.html computes in the
   browser from rows it happens to have loaded — which means they exist while
   that one page is open and not otherwise.

   This adds the missing half: a bell in the header of every page, reading this
   account's own rows, so an alert raised at two in the morning by the daily job
   (20260915_inventory_alert_notifications.sql) is waiting when somebody signs
   in, on whichever page they land on.

   WHY IT PIGGYBACKS RATHER THAN SUBSCRIBING
   -----------------------------------------
   `notifications` is already in the watch list of `admin_change_events`
   (20260804), and live-refresh.js already holds that Realtime channel and
   announces every refresh as an `inaagapay:data-refreshed` event. Opening a
   second subscription to learn the same thing would double the connection
   count per officer for no new information. This listens to the event instead,
   and keeps a slow poll for the three account pages that run no live refresh.

   USAGE
     <script src="notification-center.js"></script>
     ...
     window.AdminNotifications.attach(db);
   ===================================================== */

(function () {
  "use strict";

  const SESSION_KEY = "inaagapay_admin_session";

  // Slow on purpose. The realtime feed is the fast path; this only exists so a
  // page with no live refresh, or one whose socket has dropped, still catches
  // up within a couple of minutes.
  const POLL_MS = 90 * 1000;

  // Enough to cover a long weekend without turning the panel into an archive.
  const PAGE_SIZE = 30;

  let db = null;
  let session = null;
  let rows = [];
  let live = [];
  let unreadOnly = false;
  let loading = false;
  let loadFailed = false;
  // Switched off for good the first time the RPC answers "no such function",
  // so a portal deployed ahead of its migration stops asking every 90 seconds.
  let livePreviewAvailable = true;
  let pollId = null;
  let bell = null;
  let panel = null;

  try {
    session = JSON.parse(localStorage.getItem(SESSION_KEY));
  } catch (e) {
    session = null;
  }

  /* ── Small helpers ─────────────────────────────────── */

  function esc(value) {
    const d = document.createElement("div");
    d.textContent = value ?? "";
    return d.innerHTML;
  }

  // Timestamps in this schema are `timestamp without time zone` holding UTC, so
  // a bare parse is read as local and every notification reads eight hours old.
  // Same correction accounts.html and audit-trail.html already make.
  function toUTC(ts) {
    if (!ts) return null;
    return new Date(/Z|[+-]\d{2}:?\d{2}$/.test(ts) ? ts : ts + "Z");
  }

  function relativeTime(ts) {
    const then = toUTC(ts);
    if (!then || !Number.isFinite(then.getTime())) return "";
    const seconds = Math.round((Date.now() - then.getTime()) / 1000);
    if (seconds < 60) return "just now";
    const minutes = Math.round(seconds / 60);
    if (minutes < 60) return `${minutes}m ago`;
    const hours = Math.round(minutes / 60);
    if (hours < 24) return `${hours}h ago`;
    const days = Math.round(hours / 24);
    if (days < 7) return `${days}d ago`;
    return then.toLocaleDateString("en-US", {
      timeZone: "Asia/Manila",
      month: "short",
      day: "2-digit",
    });
  }

  function absoluteTime(ts) {
    const then = toUTC(ts);
    if (!then || !Number.isFinite(then.getTime())) return "";
    return then.toLocaleDateString("en-US", {
      timeZone: "Asia/Manila",
      month: "short",
      day: "2-digit",
      year: "numeric",
    }) + ", " + then.toLocaleTimeString("en-US", {
      timeZone: "Asia/Manila",
      hour: "2-digit",
      minute: "2-digit",
    });
  }

  /* ── What a notification is about ──────────────────────
     Read from `type` and `reference_type`, never from the wording. The message
     is a sentence written for a person; 20260909 added the reference columns
     precisely so code would stop trying to recognise events by parsing English
     prose, and this file is not going to reintroduce that.
     ──────────────────────────────────────────────────── */

  const REFERENCE_ROUTES = {
    inventory_items: {
      icon: "fa-boxes-stacked",
      tone: "stock",
      href: "inventory.html?tab=catalog&subview=summary",
      actionHint: "View item",
    },
    inventory_batches: {
      icon: "fa-hourglass-half",
      tone: "expiry",
      href: "inventory.html?tab=catalog&subview=batches",
      actionHint: "View batch",
    },
    inventory_stock_requests: {
      icon: "fa-clipboard-list",
      tone: "request",
      href: "inventory.html?tab=requests&subview=requests",
      actionHint: "Review request",
    },
    inventory_transfers: {
      icon: "fa-truck-ramp-box",
      tone: "transfer",
      href: "inventory.html?tab=requests&subview=transfers",
      actionHint: "Open transfer",
    },
  };

  const TYPE_FALLBACK = {
    inventory: { icon: "fa-boxes-stacked", tone: "stock", href: "inventory.html", actionHint: "Open inventory" },
    checkup_reminder: { icon: "fa-calendar-check", tone: "care", href: "reports.html", actionHint: "View schedule" },
    vaccine_reminder: { icon: "fa-syringe", tone: "care", href: "reports.html", actionHint: "View schedule" },
    general: { icon: "fa-circle-info", tone: "general", href: null, actionHint: null },
  };

  function routeFor(row) {
    let refType = row.reference_type;
    let refId = row.reference_id;

    // Fallback parsing for legacy rows where reference_type/reference_id was not populated
    if (!refType) {
      const text = `${row.title || ""} ${row.message || ""}`;
      const transferMatch = text.match(/transfer\s*#?(\d+)/i);
      const requestMatch = text.match(/(?:stock\s*request|requisition|request)\s*#?(\d+)/i);
      const batchMatch = text.match(/batch\s*(?:#|no\.?|number|id|:)\s*([A-Za-z0-9-_]+)/i) ||
                         text.match(/\bbatch\s+(?!expired\b|expiring\b|excursion\b)([A-Za-z0-9-_]+)/i);

      if (transferMatch) {
        refType = "inventory_transfers";
        refId = transferMatch[1];
      } else if (requestMatch) {
        refType = "inventory_stock_requests";
        refId = requestMatch[1];
      } else if (batchMatch) {
        refType = "inventory_batches";
        refId = batchMatch[1];
      } else if (row.type === "inventory") {
        refType = "inventory_items";
      }
    }

    if (refType && REFERENCE_ROUTES[refType]) {
      const base = REFERENCE_ROUTES[refType];
      let href = base.href;
      if (refId !== null && refId !== undefined && refId !== "") {
        if (refType === "inventory_transfers") {
          href += `&transfer_id=${encodeURIComponent(refId)}`;
        } else if (refType === "inventory_stock_requests") {
          href += `&request_id=${encodeURIComponent(refId)}`;
        } else if (refType === "inventory_batches") {
          href += `&batch_id=${encodeURIComponent(refId)}`;
        } else if (refType === "inventory_items") {
          href += `&item_id=${encodeURIComponent(refId)}`;
        }
      }
      return {
        ...base,
        href,
      };
    }

    return TYPE_FALLBACK[row.type] || TYPE_FALLBACK.general;
  }

  /* ── Conditions, as opposed to messages ────────────────
     `notifications` holds events: something happened, and it has a read state.
     preview_inventory_alerts() holds conditions: nothing happened, something
     IS — a shelf is short right now. A condition has no read state because
     there is nothing to acknowledge; it ends when the stock arrives, not when
     somebody clicks it.

     Both belong in this panel. Between two runs of the nightly job a shortage
     that appeared this morning has no notification row yet, and the officer
     who needs to know is the one who has not opened inventory.html today.
     ──────────────────────────────────────────────────── */

  // The same ladder as public.inventory_alert_rank(). Kept in step by hand:
  // the browser cannot read a SQL CASE, so if that function's rungs change,
  // this changes with it.
  const SEVERITY_RANK = { watch: 1, low: 2, urgent: 3, critical: 4, expired: 5 };

  // critical and expired — nothing left to give, or nothing left that may be
  // given. The rung where somebody is turned away today.
  const TOP_RUNG = 4;

  function rankOf(severity) {
    return SEVERITY_RANK[severity] || 0;
  }

  // Which row a live alert is about, derived exactly as scan_inventory_alerts()
  // derives it when the job writes the notification: rule 1 names a shelf, so
  // it points at the item; rules 2 and 3 name one box, so they point at the
  // batch. This is what lets a condition and the message about it be
  // recognised as one thing.
  function liveKey(alert) {
    return alert.batch_id === null || alert.batch_id === undefined
      ? `inventory_items:${alert.item_id}`
      : `inventory_batches:${alert.batch_id}`;
  }

  function liveRoute(alert) {
    if (alert.batch_id !== null && alert.batch_id !== undefined) {
      const isOpenVial = alert.alert_kind === "open_vial" ||
        (alert.title && alert.title.toLowerCase().includes("open vial"));
      let href = `inventory.html?tab=catalog&subview=batches&batch_id=${encodeURIComponent(alert.batch_id)}`;
      if (isOpenVial) href += "&open_vial=1";
      if (alert.facility_id !== null && alert.facility_id !== undefined) {
        href += `&facility_id=${encodeURIComponent(alert.facility_id)}`;
      }
      return {
        icon: isOpenVial ? "fa-syringe" : "fa-hourglass-half",
        tone: "expiry",
        href,
        actionHint: isOpenVial ? "Discard vial" : "View batch",
      };
    }

    if (alert.item_id !== null && alert.item_id !== undefined) {
      let href = `inventory.html?tab=catalog&subview=summary&item_id=${encodeURIComponent(alert.item_id)}`;
      if (alert.facility_id !== null && alert.facility_id !== undefined) {
        href += `&facility_id=${encodeURIComponent(alert.facility_id)}`;
      }
      return {
        icon: "fa-boxes-stacked",
        tone: "stock",
        href,
        actionHint: "View item",
      };
    }

    return TYPE_FALLBACK.inventory;
  }

  function executeNavigation(targetHref) {
    if (!targetHref) return;
    togglePanel(false);

    try {
      const currentUrl = new URL(window.location.href);
      const targetUrl = new URL(targetHref, window.location.href);

      const isCurrentInventory = currentUrl.pathname.endsWith("inventory.html");
      const isTargetInventory = targetUrl.pathname.endsWith("inventory.html");

      if (isCurrentInventory && isTargetInventory) {
        // Fast path: in-page switch without full page reload
        const newRelative = targetUrl.pathname.split("/").pop() + targetUrl.search + targetUrl.hash;
        if (window.history && window.history.pushState) {
          window.history.pushState(null, "", newRelative);
        }
        if (typeof window.applyHubQueryParam === "function") {
          window.applyHubQueryParam();
          return;
        }
      }
    } catch (e) {
      console.warn("Could not parse navigation URL:", e);
    }

    if (window.navigateTo) {
      window.navigateTo(targetHref);
    } else {
      window.location.href = targetHref;
    }
  }

  /* ── Chrome ────────────────────────────────────────── */

  function buildBell() {
    const headerRight = document.querySelector(".app-header .header-right");
    if (!headerRight) return null;

    const existing = document.getElementById("admin-notif-bell");
    if (existing) return existing;

    const wrap = document.createElement("div");
    wrap.className = "notif-wrap";

    wrap.innerHTML = `
      <button type="button" id="admin-notif-bell" class="notif-bell"
              aria-label="Notifications" aria-haspopup="true" aria-expanded="false"
              aria-controls="admin-notif-panel">
        <i class="fa-solid fa-bell" aria-hidden="true"></i>
        <span class="notif-count" id="admin-notif-count" hidden></span>
      </button>
      <div class="notif-panel" id="admin-notif-panel" role="dialog"
           aria-label="Notifications" hidden>
        <div class="notif-panel-head">
          <strong>Notifications</strong>
          <div class="notif-panel-head-actions">
            <button type="button" class="notif-filter" id="admin-notif-filter"
                    aria-pressed="false">Unread only</button>
            <button type="button" class="notif-readall" id="admin-notif-readall">
              Mark all read
            </button>
          </div>
        </div>
        <div class="notif-list" id="admin-notif-list" tabindex="-1"></div>
      </div>
    `;

    // Before the profile button, which is always last in the header. Inserting
    // before .header-badge instead would race live-refresh.js, which puts its
    // own control there — the two would swap places depending on script order.
    //
    // Anchored on the direct CHILD holding the profile button rather than on
    // .header-user itself. common-security.js wraps that element in a
    // .header-user-menu, so .header-user is only a direct child of
    // .header-right for as long as this file runs first — which today it does,
    // because attach() is called during script parse and the wrapping happens
    // on DOMContentLoaded. insertBefore throws NotFoundError on a node that is
    // not a child, and it would take the whole bell down with it, so this does
    // not rely on that ordering holding.
    const profile = Array.from(headerRight.children).find(
      (el) => el.classList.contains("header-user") || el.querySelector(".header-user"),
    );
    headerRight.insertBefore(wrap, profile || null);

    bell = wrap.querySelector("#admin-notif-bell");
    panel = wrap.querySelector("#admin-notif-panel");

    bell.addEventListener("click", (event) => {
      event.stopPropagation();
      togglePanel(panel.hidden);
    });

    wrap.querySelector("#admin-notif-filter").addEventListener("click", (event) => {
      unreadOnly = !unreadOnly;
      event.currentTarget.setAttribute("aria-pressed", String(unreadOnly));
      event.currentTarget.classList.toggle("is-on", unreadOnly);
      renderList();
    });

    wrap.querySelector("#admin-notif-readall").addEventListener("click", markAllRead);

    // One delegated listener rather than one per row, because the list is
    // rebuilt on every refresh.
    wrap.querySelector("#admin-notif-list").addEventListener("click", (event) => {
      const item = event.target.closest("[data-notif-id], [data-live-href]");
      if (!item) return;

      // A condition has nothing to mark read — it stops being true when the
      // stock does, not when somebody clicks it. So this only navigates.
      if (item.dataset.liveHref) {
        executeNavigation(item.dataset.liveHref);
        return;
      }

      openNotification(Number(item.dataset.notifId));
    });

    document.addEventListener("click", (event) => {
      if (!panel || panel.hidden) return;
      if (!wrap.contains(event.target)) togglePanel(false);
    });

    document.addEventListener("keydown", (event) => {
      if (event.key !== "Escape" || !panel || panel.hidden) return;
      togglePanel(false);
      bell.focus();
    });

    return bell;
  }

  function togglePanel(open) {
    if (!panel || !bell) return;
    panel.hidden = !open;
    bell.setAttribute("aria-expanded", String(open));
    if (open) {
      renderList();
      // A panel opened from the keyboard has to take focus with it, or the next
      // Tab continues from the bell and walks the page behind the panel.
      document.getElementById("admin-notif-list")?.focus();
      // Opening is also the cheapest moment to notice anything that arrived
      // while the socket was down.
      refresh();
    }
  }

  /* ── Reading ───────────────────────────────────────── */

  /**
   * The conditions the nightly job would report if it ran now.
   *
   * Scoped in the browser, because preview_inventory_alerts() answers for the
   * whole municipality — the database has no way to know who is asking. Same
   * client-side narrowing every other page in this portal applies, and the
   * same limitation.
   */
  async function loadLive() {
    if (!livePreviewAvailable) return [];
    try {
      const { data, error } = await db.rpc("preview_inventory_alerts");
      if (error) throw error;
      return (data || []).filter(
        (a) => !window.PortalScope || window.PortalScope.inScope(a.facility_id),
      );
    } catch (e) {
      const code = e?.code || e?.status;
      // "No such function" is a deployment-order fact, not a fault worth
      // repeating on every poll.
      if (code === "PGRST202" || code === "42883" || code === 404) {
        livePreviewAvailable = false;
        return [];
      }
      console.warn("Live inventory alerts unavailable:", e.message || e);
      return [];
    }
  }

  async function refresh() {
    if (!db || !session?.account_id || loading) return;
    loading = true;
    try {
      // Live alerts never fail the panel: loadLive() swallows its own errors
      // and returns an empty list, so a missing RPC costs the extra section
      // rather than the notifications an officer came here to read.
      const [stored, liveRows] = await Promise.all([
        db
          .from("notifications")
          .select("notification_id, title, message, type, is_read, created_at, reference_type, reference_id")
          .eq("account_id", session.account_id)
          .order("created_at", { ascending: false })
          .limit(PAGE_SIZE),
        loadLive(),
      ]);

      const { data, error } = stored;
      if (error) throw error;
      rows = data || [];
      live = liveRows;
      loadFailed = false;
    } catch (e) {
      // A missing table or column means this database predates the notification
      // work. Say so in the panel rather than leaving a bell that opens onto
      // nothing and looks broken.
      loadFailed = true;
      console.warn("Notification centre read failed:", e.message || e);
    } finally {
      loading = false;
      renderCount();
      if (panel && !panel.hidden) renderList();
    }
  }

  /**
   * The newest stored row about each referenced thing, so a condition on screen
   * can be matched to the message the job already sent about it.
   *
   * Matched on reference_type / reference_id and never on the wording —
   * 20260909 added those columns precisely so this code would not have to
   * recognise events by reading English sentences.
   */
  function twinIndex() {
    const map = new Map();
    rows.forEach((row) => {
      if (!row.reference_type || row.reference_id === null || row.reference_id === undefined) return;
      const key = `${row.reference_type}:${row.reference_id}`;
      if (!map.has(key)) map.set(key, row); // query is newest-first
    });
    return map;
  }

  /**
   * Stored rows that are not already on screen as a live condition.
   *
   * The job writes "Batch expired: BCG" about the same batch the scan is still
   * reporting as expired. Showing both is one event as two cards, which is the
   * duplicate 20260909 was written to end. The live one wins: it is current,
   * and it carries the facility name the message only mentions in prose.
   */
  function storedRows() {
    if (live.length === 0) return rows;
    const onScreen = new Set(live.map(liveKey));
    return rows.filter(
      (row) => !onScreen.has(`${row.reference_type}:${row.reference_id}`),
    );
  }

  /**
   * Live conditions the officer has not been shown yet.
   *
   * A condition whose message is sitting UNREAD counts at any rung. Hiding the
   * duplicate card must not also hide the fact that it is unread — otherwise
   * the nightly job sends 31 notifications and the bell still reads zero,
   * because storedRows() suppressed every one of them and none was severe
   * enough to count on its own. That is not hypothetical: it is what the first
   * real sweep produced.
   *
   * A condition with NO message behind it counts only on the top rung. Those
   * are the ones the job has not reported yet, and a batch thirty days out is
   * not worth a red dot every morning until it expires.
   */
  function untoldLive() {
    const twins = twinIndex();
    return live.filter((alert) => {
      const twin = twins.get(liveKey(alert));
      if (twin) return !twin.is_read;
      return rankOf(alert.severity) >= TOP_RUNG;
    });
  }

  /**
   * What the badge means: things not yet seen.
   *
   * Unread messages, plus top-rung conditions whose message is unread or has
   * never been written. Deliberately NOT every live alert — a batch thirty days
   * out is worth listing and is not worth a red dot every morning for a month,
   * and a badge that is never zero is a badge nobody reads.
   */
  function unreadCount() {
    return storedRows().filter((r) => !r.is_read).length + untoldLive().length;
  }

  function renderCount() {
    const badge = document.getElementById("admin-notif-count");
    if (!badge) return;
    const n = unreadCount();
    badge.hidden = n === 0;
    badge.textContent = n > 99 ? "99+" : String(n);
    if (bell) {
      bell.classList.toggle("has-unread", n > 0);
      bell.setAttribute(
        "aria-label",
        n > 0 ? `Notifications, ${n} unread` : "Notifications",
      );
    }
  }

  function renderList() {
    const list = document.getElementById("admin-notif-list");
    if (!list) return;

    if (loading && rows.length === 0) {
      list.innerHTML = `<div class="notif-empty">Loading…</div>`;
      return;
    }

    if (loadFailed) {
      list.innerHTML = `
        <div class="notif-empty">
          <i class="fa-solid fa-plug-circle-exclamation" aria-hidden="true"></i>
          <strong>Notifications are unavailable</strong>
          <span>The portal could not read them. Check the connection, then reload.</span>
        </div>`;
      return;
    }

    // "Unread only" is a property of messages, so under it the conditions
    // shown are the ones the badge is counting — the filter and the number on
    // the bell then agree, instead of the panel emptying while the bell still
    // reads 3.
    const visibleLive = unreadOnly ? untoldLive() : live;
    const visible = unreadOnly
      ? storedRows().filter((r) => !r.is_read)
      : storedRows();

    if (visible.length === 0 && visibleLive.length === 0) {
      list.innerHTML = `
        <div class="notif-empty">
          <i class="fa-solid fa-check" aria-hidden="true"></i>
          <strong>${unreadOnly ? "Nothing unread" : "No notifications yet"}</strong>
          <span>${
            unreadOnly
              ? "Everything here has been read."
              : "Stock alerts, requests and deliveries will appear here."
          }</span>
        </div>`;
      return;
    }

    const sections = [];

    if (visibleLive.length > 0) {
      // Capped like the stored list is by PAGE_SIZE. A municipality with high
      // thresholds can be short of a lot of things at once, and a dropdown is
      // not the place to read two hundred of them — the count in the heading
      // still tells the truth, and inventory.html is where the full list lives.
      const shownLive = visibleLive.slice(0, PAGE_SIZE);

      sections.push(
        `<div class="notif-section">Happening now<span>${visibleLive.length}</span></div>`,
        shownLive
          .map((alert) => {
            const route = liveRoute(alert);
            const top = rankOf(alert.severity) >= TOP_RUNG;
            return `
              <button type="button" class="notif-item is-live${top ? " is-top" : ""}"
                      data-live-href="${esc(route.href)}">
                <span class="notif-item-icon tone-${route.tone}" aria-hidden="true">
                  <i class="fa-solid ${route.icon}"></i>
                </span>
                <span class="notif-item-body">
                  <span class="notif-item-title">${esc(alert.title)}</span>
                  <span class="notif-item-msg">${esc(alert.message)}</span>
                  <span class="notif-item-time">
                    ${esc(alert.facility_name || "")} &middot; ${esc(alert.severity)}
                    ${route.actionHint ? `<span class="notif-item-action-hint">${esc(route.actionHint)} &rarr;</span>` : ""}
                  </span>
                </span>
              </button>`;
          })
          .join(""),
        visibleLive.length > shownLive.length
          ? `<button type="button" class="notif-item is-live" data-live-href="inventory.html?tab=catalog&amp;subview=summary">
               <span class="notif-item-body">
                 <span class="notif-item-msg">and ${visibleLive.length - shownLive.length} more &mdash; open Inventory to see all of them.</span>
               </span>
             </button>`
          : "",
      );
    }

    if (visible.length > 0) {
      sections.push(
        `<div class="notif-section">${
          visibleLive.length > 0 ? "Earlier" : "Recent"
        }<span>${visible.length}</span></div>`,
      );
    }

    list.innerHTML = sections.join("") + visible
      .map((row) => {
        const route = routeFor(row);
        return `
          <button type="button" class="notif-item${row.is_read ? "" : " is-unread"}"
                  data-notif-id="${row.notification_id}">
            <span class="notif-item-icon tone-${route.tone}" aria-hidden="true">
              <i class="fa-solid ${route.icon}"></i>
            </span>
            <span class="notif-item-body">
              <span class="notif-item-title">${esc(row.title)}</span>
              <span class="notif-item-msg">${esc(row.message)}</span>
              <span class="notif-item-time" title="${esc(absoluteTime(row.created_at))}">
                ${esc(relativeTime(row.created_at))}
                ${route.actionHint ? `<span class="notif-item-action-hint">${esc(route.actionHint)} &rarr;</span>` : ""}
              </span>
            </span>
            ${row.is_read ? "" : '<span class="notif-item-dot" aria-label="Unread"></span>'}
          </button>`;
      })
      .join("");
  }

  /* ── Writing ───────────────────────────────────────── */

  async function markRead(id) {
    const row = rows.find((r) => r.notification_id === id);
    if (!row || row.is_read) return;

    // Optimistic: the badge should drop the moment it is clicked, and a failed
    // write only means the row is still unread on the next refresh.
    row.is_read = true;
    renderCount();

    try {
      await db.from("notifications").update({ is_read: true }).eq("notification_id", id);
    } catch (e) {
      console.warn("Could not mark notification read:", e.message || e);
    }
  }

  async function markAllRead() {
    if (!db || !session?.account_id) return;
    const unread = rows.filter((r) => !r.is_read);
    if (unread.length === 0) return;

    unread.forEach((r) => { r.is_read = true; });
    renderCount();
    renderList();

    try {
      await db
        .from("notifications")
        .update({ is_read: true })
        .eq("account_id", session.account_id)
        .eq("is_read", false);
    } catch (e) {
      console.warn("Could not mark all notifications read:", e.message || e);
      refresh();
    }
  }

  async function openNotification(id) {
    const row = rows.find((r) => r.notification_id === id);
    if (!row) return;

    await markRead(id);

    const route = routeFor(row);
    if (!route.href) {
      // Nothing to open — a general notice. Leave the panel up so the reader can
      // finish the list rather than bouncing them somewhere arbitrary.
      renderList();
      return;
    }

    executeNavigation(route.href);
  }

  /* ── Wiring ────────────────────────────────────────── */

  const AdminNotifications = {
    /** Called by each page once it has built its Supabase client. */
    attach(dbInstance) {
      if (!dbInstance || !session?.account_id) return;
      db = dbInstance;

      if (!buildBell()) return;

      refresh();

      // The fast path: live-refresh.js already owns the realtime channel and
      // announces every refresh it does.
      document.addEventListener("inaagapay:data-refreshed", () => refresh());

      // The slow path, for pages with no live refresh and for a dropped socket.
      clearInterval(pollId);
      pollId = setInterval(() => {
        if (document.visibilityState === "visible") refresh();
      }, POLL_MS);

      window.addEventListener("focus", () => refresh());
      document.addEventListener("visibilitychange", () => {
        if (document.visibilityState === "visible") refresh();
      });
    },

    refresh,
    get unread() { return unreadCount(); },
  };

  window.AdminNotifications = AdminNotifications;
})();
