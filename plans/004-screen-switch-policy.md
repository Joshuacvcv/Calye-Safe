# 004 — Screen-switch motion policy (community replays, responder teleports)

- **Status**: TODO
- **Commit**: 3e6d984
- **Severity**: HIGH
- **Category**: 1 (Purpose & frequency) + 8 (Missed opportunities)
- **Estimated scope**: 2 files

## Problem

The two mobile apps treat screen navigation opposite ways, and both are wrong:

1. **Community app replays a 320–380ms staggered entrance on every bottom-nav tap.**
   `switchScreen` force-restarts animations (`calye-safe-community.html:3962-3979`):
   ```js
   // Force animation replay by briefly removing/re-adding active class
   el.style.animation = 'none';
   el.classList.add('active');
   el.scrollTop = 0;
   // Re-trigger animations on child elements
   el.querySelectorAll('.card,.announcement-card,.report-card,...').forEach(c => {
     c.style.animation = 'none';
     void c.offsetWidth; // reflow
     c.style.animation = '';
   });
   ```
   Combined with the CSS `.screen.active` → `screenEnter 0.32s` (1837–1839) and the
   stagger `.screen.active .card, ...` → `fadeUp 0.38s` with per-index delays
   (1854–1891), every nav press (tens of times per day) waits on a 380ms cascade.
   Additionally, the 10-second Supabase poll re-renders the reports list
   (`syncMyReports` → `renderReports`, `calye-safe-community.html:5037-5041`),
   and because those `.report-card` elements sit inside `.screen.active`, the whole
   feed replays its 0.38s stagger on every poll — a visible flash every 10s.

2. **Responder app has no screen transition at all.** `switchScreen`
   (`calye-safe-responders.html:2631-2641`) toggles `display:none` → `flex` instantly
   (`.screen`/`.screen.active`, lines 102–112). Content teleports with no motion
   explaining where it came from.

The apps are the same product family, so their nav feel should match.

## Target

Both apps use a fast, non-staggered, 200ms ease-out fade for screen content on
first paint only — and nothing on subsequent tab switches.

- **Community**: delete the forced-replay JS and the `.screen.active` keyframe/stagger rules so nav taps are instant and the 10s poll no longer flashes the feed.
  - Remove `calye-safe-community.html:3967-3978` (the comment, `el.style.animation='none'`, the `querySelectorAll(...).forEach` reflow block, and `void el.offsetWidth; el.style.animation='';`), leaving:
    ```js
    const el = document.getElementById('screen-' + name);
    if (el) {
      el.classList.add('active');
      el.scrollTop = 0;
    }
    ```
  - Remove the rule at 1837–1839 (`.screen.active { animation: screenEnter ... }`) and the whole stagger block 1854–1891 (`.screen.active .card, ...` through the `:nth-child(n+4)` rule). Keep the `@keyframes screenEnter` / `@keyframes fadeUp` definitions (still used elsewhere: `fadeUp` for the wizard in plan 008) or delete them if unused after all edits.
  - Keep `headerSlideDown` (2031–2033) only if the header is static on every screen; it currently replays per switch too — remove the replay by deleting 2019–2033 rule if the header is always present, or scope it to the app-shell's first paint only. Simplest: delete 2031–2033 (`.screen.active .screen-header, .screen.active .profile-header { animation: headerSlideDown ... }`) and 2019–2029 (`@keyframes headerSlideDown`) if now unused.
- **Responder**: add a subtle first-paint-friendly entrance that does NOT replay per switch. Since all screens render their content in `switchScreen` (renderHome/renderQueue/renderHistory), the entrance should live on the screen container but with the replay disabled the same way community does it after the fix. Simplest consistent target: no per-switch animation on the container; instead animate only the screen's freshly rendered content on first load with one rule gated to a one-time class:
  ```css
  .screen:first-child.active { animation: screenIn 0.2s var(--ease-out) both; }
  @keyframes screenIn {
    from { opacity: 0; transform: translateY(8px); }
    to   { opacity: 1; transform: none; }
  }
  ```
  `:first-child.active` matches only the initial screen, so it never replays on nav. (If markup order makes `:first-child` unreliable, add a `once` class to the home screen's static markup instead.)

## Repo conventions to follow

- Use `var(--ease-out)` (plan 001 token). If not applied yet, inline `cubic-bezier(0.23, 1, 0.32, 1)`.
- The responder already has a `@keyframes` style consistent with community (e.g. `livedot` at 507, `pulse-circle` at 1249) — add `screenIn` alongside them.
- Exemplar for the "no replay on repeated triggers" pattern: community's own `switchScreen` is the anti-pattern; the fix is the target.

## Steps

1. `calye-safe-community.html` — strip the forced-replay block from `switchScreen` (3967–3978) per Target.
2. `calye-safe-community.html` — delete `.screen.active` screenEnter rule (1837–1839).
3. `calye-safe-community.html` — delete the fadeUp stagger rules (1854–1891).
4. `calye-safe-community.html` — delete `.screen.active .screen-header, .screen.active .profile-header` headerSlideDown rule (2031–2033) and the now-unused `@keyframes headerSlideDown` (2019–2029). Leave `@keyframes fadeUp` and `@keyframes screenEnter` in place if referenced elsewhere; if `grep` shows zero references, remove them.
5. `calye-safe-responders.html` — add the `screenIn` keyframe + `:first-child.active` rule near the other keyframes (after line 112).
6. Verify `switchScreen` in both files contains no animation-force code.

## Boundaries

- Do NOT touch `fadeUp` used by `renderReports`'s empty-state or by plan 008.
- Do NOT change the `screenEnter`/`fadeUp` keyframe definitions that other rules may still reference.
- Do NOT restructure `switchScreen` beyond removing the force-replay block.
- If community markup is re-rendered by the poll and a feed item should still animate on arrival (nice-to-have), that is a separate concern — do not add it here.

## Verification

- **Mechanical**: `grep -n "force Animation replay\|void c.offsetWidth\|style.animation" calye-safe-community.html` returns nothing; `grep -n "screenIn\|:first-child.active" calye-safe-responders.html` returns hits.
- **Feel check**: run community, tap through all five bottom-nav tabs rapidly:
  - Screens switch instantly with no 320–380ms cascade; no content flash.
  - Leave the app on Home/My Reports for 30s (2–3 poll cycles) — the report list does NOT replay its entrance.
  - Run responder, switch Home/Queue/History — screens appear with a quick 200ms ease-out on first paint, nothing on repeated switches.
  - In DevTools Animations panel at 10% playback, the responder first paint fades smoothly, and community nav has zero animation entries.
- **Done when**: nav feels instant in community with no poll flash, and responder's first paint has a subtle fade that never replays.
