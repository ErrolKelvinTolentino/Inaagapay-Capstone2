/* =====================================================
   Auth & Utility Helpers — InaAgapay Admin Portal
   ===================================================== */

const SESSION_KEY = 'inaagapay_admin_session';

/* ── Session ─────────────────────────────────────── */
export function getSession() {
  try {
    const raw = localStorage.getItem(SESSION_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch { return null; }
}

export function setSession(data) {
  localStorage.setItem(SESSION_KEY, JSON.stringify({ ...data, logged_in_at: new Date().toISOString() }));
}

export function clearSession() {
  localStorage.removeItem(SESSION_KEY);
}

/**
 * Call on every protected page.  Redirects to login if not authenticated.
 * @param {string} relativePath - e.g. '../index.html' for pages/ subdirectory
 */
export function requireAuth(relativePath = '../index.html') {
  const session = getSession();
  if (!session || session.account_type !== 'admin') {
    window.location.href = relativePath;
    return null;
  }
  return session;
}

export function logout(relativePath = '../index.html') {
  clearSession();
  if (typeof window.navigateTo === 'function') {
    window.navigateTo(relativePath);
  } else {
    window.location.href = relativePath;
  }
}

/* ── Initials ────────────────────────────────────── */
export function getInitials(firstName = '', lastName = '') {
  return ((firstName[0] ?? '') + (lastName[0] ?? '')).toUpperCase() || '?';
}

/* ── Display full name ───────────────────────────── */
export function fullName(row) {
  const parts = [row.first_name, row.middle_name, row.last_name].filter(Boolean);
  const name = parts.join(' ');
  return row.extension_name ? `${name} ${row.extension_name}` : name;
}

/* ── Format timestamps ───────────────────────────── */
export function fmtDate(ts) {
  if (!ts) return '—';
  return new Date(ts).toLocaleDateString('en-PH', { year: 'numeric', month: 'short', day: 'numeric' });
}

export function fmtDateTime(ts) {
  if (!ts) return '—';
  return new Date(ts).toLocaleString('en-PH', {
    year: 'numeric', month: 'short', day: 'numeric',
    hour: '2-digit', minute: '2-digit'
  });
}

/* ── Toast notifications ─────────────────────────── */
export function showToast(message, type = 'info') {
  let container = document.getElementById('toast-container');
  if (!container) {
    container = document.createElement('div');
    container.id = 'toast-container';
    document.body.appendChild(container);
  }

  const icons = { success: 'fa-circle-check', error: 'fa-circle-xmark', warning: 'fa-triangle-exclamation', info: 'fa-circle-info' };
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  toast.innerHTML = `
    <i class="fa-solid ${icons[type] ?? icons.info}"></i>
    <span class="toast-text">${message}</span>
    <button class="toast-close" onclick="this.closest('.toast').remove()"><i class="fa-solid fa-xmark"></i></button>
  `;
  container.appendChild(toast);

  setTimeout(() => {
    toast.style.animation = 'fadeOut .3s ease forwards';
    toast.addEventListener('animationend', () => toast.remove());
  }, 4000);
}

/* ── Populate sidebar & header UI ───────────────── */
export function populateHeader(session) {
  const nameEl    = document.getElementById('header-user-name');
  const avatarEl  = document.getElementById('header-avatar');
  if (nameEl)   nameEl.textContent  = fullName(session) || session.email_address || 'Admin';
  if (avatarEl) avatarEl.textContent = getInitials(session.first_name, session.last_name);
}

/* ── Mark active sidebar link ───────────────────── */
export function setActiveSidebarLink() {
  const current = window.location.pathname.split('/').pop();
  document.querySelectorAll('.sidebar-nav a').forEach(a => {
    const href = a.getAttribute('href')?.split('/').pop();
    if (href === current) a.classList.add('active');
  });
}

/* ── Sidebar toggle (mobile) ─────────────────────── */
export function initSidebarToggle() {
  const toggle  = document.getElementById('sidebar-toggle');
  const sidebar = document.querySelector('.app-sidebar');
  if (!toggle || !sidebar) return;
  toggle.addEventListener('click', () => sidebar.classList.toggle('open'));
  document.addEventListener('click', e => {
    if (sidebar.classList.contains('open') && !sidebar.contains(e.target) && e.target !== toggle) {
      sidebar.classList.remove('open');
    }
  });
}

/* ── Confirm dialog (native-like) ───────────────── */
export function confirmDialog(message) {
  return window.confirm(message);
}

/* ── Escape HTML ─────────────────────────────────── */
export function esc(str) {
  const d = document.createElement('div');
  d.textContent = str ?? '';
  return d.innerHTML;
}

/* ── Debounce ────────────────────────────────────── */
export function debounce(fn, delay = 300) {
  let t;
  return (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), delay); };
}

/* ── Audit trail helper ──────────────────────────── */
export async function logAudit(supabase, session, action, description, table_name = null, old_data = null, new_data = null) {
  try {
    await supabase.from('audit_trail').insert({
      account_id: session?.account_id ?? null,
      action,
      description,
      table_name,
      old_data,
      new_data,
      ip_address: null // can't get client IP reliably from browser
    });
  } catch (_) { /* non-critical */ }
}
