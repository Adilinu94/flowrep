# FlowRep — Dokumentation

> **Stand**: 2026-07-24 · Living Docs + HW-Plan aktuell  
> Einstieg für Menschen und KI.

## Wo beginne ich?

| Ziel | Pfad |
|------|------|
| **1.0 Produkt-Status / was offen ist** | [`Version1.0/13_OFFENE_PUNKTE.md`](Version1.0/13_OFFENE_PUNKTE.md) |
| **Aktueller Hardware-Testplan (P0–P3)** | [`hardware/PLAN_HW_TEST_AKTUELL.md`](hardware/PLAN_HW_TEST_AKTUELL.md) |
| **1.0 Living Tracker** | [`Version1.0/`](Version1.0/) (00, 10–13) |
| **Full-Repo Improvement Audit** | [`design/AUDIT_FULL_REPO_IMPROVEMENTS.md`](design/AUDIT_FULL_REPO_IMPROVEMENTS.md) |
| **CV Skelett-Overlay Plan** | [`Version1.0/14_CV_SKELETT_OVERLAY_PLAN.md`](Version1.0/14_CV_SKELETT_OVERLAY_PLAN.md) |
| **Post-1.0 Backlog (V1.1+)** | [`Version1.0/15_VERBESSERUNGEN_EXTERNE_REPOS.md`](Version1.0/15_VERBESSERUNGEN_EXTERNE_REPOS.md) |
| **BLE-Protokoll (kanonisch)** | [`reference/protocol.yaml`](reference/protocol.yaml) |
| **Architektur** | [`reference/GYM_TRACKER_ARCHITEKTUR.md`](reference/GYM_TRACKER_ARCHITEKTUR.md) |
| **Setup (Adi)** | [`reference/SETUP_ANLEITUNG.md`](reference/SETUP_ANLEITUNG.md) · [`reference/ANLEITUNG_FUER_ADI.md`](reference/ANLEITUNG_FUER_ADI.md) |
| **Hardware-QA Checklist** | [`Version1.0/11_HARDWARE_QA_CHECKLISTE.md`](Version1.0/11_HARDWARE_QA_CHECKLISTE.md) · [`hardware/`](hardware/) |
| **Design / Spec / Recherche** | [`design/`](design/) |
| **Historisches (Umbauplan, alte DoD)** | [`archive/`](archive/) |

## Ordnerstruktur

```
docs/
├── README.md                 ← diese Datei
├── Version1.0/               ← AKTIV: Product 1.0 Pläne + Living Tracker
├── reference/                ← AKTIV: Protokoll, ADRs, Glossar, Setup, Architektur
├── hardware/                 ← AKTIV: Testpläne + Session-Evidence
│   ├── PLAN_HW_TEST_AKTUELL.md
│   └── sessions/YYYY-MM-DD/
├── design/                   ← AKTIV-NACHSCHLAG: Audit, Specs, Kalib, Recherchen
└── archive/                  ← HISTORISCH: Umbauplan, Phasen-DoD, Legacy-Onboarding
    ├── umbauplan/
    └── process/
```

## Regeln

1. **Living Status** nur in `Version1.0/10–13` und ggf. `hardware/sessions/`.  
2. **Protokoll-Wahrheit** nur `reference/protocol.yaml` (nicht in Prosa neu definieren).  
3. **`_useNewPipeline = true`** nicht ohne Shadow-DoD (siehe Version1.0).  
4. `archive/` nicht als aktuellen Stand zitieren; nur Hintergrund.  
5. **Device-Pulls / Logs** bleiben lokal (`data/`, `*.log`) — nicht committen.

## Code-Stand (Kurz, 2026-07-24)

- Product-Pfad: IMU gP, manuelles Satzende, Korrektur-Learn  
- Trust-UX: Status-Chip, Auto-Arm (persisted), Health/Placement/Quality, Active-Set HUD  
- Vision: Form-Check + Agreement-Badge (kein Count-Override)  
- BLE: Dual-Scan FlowRep + GymTracker  
- Settings: volle Prefs-Suite + Übungsziele in `UserPrefsStore`  
- Gate: physische A1–A5-Kurzchecks (siehe HW-Plan)
