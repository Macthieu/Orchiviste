# S2 Closure Note (Program Level)

Date: 2026-04-14

## Scope audited
- Orchiviste
- MuniAnalyse
- MuniRegles
- MuniRenommage

All four repositories were verified on `main...origin/main` at audit time.

## Final status by sub-phase

| Sub-phase | Final status | Evidence |
| --- | --- | --- |
| S0 | Done | Orchiviste commits `10fd8b01`, `92430d0a` |
| S2.1 | Done | MuniRegles `785ca18`; MuniRenommage `bd2807f`, `d4f165b`; MuniAnalyse `d9bb834`, `dcbb437`; Orchiviste `eb1e114a` |
| S2.2 | Done (documented at closure) | MuniAnalyse extraction chain commits `2b3644a`, `2677470`, `3ea5971`, `a577598`, `d8373ae`; MuniRenommage integration commits `d4d7e90`, `940e1cd`, `a9046fc`, `43aa927` |
| S2.3 | Done | MuniRenommage commits `2e1451d`, `b3388e8`, `690adb5`, `593963d`, `eb44b5b`, `18c34b3` |
| S2.4 | Covered indirectly (absorbed) | Orchiviste commits `eb1e114a`, `5da43bd1`, `273e0372`, `8f2d8c4d` |
| S2.5 | Done | Orchiviste commits `5da43bd1`, `273e0372`, `8f2d8c4d` |

## Backlog to commits mapping (concise)

### S0
- S0-T1 demo fixtures tracked: Orchiviste `10fd8b01`
- S0-T2 stash scope documented: Orchiviste `92430d0a`

### S2.1
- S2.1-T1 bundle requirements contract: MuniRegles `785ca18`
- S2.1-T2 trace keys and fallback reasons normalized: MuniRenommage `bd2807f`, `d4f165b`
- S2.1-T3 extraction provenance + structured warnings: MuniAnalyse `d9bb834`, `dcbb437`
- S2.1-T4 diagnostics surfaced in Pilotage/Historique: Orchiviste `eb1e114a`

### S2.2
- Minimal deterministic extraction from PDFs:
  - MuniAnalyse `2b3644a`, `2677470`, `3ea5971`, `a577598`, `d8373ae`
- Controlled rule application from MuniRegles + document metadata:
  - MuniRenommage `d4d7e90`, `940e1cd`, `a9046fc`, `43aa927`

### S2.3
- Required metadata preflight: MuniRenommage `2e1451d`, `b3388e8`
- Preview/apply parity guard (`plan_digest`): MuniRenommage `690adb5`, `593963d`
- Deterministic collision + idempotence behavior: MuniRenommage `eb44b5b`, `18c34b3`

### S2.4 (explicit treatment)
No standalone S2.4 commit series was named during execution.
Its intent is considered covered indirectly by delivered and pushed work:
- Diagnostics visibility in UI/History: Orchiviste `eb1e114a`
- Positive E2E chain validation: Orchiviste `5da43bd1`
- Negative E2E chain validation: Orchiviste `273e0372`
- Manual CI entrypoint for rename-chain hardening smokes: Orchiviste `8f2d8c4d`

Decision at program level: **S2.4 is absorbed by S2.1-T4 + S2.5-T1/T2/T3 and does not remain open as a separate blocking stream.**

### S2.5
- Positive E2E smoke: Orchiviste `5da43bd1`
- Negative E2E smoke: Orchiviste `273e0372`
- Manual workflow dispatch for both smokes: Orchiviste `8f2d8c4d`

## Delivered technical baseline at S2 close
- Deterministic metadata extraction path is in place.
- MuniRegles contract fields are exposed and consumed.
- MuniRenommage canonical flow is hardened (preflight, parity, collisions/idempotence, diagnostics).
- Orchiviste surfaces chain diagnostics and provides manual CI smoke execution for positive/negative runs.

## Explicit closure verdict
**S2 is declared complete at program level.**

Reasoning:
- All planned technical objectives for S0, S2.1, S2.2, S2.3, S2.5 are delivered and pushed.
- S2.4 intent is explicitly absorbed by shipped UI diagnostics and E2E/CI hardening work listed above.

## Scope reminder
- Existing UI stash remains outside S2:
  - `stash@{0}: wip(ui): cockpit.leaf en attente validation visuelle`
