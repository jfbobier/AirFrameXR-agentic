# Deterministic helpers for a small model: first catalog (draft, 2026-11-15)

Principle: **the model decides what to ask and how to say it; code decides every number, every rule and every write.** A 12B model can pick a
well-named tool and fill typed parameters; it cannot be trusted to do tangent arithmetic, apply a threshold from memory or write valid JSON.
Nothing below exists yet. Every item says where its truth lives, so it is ported, not invented.

**Delivery (decided 2026-11-15): no MCP server.** The tools are one stdlib-Python CLI behind a launcher, `agentic\afxr.bat <tool> key=value ...`, and the model learns them from `agent\TOOLS.md`, which is loaded with the rest of the brief. opencode's Windows shell is cmd.exe, so a `.bat` runs as is. Leaner (no server, no protocol, no extra process), debuggable (the user can paste any command the agent ran and get the same output), and the eval harness calls the same CLI directly.

## 1. Conventions

- **Command grammar for a small model.** `afxr.bat <tool> [action] key=value ...`; plain `key=value` pairs, never JSON (quoting JSON in cmd.exe is a trap); `--key value` and `--key=value` also accepted; units inline (`amount=2deg`, `hz=100`); case-insensitive; unambiguous abbreviations of tool names and keys accepted. A wrong command exits non-zero with the usage line and a "did you mean" and writes nothing. `afxr.bat help` and `afxr.bat help <tool>` print the same text as `TOOLS.md`.
- **Output.** Default is a short plain-text block (`CONCLUSION`, `FACTS`, `RECOMMEND`, `EVIDENCE`, `CAVEATS`, `NEXT`), which a small model reads better than JSON; `json=1` prints the structured form for the harness.
- **One source.** `kb/tools/catalog.yaml` (name, description, parameters, example call, example result, source of truth, permission) renders `agent/TOOLS.md`, the CLI's argument parser and `help`, and the tool-call eval cases, so the three cannot drift. A check runs every documented example and compares the result.
- **Two layers.** A small *exposed surface* (12 intent-level tools, section 2: what the model reads about in `TOOLS.md` and chooses between; several take an `action` word instead of becoming separate tools) over a larger *internal library* (section 3: pure functions, unit-tested, reused by several tools). Few tools = fewer wrong choices; the library can grow freely. Tool-selection accuracy is a measured eval family: if it is low, tools are merged behind an `action` enum, not multiplied.
- **Intent-level, not function-level.** `fov_plan` does the whole job (parse the symptom, compute, validate, report the pixel cost). The model never chains `tan`, `atan` and a validator.
- **Results carry the wording.** Every result is `{ok, conclusion, facts, recommend[], evidence[], caveats[], next[]}`: `conclusion` is one plain sentence the model can read out; `recommend` entries name the exact control or `propose_change` arguments; `evidence` points at file and line; `caveats` carry the "untested / judgement" flags from the docs; `next` names the tool to call after.
- **Errors never raise.** `{ok:false, why, ask_user}`: what was wrong in words, and the one question to put to the user.
- **Units in names** (`_deg`, `_tan`, `_ms`, `_mbps`, `_px`); numbers rounded for speech (tangents 2 decimals, angles 1, as the UI shows them), exact values kept in `facts`.
- **Deterministic.** Same inputs, same output; no clock except an explicit `now`; no network.
- **Read-only unless the name says otherwise.** Only `apply_change` and `undo_change` write. They are `ask` in the shell permissions, and the code adds its own guard: `apply` accepts only a proposal id that `propose_change` created and that has not expired, so a loosened allow-list cannot become a free-form write. The others are allowed without prompting by command pattern (`*afxr.bat diagnose*` and so on; a command worded differently just asks the user).
- **Golden vectors or it does not ship.** Each function has vectors generated from AirFrameXR's own implementation (the C# in `tools/gui/`, the Rust host, or `harness/fov_stream_geometry.py`, which already self-tests against the shader's equations). A function with no vector is a draft. The suite runs on Linux.
- **Reuse before writing.** `harness/fov_stream_geometry.py` and `harness/lib.py` (`fov_vars`) are vendored with provenance (same author, MIT); `Advice.cs` thresholds and `FovValidator` are ported line by line.
- **Scratch.** The model has a temp folder, `agentic\scratch\` (the only place edits are allowed without asking; pruned at start after 7 days). Tools accept `out=scratch\name.txt` to write a long result there instead of into the conversation, and the model can read it back in ranges: a way to keep the context small. Proposals and backups live in `state\`, never in scratch.
- Stdlib (plus numpy, already in the runtime) so it runs on the Python that ships with vLLM; no .exe.

## 2. The exposed surface (12 tools) and the text the model reads (`TOOLS.md`)

Descriptions are what `TOOLS.md` tells the model: imperative, say *when* to call, say what it does not do. "Params" are the `key=value` pairs; the call looks like `agentic\afxr.bat fov_plan symptom=black_band edge=lower amount=a_little`. Permissions are shell-command patterns.

| # | Tool | Description shown to the model | Params (typed) | Writes | Permission |
|---|---|---|---|---|---|
| 1 | `afxr_status` | "Call first in every session. Returns the installed AirFrameXR version, the headset and display rate seen in the logs, which config files exist, and the last game runs. Use it instead of reading logs by hand." | none | no | allow |
| 2 | `diagnose` | "Call when the user describes judder, stutter, lag, repeated frames, a slow encoder or Wi-Fi trouble and there is no Black Box recording. Reads the live logs and applies AirFrameXR's own rules; returns ranked findings with the numbers, the log lines, and which setting or button to use. Does not change anything." | `game` (exe, optional), `last_n_runs` (1-10, default 3) | no | allow |
| 3 | `game_stats` | "Call to read what AirFrameXR recorded for a game: per headset and per frame-generation level, the rendered and streamed fps, how often the headset repeated frames, network and encode times, the stream size. Use `action=levels` to compare frame-generation levels, `sessions` for single runs, `trend` for change over time. It says which level was clean and how far to trust the numbers (run length). Never judge smoothness from streamed vs rendered fps; use the repeat percentages." | `game` (exe or name), `headset` (optional), `action` (levels\|sessions\|trend) | no | allow |
| 4 | `blackbox` | "Call when the user has a Black Box recording or asks where the time goes (game, encoder, network, GPU, headset). `action=list` finds recordings; `read` returns the verdict and each finding in plain words with its severity; `interpret` maps the findings to AirFrameXR levers and says what ONE thing to change and record next; `compare` sets two recordings side by side." | `action` (list\|read\|interpret\|compare), `session` (folder name), `other` (for compare) | no | allow |
| 5 | `explain_setting` | "Call when the user names a setting or a button, or when you want to propose one. Returns what it does, its default, its current value on this PC, where in the UI it is, when a change takes effect (live / streamer restart / next game start), and whether it may be changed (user-safe / UI only / removed / lab only)." | `name` (key or UI label) | no | allow |
| 6 | `fov_check` | "Call when the user gives or asks about field-of-view numbers (four edges, tangents or degrees). Validates them, converts between tangents and degrees, and says what share of the headset's picture and of the game's pixels they keep." | `outer`, `inner`, `upper`, `lower` (numbers), `unit` ("tan"\|"deg"), `profile` (optional name) | no | allow |
| 7 | `fov_plan` | "Call to compute new field-of-view edges from a symptom or a goal: a black band or a visible box at one edge, a cut corner, 'more margin', 'fewer pixels' (target saving), or switching to the shipped or measured profile. Returns the four new values, their cost in pixels, and the exact fields to type in the launcher's FOV card. Does not change anything." | `symptom` (enum), `edge` (outer\|inner\|upper\|lower, when relevant), `amount` (a_little\|some\|a_lot, or `degrees`), `goal_saving_pct`, `current` (4 numbers, default: read from this PC) | no | allow |
| 8 | `resolution_plan` | "Call for any question about resolution, sharpness, bitrate, or whether the PC can afford a setting: stream size per eye, encoded pixels, bits per pixel, pixels per tangent (sharpness), the game's render size at a render-quality value, NVENC strips, and the time budget of each stage at the refresh rate. Give the settings you are considering; it returns what the pipeline will do before any game runs, and which stage becomes the limit. Does not change anything." | `refresh_hz`, `eye` (w,h), `bitrate_mbps`, `foveated` (bool), `fov` (4 numbers, optional), `render_quality` (0-1), `question` (enum: sharpness\|budget\|fit\|compare), `candidate` (a second setting set, for compare) | no | allow |
| 9 | `calc` | "Call for any arithmetic you would otherwise do in your head: display period, generation caps at a refresh rate, a cap for a GPU-bound game, Mbps conversions, pixel counts, sizes aligned to 32." | `kind` (enum, section 3.D; more kinds: `frame_period`, `stage_share`, `density`, `bpp`), plus the parameters of that kind | no | allow |
| 10 | `propose_change` | "Call before any edit. Checks that the key exists and is user-safe, that the value is valid, shows the exact diff, the restart rule, how to verify and how to undo. Returns a `proposal_id`. Does not write." | `key`, `value`, `reason` (one sentence, with the measurement) | no | allow |
| 11 | `apply_change` | "Call only after the user approved a proposal. Backs the file up, writes it, checks it parses, appends the journal." | `proposal_id` | **yes** | **ask** |
| 12 | `undo_change` | "Restores the backup of a change and journals it." | `change_id` | **yes** | **ask** |

`afxr_status`, `explain_setting`, `diagnose`, `game_stats` and `blackbox` replace the shell reads that were failing on Windows (cmd.exe) and the log greps a small model was
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

### F. Performance and resolution (behind `resolution_plan`, `calc`, `diagnose`)
| Function | Does | Truth | P |
|---|---|---|---|
| `frame_period_ms(hz)`, `stage_share(stage_ms, hz)` | the period and what share of it a stage uses | Advice.cs (`period = 1000 / fps`) | P0 |
| `stage_budget(encode_p95, network_p95, decode_p95, compose_ms, latency_ms, hz)` | which stage exceeds its share of the period; the latency split (encode / network / decode / queues) | Advice.cs, `net` block of the game records, Black Box T06 | P0 |
| `density_px_per_tan(eye_px, span_tan)` | pixels per tangent unit over the declared box: the real "sharpness" number (stock FoV 0.6 is sharper because the stream covers less angle at the same size) | FOV_PIPELINE_OPTIM.md section 2, the 1.3.6 sharpness analysis | P0 |
| `stream_eye_options(declared, reference_eye, reference_fov, bitrate, fps)` | the stream sizes AirFrameXR would pick for each mode (bitrate-sized, user-typed, fit to the declared box, keep panel size), each with Mpx, density and bits per pixel | `fov_stream_geometry.py model()`, `PipelineModel.Compute`, `stream_fit_window`, `stream_keep_panel_size` | P0 |
| `bits_per_pixel(mbps, fps, w, h)` and `bitrate_for_bpp(bpp, w, h, fps)` | the quality budget of a frame; compare with the docs' reference points (0.47 and 0.29 bits per pixel in the keep-panel-size analysis) | EXPERIMENTAL_SWITCHES.md, `ChooseEye` | P0 |
| `encoded_size(eye, foveated, cs, sh, er)` | the foveated frame ALVR will encode (aligned to 32) | `fov_vars` (`harness/lib.py`), `PipelineModel.FfrVars` | P0 |
| `render_size(floor, ceiling, quality)` and `render_floor_ceiling(...)` | the game's recommended render size per eye and the saving versus unrestricted | `PipelineModel.GameRenderSize`, `RenderPlan.Make` | P0 |
| `nvenc_plan(height, engines, preset, tuning, codec, split_mode)` | strips and why; engine count from `config\airframexr_gpu.json` | `PipelineModel.SplitStrips`, FOV_PIPELINE_OPTIM.md section 4 | P1 |
| `gpu_bound_check(app_fps, releases_late, releases, gpu_util)` | GPU-bound vs CPU-bound: most releases late with a steady fps = GPU-bound -> candidates are the fps cap, FoV restriction, render quality, the game's own settings | PERFORMANCE_KNOBS.md, EXPERIMENTAL_SWITCHES.md (`frame_gen_cap_fps`) | P0 |
| `fg_capacity(app_fps, hz)` | which generation levels the game can hold (cap >= sustained fps needed) | PERFORMANCE_KNOBS.md (caps 30/45/60 at 90 Hz, 33/50/67 at 100) | P0 |
| `cost_of_setting(change)` | what a candidate setting does to pixels, encode load and bits per pixel, before running (the pipeline model the UI is meant to carry) | FOV_PIPELINE_OPTIM.md section 2b | P1 |
| `compare_settings(a, b)` | the same outputs for two candidates, side by side | | P1 |

### G. Game statistics (behind `game_stats`; record = `config\games\<exe>.json`, per-run logs = `logs\games\<exe>\<time>.log`)
Record shape (read from a real file): `levels[headset][level]` = `{display_hz, rendered_fps, rendered_fps_low, streamed_fps, headset_repeated_typ, headset_repeated_p90, host_repeats_typ, skipped, runs, seconds, windows, updated}` (fractions, not percentages) and `sessions[]` = `{headset, level, display_hz, gpu{name, driver}, headset_repeated_*, host_repeats_typ, net{bitrate_mbps, throughput_mbps, encode_ms, network_ms, decode_ms, latency_ms, latency_p95_ms, packets_lost, displayed_fps}, pipeline{compose_ms, encoded[w,h], foveated, foveation{...}, declared_fov[8], fov_scale[4], ceiling}, log}`.
| Function | Does | Truth | P |
|---|---|---|---|
| `load_game_record(exe)` / `list_games()` | read and normalise (fractions -> percent, headset names) | the files, `Advice.LogFacts` | P0 |
| `level_table(record, headset)` | one row per frame-generation level: fps, repeats, clean or not, runs, seconds | PERFORMANCE_KNOBS.md ("clean = both repeat counts under 5 % in the typical window") | P0 |
| `recommended_level(record, headset)` | the fastest clean level (what the "Recommended" tick picks) | FRAME_GENERATION.md, `Advice.cs` | P0 |
| `trust(run)` | how far to trust a number: runs, seconds, windows (a 38 s run is not typical) | the `runs` / `seconds` / `windows` fields; **the short-run limit is a judgement to confirm** | P0 |
| `fps_reading(rendered, rendered_low, streamed, hz, level)` | explains the three fps numbers in words and refuses the common misreading (see "Rules to confirm", rule 2) | `game run recorded` format, Black Box T05 caveat | P0 |
| `net_reading(net, hz)` | latency, p95, loss, throughput vs bitrate, encode / network / decode against the period | `net` block, Advice.cs thresholds | P0 |
| `pipeline_reading(pipeline)` | stream and encoded size, whether foveated, the share of the declared field the game was told (from `fov_scale`), compose time against the period | `pipeline` block, `fov_scale_from` | P1 |
| `compare_runs(a, b)` / `trend(record, headset, level)` | descriptive differences between runs (no rule: the model is told what moved and by how much) | | P1 |
| `game_log_events(path)` | stalls, warnings, level changes in a per-run log; known-benign vs real | logging framework (1.3.10 downgrades) | P1 |

### H. Black Box results (behind `blackbox`; a recording is a folder with `report.md`, `analysis.json`, the CSVs and `capabilities.csv`)
Report shape (read from a real recording, `private/logs/5090-2026-10-30-blackbox-acbf`): a headline `**STATUS**: verdict`, findings `T01..T11` each `OK | WATCH | PROBLEM | INSUFFICIENT DATA` with an evidence line and a "Suggested test", a stage table (gap, queue age, encode, hold: p50/p95/p99/max), the worst 10 s windows, the worst late frames with the stage that made them late. The attribution rule is stated in the report (each late gap goes to the stage whose time exceeded its own median by the most); the caveats are T11.
| Function | Does | Truth | P |
|---|---|---|---|
| `bb_list(root)` | recordings (folder, scene, date, status, duration) | `logs\performance\<time>_<scene>\`, `PerfAnalyze.cs` | P0 |
| `bb_parse_report(path)` | `report.md` -> `{status, verdict, findings[{id, severity, title, evidence_text, numbers, suggested_test}], stages, worst_windows, worst_frames}`; fails loudly on a format it does not know | the report generator (`perfcore`), `harness/perfreport_check.py` fixtures | P0 |
| `bb_attribution(findings)` | the T03 split in words: upstream (game or runtime) vs encoder queue vs sender; the dominant cause and its share | report T03 | P0 |
| `bb_levers(findings, settings)` | the curated map from finding to AirFrameXR lever: late gaps upstream -> cap the game's fps / lower its settings / frame generation / FoV restriction; encoder queue or encode over budget -> preset, resolution, foveation; headset side slow tail -> bitrate, Wi-Fi band, headset load; limiter active -> power or cooling; sender -> network. Each with the restart rule | report "Suggested test" texts, PERFORMANCE_KNOBS.md | P0 |
| `bb_next_step(findings, settings)` | exactly ONE change to try and what to record after it ("change one thing and capture again") | report T02 suggested test, the project's one-change rule | P0 |
| `bb_caveats(findings)` | the T11 rules attached to every conclusion (streamed fps is not game fps; the NIC figure is all adapters; GPU util is a window average; a limiter flag is not a cause; blank is not 0) | report T11 | P0 |
| `bb_compare(a, b)` | per finding and per stage: before, after, delta, whether it exceeds run-to-run noise (same scene and duration, warm-up excluded) | the stage table; noise bound to be measured with two identical recordings | P1 |
| `bb_limiter_decode(throttle_reasons)` | NVML clock-event bitmask -> names; **an unnamed bit (the real recording shows 0x400, and the report printed `Limiter: .`) is reported as "unnamed limiter bit", never as nothing** | NVML header (`nvml.h` clock event reasons) | P1 |
| `bb_engines(rows)` | per-process engine shares in words; the rows sum engine instances, so divide by the instance count before saying "full" | report T09 note, `hardware_engines.csv` | P1 |
| `bb_capabilities(path)` | which counters were unavailable and why (blank, never 0) | `capabilities.csv` | P1 |
| `bb_frames_stats(csv)` | recompute gap / queue / encode percentiles from `host_frames.csv` to double-check a report | harness `frames.py` | P2 |

### I. Curated rules (not extracted: each is a place where a doc or a log was read and a person should say "yes, that is the rule")
**Status 2026-11-15: the author reviewed these and judged them sound as proposed** (the step size, the 60 s short-run limit and the other values below stand as defaults until a measurement says otherwise). Items 4, 5, 6 and 7 still need their concrete value or meaning filled in during execution: the builder can answer 6 (limiter bit 0x400) and the 80 % vs 50/70 % reconciliation from the code.

1. **A black band or box at an edge means that edge's value is too small: raise it** (`symptom_to_edge`): from the validator's message and the "Check it" paragraph of AVP_FOV.md. Step size default 2 degrees: a default, not a measurement.
2. **Smoothness is judged by `headset repeated %` (and host repeats), never by streamed vs rendered fps.** Evidence: the real SWGR record (rendered 98.8, streamed 74.0, level off, repeated 1.0 %) was read as a streaming bottleneck by every local model tested. I do not know why streamed is below rendered there; the interpreter says "look at the repeat percentages" and flags the gap as a question, not a finding.
3. **Short runs**: a run under N seconds is not typical (the 38 s SWGR run produced 7.2 % / 59.5 %). N is a guess (60 s?).
4. **Encoder budget**: the Black Box says "encode over 80 % of the period" is a PROBLEM, `Advice.cs` says hint at 50 %, warning at 70 % of the p95. Two sources, two thresholds: which one does the assistant quote, and when?
5. **Bits-per-pixel references**: the docs cite 0.47 and 0.29 with "check before keeping". Is there a floor below which the assistant should warn?
6. **Limiter bit 0x400**: what it is (the report prints it blank). Needed for `bb_limiter_decode`.
7. **GPU-bound reading**: "most releases late with a steady app fps = GPU-bound" is from the docs' wording; confirm the cut-off (what share of releases is "most").

## 4. What stays prose (FAQ or brief), not code
Taste ("some games look better raw"), game-specific advice, router and Wi-Fi placement (README "Recommended network setup"), anything that needs the user's eyes. A tool exists only when the answer is a rule or a number.

## 5. First slice (P0) and how it is proven
1. Vendor `fov_stream_geometry.py` + `lib.fov_vars`; port `FovValidator`, `FitEye`, `GameRenderSize`, the `Advice.cs` rules, the log parsers.
2. Golden vectors: run the C# originals through the harness on the builder (when it is back) or, until then, through the Python references that already self-test, plus the worked numbers in the docs (AVP_FOV tables, the 0.29 vs 0.47 bits-per-pixel example, the generation caps) as hand-checkable cases.
3. Real-log fixtures: the 2026-11-15 sessions (sanitised) as `parse_*` and `diagnose` cases.
4. The CLI (`tools/afxr.py` + `afxr.bat`, stdlib) exposing the 12 tools, and the generated `agent/TOOLS.md`. **Spike first**: (a) does a 12B emit correct commands from the `TOOLS.md` examples (tool-call accuracy over the FAQ prompts, measured by parsing the command strings in transcripts); (b) do opencode 2.3's shell permission patterns match the commands as the model writes them (`afxr.bat`, `agentic\\afxr.bat`, `.\\agentic\\afxr.bat`, `agentic/afxr.bat`), and which variants fall back to "ask"; (c) start-up cost of one call on the user's PC (lazy-import numpy).
5. If the model's command wording proves unreliable: tighten the grammar (fewer keys, defaults), add the usage-and-did-you-mean retry, and only then consider typed tooling. No MCP unless the spike shows the shell route cannot work.

## 6. Risks
Tool-count creep (cap the surface at 8-10; grow the library, not the menu); the model mistyping a command (mitigated by the forgiving grammar, the usage retry and a measured accuracy gate); a ported rule drifting from the C# (golden vectors, rerun on each AirFrameXR version, by hand at first); a curated rule that is only my reading of a doc (`symptom_to_edge`: mark it, get the author's confirmation); the model ignoring `conclusion` and re-deriving (the eval counts it); results too verbose for the context (cap `facts`, keep `conclusion` short).
