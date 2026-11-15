# Knowledge-base harness: plan (draft, 2026-11-15)

Goal: the files the agent reads (`agent/AGENTS.md`, `agent/playbook/*.md`, `agent/docs-index.md`, and what we add) are **generated from AirFrameXR's
own sources, checked against them, and scored by a fixed set of scenarios**, so that when AirFrameXR changes the knowledge base changes with it, and
when we change the knowledge base we can tell whether the agent got better or worse. Nothing below is built yet.

## 1. What drifts, and how we notice

| Drift | Example | Detector (no GPU needed unless noted) |
|---|---|---|
| A key is added, removed, renamed, its default or restart rule changes | `frame_gen_hold_age` removed in 1.0.1 | **fact check**: every key in the KB exists in AirFrameXR's config code and in `EXPERIMENTAL_SWITCHES.md` with the same default and "takes effect" |
| A log line the playbook greps changes | `game run recorded` reworded | **log-format check**: every grep pattern in the KB is a substring of a format string in `tools/host/src/*.rs`; sample lines parsed by the playbook's regexes |
| The UI is renamed | "Advanced video and performance settings" | **UI-label check**: labels the KB quotes exist in `tools/gui/*.cs` strings |
| The docs move on | a new section, a measurement revised | **source hash check**: each fact records `file#section` and the section's hash at build time; a changed hash marks the fact *stale* |
| The model changes | Gemma 4 -> something better | **eval matrix** (needs GPU): same scenarios, new model |
| The advice stops working in the field | a lever that no longer helps | **journal results** (`notes/changes.md`), see section 6 |

The user's installed version is already in their log (`AirFrameXR <component> 1.3.10 started`, written at every start, `tools/gui/Common.cs`): the KB
declares the AirFrameXR versions it was built for and the assistant says so when the installed one is outside the range. No engine change needed.

## 2. Pipeline (all in this repo, `kb/`)

```
AirFrameXR @ pinned sha ──ingest──> kb/facts/*.yaml ──render──> agent/*.md (+ token report)
        docs, config code,             (one record per fact,      generated header: source sha, KB version
        log formats, UI strings         each with a source)
                                          ^
                          kb/curated/*.yaml  (expert rules a script cannot extract:
                          decision rules, the symptom -> lever tree, "never propose")
```
1. **Ingest** (deterministic, tested): parse the tables of `EXPERIMENTAL_SWITCHES.md` / `PERFORMANCE_KNOBS.md` into knob records; cross-check against the
   code (config keys in the Rust/C# readers, log format strings, UI labels). A disagreement is an error, not a guess. Output `kb/facts/knobs.yaml`,
   `logs.yaml` (pattern, fields, meaning), `ui.yaml` (label -> key -> restart rule, since users speak in UI words), `removed.yaml`.
2. **Curate** (hand-written, small): the decision rules and the symptom router, each citing the facts it relies on. A model (Claude, at development time only)
   may draft a rule; it enters only with source pointers and a human review. This is where the project's judgement lives ("5 % repeated = clean", "debug logging costs 4.6 ms").
3. **Render** the tiers (the context is 81,920 tokens, so most of the KB is loaded, not searched):
   - Tier 0, always loaded, about 8k tokens: brief, symptom router, knob cheat sheet, glossary (Apple Headset = Vision Pro, ...).
   - Tier 1, always loaded, about 25-35k tokens: one digest per topic (frame generation, field of view, arrival/pacing, encode/network, audio, install/troubleshooting), each with the decision rules and the "never" list.
   - Tier 2, searched on demand: `docs-cache/` (full docs) and the Q&A index.
   A token budget (hard cap 45k for tiers 0+1) is checked at render time so a session always has 35k tokens left for logs and conversation.
4. **Verify**: fact check + log-format check + UI-label check + stale-fact list; fail the build on any error.
5. **Release**: a KB artifact `kb-<afxr-version>.zip` (rendered files + facts + report). `update-docs` fetches the KB that matches the installed AirFrameXR
   instead of `main` (this removes today's caveat that the docs describe `main`).

## 3. Evaluation (needs the GPU PC; the scorer runs anywhere)

Scenario = a fixture AirFrameXR folder (config + log excerpt, sanitised) + a user prompt + expectations. Run through the **production path**:
`make-config.ps1` -> `opencode run` with the fixture as the working directory (same permissions, same instruction files, same model server), transcript captured.

| Family | Expectation (mechanical checks first, rubric second) | Seed |
|---|---|---|
| Grounding | reads the evidence before advising; cites file and date; proposes a key that exists, with the correct restart rule | `eval/agent_eval.py` T1, T4 |
| Decision | the right lever for a given log (rendered 77 fps at 100 Hz, repeated 7.2 % -> frame generation; clean run -> change nothing) | the real SWGR session |
| Refusal | invented key, removed knob, registry, `session.json`, "just do it" | T2, T3 |
| No evidence | asks for a recording instead of guessing | new |
| Version skew | log says 1.2.x, KB says 1.3.x -> says so | new |
| Multi-turn | proposal -> user approves -> edit with backup + journal entry -> verification read | new |
| Long context | fact retrieval at 80k with the real KB loaded | `eval/needle.py` |

- **Synthetic variants**: a generator mutates fixture logs (fps, repeated %, late releases, missing lines) so each decision rule has several cases with a known right answer; this is the unit-test layer.
- **Real cases**: sanitised excerpts of real logs (no names, paths, addresses; the repo is public).
- **Scoring**: N = 5 samples per scenario (temperature 0.3), pass rate with a confidence interval; paired comparison between two KB versions on the same seeds. Rubric items (is the explanation correct and non-misleading) are judged by Claude offline at development time, cached, spot-checked by a human; the shipped agent never calls it.
- **Gates**: a KB change merges only if the regression set does not get worse (paired test) and every field bug gets a scenario first. A **hold-out** third of the scenarios is never used while tuning, to catch overfitting.
- **Output**: `eval/results/<kb-version>_<model>.jsonl` + a one-page report (pass rate per family, new failures, token use, tool-call count, wall time).

## 4. What we will tune with it (each an A/B on the same scenarios)
Tier-1 size (0 / 15k / 30k tokens), ordering (important first and last), examples in the digests (worked proposals), the symptom router's form (table vs
prose), fact-style rules ("never X") vs positive rules, English only vs the user's language, brief length. Keep whatever raises the pass rate; delete the rest (lean).

## 5. Milestones

| | Content | Needs | Done when |
|---|---|---|---|
| M0 | `kb/` skeleton, knob + removed-key extractor, fact check against the AirFrameXR checkout, `kb check` CLI, GitHub Action on a schedule that opens an issue on drift | Linux only | the check passes on today's AirFrameXR and fails when I delete a key from the docs (negative test) |
| M1 | log-format registry, UI-label map, token-budget report, renderer producing today's `knobs.md`/`diagnose.md` byte-for-byte equivalent in content | Linux only | generated files replace the hand-written ones, no behaviour change in the eval |
| M2 | runner (`eval/run.ps1`) + scorer + 30 scenarios, baseline for Gemma 4 12B at the current KB | the 5090 (server stopped for other use) | a baseline pass rate with an interval, reproducible twice within the interval |
| M3 | tier-1 digests, the A/B experiments of section 4 | the 5090 | a KB version that beats the baseline on the regression set and holds on the hold-out |
| M4 | KB-by-version release + `update-docs` change, release hook (a new AirFrameXR tag triggers rebuild + eval + PR) | GitHub only | a simulated AirFrameXR release produces a reviewed KB PR end to end |
| M5 | field loop: the journal's kept/undone results, an optional user-attached export, new scenarios from real issues; model matrix when a better 16 GB model appears | users | at least one scenario born from a field report |

## 6. Principles (from the project's own rules)
- A fact lives in one place: the KB points at AirFrameXR's docs and code, it never becomes a second copy of the numbers.
- Measure before changing the KB; a rule that cannot be tested by a scenario is a candidate for deletion.
- Say what was tested: every KB release carries its eval report; untested advice is marked as such in the text the agent reads.
- No new settings or modes without a measurement; manual over automatic.

## 7. Decisions needed
1. **Where the KB lives**: this repo (recommended: AirFrameXR stays free of assistant files) or `docs/` in AirFrameXR. Optional later: AirFrameXR emits a `docs/knobs.json` so scraping tables becomes reading data (docs are allowed without asking; it would be a separate change there).
2. **The judge**: Claude offline at development time (recommended, small cost, never shipped) or mechanical checks only (cheaper, weaker on explanations).
3. **Real logs as fixtures**: sanitised excerpts from your own sessions (better) or synthetic only (safer).
4. **Cadence**: weekly drift check plus on every AirFrameXR tag, or only on tags.

## 8. Risks
Scenario noise with a small model (hence N = 5 and paired seeds); overfitting to our scenarios (hold-out); a judge that flatters (rubric + spot checks); the KB growing past what the model can use (token cap, long-context scenario in every run); doc scraping breaking on a table format change (the ingest tests fail loudly, M0); the 12B model itself being the ceiling (the matrix tells us when to move).
