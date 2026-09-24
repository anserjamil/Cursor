// =====================================================================================
// idp.js — the individual development plan board.
//
// Tab switching, session pickers, seat counts, multi-select booking, Suggest, Approve
// and conflict badges.
//
// Every seat count shown here comes from the server. This file may show that a session
// has two places left; it may not decide that booking three into it is fine. The
// procedure refuses that, with a sentence naming how many places are left, and this
// shows the sentence.
// =====================================================================================

import { $, $$, post, getPartial, toast, toastResult } from './site.js';

const ROOT = '[data-idp]';

/* ---- tabs ------------------------------------------------------------------------ */

/**
 * Tabs are links first. This swaps the panel in place and keeps the address bar in step,
 * so the same URL opens the same tab on a refresh or when it is shared.
 */
function initTabs(root) {
  $$('[data-idp-tab]', root).forEach(tab =>
    tab.addEventListener('click', async e => {
      e.preventDefault();

      const url = new URL(tab.href, window.location.origin);
      const panel = $('[data-idp-panel]', root);
      if (!panel) { window.location.href = url.toString(); return; }

      panel.setAttribute('aria-busy', 'true');
      panel.innerHTML = await getPartial(url.toString());
      panel.removeAttribute('aria-busy');

      $$('[data-idp-tab]', root).forEach(t => t.classList.toggle('is-current', t === tab));
      window.history.pushState({}, '', url.toString());
      wirePanel(root);
    }));

  window.addEventListener('popstate', () => window.location.reload());
}

/* ---- the session picker ---------------------------------------------------------- */

/**
 * The last option in a session dropdown is always "pencil in a date", because a
 * requirement with no scheduled session still has to be planned.
 */
function initSessionPickers(root) {
  $$('[data-session-picker]', root).forEach(select => {
    const row = select.closest('[data-idp-item]');
    const dateBox = $('[data-pencil-date]', row);

    const sync = () => {
      const pencil = select.value === 'PENCIL';
      if (dateBox) { dateBox.hidden = !pencil; dateBox.disabled = !pencil; }

      // A session after the person's target date is still offered, and still flagged.
      const late = select.selectedOptions[0]?.dataset.afterTarget === 'true';
      $('[data-late-warning]', row)?.toggleAttribute('hidden', !late);
    };

    select.addEventListener('change', () => { sync(); submitRow(row); });
    sync();
  });
}

async function submitRow(row) {
  const form = row?.closest('form');
  if (!form) return;

  const result = await post(form.action, new FormData(form));
  toastResult(result, 'Saved.');

  // The seat count the server just recomputed replaces the one on screen.
  if (result.ok && typeof result.seatsLeft === 'number') {
    const seats = $('[data-seats-left]', row);
    if (seats) seats.textContent = result.seatsLeft;
  }

  if (result.ok) refreshProgress(row.closest(ROOT));
}

/* ---- multi-select booking --------------------------------------------------------- */

function selectedPeople(scope) {
  return $$('input[data-idp-select]:checked', scope).map(i => i.value);
}

function initBulkBooking(root) {
  $$('[data-book-session]', root).forEach(card => {
    const button = $('[data-book-go]', card);
    const seatsLeft = Number(card.dataset.seatsLeft ?? 'NaN');

    const refresh = () => {
      const picked = selectedPeople(card.closest('[data-book-scope]') ?? root).length;
      const label = $('[data-book-count]', card);
      if (label) label.textContent = picked ? `Book ${picked}` : 'Book';

      // A warning, not a block: the server decides, and says how many places are left.
      const over = !Number.isNaN(seatsLeft) && picked > seatsLeft;
      $('[data-over-seats]', card)?.toggleAttribute('hidden', !over);
      if (button) button.disabled = picked === 0;
    };

    $$('input[data-idp-select]', root).forEach(box => box.addEventListener('change', refresh));

    button?.addEventListener('click', async () => {
      const people = selectedPeople(card.closest('[data-book-scope]') ?? root);
      if (!people.length) return;

      const body = new FormData();
      body.set('cycleStageId', root.dataset.cycleStageId);
      body.set('devSessionId', card.dataset.bookSession);
      people.forEach(p => body.append('personnelNo', p));

      const result = await post(root.dataset.bookUrl, body);
      toastResult(result, `${people.length} booked.`);
      if (result.ok) window.location.reload();
    });

    refresh();
  });
}

/* ---- Suggest --------------------------------------------------------------------- */

/**
 * Suggest returns what it DID, as sentences. They are shown rather than summarised,
 * because "coverage was left for you" is the sentence a planner most needs to read.
 */
function initSuggest(root) {
  $$('[data-suggest]', root).forEach(button =>
    button.addEventListener('click', async () => {
      button.disabled = true;
      button.dataset.busy = 'true';

      try {
        const body = new FormData();
        body.set('cycleStageId', root.dataset.cycleStageId);
        if (button.dataset.suggest !== 'all') body.set('personnelNo', button.dataset.suggest);

        const result = await post(root.dataset.suggestUrl, body);

        if (result.problem) { toast(result.problem, 'warn'); return; }

        const list = $('[data-suggest-output]', root);
        if (list && result.sentences?.length) {
          list.innerHTML = '';
          result.sentences.forEach(sentence => {
            const li = document.createElement('li');
            li.className = 'ms-suggest__line';
            li.textContent = sentence;
            list.append(li);
          });
          list.closest('[data-suggest-panel]')?.removeAttribute('hidden');
        }

        toast(result.changed
          ? `${result.changed} requirement${result.changed === 1 ? ' was' : 's were'} planned.`
          : 'There was nothing left to plan.', 'ok');

        if (result.changed) setTimeout(() => window.location.reload(), 1200);
      } finally {
        button.disabled = false;
        delete button.dataset.busy;
      }
    }));
}

/* ---- Approve ---------------------------------------------------------------------- */

function initApprove(root) {
  $$('[data-approve]', root).forEach(button =>
    button.addEventListener('click', async () => {
      const who = button.dataset.approve === 'ready'
        ? $$('[data-plan-ready="true"]', root).map(el => el.dataset.personnelNo)
        : [button.dataset.approve];

      if (!who.length) { toast('Nobody has a plan ready to approve yet.', 'warn'); return; }

      const body = new FormData();
      body.set('cycleStageId', root.dataset.cycleStageId);
      who.forEach(p => body.append('personnelNo', p));

      const result = await post(root.dataset.approveUrl, body);
      toastResult(result, who.length === 1 ? 'Approved and notified.' : `${who.length} plans approved.`);

      // After a plan completes the person STAYS on screen in the finished state, so the
      // row is updated in place rather than the list being re-sorted under the cursor.
      if (result.ok) {
        who.forEach(p => {
          const row = $(`[data-person-row="${CSS.escape(p)}"]`, root);
          if (!row) return;
          row.dataset.planState = 'APPROVED';
          row.classList.add('is-approved');
          const state = $('[data-plan-state]', row);
          if (state) state.textContent = 'Approved';
          $$('[data-approve]', row).forEach(b => (b.disabled = true));
        });
      }
    }));
}

/* ---- conflicts and progress -------------------------------------------------------- */

function initConflicts(root) {
  $$('[data-conflict-badge]', root).forEach(badge =>
    badge.addEventListener('click', async () => {
      const panel = $('[data-conflict-panel]', root);
      if (!panel) return;
      panel.hidden = false;
      panel.innerHTML = await getPartial(badge.dataset.conflictBadge);
    }));
}

/** The progress bars come back from the server; nothing here recomputes them. */
async function refreshProgress(root) {
  const bar = $('[data-idp-progress]', root);
  if (!bar?.dataset.url) return;
  bar.innerHTML = await getPartial(bar.dataset.url);
}

/* ---- wiring ------------------------------------------------------------------------ */

function wirePanel(root) {
  initSessionPickers(root);
  initBulkBooking(root);
  initSuggest(root);
  initApprove(root);
  initConflicts(root);
}

export function init() {
  const root = $(ROOT);
  if (!root) return;

  initTabs(root);
  wirePanel(root);
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
else init();
