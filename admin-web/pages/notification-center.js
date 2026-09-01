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
  let unreadOnly = false;
  let loading = false;
  let loadFailed = false;
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
    return then.toLocaleDateString("en-PH", {
      timeZone: "Asia/Manila",
      month: "short",
      day: "numeric",
    });
  }

  function absoluteTime(ts) {
    const then = toUTC(ts);
    if (!then || !Number.isFinite(then.getTime())) return "";
    return then.toLocaleString("en-PH", {
      timeZone: "Asia/Manila",
      dateStyle: "medium",
      timeStyle: "short",
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
    },
    inventory_batches: {
      icon: "fa-hourglass-half",
      tone: "expiry",
      href: "inventory.html?tab=catalog&subview=batches",
    },
    inventory_stock_requests: {
      icon: "fa-clipboard-list",
      tone: "request",
      href: "inventory.html?tab=requests&subview=requests",
    },
    inventory_transfers: {
      icon: "fa-truck-ramp-box",
      tone: "transfer",
      href: "inventory.html?tab=requests&subview=transfers",
    },
  };

  const TYPE_FALLBACK = {
    inventory: { icon: "fa-boxes-stacked", tone: "stock", href: "inventory.html" },
    checkup_reminder: { icon: "fa-calendar-check", tone: "care", href: null },
    vaccine_reminder: { icon: "fa-syringe", tone: "care", href: null },
    general: { icon: "fa-circle-info", tone: "general", href: null },
  };

  function routeFor(row) {
    return (
      REFERENCE_ROUTES[row.reference_type] ||
      TYPE_FALLBACK[row.type] ||
      TYPE_FALLBACK.general
    );
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
    const profile = headerRight.querySelector(".header-user");
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
      const item = event.target.closest("[data-notif-id]");
      if (!item) return;
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

  async function refresh() {
    if (!db || !session?.account_id || loading) return;
    loading = true;
    try {
      const { data, error } = await db
        .from("notifications")
        .select("notification_id, title, message, type, is_read, created_at, reference_type, reference_id")
        .eq("account_id", session.account_id)
        .order("created_at", { ascending: false })
        .limit(PAGE_SIZE);

      if (error) throw error;
      rows = data || [];
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

  function unreadCount() {
    return rows.filter((r) => !r.is_read).length;
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

    const visible = unreadOnly ? rows.filter((r) => !r.is_read) : rows;

    if (visible.length === 0) {
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

    list.innerHTML = visible
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

    togglePanel(false);
    if (window.navigateTo) {
      window.navigateTo(route.href);
    } else {
      window.location.href = route.href;
    }
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
