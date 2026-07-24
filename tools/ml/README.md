# FlowRep ML tools (Doc 15)

## `loso_eval.py` (FR-A9)

Leave-One-Subject-Out evaluation for exercise labels.

```bash
python tools/ml/loso_eval.py --input path/to/exports --out report.json
```

Accepts:

- FlowRep JSON exports (`flowrep-export-v1`) — subject = file stem, features from rep peaks
- Flat JSON/JSONL rows: `{"subject","exercise","features":[...]}`

Optional: install `scikit-learn` for RandomForest; otherwise majority-class baseline.

**Does not** train or ship a production TFLite model (FR-A4 remains a separate data project).
