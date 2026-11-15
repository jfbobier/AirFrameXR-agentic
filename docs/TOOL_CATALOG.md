# Deterministic helpers for a small model: first catalog (draft, 2026-11-15)

Principle: **the model decides what to ask and how to say it; code decides every number, every rule and every write.** A 12B model can pick a
well-named tool and fill typed parameters; it cannot be trusted to do tangent arithmetic, apply a threshold from memory or write valid JSON.
Nothing below exists yet. Every item says where its truth lives, so it is ported, not invented.

## 1. Conventions

- **Two layers.** A small *exposed surface* (8 tools, section 2: what the model sees and chooses between) over a larger *internal library* (section 3: pure functions, unit-tested, reused by several tools). Few tools = fewer wrong choices; the library can grow freely.
- **Intent-level, not function-level.** `fov_plan` does the whole job (parse the symptom, compute, validate, report the pixel cost). The model never chains `tan`, `atan` and a validator.
- **Results carry the wording.** Every result is `{ok, conclusion, facts, recommend[], evidence[], caveats[], next[]}`: `conclusion` is one plain sentence the model can read out; `recommend` entries name the exact control or `propose_change` arguments; `evidence` points at file and line; `caveats` carry the "untested / judgement" flags from the docs; `next` names the tool to call after.
- **Errors never raise.** `{ok:false, why, ask_user}`: what was wrong in words, and the one question to put to the user.
- **Units in names** (`_deg`, `_tan`, `_ms`, `_mbps`, `_px`); numbers rounded for speech (tangents 2 decimals, angles 1, as the UI shows them), exact values kept in `facts`.
- **Deterministic.** Same inputs, same output; no clock except an explicit `now`; no network.
- **Read-only unless the name says otherwise.** Only `apply_change` and `undo_change` write, and the user approves each (permission `ask`); the others are allowed without prompting.
- **Golden vectors or it does not ship.** Each function has vectors generated from AirFrameXR's own implementation (the C# in `tools/gui/`, the Rust host, or `harness/fov_stream_geometry.py`, which already self-tests against the shader's equations). A function with no vector is a draft. The suite runs on Linux.
- **Reuse before writing.** `harness/fov_stream_geometry.py` and `harness/lib.py` (`fov_vars`) are vendored with provenance (same author, MIT); `Advice.cs` thresholds and `FovValidator` are ported line by line.
- Stdlib (plus numpy, already in the runtime) so it runs on the Python that ships with vLLM; no .exe.

## 2. The exposed surface (8 tools) with the text the model sees

Descriptions are what goes in the tool definition: imperative, say *when* to call, say what it does not do.

| # | Tool | Description shown to the model | Params (typed) | Writes | Permission |
|---|---|---|---|---|---|
| 1 | `afxr_status` | "Call first in every session. Returns the installed AirFrameXR version, the headset and display rate seen in the logs, which config files exist, and the last game runs. Use it instead of reading logs by hand." | none | no | allow |
| 2 | `diagnose` | "Call when the user describes judder, stutter, lag, repeated frames, a slow encoder or Wi-Fi trouble. Reads the logs and applies AirFrameXR's own rules; returns ranked findings with the numbers, the log lines, and which setting or button to use. Does not change anything." | `game` (exe name, optional), `last_n_runs` (1-10, default 3) | no | allow |
| 3 | `explain_setting` | "Call when the user names a setting or a button, or when you want to propose one. Returns what it does, its default, its current value on this PC, where in the UI it is, when a change takes effect (live / streamer restart / next game start), and whether it may be changed (user-safe / UI only / removed / lab only)." | `name` (key or UI label) | no | allow |
| 4 | `fov_check` | "Call when the user gives or asks about field-of-view numbers (four edges, tangents or degrees). Validates them, converts between tangents and degrees, and says what share of the headset's picture and of the game's pixels they keep." | `outer`, `inner`, `upper`, `lower` (numbers), `unit` ("tan"\|"deg"), `profile` (optional name) | no | allow |
| 5 | `fov_plan` | "Call to compute new field-of-view edges from a symptom or a goal: a black band or a visible box at one edge, a cut corner, 'more margin', 'fewer pixels' (target saving), or switching to the shipped or measured profile. Returns the four new values, their cost in pixels, and the exact fields to type in the launcher's FOV card. Does not change anything." | `symptom` (enum), `edge` (outer\|inner\|upper\|lower, when relevant), `amount` (enum: a_little\|some\|a_lot, or `degrees` number), `goal_saving_pct`, `current` (4 numbers, default: read from this PC) | no | allow |
| 6 | `calc` | "Call for any arithmetic you would otherwise do in your head: display period, generation caps at a refresh rate, a cap for a GPU-bound game, bits per pixel, Mbps conversions, pixel counts, sizes aligned to 32." | `kind` (enum, section 3.D), plus the parameters of that kind | no | allow |
| 7 | `propose_change` | "Call before any edit. Checks that the key exists and is user-safe, that the value is valid, shows the exact diff, the restart rule, how to verify and how to undo. Returns a `proposal_id`. Does not write." | `key`, `value`, `reason` (one sentence, with the measurement) | no | allow |
| 8 | `apply_change` / `undo_change` | "Call only after the user approved a proposal. `apply_change` backs the file up, writes it, checks it parses, and appends the journal; `undo_change` restores the backup." | `proposal_id` / `change_id` | **yes** | **ask** |

`afxr_status`, `explain_setting` and `diagnose` replace the shell reads that were failing on Windows (cmd.exe) and the log greps a small model was
skipping. `propose_change` -> `apply_change` makes "one change at a time, backup first, journal" a property of the code instead of a request in the prompt.

### Example result shapes (illustrative: the numbers are the shipped Vision Pro profile, to be re-validated against the engine before use)

`fov_plan(symptom="black_band", edge="lower", amount="a_little")` with the shipped 0.97 / 0.71 / 0.69 / 0.63:
```json
{"ok": true,
 "conclusion": "Raising the lower edge from 0.63 (32.2 deg) to 0.68 (34.2 deg) should remove a band of black at the bottom, at a cost of about 1 point of game pixels (35.3 % to 36.6 % of the headset's declared picture).",
 "facts": {"before": {"outer": 0.97, "inner": 0.71, "upper": 0.69, "lower": 0.63}, "after": {"outer": 0.97, "inner": 0.71, "upper": 0.69, "lower": 0.68},
           "step_deg": 2.0, "area_share_before": 0.353, "area_share_after": 0.366, "within_declared": true},
 "recommend": [{"where": "Launcher > FOV restriction and calibration card > Lower", "type": "0.68", "takes_effect": "streamer restart, then the game's next start"}],
 "caveats": ["The step size (2 degrees) is a default, not a measurement: use the FOV grid (fovgrid.exe) to check the bottom edge afterwards."],
 "next": ["Ask the user to run fovgrid.exe and look at the bottom border"]}
```
`diagnose(game="SWGR-Win64-Shipping.exe")` on the real log of 2026-11-15:
```json
{"ok": true,
 "conclusion": "Run 3 (12:41) was not smooth: 77.6 fps on a 100 Hz panel and the headset repeated 7.2 % of its refreshes (over the 5 % limit). Run 4 (13:36) was clean (1.0 %).",
 "recommend": [{"lever": "Frame generation", "where": "Streamer window > Frame generation tick", "why": "rendered fps under 90 % of the panel rate and repeats over 5 % (the rule in Advice.cs)", "takes_effect": "live"}],
 "evidence": [{"file": "logs/AirFrameXR.log", "line": 32, "text": "game run recorded: SWGR-Win64-Shipping.exe ... headset repeated 7.2 % typical / 59.5 % worst (run 3)"}],
 "caveats": ["Run 3 lasted 38 s: too short to be typical."],
 "next": ["explain_setting('Frame generation')", "propose_change"]}
```

## 3. The internal library (first list)

Priority: **P0** first slice, **P1** next, **P2** later. "Truth" is the source the function is ported from and tested against.

### A. Field of view (the user's example domain)
| Function | Does | Truth | P |
|---|---|---|---|
| `tan_to_deg`, `deg_to_tan` | angle of a half-FoV edge <-> tangent | `FovValidator.Check` | P0 |
| `eye_edges(values, eye)` | outer/inner swap between left and right eye | AVP_FOV.md, `fov_scale_from` | P0 |
| `fov_totals(edges)` | horizontal and vertical total in degrees | `FovValidator` (c.TotalH/TotalV) | P0 |
| `area_share(values, declared)` | share of the declared picture rendered; each edge counts at most the declared one | `FovValidator` (AreaShare) | P0 |
| `fov_validate(values, unit, declared)` | the validator's red/yellow messages (not a number, >= 90 deg, over declared, an edge under 70 % of declared, side ratio > 1.8, vertical ratio > 2, total outside 40-130 deg) | `FovValidator.Check` | P0 |
| `edge_adjust(edge, delta_deg)` | move one edge by a number of degrees, clamp to the declared tangent | AVP_FOV.md ("visible + 3 deg" recommended, "+5 deg" safer) | P0 |
| `fov_from_visible(visible_deg, margin_deg)` | recommended / tight / safer rows from measured visible angles | AVP_FOV.md tables | P0 |
| `symptom_to_edge(symptom, location)` | black band at a side -> raise that edge; border cut -> more margin; "box" at the bottom -> lower edge. **Curated rule, to be confirmed by the author before shipping** | FovValidator message ("if you see black bands, raise the value"), AVP_FOV.md "Check it" | P0 |
| `pixel_saving(values, declared, quality)` | game pixel cost relative to an unrestricted game | AVP_FOV.md, FOV_PIPELINE_OPTIM.md | P0 |
| `fov_scale_effect(declared, scale)` | the stock client's FoV Scale: declared tangents x scale, density x 1/scale (0.8 -> 1.25 x), the inner edge clamp | AVP_FOV.md | P1 |
| `profile_load(name)` / `profile_validate(json)` | shipped and user profiles (`config\user_fov_profiles.json`, `profiles\*.json`) | `harness/fov_profile_check.py`, HMD_PROFILES.md | P1 |
| `calibration_union(sweeps, coverage)` | the rectangle covering N % of measured windows | `UserFovProfiles.FromCalibration`, FOV_CALIBRATION.md | P2 |

### B. Stream geometry and encode
| Function | Does | Truth | P |
|---|---|---|---|
| `align32_floor`, `even_at_least_64` | ALVR's and the shim's size roundings | `PipelineModel.Align32Floor` / `EvenAtLeast64` | P0 |
| `fit_eye(reference_eye, reference_fov, declared)` | stream size that keeps the pixel density over a new declared box | `PipelineModel.FitEye` | P0 |
| `game_render_size(floor, ceiling, quality)` | game render size from the render-quality slider | `PipelineModel.GameRenderSize`, `ovrshim/render_size.h` | P0 |
| `ffr_band(cs, sh)` / `band_params(start, width)` / `band_degrees(...)` | where ALVR's full-density band sits | `fov_stream_geometry.py` (`--selftest` vs the shader) | P1 |
| `split_strips(height, mode, engines, preset, tuning, codec)` | NVENC strips and why | `PipelineModel.SplitStrips`, FOV_PIPELINE_OPTIM.md section 4 | P1 |
| `choose_eye(view, ratemap, bitrate, fps)` / `encoded_px` | stream size for a bitrate budget (needs the rate map) | `PipelineModel.ChooseEye`, `fov_stream_geometry.py` | P2 |

### C. Performance rules (from the logs; the thresholds are AirFrameXR's own)
| Function | Does | Truth | P |
|---|---|---|---|
| `parse_game_runs(log)` | `game run recorded` lines -> exe, headset, level, seconds, fps, slowest tenth, streamed fps, repeated typical/worst, run number | `tools/host/src/main.rs` format string | P0 |
| `parse_perf(log)` / `parse_samples(log)` / `parse_fg_config(log)` | the `frame generation perf / samples / config` lines | `main.rs` | P0 |
| `afxr_version(log)` | `AirFrameXR <component> X started` | `Common.cs` log line | P0 |
| `headset_name(raw)` | "Apple Headset" = Vision Pro, "Meta Quest..." | observed in logs | P0 |
| `clean_run(rep_typ_pct, host_rep_pct)` | clean = both under 5 % in the typical window | PERFORMANCE_KNOBS.md | P0 |
| `fg_candidate(run)` | rendered fps < 0.9 x panel Hz and repeated > 5 % with generation off -> propose generation on | `Advice.cs` | P0 |
| `fg_rate_choice(runs)` | fastest level whose last run was clean; host repeats >= 5 % -> next lower level | `Advice.cs`, PERFORMANCE_KNOBS.md | P0 |
| `link_check(gap_p95, share_over_15, samples_per_s, fps)` | Wi-Fi bursts: gap p95 > 15 ms, or > 5 % of gaps over 15 ms, or samples under 0.8 x fps | `Advice.cs` | P0 |
| `encode_headroom(encode_p95, period)` | hint at >= 50 % of the period, warning at >= 70 % | `Advice.cs` | P0 |
| `arrival_margin(spread_median_ms)` | clamp(round(0.85 x spread), 4, 10); propose only if it differs from 7 by 2 or more | `Advice.cs` | P0 |
| `keepalive_check(video_mhz, gpu_pct, pstate)` | video clock under 900 MHz with the GPU under 30 % busy -> keep-alive 90 | `Advice.cs`, PERFORMANCE_KNOBS.md | P1 |
| `classify_warning(line)` | known-benign vs real (the 1.3.10 INFO downgrades, tracking stalls in other games) | logging framework notes | P1 |
| `gpu_csv_summary(path)` | p-state, clocks, utilisation, VRAM from a debug run | INSTALL.md log table | P1 |

### D. Arithmetic helpers behind `calc` (enum `kind`)
`period_ms(hz)` | `fg_caps(hz)` (30/45/60 at 90 Hz, 33/50/67 at 100) | `cap_for_gpu_bound(sustained_fps)` (about 90 %) | `bits_per_pixel(mbps, fps, w, h)` | `mpx(w, h)` | `tan_deg` conversions | `align32` | `ratio_pct(a, b)` | `mbps_to_mb_per_s`. **P0**; each a one-line function with a vector, grouped so the model sees one tool.

### E. Settings and files (the only code that writes)
| Function | Does | Truth | P |
|---|---|---|---|
| `facts_lookup(name)` | key or UI label -> record (default, values, restart rule, UI path, status, source) | `kb/facts/*.yaml` (section 4 of the plan) | P0 |
| `effective_settings()` | `airframexr.json` with defaults filled in (a key at default is absent from the file); `session.base.json` extracts (resolution, bitrate, foveation) read-only | EXPERIMENTAL_SWITCHES.md, golden-master note | P0 |
| `validate_change(key, value)` | exists, user-safe (not removed, not lab-only, not `session.json`), type and range, same nesting as the file | facts | P0 |
| `diff_preview(key, value)` | the exact text change | | P0 |
| `backup_file(path)` / `restore(change_id)` | `<name>.bak-<yyyymmdd-hhmm>` and restore | | P0 |
| `write_json_atomic(path, obj)` | temp file + rename, re-parse check, keep formatting | | P0 |
| `journal_append(entry)` / `journal_tail(n)` | `notes\changes.md` | | P0 |
| `restart_rule(key)` | live / streamer restart / next game start, from the facts | | P0 |
| `streamer_running()` | whether `streamer.exe` is up (a restart rule needs it) | `StreamerProc.Running` | P1 |

## 4. What stays prose (FAQ or brief), not code
Taste ("some games look better raw"), game-specific advice, router and Wi-Fi placement (README "Recommended network setup"), anything that needs the user's eyes. A tool exists only when the answer is a rule or a number.

## 5. First slice (P0) and how it is proven
1. Vendor `fov_stream_geometry.py` + `lib.fov_vars`; port `FovValidator`, `FitEye`, `GameRenderSize`, the `Advice.cs` rules, the log parsers.
2. Golden vectors: run the C# originals through the harness on the builder (when it is back) or, until then, through the Python references that already self-test, plus the worked numbers in the docs (AVP_FOV tables, the 0.29 vs 0.47 bits-per-pixel example, the generation caps) as hand-checkable cases.
3. Real-log fixtures: the 2026-11-15 sessions (sanitised) as `parse_*` and `diagnose` cases.
4. The MCP server (stdio, stdlib) exposing the 8 tools; **spike first**: confirm opencode 2.3's MCP discovery, the `<server>_<tool>` permission names, and whether a 12B fills the typed schemas reliably (tool-call accuracy is the first eval family).
5. Fallback if MCP misbehaves: the same functions as allow-listed `python tools\afxr.py <tool> --json ...` shell commands.

## 6. Risks
Tool-count creep (cap the surface at 8-10; grow the library, not the menu); a ported rule drifting from the C# (golden vectors, rerun on each AirFrameXR version, by hand at first); a curated rule that is only my reading of a doc (`symptom_to_edge`: mark it, get the author's confirmation); the model ignoring `conclusion` and re-deriving (the eval counts it); results too verbose for the context (cap `facts`, keep `conclusion` short).
