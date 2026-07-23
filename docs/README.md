# FlowRep — Dokumentation

> **Stand**: 2026-07-23 · Struktur bereinigt  
> Einstieg für Menschen und KI.

## Wo beginne ich?

| Ziel | Pfad |
|------|------|
| **1.0 Produkt-Status / was offen ist** | [`Version1.0/13_OFFENE_PUNKTE.md`](Version1.0/13_OFFENE_PUNKTE.md) |
| **1.0 Living Tracker** | [`Version1.0/`](Version1.0/) (00, 10–13) |
| **CV Skelett-Overlay Plan** | [`Version1.0/14_CV_SKELETT_OVERLAY_PLAN.md`](Version1.0/14_CV_SKELETT_OVERLAY_PLAN.md) |
| **Post-1.0 Backlog (V1.1+)** | [`Version1.0/15_VERBESSERUNGEN_EXTERNE_REPOS.md`](Version1.0/15_VERBESSERUNGEN_EXTERNE_REPOS.md) |
| **BLE-Protokoll (kanonisch)** | [`reference/protocol.yaml`](reference/protocol.yaml) |
| **Architektur** | [`reference/GYM_TRACKER_ARCHITEKTUR.md`](reference/GYM_TRACKER_ARCHITEKTUR.md) |
| **Setup (Adi)** | [`reference/SETUP_ANLEITUNG.md`](reference/SETUP_ANLEITUNG.md) · [`reference/ANLEITUNG_FUER_ADI.md`](reference/ANLEITUNG_FUER_ADI.md) |
| **Hardware-QA** | [`hardware/`](hardware/) · [`Version1.0/11_HARDWARE_QA_CHECKLISTE.md`](Version1.0/11_HARDWARE_QA_CHECKLISTE.md) |
| **Design / Spec / Recherche** | [`design/`](design/) |
| **Historisches (Umbauplan, alte DoD)** | [`archive/`](archive/) |

## Ordnerstruktur

```
docs/
├── README.md                 ← diese Datei
├── Version1.0/               ← AKTIV: Product 1.0 Pläne + Living Tracker
├── reference/                ← AKTIV: Protokoll, ADRs, Glossar, Setup, Architektur
├── hardware/                 ← AKTIV: Testprotokolle + Session-Evidence
│   └── sessions/YYYY-MM-DD/
├── design/                   ← AKTIV-NACHSCHLAG: Specs, Kalib-Konzept, Recherchen
└── archive/                  ← HISTORISCH: Umbauplan, Phasen-DoD, Legacy-Onboarding
    ├── umbauplan/
    └── process/
```

## Regeln

1. **Living Status** nur in `Version1.0/10–13` und ggf. `hardware/sessions/`.  
2. **Protokoll-Wahrheit** nur `reference/protocol.yaml` (nicht in Prosa neu definieren).  
3. **`_useNewPipeline = true`** nicht ohne Shadow-DoD (siehe Version1.0).  
4. `archive/` nicht als aktuellen Stand zitieren; nur Hintergrund.

## Frühere Pfade (Umzug 2026-07-23)

| Alt | Neu |
|-----|-----|
| `docs/reference/protocol.yaml` | `docs/reference/protocol.yaml` |
| `docs/reference/GYM_TRACKER_ARCHITEKTUR.md` | `docs/reference/GYM_TRACKER_ARCHITEKTUR.md` |
| `docs/04_ARCHITECTURE_DECISION_RECORDS.md` | `docs/reference/ARCHITECTURE_DECISION_RECORDS.md` |
| `docs/reference/SETUP_ANLEITUNG.md` | `docs/reference/SETUP_ANLEITUNG.md` |
| `docs/Umbauplan Flowrep/*` | `docs/archive/umbauplan/*` |
| `docs/hardware/sessions/*` | `docs/hardware/` |
| `docs/Version1.0/HW_VALIDATION_*.md` | `docs/hardware/sessions/2026-07-23/HW_VALIDATION.md` |
| `docs/README.md` | `docs/archive/process/…` (ersetzt durch dieses README) |
