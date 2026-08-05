/* =====================================================
   InaAgapay Admin Web — Common Security & Defense Module
   Provides: DB Session Verification, Idle Timeout,
   Network Status Monitor, and DPA 2012 Masking Utilities
   ===================================================== */

(function () {
  const SESSION_KEY = "inaagapay_admin_session";
  const IDLE_TIMEOUT_MS = 15 * 60 * 1000; // 15 Minutes Inactivity Timeout

  // Read Session
  let session = null;
  try {
    session = JSON.parse(localStorage.getItem(SESSION_KEY));
  } catch (e) {
    session = null;
  }

  // 1. RBAC Session Enforcement
  const isLoginPage = window.location.pathname.endsWith("index.html") || window.location.pathname.endsWith("/");
  if (!isLoginPage) {
    if (!session || session.account_type !== "admin") {
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

    document.getElementById("rhu-confirm-cancel-btn").addEventListener("click", () => overlay.remove());
    document.getElementById("rhu-confirm-action-btn").addEventListener("click", () => {
      overlay.remove();
      if (typeof opts.onConfirm === "function") opts.onConfirm();
    });
  };
})();

