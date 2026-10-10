# Third-party software and speech models

The repository's restrictive license covers original Press To Write material.
It does not replace the licenses for separately installed dependencies or model
weights. Setup downloads dependencies into a local Python environment and models
into a local cache; neither is included in this repository.

- [MLX](https://github.com/ml-explore/mlx) and
  [MLX Whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper)
  use the MIT license.
- [NumPy](https://numpy.org/doc/stable/license.html) uses a BSD license and
  includes notices for bundled components.
- [Hugging Face Hub](https://github.com/huggingface/huggingface_hub) uses
  Apache License 2.0.
- The default
  [MLX Whisper large-v3-turbo model](https://huggingface.co/mlx-community/whisper-large-v3-turbo)
  and [English base fallback](https://huggingface.co/mlx-community/whisper-base.en)
  publish their own model cards and license information.
- Optional [NeMo-Speech.cpp 0.2.0](https://github.com/NVIDIA/NeMo-Speech.cpp/tree/v0.2.0)
  uses Apache License 2.0. The separately installed Metal package retains its
  LICENSE, NOTICE, and third-party notices, including GGML and SentencePiece.
- Optional [Nemotron English 0.6B](https://huggingface.co/nvidia/nemotron-speech-streaming-en-0.6b)
  publishes the NVIDIA Open Model License. Setup pins model revision
  `ebe59e5a817142986528bbbee5dba8db7b38ed50` and verifies the Q8 GGUF and original
  SentencePiece tokenizer by SHA-256. An older export omitted the tokenizer;
  setup adds the original tokenizer metadata for RNNT word boosting without
  altering tensor data or quantization. See the upstream
  [boosting documentation](https://github.com/NVIDIA/NeMo-Speech.cpp/blob/v0.2.0/docs/asr/customization.md).

Installed packages retain license files in their package metadata directories,
including notices for transitive dependencies. Consult those notices when
using or distributing third-party material separately. Press To Write's license
does not grant permission to redistribute Press To Write itself.
