# AirFrameXR-agentic 0.1 (experimental)

> **Version 0.1.0, experimental.** A small local model proposes changes to your AirFrameXR settings and you approve each one. Expect rough edges; read the Status section for what was and was not tested.

A local AI assistant for [AirFrameXR](https://github.com/jfbobier/AirFrameXR) that replaces the manual. It runs entirely on your own NVIDIA GPU:
you describe what you see in the headset ("Gears of War judders", "double image in frame generation"), it reads **your** logs and settings, proposes
**one** change at a time with the reason, the restart rule and how to check it, and keeps a journal of what it changed.

Experimental, on purpose: the idea is that a manual you can talk to, that knows your PC's measurements, may beat a long page of settings. Whether it
does is what this repository is for finding out.

- **Self-contained.** One folder. `install.bat` puts Python, vLLM, the agent shell and the model inside `runtime\`; delete the folder to uninstall.
- **Local.** No cloud model, no account, no API key, nothing about your PC leaves it. The only network use is the install (GitHub, PyPI, PyTorch, Hugging Face) and copying AirFrameXR's docs from GitHub.
- **Safe by default.** Every file edit, every shell command beyond read-only ones, and every access outside the two folders it needs asks you first. It cannot touch the registry, the firewall or AirFrameXR's program files without you.
- **The weights are not in this repo.** They are downloaded from Hugging Face at a pinned revision (`config\model.json`).

## Requirements
- Windows 10/11, **NVIDIA RTX 50 series (Blackwell)**, driver 580 or newer, **16 GB of VRAM or more** (RTX 5070 Ti and up). The bundled vLLM carries native Blackwell FP4/FP8 kernels only; older cards are refused by the installer.
- About 30 GB of free disk. AirFrameXR installed (the assistant works without it, from the docs only).
- The model holds about **13 GB of VRAM while the agent runs**. Close your game first, and run `stop.bat` before you play.

## Install (one file)
Download **`setup.bat`** from the [0.1 release](https://github.com/jfbobier/AirFrameXR-agentic/releases/tag/v0.1.0), put it **in your AirFrameXR folder** (next to `AirFrameXR.exe`) and double-click it. It installs everything into `AirFrameXR\agentic\`
(about 9 GB of model plus 8 GB of runtime, 10-30 minutes; run it again if it stops, it resumes) and adds `AirFrameXR-Assistant.bat` to start it.
To uninstall, delete `AirFrameXR\agentic\` and that .bat.

## Use
1. (If you cloned this repo instead of using setup.bat: `install.bat`.)
2. `AirFrameXR-Assistant.bat` (or `start.bat` in this folder): starts the model, opens the agent in your AirFrameXR folder. Ask it anything about your settings. Quit the agent and the model stops.
   `start.bat -KeepRunning` leaves the model up; `stop.bat` frees the VRAM.
3. `update-docs.bat` refreshes the copy of AirFrameXR's docs the agent reads.

## How it works
| Piece | Where |
|---|---|
| The brief loaded at every session (rules, workflow) | `agent\AGENTS.md` |
| Facts about this PC, regenerated at each start (GPU, AirFrameXR folder, config files, last game runs) | `state\machine.md` |
| Playbooks read on demand: how to read the logs; which knobs it may propose | `agent\playbook\` |
| AirFrameXR's own docs (the source of truth for keys and numbers) | `docs-cache\`, indexed by `agent\docs-index.md` |
| What it changed and what came of it (its memory between sessions) | `notes\changes.md` |
| Model, revision and VRAM budget | `config\model.json` |
| Your own opencode additions (merged on top, your permission rules win) | `config\opencode.user.json` (optional) |

The playbooks carry mechanisms and rules, not numbers: the numbers live in AirFrameXR's docs and are read from there, so they cannot drift.

## The model
Default: **Gemma 4 12B instruction-tuned, NVFP4** (`unsloth/gemma-4-12b-it-NVFP4`, 9.3 GB download, Apache-2.0), served with a 13 GB budget and an
**81,920-token context** (101k tokens of KV cache). The context is the point: the brief, both playbooks and the docs index are loaded whole, and a search
result or a log excerpt fits beside them. Measured on the RTX 5090 with a 13 GB cap (2026-11-15): a fact buried in an 82k-token prompt of the real docs was found.

Why not smaller (the download would be 4-5 GB): two smaller NVFP4 models were run through the same real session (the agent reads a real AirFrameXR log and must
propose one change, through opencode, 2-3 runs each, one scenario, judged by hand):

| Model | Download | Result |
|---|---|---|
| Qwen3.5 4B NVFP4 | 4.2 GB | reads the right files but the answer is incoherent (fragments, an invented cause, a bitrate change not supported by the log). Not trusted with settings |
| Qwen3 8B NVFP4 (NVIDIA) | 6.4 GB | tried to edit files when told not to (the permission rules blocked it), wrong reasoning, one run gave no answer |
| **Gemma 4 12B NVFP4** | 9.3 GB | follows the brief: reads evidence, quotes lines with dates, one proposal in the five-point form, asks before acting. Still imperfect (it once proposed a rate while frame generation was off): the user approves every edit |

Qwen 3.8's smallest official model is 27B (21 GB in NVFP4) and DeepSeek V4 is far larger; neither fits a 16 GB card. A bigger model gives better answers
if your card allows it (the maintainer runs Qwen 3.8 27B NVFP4 on an RTX 5090): change `repo`, `revision`, `servedName`, `targetVramGB`, the parsers and
`contextTokens` together in `config\model.json`. `eval\agent_eval.py` (behaviour checks) and `eval\needle.py` (long context) test any model against a running server.

**This is a small model editing your settings.** That is why every edit asks for your approval and shows its diff, why a backup is made first, and why it
may only change the keys listed in `agent\playbook\knobs.md`. Read what it proposes; the journal in `notes\changes.md` records everything it did.

## Status (what was and was not tested)
Nothing here is "works" until its row says so.

| Item | State |
|---|---|
| Scripts parse in Windows PowerShell 5.1 | checked |
| Fresh install into an empty folder on the RTX 5090 PC (2026-11-15, `install.bat -SkipModel`, then with the model) | **passed**: uv, Python 3.13, torch cu130 + 153 pinned packages, the wheel (checksum verified), smoke test on the GPU (matmul, FP8, NVFP4 all OK), opencode 1.19.5, docs copy, model download (8.7 GB, 96 s on that line); total env about 8.5 GB. Not run: a PC without the previous vLLM, the wheel download from the GitHub release (the repo is not published yet: a local wheel with the same checksum was used) |
| Gemma 4 12B NVFP4 loads on vLLM 0.33 inside the 13 GB budget (`--language-model-only` is required: the vision encoder budget otherwise exceeds the batch size) | **passed** on the RTX 5090 capped at 13 GB: 101k tokens of KV cache, 81,920 context |
| Tool calls through the `gemma4` parser, opencode 2.3.0 | **passed**: `opencode run` made grep/read calls and read-only commands; `eval\agent_eval.py` 5/5 (reads evidence first, refuses an invented key, will not touch the registry, proposes with restart rule and verification) |
| opencode accepts the generated config and enforces the permission rules | **passed** headless: asks are auto-rejected in a non-interactive run (an edit and a delete were blocked). **Not tested**: the interactive TUI approval flow |
| Nothing leaves the PC | opencode falls back to its own hosted free models when no local model answers (seen in a test run). `enabled_providers: ["vllm"]` plus `OPENCODE_DISABLE_FREE_MODELS`/`MODELS_FETCH`/`AUTOUPDATE` are now set; with the server down the run fails with "No model is available". **Not audited**: a packet capture of a full session |
| Answer quality against real AirFrameXR logs | **partly**: one scenario (judder in a game, real log), 2-3 runs per model, judged by hand. Proposals were grounded in the log and the playbook but not always the best lever. No headset test of any proposed change |
| 16 GB card (RTX 5070 Ti) | not run: 13 GB is capped on a 32 GB card; a real 16 GB card also carries the Windows desktop (about 1-1.5 GB) |

## Where the wheel comes from
vLLM has no Windows build with native Blackwell FP4 kernels, so `wheel-build\` holds how the one used here was made: upstream vLLM 0.33.0 + the community
`aivrar/vllm-windows-build` patch + a small opt-in SM120 patch (proposed upstream: https://github.com/aivrar/vllm-windows-build/pull/19). The wheel itself is
a release asset of this repository; `config\wheel.json` pins its SHA-256 and the installer refuses a file that does not match.

## Known problems
- **`0xC000001D` / cuBLAS dies at start:** Windows hides AVX-512 from your CPU (the boot setting `xsaveremovefeature`, often set for anti-cheat games). It only matters on CPUs that have AVX-512 (AMD Zen 4/5, some Intel server parts). Undo it (administrator, then reboot): `bcdedit /deletevalue xsaveremovefeature`. This affects games with anti-cheat, so it is your call; the installer does not touch it.
- **Out of memory at startup:** another program holds VRAM. Close it, or `start.bat -Eager`, or lower `targetVramGB` in `config\model.json`.
- **Long first start:** the first run compiles kernels (minutes); later starts take 1-3 minutes.

## Licence
MIT (see LICENSE). Third-party components keep their own licences: THIRD_PARTY_NOTICES.md.
