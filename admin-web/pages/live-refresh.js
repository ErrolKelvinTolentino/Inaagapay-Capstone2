/* =====================================================
   InaAgapay Admin Web — Shared Refresh & Live Sync

   Each protected page registers its existing data loader. The helper adds a
   consistent header control, refreshes stale pages after focus/online events,
   keeps a periodic fallback, and listens to the sanitized
   `admin_change_events` Supabase Realtime feed.
   ===================================================== */

(function () {
  "use strict";

  const DEFAULT_INTERVAL_MS = 60 * 1000;
  const DEFAULT_STALE_MS = 15 * 1000;
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

    const intervalMs = Number.isFinite(options.intervalMs)
      ? Math.max(0, options.intervalMs)
      : DEFAULT_INTERVAL_MS;
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
    let realtimeTimer = null;
    let channel = null;

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

    if (intervalMs > 0) {
      intervalId = window.setInterval(() => {
        if (!document.hidden) refresh("interval");
      }, intervalMs);
    }

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
