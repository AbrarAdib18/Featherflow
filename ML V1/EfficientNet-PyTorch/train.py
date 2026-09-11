"""
train.py  —  EfficientNet fine-tuning script for Featherflow bird classifier
Place this file at: G:\Featherflow\EfficientNet-PyTorch\train.py

Dataset must follow ImageFolder structure:
    G:\Featherflow\Dataset\
        species_a\  img1.jpg, img2.jpg ...
        species_b\  img1.jpg ...
        ...

Run:
    python train.py
"""

import os
import copy
import time
import json
import torch
import torch.nn as nn
import torch.optim as optim
from torch.optim import lr_scheduler
from torch.utils.data import DataLoader, random_split
from torchvision import datasets, transforms
from efficientnet_pytorch import EfficientNet   # pip install efficientnet_pytorch
                                                # OR use your local package below:
# ── If you want to use your LOCAL model.py / utils.py instead of pip package ──
# import sys, pathlib
# sys.path.insert(0, str(pathlib.Path(__file__).parent))
# from model import EfficientNet

# ════════════════════════════════════════════════════════════
#  CONFIG  —  change these to suit your setup
# ════════════════════════════════════════════════════════════
CONFIG = {
    # Paths
    "data_dir":        r"G:\Featherflow\Dataset",
    "output_dir":      r"G:\Featherflow\EfficientNet-PyTorch\checkpoints",

    # Model
    "model_name": "efficientnet-b0",   # b0 (fast) … b7 (accurate)
    "pretrained":      True,                # start from ImageNet weights

    # Training
    "num_epochs":      30,
    "batch_size":      16,                  # reduce to 16 if you hit OOM
    "num_workers":     0,                   # set 0 on Windows if DataLoader errors
    "val_split":       0.15,                # 15 % of data used for validation
    "seed":            42,

    # Optimiser
    "lr":              1e-4,
    "weight_decay":    1e-5,
    "lr_step_size":    7,                   # StepLR: decay every N epochs
    "lr_gamma":        0.1,

    # Early stopping
    "patience":        7,                   # stop if val-acc doesn't improve for N epochs
}
# ════════════════════════════════════════════════════════════

def get_transforms(image_size):
    """Return train / val transform pipelines."""
    mean = [0.485, 0.456, 0.406]
    std  = [0.229, 0.224, 0.225]

    train_tf = transforms.Compose([
        transforms.RandomResizedCrop(image_size),
        transforms.RandomHorizontalFlip(),
        transforms.RandomVerticalFlip(p=0.1),
        transforms.ColorJitter(brightness=0.3, contrast=0.3, saturation=0.2, hue=0.05),
        transforms.RandomRotation(15),
        transforms.ToTensor(),
        transforms.Normalize(mean, std),
    ])
    val_tf = transforms.Compose([
        transforms.Resize(int(image_size * 1.14)),
        transforms.CenterCrop(image_size),
        transforms.ToTensor(),
        transforms.Normalize(mean, std),
    ])
    return train_tf, val_tf


def build_model(model_name, num_classes, pretrained):
    if pretrained:
        model = EfficientNet.from_pretrained(model_name, num_classes=num_classes)
    else:
        model = EfficientNet.from_name(model_name, num_classes=num_classes)
    return model


def train_model(model, dataloaders, dataset_sizes, criterion, optimizer,
                scheduler, num_epochs, patience, output_dir, device):

    best_model_wts = copy.deepcopy(model.state_dict())
    best_acc = 0.0
    epochs_no_improve = 0
    history = {"train_loss": [], "train_acc": [], "val_loss": [], "val_acc": []}

    for epoch in range(num_epochs):
        print(f"\nEpoch {epoch+1}/{num_epochs}  {'─'*40}")

        for phase in ["train", "val"]:
            model.train() if phase == "train" else model.eval()

            running_loss = 0.0
            running_corrects = 0
            t0 = time.time()

            for inputs, labels in dataloaders[phase]:
                inputs = inputs.to(device)
                labels = labels.to(device)

                optimizer.zero_grad()

                with torch.set_grad_enabled(phase == "train"):
                    outputs = model(inputs)
                    _, preds = torch.max(outputs, 1)
                    loss = criterion(outputs, labels)

                    if phase == "train":
                        loss.backward()
                        optimizer.step()

                running_loss     += loss.item() * inputs.size(0)
                running_corrects += torch.sum(preds == labels.data)

            if phase == "train":
                scheduler.step()

            epoch_loss = running_loss / dataset_sizes[phase]
            epoch_acc  = running_corrects.double() / dataset_sizes[phase]
            elapsed    = time.time() - t0

            print(f"  {phase:5s}  loss: {epoch_loss:.4f}  acc: {epoch_acc:.4f}  ({elapsed:.1f}s)")
            history[f"{phase}_loss"].append(epoch_loss)
            history[f"{phase}_acc"].append(epoch_acc.item())

            # ── Save best model ──────────────────────────────────────
            if phase == "val":
                if epoch_acc > best_acc:
                    best_acc = epoch_acc
                    best_model_wts = copy.deepcopy(model.state_dict())
                    best_path = os.path.join(output_dir, "best_model.pth")
                    torch.save(model.state_dict(), best_path)
                    print(f"  ✔  New best val acc {best_acc:.4f}  →  saved to {best_path}")
                    epochs_no_improve = 0
                else:
                    epochs_no_improve += 1

        # ── Checkpoint every epoch ───────────────────────────────────
        ckpt_path = os.path.join(output_dir, f"epoch_{epoch+1:03d}.pth")
        torch.save({
            "epoch":      epoch + 1,
            "state_dict": model.state_dict(),
            "optimizer":  optimizer.state_dict(),
            "val_acc":    epoch_acc.item(),
        }, ckpt_path)

        # ── Early stopping ───────────────────────────────────────────
        if epochs_no_improve >= patience:
            print(f"\n⏹  Early stopping triggered after {epoch+1} epochs (no improvement for {patience}).")
            break

    print(f"\n✅  Training complete.  Best val acc: {best_acc:.4f}")
    model.load_state_dict(best_model_wts)
    return model, history


def main():
    cfg = CONFIG
    torch.manual_seed(cfg["seed"])
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Using device: {device}")
    if device.type == "cuda":
        print(f"GPU: {torch.cuda.get_device_name(0)}")

    os.makedirs(cfg["output_dir"], exist_ok=True)

    # ── Image size for the chosen model ─────────────────────────────
    image_size = EfficientNet.get_image_size(cfg["model_name"])
    print(f"Model: {cfg['model_name']}  |  input size: {image_size}×{image_size}")

    # ── Dataset ─────────────────────────────────────────────────────
    train_tf, val_tf = get_transforms(image_size)
    full_dataset = datasets.ImageFolder(cfg["data_dir"], transform=train_tf)
    class_names  = full_dataset.classes
    num_classes  = len(class_names)
    print(f"Classes found: {num_classes}  →  {class_names[:10]}{'…' if num_classes > 10 else ''}")

    # Save class index map (needed by the web app)
    class_map = {str(v): k for k, v in full_dataset.class_to_idx.items()}
    map_path  = os.path.join(cfg["output_dir"], "class_map.json")
    with open(map_path, "w") as f:
        json.dump(class_map, f, indent=2)
    print(f"Class map saved → {map_path}")

    # Train / val split
    n_val   = int(len(full_dataset) * cfg["val_split"])
    n_train = len(full_dataset) - n_val
    train_ds, val_ds = random_split(
        full_dataset, [n_train, n_val],
        generator=torch.Generator().manual_seed(cfg["seed"])
    )
    # Apply correct transform to val subset
    val_ds.dataset = copy.deepcopy(full_dataset)
    val_ds.dataset.transform = val_tf

    dataloaders = {
        "train": DataLoader(train_ds, batch_size=cfg["batch_size"],
                            shuffle=True,  num_workers=cfg["num_workers"], pin_memory=True),
        "val":   DataLoader(val_ds,   batch_size=cfg["batch_size"],
                            shuffle=False, num_workers=cfg["num_workers"], pin_memory=True),
    }
    dataset_sizes = {"train": n_train, "val": n_val}
    print(f"Train samples: {n_train}  |  Val samples: {n_val}")

    # ── Model ────────────────────────────────────────────────────────
    model = build_model(cfg["model_name"], num_classes, cfg["pretrained"])
    model = model.to(device)

    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=cfg["lr"], weight_decay=cfg["weight_decay"])
    step_lr   = lr_scheduler.StepLR(optimizer, step_size=cfg["lr_step_size"], gamma=cfg["lr_gamma"])

    # ── Train ────────────────────────────────────────────────────────
    model, history = train_model(
        model, dataloaders, dataset_sizes, criterion, optimizer,
        step_lr, cfg["num_epochs"], cfg["patience"], cfg["output_dir"], device
    )

    # ── Save final model with metadata ───────────────────────────────
    final_path = os.path.join(cfg["output_dir"], "final_model.pth")
    torch.save({
        "model_name":  cfg["model_name"],
        "num_classes": num_classes,
        "class_names": class_names,
        "state_dict":  model.state_dict(),
        "history":     history,
    }, final_path)
    print(f"\n💾  Final model saved → {final_path}")

    # Save training history as JSON
    hist_path = os.path.join(cfg["output_dir"], "history.json")
    with open(hist_path, "w") as f:
        json.dump(history, f, indent=2)
    print(f"📊  Training history saved → {hist_path}")


if __name__ == "__main__":
    main()
