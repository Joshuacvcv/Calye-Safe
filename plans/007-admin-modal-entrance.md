# 007 — Admin modal entrance animation

- **Status**: TODO
- **Commit**: 3e6d984
- **Severity**: MEDIUM
- **Category**: 8 (Missed opportunities)
- **Estimated scope**: 1 file

## Problem

Admin modals appear instantly. `.modal-overlay` toggles `display:none` → `flex`
(`calye-safe-admins.html:1362-1375`) and `.modal-box` has no entrance animation —
the dispatch, resolve, photo, and verify-detail modals teleport onto the screen with
no motion explaining where they came from. This is a state change that jumps
(category 8), in an app whose dashboards otherwise ease in (`fadeUp`, toast, pulse).

Modals are exempt from the transform-origin rule (they appear centered), so a
center scale + fade is the correct entrance.

## Target

Add a short, crisp entrance — `scale(0.95)` + fade from center, easing in with the
motion token — gated to the open state so it plays once per open and does not run
while hidden (`display:none` prevents animation):

```css
.modal-overlay.open {
  display: flex;
  animation: modalFadeIn 0.2s ease both; /* overlay: opacity only */
}

@keyframes modalFadeIn {
  from { opacity: 0; }
  to   { opacity: 1; }
}

.modal-overlay.open .modal-box {
  animation: modalIn 0.24s var(--ease-out) both;
}

@keyframes modalIn {
  from {
    opacity: 0;
    transform: scale(0.95) translateY(4px);
  }
  to {
    opacity: 1;
    transform: scale(1) translateY(0);
  }
}
```

- Overlay fade: `0.2s ease` (opacity only, no movement — allowed under reduced motion to stay).
- Box: `0.24s` with `var(--ease-out)` (`cubic-bezier(0.23, 1, 0.32, 1)`), starting at `scale(0.95)` — never `scale(0)`.
- `transform-origin: center` is correct for modals; do not set it to trigger-based.

Because the overlay uses `display:none` toggling, there is no exit transition
without JS restructure (removing `.open` drops it instantly). That is an accepted
limitation for this prototype — do not refactor the toggle to opacity-based.

## Repo conventions to follow

- Existing exemplar of an entrance keyframe: `@keyframes fadeUp` (1689–1699) used by `.panel, .stat-card, .priority-card` (1701–1705) — same shape (opacity + translate), imitate its style but use the modal-specific scale so it reads as "the modal arrived," not "the page scrolled."
- Place the new rules next to the existing modal CSS (after line 1375) and the keyframes near the other `@keyframes` (after `fadeUp` at 1699).

## Steps

1. Add `animation: modalFadeIn 0.2s ease both;` to `.modal-overlay.open` (line 1373–1375).
2. Add `animation: modalIn 0.24s var(--ease-out) both;` to `.modal-overlay.open .modal-box` (new rule after 1385).
3. Add the two `@keyframes` blocks (after line 1699).
4. Confirm `grep -n "scale(0)"` finds nothing in `calye-safe-admins.html`.

## Boundaries

- Do NOT add exit animations (the `display:none` toggle precludes them without JS changes — out of scope).
- Do NOT animate `transform-origin` or make the modal scale from a trigger point.
- Do NOT touch the community bottom-sheet modal (`.modal-overlay` / `.modal-box` at `calye-safe-community.html:1422-1453`) — it already transitions correctly.
- If `--ease-out` is not defined (plan 001 pending), inline `cubic-bezier(0.23, 1, 0.32, 1)` and note it in the commit.

## Verification

- **Mechanical**: `grep -n "modalFadeIn\|modalIn"` in `calye-safe-admins.html` returns the rule + keyframes.
- **Feel check**: open any modal (Dispatch, Respond, Resolve, verify detail):
  - The overlay fades in over 0.2s, then the box scales from 0.95 to 1 with a fast ease-out start — no "appear out of nowhere," no overshoot bounce.
  - Rapidly close/reopen: the animation replays cleanly each open (element re-enters the render tree, animation restarts from the `from` keyframe).
  - DevTools Animations panel at 10% playback: the box's first frames are `scale(0.95)` + partial opacity, settling at 0.24s.
  - Emulate `prefers-reduced-motion: reduce`: the box still appears (opacity retained if the universal rule from plan 003 is applied, it will be instant) — no jank.
- **Done when**: every admin modal enters with the center scale+fade and never with `scale(0)`.
