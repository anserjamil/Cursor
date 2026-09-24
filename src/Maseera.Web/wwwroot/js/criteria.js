// =====================================================================================
// criteria.js — the criteria builder and the completion-rule editor.
//
// Sets, modes, joins, an operator list driven by the field's data type, Arity-aware value
// editors, the rule read back as a sentence, and the live reach.
//
// The sentence and the reach both come from the server. This file decides which value
// boxes to show and which operators to offer — nothing else. It may not decide whether a
// requirement is met, or what a count is.
// =====================================================================================

import { $, $$, post, getPartial, toastResult } from './site.js';

/* ---- the operator list, driven by the field's data type ------------------------- */

/**
 * The operators are rendered once by the server with the data types each applies to, so
 * this narrows an existing list rather than inventing one. cfg.Operator.AppliesTo decides
 * what is offered; there is no operator list in this file.
 */
function operatorsFor(select, dataType) {
  let firstVisible = null;

  $$('option', select).forEach(option => {
    if (!option.value) return;
    const applies = (option.dataset.appliesTo ?? '').split(',');
    const hit = !dataType || applies.includes(dataType);
    option.hidden = !hit;
    option.disabled = !hit;
    if (hit && !firstVisible) firstVisible = option;
  });

  // Never carry over an operator that reads as nonsense: if what was chosen no longer
  // applies to this field, fall back to the first one that does.
  const chosen = select.selectedOptions[0];
  if (!chosen || chosen.disabled) select.value = firstVisible?.value ?? '';
}

/** How many value boxes this operator collects, from its own Arity. */
function arityOf(select) {
  return Number(select.selectedOptions[0]?.dataset.arity ?? 1);
}

function applyArity(row) {
  const select = $('[data-operator]', row);
  if (!select) return;

  const arity = arityOf(select);
  const v1 = $('[data-value1]', row);
  const v2 = $('[data-value2]', row);

  if (v1) { v1.hidden = arity < 1; v1.disabled = arity < 1; if (arity < 1) v1.value = ''; }
  if (v2) { v2.hidden = arity < 2; v2.disabled = arity < 2; if (arity < 2) v2.value = ''; }

  // "is one of" and "is none of" take a list, so the box says so.
  const takesList = select.selectedOptions[0]?.dataset.list === 'true';
  if (v1) v1.placeholder = takesList ? 'One value per comma' : 'Value';
}

/** The field proposes its own operator when it is first chosen. */
function proposeOperator(row) {
  const field = $('[data-field]', row);
  const operator = $('[data-operator]', row);
  if (!field || !operator) return;

  const option = field.selectedOptions[0];
  const dataType = option?.dataset.dataType ?? 'text';
  operatorsFor(operator, dataType);

  const proposed = option?.dataset.proposedOperator;
  if (proposed && !operator.dataset.touched) {
    const candidate = $$('option', operator).find(o => o.value === proposed && !o.disabled);
    if (candidate) operator.value = proposed;
  }

  applyArity(row);
}

/* ---- the live sentence and the live reach --------------------------------------- */

/**
 * Both come back from the server, because both are built by the same functions the
 * engine uses. A sentence composed here would be a second implementation of the rule.
 */
async function refreshPreview(root) {
  const url = root.dataset.previewUrl;
  if (!url) return;

  const target = $('[data-preview]', root);
  if (!target) return;

  target.setAttribute('aria-busy', 'true');
  target.innerHTML = await getPartial(url);
  target.removeAttribute('aria-busy');
}

let previewTimer;
function schedulePreview(root) {
  clearTimeout(previewTimer);
  previewTimer = setTimeout(() => refreshPreview(root), 400);
}

/* ---- saving --------------------------------------------------------------------- */

async function saveRow(root, row) {
  const form = row.closest('form');
  if (!form) return;

  const result = await post(form.action, new FormData(form));
  toastResult(result, 'Saved.');

  if (result.ok) {
    // The phrase the server read back replaces what was typed, so the two agree.
    const phrase = $('[data-phrase]', row);
    if (phrase && result.phrase) phrase.textContent = result.phrase;
    schedulePreview(root);
  }
}

/* ---- wiring ---------------------------------------------------------------------- */

function wireRow(root, row) {
  const field = $('[data-field]', row);
  const operator = $('[data-operator]', row);

  field?.addEventListener('change', () => { proposeOperator(row); saveRow(root, row); });

  operator?.addEventListener('change', () => {
    operator.dataset.touched = 'true';
    applyArity(row);
    saveRow(root, row);
  });

  $$('[data-value1], [data-value2]', row).forEach(input => {
    let timer;
    input.addEventListener('input', () => {
      clearTimeout(timer);
      timer = setTimeout(() => saveRow(root, row), 600);
    });
  });

  // Shown on load so a saved rule opens with the right number of boxes.
  proposeOperator(row);
}

export function init() {
  const root = $('[data-criteria]');
  if (!root) return;

  $$('[data-condition-row]', root).forEach(row => wireRow(root, row));

  // The set mode selector is shown even when there is only one set: one set with
  // "any one" is a legitimate rule, and hiding the selector hides that.
  $$('[data-set-mode], [data-set-join]', root).forEach(select =>
    select.addEventListener('change', async () => {
      const form = select.closest('form');
      if (!form) return;
      toastResult(await post(form.action, new FormData(form)), 'The set was saved.');
      schedulePreview(root);
    }));

  // A condition added or removed re-reads the whole rule, because the join to the set
  // before it may have changed too.
  $$('[data-add-condition], [data-remove-condition], [data-add-set], [data-remove-set]', root)
    .forEach(button => button.addEventListener('click', () => setTimeout(() => schedulePreview(root), 100)));

  // The floor of a summed kind lives on the rule panel and is edited inline.
  $('[data-sum-floor]', root)?.addEventListener('change', async e => {
    const form = e.target.closest('form');
    if (!form) return;
    toastResult(await post(form.action, new FormData(form)), 'The floor was saved.');
    schedulePreview(root);
  });

  refreshPreview(root);
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
else init();
