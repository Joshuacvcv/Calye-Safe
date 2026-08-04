# Calye-Safe — Documentation vs. Implementation Assessment

Review of **"A Mobile App for Calye-Safe: A GPS-Enabled Community Incident Reporting and Response Management System"** (Chapters 1–3, 46 pages) against the current codebase.

---

## 1. Executive Verdict

The documentation (Chapters 1–3) is conceptually strong: the three-pillar literature synthesis (geospatial e-governance, categorization, analytics), the research-gap argument, the theoretical frameworks, and the mixed-methods methodology are coherent and clearly connected to the artifact. However, there is a **significant stage mismatch** between the document and the code: the methodology explicitly states the project is "in the high-fidelity design stage" with backend coding yet to begin, while the repository contains a fully implemented Supabase backend, production SQL schema, OSRM routing, and authentication. Additionally, several platform/technical claims in the document (Android-native, Google Maps API, department routing, automated monthly summaries) do not match what was actually built.

**Bottom line:** the implementation is more mature than the document claims, but a handful of documented features are missing or implemented differently than described. The document needs updating to match the delivered system more than the system needs new features.

---

## 2. Documentation Claims vs. Implementation Reality

| # | Claim in the document | Where | Reality in the codebase | Verdict |
|---|-----------------------|-------|-------------------------|---------|
| 1 | "Engineered specifically for the latest **Android operating system**" | Scope, p.10 | All roles are browser-based HTML/JS/PWA-style apps (`calye-safe-community.html`, `-admins.html`, `-responders.html`); no native Android build. About screen even says "Platform: Android (mobile app)" — aspirational, not delivered | **Mismatch** |
| 2 | "Spatial mapping via the **Google Maps API**" | Conceptual Framework (IPO), p.31 | All maps use **Leaflet + OpenStreetMap** tiles (e.g., `calye-safe-community.html:3548`, `calye-safe-admins.html:4752`). Stale HTML comment "Google Maps Report Map" at `calye-safe-community.html:2463` | **Mismatch** |
| 3 | System "is currently in the **high-fidelity design stage**... before backend development and technical coding begin" | Methodology, Phase 3, p.35 | Full backend exists: 11-table schema, RLS seed, auth, storage buckets, OSRM routing (`supabase-schema.sql`, `supabase-auth.js`, `supabase-data.js`) | **Understates system maturity** |
| 4 | Multi-step verification filters "misinformation, duplicate reports, and false alarms" | Research Gap, p.25; Def. of Terms, p.14 | Implemented verification is **identity verification** (account pending/approved/rejected with ID photo, `supabase-auth.js:157`), not **report-level review**. Reports are not gated before action | **Conceptual mismatch** |
| 5 | Routing "to relevant departments such as **traffic enforcement, engineering, or waste management**" | Ch. II p.19/23; Objective B | No departments table; dispatch is a generic "Assign Responder" modal (`calye-safe-admins.html:3930`); categories are only Major/Minor | **Gap** |
| 6 | Automated tools generate "**monthly summaries**" | Objective C, Ch. II p.23 | Does not exist; "Export Report" only shows a toast (`calye-safe-admins.html:3467`); Actionable Insights is static HTML | **Gap** |
| 7 | Heatmap + analytics from incident data | Objective C, Scope | Heatmap exists (Leaflet.heat) but is fed from hardcoded/localStorage `incidentPins`, not live aggregation; no date-range/trend logic | **Partially met** |
| 8 | Emergency module with "**proximity-based safety alerts**" | Scope, p.11 | Alerts are UI/demo-only (alert banner, all-alerts modal, hotlines screen); no GPS-proximity broadcast logic. Responder dispatch is proximity-simulated | **Partial** |
| 9 | "No offline processing or localized data-queuing capabilities" | Scope & Delimitation, p.12 | Accurately matches code — no service worker/outbox exists. Document is honest here | **Consistent** |
| 10 | Rejects data outside **Santa Rosa boundaries** | Scope, p.11 | `santarosa-boundary.js` exists and is drawn on maps | **Consistent** |
| 11 | Real-time status tracking Pending → In Progress → Resolved, pushed to citizen | Scope, p.11; IPO | Implemented and exceeded (5-step timeline in admin, tracker in community app, `markReportStep`) | **Exceeded** |
| 12 | Photo + GPS metadata into centralized database | Objective A | Implemented: `reports` + `report_media` tables, Nominatim reverse geocoding, verified gate | **Met** |
| 13 | Population/sampling: 100 residents, 15 staff | p.36 | Methodology-level claim; cannot verify from code (no survey data in repo) | **Not verifiable** |
| 14 | iOS excluded, future development | Scope, p.12 | Consistent with codebase (web apps are Android-browser-friendly, no iOS-specific work) | **Consistent** |

---

## 3. System Elements That Exceed the Documentation

These are present in the code but never mentioned as deliverables in Chapters 1–3:

- **Full third role — Responder app** (`calye-safe-responders.html`): dispatch simulation, OSRM road-following route, on-site status progression, proof-of-resolution upload, escalation, on-duty toggling. The document only mentions residents and officials.
- **Production-grade SQL schema**: enums, RLS, triggers, indexes across 11 tables (`supabase-schema.sql`) — far beyond a "high-fidelity design stage."
- **Identity verification workflow** with admin review queue and auto-refresh polling — the single strongest alignment with the stated research gap, but documented as "report verification."
- **Announcements composer**, push-pin boundary drawing, notifications preferences, search across incidents/alerts.

**Implication:** if a panel member inspects the repository, they will find a much more complete system than Chapter 3 describes. This is favorable, but the mismatch should be explained (see recommendations) or the chapter updated.

---

## 4. Internal Consistency Issues in the Document (Chapters 1–3)

These are document-quality problems independent of the code:

1. **TOC vs. body figure mismatch.** TOC lists *"Figure 2: Technology Acceptance Model (TAM)"* (p.28), but the body's theoretical framework (p.28–29) presents **Swiss Cheese Model, ISO 25010, and IS Success Model** — TAM is never actually described. ISO 25010 is mislabeled as "(Technology Acceptance)."
2. **Duplicate figure numbering.** "Figure 1. Synthesis of Related Literature and Studies" (p.25) and "Figure 1. Swiss Cheese Model" (p.29) share a number.
3. **Bare figure captions.** "Figure 2." (ISO 25010) has no descriptive caption; Figure 2.1 has no space before its caption.
4. **Missing references.** `Mutambik (2024)` and `Agrawal et al. (2025)` are cited in the body (p.19/22 and p.20/23) but absent from the References list.
5. **Year inconsistency.** McKinsey is cited as 2024 in the body but listed as **(2025)** in References.
6. **Diacritic inconsistency.** "Damaševičius" appears both with and without diacritics in body and references.
7. **Inconsistent reference style.** Entries mix styles (some initial-driven, some full-name, e.g., "Bernandino P. Malang, DIT, PhD & Solis, Jennifer DT P." vs "Goh M.L.I., ..."); the ISO/IEC 25010 standard is referenced only as a framework with no citation.
8. **Sample ambiguity.** Population says 100 residents sampled from 3 barangays, but the recruitment and data-gathering sections describe survey deployment across 9 barangays — the relationship between the 3-barangay testing scope and 9-barangay data collection is not clearly reconciled.

---

## 5. Recommended Corrections (by priority)

### Documentation fixes (cheap, high value for the defense)

| Fix | Priority |
|-----|----------|
| Update Chapter 3's "high-fidelity design stage" statement to reflect that a full working backend (Supabase schema, RLS, OSRM) was implemented in the Integration & Optimization phase | **High** |
| Replace "Google Maps API" with OpenStreetMap/Leaflet in the IPO model and any other mentions | High |
| Clarify the platform: describe the deliverable as an **Android-optimized web/mobile app** (runs in Android browsers) rather than "engineered for the Android operating system" | High |
| Reconcile "Multi-Step Verification Workflow": it currently verifies **identity**, not **reports**; either rename the implemented workflow or implement report-review gating to match the research-gap claim | High |
| Fix TOC (remove TAM, correct figure numbers/captions), duplicate Figure 1, missing Mutambik/Agrawal references, McKinsey year, and reference style consistency | Medium |
| Add the Responder app and the SQL/RLS/verification work as documented deliverables/scope so the paper matches the repo | Medium |

### Code fixes to close documented-but-missing features
(Already detailed in `GAPS-AND-SOLUTIONS.md`)

- **Department routing** (Objective B) — the single most-repeated promise in the document (p.7, 10, 19, 23) with zero implementation.
- **Automated monthly summaries + real export** (Objective C) — replaces the toast-only button.
- **Live data-driven heatmap/aggregation** — the document describes "automatically processes raw coordinates and report frequencies"; the code seeds analytics from localStorage.
- **Proximity-based safety alerts** — either implement geo-triggered alerts or soften the Scope wording.

---

## 6. Bottom Line

- **Chapter quality:** high conceptual coherence; the literature review genuinely supports the design decisions (verification, categorization, heatmap).
- **Honesty issue that works in the team's favor:** the paper undersells the build. A reviewer inspecting the repo will find it *more* complete than described.
- **Documentation-vs-code gaps to close before defense:** Android-native framing, Google Maps API claim, missing department routing, missing monthly summaries, and the identity-vs-report verification wording.
