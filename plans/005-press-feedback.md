# 005 — Standardize press feedback

- **Status**: TODO
- **Commit**: 3e6d984
- **Severity**: MEDIUM
- **Category**: 3 (Physicality & origin)
- **Estimated scope**: 3 files

## Problem

Press feedback is either imperceptible or missing, so taps give no physical
confirmation:

- Too subtle to feel — scale barely changes:
  - `calye-safe-community.html:714-716` — `.btn-primary:active { transform: scale(0.99); }`
  - `calye-safe-community.html:976-978` — `.report-card:active { transform: scale(0.99); }`
  - `calye-safe-responders.html:1339-1341` — `.btn:active { transform: scale(0.99); }`
  - `calye-safe-responders.html:556-558` — `.queue-card:active { transform: scale(0.99); }`
- Too strong — past the 0.95–0.98 subtle band (nav/call buttons are large targets):
  - `calye-safe-community.html:1898-1900` — `.nav-item:active { transform: scale(0.88); }`
  - `calye-safe-community.html:1975-1978` — `.call-btn:active { transform: scale(0.88); }`
- Missing entirely — `calye-safe-admins.html` has **no `:active` rule anywhere**,
  so none of its ~30 buttons, nav items, verify cards, or filter tabs give press
  feedback.

The AUDIT target for press feedback is `transform: scale(0.97)` on `:active` with
`transition: transform 160ms ease-out`, kept subtle (0.95–0.98).

## Target

1. Normalize the four imperceptible ones to `scale(0.97)`.
2. Soften the two oversized nav/call buttons to `scale(0.95)` (they are 40–52px circular targets; 0.95 still reads clearly but stops the "jelly" squash).
3. Add `:active { transform: scale(0.97); }` to admin's primary interactive controls, and add `transform 160ms var(--ease-out)` (or the file's existing `--ease-spring` for consistency with community's bouncy controls — use `var(--ease-spring)` where the element already bounces, else `var(--ease-out)`) to their transition lists so the press animates.

Exact edits:

- Community:
  - `.btn-primary:active` (714) → `transform: scale(0.97);`
  - `.report-card:active` (976) → `transform: scale(0.97);`
  - `.nav-item:active` (1898) → `transform: scale(0.95);`
  - `.call-btn:active` (1975) → `transform: scale(0.95);`
  - `.incident-type:active` (588) already `scale(0.97)` — leave it.
- Responder:
  - `.btn:active` (1339) → `transform: scale(0.97);`
  - `.queue-card:active` (556) → `transform: scale(0.97);`
- Admin — add to each rule's `transition` list `transform 160ms` and append:
  - `.nav-item:active` → `transform: scale(0.97);` (add after `.nav-item:hover`, line 239)
  - `.topbar-btn:active` → `transform: scale(0.97);` (after 434)
  - `.btn-respond:active` → `transform: scale(0.97);` (after the hover rules)
  - `.modal-btn:active` → `transform: scale(0.97);` (after 1450)
  - `.ftab:active` → `transform: scale(0.97);` (after 1930)
  - `.verify-filter:active` → `transform: scale(0.97);` (after 2192)
  - `.verify-card:active` → `transform: scale(0.97);` (after 2210)
  - `.verify-btn:active` → `transform: scale(0.97);` (after 2348)
  - `.settings-save-btn:active` → `transform: scale(0.97);` (after 2501)
  - `.map-btn:active` → `transform: scale(0.97);` (after 1317)
  - `.ann-mini-btn:active` → `transform: scale(0.97);` (after 2149)
  - `.verify-reload-btn:active` → `transform: scale(0.97);` (after 2189)

For each admin rule, extend the existing `transition: ...` list with `transform 160ms`
(e.g. `.nav-item` becomes `transition: background 0.16s, color 0.16s, transform 160ms;`
if plan 002 is applied first, or `transition: all 0.16s` still works if 002 is pending —
in that case add `transform 160ms` to the `all` list). Use `var(--ease-out)` as the
easing token for transform on the neutral admin controls.

## Repo conventions to follow

- Correct-scale exemplars already in the codebase: `calye-safe-community.html:588`
  (`.incident-type:active { transform: scale(0.97); }`) and `:597`-style subtle transforms.
- The recommended transition shorthand is `transition: transform 160ms ease-out`;
  with the plan-001 token it becomes `transition: transform 160ms var(--ease-out)`.

## Steps

1. Apply the four `0.99 → 0.97` and two `0.88 → 0.95` edits in community/responder.
2. Add the 12 admin `:active` rules + transform transitions.
3. Grep all three files for `:active` and confirm every interactive control has a scale press in the 0.95–0.98 band.

## Boundaries

- Do NOT add `:active` to elements that are not press targets (`.modal-overlay`, `.toggle-slider`, `label`).
- Do NOT change existing `:active` background/box-shadow rules (e.g. `.service-item:active`, `.profile-menu-item:active` keep their backgrounds — only ensure they also have a scale if they are buttons; they currently don't scale, which is acceptable).
- Do NOT touch the camera shutter press handlers (`calye-safe-community.html:5281-5282, 5290-5291`) — they already implement `scale(0.98)` via inline JS; optionally normalize to `0.97` but that is out of scope for this plan.
- If plan 002 is not yet applied, `transition: all 0.16s` plus `transform 160ms` in the same list is valid CSS; do not reformat it.

## Verification

- **Mechanical**: `grep -n ":active"` in all three files lists every pressable control; no `scale(0.99)`/`scale(0.98)`/`scale(0.88)` remains except the camera inline handlers.
- **Feel check**: on a touch device or DevTools touch emulation:
  - Tapping the community primary button, report card, nav items, and call buttons gives an immediate, perceptible squash-and-release (~160ms), no jelly.
  - Admin sidebar nav, Respond, dispatch-modal buttons, verify cards all respond with a visible 0.97 press.
  - DevTools Animations panel at 10% playback: the press is a single quick scale that settles before release.
  - Under reduced motion (emulate), the press transform is instant (no lingering animation).
- **Done when**: every primary interactive control across the three apps gives consistent 0.95–0.97 press feedback.
