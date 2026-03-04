from __future__ import annotations

import argparse
import json
import math
import random
from pathlib import Path
from typing import Any

import torch
import torch.nn as nn
import torch.optim as optim


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Entraine un classifieur documentaire Orchiviste simple en PyTorch."
    )
    parser.add_argument("--train", required=True, help="Corpus train JSONL.")
    parser.add_argument("--eval", required=False, help="Corpus eval JSONL.")
    parser.add_argument("--label-field", default="type_document")
    parser.add_argument("--text-field", default="text")
    parser.add_argument("--vector-size", type=int, default=256)
    parser.add_argument("--hidden-size", type=int, default=128)
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--learning-rate", type=float, default=3e-3)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--device", default="auto", choices=["auto", "cpu", "mps"])
    parser.add_argument("--output-model", default="ml/models-src/document_classifier.pt")
    parser.add_argument("--output-labels", default="ml/models-src/document_classifier.labels.json")
    parser.add_argument("--output-metrics", default="ml/models-src/document_classifier.metrics.json")
    return parser.parse_args()


class HashedTextClassifier(nn.Module):
    def __init__(self, input_dim: int, hidden_dim: int, num_classes: int) -> None:
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(input_dim, hidden_dim),
            nn.ReLU(),
            nn.Dropout(0.1),
            nn.Linear(hidden_dim, num_classes),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)


def main() -> int:
    args = parse_args()
    seed_everything(args.seed)

    train_records = load_jsonl(Path(args.train))
    eval_records = load_jsonl(Path(args.eval)) if args.eval else []
    if not train_records:
        raise SystemExit("Aucun enregistrement d'entrainement.")

    labels = sorted({str(record[args.label_field]) for record in train_records if record.get(args.label_field)})
    if not labels:
        raise SystemExit("Aucun label exploitable trouvé dans le corpus train.")

    label_to_index = {label: index for index, label in enumerate(labels)}
    train_x, train_y = vectorize_records(train_records, args.text_field, args.label_field, label_to_index, args.vector_size)
    eval_x, eval_y = vectorize_records(eval_records, args.text_field, args.label_field, label_to_index, args.vector_size)

    device = resolve_device(args.device)
    model = HashedTextClassifier(args.vector_size, args.hidden_size, len(labels)).to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=args.learning_rate)

    for epoch in range(args.epochs):
        model.train()
        epoch_loss = 0.0
        batch_count = 0
        for batch_x, batch_y in iterate_batches(train_x, train_y, args.batch_size):
            optimizer.zero_grad()
            logits = model(batch_x.to(device))
            loss = criterion(logits, batch_y.to(device))
            loss.backward()
            optimizer.step()
            epoch_loss += float(loss.item())
            batch_count += 1

        if (epoch + 1) % 5 == 0 or epoch == 0 or epoch + 1 == args.epochs:
            metrics = evaluate(model, eval_x, eval_y, device) if eval_records else {}
            print(
                f"[epoch {epoch + 1:02d}] loss={epoch_loss / max(1, batch_count):.4f} "
                + " ".join(f"{key}={value:.4f}" for key, value in metrics.items())
            )

    metrics = evaluate(model, eval_x, eval_y, device) if eval_records else {}
    save_outputs(
        model=model,
        labels=labels,
        metrics={
            "device": str(device),
            "vector_size": args.vector_size,
            "hidden_size": args.hidden_size,
            "epochs": args.epochs,
            "train_count": len(train_records),
            "eval_count": len(eval_records),
            **metrics,
        },
        output_model=Path(args.output_model),
        output_labels=Path(args.output_labels),
        output_metrics=Path(args.output_metrics),
        vector_size=args.vector_size,
    )
    return 0


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    records: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            records.append(json.loads(line))
    return records


def vectorize_records(
    records: list[dict[str, Any]],
    text_field: str,
    label_field: str,
    label_to_index: dict[str, int],
    vector_size: int,
) -> tuple[torch.Tensor, torch.Tensor]:
    feature_rows: list[list[float]] = []
    label_rows: list[int] = []
    for record in records:
        text = str(record.get(text_field) or "").strip()
        label = str(record.get(label_field) or "").strip()
        if not text or label not in label_to_index:
            continue
        feature_rows.append(hashed_text_feature_vector(text, vector_size))
        label_rows.append(label_to_index[label])

    if not feature_rows:
        return (
            torch.zeros((0, vector_size), dtype=torch.float32),
            torch.zeros((0,), dtype=torch.long),
        )

    return (
        torch.tensor(feature_rows, dtype=torch.float32),
        torch.tensor(label_rows, dtype=torch.long),
    )


def iterate_batches(features: torch.Tensor, labels: torch.Tensor, batch_size: int):
    indices = list(range(len(features)))
    random.shuffle(indices)
    for start in range(0, len(indices), batch_size):
        batch_indices = indices[start:start + batch_size]
        yield features[batch_indices], labels[batch_indices]


def evaluate(model: nn.Module, features: torch.Tensor, labels: torch.Tensor, device: torch.device) -> dict[str, float]:
    if len(features) == 0:
        return {}
    model.eval()
    with torch.no_grad():
        logits = model(features.to(device))
        predictions = torch.argmax(logits, dim=1).cpu()
        accuracy = float((predictions == labels).float().mean().item())
    return {"eval_accuracy": accuracy}


def save_outputs(
    model: nn.Module,
    labels: list[str],
    metrics: dict[str, Any],
    output_model: Path,
    output_labels: Path,
    output_metrics: Path,
    vector_size: int,
) -> None:
    output_model.parent.mkdir(parents=True, exist_ok=True)
    output_labels.parent.mkdir(parents=True, exist_ok=True)
    output_metrics.parent.mkdir(parents=True, exist_ok=True)

    model = model.cpu().eval()
    example_input = torch.randn(1, vector_size)
    traced = torch.jit.trace(model, example_input)
    traced.save(str(output_model))

    output_labels.write_text(json.dumps(labels, ensure_ascii=False, indent=2), encoding="utf-8")
    output_metrics.write_text(json.dumps(metrics, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"Modèle TorchScript : {output_model}")
    print(f"Labels             : {output_labels}")
    print(f"Métriques          : {output_metrics}")


def resolve_device(raw: str) -> torch.device:
    if raw == "cpu":
        return torch.device("cpu")
    if raw == "mps":
        if torch.backends.mps.is_available():
            return torch.device("mps")
        raise SystemExit("MPS demandé mais indisponible sur cette machine.")
    if torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def seed_everything(seed: int) -> None:
    random.seed(seed)
    torch.manual_seed(seed)
    if torch.backends.mps.is_available():
        torch.mps.manual_seed(seed)


def hashed_text_feature_vector(text: str, dimension: int) -> list[float]:
    safe_dimension = max(8, dimension)
    tokens = feature_tokens(text)
    if not tokens:
        return [0.0] * safe_dimension

    vector = [0.0] * safe_dimension
    for token in tokens:
        bucket = fnv1a_hash(token) % safe_dimension
        vector[bucket] += 1.0

    total = sum(vector)
    if total <= 0:
        return vector
    return [value / total for value in vector]


def feature_tokens(text: str) -> list[str]:
    normalized = text.casefold()
    token = []
    tokens = []
    stop_words = {
        "avec", "dans", "pour", "sans", "par", "sur", "aux", "des", "les",
        "une", "que", "qui", "est", "sont", "dont", "ceci", "cela", "ville",
        "amos", "conseil", "municipal", "document", "fichier", "type", "objet", "resume",
    }
    for character in normalized:
        if character.isalnum():
            token.append(character)
            continue
        if token:
            candidate = "".join(token)
            if len(candidate) >= 3 and candidate not in stop_words:
                tokens.append(candidate)
            token = []
    if token:
        candidate = "".join(token)
        if len(candidate) >= 3 and candidate not in stop_words:
            tokens.append(candidate)
    return tokens


def fnv1a_hash(text: str) -> int:
    hash_value = 1469598103934665603
    fnv_prime = 1099511628211
    for byte in text.encode("utf-8"):
        hash_value ^= byte
        hash_value = (hash_value * fnv_prime) & 0xFFFFFFFFFFFFFFFF
    return hash_value


if __name__ == "__main__":
    raise SystemExit(main())
