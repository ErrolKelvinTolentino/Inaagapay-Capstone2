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
})();
