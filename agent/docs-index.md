# Docs index (copies of the AirFrameXR project docs in `docs-cache\`)

Search first (grep tool), read second (read tool, a small range).

| File | Answers | Notes |
|---|---|---|
| `EXPERIMENTAL_SWITCHES.md` | every setting key: where it lives, values, default, when a change takes effect, what we measured | **the authority for keys.** Three "takes effect" rules: streamer restart / live / next game start |
| `PERFORMANCE_KNOBS.md` | what each knob does, what drives it, and the list "Removed on purpose" | read the removed list before proposing anything |
| `PERFORMANCE_FINDINGS.md` | what was already tried and failed (dead ends) | read before suggesting any optimisation |
| `FRAME_GENERATION.md`, `FRAME_GENERATION_UNCAPPED.md` | how frame generation works, the rates, the recorded per-game choice, uncapped mode | |
| `AVP_FOV.md`, `FOV_CALIBRATION.md` | Vision Pro field of view, the two profiles, calibration | Vision Pro only |
| `HMD_PROFILES.md` | community headset profiles | |
| `INSTALL.md` | the folder layout, setup steps, which log holds what, audio | |
| `ARCHITECTURE.md` | how the pieces fit | long; grep, do not read through |
| `progress.md` | current status and what is untested | the place that says "tested" vs "only built" |
| `README.md` | human-facing overview, recommended network setup, Black Box performance recorder | may lag behind the code; the docs above win |

If a doc and the user's installed build disagree (a key missing from `airframexr.json`'s docs or a window that looks different), the build may be older or
newer than the docs: ask the user for the version shown in the launcher and say what you could not confirm.
