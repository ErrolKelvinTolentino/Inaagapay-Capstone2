const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');

function element() {
  const classes = new Set();
  return {
    attrs: {}, events: {}, focused: false,
    classList: {
      contains: value => classes.has(value),
      add: value => classes.add(value), remove: value => classes.delete(value),
      toggle(value, force = !classes.has(value)) {
        if (force) classes.add(value); else classes.delete(value);
      },
    },
    setAttribute(name, value) { this.attrs[name] = value; },
    addEventListener(name, handler, capture) { this.events[name] = { handler, capture }; },
    focus() { this.focused = true; },
  };
}

function navigation(width) {
  const source = fs.readFileSync('admin-web/pages/common-security.js', 'utf8');
  const start = source.indexOf('  function initResponsiveSidebar()');
  const end = source.indexOf('  if (document.readyState', start);
  const toggle = element(), sidebar = element(), body = element();
  let backdrop = null, railToggles = 0;
  const document = {
    body: Object.assign(body, { appendChild(el) { backdrop = el; } }),
    getElementById: () => toggle,
    querySelector: selector => selector === '.app-sidebar' ? sidebar : backdrop,
    createElement: element,
    addEventListener: body.addEventListener.bind(body),
  };
  const window = {
    innerWidth: width, events: {},
    AdminSidebar: { toggle() { railToggles++; } },
    addEventListener: body.addEventListener.bind(body),
  };
  vm.runInNewContext(source.slice(start, end) + '\ninitResponsiveSidebar();', {
    window, document, MutationObserver: class { observe() {} },
  });
  return { toggle, sidebar, body, window, get backdrop() { return backdrop; },
    get railToggles() { return railToggles; }, click() {
      let intercepted = false;
      toggle.events.click.handler({ stopImmediatePropagation() { intercepted = true; } });
      assert.equal(intercepted, true);
      assert.equal(toggle.events.click.capture, true);
    },
  };
}

test('desktop activation collapses the rail without opening a drawer backdrop', () => {
  const nav = navigation(1366);
  nav.click(); nav.click();
  assert.equal(nav.railToggles, 2);
  assert.equal(nav.sidebar.classList.contains('open'), false);
  assert.equal(nav.backdrop.classList.contains('show'), false);
  assert.equal(nav.body.classList.contains('sidebar-open'), false);
});

test('mobile activation opens and closes the drawer, preserving focus on dismissal', () => {
  const nav = navigation(390);
  nav.click();
  assert.equal(nav.railToggles, 0);
  assert.equal(nav.sidebar.classList.contains('open'), true);
  assert.equal(nav.backdrop.classList.contains('show'), true);
  assert.equal(nav.toggle.attrs['aria-expanded'], 'true');
  nav.backdrop.events.click.handler();
  assert.equal(nav.sidebar.classList.contains('open'), false);
  assert.equal(nav.toggle.focused, true);
});

test('resizing an open drawer to desktop removes its backdrop', () => {
  const nav = navigation(390);
  nav.click();
  nav.window.innerWidth = 1366;
  nav.body.events.resize.handler();
  assert.equal(nav.sidebar.classList.contains('open'), false);
  assert.equal(nav.backdrop.classList.contains('show'), false);
});

test('an empty notification bell has no visible zero; unread counts still render', () => {
  const source = fs.readFileSync('admin-web/pages/notification-center.js', 'utf8');
  const start = source.indexOf('  function renderCount()');
  const end = source.indexOf('  function renderList()', start);
  const badge = element(), bell = element();
  for (const count of [0, 3, 120]) {
    vm.runInNewContext(source.slice(start, end) + '\nrenderCount();', {
      document: { getElementById: () => badge }, bell, unreadCount: () => count,
    });
    assert.equal(badge.hidden, count === 0);
    assert.equal(badge.textContent, count === 0 ? '' : count > 99 ? '99+' : String(count));
    assert.equal(bell.classList.contains('has-unread'), count > 0);
  }
});
