#!/usr/bin/env python3
"""Explicit one-time installation of optional Nemotron English on Metal.

Only public, pinned assets are downloaded. Normal dictation never imports this
installer. --offline verifies or repairs from already downloaded assets.
"""

import argparse
import hashlib
import json
from pathlib import Path
import platform
import shutil
import sys
import tarfile
import tempfile
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "daemon"))
from gguf_metadata import embed_tokenizer, embedded_tokenizer
from nemotron_engine import (SDK_FOLDER, SDK_SHA256, MODEL_REVISION, MODEL_FILENAME,
                             MODEL_SHA256, TOKENIZER_SHA256, REPAIRED_SHA256, install_root, local_files)

SDK_URL = f"https://github.com/NVIDIA/NeMo-Speech.cpp/releases/download/v0.2.0/{SDK_FOLDER}.tar.gz"
MODEL_BASE = f"https://huggingface.co/nvidia/nemotron-speech-streaming-en-0.6b/resolve/{MODEL_REVISION}/"
TOKENIZER_START, TOKENIZER_SIZE = 21504, 251056


def digest(path):
    sha = hashlib.sha256()
    with Path(path).open("rb") as file:
        for block in iter(lambda: file.read(1024 * 1024), b""):
            sha.update(block)
    return sha.hexdigest()


def asset(url, target, expected, offline=False, byte_range=None):
    if target.is_file() and digest(target) == expected:
        return target
    if offline:
        raise RuntimeError("A verified fast-mode asset is missing. Run make setup-fast online once.")
    headers = {"User-Agent": "PressToWrite-local-setup"}
    if byte_range:
        start, size = byte_range
        headers["Range"] = f"bytes={start}-{start + size - 1}"
    temporary = target.with_suffix(target.suffix + ".part")
    try:
        print(f"Downloading public asset: {target.name}", flush=True)
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as response:
            if byte_range and (response.status != 206 or not response.headers.get("Content-Range", "").startswith(
                f"bytes {start}-{start + size - 1}/"
            )):
                raise RuntimeError("The model host did not provide the requested tokenizer range")
            with temporary.open("wb") as output:
                shutil.copyfileobj(response, output, 1024 * 1024)
        if byte_range and temporary.stat().st_size != size:
            raise RuntimeError("Incomplete tokenizer download")
        if digest(temporary) != expected:
            raise RuntimeError("Fast-mode asset checksum mismatch; installation stopped")
        temporary.replace(target)
        return target
    finally:
        temporary.unlink(missing_ok=True)


def extract_sdk(archive, destination):
    with tarfile.open(archive) as package:
        members = package.getmembers()
        root = destination.resolve()
        for member in members:
            path = (root / member.name).resolve()
            if not path.is_relative_to(root):
                raise ValueError("Runtime archive path escapes the installation directory")
            if member.issym() or member.islnk():
                link = path.parent / member.linkname if member.issym() else root / member.linkname
                if not link.resolve().is_relative_to(root):
                    raise ValueError("Runtime archive link escapes the installation directory")
            elif not (member.isfile() or member.isdir()):
                raise ValueError("Unsupported runtime archive member")
        package.extractall(destination, members=members)


def prepare(destination=None, cache=None, offline=False):
    root = install_root() if destination is None else Path(destination)
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    cache = root / "downloads" if cache is None else Path(cache)
    cache.mkdir(parents=True, exist_ok=True)
    archive = asset(SDK_URL, cache / f"{SDK_FOLDER}.tar.gz", SDK_SHA256, offline)
    original = asset(MODEL_BASE + MODEL_FILENAME, cache / MODEL_FILENAME, MODEL_SHA256, offline)
    tokenizer = asset(MODEL_BASE + "nemotron-speech-streaming-en-0.6b.nemo",
                      cache / "nemotron-en-tokenizer.model", TOKENIZER_SHA256, offline,
                      (TOKENIZER_START, TOKENIZER_SIZE))
    with tempfile.TemporaryDirectory(prefix="fast-setup-", dir=root) as temporary:
        temporary = Path(temporary)
        library = root / SDK_FOLDER / "lib/libnemo_speech_asr_c.dylib"
        if not library.is_file():
            extract_sdk(archive, temporary)
            extracted = temporary / SDK_FOLDER
            if not (extracted / "lib/libnemo_speech_asr_c.dylib").is_file():
                raise RuntimeError("The verified runtime archive is incomplete")
            if (root / SDK_FOLDER).exists():
                raise RuntimeError("An incomplete runtime folder exists. Preserve it and repair setup before continuing.")
            extracted.rename(root / SDK_FOLDER)
        repaired = root / "nemotron-en-boosted.gguf"
        if not repaired.is_file() or digest(repaired) != REPAIRED_SHA256:
            print("Embedding the original matching tokenizer; preserving all tensor bytes…", flush=True)
            output = temporary / repaired.name
            embed_tokenizer(original, output, tokenizer.read_bytes())
            if digest(output) != REPAIRED_SHA256:
                raise RuntimeError("Repaired model checksum mismatch")
            output.replace(repaired)
    if hashlib.sha256(embedded_tokenizer(repaired)).hexdigest() != TOKENIZER_SHA256:
        raise RuntimeError("Vocabulary tokenizer verification failed")
    local_files(root)
    (root / "install.json").write_text(json.dumps({
        "sdk_sha256": SDK_SHA256, "model_revision": MODEL_REVISION,
        "original_sha256": MODEL_SHA256, "tokenizer_sha256": TOKENIZER_SHA256,
        "repaired_sha256": REPAIRED_SHA256,
    }, indent=2) + "\n")
    print("Fast mode installed locally. Select Fast — Nemotron English in Settings → Engine.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--destination", type=Path)
    parser.add_argument("--cache", type=Path, help="Use an existing public-asset cache")
    args = parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        parser.error("Fast mode requires a native Apple Silicon Mac")
    try:
        prepare(args.destination, args.cache, args.offline)
        return 0
    except (OSError, ValueError, RuntimeError) as error:
        print(f"Fast-mode setup failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
