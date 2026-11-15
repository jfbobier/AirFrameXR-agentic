# Knobs the assistant may propose (exact meaning and numbers: `docs-cache\EXPERIMENTAL_SWITCHES.md`, `PERFORMANCE_KNOBS.md`)

Rules of this table: a key at its default is **absent** from `config\airframexr.json` (the Advanced window removes it). Open the file first and copy
the nesting of the keys already there; the docs write `video.<key>` for keys inside the `video` object. Never invent a key that is not below.
"Takes effect": **live** = the streamer window watches the file; **restart** = the launcher restarts the streamer (tell the user to close and start the streamer);
**game** = at the next game start.

## Offer these (and prefer the window named in the last column)
| Key (airframexr.json) | Values, default | Takes effect | Propose when | Control in the UI |
|---|---|---|---|---|
| `frame_gen` | on/off, off | live | game's fps is below the display rate and `headset repeated` > 5 % | streamer window tick |
| `frame_gen_rate` | `third` / `half` / `two_thirds` / `uncapped`, half | live | pick the fastest rate whose run was clean (both repeat counts < 5 %); `uncapped` for games above/below ~50 fps per FRAME_GENERATION_UNCAPPED.md | streamer slider + Uncapped tick |
| `frame_gen_cap_fps` | 0-240, 0 (none) | live | a GPU-bound game with most releases late: about 90 % of its sustained fps | Advanced window |
| `frame_gen_synthesis` | `edge` / `classic` / `edge-blend`, edge | restart | ghosting/double images in one game: try `classic` as the predictable fallback; edge and edge-blend look the same | Advanced window |
| `drop_duplicate_frames` | true/false, false | restart | a mod that submits every frame twice (alternate-eye VR mods); labelled "Maximum OpenXR compatibility mode (lower performance)" | Advanced window |
| `phase_margin_ms` | ms, 7 | restart | `headset repeated` high with the stream near the display rate: Diagnose proposes a value from measurements, prefer its **Apply** button | Diagnostics card |
| `gpu_keepalive` | duty %, off | restart | GPU downclocks (P8, low video clock) and encode time rises while the GPU is under 30 % busy; typical on laptops | Diagnostics card |
| `qp_map` | true/false, true | restart | only to A/B on the user's request (never judged on a headset) | Advanced window |
| `encode_profile` | `foveated` / `full-split` | restart | only on the wizard's recommendation | Setup / Advanced |

## Only through the UI (they involve the stream size, the headset's declared field of view, or close the streamer)
Field of view restriction, render quality, stream fit, resolution, bitrate, foveation: launcher card **FOV restriction and calibration**, Setup tabs.
Explain the trade-off from `AVP_FOV.md` / `EXPERIMENTAL_SWITCHES.md` section 0 and let the user move the sliders. Vision Pro: two measured profiles exist (performance, quality).

## Needs the user (administrator prompt), explain, never do it yourself
- Frame-start gate (registry `ovrshim_vdxr_running_start`, default on, applies at the next game start): the commands are in EXPERIMENTAL_SWITCHES.md section 1.
  Propose turning it off only if a game LOSES fps with it on (its CPU frame is longer than its GPU frame). It is on by default and measured as no fps loss in 6 h of play.
- The launcher's OpenXR runtime button (Switch to AirFrameXR / back).

## Do not offer
Anything under "Removed on purpose" (PERFORMANCE_KNOBS.md, EXPERIMENTAL_SWITCHES.md section 5), environment variables `AIRFRAMEXR_*` (lab knobs), `phase_lock` off,
`intake_gate`, `running_start_ms`, `head_wait_ms`, `predict_missing_head` unless the user has a measured problem and asks: they held through every test at their defaults.
The game's own limits (DLSS quality, internal resolution) are often the real lever: say so.
