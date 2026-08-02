# 001 — Introduce motion tokens, kill bare `ease` and duplicate curves

- **Status**: TODO
- **Commit**: 3e6d984
- **Severity**: HIGH
- **Category**: 2 (Easing & duration) + 7 (Cohesion & tokens)
- **Estimated scope**: 3 files, ~14 edits + 3 `:root` blocks

## Problem

Entrances and in-screen movement use bare CSS `ease` or hand-typed near-identical
curves, so motion is weak and inconsistent across the three apps.

- `ease` starts slow, delaying the exact moment the user is watching:
  - `calye-safe-admins.html:1704` — `.panel, .stat-card, .priority-card { animation: fadeUp 0.35s ease both; }`
  - `calye-safe-admins.html:1736` — `#notif-panel { ... animation: fadeUp 0.2s ease both; }`
  - `calye-safe-responders.html:1787` — `.sheet { ... animation: sheetUp 0.25s ease; }`
- The same "strong ease-out" curve is hand-typed 6+ times with two micro-variants
  (`cubic-bezier(0.22, 1, 0.36, 1)` in community/admin and `cubic-bezier(.22, 1, .36, 1)`
  in admin) instead of living as one token:
  - `calye-safe-community.html:1838`, `1861`, `1930`, `1962`, `1982`, `1991`, `2033`
  - `calye-safe-admins.html:1110`, `1151`, `1630`
- The bouncy overshoot curve `cubic-bezier(0.34, 1.56, 0.64, 1)` is also duplicated:
  - `calye-safe-community.html:1446`, `1482`, `1895`, `1904`, `1908`, `1972`, `2001`, `2006`

This is the exact "five hand-typed cubic-beziers that almost match" consolidation
finding. Because every one of these edits targets the same two values, they merge
into one plan.

## Target

Add three motion tokens to each file's `:root` (matching the existing
`--radius-sm`, `--shadow` var convention) and replace every occurrence:

```css
--ease-out: cubic-bezier(0.23, 1, 0.32, 1);        /* strong ease-out for entrances (replaces 0.22,1,0.36,1) */
--ease-in-out: cubic-bezier(0.77, 0, 0.175, 1);    /* reserved for on-screen movement; not required by this plan */
--ease-spring: cubic-bezier(0.34, 1.56, 0.64, 1);  /* bouncy press/overshoot, reused as-is */
```

Then, in each file, replace:

1. `animation: ... ease` → `animation: ... var(--ease-out)`
2. `cubic-bezier(0.22, 1, 0.36, 1)` → `var(--ease-out)` (and admin's `cubic-bezier(.22, 1, .36, 1)` → `var(--ease-out)`)
3. `cubic-bezier(0.34, 1.56, 0.64, 1)` → `var(--ease-spring)`

Keep durations exactly as they are today (this plan is easing-only — duration
changes live in their own plans).

## Repo conventions to follow

- Tokens are CSS custom properties in the single `:root { ... }` block of each file:
  - `calye-safe-community.html:27` — insert after `--shadow-lg` (line 45), before the closing `}`
  - `calye-safe-admins.html:28` — insert after `--sidebar-w` (line 65)
  - `calye-safe-responders.html:22` — insert after `--status-h` (line 46)
- Exemplar for a strong curve already used deliberately: `calye-safe-community.html:1838`
  `animation: screenEnter 0.32s cubic-bezier(0.22, 1, 0.36, 1) both;` — the intent is right,
  it just needs to become the token.

## Steps

1. `calye-safe-community.html` `:root` (line 27–48): add the three tokens above before the closing `}`.
2. `calye-safe-community.html` — replace `cubic-bezier(0.22, 1, 0.36, 1)` with `var(--ease-out)` at lines 1838, 1861, 1930, 1962, 1982, 1991, 2033.
3. `calye-safe-community.html` — replace `cubic-bezier(0.34, 1.56, 0.64, 1)` with `var(--ease-spring)` at lines 1446, 1482, 1895, 1904, 1908, 1972, 2001, 2006.
4. `calye-safe-admins.html` `:root` (line 28–66): add the three tokens before the closing `}`.
5. `calye-safe-admins.html` — replace `cubic-bezier(.22, 1, .36, 1)` (note: no spaces after commas) with `var(--ease-out)` at lines 1110, 1151, 1630.
6. `calye-safe-admins.html` — replace `animation: fadeUp 0.35s ease both;` (line 1704) with `animation: fadeUp 0.35s var(--ease-out) both;`.
7. `calye-safe-admins.html` — replace `animation: fadeUp 0.2s ease both;` (line 1736) with `animation: fadeUp 0.2s var(--ease-out) both;`.
8. `calye-safe-responders.html` `:root` (line 22–47): add the three tokens before the closing `}`.
9. `calye-safe-responders.html` — replace `animation: sheetUp 0.25s ease;` (line 1787) with `animation: sheetUp 0.25s var(--ease-out);`.
10. Grep the whole repo for `cubic-bezier` and `ease;` and ` ease` on `animation:`/`transition:` lines to confirm only `var(--ease-out)` / `var(--ease-spring)` remain (the `ease-in-out` instances on infinite state pulses are intentionally left — they are constant loops, see plan 003).

## Boundaries

- Do NOT change durations, keyframe geometry, or any `transition` property list. This is a token/easing pass only.
- Do NOT touch `ease-in-out` on the infinite pulse loops (`alertPulse`, `pulse-fade`, `livedot`, `camBlink`) — plan 003 handles those.
- Do NOT touch the inline `transition: transform 0.1s` on camera buttons (`calye-safe-community.html:5208, 5280, 5289`) or the `cubic-bezier(0.4, 0, 0.2, 1)` panel/sheet curves (1518, 1606) — those are deliberate and different.
- If a line number does not match a `cubic-bezier(0.22, 1, 0.36, 1)` / `cubic-bezier(0.34, 1.56, 0.64, 1)` / `ease` token, STOP and report drift instead of guessing.

## Verification

- **Mechanical**: `git diff` should show only `:root` additions and easing value swaps — no duration or property-list changes.
- **Feel check**: run all three apps, trigger the entrances (admin dashboard load, admin notification panel, responder resolve sheet), and confirm:
  - The entrance starts fast and decelerates (no slow start like `ease`).
  - In DevTools Animations panel at 10% playback, the curve easing is applied to the first frames.
  - The bouncy overshoot elements (`success-icon` pop-in, nav-item taps in community) behave identically to before — the curve value is unchanged.
- **Done when**: no bare `ease`/`linear` remains on any entrance in the three files, and `grep -c "cubic-bezier" calye-safe-*.html` returns 0 (all replaced by tokens).
