// =====================================================================================
// site.js — the top bar, menus, command palette, toasts, drawers, modals, confirm
//           prompts, and the as-of and mode pills.
//
// Progressive enhancement throughout: every action on every screen is a real form post
// that works with this file switched off. What is here upgrades those posts to a partial
// refresh and adds the chrome around them.
//
// No client-side routing, and no client-side business rule. The client may not decide
// whether a requirement is met, whether a stage is open, or what a count is.
// =====================================================================================

/* ---- small helpers -------------------------------------------------------------- */

export const $  = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

/** The anti-forgery token every write posts back. */
export function antiForgeryToken() {
  return $('input[name="__RequestVerificationToken"]')?.value ?? '';
}

/**
 * A fetch that carries the anti-forgery token and asks for a partial.
 * It never throws on a refusal: a refusal is a designed state, and the caller reads
 * `problem` out of the answer and shows it as a sentence.
 */
export async function post(url, body) {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'X-Requested-With': 'fetch',
      'RequestVerificationToken': antiForgeryToken()
    },
    body
  });

  const type = response.headers.get('content-type') ?? '';
  if (type.includes('application/json')) return response.json();

  return { ok: response.ok, html: await response.text() };
}

export async function getPartial(url) {
  const response = await fetch(url, { headers: { 'X-Requested-With': 'fetch' } });
  return response.text();
}

/* ---- toasts --------------------------------------------------------------------- */

/**
 * Every write produces a toast — ok or warn — including every refusal, with its reason.
 * The sentence always comes from the server; nothing here composes one.
 */
export function toast(message, kind = 'ok') {
  if (!message) return;

  let host = $('.ms-toasts');
  if (!host) {
    host = document.createElement('div');
    host.className = 'ms-toasts';
    host.setAttribute('role', 'status');
    host.setAttribute('aria-live', 'polite');
    document.body.append(host);
  }

  const el = document.createElement('div');
  el.className = `ms-toast ms-toast--${kind}`;
  el.innerHTML = `<div class="ms-toast__text"></div>
                  <button type="button" class="ms-toast__close" aria-label="Dismiss">×</button>`;
  $('.ms-toast__text', el).textContent = message;
  $('.ms-toast__close', el).addEventListener('click', () => el.remove());

  host.append(el);

  // A refusal stays until it is read; an acknowledgement does not need to.
  if (kind === 'ok') setTimeout(() => el.remove(), 6000);
}

/** Turns a server answer into the toast it deserves. */
export function toastResult(result, okMessage) {
  if (result?.problem) toast(result.problem, 'warn');
  else toast(result?.message ?? okMessage, 'ok');
}

/* ---- menus ---------------------------------------------------------------------- */

function initMenus() {
  const closeAll = except => {
    $$('.ms-nav__menu').forEach(menu => {
      if (menu === except) return;
      menu.hidden = true;
      menu.previousElementSibling?.setAttribute('aria-expanded', 'false');
    });
  };

  $$('.ms-nav__trigger').forEach(trigger => {
    trigger.addEventListener('click', event => {
      event.stopPropagation();
      const menu = trigger.nextElementSibling;
      if (!menu) return;
      const willOpen = menu.hidden;
      closeAll(willOpen ? menu : null);
      menu.hidden = !willOpen;
      trigger.setAttribute('aria-expanded', String(willOpen));
    });
  });

  document.addEventListener('click', () => closeAll(null));
  document.addEventListener('keydown', e => { if (e.key === 'Escape') closeAll(null); });

  // Below 992px the navigation becomes a drawer rather than disappearing.
  $('[data-nav-toggle]')?.addEventListener('click', () => $('.ms-nav')?.classList.toggle('is-open'));
}

/* ---- the command palette: it navigates, it never acts --------------------------- */

function initPalette() {
  const palette = $('.ms-palette');
  if (!palette) return;

  const input = $('.ms-palette__input', palette);
  const list = $('.ms-palette__list', palette);
  const items = $$('.ms-palette__item', list);
  let active = 0;

  const show = shown => {
    palette.hidden = !shown;
    if (shown) { input.value = ''; filter(''); input.focus(); }
  };

  const filter = term => {
    const needle = term.trim().toLowerCase();
    let first = -1;
    items.forEach((item, i) => {
      const hit = !needle || item.dataset.search?.includes(needle);
      item.hidden = !hit;
      if (hit && first < 0) first = i;
    });
    setActive(first < 0 ? 0 : first);
  };

  const setActive = index => {
    active = index;
    items.forEach((item, i) => item.classList.toggle('is-active', i === index));
    items[index]?.scrollIntoView({ block: 'nearest' });
  };

  const move = step => {
    const visible = items.map((item, i) => (item.hidden ? -1 : i)).filter(i => i >= 0);
    if (!visible.length) return;
    const at = visible.indexOf(active);
    setActive(visible[(at + step + visible.length) % visible.length]);
  };

  document.addEventListener('keydown', e => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); show(true); }
    else if (e.key === 'Escape' && !palette.hidden) show(false);
  });

  input.addEventListener('input', () => filter(input.value));
  input.addEventListener('keydown', e => {
    if (e.key === 'ArrowDown') { e.preventDefault(); move(1); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1); }
    else if (e.key === 'Enter') {
      e.preventDefault();
      const href = items[active]?.dataset.href;
      if (href) window.location.href = href;   // navigation only
    }
  });

  items.forEach((item, i) => {
    item.addEventListener('mouseenter', () => setActive(i));
    item.addEventListener('click', () => { if (item.dataset.href) window.location.href = item.dataset.href; });
  });

  palette.addEventListener('click', e => { if (e.target === palette) show(false); });
}

/* ---- drawers and modals --------------------------------------------------------- */

export function openDrawer(id, html) {
  const drawer = document.getElementById(id);
  if (!drawer) return;
  if (html !== undefined) $('.ms-drawer__body', drawer).innerHTML = html;
  drawer.hidden = false;
  drawer.querySelector('[data-close]')?.focus();
}

export function closeDrawer(id) {
  const drawer = document.getElementById(id);
  if (drawer) drawer.hidden = true;
}

export function openModal(id, html) {
  const modal = document.getElementById(id);
  if (!modal) return;
  if (html !== undefined) $('.ms-modal__body', modal).innerHTML = html;
  modal.hidden = false;
  modal.querySelector('input, select, textarea, button')?.focus();
}

export function closeModal(id) {
  const modal = document.getElementById(id);
  if (modal) modal.hidden = true;
}

function initOverlays() {
  document.addEventListener('click', e => {
    const opener = e.target.closest('[data-drawer-open], [data-modal-open]');
    if (opener) {
      const drawerId = opener.dataset.drawerOpen;
      const modalId = opener.dataset.modalOpen;
      const src = opener.dataset.src;

      if (src) {
        getPartial(src).then(html => (drawerId ? openDrawer(drawerId, html) : openModal(modalId, html)));
      } else if (drawerId) openDrawer(drawerId);
      else if (modalId) openModal(modalId);
      return;
    }

    const closer = e.target.closest('[data-close]');
    if (closer) {
      closer.closest('.ms-drawer')?.setAttribute('hidden', '');
      closer.closest('.ms-modal')?.setAttribute('hidden', '');
      return;
    }

    // Clicking the scrim closes the modal; clicking the panel does not.
    if (e.target.classList?.contains('ms-modal')) e.target.hidden = true;
  });

  document.addEventListener('keydown', e => {
    if (e.key !== 'Escape') return;
    $$('.ms-drawer:not([hidden]), .ms-modal:not([hidden])').forEach(el => (el.hidden = true));
  });
}

/* ---- confirm prompts ------------------------------------------------------------ */

/**
 * Watch and drop in review and calibration open a reason prompt. The prompt is a real
 * form; this only stops the submit until the reason is there, so the same post works
 * with JavaScript off.
 */
function initConfirms() {
  document.addEventListener('submit', e => {
    const form = e.target;
    const question = form.dataset.confirm;
    if (!question) return;

    if (!window.confirm(question)) e.preventDefault();
  });
}

/* ---- the as-of and mode pills --------------------------------------------------- */

function initPills() {
  // Test mode is an administrator's tool, and the server checks it again. This only
  // flips the cookie and reloads, so the whole request agrees about the mode.
  $('[data-test-mode]')?.addEventListener('click', event => {
    const on = event.currentTarget.dataset.testMode !== 'on';
    document.cookie = `maseera-test=${on ? '1' : '0'}; path=/; samesite=lax`;
    window.location.reload();
  });

  $('[data-sign-in-as]')?.addEventListener('change', event => {
    document.cookie = `maseera-as=${encodeURIComponent(event.target.value)}; path=/; samesite=lax`;
    window.location.reload();
  });
}

/* ---- forms that post without leaving the page ----------------------------------- */

/**
 * A form marked data-ajax posts in place and shows its own toast. Without JavaScript it
 * posts normally and the server redirects with the same toast in TempData, so the two
 * paths say exactly the same thing.
 */
function initAjaxForms() {
  document.addEventListener('submit', async e => {
    const form = e.target;
    if (!form.matches('form[data-ajax]')) return;

    e.preventDefault();
    const result = await post(form.action, new FormData(form));
    toastResult(result, form.dataset.okMessage ?? 'Saved.');

    if (result.ok && form.dataset.reloadTarget) {
      const target = $(form.dataset.reloadTarget);
      if (target) target.innerHTML = await getPartial(form.dataset.reloadUrl ?? window.location.href);
    } else if (result.ok && form.dataset.reload !== 'false') {
      window.location.reload();
    }
  });
}

/* ---- toasts the server left in TempData ----------------------------------------- */

function initServerToasts() {
  const source = $('#ms-server-toasts');
  if (!source) return;

  try {
    JSON.parse(source.textContent || '[]').forEach(t => toast(t.Message ?? t.message, t.Kind ?? t.kind));
  } catch {
    // A malformed payload must not take the page down with it.
  }
}

/* ---- start ---------------------------------------------------------------------- */

export function init() {
  initMenus();
  initPalette();
  initOverlays();
  initConfirms();
  initPills();
  initAjaxForms();
  initServerToasts();
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
else init();
