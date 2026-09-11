# Disease-detection model — operations & retraining

The farmer-panel "Disease Detection" screen sends a photo to
`POST /api/ml/predict-disease/`, which runs this model in-process in the Django
backend and returns the predicted condition plus first-aid advice.

---

## 1. What the model is

| | |
|---|---|
| Architecture | **EfficientNet-b0** (via `efficientnet_pytorch`) — retrained model swapped in 2026-09-10; was b3 (see `ML/old/` + `ML_MODEL_UPDATE.md`) |
| Framework | PyTorch (CPU is fine; CUDA used automatically if present) |
| Input | RGB image, **224 x 224** (b0's native size — read from the checkpoint, not hard-coded) |
| Preprocess | `Resize(round(size*1.14))` -> `CenterCrop(size)` -> `ToTensor` -> `Normalize(ImageNet mean/std)` |
| Output | softmax over **14 classes**, top-5 returned |
| Checkpoint | `ML/checkpoints/final_model.pth` (~16 MB) |

The checkpoint is a dict written by `ML/train.py`:

```python
{
  "model_name":  "efficientnet-b0",
  "num_classes": 14,
  "class_names": [...14 strings...],
  "state_dict":  <model weights>,
  "history":     {train/val loss & acc per epoch},
}
```

`backend/ml/inference.py` reads `model_name` / `num_classes` / `class_names`
from the file, so swapping in a differently-sized EfficientNet checkpoint needs
no backend code change.

The raw class names (from the training `ImageFolder`) are messy on purpose.
`backend/ml/content.py` maps each raw name to a clean label + severity + advice
(older raw names like `Botulism`, `Mareks`, `Healthy Chicken` are kept as
aliases so historical scans still resolve):

| raw label | shown as | severity |
|---|---|---|
| `HEALTHY` (alias: `Healthy Chicken`) | Healthy | – |
| `Anemia Virus` | Chicken Infectious Anaemia | high |
| `Avian Influenza` | Avian Influenza (Bird Flu) | critical, notifiable |
| `Botulism Disease` (alias: `Botulism`) | Botulism | high |
| `Bumblefoot` | Bumblefoot (Foot-pad Dermatitis) | medium |
| `COCCIDIOSIS` | Coccidiosis | high |
| `Fowl Cholera` | Fowl Cholera (Pasteurellosis) | high |
| `Fowl pox` | Fowl Pox | medium |
| `Mareks disease` (alias: `Mareks`) | Marek's Disease | high |
| `NEW CASTLE` | Newcastle Disease | critical, notifiable |
| `Salmonella` | Salmonellosis | high, notifiable |
| `Vent Gleet` | Vent Gleet (Cloacitis) | medium |
| `coryza` | Infectious Coryza | medium |
| `crd` | Chronic Respiratory Disease (CRD / Mycoplasma) | medium |

---

## 2. How the backend uses it

* `backend/ml/inference.py` — loads the checkpoint **lazily on the first
  request** (never at Django start-up / autoreload) and caches it for the life
  of the worker process. Thread-safe.
* `backend/ml/views.py` — validates the upload, runs `inference.predict()`,
  applies the **confidence threshold**, links a `diseases` reference row, saves a
  `disease_scans` row, writes an `activity_logs` audit entry, and returns the
  advice payload.
* `backend/ml/content.py` — the per-class advice (single source of truth).
* `manage.py seed_disease_reference` — upserts the `diseases` table from
  `content.py`. Run it after editing advice.

### Endpoints

| method + path | purpose |
|---|---|
| `POST /api/ml/predict-disease/` | run the model (`image` multipart field, optional `flock_id`) |
| `GET  /api/ml/scans/?limit=N` | the farmer's recent completed scans |
| `GET  /api/ml/scans/<uuid>/` | one scan with full advice |
| `GET  /api/ml/diseases/<uuid>/` | reference card for a disease |
| `GET  /api/ml/health/` | model status (does not load the model) |

### Config (env vars)

| var | default | meaning |
|---|---|---|
| `DISEASE_MODEL_PATH` | `<repo>/ML/checkpoints/final_model.pth` | checkpoint location |
| `DISEASE_CONFIDENCE_THRESHOLD` | `0.45` | below this top-1 probability the result is returned as **"Uncertain"** and the farmer is pushed to a vet |
| `THROTTLE_DISEASE_PREDICT` | `30/hour` | per-farmer rate limit |

### Install the runtime deps

```bash
cd backend
venv/Scripts/pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
venv/Scripts/pip install "efficientnet-pytorch==0.7.1" numpy Pillow
```
(also listed in `backend/requirements.txt`)

---

## 3. Known limitations

* **No "not a chicken" class.** The model will confidently classify any image
  (a landscape, a person) as one of the 15 conditions — usually "Healthy". The
  confidence threshold and the always-on disclaimer mitigate this, but a real
  "reject non-poultry" gate (a separate binary classifier, or an OOD score) is
  the recommended follow-up.
* Two "healthy" training folders were merged, so the effective class count that
  matters clinically is 14.
* Accuracy on genuine field photos was **not** validated in this integration —
  do that against a held-out set of real, vet-labelled poultry images before
  relying on it (see §5).

---

## 4. Retrain / update the model

`ML/train.py` already does transfer-learning fine-tuning. It needs a CUDA GPU.

```
ML/
  train.py            # edit CONFIG at the top
  model.py, utils.py  # vendored efficientnet_pytorch (used by train.py only)
  checkpoints/        # outputs (gitignored — large)
```

1. **Prepare the dataset** as an `ImageFolder`:
   ```
   Dataset/
     Newcastle Disease/ img1.jpg ...
     Coccidiosis/       ...
     Healthy/           ...
   ```
   Use clean folder names — they become `class_names` and should match the
   `label` values in `content.py` (or update `content.py` to match).

2. Point `CONFIG["data_dir"]` / `CONFIG["output_dir"]` at your paths, tune
   `model_name`, `num_epochs`, `batch_size`, `lr`, then:
   ```bash
   python ML/train.py
   ```
   It writes `checkpoints/final_model.pth` (+ `best_model.pth`, per-epoch
   checkpoints, `history.json`, `class_map.json`).

3. **Deploy the new model:** copy the new `final_model.pth` to
   `ML/checkpoints/` (or set `DISEASE_MODEL_PATH`) and restart the Django
   workers. `inference.py` reads `model_name` / `class_names` from the
   checkpoint, so a different EfficientNet size works with no code change as
   long as `efficientnet_pytorch` supports it.

4. **If the class list changed:** update `CLASS_META` in
   `backend/ml/content.py` (add/rename entries keyed by the new raw label),
   then `python manage.py seed_disease_reference`. Any raw label with no
   `CLASS_META` entry falls back to the generic "Uncertain" advice.

### Adding one new disease class

1. Retrain with the new folder (step 1-3 above) — the class count must match.
2. Add a `CLASS_META['<raw folder name>'] = { label, severity, ... }` block in
   `content.py`.
3. `python manage.py seed_disease_reference`.
4. No frontend change needed — the screen renders whatever the API returns.

---

## 5. Testing

* Automated: `backend/venv/Scripts/python.exe backend/scripts/test_disease_detection.py`
  (25 checks — health, predict, validation, auth, throttle-free, history,
  reference card).
* Accuracy: run the model over a labelled hold-out set:
  ```python
  from ml import inference
  ranked, ok = inference.predict(open('photo.jpg','rb').read())
  print(ranked[0])   # {'raw_label': ..., 'confidence': ...}
  ```
  Build a confusion matrix, then tune `DISEASE_CONFIDENCE_THRESHOLD` so that
  low-confidence *wrong* predictions fall into the "Uncertain" bucket without
  hiding too many correct ones.
