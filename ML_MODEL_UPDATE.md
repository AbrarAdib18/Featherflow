# Disease-detection model replacement — 2026-09-10

The farmer-panel disease-detection model was replaced with the retrained model
supplied in `ML V1/`. The API contract (`POST /api/ml/predict-disease/`, response
shape) is unchanged and the frontend was **not** touched.

## Old model

| | |
|---|---|
| Path | `ML/checkpoints/final_model.pth` |
| Architecture | EfficientNet-b3 |
| Input size | 300 × 300 |
| Classes | 15 |
| Class list | `Anemia Virus`, `Avian Influenza`, `Botulism`, `Bumblefoot`, `COCCIDIOSIS`, `Fowl Cholera`, `Fowl pox`, `HEALTHY`, `Healthy Chicken`, `Mareks`, `NEW CASTLE`, `Salmonella`, `Vent Gleet`, `coryza`, `crd` |
| Checkpoint size | ~41 MB |
| Best val accuracy (own split, `history.json`) | 0.99968 |

Backed up to (kept for rollback — do **not** delete):

* `ML/old/final_model_b3_15class_20260910.pth`
* `ML/old/best_model_b3_15class_20260910.pth`
* `ML/old/class_map_b3_15class_20260910.json`
* `ML/old/history_b3_15class_20260910.json`

## New model (now live)

| | |
|---|---|
| Source | `ML V1/EfficientNet-PyTorch/checkpoints/final_model.pth` |
| Installed to | `ML/checkpoints/final_model.pth` (path unchanged — no env/config change needed) |
| Architecture | EfficientNet-b0 |
| Input size | 224 × 224 |
| Classes | 14 |
| Class list | `Anemia Virus`, `Avian Influenza`, `Botulism Disease`, `Bumblefoot`, `COCCIDIOSIS`, `Fowl Cholera`, `Fowl pox`, `HEALTHY`, `Mareks disease`, `NEW CASTLE`, `Salmonella`, `Vent Gleet`, `coryza`, `crd` |
| Checkpoint size | ~16 MB |
| Best val accuracy (own split, `history.json`) | 0.99758 |

`ML/checkpoints/{final_model.pth, best_model.pth, class_map.json, history.json}`
were all replaced with the `ML V1` versions.

### Format / compatibility check

| Aspect | Old | New | Action |
|---|---|---|---|
| File format | `.pth` (torch dict) | `.pth` (torch dict) | ✅ identical wrapper: `{model_name, num_classes, class_names, state_dict, history}` |
| Architecture | `efficientnet-b3` | `efficientnet-b0` | ✅ `inference.py` reads `model_name` from the checkpoint and builds the matching net; input size comes from `EfficientNet.get_image_size(model_name)` |
| Preprocessing | `Resize(size*1.14)` → `CenterCrop(size)` → `ToTensor` → ImageNet `Normalize` | same recipe | ✅ no change — matches `ML V1/.../app.py` |
| Output | softmax, top-k | softmax, top-k | ✅ unchanged |
| Class labels | 15 | 14 (3 renamed, duplicate "Healthy Chicken" dropped) | ⚠️ see below |

### Class-label changes

The new model renames three raw labels and drops the duplicate healthy folder:

| Old raw label | New raw label |
|---|---|
| `Botulism` | `Botulism Disease` |
| `Mareks` | `Mareks disease` |
| `Healthy Chicken` | *(removed — only `HEALTHY` remains)* |

## Code changes

**`backend/ml/content.py`** — added aliases so the renamed labels resolve to the
existing advice content (severity, symptoms, recommendations unchanged). Old
label keys are kept too, so scans stored under the old names still resolve:

```python
CLASS_META['Botulism Disease'] = CLASS_META['Botulism']
CLASS_META['Mareks disease']  = CLASS_META['Mareks']
```

**No other backend changes.** `inference.py` is architecture-agnostic (reads
`model_name`, `num_classes`, `class_names`, and input size from the checkpoint),
so the b3→b0 swap and the 15→14 class-count change needed no edits there.
Docstrings/comments in `inference.py`, `content.py` and `ML/README-ML.md` were
refreshed for accuracy.

**No frontend changes.** `lib/features/farmer/data/disease_detection_service.dart`
consumes `disease` / `confidence` / `all_predictions` / advice lists generically —
no hard-coded class names anywhere in `lib/`.

## Verification

* Model loads cleanly via `inference.ensure_loaded()`:
  `model_name='efficientnet-b0', num_classes=14, loaded=True, last_error=None` —
  no shape-mismatch / missing-layer / weight warnings.
* All 14 raw class labels map to advice metadata (none fall through to
  "Uncertain").
* `backend/scripts/test_disease_detection.py` — **25 passed, 0 failed**
  (health check, predict 201, validation/error paths, auth, scan history,
  disease reference card).

### Sample predictions (via `POST /api/ml/predict-disease/`, real uploaded photos)

| Image | Predicted disease | Confidence | Severity | Top-3 |
|---|---|---|---|---|
| `20260907104404_cd9031da.jpg` | Fowl Pox | 0.854 | medium | Fowl Pox 0.854 · Coccidiosis 0.080 · Avian Influenza 0.040 |
| `20260907111236_4b644747.jpg` | Newcastle Disease | 0.991 | critical | NEW CASTLE 0.991 · … |
| `20260907111907_45bc709d.jpg` | Salmonellosis | 0.973 | high | Salmonella 0.973 · … |
| `20260907104405_4f876fc5.jpg` | Coccidiosis | 0.928 | high | COCCIDIOSIS 0.928 · HEALTHY 0.049 · Avian Influenza 0.014 |

Predictions are confident and well-separated; low-confidence images
(< 0.45 top-1) correctly fall back to the "Uncertain → see a vet" path.

## Accuracy note

The new b0 model's self-reported best validation accuracy (0.99758) is
marginally below the old b3's (0.99968). The old figure is near-ceiling and
likely reflects train/val leakage in the previous merged dataset (it had two
near-identical "healthy" folders and heavily duplicated images). The `ML V1`
model was provided as the improved/cleaned retrain (14 well-defined classes, no
duplicate healthy class) and is now the served model. If a labelled hold-out set
becomes available, run a before/after comparison using the backups in `ML/old/`.

## Rollback

```bash
cp "ML/old/final_model_b3_15class_20260910.pth" ML/checkpoints/final_model.pth
cp "ML/old/class_map_b3_15class_20260910.json"  ML/checkpoints/class_map.json
cp "ML/old/history_b3_15class_20260910.json"    ML/checkpoints/history.json
# revert backend/ml/content.py alias lines (harmless to leave, but not needed)
# restart the Django worker
```
