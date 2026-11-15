# AirFrameXR-agentic (experimental)

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
- The model holds about **12 GB of VRAM while the agent runs**. Close your game first, and run `stop.bat` before you play.

## Use
1. `install.bat` (10-30 minutes, mostly downloads; run it again if it stops, it resumes).
2. `start.bat`: starts the model, opens the agent in your AirFrameXR folder. Ask it anything about your settings. Quit the agent and the model stops.
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
Default: **Gemma 4 12B instruction-tuned, NVFP4** (`unsloth/gemma-4-12b-it-NVFP4`, 9.3 GB of weights, Apache-2.0). Why this one:
- It must fit about 12 GB with room for context. Qwen 3.8's smallest official model is 27B (21 GB in NVFP4) and DeepSeek V4 is far larger; neither fits. Gemma 4 12B is the strongest tool-calling model that does, and vLLM 0.33 has native Gemma 4 support (`gemma4` tool and reasoning parsers).
- NVFP4 runs natively on Blackwell tensor cores (that is what the bundled wheel adds on Windows).
- Alternatives are one line in `config\model.json` (for example `unsloth/gemma-4-E4B-it-NVFP4`, 8.1 GB, weaker; `RedHatAI/gemma-4-12B-it-NVFP4`, 10.3 GB). On a 24-32 GB card a larger model gives better answers (the maintainer runs Qwen 3.8 27B NVFP4 on an RTX 5090): change `repo`, `revision`, `servedName`, `targetVramGB` and the parsers together.

## Status (what was and was not tested)
Nothing here is "works" until its row says so.

| Item | State |
|---|---|
| Scripts parse in Windows PowerShell 5.1 | checked |
| Fresh install into an empty folder on the RTX 5090 PC | not run yet |
| Gemma 4 12B NVFP4 loads on vLLM 0.33 in a 12 GB budget | not run yet |
| Tool calls through the `gemma4` parser | not run yet |
| opencode accepts the generated config and permission rules | not run yet |
| Answer quality against real AirFrameXR logs | not run yet |
| 16 GB card (RTX 5070 Ti) | not run: the budget is computed from your VRAM, no 16 GB card was available |

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
