"""Small, bounded GGUF v3 metadata reader and lossless tokenizer repair.

Tensor bytes and relative tensor offsets are copied unchanged. No model library
or network access is needed to inspect a model or embed its original tokenizer.
"""

import base64
from pathlib import Path
import shutil
import struct

TOKENIZER_KEY = "asr.tokenizer.spm_model"
SCALARS = {0: "B", 1: "b", 2: "H", 3: "h", 4: "I", 5: "i", 6: "f", 7: "?", 10: "Q", 11: "q", 12: "d"}


def exact(file, count):
    data = file.read(count)
    if len(data) != count:
        raise ValueError("Incomplete GGUF model")
    return data


def integer(file):
    return struct.unpack("<Q", exact(file, 8))[0]


def string(file):
    size = integer(file)
    if size > 4 * 1024 * 1024:
        raise ValueError("GGUF metadata string is too large")
    return exact(file, size).decode("utf-8")


def value(file, kind):
    if kind in SCALARS:
        fmt = "<" + SCALARS[kind]
        return struct.unpack(fmt, exact(file, struct.calcsize(fmt)))[0]
    if kind == 8:
        return string(file)
    if kind == 9:
        element = struct.unpack("<I", exact(file, 4))[0]
        count = integer(file)
        if count > 100000 or element == 9:
            raise ValueError("Unsupported GGUF metadata array")
        return [value(file, element) for _ in range(count)]
    raise ValueError("Unsupported GGUF metadata type")


def read_metadata(path):
    with Path(path).open("rb") as file:
        if exact(file, 4) != b"GGUF" or exact(file, 4) != struct.pack("<I", 3):
            raise ValueError("Expected a GGUF v3 model")
        tensors, count = integer(file), integer(file)
        if count > 4096 or tensors > 100000:
            raise ValueError("Invalid GGUF model header")
        metadata = {}
        for _ in range(count):
            key = string(file)
            if key in metadata:
                raise ValueError("Duplicate GGUF metadata key")
            metadata[key] = value(file, struct.unpack("<I", exact(file, 4))[0])
        metadata_end = file.tell()
        for _ in range(tensors):
            string(file)
            dimensions = struct.unpack("<I", exact(file, 4))[0]
            if not 1 <= dimensions <= 4:
                raise ValueError("Invalid GGUF tensor dimensions")
            exact(file, dimensions * 8 + 4 + 8)
        alignment = metadata.get("general.alignment", 32)
        if not isinstance(alignment, int) or not 1 <= alignment <= 4096:
            raise ValueError("Invalid GGUF tensor alignment")
        table_end = file.tell()
        data_offset = (table_end + alignment - 1) // alignment * alignment
        if Path(path).stat().st_size < data_offset:
            raise ValueError("Incomplete GGUF tensor table")
        return metadata, metadata_end, table_end, data_offset


def embedded_tokenizer(path):
    metadata = read_metadata(path)[0]
    text = metadata.get(TOKENIZER_KEY)
    if not isinstance(text, str) or not text:
        raise ValueError("Nemotron vocabulary boosting needs its embedded tokenizer. Run make setup-fast.")
    data = base64.b64decode(text, validate=True)
    if not 1024 <= len(data) <= 1024 * 1024:
        raise ValueError("Invalid embedded Nemotron tokenizer")
    return data


def embed_tokenizer(source, destination, tokenizer):
    source, destination = Path(source), Path(destination)
    if source.resolve() == destination.resolve():
        raise ValueError("Preserve the original model when repairing the tokenizer")
    metadata, metadata_end, table_end, data_offset = read_metadata(source)
    if TOKENIZER_KEY in metadata:
        raise ValueError("The model already contains a tokenizer")
    def encoded_string(text):
        data = text.encode("utf-8")
        return struct.pack("<Q", len(data)) + data
    extra = encoded_string(TOKENIZER_KEY) + struct.pack("<I", 8)
    extra += encoded_string(base64.b64encode(tokenizer).decode("ascii"))
    alignment = metadata.get("general.alignment", 32)
    with source.open("rb") as original, destination.open("xb") as repaired:
        header = bytearray(exact(original, 24))
        struct.pack_into("<Q", header, 16, len(metadata) + 1)
        repaired.write(header)
        repaired.write(exact(original, metadata_end - 24))
        repaired.write(extra)
        repaired.write(exact(original, table_end - metadata_end))
        repaired.write(b"\0" * (-repaired.tell() % alignment))
        original.seek(data_offset)
        shutil.copyfileobj(original, repaired, 1024 * 1024)
    if embedded_tokenizer(destination) != tokenizer:
        raise ValueError("Tokenizer repair verification failed")
