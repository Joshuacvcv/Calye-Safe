# 002 — Replace `transition: all` with targeted transitions

- **Status**: TODO
- **Commit**: 3e6d984
- **Severity**: HIGH
- **Category**: 5 (Performance)
- **Estimated scope**: 3 files, 35 `transition: all` occurrences (12 community, 17 admin, 6 responder)

## Problem

`transition: all` animates every property change on the element, including
unintended off-GPU layout/paint properties (box-shadow, transform origin changes,
etc.). It is used 35 times across the three apps on hover/press/state feedback:

- `calye-safe-community.html` — lines 447 (`.step-dot`), 582 (`.incident-type`), 701 (`.btn`), 939 (`.filter-tab`), 1061 (`.timeline-circle`), 1164 (`.upload-area`), 1254 (`.radio-opt`), 1275 (`.radio-circle`), 1982 (`.filter-tab` override), 1991 (`.incident-type` override), 2001 (`.step-dot` override), 2006 (`.btn-primary`)
- `calye-safe-admins.html` — lines 221 (`.nav-item`), 430 (`.topbar-btn`), 524 (`.stat-card`), 821 (`.btn-respond`), 1311 (`.map-btn`), 1442 (`.modal-btn`), 1630 (`#toast`), 1926 (`.ftab`), 2146 (`.ann-mini-btn`), 2172 (`.verify-filter`), 2187 (`.verify-reload-btn`), 2207 (`.verify-card`), 2337 (`.verify-btn`), 2498 (`.settings-save-btn`), plus inline `transition:all 0.16s` in template strings at 3959, 4032 (Respond buttons) and 4802 (map list rows)
- `calye-safe-responders.html` — lines 203 (`.nav-item.job-btn .job-circle`), 715 (`.filter-tab`), 1218 (`.timeline-circle`), 1324 (`.btn`), 1882 (`.upload-area`), 1937 (`.reason-chip`)

Every occurrence animates only color / background / border-color / box-shadow /
transform in practice. Scope the transition to exactly those properties so layout
and unknown properties are never animated.

## Target

For each site, list the properties that actually change on hover/active and
transition only those. The concrete rewrite per site:

| Current (abbrev.) | Target |
| --- | --- |
| `.nav-item` `all 0.16s` | `background 0.16s, color 0.16s` |
| `.topbar-btn` `all 0.16s` | `background 0.16s, border-color 0.16s` |
| `.stat-card` `all 0.2s` | `border-color 0.2s, box-shadow 0.2s, transform 0.2s` |
| `.btn-respond` `all 0.18s` | `background 0.18s, color 0.18s, border-color 0.18s, transform 0.18s, box-shadow 0.18s` |
| `.map-btn` / `.modal-btn` / `.ftab` / `.ann-mini-btn` / `.verify-filter` / `.verify-reload-btn` / `.verify-card` / `.verify-btn` / `.settings-save-btn` `all 0.16s/0.18s` | `background 0.16s, color 0.16s, border-color 0.16s` (use the site's existing duration; 0.18s where the rule uses 0.18s) |
| `#toast` `all 0.3s var(--ease-out)` (admin 1630) | `transform 0.3s var(--ease-out), opacity 0.3s var(--ease-out)` |
| `.step-dot` `all 0.35s var(--ease-spring)` (community 2001 override; base 447 `all 0.3s`) | `background 0.35s, color 0.35s` (both rules); base rule at 447 becomes `background 0.3s, color 0.3s` |
| `.incident-type` (582 base `all 0.2s`; 1991 override `all 0.2s var(--ease-out)`) | `border-color 0.2s, background 0.2s, transform 0.2s` (both rules; keep `var(--ease-out)` only on the override) |
| `.filter-tab` (939 base `all 0.2s`; 1982 override `all 0.2s var(--ease-out)`) | `background 0.2s, color 0.2s, border-color 0.2s, transform 0.2s` (both; keep `var(--ease-out)` on the override) |
| `.timeline-circle` (community 1061, responder 1218) `all 0.3s` | `background 0.3s, border-color 0.3s, box-shadow 0.3s` |
| `.upload-area` (community 1164, responder 1882) `all 0.2s` | `border-color 0.2s, background 0.2s` |
| `.radio-opt` 1254 `all 0.2s` | `border-color 0.2s, background 0.2s` |
| `.radio-circle` 1275 `all 0.2s` | `background 0.2s, border-color 0.2s` |
| `.btn` (community 701, responder 1324) `all 0.2s` | `background 0.2s, color 0.2s, transform 0.2s` |
| `.btn-primary` 2006 `all 0.2s, transform 0.15s var(--ease-spring)` | `box-shadow 0.2s, transform 0.15s var(--ease-spring)` |
| `.nav-item.job-btn .job-circle` (responder 203) `all 0.3s` | `background 0.3s, box-shadow 0.3s` |
| `.reason-chip` (responder 1937) `all 0.2s` | `background 0.2s, color 0.2s, border-color 0.2s` |
| Inline buttons (admin 3959, 4032) `transition:all 0.16s` | `transition:background 0.16s,color 0.16s,border-color 0.16s` |
| Inline map rows (admin 4802) `transition:all 0.16s` | `transition:background 0.16s,border-color 0.16s` |

Note: `all 0.3s` on `.step-dot` (447) is overridden by 2001; fix both anyway so the
base rule is correct if the override is ever removed. Same for `.incident-type`
(582/1991) and `.filter-tab` (939/1982).

## Repo conventions to follow

- Existing correct exemplars (transform+opacity only) to imitate:
  - `calye-safe-community.html:1446` — `.modal-box { transition: transform 0.35s var(--ease-spring); }`
  - `calye-safe-admins.html:1630` — `#toast` (becomes this pattern after edit)
- Durations are kept from the current rule; only the property list narrows.
- Use `var(--ease-out)` / `var(--ease-spring)` if plan 001 is applied first; if not, add the tokens to the file's `:root` (values in plan 001's Repo conventions) or inline the raw curves.

## Steps

1. In each of the three files, for every line matched by grep `transition:\s*all`, replace with the targeted property list from the table above, preserving the rule's own duration and easing token.
2. Do a second pass with `grep -n "transition:\s*all"` to confirm zero matches remain.
3. Re-check the overridden pairs (`.step-dot`, `.incident-type`, `.filter-tab`) so base + override are both fixed.

## Boundaries

- Do NOT change durations or easing values — only the property lists.
- Do NOT touch `transition: transform`, `transition: opacity`, or multi-property transitions that already avoid `all` (e.g. community 141, 151, 358, 501, 846, 973, 1895, 1930, 1952, 1962, 1972, 2006's transform, 1349, 1432).
- Do NOT touch inline styles that already avoid `all` (e.g. `calye-safe-community.html:2564, 3436, 3458` which use `transition:border 0.2s` / `border-color 0.2s`).
- If a grep hit is `transition: all` on something not in the table (drift), STOP and report.

## Verification

- **Mechanical**: `grep -rn "transition:\s*all" calye-safe-*.html` returns nothing.
- **Feel check**: run each app; hover/press/state-change the affected controls and confirm:
  - Hover color/background changes still transition at the same speed and smoothness.
  - In DevTools Animations panel at 10% playback, box-shadow/transform changes still ease the same.
  - Nothing "snaps" that previously eased — the feel must be identical, only the property set narrower.
- **Done when**: no `transition: all` remains, and spot-checking each app's main list/table hover (report table rows, queue cards, report feed cards) shows no regression.
