from __future__ import annotations

import argparse
import json
import random
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SUPPORTED_EXTENSIONS = {".pdf", ".docx", ".xlsx", ".xls", ".pptx", ".png", ".jpg", ".jpeg", ".tif", ".tiff"}


@dataclass(frozen=True)
class FamilySpec:
    key: str
    type_document: str
    class_code: str
    preset_id: str


FAMILY_SPECS: dict[str, FamilySpec] = {
    "resolution_conseil": FamilySpec(
        key="resolution_conseil",
        type_document="Resolution",
        class_code="ADM-RES",
        preset_id="preset_resolution",
    ),
    "avis_motion": FamilySpec(
        key="avis_motion",
        type_document="AvisMotion",
        class_code="ADM-AM",
        preset_id="preset_default",
    ),
    "depot": FamilySpec(
        key="depot",
        type_document="Depot",
        class_code="ADM-DEP",
        preset_id="preset_default",
    ),
    "entente_uniformisee": FamilySpec(
        key="entente_uniformisee",
        type_document="Entente",
        class_code="ADM-ENT",
        preset_id="preset_default",
    ),
    "permis_construction": FamilySpec(
        key="permis_construction",
        type_document="Permis",
        class_code="URB-PER",
        preset_id="preset_permis",
    ),
}


ENTENTE_POSITIVE_KEYWORDS = [
    "entente",
    "avenant",
    "bail",
    "contrat",
    "convention",
    "protocole",
]

ENTENTE_EXCLUDED_KEYWORDS = [
    "lettre",
    "promesse",
    "declaration",
    "déclaration",
    "annexe",
]

PERMIS_NUMBER_PATTERNS = [
    re.compile(r"(?i)permis(?:\s+de\s+construction)?\s*(?:no|n°|numero)?\s*([a-z]{0,4}-?(?:19|20)\d{2}-\d{1,6}[a-z]?)"),
    re.compile(r"\b((?:19|20)\d{2}-\d{3,6}[a-z]?)\b", flags=re.IGNORECASE),
]
MATRICULE_PATTERN = re.compile(r"\b(\d{4}-\d{2}-\d{4})\b")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Prépare des corpus d'entraînement séparés par famille documentaire "
            "(résolution, avis de motion, dépôt, entente) à partir de dossiers externes."
        )
    )
    parser.add_argument(
        "--resolution-folder",
        required=True,
        help="Dossier source des résolutions (incluant avis motion/dépôts)."
    )
    parser.add_argument(
        "--entente-folder",
        required=True,
        help="Dossier source des ententes déjà renommées."
    )
    parser.add_argument(
        "--permis-folder",
        default="",
        help="Dossier source des permis (optionnel, ex: PDF Permis)."
    )
    parser.add_argument(
        "--output-dir",
        default="ml/datasets/labeled",
        help="Dossier de sortie des JSONL."
    )
    parser.add_argument(
        "--eval-ratio",
        type=float,
        default=0.2,
        help="Part des enregistrements envoyés dans eval."
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Graine de randomisation pour le split."
    )
    parser.add_argument(
        "--max-per-family",
        type=int,
        default=0,
        help="Limite max par famille (0 = illimité)."
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    resolution_folder = Path(args.resolution_folder)
    entente_folder = Path(args.entente_folder)
    permis_folder = Path(args.permis_folder) if args.permis_folder else None
    output_dir = Path(args.output_dir)

    if not resolution_folder.exists():
        raise SystemExit(f"Dossier introuvable: {resolution_folder}")
    if not entente_folder.exists():
        raise SystemExit(f"Dossier introuvable: {entente_folder}")
    if permis_folder is not None and not permis_folder.exists():
        raise SystemExit(f"Dossier introuvable: {permis_folder}")

    enabled_families = [
        "resolution_conseil",
        "avis_motion",
        "depot",
        "entente_uniformisee",
    ]
    if permis_folder is not None:
        enabled_families.append("permis_construction")

    family_records: dict[str, list[dict[str, Any]]] = {key: [] for key in enabled_families}
    excluded: dict[str, list[dict[str, str]]] = {
        "resolution_folder": [],
        "entente_folder": [],
        "permis_folder": [],
    }

    scan_resolution_folder(
        folder=resolution_folder,
        family_records=family_records,
        excluded=excluded["resolution_folder"],
    )
    scan_entente_folder(
        folder=entente_folder,
        family_records=family_records,
        excluded=excluded["entente_folder"],
    )
    if permis_folder is not None:
        scan_permis_folder(
            folder=permis_folder,
            family_records=family_records,
            excluded=excluded["permis_folder"],
        )

    if args.max_per_family > 0:
        for family_key, records in family_records.items():
            family_records[family_key] = records[: args.max_per_family]

    rng = random.Random(args.seed)
    eval_ratio = min(max(args.eval_ratio, 0.0), 0.5)
    output_dir.mkdir(parents=True, exist_ok=True)

    merged_train: list[dict[str, Any]] = []
    merged_eval: list[dict[str, Any]] = []
    split_summary: dict[str, dict[str, int]] = {}

    for family_key in enabled_families:
        records = family_records[family_key]
        rng.shuffle(records)
        eval_count = int(round(len(records) * eval_ratio))
        eval_records = records[:eval_count]
        train_records = records[eval_count:]

        family_train_path = output_dir / f"classification_{family_key}_train.jsonl"
        family_eval_path = output_dir / f"classification_{family_key}_eval.jsonl"
        write_jsonl(family_train_path, train_records)
        write_jsonl(family_eval_path, eval_records)

        merged_train.extend(train_records)
        merged_eval.extend(eval_records)
        split_summary[family_key] = {
            "train": len(train_records),
            "eval": len(eval_records),
            "total": len(records),
        }

    write_jsonl(output_dir / "classification_external_train.jsonl", merged_train)
    write_jsonl(output_dir / "classification_external_eval.jsonl", merged_eval)

    report = {
        "resolution_folder": str(resolution_folder),
        "entente_folder": str(entente_folder),
        "permis_folder": str(permis_folder) if permis_folder is not None else None,
        "summary": split_summary,
        "excluded": {
            "resolution_folder_count": len(excluded["resolution_folder"]),
            "entente_folder_count": len(excluded["entente_folder"]),
            "permis_folder_count": len(excluded["permis_folder"]),
            "resolution_folder_examples": excluded["resolution_folder"][:20],
            "entente_folder_examples": excluded["entente_folder"][:20],
            "permis_folder_examples": excluded["permis_folder"][:20],
        },
    }
    report_path = output_dir / "classification_external_report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print("Corpus externes préparés.")
    for family_key, stats in split_summary.items():
        print(f"- {family_key}: train={stats['train']} eval={stats['eval']} total={stats['total']}")
    print(f"- merged train: {len(merged_train)}")
    print(f"- merged eval : {len(merged_eval)}")
    print(f"- rapport     : {report_path}")
    return 0


def scan_resolution_folder(
    folder: Path,
    family_records: dict[str, list[dict[str, Any]]],
    excluded: list[dict[str, str]],
) -> None:
    for path in sorted(folder.iterdir()):
        if not path.is_file():
            continue
        if path.suffix.lower() not in SUPPORTED_EXTENSIONS:
            excluded.append({"file": path.name, "reason": "unsupported_extension"})
            continue

        family_key = detect_resolution_family(path.stem)
        if family_key is None:
            excluded.append({"file": path.name, "reason": "cannot_detect_family"})
            continue
        spec = FAMILY_SPECS[family_key]
        family_records[family_key].append(
            make_record(
                path=path,
                spec=spec,
                origin="resolution_folder",
                human_validated=False,
            )
        )


def scan_entente_folder(
    folder: Path,
    family_records: dict[str, list[dict[str, Any]]],
    excluded: list[dict[str, str]],
) -> None:
    spec = FAMILY_SPECS["entente_uniformisee"]
    for path in sorted(folder.iterdir()):
        if not path.is_file():
            continue
        if path.suffix.lower() not in SUPPORTED_EXTENSIONS:
            excluded.append({"file": path.name, "reason": "unsupported_extension"})
            continue

        normalized = normalize_text(path.stem)
        if any(keyword in normalized for keyword in ENTENTE_EXCLUDED_KEYWORDS):
            excluded.append({"file": path.name, "reason": "excluded_keyword"})
            continue
        if not any(keyword in normalized for keyword in ENTENTE_POSITIVE_KEYWORDS):
            excluded.append({"file": path.name, "reason": "missing_entente_keyword"})
            continue

        family_records["entente_uniformisee"].append(
            make_record(
                path=path,
                spec=spec,
                origin="entente_folder",
                human_validated=True,
            )
        )


def scan_permis_folder(
    folder: Path,
    family_records: dict[str, list[dict[str, Any]]],
    excluded: list[dict[str, str]],
) -> None:
    spec = FAMILY_SPECS["permis_construction"]
    for path in sorted(folder.iterdir()):
        if not path.is_file():
            continue
        if path.suffix.lower() not in SUPPORTED_EXTENSIONS:
            excluded.append({"file": path.name, "reason": "unsupported_extension"})
            continue

        parsed = parse_permis_filename(path.stem)
        if not parsed["looks_like_permis"]:
            excluded.append({"file": path.name, "reason": "cannot_detect_permis_pattern"})
            continue

        text_hints: list[str] = []
        if parsed["matricule"]:
            text_hints.append(f"matricule {parsed['matricule']}")
        if parsed["permit_number"]:
            text_hints.append(f"permis de construction no {parsed['permit_number']}")
        if parsed["permit_year"]:
            text_hints.append(f"annee permis {parsed['permit_year']}")

        family_records["permis_construction"].append(
            make_record(
                path=path,
                spec=spec,
                origin="permis_folder",
                human_validated=True,
                additional_metadata={
                    "matricule": parsed["matricule"],
                    "numero_permis": parsed["permit_number"],
                    "annee_permis": parsed["permit_year"],
                },
                text_hints=text_hints,
            )
        )


def detect_resolution_family(stem: str) -> str | None:
    normalized = normalize_text(stem)
    if "avis motion" in normalized:
        return "avis_motion"
    if normalized.startswith("depot") or normalized.startswith("depot "):
        return "depot"
    if normalized.startswith("depot certificat"):
        return "depot"
    return "resolution_conseil"


def make_record(
    path: Path,
    spec: FamilySpec,
    origin: str,
    human_validated: bool,
    additional_metadata: dict[str, Any] | None = None,
    text_hints: list[str] | None = None,
) -> dict[str, Any]:
    stem = path.stem
    numero = infer_numero(stem)
    session_date = infer_date(stem)
    subjects = infer_subjects(stem)
    normalized_stem = re.sub(r"[_\-]+", " ", stem).strip()

    weak_text_lines = [spec.type_document, spec.class_code, normalized_stem]
    if text_hints:
        weak_text_lines.extend([hint for hint in text_hints if hint.strip()])

    metadata: dict[str, Any] = {
        "source_origin": origin,
        "family_key": spec.key,
        "weak_supervision": not human_validated,
    }
    if additional_metadata:
        metadata.update({key: value for key, value in additional_metadata.items() if value not in (None, "")})

    return {
        "document_id": f"external::{spec.key}::{stable_id(path.name)}",
        "source_path": str(path),
        "text_source": "hybrid",
        "text": "\n".join(weak_text_lines),
        "language": "fr",
        "type_document": spec.type_document,
        "class_code": spec.class_code,
        "preset_id": spec.preset_id,
        "subjects": subjects,
        "session_date": session_date,
        "numero_document": numero,
        "validated_filename": path.name,
        "human_validated": human_validated,
        "review_status": "validated" if human_validated else "needs_review",
        "metadata": metadata,
    }


def infer_subjects(stem: str) -> list[str]:
    normalized = normalize_text(stem)
    tokens = [token for token in re.split(r"[^a-z0-9]+", normalized) if token]
    stop = {
        "entente", "resolution", "avis", "motion", "depot", "depot", "no", "va",
        "pdf", "docx", "xlsx", "xls", "pour", "avec", "sans", "les", "des", "une",
    }
    kept = [token for token in tokens if token not in stop and len(token) >= 3]
    return [token.capitalize() for token in kept[:4]]


def infer_numero(stem: str) -> str | None:
    match = re.search(r"\b(?:(?:19|20)\d{2}-\d{1,6}|VA1-\d{1,4}|VA-\d{1,4})\b", stem, flags=re.IGNORECASE)
    return match.group(0).upper() if match else None


def infer_date(stem: str) -> str | None:
    match = re.search(r"\b(20\d{2})[-_](\d{2})[-_](\d{2})\b", stem)
    if not match:
        return None
    return f"{match.group(1)}-{match.group(2)}-{match.group(3)}"


def normalize_text(raw: str) -> str:
    lowered = unicodedata.normalize("NFKD", raw).encode("ascii", "ignore").decode("ascii").lower()
    return re.sub(r"\s+", " ", lowered).strip()


def parse_permis_filename(stem: str) -> dict[str, str | bool | None]:
    normalized_stem = normalize_text(stem)
    matricule_match = MATRICULE_PATTERN.search(stem)
    matricule = matricule_match.group(1) if matricule_match else None

    permit_number = None
    for pattern in PERMIS_NUMBER_PATTERNS:
        match = pattern.search(stem)
        if match:
            permit_number = match.group(1).upper()
            break

    permit_year = None
    if permit_number:
        year_match = re.search(r"\b((?:19|20)\d{2})-", permit_number)
        if year_match:
            permit_year = year_match.group(1)

    looks_like_permis = (
        "permis" in normalized_stem
        or "demande de permis" in normalized_stem
        or permit_number is not None
        or matricule is not None
    )

    return {
        "looks_like_permis": looks_like_permis,
        "matricule": matricule,
        "permit_number": permit_number,
        "permit_year": permit_year,
    }


def stable_id(name: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9]+", "-", name).strip("-").lower()
    return cleaned or "document"


def write_jsonl(path: Path, records: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
