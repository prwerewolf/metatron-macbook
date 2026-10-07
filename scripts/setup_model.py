#!/usr/bin/env python3
"""Resolve local models; download only during explicitly requested setup."""

import argparse
import os
from pathlib import Path
import sys

DEFAULT_MODEL = "mlx-community/whisper-large-v3-turbo"
FALLBACK_MODEL = "mlx-community/whisper-base.en"


def complete_model(folder):
    folder = Path(folder)
    return (folder / "config.json").is_file() and any(
        (folder / name).is_file() and (folder / name).stat().st_size > 0
        for name in ("weights.safetensors", "weights.npz")
    )


def cache_root(environment):
    cache_home = Path(environment.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))).expanduser()
    hf_home = Path(environment.get("HF_HOME", str(cache_home / "huggingface"))).expanduser()
    return Path(environment.get("HF_HUB_CACHE", environment.get(
        "HUGGINGFACE_HUB_CACHE", str(hf_home / "hub")
    ))).expanduser()


def existing_model(environment):
    explicit = environment.get("PRESSTOWRITE_MODEL_DIR") or environment.get("METATRON_MODEL_DIR")
    if explicit:
        folder = Path(explicit).expanduser().resolve()
        if not complete_model(folder):
            raise RuntimeError("The explicitly configured model directory is incomplete.")
        return folder
    hub = cache_root(environment)
    for model in (DEFAULT_MODEL, FALLBACK_MODEL):
        repository = hub / ("models--" + model.replace("/", "--"))
        snapshots = repository / "snapshots"
        folders = []
        ref = repository / "refs" / "main"
        if ref.is_file():
            revision = ref.read_text().strip()
            if revision and "/" not in revision and revision not in (".", ".."):
                folders.append(snapshots / revision)
        if snapshots.is_dir():
            folders.extend(sorted(snapshots.iterdir()))
        for folder in folders:
            if complete_model(folder):
                return folder.resolve()
    return None


def prepare_model(download=False, environment=None, downloader=None):
    environment = os.environ if environment is None else environment
    existing = existing_model(environment)
    if existing:
        return existing
    if not download:
        raise RuntimeError("No complete local model found. Run make setup with internet access first.")
    if downloader is None:
        # No Hub dependency is imported for a cache check or offline setup.
        from huggingface_hub import snapshot_download
        downloader = snapshot_download
    folder = Path(downloader(
        repo_id=DEFAULT_MODEL,
        cache_dir=str(cache_root(environment)),
        allow_patterns=["config.json", "weights.safetensors", "weights.npz", "README.md", "LICENSE*"],
        token=False,
    ))
    if not complete_model(folder):
        raise RuntimeError("Model download is incomplete. Re-run setup before launching the app.")
    return folder


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true", help="Allow the one-time model download")
    args = parser.parse_args()
    try:
        prepare_model(download=args.download)
        print("A complete local speech model is available.")
        return 0
    except (OSError, RuntimeError, ImportError) as error:
        print(f"Model setup failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
