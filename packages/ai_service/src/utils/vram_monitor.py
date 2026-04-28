import os
import subprocess


def get_vram_used_gb() -> float:
    """Return current GPU VRAM usage in GiB, or 0.0 if nvidia-smi unavailable."""
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return float(result.stdout.strip()) / 1024  # MiB → GiB
    except Exception:
        return 0.0


def check_vram(threshold_gb: float = None) -> None:
    """Raise MemoryError if VRAM usage exceeds threshold_gb."""
    threshold_gb = threshold_gb or float(os.getenv("VRAM_THRESHOLD", "5.5"))
    used = get_vram_used_gb()
    if used >= threshold_gb:
        raise MemoryError(
            f"VRAM {used:.1f} GB >= threshold {threshold_gb} GB — reduce load before continuing"
        )
