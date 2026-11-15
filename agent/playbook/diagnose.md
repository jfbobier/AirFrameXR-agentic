# Diagnose: read the evidence (PowerShell, from the AirFrameXR folder shown in state/machine.md)

All logs are under `<AirFrameXR>\logs`. `AirFrameXR.log` always exists (appended, rotates at 10 MB). Never print a whole log.

## The three lines that matter (general log, always on)
```powershell
$log = '<AirFrameXR>\logs\AirFrameXR.log'
Get-Content $log -Tail 3000 | Select-String 'game run recorded'            # one per finished game
Get-Content $log -Tail 3000 | Select-String 'frame generation perf' | Select-Object -Last 6     # every 10 s while a game runs
Get-Content $log -Tail 3000 | Select-String 'frame generation samples' | Select-Object -Last 3
Get-Content $log -Tail 3000 | Select-String -Pattern ' WARN | ERROR ' | Select-Object -Last 15
```
| Line | Read | Means |
|---|---|---|
| `game run recorded: <exe> on <headset> at <level>, N s, X fps rendered (slowest tenth Y), Z streamed, headset repeated A % typical / B % worst` | rendered vs streamed fps; A and B | A = share of display refreshes where the headset had no new frame. **Under 5 % typical = a clean run** (the project's own rule). Over 5 % = the user probably saw judder |
| `frame generation perf: app X fps (envelope E ms, L/R releases late), stream Y fps, game period ..., lag ... ms` | X against the display rate (90 or 100 Hz); L/R | X well under the display rate = frame generation territory. Most releases late with X steady = the game is GPU-bound: a cap near 90 % of X may help |
| `frame generation samples: ... boundaries skipped ... (S %), ... regime switches` | S | skipped tracking samples; typical 0.2-1.9 %. A large S with Wi-Fi trouble points at the network, not at a knob |
| `frame generation config (...)` | which rate/cap is in force | confirms what the host actually took (read back, not what the user clicked) |
| WARN / ERROR lines | exact text | quote them; search the docs for the words before guessing |

## Deeper (debug logging ON, one folder per streamer run: `logs\debug\<yyyymmdd-hhmmss>\`)
- `host_events.jsonl`: `encoder_stats` every 2 s (encode p50/p95 in ms, ALVR client statistics: network and decode latency), `phase_lock` events (`spread_ms`, `est_ms`) for the arrival margin.
- `gpu.csv` (1 Hz): GPU / encoder / decoder utilisation, clocks, power, P-state, VRAM. A GPU at P8 or a low video clock while streaming = downclocking: that is what `gpu_keepalive` is for.
- `client_graph.csv`: the headset's per-frame latency.
- Debug logging slows the stream itself (about 4.6 ms per frame, known bug): use it for one diagnosing session, then ask the user to turn it off.

```powershell
$d = Get-ChildItem '<AirFrameXR>\logs\debug' -Directory | Sort-Object Name | Select-Object -Last 1
Get-Content "$($d.FullName)\gpu.csv" -TotalCount 2          # header + first row: learn the column names first
Get-Content "$($d.FullName)\host_events.jsonl" -Tail 400 | Select-String 'encoder_stats' | Select-Object -Last 3
```

## Built-in tools to ask the user to run (they stop the streamer)
- Launcher card **Diagnostics (experimental)** (= `bin\configure.exe --diagnose`): tests encoder, network and a short scene on the settings as they are; shows suggestions with Apply buttons (arrival margin, GPU keep-alive).
- **Performance** window: the games played, per-session numbers, log export.
- **Black Box** (separate install in the bundle's `blackbox\` folder): records a play session and reports where the time goes (game, encoder, network, GPU). Use it when the log lines above do not explain a stutter.

## From symptom to first look
| The user says | Look at first | Likely lever (see knobs.md) |
|---|---|---|
| judder / "not smooth" in one game | `game run recorded` for that exe: rendered fps vs display rate, headset repeated % | frame generation on; rate per `FRAME_GENERATION.md`; cap |
| smooth in some games, not others | compare the `game run recorded` lines per exe | per-game rate; the game's own settings (GPU-bound) |
| doubled / ghosting image with frame generation | `frame_gen_synthesis` value in `airframexr.json` | edge (default) vs classic; or frame generation off for that game |
| a mod/VR-injector game runs at half the expected speed | `frame generation perf`, game fps | `drop_duplicate_frames` (compatibility mode), see EXPERIMENTAL_SWITCHES.md |
| black picture after changing field of view | the version in the launcher; `AirFrameXR.log` around the change | versions before 1.3.9 had a pinned-shift black picture bug: update first |
| picture soft / blurry | resolution and bitrate in the Setup tabs; FoV restriction on? | bitrate/resolution via the UI; FoV docs; not a json guess |
| frames late but GPU not busy, encode slow, laptop | `gpu.csv` P-state and video clock | `gpu_keepalive` |
| connection drops, packet loss | `AirFrameXR.log` warnings; `Find headset...`; README "Recommended network setup" | network, not a knob |
