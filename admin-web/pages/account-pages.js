(function () {
  "use strict";

  const SESSION_KEY = "inaagapay_admin_session";
  let session = null;
  try {
    session = JSON.parse(localStorage.getItem(SESSION_KEY));
  } catch (_) {
    session = null;
  }

  if (!session) return;

  const displayName = [session.first_name, session.last_name].filter(Boolean).join(" ") || "Admin";
  const roleLabel = session.account_type === "mho"
    ? "Municipal Health Office administrator"
    : "Rural Health Unit administrator";
  const portalName = window.PortalScope?.facilityName || (session.account_type === "mho" ? "Municipal Health Office" : "Rural Health Unit");

  document.querySelectorAll("[data-account-name]").forEach((element) => {
    element.textContent = displayName;
  });
  document.querySelectorAll("[data-account-role]").forEach((element) => {
    element.textContent = roleLabel;
  });
  document.querySelectorAll("[data-account-email]").forEach((element) => {
    element.textContent = session.email_address || "—";
  });
  document.querySelectorAll("[data-account-portal]").forEach((element) => {
    element.textContent = portalName;
  });
  document.querySelectorAll("[data-account-id]").forEach((element) => {
    element.textContent = session.account_id || "—";
  });

  const loginDate = session.logged_in_at ? new Date(session.logged_in_at) : null;
  const loginText = loginDate && Number.isFinite(loginDate.getTime())
    ? loginDate.toLocaleString("en-PH", { dateStyle: "medium", timeStyle: "short" })
    : "—";
  document.querySelectorAll("[data-account-login]").forEach((element) => {
    element.textContent = loginText;
  });

  const logoutButton = document.getElementById("logout-btn");
  if (logoutButton) {
    logoutButton.addEventListener("click", () => {
      if (!confirm("Logout?")) return;
      localStorage.removeItem(SESSION_KEY);
      window.PortalScope?.clear();
      if (window.navigateTo) {
        window.navigateTo("../index.html");
      } else {
        window.location.href = "../index.html";
      }
    });
  }

  const sidebarToggle = document.getElementById("sidebar-toggle");
  const sidebar = document.querySelector(".app-sidebar");
  if (sidebarToggle && sidebar) {
    sidebarToggle.addEventListener("click", () => sidebar.classList.toggle("open"));
  }

  const currentPage = window.location.pathname.split("/").pop();
  document.querySelectorAll(`.profile-menu a[href="${currentPage}"]`).forEach((link) => {
    link.setAttribute("aria-current", "page");
  });

  /* ── Notification bell ──────────────────────────────
     help, profile and settings are the only pages that read nothing from the
     database, so they were the only three with no Supabase client to hand the
     notification centre. A bell that is present on eleven pages and absent on
     three reads as a bug, so the client is built here — once, for all three —
     rather than pasted into each of them.

     These constants are the twelfth copy of the same pair in this folder. That
     is worth fixing, but it is a refactor of every page and does not belong in
     this change; keeping them identical to the other eleven is the safe move
     today.
     ─────────────────────────────────────────────────── */
  const SUPABASE_URL = "https://krooorixhjwygcsdoomg.supabase.co";
  const SUPABASE_ANON =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imtyb29vcml4aGp3eWdjc2Rvb21nIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ0NjI5NDIsImV4cCI6MjEwMDAzODk0Mn0.iVIxsgZhd_k0c-rDOjRK5J9xBiL0z-bH2l1LXH9IksU";

  if (window.supabase?.createClient && window.AdminNotifications) {
    window.AdminNotifications.attach(
      window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON),
    );
  }
})();
