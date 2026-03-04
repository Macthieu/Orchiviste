from __future__ import annotations

import argparse
import json
import random
import re
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Construit un corpus bootstrap faiblement supervisé à partir des "
            "fichiers déjà routés Orchiviste."
        )
    )
    parser.add_argument(
        "--routed-dir",
        default="runtime/routed",
        help="Racine des documents déjà routés."
    )
    parser.add_argument(
        "--output-train",
        default="ml/datasets/labeled/classification_bootstrap_train.jsonl",
        help="JSONL de sortie pour l'entraînement."
    )
    parser.add_argument(
        "--output-eval",
        default="ml/datasets/labeled/classification_bootstrap_eval.jsonl",
        help="JSONL de sortie pour l'évaluation."
    )
    parser.add_argument(
        "--eval-ratio",
        type=float,
        default=0.2,
        help="Part du corpus réservée à l'évaluation."
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Graine pour le shuffle."
    )
    parser.add_argument(
        "--include-review-staging",
        action="store_true",
        help="Inclut aussi les fichiers présents sous A_reviser."
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    routed_dir = Path(args.routed_dir)
    output_train = Path(args.output_train)
    output_eval = Path(args.output_eval)

    records = build_records(
        routed_dir=routed_dir,
        include_review_staging=args.include_review_staging,
    )

    random.Random(args.seed).shuffle(records)
    eval_ratio = min(max(args.eval_ratio, 0.0), 0.5)
    eval_count = int(round(len(records) * eval_ratio))
    eval_records = records[:eval_count]
    train_records = records[eval_count:]

    write_jsonl(output_train, train_records)
    write_jsonl(output_eval, eval_records)

    print(f"Documents routés lus : {len(records)}")
    print(f"Train écrit dans     : {output_train}")
    print(f"Eval écrit dans      : {output_eval}")
    return 0


def build_records(
    routed_dir: Path,
    include_review_staging: bool,
) -> list[dict[str, Any]]:
    if not routed_dir.exists():
        return []

    records: list[dict[str, Any]] = []
    for path in sorted(routed_dir.rglob("*.pdf")):
        relative = path.relative_to(routed_dir)
        if not include_review_staging and "A_reviser" in relative.parts:
            continue

        record = build_record_from_path(path, relative)
        if record is not None:
            records.append(record)
    return records


def build_record_from_path(path: Path, relative: Path) -> dict[str, Any] | None:
    parts = list(relative.parts)
    filename = path.name
    stem = path.stem

    class_code = infer_class_code(parts, filename)
    type_document = infer_type_document(parts, filename)
    if class_code is None or type_document is None:
        return None

    subjects = infer_subjects(parts)
    numero_document = infer_numero(stem)
    session_date = infer_date(stem)
    preset_id = infer_preset_id(type_document)
    weak_text = build_weak_text(parts, stem, class_code, type_document)

    return {
        "document_id": stable_document_id(relative),
        "source_path": str(path),
        "text_source": "hybrid",
        "text": weak_text,
        "language": "fr",
        "type_document": type_document,
        "class_code": class_code,
        "preset_id": preset_id,
        "subjects": subjects,
        "session_date": session_date,
        "numero_document": numero_document,
        "validated_filename": filename,
        "human_validated": False,
        "review_status": "validated",
        "metadata": {
            "bootstrap_source": "runtime_routed_path",
            "relative_path": str(relative),
            "weak_supervision": True,
        },
    }


def infer_class_code(parts: list[str], filename: str) -> str | None:
    for part in parts:
        if re.fullmatch(r"[A-Z]{2,6}-[A-Z0-9]{2,6}", part):
            return part
    for part in parts:
        if re.fullmatch(r"\d{3,6}", part) and not re.fullmatch(r"20\d{2}", part):
            return part
    if filename.startswith("FIN-001"):
        return "FIN-001"
    if filename.startswith("ADM-RES"):
        return "ADM-RES"
    if filename.startswith("ADM-PV"):
        return "ADM-PV"
    return None


def infer_type_document(parts: list[str], filename: str) -> str | None:
    lowered_parts = [part.casefold() for part in parts]
    lowered_filename = filename.casefold()
    if "resolutions" in lowered_parts or "-res-" in lowered_filename:
        return "Resolution"
    if "proces-verbaux" in lowered_parts or "-pv-" in lowered_filename:
        return "ProcesVerbal"
    if "factures" in lowered_parts or "-fact-" in lowered_filename:
        return "Facture"
    if "entente" in lowered_filename or "contrat" in lowered_filename:
        return "Entente"
    if "permis" in lowered_parts or "permis" in lowered_filename:
        return "Permis"
    return "Autre" if lowered_parts else None


def infer_subjects(parts: list[str]) -> list[str]:
    ignored = {
        "archives",
        "a_reviser",
        "resolutions",
        "proces-verbaux",
        "factures",
        "autres",
    }
    subjects: list[str] = []
    for part in parts:
        normalized = part.strip()
        if not normalized or normalized.casefold() in ignored:
            continue
        if normalized.lower().endswith(".pdf"):
            continue
        if re.fullmatch(r"20\d{2}", normalized):
            continue
        if re.fullmatch(r"[A-Z]{2,6}-[A-Z0-9]{2,6}", normalized):
            continue
        if re.fullmatch(r"\d{3,6}", normalized):
            continue
        if normalized.lower() == normalized:
            normalized = normalized.replace("-", " ").title()
        subjects.append(normalized)
    return subjects[:4]


def infer_numero(stem: str) -> str | None:
    match = re.search(r"\b(?:20\d{2}-\d{1,4}|PV-\d{4}-\d{1,4}|R ?\d{1,4}(?:-\d{1,3})?)\b", stem)
    return match.group(0).replace(" ", "") if match else None


def infer_date(stem: str) -> str | None:
    match = re.search(r"\b(20\d{2})[-_]?(\d{2})[-_]?(\d{2})\b", stem)
    if not match:
        return None
    return f"{match.group(1)}-{match.group(2)}-{match.group(3)}"


def infer_preset_id(type_document: str) -> str:
    mapping = {
        "Resolution": "preset_resolution",
        "ProcesVerbal": "preset_pv",
        "Facture": "preset_facture",
        "Entente": "preset_default",
        "Permis": "preset_default",
        "Autre": "preset_default",
    }
    return mapping.get(type_document, "preset_default")


def build_weak_text(parts: list[str], stem: str, class_code: str, type_document: str) -> str:
    fragments = [class_code, type_document]
    for part in parts:
        if part.lower().endswith(".pdf"):
            continue
        fragments.append(part.replace("-", " "))
    fragments.append(stem.replace("-", " ").replace("_", " "))
    return "\n".join(fragment for fragment in fragments if fragment.strip())


def stable_document_id(relative: Path) -> str:
    sanitized = str(relative).replace("/", "__")
    return sanitized.removesuffix(".pdf")


def write_jsonl(path: Path, records: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
