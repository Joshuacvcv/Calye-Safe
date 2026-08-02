# 008 — Report wizard step transition in community

- **Status**: TODO
- **Commit**: 3e6d984
- **Severity**: LOW
- **Category**: 8 (Missed opportunities)
- **Estimated scope**: 1 file

## Problem

The 3-step incident report wizard teleports between steps. `goStep`
(`calye-safe-community.html:4012-4026`) toggles each step panel's `display`:

```js
function goStep(n) {
  [1, 2, 3].forEach(i => {
    const el = document.getElementById('report-step-' + i);
    if (el) el.style.display = (i === n ? 'block' : 'none');
    const dot = document.getElementById('sdot-' + i);
    if (dot) dot.className = 'step-dot ' + (i < n ? 'done' : i === n ? 'active' : 'pending');
    ...
  });
  ...
}
```

The step *indicators* animate (`.step-dot` transitions, `.step-line` background,
`.timeline-circle` pulses) but the step *content* panel (title/type → map/location →
summary) swaps instantly with no motion — a jarring, spatially-adjacent step change
that deserves a brief transition to anchor "you moved forward in the form."

## Target

Add a lightweight entrance to the shown step panel. Because a `display:none →
block` swap restarts CSS animations on the element, no JS change is required —
only a CSS rule. Reuse the existing `@keyframes fadeUp` (community 1842–1852,
`opacity` + `translateY(14px)`):

```css
#report-step-1,
#report-step-2,
#report-step-3 {
  animation: fadeUp 0.24s var(--ease-out) both;
}
```

- `0.24s` keeps the form snappy (under the 300ms UI budget) — do not use the 0.38s feed stagger duration.
- `var(--ease-out)` (`cubic-bezier(0.23, 1, 0.32, 1)`) for a responsive start.
- Direction is forward-only (fade-up), consistent with the wizard's progress metaphor.
- Only the active panel is `display:block`, so only it animates; `display:none` panels do not run the animation.

If `@keyframes fadeUp` was removed by plan 004 (it is retained there for this
purpose, but if drift occurred), inline a local keyframe instead:
`@keyframes stepIn { from { opacity: 0; transform: translateY(12px); } to { opacity: 1; transform: none; } }`
and reference it.

## Repo conventions to follow

- Reuse existing keyframes rather than adding new ones — `fadeUp` at `calye-safe-community.html:1842` is the exemplar; the file already uses `0.38s cubic-bezier(0.22, 1, 0.36, 1)` for card entrances and `0.35s` spring for step dots (2001). The wizard content entrance should feel faster than the card stagger but consistent with the same easing family.
- Place the rule near the step markup CSS (`.step-dot` at 437) or near the `fadeUp` keyframes.

## Steps

1. Add the `#report-step-1/2/3` rule to `calye-safe-community.html` (after `.step-dot` rules, ~line 448).
2. Verify the `fadeUp` keyframe still exists (1842); if not, add the local `stepIn` keyframe per Target.
3. Confirm `grep -n "report-step-" calye-safe-community.html` shows the three IDs and the new rule.

## Boundaries

- Do NOT change `goStep` JS logic or timing.
- Do NOT animate `display` — the existing toggle stays.
- Do NOT touch the step indicators (they already transition; plan 002/001 adjusts their easing/property lists).
- Do NOT add an exit animation for the hidden step — hidden panels are `display:none`, nothing can (or should) animate out.

## Verification

- **Mechanical**: `grep -n "report-step-1," calye-safe-community.html` returns the new rule.
- **Feel check**: open the report form, step 1 → 2 (valid title + type) → 3:
  - Each forward step fades up 14px and settles in ~0.24s — a clear but brief sense of progress.
  - Going back (step 3 → 2 → 1) also fades the shown panel in (same animation) — acceptable and consistent.
  - The step dots still color/transition as before; nothing double-animates.
  - DevTools Animations panel at 10% playback: only the newly shown panel animates, once.
  - Emulate `prefers-reduced-motion: reduce`: the panel appears instantly (opacity kept if using the 001-token `--ease-out`, or instant under the plan 003 universal rule) — no movement.
- **Done when**: wizard step content transitions forward with a subtle 0.24s fade-up and no layout jump.
