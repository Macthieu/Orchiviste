from __future__ import annotations

from pathlib import Path

import torch
import torch.nn as nn


class TinyDocClassifier(nn.Module):
    """
    Very small demo model for testing the Core ML conversion pipeline.

    Input shape:
        (batch_size, 16)

    Output shape:
        (batch_size, 3)
    """

    def __init__(self) -> None:
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(16, 8),
            nn.ReLU(),
            nn.Linear(8, 3),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)


def main() -> None:
    output_dir = Path("ml/models-src")
    output_dir.mkdir(parents=True, exist_ok=True)

    model = TinyDocClassifier()
    model.eval()

    example_input = torch.randn(1, 16)
    traced_model = torch.jit.trace(model, example_input)

    output_path = output_dir / "tiny_doc_classifier.pt"
    traced_model.save(str(output_path))

    print(f"TorchScript model saved to: {output_path}")


if __name__ == "__main__":
    main()