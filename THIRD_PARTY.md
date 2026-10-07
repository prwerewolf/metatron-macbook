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

Installed packages retain license files in their package metadata directories,
including notices for transitive dependencies. Consult those notices when
using or distributing third-party material separately. Press To Write's license
does not grant permission to redistribute Press To Write itself.
