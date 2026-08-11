/* =====================================================
   InaAgapay Admin Web — Common Security & Defense Module
   Provides: DB Session Verification, Idle Timeout,
   Network Status Monitor, and DPA 2012 Masking Utilities
   ===================================================== */

(function () {
  const SESSION_KEY = "inaagapay_admin_session";
  const IDLE_TIMEOUT_MS = 15 * 60 * 1000; // 15 Minutes Inactivity Timeout
  const MAX_SESSION_AGE_MS = 12 * 60 * 60 * 1000; // Absolute session lifetime — 12 hours

  // Read Session
  let session = null;
  try {
    session = JSON.parse(localStorage.getItem(SESSION_KEY));
  } catch (e) {
    session = null;
  }

  // A stored session is only usable while it is inside its absolute lifetime.
  // Without this the idle timer resets on every reload, so a session never expires.
  function isSessionExpired(s) {
    if (!s || !s.logged_in_at) return true;
    const issued = new Date(s.logged_in_at).getTime();
    if (!Number.isFinite(issued)) return true;
    return Date.now() - issued > MAX_SESSION_AGE_MS;
  }
  window.isAdminSessionExpired = isSessionExpired;

  // 1. RBAC Session Enforcement
  const isLoginPage = window.location.pathname.endsWith("index.html") || window.location.pathname.endsWith("/");
  if (!isLoginPage) {
    if (!session || session.account_type !== "admin" || isSessionExpired(session)) {
      localStorage.removeItem(SESSION_KEY);
      window.location.href = "../index.html";
      return;
    }
  }

  // 2. Idle Timeout Handler
  let idleTimer = null;
  function resetIdleTimer() {
    if (idleTimer) clearTimeout(idleTimer);
    if (!isLoginPage && session) {
      idleTimer = setTimeout(handleIdleTimeout, IDLE_TIMEOUT_MS);
    }
  }

  function handleIdleTimeout() {
    if (isLoginPage || !session) return;
    try {
      if (window.db) {
        window.db.from("audit_trail").insert({
          account_id: session.account_id,
          action: "session_idle_timeout",
          table_name: "accounts",
          description: "Admin session automatically ended after 15 minutes of inactivity",
        }).then(() => {});
      }
    } catch (e) {}

    localStorage.removeItem(SESSION_KEY);
    alert("Session Expired: You have been logged out due to 15 minutes of inactivity for security compliance.");
    window.location.href = "../index.html";
  }

  // Bind Activity Listeners for Idle Timer
  ["mousemove", "keydown", "click", "scroll", "touchstart"].forEach((evt) => {
    window.addEventListener(evt, resetIdleTimer, { passive: true });
  });
  resetIdleTimer();

  // 3. Network Status Monitor (Online / Offline Banner)
  function initNetworkMonitor() {
    let banner = document.getElementById("network-status-banner");
    if (!banner) {
      banner = document.createElement("div");
      banner.id = "network-status-banner";
      banner.style.display = "none";
      document.body.appendChild(banner);
    }

    function updateOnlineStatus() {
      if (!navigator.onLine) {
        banner.className = "network-status-banner offline";
        banner.innerHTML = '<i class="fa-solid fa-triangle-exclamation"></i> Operating in Offline Mode — Connection Disconnected';
        banner.style.display = "flex";
      } else {
        if (banner.classList.contains("offline")) {
          banner.className = "network-status-banner online";
          banner.innerHTML = '<i class="fa-solid fa-circle-check"></i> Connection Restored';
          banner.style.display = "flex";
          setTimeout(() => {
            banner.style.display = "none";
          }, 3500);
        }
      }
    }

    window.addEventListener("online", updateOnlineStatus);
    window.addEventListener("offline", updateOnlineStatus);
    updateOnlineStatus();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initNetworkMonitor);
  } else {
    initNetworkMonitor();
  }

  // 4. Async Security DB Verification (Tamper Protection)
  window.verifyAdminSessionWithDB = async function (dbInstance) {
    if (!session || !session.account_id || !dbInstance) return;
    try {
      const { data, error } = await dbInstance
        .from("accounts")
        .select("account_id, status, account_type")
        .eq("account_id", session.account_id)
        .single();

      if (error || !data || data.status !== "active" || data.account_type !== "admin") {
        console.warn("Security Alert: Invalid or suspended session detected.");
        localStorage.removeItem(SESSION_KEY);
        window.location.href = isLoginPage ? "index.html" : "../index.html";
      }
    } catch (e) {
      console.warn("Session verification warning:", e);
    }
  };

  // 5. Shared Masking & Validation Helpers
  window.escHtml = function (value) {
    const d = document.createElement("div");
    d.textContent = value ?? "";
    return d.innerHTML;
  };

  // Masks a free-text value (name, barangay, email) for DPA display.
  // Keeps the first character so rows stay distinguishable to the operator.
  window.maskText = function (value, isMasked = true) {
    if (value === null || value === undefined || value === "") return "—";
    const str = String(value);
    if (!isMasked) return window.escHtml(str);
    if (str.includes("@")) return window.escHtml(window.maskEmail(str, true));
    if (str.length <= 2) return window.escHtml(str.charAt(0)) + "•";
    return window.escHtml(str.charAt(0)) + "•".repeat(Math.min(str.length - 1, 8));
  };

  // Neutralises spreadsheet formula injection before a value enters a CSV cell.
  // Excel/Sheets execute any cell beginning with = + - @ TAB or CR.
  window.csvCell = function (value) {
    let str = value === null || value === undefined ? "" : String(value);
    if (/^[=+\-@\t\r]/.test(str)) str = "'" + str;
    return '"' + str.replace(/"/g, '""') + '"';
  };

  window.maskEmail = function (email, isMasked = true) {
    if (!email) return "—";
    if (!isMasked) return email;
    const parts = String(email).split("@");
    if (parts.length === 2) {
      return parts[0].charAt(0) + "***@" + parts[1];
    }
    return "***@***";
  };

  window.maskPhone = function (phone, isMasked = true) {
    if (!phone) return "—";
    if (!isMasked) return phone;
    const str = String(phone).trim();
    if (str.length >= 7) {
      return str.substring(0, 4) + "-***-" + str.substring(str.length - 4);
    }
    return "***-***";
  };

  window.isValidPhPhone = function (phone) {
    if (!phone) return false;
    const str = String(phone).trim();
    return /^(09|\+639)\d{9}$/.test(str);
  };

  // 6. Custom RHU Confirmation Modal (Replaces browser confirm/alert popups)
  window.openConfirmationModal = function (options) {
    const opts = Object.assign({
      title: "Confirm Action",
      message: "Are you sure you want to proceed with this operation?",
      icon: "fa-solid fa-circle-question",
      confirmText: "Proceed",
      cancelText: "Cancel",
      isDanger: false,
      onConfirm: () => {}
    }, options || {});

    const existing = document.getElementById("rhu-confirmation-modal-overlay");
    if (existing) existing.remove();

    const overlay = document.createElement("div");
    overlay.id = "rhu-confirmation-modal-overlay";
    overlay.className = "rhu-modal-overlay";
    overlay.innerHTML = `
      <div class="rhu-modal-card">
        <div class="rhu-modal-header">
          <i class="${opts.icon}"></i>
          <h3 class="rhu-modal-title">${opts.title}</h3>
        </div>
        <div class="rhu-modal-body">
          <p style="margin:0;font-size:14px;color:var(--text-primary);line-height:1.5;">${opts.message}</p>
          <div class="rhu-dpa-notice">
            <i class="fa-solid fa-user-shield"></i>
            <span>Data Privacy Act (RA 10173): Action will be logged for security compliance.</span>
          </div>
        </div>
        <div class="rhu-modal-footer">
          <button class="btn btn-secondary btn-sm" id="rhu-confirm-cancel-btn" style="min-width:90px;">${opts.cancelText}</button>
          <button class="btn ${opts.isDanger ? 'btn-danger' : 'btn-primary'} btn-sm" id="rhu-confirm-action-btn" style="min-width:100px;">${opts.confirmText}</button>
        </div>
      </div>
    `;
    document.body.appendChild(overlay);
    document.body.classList.add("modal-open");

    function closeConfirmOverlay() {
      overlay.remove();
      syncModalScrollLock();
    }
    document.getElementById("rhu-confirm-cancel-btn").addEventListener("click", closeConfirmOverlay);
    document.getElementById("rhu-confirm-action-btn").addEventListener("click", () => {
      closeConfirmOverlay();
      if (typeof opts.onConfirm === "function") opts.onConfirm();
    });
  };

  // 7. Reason Prompt Modal — replaces the native window.prompt()
  window.openReasonModal = function (options) {
    const opts = Object.assign({
      title: "Provide a Reason",
      message: "Enter a reason for this action.",
      placeholder: "Reason…",
      confirmText: "Submit",
      required: false,
    }, options || {});

    return new Promise((resolve) => {
      const existing = document.getElementById("rhu-reason-modal-overlay");
      if (existing) existing.remove();

      const overlay = document.createElement("div");
      overlay.id = "rhu-reason-modal-overlay";
      overlay.className = "rhu-modal-overlay";
      overlay.innerHTML = `
        <div class="rhu-modal-card" role="dialog" aria-modal="true" aria-labelledby="rhu-reason-title">
          <div class="rhu-modal-header">
            <i class="fa-solid fa-comment-dots"></i>
            <h3 class="rhu-modal-title" id="rhu-reason-title">${window.escHtml(opts.title)}</h3>
          </div>
          <div class="rhu-modal-body">
            <p style="margin:0 0 10px;font-size:14px;color:var(--text-primary);line-height:1.5;">${window.escHtml(opts.message)}</p>
            <textarea id="rhu-reason-input" class="form-control" rows="3"
              placeholder="${window.escHtml(opts.placeholder)}" style="width:100%;resize:vertical;"></textarea>
            <div id="rhu-reason-error" style="display:none;color:var(--error);font-size:12px;margin-top:6px;"></div>
            <div class="rhu-dpa-notice">
              <i class="fa-solid fa-user-shield"></i>
              <span>Data Privacy Act (RA 10173): Action will be logged for security compliance.</span>
            </div>
          </div>
          <div class="rhu-modal-footer">
            <button class="btn btn-secondary btn-sm" id="rhu-reason-cancel" style="min-width:90px;">Cancel</button>
            <button class="btn btn-primary btn-sm" id="rhu-reason-submit" style="min-width:100px;">${window.escHtml(opts.confirmText)}</button>
          </div>
        </div>
      `;
      document.body.appendChild(overlay);
      document.body.classList.add("modal-open");

      const input = document.getElementById("rhu-reason-input");
      input.focus();

      function close(value) {
        document.removeEventListener("keydown", onKey);
        overlay.remove();
        syncModalScrollLock();
        resolve(value);
      }
      function submit() {
        const value = input.value.trim();
        if (opts.required && !value) {
          const err = document.getElementById("rhu-reason-error");
          err.textContent = "A reason is required.";
          err.style.display = "block";
          return;
        }
        close(value);
      }
      function onKey(e) {
        if (e.key === "Escape") close(null);
      }

      document.getElementById("rhu-reason-cancel").addEventListener("click", () => close(null));
      document.getElementById("rhu-reason-submit").addEventListener("click", submit);
      document.addEventListener("keydown", onKey);
    });
  };

  // 8. Global modal keyboard handling — Escape closes the topmost open modal.
  document.addEventListener("keydown", (e) => {
    if (e.key !== "Escape") return;
    const open = [...document.querySelectorAll(".modal-overlay.show")].pop();
    if (open) open.classList.remove("show");
  });

  // 9. Body scroll-lock — keeps body.modal-open in sync with any open modal.
  //    A MutationObserver covers every page without needing per-page changes:
  //    • .modal-overlay.show  (class-based modals across all pages)
  //    • .rhu-modal-overlay   (dynamically appended confirmation / reason modals)
  function syncModalScrollLock() {
    const hasClassModal = document.querySelector(".modal-overlay.show") !== null;
    const hasRhuModal   = document.querySelector(".rhu-modal-overlay") !== null;
    document.body.classList.toggle("modal-open", hasClassModal || hasRhuModal);
  }

  // Expose so the rhu-modal close helpers above can call it.
  window.syncModalScrollLock = syncModalScrollLock;

  const _scrollLockObserver = new MutationObserver(syncModalScrollLock);
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => {
      _scrollLockObserver.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
    });
  } else {
    _scrollLockObserver.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["class"] });
  }
})();

