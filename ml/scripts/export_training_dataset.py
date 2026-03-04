from __future__ import annotations

import argparse
import json
import random
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any


UUID_RE = re.compile(
    r"feedback-(?P<job_id>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})-"
)


@dataclass
class RuleInfo:
    rule_id: str
    document_family: str | None
    class_code: str | None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Exporte un corpus d'entrainement JSONL a partir des feedbacks de nommage Orchiviste."
    )
    parser.add_argument(
        "--feedback-dir",
        default="OrchivisteAPI/configs/naming/feedback",
        help="Dossier des feedbacks de nommage persistés."
    )
    parser.add_argument(
        "--rules-dir",
        default="OrchivisteAPI/configs/naming/rules",
        help="Dossier des règles de nommage actives."
    )
    parser.add_argument(
        "--ocr-artifact-dir",
        default="",
        help="Dossier des artefacts OCR du worker (<job_id>.ocr.json)."
    )
    parser.add_argument(
        "--output-train",
        default="ml/datasets/labeled/classification_train.jsonl",
        help="Fichier JSONL de sortie pour l'entrainement."
    )
    parser.add_argument(
        "--output-eval",
        default="ml/datasets/labeled/classification_eval.jsonl",
        help="Fichier JSONL de sortie pour l'evaluation."
    )
    parser.add_argument(
        "--eval-ratio",
        type=float,
        default=0.2,
        help="Part des enregistrements envoyés dans le jeu d'evaluation."
    )
    parser.add_argument(
        "--min-text-chars",
        type=int,
        default=80,
        help="Longueur minimale du texte pour garder un enregistrement."
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Graine aleatoire pour le split train/eval."
    )
    parser.add_argument(
        "--fallback-to-filename-text",
        action="store_true",
        help="Utilise le nom corrigé comme texte minimal quand aucun artefact OCR n'est disponible."
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    feedback_dir = Path(args.feedback_dir)
    rules_dir = Path(args.rules_dir)
    ocr_artifact_dir = Path(args.ocr_artifact_dir) if args.ocr_artifact_dir else None
    output_train = Path(args.output_train)
    output_eval = Path(args.output_eval)

    rule_index = load_rules(rules_dir)
    records, skipped = export_records(
        feedback_dir=feedback_dir,
        rule_index=rule_index,
        ocr_artifact_dir=ocr_artifact_dir,
        min_text_chars=max(1, args.min_text_chars),
        fallback_to_filename_text=args.fallback_to_filename_text,
    )

    random.Random(args.seed).shuffle(records)
    eval_ratio = min(max(args.eval_ratio, 0.0), 0.5)
    eval_count = int(round(len(records) * eval_ratio))
    eval_records = records[:eval_count]
    train_records = records[eval_count:]

    write_jsonl(output_train, train_records)
    write_jsonl(output_eval, eval_records)

    print(f"Feedback lus          : {len(records) + skipped}")
    print(f"Enregistrements gardés: {len(records)}")
    print(f"Enregistrements ignorés: {skipped}")
    print(f"Train écrit dans      : {output_train}")
    print(f"Eval écrit dans       : {output_eval}")
    return 0


def load_rules(rules_dir: Path) -> dict[str, RuleInfo]:
    index: dict[str, RuleInfo] = {}
    if not rules_dir.exists():
        return index

    for path in sorted(rules_dir.glob("*.json")):
        raw = json.loads(path.read_text(encoding="utf-8"))
        metadata = raw.get("metadata") or {}
        index[raw["id"]] = RuleInfo(
            rule_id=raw["id"],
            document_family=string_or_none(raw.get("document_family")),
            class_code=string_or_none(metadata.get("suggested_class_code")),
        )
    return index


def export_records(
    feedback_dir: Path,
    rule_index: dict[str, RuleInfo],
    ocr_artifact_dir: Path | None,
    min_text_chars: int,
    fallback_to_filename_text: bool,
) -> tuple[list[dict[str, Any]], int]:
    records: list[dict[str, Any]] = []
    skipped = 0

    if not feedback_dir.exists():
        return records, skipped

    for path in sorted(feedback_dir.glob("*.json")):
        raw = json.loads(path.read_text(encoding="utf-8"))
        feedback = raw.get("feedback") or {}
        rule_id = string_or_none(raw.get("rule_id")) or ""
        job_id = extract_job_id(string_or_none(raw.get("feedback_id")) or path.stem)
        ocr_text, ocr_path = load_ocr_text(job_id, ocr_artifact_dir)
        corrected_filename = string_or_none(feedback.get("corrected_filename")) or ""
        source_fields = feedback.get("source_fields") or {}
        corrected_fields = feedback.get("corrected_fields") or {}

        text = (ocr_text or "").strip()
        if not text and fallback_to_filename_text:
            text = corrected_filename
        if len(text) < min_text_chars:
            skipped += 1
            continue

        rule = rule_index.get(rule_id)
        type_document = infer_type_document(rule, corrected_filename, source_fields, corrected_fields)
        class_code = (
            string_or_none(corrected_fields.get("class_code"))
            or string_or_none(source_fields.get("class_code"))
            or (rule.class_code if rule else None)
            or infer_class_code_from_type(type_document)
        )
        preset_id = infer_preset_id_from_type(type_document)
        subjects = infer_subjects(source_fields, corrected_fields)

        record = {
            "document_id": job_id or path.stem,
            "source_path": ocr_path or corrected_filename,
            "text_source": "ocr" if ocr_text else "hybrid",
            "text": text,
            "language": "fr",
            "type_document": type_document,
            "class_code": class_code or "GEN-000",
            "preset_id": preset_id,
            "subjects": subjects,
            "session_date": string_or_none(corrected_fields.get("date")) or string_or_none(source_fields.get("date")),
            "numero_document": string_or_none(corrected_fields.get("numero")) or string_or_none(source_fields.get("numero")),
            "validated_filename": corrected_filename,
            "human_validated": True,
            "review_status": "validated",
            "metadata": {
                "rule_id": rule_id,
                "source_filename": string_or_none(feedback.get("source_filename")),
                "corrected_filename": corrected_filename,
                "notes": string_or_none(feedback.get("notes")),
                "ocr_artifact_path": ocr_path,
            },
        }
        records.append(record)

    return records, skipped


def extract_job_id(raw: str) -> str:
    match = UUID_RE.search(raw)
    if match:
        return match.group("job_id")
    return ""


def load_ocr_text(job_id: str, ocr_artifact_dir: Path | None) -> tuple[str | None, str | None]:
    if not job_id or ocr_artifact_dir is None:
        return None, None
    artifact_path = ocr_artifact_dir / f"{job_id}.ocr.json"
    if not artifact_path.exists():
        return None, None
    raw = json.loads(artifact_path.read_text(encoding="utf-8"))
    pages = raw.get("pages") or []
    texts = []
    for page in pages:
        text = string_or_none(page.get("text"))
        if text:
            texts.append(text)
    if not texts:
        return None, str(artifact_path)
    return "\n\n".join(texts), str(artifact_path)


def infer_type_document(
    rule: RuleInfo | None,
    corrected_filename: str,
    source_fields: dict[str, Any],
    corrected_fields: dict[str, Any],
) -> str:
    for candidate in (
        corrected_fields.get("type_document"),
        source_fields.get("type_document"),
        corrected_fields.get("doc_type_hint"),
        source_fields.get("doc_type_hint"),
        rule.document_family if rule else None,
    ):
        resolved = normalize_type_document(string_or_none(candidate))
        if resolved != "Autre":
            return resolved

    lowered = corrected_filename.casefold()
    if lowered.startswith("résolution no") or lowered.startswith("resolution no"):
        return "Resolution"
    if lowered.startswith("avis de motion"):
        return "AvisMotion"
    if lowered.startswith("dépôt") or lowered.startswith("depot"):
        return "Depot"
    if "entente" in lowered:
        return "Entente"
    return "Autre"


def infer_class_code_from_type(type_document: str) -> str | None:
    mapping = {
        "Resolution": "ADM-RES",
        "ProcesVerbal": "ADM-PV",
        "Facture": "FIN-001",
        "Permis": "URB-PER",
        "Entente": "ADM-ENT",
        "AvisMotion": "ADM-AM",
        "Depot": "ADM-DEP",
    }
    return mapping.get(type_document)


def infer_preset_id_from_type(type_document: str) -> str:
    mapping = {
        "Resolution": "preset_resolution",
        "ProcesVerbal": "preset_pv",
        "Facture": "preset_facture",
    }
    return mapping.get(type_document, "preset_default")


def infer_subjects(source_fields: dict[str, Any], corrected_fields: dict[str, Any]) -> list[str]:
    raw_subjects = string_or_none(corrected_fields.get("sujets")) or string_or_none(source_fields.get("sujets"))
    if raw_subjects:
        return [part.strip() for part in raw_subjects.split(",") if part.strip()]
    object_value = string_or_none(corrected_fields.get("objet")) or string_or_none(source_fields.get("objet"))
    if object_value:
        return [object_value]
    return []


def normalize_type_document(raw: str | None) -> str:
    value = (raw or "").casefold()
    if "résolution" in value or "resolution" in value:
        return "Resolution"
    if "procès-verbal" in value or "proces-verbal" in value or value == "pv":
        return "ProcesVerbal"
    if "facture" in value or "invoice" in value:
        return "Facture"
    if "permis" in value:
        return "Permis"
    if "entente" in value or "contrat" in value or "convention" in value or "bail" in value:
        return "Entente"
    if "avis de motion" in value:
        return "AvisMotion"
    if "dépôt" in value or "depot" in value:
        return "Depot"
    return "Autre"


def string_or_none(value: Any) -> str | None:
    if value is None:
        return None
    rendered = str(value).strip()
    return rendered or None


def write_jsonl(path: Path, records: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
