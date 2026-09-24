// =====================================================================================
// tables.js — server paging, the sticky header and first column, the column picker, the
//             per-column filter popovers, saved views, row selection, the bulk bar and
//             export.
//
// Everything that decides WHAT is in the table happens on the server. This file changes
// the query string and swaps the partial the server sends back; it never filters or
// sorts rows itself, because a filter applied to the page that happens to be loaded is
// a filter over 50 of 12,480 rows.
// =====================================================================================

import { $, $$, getPartial, post, toast, toastResult } from './site.js';

const TABLE = '[data-table]';

/* ---- navigating the table -------------------------------------------------------- */

/**
 * Replaces the table partial for a new set of query parameters, and keeps the address
 * bar in step so the view survives a refresh and can be shared.
 */
async function reload(root, changes) {
  const url = new URL(window.location.href);
  for (const [key, value] of Object.entries(changes)) {
    if (value === null || value === undefined || value === '') url.searchParams.delete(key);
    else url.searchParams.set(key, value);
  }

  root.setAttribute('aria-busy', 'true');
  const html = await getPartial(url.toString());
  root.outerHTML = html;
  window.history.replaceState({}, '', url.toString());

  // The partial replaced the node, so the new one has to be wired up.
  wire($(TABLE));
}

/* ---- per-column filters ---------------------------------------------------------- */

/** The filters currently applied, as the server's JSON shape. */
function readFilters(root) {
  try { return JSON.parse(root.dataset.filters || '[]'); } catch { return []; }
}

function writeFilters(root, filters) {
  const kept = filters.filter(f => f.values?.length);
  return kept.length ? JSON.stringify(kept) : null;
}

/**
 * The value list comes from a procedure, with counts — never from the rows on screen.
 * A sensitive column comes back refused, with a sentence saying why.
 */
async function openFilter(root, button) {
  const column = button.dataset.column;
  const existing = $('.ms-popover', button.parentElement);
  if (existing) { existing.remove(); return; }

  const popover = document.createElement('div');
  popover.className = 'ms-popover';
  popover.innerHTML = '<div class="ms-micro">Loading…</div>';
  button.parentElement.append(popover);

  const url = new URL(root.dataset.columnValuesUrl, window.location.origin);
  url.searchParams.set('cycleStageId', root.dataset.cycleStageId ?? '');
  url.searchParams.set('columnName', column);

  const response = await fetch(url, { headers: { 'X-Requested-With': 'fetch' } });
  const data = await response.json();

  if (!data.ok) {
    // Refused, not empty. The difference matters and the panel shows it.
    popover.innerHTML = '<div class="ms-refusal"><div class="ms-refusal__title">Not available as a filter</div><p></p></div>';
    $('.ms-refusal p', popover).textContent = data.problem;
    return;
  }

  const chosen = new Set(readFilters(root).find(f => f.field === column)?.values ?? []);

  popover.innerHTML = `
    <input type="search" class="ms-input" placeholder="Search values" data-filter-search>
    <div class="ms-popover__values" role="group" aria-label="Values"></div>
    <div class="ms-popover__foot">
      <button type="button" class="ms-btn ms-btn--sm" data-filter-clear>Clear</button>
      <button type="button" class="ms-btn ms-btn--sm ms-btn--primary" data-filter-apply>Apply</button>
    </div>`;

  const values = $('.ms-popover__values', popover);
  data.values.forEach(v => {
    const label = document.createElement('label');
    label.className = 'ms-popover__value';
    label.innerHTML = `<input type="checkbox" value=""><span class="ms-popover__text"></span>
                       <span class="ms-num ms-popover__count"></span>`;
    const box = $('input', label);
    box.value = v.value ?? '';
    box.checked = chosen.has(v.value ?? '');
    $('.ms-popover__text', label).textContent = v.value || '(not recorded)';
    $('.ms-popover__count', label).textContent = v.count.toLocaleString();
    values.append(label);
  });

  $('[data-filter-search]', popover).addEventListener('input', e => {
    const needle = e.target.value.trim().toLowerCase();
    $$('.ms-popover__value', values).forEach(row => {
      row.hidden = needle && !$('.ms-popover__text', row).textContent.toLowerCase().includes(needle);
    });
  });

  $('[data-filter-clear]', popover).addEventListener('click', () => {
    const filters = readFilters(root).filter(f => f.field !== column);
    reload(root, { filters: writeFilters(root, filters), page: 1 });
  });

  $('[data-filter-apply]', popover).addEventListener('click', () => {
    const picked = $$('input:checked', values).map(i => i.value);
    const filters = readFilters(root).filter(f => f.field !== column);
    if (picked.length) filters.push({ field: column, values: picked });
    // Filters combine: every applied column narrows the set further.
    reload(root, { filters: writeFilters(root, filters), page: 1 });
  });
}

/* ---- selection and the bulk bar --------------------------------------------------- */

function selected(root) {
  return $$('input[data-row-select]:checked', root).map(i => i.value);
}

function refreshBulkBar(root) {
  const bar = $('[data-bulk-bar]', root);
  if (!bar) return;

  const count = selected(root).length;
  bar.hidden = count === 0;
  const label = $('[data-bulk-count]', bar);
  if (label) label.textContent = count === 1 ? '1 person selected' : `${count} people selected`;

  $$('[data-bulk-needs-selection]', bar).forEach(el => (el.disabled = count === 0));
}

/* ---- the column picker and saved views -------------------------------------------- */

function initColumnPicker(root) {
  const picker = $('[data-column-picker]', root);
  if (!picker) return;

  $('[data-columns-apply]', picker)?.addEventListener('click', () => {
    const chosen = $$('input[data-column]:checked', picker).map(i => i.value);
    reload(root, { columns: chosen.join(','), page: 1 });
  });

  $('[data-columns-search]', picker)?.addEventListener('input', e => {
    const needle = e.target.value.trim().toLowerCase();
    $$('[data-column-row]', picker).forEach(row => {
      row.hidden = needle && !row.dataset.search.includes(needle);
    });
  });

  $('[data-columns-save]', picker)?.addEventListener('click', async e => {
    const chosen = $$('input[data-column]:checked', picker).map(i => i.value);
    const body = new FormData();
    body.set('screenCode', root.dataset.screenCode ?? '');
    body.set('viewName', 'Default');
    body.set('columnList', chosen.join(','));
    body.set('asPreset', e.currentTarget.dataset.preset === 'true');
    toastResult(await post(root.dataset.saveViewUrl, body), 'Your columns were saved.');
  });

  $('[data-columns-reset]', picker)?.addEventListener('click', async () => {
    const body = new FormData();
    body.set('screenCode', root.dataset.screenCode ?? '');
    body.set('viewName', 'Default');
    await post(root.dataset.resetViewUrl, body);
    reload(root, { columns: null, page: 1 });
  });
}

/* ---- export ----------------------------------------------------------------------- */

function initExport(root) {
  // The export streams from the same procedure with paging off, so it is a plain link
  // carrying the current filters rather than anything assembled from the DOM.
  $$('[data-export]', root).forEach(link => {
    link.addEventListener('click', () => {
      const url = new URL(link.href, window.location.origin);
      const here = new URL(window.location.href);
      ['q', 'filters', 'pill', 'sort', 'dir'].forEach(key => {
        const value = here.searchParams.get(key);
        if (value) url.searchParams.set(key, value);
      });
      link.href = url.toString();
    });
  });
}

/* ---- wiring ----------------------------------------------------------------------- */

export function wire(root) {
  if (!root) return;

  // Paging, sorting, the funnel pills and the page size all go back to the server.
  $$('[data-page]', root).forEach(el => el.addEventListener('click', e => {
    e.preventDefault();
    reload(root, { page: el.dataset.page });
  }));

  $$('[data-sort]', root).forEach(el => el.addEventListener('click', e => {
    e.preventDefault();
    const column = el.dataset.sort;
    const dir = root.dataset.sortBy === column && root.dataset.sortDir === 'ASC' ? 'DESC' : 'ASC';
    reload(root, { sort: column, dir, page: 1 });
  }));

  $$('[data-pill]', root).forEach(el => el.addEventListener('click', e => {
    e.preventDefault();
    const pill = el.dataset.pill;
    reload(root, { pill: root.dataset.activePill === pill ? null : pill, page: 1 });
  }));

  $('[data-page-size]', root)?.addEventListener('change', e => reload(root, { size: e.target.value, page: 1 }));

  let searchTimer;
  $('[data-table-search]', root)?.addEventListener('input', e => {
    clearTimeout(searchTimer);
    const value = e.target.value;
    searchTimer = setTimeout(() => reload(root, { q: value, page: 1 }), 300);
  });

  $$('[data-column-filter]', root).forEach(button =>
    button.addEventListener('click', e => { e.stopPropagation(); openFilter(root, button); }));

  document.addEventListener('click', () => $$('.ms-popover', root).forEach(p => p.remove()));

  $$('input[data-row-select]', root).forEach(box =>
    box.addEventListener('change', () => {
      box.closest('tr')?.classList.toggle('is-selected', box.checked);
      refreshBulkBar(root);
    }));

  $('[data-select-all]', root)?.addEventListener('change', e => {
    $$('input[data-row-select]', root).forEach(box => {
      box.checked = e.target.checked;
      box.closest('tr')?.classList.toggle('is-selected', box.checked);
    });
    refreshBulkBar(root);
  });

  // A bulk action posts the selection as a table-valued parameter on the server side;
  // here it is just the checked values on one form.
  $$('[data-bulk-action]', root).forEach(button =>
    button.addEventListener('click', async () => {
      const people = selected(root);
      if (!people.length) return;

      const body = new FormData();
      people.forEach(p => body.append('personnelNo', p));
      for (const [key, value] of Object.entries(button.dataset)) {
        if (key.startsWith('arg')) body.set(key.slice(3).toLowerCase(), value);
      }

      const result = await post(button.dataset.bulkAction, body);
      toastResult(result, button.dataset.okMessage ?? 'Done.');
      if (result.ok) reload(root, {});
    }));

  initColumnPicker(root);
  initExport(root);
  refreshBulkBar(root);

  // "Compare first 6" reads the setting the server put on the table.
  $('[data-compare-selection]', root)?.addEventListener('click', e => {
    const max = Number(root.dataset.compareMax ?? 6);
    const people = selected(root).slice(0, max);
    if (!people.length) { toast('Nobody is selected to compare.', 'warn'); e.preventDefault(); return; }

    const url = new URL(e.currentTarget.href, window.location.origin);
    people.forEach(p => url.searchParams.append('personnelNo', p));
    e.currentTarget.href = url.toString();
  });
}

export function init() {
  wire($(TABLE));
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
else init();
