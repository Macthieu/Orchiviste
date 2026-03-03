from __future__ import annotations

import argparse
from pathlib import Path
import sys

import coremltools as ct


def convert_torchscript_to_coreml(
    source_path: Path,
    output_path: Path,
    input_name: str = "input",
    input_shape: tuple[int, ...] = (1, 16),
) -> None:
    """
    Convert a TorchScript model (.pt / .torchscript.pt) to Core ML (.mlpackage).

    This script expects a TorchScript model already saved on disk.
    Example input shape is intentionally simple and should be adapted later
    to the real Orchiviste model.
    """
    try:
        import torch
    except ImportError as exc:
        raise RuntimeError(
            "PyTorch is not installed in the active environment. "
            "Install it before converting a TorchScript model."
        ) from exc

    if not source_path.exists():
        raise FileNotFoundError(f"Source model not found: {source_path}")

    output_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"Loading TorchScript model: {source_path}")
    model = torch.jit.load(str(source_path))
    model.eval()

    print("Converting model to Core ML...")
    mlmodel = ct.convert(
        model,
        inputs=[ct.TensorType(name=input_name, shape=input_shape)],
        convert_to="mlprogram",
    )

    print(f"Saving Core ML model to: {output_path}")
    mlmodel.save(str(output_path))
    print("Done.")


def parse_shape(shape_text: str) -> tuple[int, ...]:
    """
    Parse a shape string like '1,16' or '1,3,224,224' into a tuple of ints.
    """
    try:
        parts = [int(x.strip()) for x in shape_text.split(",") if x.strip()]
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            "Shape must be a comma-separated list of integers, e.g. 1,16 or 1,3,224,224"
        ) from exc

    if not parts:
        raise argparse.ArgumentTypeError("Shape cannot be empty.")

    return tuple(parts)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Convert a TorchScript model to Core ML (.mlpackage)."
    )
    parser.add_argument(
        "--source",
        required=True,
        help="Path to the source TorchScript model (.pt).",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Path to the output Core ML model (.mlpackage).",
    )
    parser.add_argument(
        "--input-name",
        default="input",
        help="Input tensor name for the Core ML model.",
    )
    parser.add_argument(
        "--input-shape",
        type=parse_shape,
        default=(1, 16),
        help="Input tensor shape, e.g. 1,16 or 1,3,224,224",
    )

    args = parser.parse_args()

    try:
        convert_torchscript_to_coreml(
            source_path=Path(args.source),
            output_path=Path(args.output),
            input_name=args.input_name,
            input_shape=args.input_shape,
        )
        return 0
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())