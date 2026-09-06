"""Single source of truth for every path in the project.

Import this instead of writing paths. Nothing else in the codebase should
contain an absolute path, because the two machines differ and hardcoded paths
are the reason "works on my laptop" happens.

    from config.paths import P
    P.tierA_raw / "session_003.wav"
"""
import os
from pathlib import Path
from dataclasses import dataclass

from dotenv import load_dotenv

REPO = Path(__file__).resolve().parent.parent
load_dotenv(REPO / ".env")


def _data_root() -> Path:
    raw = os.environ.get("NAJDICS_DATA_ROOT")
    if not raw:
        raise RuntimeError(
            "NAJDICS_DATA_ROOT is not set. Copy .env.example to .env and set it, "
            "or run ./scripts/bootstrap.sh"
        )
    p = Path(raw).expanduser().resolve()
    if not p.exists():
        raise RuntimeError(f"NAJDICS_DATA_ROOT points at a missing directory: {p}")
    return p


@dataclass(frozen=True)
class Paths:
    repo: Path
    data: Path
    role: str

    # --- in git (small, textual, versioned) ---
    @property
    def docs(self) -> Path: return self.repo / "docs"
    @property
    def guidelines(self) -> Path: return self.repo / "guidelines"
    @property
    def metadata(self) -> Path: return self.repo / "metadata"
    @property
    def transcripts(self) -> Path: return self.repo / "corpus" / "transcripts"
    @property
    def splits(self) -> Path: return self.repo / "splits"
    @property
    def provenance(self) -> Path: return self.repo / "provenance"

    # --- not in git (bulk binary) ---
    @property
    def tierA_raw(self) -> Path: return self.data / "tierA" / "raw"
    @property
    def tierA_work(self) -> Path: return self.data / "tierA" / "work"
    @property
    def tierB_raw(self) -> Path: return self.data / "tierB" / "raw"
    @property
    def tierB_work(self) -> Path: return self.data / "tierB" / "work"
    @property
    def drafts(self) -> Path: return self.data / "drafts"
    @property
    def checkpoints(self) -> Path: return self.data / "checkpoints"

    @property
    def is_gpu(self) -> bool: return self.role == "gpu"
    @property
    def is_mac(self) -> bool: return self.role == "mac"

    def audio_for(self, segment: dict) -> Path:
        """Resolve a segment's audio_path (stored relative) to this machine."""
        return (self.data / segment["audio_path"]).resolve()

    def relative(self, absolute: Path) -> str:
        """Store paths RELATIVE to the data root, never absolute.

        This is what makes a transcripts JSONL file portable between machines.
        """
        return str(Path(absolute).resolve().relative_to(self.data))


P = Paths(repo=REPO, data=_data_root(), role=os.environ.get("MACHINE_ROLE", "mac"))


if __name__ == "__main__":
    print(f"repo        {P.repo}")
    print(f"data        {P.data}")
    print(f"role        {P.role}")
    print()
    for name in ("tierA_raw", "tierA_work", "tierB_raw", "tierB_work",
                 "drafts", "checkpoints", "transcripts", "guidelines"):
        p = getattr(P, name)
        print(f"  {'ok ' if p.exists() else 'MISSING'}  {name:14s} {p}")
