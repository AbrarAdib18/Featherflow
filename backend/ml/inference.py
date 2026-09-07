"""Disease-detection model loader and inference.

The EfficientNet-b3 checkpoint lives at ``<repo>/ML/checkpoints/final_model.pth``
and is a dict of ``{model_name, num_classes, class_names, state_dict, history}``
(see ``ML/train.py``). torch + efficientnet_pytorch are heavy, so the model is
**lazy-loaded on the first prediction request** and then cached for the life of
the worker process — Django start-up and the autoreloader are never slowed.
"""
import io
import os
import threading

from django.conf import settings

# Preprocessing must match ML/app.py / ML/train.py (val transform):
#   Resize(int(image_size * 1.14)) -> CenterCrop(image_size) -> ToTensor -> Normalize(ImageNet)
_IMAGENET_MEAN = [0.485, 0.456, 0.406]
_IMAGENET_STD = [0.229, 0.224, 0.225]

_MODEL_PATH = os.environ.get(
    'DISEASE_MODEL_PATH',
    os.path.join(settings.BASE_DIR.parent, 'ML', 'checkpoints', 'final_model.pth'),
)

_lock = threading.Lock()
_state = {'model': None, 'transform': None, 'class_names': None, 'device': None,
          'model_name': None, 'error': None}


class ModelUnavailable(RuntimeError):
    """Raised when the checkpoint or its dependencies cannot be loaded."""


def _load():
    import torch
    from efficientnet_pytorch import EfficientNet
    from torchvision import transforms

    if not os.path.exists(_MODEL_PATH):
        raise ModelUnavailable(
            f'Model checkpoint not found at {_MODEL_PATH}. '
            'Place final_model.pth under ML/checkpoints/ (see ML/README-ML.md).')

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    checkpoint = torch.load(_MODEL_PATH, map_location=device, weights_only=False)

    model_name = checkpoint['model_name']
    num_classes = checkpoint['num_classes']
    class_names = list(checkpoint['class_names'])

    model = EfficientNet.from_name(model_name, num_classes=num_classes)
    model.load_state_dict(checkpoint['state_dict'])
    model.to(device)
    model.eval()

    image_size = EfficientNet.get_image_size(model_name)
    transform = transforms.Compose([
        transforms.Resize(int(image_size * 1.14)),
        transforms.CenterCrop(image_size),
        transforms.ToTensor(),
        transforms.Normalize(_IMAGENET_MEAN, _IMAGENET_STD),
    ])

    _state.update(model=model, transform=transform, class_names=class_names,
                  device=device, model_name=model_name, error=None)


def ensure_loaded():
    """Load the model once. Subsequent calls are cheap. Raises ModelUnavailable."""
    if _state['model'] is not None:
        return
    with _lock:
        if _state['model'] is not None:
            return
        try:
            _load()
        except ModelUnavailable:
            raise
        except Exception as exc:  # noqa: BLE001 — surface any load failure cleanly
            _state['error'] = str(exc)
            raise ModelUnavailable(f'Could not load the disease model: {exc}') from exc


def class_names():
    ensure_loaded()
    return list(_state['class_names'])


def model_info():
    """Lightweight status for a health check — does NOT force a load."""
    return {
        'loaded': _state['model'] is not None,
        'model_name': _state['model_name'],
        'checkpoint_path': _MODEL_PATH,
        'checkpoint_present': os.path.exists(_MODEL_PATH),
        'num_classes': len(_state['class_names']) if _state['class_names'] else None,
        'last_error': _state['error'],
    }


def predict(image_bytes, top_k=5):
    """Run inference on raw image bytes.

    Returns ``(ranked, image_ok)`` where ``ranked`` is a list of
    ``{"raw_label": str, "confidence": float}`` sorted high→low (length top_k),
    and ``image_ok`` is False when the bytes are not a readable image.
    """
    import torch
    import torch.nn.functional as F
    from PIL import Image, UnidentifiedImageError

    ensure_loaded()

    try:
        image = Image.open(io.BytesIO(image_bytes)).convert('RGB')
    except (UnidentifiedImageError, OSError):
        return [], False

    tensor = _state['transform'](image).unsqueeze(0).to(_state['device'])
    with torch.no_grad():
        probs = F.softmax(_state['model'](tensor), dim=1)[0]

    names = _state['class_names']
    k = min(top_k, len(names))
    top_probs, top_idx = torch.topk(probs, k)
    ranked = [
        {'raw_label': names[i.item()], 'confidence': round(float(p.item()), 6)}
        for p, i in zip(top_probs, top_idx)
    ]
    return ranked, True
