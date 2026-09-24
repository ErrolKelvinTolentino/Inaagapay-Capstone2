/* =====================================================
   InaAgapay Admin Web — Shared Refresh & Live Sync

   Each protected page registers its existing data loader. The helper adds a
   consistent header control, refreshes stale pages after focus/online events,
   keeps a periodic fallback, and listens to the sanitized
   `admin_change_events` Supabase Realtime feed.
   ===================================================== */

(function () {
  "use strict";

  // Two very different intervals, because they do two different jobs.
  //
  // When Realtime is subscribed the page already learns about every change the
  // moment it happens; the timer is only there to catch a socket that has gone
  // quiet without saying so. Ten minutes is plenty for that, and the old
  // sixty-second tick was re-reading whole tables 600 times a day per open tab
  // to discover nothing had changed. That single number was the largest source
  // of egress in the portal.
  //
  // With Realtime down the timer is the only way the page learns anything, so
  // it stays brisk.
  const LIVE_HEARTBEAT_MS = 10 * 60 * 1000;
  const FALLBACK_INTERVAL_MS = 2 * 60 * 1000;
  const DEFAULT_STALE_MS = 30 * 1000;
  const REALTIME_DEBOUNCE_MS = 650;
  let activeController = null;

  function uniqueStrings(values) {
    return [...new Set((values || []).filter(Boolean).map(String))];
  }

  function formatTime(value) {
    return new Date(value).toLocaleTimeString("en-PH", {
      hour: "2-digit",
      minute: "2-digit",
    });
  }

  function createHeaderControl() {
    const headerRight = document.querySelector(".app-header .header-right");
    if (!headerRight) return null;

    let button = document.getElementById("admin-live-refresh");
    if (button) return button;

    button = document.createElement("button");
    button.type = "button";
    button.id = "admin-live-refresh";
    button.className = "live-sync-control";
    button.setAttribute("aria-label", "Refresh page data");
    button.innerHTML = `
      <span class="live-sync-dot" aria-hidden="true"></span>
      <span class="live-sync-label" aria-live="polite">Connecting</span>
      <i class="fa-solid fa-arrows-rotate live-sync-icon" aria-hidden="true"></i>
    `;

    const portalBadge = headerRight.querySelector(".header-badge");
    headerRight.insertBefore(button, portalBadge || headerRight.firstChild);
    return button;
  }

  function start(options) {
    activeController?.stop();

    const db = options?.db;
    const refreshCallback = options?.refresh;
    const watchedTables = new Set(uniqueStrings(options?.tables));
    if (!db || typeof refreshCallback !== "function") {
      console.warn("Live refresh requires a Supabase client and refresh callback.");
      return null;
    }

    const overrideIntervalMs = Number.isFinite(options.intervalMs)
      ? Math.max(0, options.intervalMs)
      : null;
    const staleMs = Number.isFinite(options.staleMs)
      ? Math.max(0, options.staleMs)
      : DEFAULT_STALE_MS;
    const canRefresh =
      typeof options.canRefresh === "function" ? options.canRefresh : () => true;

    const control = createHeaderControl();
    const label = control?.querySelector(".live-sync-label");
    const pageKey =
      window.location.pathname.split("/").pop()?.replace(/\W+/g, "-") ||
      "admin";

    let stopped = false;
    let inFlight = false;
    let queued = false;
    let realtimeConnected = false;
    let lastRefreshAt = Date.now();
    let intervalId = null;
    let intervalPeriod = null;
    let realtimeTimer = null;
    let channel = null;
    // Tables named by realtime events since the last refresh. Only the cached
    // reads built from these are dropped, so a change to one account does not
    // cost a re-read of every inventory batch in the municipality.
    let dirtyTables = new Set();

    function updateState(state, text, detail) {
      if (!control || !label) return;
      control.dataset.state = state;
      label.textContent = text;
      control.title = detail || text;
      control.setAttribute("aria-busy", state === "syncing" ? "true" : "false");
    }

    function restingState() {
      if (!navigator.onLine) {
        updateState("offline", "Offline", "Waiting for the network to reconnect");
      } else if (realtimeConnected) {
        updateState(
          "live",
          "Live",
          `Realtime active • Last checked ${formatTime(lastRefreshAt)}`,
        );
      } else {
        updateState(
          "fallback",
          "Auto refresh",
          `Realtime unavailable • Last checked ${formatTime(lastRefreshAt)}`,
        );
      }
    }

    async function refresh(source = "manual") {
      if (stopped) return;
      if (!navigator.onLine) {
        restingState();
        return;
      }
      if (!canRefresh(source)) {
        queued = true;
        return;
      }
      if (inFlight) {
        queued = true;
        return;
      }

      inFlight = true;
      queued = false;
      updateState("syncing", "Syncing", "Refreshing page data");

      // Drop the cached reads this refresh is meant to supersede. A realtime
      // tick knows exactly which tables moved; every other trigger is a human
      // or a heartbeat asking for the current picture, so nothing is kept.
      if (window.AdminData) {
        if (source === "realtime" && dirtyTables.size > 0) {
          window.AdminData.invalidateTables([...dirtyTables]);
        } else {
          window.AdminData.invalidate();
        }
      }
      dirtyTables = new Set();

      try {
        await refreshCallback(source);
        lastRefreshAt = Date.now();
        document.dispatchEvent(
          new CustomEvent("inaagapay:data-refreshed", {
            detail: { source, refreshedAt: lastRefreshAt },
          }),
        );
        restingState();
      } catch (error) {
        console.error("Page refresh failed:", error);
        updateState("error", "Retry", "Refresh failed — click to try again");
      } finally {
        inFlight = false;
        if (queued && !stopped) {
          queued = false;
          window.setTimeout(() => refresh("queued"), 0);
        }
      }
    }

    function scheduleRealtimeRefresh(payload) {
      const tableName = payload?.new?.table_name;
      if (watchedTables.size && tableName && !watchedTables.has(tableName)) {
        return;
      }
      if (tableName) dirtyTables.add(String(tableName));
      window.clearTimeout(realtimeTimer);
      realtimeTimer = window.setTimeout(
        () => refresh("realtime"),
        REALTIME_DEBOUNCE_MS,
      );
    }

    function refreshIfStale(source) {
      if (document.hidden || Date.now() - lastRefreshAt < staleMs) return;
      refresh(source);
    }

    function handleVisibilityChange() {
      if (!document.hidden) refreshIfStale("visible");
    }

    function handleFocus() {
      refreshIfStale("focus");
    }

    function handleOnline() {
      refresh("online");
    }

    function handleOffline() {
      restingState();
    }

    control?.addEventListener("click", () => refresh("manual"));
    document.addEventListener("visibilitychange", handleVisibilityChange);
    window.addEventListener("focus", handleFocus);
    window.addEventListener("online", handleOnline);
    window.addEventListener("offline", handleOffline);

    // The timer's period depends on whether Realtime is carrying the updates,
    // so it is rebuilt whenever that changes rather than fixed at start-up.
    function rescheduleInterval() {
      const period = overrideIntervalMs !== null
        ? overrideIntervalMs
        : (realtimeConnected ? LIVE_HEARTBEAT_MS : FALLBACK_INTERVAL_MS);

      if (intervalId !== null && period === intervalPeriod) return;
      window.clearInterval(intervalId);
      intervalId = null;
      intervalPeriod = period;
      if (period <= 0) return;

      intervalId = window.setInterval(() => {
        // A background tab that nobody is looking at has no reason to pull
        // rows. It re-reads on the visibilitychange that brings it forward.
        if (!document.hidden) refresh("interval");
      }, period);
    }

    rescheduleInterval();

    updateState("connecting", "Connecting", "Connecting live page updates");
    try {
      channel = db
        .channel(`admin-live-${pageKey}-${Date.now()}`)
        .on(
          "postgres_changes",
          {
            event: "INSERT",
            schema: "public",
            table: "admin_change_events",
          },
          scheduleRealtimeRefresh,
        )
        .subscribe((status) => {
          realtimeConnected = status === "SUBSCRIBED";
          if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
            console.warn("Realtime unavailable; periodic refresh remains active.");
          }
          // Losing the socket means the timer becomes the only source of
          // updates, and regaining it means the timer can stand down again.
          rescheduleInterval();
          restingState();
        });
    } catch (error) {
      console.warn("Realtime setup failed; periodic refresh remains active.", error);
      restingState();
    }

    function stop() {
      if (stopped) return;
      stopped = true;
      window.clearInterval(intervalId);
      window.clearTimeout(realtimeTimer);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
      window.removeEventListener("focus", handleFocus);
      window.removeEventListener("online", handleOnline);
      window.removeEventListener("offline", handleOffline);
      if (channel) db.removeChannel(channel);
    }

    window.addEventListener("beforeunload", stop, { once: true });
    activeController = { refresh, stop };
    return activeController;
  }

  window.AdminLiveRefresh = {
    start,
    stop() {
      activeController?.stop();
      activeController = null;
    },
  };
})();
