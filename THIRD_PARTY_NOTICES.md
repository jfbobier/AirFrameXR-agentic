# Third-party notices

This repository's own scripts and texts are MIT (see LICENSE). It downloads, but does not contain, the components below; each keeps its own licence.

| Component | How it is used | Licence | Source |
|---|---|---|---|
| vLLM 0.33.0 | the model server; a self-built Windows wheel with native Blackwell kernels is a release asset of this repo; the patches applied to it are in `wheel-build\patches\` | Apache-2.0 | https://github.com/vllm-project/vllm |
| aivrar/vllm-windows-build | the community Windows port of vLLM that our patch set is built on (`wheel-build\patches\aivrar-vllm-windows-v12.patch` is that project's patch, unmodified) | MIT, Copyright (c) 2025 aivrar | https://github.com/aivrar/vllm-windows-build |
| CUTLASS | compiled into vLLM's FP8/NVFP4 kernels; `wheel-build\patches\cutlass-windows-sm120.patch` is a small Windows build fix | BSD-3-Clause | https://github.com/NVIDIA/cutlass |
| PyTorch, torchvision, torchaudio | installed from the PyTorch CUDA 13 index | BSD-style | https://pytorch.org |
| triton-windows | Triton kernels on Windows | MIT | https://github.com/woct0rdho/triton-windows |
| opencode 2.3.0 | the terminal agent shell, downloaded from its GitHub release | MIT | https://github.com/anomalyco/opencode |
| uv | creates the Python environment | MIT or Apache-2.0 | https://github.com/astral-sh/uv |
| Gemma 4 12B (instruction tuned) | the default model, downloaded from Hugging Face (`unsloth/gemma-4-12b-it-NVFP4`, an NVFP4 quantisation of Google's `google/gemma-4-12B-it`); weights are never stored in this repository | Apache-2.0 (as declared on both model cards) | https://huggingface.co/google/gemma-4-12B-it |
| The other Python packages | pinned in `requirements.lock.txt`, installed from PyPI | each its own | |

The docs copied into `docs-cache\` at install time are AirFrameXR's own documentation (MIT), https://github.com/jfbobier/AirFrameXR.
