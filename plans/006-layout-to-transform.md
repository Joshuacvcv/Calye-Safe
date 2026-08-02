# 006 — Convert layout-property animations to `transform`

- **Status**: TODO
- **Commit**: 3e6d984
- **Severity**: MEDIUM
- **Category**: 5 (Performance)
- **Estimated scope**: 2 files (responder + admin)

## Problem

Two animations drive `width`/`height`, which triggers layout + paint + composite
every frame instead of the GPU-friendly `transform`:

1. **Responder dispatch countdown fill** — the 15s accept-countdown bar is driven by
   animating `width` for the entire 15 seconds:
   - CSS `calye-safe-responders.html:1736-1742`:
     ```css
     .dispatch-countdown-fill {
         height: 100%;
         width: 100%;
         background: var(--accent);
         border-radius: 3px;
         transition: width linear;
     }
     ```
   - JS `calye-safe-responders.html:3274-3284`:
     ```js
     const fill = document.getElementById('dispatch-countdown');
     fill.style.transition = 'none';
     fill.style.width = '100%';
     overlay.classList.add('show');
     requestAnimationFrame(() => {
         requestAnimationFrame(() => {
             fill.style.transition = 'width 15s linear';
             fill.style.width = '0%';
         });
     });
     ```
2. **Responder dispatch rings** — `ringExpand` animates `width`/`height` on a 2s
   infinite loop (three rings, 70px → 130px):
   - CSS `calye-safe-responders.html:1637-1649`:
     ```css
     @keyframes ringExpand {
         0% { width: 70px; height: 70px; opacity: 0.9; }
         100% { width: 130px; height: 130px; opacity: 0; }
     }
     ```
     Rings start at 70px (`calye-safe-responders.html:1619-1635`).

The admin `.bar { transition: height 0.5s ... }` (1110) and `.cat-bar { transition: width 0.6s ... }` (1151) are **dormant** — their values are static inline heights set at page load (2863–2888, 3385+), so nothing animates at runtime. They are left as-is; do not change them.

## Target

1. **Countdown fill** — scale along X instead of resizing width. The fill keeps
   `width: 100%` (its container `.dispatch-countdown` is `height: 6px`-ish, full
   width) and animates `transform: scaleX` from origin left:
   ```css
   .dispatch-countdown-fill {
       height: 100%;
       width: 100%;
       background: var(--accent);
       border-radius: 3px;
       transform: scaleX(1);
       transform-origin: left;
       transition: transform 15s linear;
   }
   ```
   JS becomes:
   ```js
   fill.style.transition = 'none';
   fill.style.transform = 'scaleX(1)';
   overlay.classList.add('show');
   requestAnimationFrame(() => {
       requestAnimationFrame(() => {
           fill.style.transition = 'transform 15s linear';
           fill.style.transform = 'scaleX(0)';
       });
   });
   ```
   (`transition: width linear` has no duration in CSS — the real duration was
   always set in JS. The new CSS carries `transform 15s linear` as the default so
   the rule is self-describing; JS still overrides `transition: none` on reset.)

2. **Dispatch rings** — animate `transform: scale` from the fixed 70px base
   (130 / 70 ≈ 1.857):
   ```css
   @keyframes ringExpand {
       0% {
           transform: scale(1);
           opacity: 0.9;
       }
       100% {
           transform: scale(1.857);
           opacity: 0;
       }
   }
   ```
   Keep `.dispatch-ring` base `width: 70px; height: 70px;` (lines 1619–1635) and
   the per-ring `animation-delay` (0s / 0.6s / 1.2s). Ensure `.dispatch-ring` has
   no conflicting `transform` (it does not today) and add `will-change: transform`
   on `.dispatch-ring` if desired — optional, not required.

## Repo conventions to follow

- The codebase already uses transform-only motion elsewhere: community `.modal-box`
  slides with `transform: translateY(100%)` (`calye-safe-community.html:1445-1453`)
  and `.notif-panel`/`.search-overlay` with `transform: translateX/Y` (1517–1613).
  The responder's own `.sheet` uses `transform: translateY` in `sheetUp` (1790–1800).
  Imitate that: movement is always `transform`, never `width`/`height`/`top`/`left`.

## Steps

1. `calye-safe-responders.html` — rewrite `.dispatch-countdown-fill` per Target (lines 1736–1742).
2. `calye-safe-responders.html` — rewrite the JS block at 3274–3284 per Target.
3. `calye-safe-responders.html` — rewrite `@keyframes ringExpand` (1637–1649) to `transform: scale(...)`.
4. Grep for `transition: width` / `transition: height` / `width:` inside any `@keyframes` to confirm none remain.

## Boundaries

- Do NOT touch admin `.bar` (1110) or `.cat-bar` (1151) — dormant transitions with static values; leave as-is.
- Do NOT change the countdown's 15s timing or the ring delays/durations.
- Do NOT alter the overlay/card markup — motion-property edits only.
- If the countdown element or ring markup has drifted (different IDs/classes), STOP and report.

## Verification

- **Mechanical**: `grep -n "transition: width\|transition: height"` and `grep -n "width:\|height:" calye-safe-responders.html` inside the keyframes range returns only the base `.dispatch-ring` 70px sizes, never a keyframe animating them.
- **Feel check**: trigger a dispatch in responder:
  - The countdown bar still drains left→right over exactly 15s, same visual as before.
  - In DevTools, enable the FPS meter / paint-flashing while the countdown runs: no full-width layout recalc each frame; the bar uses composited transform.
  - The expanding rings still grow smoothly to the same visual size and opacity over 2s.
  - Animations panel at 10% playback: ring keyframes show `scale` not `width/height`.
- **Done when**: the countdown and rings animate entirely via `transform`, visually identical to today.
