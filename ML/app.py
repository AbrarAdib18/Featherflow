"""
app.py  —  Featherflow · Bird Species Classifier  (Flask web app)
Place this file at: G:\Featherflow\EfficientNet-PyTorch\app.py

Requirements:
    pip install flask torch torchvision pillow efficientnet_pytorch

Run:
    python app.py
Then open http://localhost:5000 in your browser.

The app loads the saved model from:
    G:\Featherflow\EfficientNet-PyTorch\checkpoints\final_model.pth
"""

import io
import json
import os
import torch
import torch.nn.functional as F
from flask import Flask, request, jsonify, render_template_string
from PIL import Image
from torchvision import transforms
from efficientnet_pytorch import EfficientNet  # pip install efficientnet_pytorch

# ── Paths ────────────────────────────────────────────────────────────────────
BASE_DIR   = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(BASE_DIR, "checkpoints", "final_model.pth")

# ── Load model once at startup ────────────────────────────────────────────────
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

print(f"Loading model from: {MODEL_PATH}")
checkpoint  = torch.load(MODEL_PATH, map_location=device)
model_name  = checkpoint["model_name"]
num_classes = checkpoint["num_classes"]
class_names = checkpoint["class_names"]

model = EfficientNet.from_name(model_name, num_classes=num_classes)
model.load_state_dict(checkpoint["state_dict"])
model.to(device)
model.eval()

image_size = EfficientNet.get_image_size(model_name)
print(f"✅  Model ready  |  {model_name}  |  {num_classes} classes  |  input {image_size}px")

# ── Transform for inference ───────────────────────────────────────────────────
infer_tf = transforms.Compose([
    transforms.Resize(int(image_size * 1.14)),
    transforms.CenterCrop(image_size),
    transforms.ToTensor(),
    transforms.Normalize([0.485, 0.456, 0.406],
                         [0.229, 0.224, 0.225]),
])

# ── Flask app ─────────────────────────────────────────────────────────────────
app = Flask(__name__)

# ── HTML (embedded — no separate template file needed) ───────────────────────
HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Featherflow</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;1,300&family=DM+Mono:wght@300;400&display=swap" rel="stylesheet">
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  :root {
    --bg:       #0d0e0c;
    --surface:  #131410;
    --border:   #2a2c25;
    --text:     #e8e5dc;
    --muted:    #6b6b60;
    --accent:   #c8b97a;
    --accent2:  #7a9c6e;
    --danger:   #c87a7a;
    --radius:   4px;
    --mono:     'DM Mono', monospace;
    --serif:    'Cormorant Garamond', Georgia, serif;
  }

  html, body {
    height: 100%;
    background: var(--bg);
    color: var(--text);
    font-family: var(--serif);
    font-weight: 300;
    font-size: 16px;
    line-height: 1.6;
    -webkit-font-smoothing: antialiased;
  }

  /* ── Layout ── */
  .shell {
    min-height: 100vh;
    display: grid;
    grid-template-rows: auto 1fr auto;
    max-width: 760px;
    margin: 0 auto;
    padding: 0 24px;
  }

  /* ── Header ── */
  header {
    padding: 56px 0 40px;
    border-bottom: 1px solid var(--border);
  }
  .wordmark {
    font-size: clamp(2rem, 6vw, 3.2rem);
    font-weight: 300;
    letter-spacing: 0.18em;
    text-transform: uppercase;
    color: var(--accent);
  }
  .tagline {
    font-style: italic;
    color: var(--muted);
    font-size: 0.95rem;
    letter-spacing: 0.04em;
    margin-top: 6px;
  }
  .meta-pill {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    margin-top: 14px;
    font-family: var(--mono);
    font-size: 0.72rem;
    color: var(--muted);
    border: 1px solid var(--border);
    border-radius: 999px;
    padding: 4px 12px;
  }
  .meta-pill span { color: var(--accent2); }

  /* ── Main ── */
  main { padding: 48px 0; }

  /* ── Drop zone ── */
  .drop-zone {
    position: relative;
    border: 1px dashed var(--border);
    border-radius: var(--radius);
    background: var(--surface);
    cursor: pointer;
    transition: border-color .2s, background .2s;
    overflow: hidden;
  }
  .drop-zone:hover, .drop-zone.drag-over {
    border-color: var(--accent);
    background: #181910;
  }
  .drop-zone input[type="file"] {
    position: absolute; inset: 0;
    opacity: 0; cursor: pointer; width: 100%; height: 100%;
  }
  .drop-inner {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    padding: 64px 32px;
    pointer-events: none;
  }
  .drop-icon {
    width: 48px; height: 48px;
    opacity: .35;
    transition: opacity .2s;
  }
  .drop-zone:hover .drop-icon { opacity: .7; }
  .drop-label {
    font-size: 1.05rem;
    letter-spacing: 0.06em;
    color: var(--muted);
  }
  .drop-hint {
    font-family: var(--mono);
    font-size: 0.7rem;
    color: #45453e;
    letter-spacing: 0.08em;
  }

  /* ── Preview ── */
  .preview-wrap {
    display: none;
    position: relative;
  }
  .preview-wrap img {
    width: 100%;
    max-height: 400px;
    object-fit: contain;
    border-radius: var(--radius);
    background: #0a0b09;
    display: block;
  }
  .preview-clear {
    position: absolute;
    top: 12px; right: 12px;
    background: rgba(0,0,0,.7);
    border: 1px solid var(--border);
    border-radius: 999px;
    color: var(--muted);
    font-family: var(--mono);
    font-size: 0.7rem;
    padding: 4px 10px;
    cursor: pointer;
    transition: color .15s, border-color .15s;
    letter-spacing: 0.06em;
  }
  .preview-clear:hover { color: var(--text); border-color: var(--accent); }

  /* ── Button ── */
  .btn {
    display: block;
    width: 100%;
    margin-top: 16px;
    padding: 14px;
    background: transparent;
    border: 1px solid var(--accent);
    border-radius: var(--radius);
    color: var(--accent);
    font-family: var(--mono);
    font-size: 0.78rem;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    cursor: pointer;
    transition: background .15s, color .15s;
  }
  .btn:hover { background: var(--accent); color: var(--bg); }
  .btn:disabled { opacity: .35; cursor: not-allowed; }
  .btn:hover:disabled { background: transparent; color: var(--accent); }

  /* ── Results ── */
  .result-block {
    margin-top: 40px;
    padding-top: 40px;
    border-top: 1px solid var(--border);
    display: none;
    animation: fadeUp .4s ease both;
  }
  @keyframes fadeUp {
    from { opacity:0; transform: translateY(12px); }
    to   { opacity:1; transform: translateY(0); }
  }
  .result-species {
    font-size: clamp(1.8rem, 5vw, 2.6rem);
    font-weight: 300;
    color: var(--accent);
    letter-spacing: 0.05em;
    line-height: 1.2;
    margin-bottom: 6px;
  }
  .result-conf {
    font-family: var(--mono);
    font-size: 0.75rem;
    color: var(--accent2);
    letter-spacing: 0.1em;
    margin-bottom: 32px;
  }

  /* ── Bar chart ── */
  .bars { display: flex; flex-direction: column; gap: 10px; }
  .bar-row { display: grid; grid-template-columns: 1fr 3fr auto; align-items: center; gap: 12px; }
  .bar-name {
    font-family: var(--mono);
    font-size: 0.7rem;
    color: var(--muted);
    letter-spacing: 0.04em;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .bar-track {
    height: 3px;
    background: var(--border);
    border-radius: 999px;
    overflow: hidden;
  }
  .bar-fill {
    height: 100%;
    border-radius: 999px;
    background: var(--accent);
    transform-origin: left;
    animation: growBar .5s cubic-bezier(.4,0,.2,1) both;
  }
  .bar-row:first-child .bar-fill { background: var(--accent); }
  .bar-row:not(:first-child) .bar-fill { background: var(--border); filter: brightness(2); }
  @keyframes growBar {
    from { transform: scaleX(0); }
    to   { transform: scaleX(1); }
  }
  .bar-pct {
    font-family: var(--mono);
    font-size: 0.68rem;
    color: var(--muted);
    min-width: 36px;
    text-align: right;
  }

  /* ── Error ── */
  .error-msg {
    margin-top: 20px;
    padding: 14px 18px;
    border: 1px solid var(--danger);
    border-radius: var(--radius);
    font-family: var(--mono);
    font-size: 0.75rem;
    color: var(--danger);
    letter-spacing: 0.05em;
    display: none;
  }

  /* ── Spinner ── */
  .spinner {
    display: none;
    width: 20px; height: 20px;
    border: 2px solid var(--border);
    border-top-color: var(--accent);
    border-radius: 50%;
    animation: spin .7s linear infinite;
    margin: 0 auto;
  }
  @keyframes spin { to { transform: rotate(360deg); } }

  /* ── Footer ── */
  footer {
    padding: 24px 0;
    border-top: 1px solid var(--border);
    font-family: var(--mono);
    font-size: 0.68rem;
    color: #3a3a33;
    letter-spacing: 0.08em;
    display: flex;
    justify-content: space-between;
  }
</style>
</head>
<body>
<div class="shell">

  <header>
    <div class="wordmark">Featherflow</div>
    <div class="tagline">Bird species classification · EfficientNet</div>
    <div class="meta-pill">model <span>{{ model_name }}</span> · <span>{{ num_classes }}</span> species</div>
  </header>

  <main>
    <!-- Drop zone -->
    <div class="drop-zone" id="dropZone">
      <input type="file" id="fileInput" accept="image/*">
      <div class="drop-inner">
        <svg class="drop-icon" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M24 4C13 4 4 13 4 24s9 20 20 20 20-9 20-20S35 4 24 4z" stroke="currentColor" stroke-width="1.5"/>
          <path d="M24 16v16M16 24l8-8 8 8" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
        <div class="drop-label">Drop an image here</div>
        <div class="drop-hint">JPG · PNG · WEBP</div>
      </div>
    </div>

    <!-- Preview -->
    <div class="preview-wrap" id="previewWrap">
      <img id="previewImg" src="" alt="preview">
      <button class="preview-clear" onclick="clearImage()">✕ clear</button>
    </div>

    <!-- Classify button -->
    <button class="btn" id="classifyBtn" onclick="classify()" disabled>Identify Species</button>

    <!-- Spinner -->
    <div class="spinner" id="spinner"></div>

    <!-- Error -->
    <div class="error-msg" id="errorMsg"></div>

    <!-- Results -->
    <div class="result-block" id="resultBlock">
      <div class="result-species" id="resultSpecies"></div>
      <div class="result-conf" id="resultConf"></div>
      <div class="bars" id="bars"></div>
    </div>
  </main>

  <footer>
    <span>Featherflow · {{ year }}</span>
    <span>{{ device_label }}</span>
  </footer>

</div>

<script>
const dropZone   = document.getElementById('dropZone');
const fileInput  = document.getElementById('fileInput');
const previewImg = document.getElementById('previewImg');
const previewWrap= document.getElementById('previewWrap');
const classifyBtn= document.getElementById('classifyBtn');
const spinner    = document.getElementById('spinner');
const errorMsg   = document.getElementById('errorMsg');
const resultBlock= document.getElementById('resultBlock');

let selectedFile = null;

// File input change
fileInput.addEventListener('change', e => {
  if (e.target.files[0]) loadFile(e.target.files[0]);
});

// Drag & drop
dropZone.addEventListener('dragover', e => { e.preventDefault(); dropZone.classList.add('drag-over'); });
dropZone.addEventListener('dragleave', () => dropZone.classList.remove('drag-over'));
dropZone.addEventListener('drop', e => {
  e.preventDefault();
  dropZone.classList.remove('drag-over');
  if (e.dataTransfer.files[0]) loadFile(e.dataTransfer.files[0]);
});

function loadFile(file) {
  selectedFile = file;
  const reader = new FileReader();
  reader.onload = ev => {
    previewImg.src = ev.target.result;
    dropZone.style.display  = 'none';
    previewWrap.style.display = 'block';
    classifyBtn.disabled = false;
    resultBlock.style.display = 'none';
    errorMsg.style.display = 'none';
  };
  reader.readAsDataURL(file);
}

function clearImage() {
  selectedFile = null;
  fileInput.value = '';
  dropZone.style.display = 'block';
  previewWrap.style.display = 'none';
  classifyBtn.disabled = true;
  resultBlock.style.display = 'none';
  errorMsg.style.display = 'none';
}

async function classify() {
  if (!selectedFile) return;

  classifyBtn.disabled = true;
  spinner.style.display = 'block';
  resultBlock.style.display = 'none';
  errorMsg.style.display = 'none';

  const fd = new FormData();
  fd.append('image', selectedFile);

  try {
    const res  = await fetch('/predict', { method: 'POST', body: fd });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Unknown error');
    showResults(data);
  } catch (err) {
    errorMsg.textContent = 'Error: ' + err.message;
    errorMsg.style.display = 'block';
  } finally {
    spinner.style.display = 'none';
    classifyBtn.disabled = false;
  }
}

function showResults(data) {
  document.getElementById('resultSpecies').textContent = data.top_class.replace(/_/g, ' ');
  document.getElementById('resultConf').textContent =
    `${(data.top_confidence * 100).toFixed(1)} % confidence`;

  const bars = document.getElementById('bars');
  bars.innerHTML = '';
  data.top5.forEach((item, i) => {
    const pct = (item.confidence * 100).toFixed(1);
    const width = (item.confidence * 100).toFixed(2);
    bars.innerHTML += `
      <div class="bar-row">
        <div class="bar-name" title="${item.class}">${item.class.replace(/_/g,' ')}</div>
        <div class="bar-track">
          <div class="bar-fill" style="width:${width}%;animation-delay:${i*0.07}s"></div>
        </div>
        <div class="bar-pct">${pct}%</div>
      </div>`;
  });

  resultBlock.style.display = 'block';
  void resultBlock.offsetWidth; // trigger reflow for animation
}
</script>
</body>
</html>"""


@app.route("/")
def index():
    import datetime
    return render_template_string(
        HTML,
        model_name=model_name,
        num_classes=num_classes,
        year=datetime.date.today().year,
        device_label="GPU · CUDA" if device.type == "cuda" else "CPU",
    )


@app.route("/predict", methods=["POST"])
def predict():
    if "image" not in request.files:
        return jsonify({"error": "No image uploaded"}), 400

    file = request.files["image"]
    if file.filename == "":
        return jsonify({"error": "Empty filename"}), 400

    try:
        img = Image.open(io.BytesIO(file.read())).convert("RGB")
    except Exception as e:
        return jsonify({"error": f"Cannot open image: {e}"}), 400

    tensor = infer_tf(img).unsqueeze(0).to(device)

    with torch.no_grad():
        logits = model(tensor)
        probs  = F.softmax(logits, dim=1)[0]

    top5_probs, top5_idx = torch.topk(probs, min(5, len(class_names)))
    top5 = [
        {"class": class_names[idx.item()], "confidence": round(prob.item(), 6)}
        for idx, prob in zip(top5_idx, top5_probs)
    ]

    return jsonify({
        "top_class":      top5[0]["class"],
        "top_confidence": top5[0]["confidence"],
        "top5":           top5,
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
