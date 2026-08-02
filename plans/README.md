# Calye-Safe — Animation Audit Plans

Read-only audit produced with the `improve-animations` skill. Source files are
**not** modified by these plans; an executor applies them. Commit stamp for all
plans: `3e6d984`.

## Findings overview (prioritized)

| # | Title | Severity | Category | Scope |
| --- | --- | --- | --- | --- |
| 001 | Introduce motion tokens, kill bare `ease` and duplicate curves | HIGH | 2 + 7 | 3 files |
| 002 | Replace `transition: all` with targeted transitions (35 sites) | HIGH | 5 | 3 files |
| 003 | `prefers-reduced-motion` coverage + stop perpetual pulses | HIGH | 6 + 1 | 3 files |
| 004 | Screen-switch motion policy (community replays, responder teleports) | HIGH | 1 + 8 | 2 files |
| 005 | Standardize press feedback (weak `scale(0.98/0.99)`, admin has none) | MEDIUM | 3 | 3 files |
| 006 | Convert layout-property animations to `transform` | MEDIUM | 5 | 2 files |
| 007 | Admin modal entrance animation | MEDIUM | 8 | 1 file |
| 008 | Report wizard step transition in community | LOW | 8 | 1 file |

## Recommended execution order

1. **001** — introduces `--ease-out` / `--ease-spring` tokens that later plans reference.
2. **002** — depends on 001's tokens; rewrites `transition: all` to targeted properties.
3. **006** — converts the two live layout-property animations to `transform`.
4. **005** — press feedback values; independent of 001/002 values already applied.
5. **007** — admin modal entrance; uses 001's tokens.
6. **008** — wizard step entrance; uses 001's tokens.
7. **004** — screen-switch policy; last so the final animation surface is set before removing replays.
8. **003** — reduced-motion guard; last so it covers the final animation set.

## Dependencies

- 002, 005, 007, 008 reference `--ease-out` / `--ease-spring`. If applied before 001, add the two tokens to the file's `:root` block first (the token values are inlined in each plan's Repo conventions section).
- 004 removes the `.screen.active` keyframe rules in `calye-safe-community.html` that 003 would otherwise have to disable; order them 004 → 003.

## Notes

- All files are single self-contained HTML apps (no build, no shared CSS file). "Tokens" therefore mean CSS custom properties added to each file's own `:root`.
- Verification requires opening the three files over `localhost` (XAMPP) and using DevTools Rendering → Emulate `prefers-reduced-motion`, plus the Animations panel at 10% playback.
