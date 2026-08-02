# 003 — `prefers-reduced-motion` coverage + stop perpetual pulses

- **Status**: TODO
- **Commit**: 3e6d984
- **Severity**: HIGH
- **Category**: 6 (Accessibility) + 1 (Purpose & frequency)
- **Estimated scope**: 3 files

## Problem

Only `calye-safe-admins.html` has any reduced-motion handling, and it covers a
single rule: `@media (prefers-reduced-motion:reduce)` at line 109–114 disables only
`.pulse-dot::after`. Everything else in all three apps animates regardless of the
user's OS setting:

- `calye-safe-community.html` — no reduced-motion block at all. Active motion: `fieldShake` (515, 561), `pulse-circle` (1072), `pop-in` (1482), `screenEnter` (1838), `fadeUp` stagger (1861), `alertPulse` infinite (1925), `headerSlideDown` (2033), hover lifts on `.report-card`/`.incident-type`/`.btn-primary` (1955–2016).
- `calye-safe-responders.html` — no reduced-motion block at all. Active motion: `jobPulse` infinite (209), `livedot` infinite (504), `pulse-circle` infinite (1229), `navspin` (919), `ringExpand` (1616), `sheetUp` (1787).
- `calye-safe-admins.html` — remaining motion unguarded: `borderPulse` infinite (911), `pulse-fade` infinite (1001, 1010), `fadeUp` (1704, 1736).

Perpetual pulsing is also overused on elements that are always on screen, where a
never-ending loop has no information value once the user has seen it:
`.alert-banner` runs `alertPulse 2.8s ease-in-out infinite` (community 1925) forever,
and the responder job circle runs `jobPulse 1.8s infinite` (209) the entire time a
job is live. These should run once (on state change) or be reduced to a static
shadow, and they must be disabled under reduced motion.

## Target

Add a per-file reduced-motion block that keeps opacity/color feedback but removes
movement, plus gate hover lifts behind fine pointers. Copy the recommended pattern:

```css
@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

This is the standard accessibility-conservative kill, but the AUDIT bar is
"fewer and gentler, not zero." Because this codebase has no `useReducedMotion`
hook, the CSS above is the right mechanical target for the prototype; the 
`transition-duration` clause preserves instantaneous opacity/color state feedback
while removing all movement. (If a gentler variant is preferred, a hand-curated
per-selector `animation: none` list is in plan 004/007's spirit, but the universal
rule is the safer, self-contained default.)

Additionally, replace the two perpetual attention loops with one-shot animations:

1. `calye-safe-community.html:1925` — `.alert-banner { animation: alertPulse 2.8s ease-in-out infinite; }`
   → `animation: alertPulse 2.8s ease-in-out;` (plays once on render). The banner's
   resting box-shadow (keyframe 0%/100%) is a static `0 4px 16px rgba(229,57,53,0.25)`
   — acceptable as a constant state, no loop needed.
2. `calye-safe-responders.html:209` — `.nav-item.job-btn.live .job-circle { ... animation: jobPulse 1.8s infinite; }`
   → `animation: jobPulse 1.8s ease-in-out;` (plays once when the job goes live).

## Repo conventions to follow

- Existing exemplar: `calye-safe-admins.html:109-114` — the `@media (prefers-reduced-motion:reduce)` block. Extend it rather than adding a second one in the same file.
- Blocks live at the end of the file's `<style>` so they win the cascade over later rules (CSS: last rule wins at equal specificity). Community `</style>` is before `</head>` at ~line 2160; admin at 2508; responder at ~line 1955.

## Steps

1. `calye-safe-community.html` — add the universal reduced-motion block just before the closing `</style>`.
2. `calye-safe-community.html` — change `.alert-banner` animation (line 1925) from `infinite` to one-shot (remove `infinite`).
3. `calye-safe-admins.html` — replace the existing block at 109–114 with the universal block (the `.pulse-dot::after { animation: none; }` inside it is subsumed by the universal rule; keep `display:none` removal too).
4. `calye-safe-responders.html` — add the universal reduced-motion block just before the closing `</style>`.
5. `calye-safe-responders.html` — change `.nav-item.job-btn.live .job-circle` animation (line 209) from `infinite` to one-shot.
6. Add hover-lift gating to the three apps' existing `:hover` transform lifts. In each file add:
   ```css
   @media (hover: hover) and (pointer: fine) {
     /* keep existing hover lifts */
   }
   ```
   Wrap the transform-bearing hover rules only: community `.report-card:hover` (1955), `.incident-type:hover` (1994), `.btn-primary:hover` (2009), `.service-item:hover` (if any transform), admin `.stat-card:hover` (528), `.btn-respond.primary:hover` (830), `.settings-save-btn:hover` (2501), responder (none transform-based today — skip). Background/border-color hover changes may stay ungated.

## Boundaries

- Do NOT delete any keyframes or other animation rules — only gate them.
- Do NOT remove the `livedot`, `pulse-fade`, or `pulse-circle` keyframes or their use on live/active state indicators (these are state meaning, not decoration); the universal rule disables them under reduced motion automatically.
- Do NOT change durations. `alertPulse`/`jobPulse` keep `2.8s`/`1.8s`, only `infinite` is removed.
- If the `.alert-banner`/`.job-circle` markup has drifted (different class), STOP and report.

## Verification

- **Mechanical**: `grep -n "prefers-reduced-motion" calye-safe-*.html` returns a hit in all three files; `grep -n "infinite"` no longer lists `alertPulse` or `jobPulse`.
- **Feel check**: DevTools Rendering → Emulate `prefers-reduced-motion: reduce`, then:
  - Community: open the app, switch screens, submit a form with an empty field — everything appears instantly, no shake, no slide, but the red error border still appears (state feedback kept).
  - Responder: trigger a dispatch — the ring animation and countdown fill do not animate (plan 006 converts the fill; under reduced motion it should jump), but accept/decline buttons still respond.
  - Admin: load dashboard — panels appear instantly, no pulse dots.
  - On a real mouse (fine pointer): hover lifts still work; on a touch emulation, tap does not fire a lingering hover transform.
- **Done when**: all three files honor reduced motion with no movement, and the two perpetual loops (`alertPulse`, `jobPulse`) play once.
