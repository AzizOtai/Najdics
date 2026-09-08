# Claude Code — Handoff & Build Instructions

**Read this entire file before running anything. Then start at Stage 0.**

You are picking up a project mid-flight after a context reset. The repo and
environment are already set up. Your job right now is **not** to build the whole
pipeline — it is to (1) verify what actually exists, (2) build the Tier B
discovery pipeline incrementally with a pass/fail gate at every stage, and
(3) write a detailed run log that a collaborator who cannot see your machine can
read to debug you.

That last point is critical. The person reviewing your work **cannot see your
terminal, your filesystem, or your code output**. The run log is the only
channel. Write it as if the reader is blind to everything except that file.

---

## 1. Project context

### The program

Three linked projects building toward Najdi (central Saudi) Arabic-English
code-switched speech technology:

- **Project 1 — Corpus.** Build a speaker-diverse, gender-balanced speech
  dataset of Najdi Arabic mixed with English mid-sentence. This is the current
  work. Target 8-20 hours, 25+ speakers.
- **Project 2 — Model.** Benchmark commercial/open ASR on it, then LoRA
  fine-tune Whisper. Not started.
- **Project 3 — TARS.** A bilingual conversational robot demonstrator. Not
  started.

### What "code-switching" means here

Speakers mixing Arabic and English **within a single sentence**:

```
عندي meeting الساعة ثلاث
والـdeadline كان really tight فما قدرت أخلصه
```

The second example contains **morphological code-switching** — `والـdeadline`
is Arabic conjunction `و` + definite article `الـ` fused onto the English stem
`deadline`. This is one token that is both languages. It appears in ~46% of
code-mixed sentences in comparable Egyptian data. Any tokenizer or label scheme
that treats it as two tokens is wrong.

### The gap being filled

SDAIA released **SCC** (Saudilang Code-Switch Corpus): 4.45 hours, 4 speakers,
all male, 3 podcast episodes, CC BY-NC-SA 4.0, explicitly an **evaluation** set.
No Najdi-specific *training* corpus exists. SCC is our independent test set and
**must never be trained on**.

### Two data tiers

- **Tier A** — bilingual speakers we record ourselves. High code-switch density
  (~89% in comparable corpora), clean consent. Not your concern right now.
- **Tier B** — selected Saudi YouTube/podcast audio. **This is what you are
  building the pipeline for.**

---

## 2. Current state

**Already done and working (do not rebuild):**

- Git repo exists, GitHub remote configured
- `scripts/bootstrap.sh` has been run — `.venv`, `.env`, directory tree exist
- `config/paths.py` — path resolution module, tested
- `scripts/preflight.sh` + git pre-commit hook — blocks committing audio, API
  keys, `.env`, PII filenames. **Tested and confirmed working.**
- `scripts/sync-up.sh` / `sync-down.sh` — rclone mirror to Google Drive
- `tools/yt_discover.py` — Stage 2, written, logic unit-tested
- `tools/yt_triage.py` — Stage 3, written, scoring logic unit-tested
- `provenance/candidate_channels.csv` + `provenance/sources.csv` — seed templates

**Never tested against real YouTube.** The two tools above were tested only
against synthetic fixtures because the authoring environment had no network
access to youtube.com. **Assume they may fail on first contact with reality.**

**Not built yet:** Stages 6-10 (download, segment, draft, push to Label Studio,
export).

---

## 3. Environment contract

### Machines

- **MacBook Pro, Apple Silicon** — `MACHINE_ROLE=mac`. Annotation, local Whisper
  via `mlx-whisper`, daily driver. **This is almost certainly where you are.**
- **Desktop, RTX 3050 8GB, WSL2** — `MACHINE_ROLE=gpu`. Training only. Not used
  in this pipeline.

### Path rules — non-negotiable

**Never write an absolute path in code.** Import from `config.paths`:

```python
from config.paths import P
P.tierB_raw / f"{video_id}.wav"
```

`P.data` resolves from `NAJDICS_DATA_ROOT` in `.env`. Two storage classes:

| Class | Location | In git? |
|---|---|---|
| Code, docs, transcripts, metadata, provenance CSVs | `~/najdics/` | **yes** |
| Audio, captions, candidates, drafts, checkpoints | `~/najdics-data/` (symlinked as `data/`) | **never** |

When storing an audio path inside a transcript record, store it **relative to
the data root** via `P.relative(abs_path)`. Absolute paths break portability
between the two machines.

### Hard rules

1. **Never commit audio.** `.wav`, `.mp3`, `.m4a`, `.flac` — the pre-commit hook
   blocks these. Do not use `git add -f` to bypass it.
2. **Never commit `.env`** or anything containing an API key.
3. **Never train on or modify SCC.**
4. **The rights gate (Stage 5) is a hard block**, not a warning. See §5.
5. **Never pass `language="ar"`** to Whisper or any ASR call. It forces
   Arabic-script decoding and destroys or transliterates the English tokens,
   which are the entire point of this corpus.
6. Arabic normalization is for **comparison and scoring only** — never store
   normalized text as the transcript. Always keep a verbatim layer.

---

## 4. Stage 0 — Environment audit (DO THIS FIRST, WRITE NO CODE)

Before building anything, produce a factual report of what exists. Do not
assume; check. Write results into the run log (§6).

Check and report:

```bash
# 1. Repo state
pwd
git remote -v
git status --short
git log --oneline -5

# 2. Environment
python3 --version
cat .env | sed 's/=.*/=<redacted>/'      # keys redacted, keys' NAMES visible
echo "NAJDICS_DATA_ROOT=$NAJDICS_DATA_ROOT"

# 3. Does path resolution work?
source .venv/bin/activate
python3 -m config.paths

# 4. What files actually exist
find . -type f -name "*.py" -not -path "./.venv/*" | sort
ls -la provenance/
ls -la scripts/

# 5. Tooling
which yt-dlp && yt-dlp --version
which rclone && rclone --version | head -1
python3 -c "import mlx_whisper; print('mlx-whisper ok')" 2>&1 | tail -1
pip list 2>/dev/null | grep -iE "label-studio|yt-dlp|dotenv|soundfile|librosa"

# 6. Is the pre-commit hook live?
ls -la .git/hooks/pre-commit
```

**Gate 0 passes if:** repo is a git repo with a remote, `python3 -m config.paths`
runs without raising, and `yt-dlp` is installed.

**If Gate 0 fails, STOP.** Write the failure into the run log and do nothing
else. Do not attempt to fix the environment by guessing — report it.

---

## 5. The pipeline — stages, gates, and specs

Ten stages. Each has a **precondition** (checked before running), an **action**,
and a **postcondition** (checked after). A stage that fails either gate must
**stop the pipeline** and be reported — never silently continue.

### Stage 1 — Seed (human input, not yours)

`provenance/candidate_channels.csv`, columns:
`channel_id,channel_name,platform,register_notes,added_date,status`

**Pre:** file exists and has ≥1 row with a non-empty `channel_id`.
**If empty:** this is expected during demo. Report it and use the demo fixture
in §7 instead of failing.

### Stage 2 — Discover

**Tool:** `tools/yt_discover.py` (exists)
**Action:** `yt-dlp --flat-playlist --dump-json` on a channel's `/videos` page.
No audio downloaded.
**Out:** `data/candidates/{name}.jsonl`, one JSON per video with
`video_id, title, duration_sec, upload_date, channel_id`.

**Post:** file exists, line count > 0, every line parses as JSON, every record
has a non-empty `video_id`.

**Known risk:** the channel URL format. `yt-dlp` may need a handle
(`@channelname`) rather than a `channel_id`, or the `/videos` suffix may behave
differently. If discovery returns zero videos, **try the handle form and report
which worked.** This is exactly the kind of first-contact failure expected here.

### Stage 3 — Triage

**Tool:** `tools/yt_triage.py` (exists)
**Action:** fetch auto-captions only, score by Latin-script ratio.

**Flags are `--write-auto-subs` and `--sub-langs` — PLURAL.** The singular forms
(`--write-auto-sub`, `--sub-lang`) were used in earlier drafts and are wrong.
This was verified against `yt-dlp --help`.

**Out:** `data/captions/{video_id}.ar.vtt` and appended rows in
`data/candidates/triage_scores.jsonl` with `latin_ratio` and `has_captions`.

**Post:** scores file has ≥1 row; every `latin_ratio` is either `null` (no
captions) or a float in `[0.0, 1.0]`.

**Interpretation — report this, don't act on it:** a video scoring high on
Latin ratio likely contains code-switching. **This is a triage signal, not
ground truth.** YouTube's Arabic auto-captions are weak on dialect and may drop
English words entirely rather than transcribe them. A low score does not prove
absence of code-switching.

**Report explicitly in the log:** of N videos, how many had captions at all,
and the distribution of scores. If most videos have **no** caption track, the
entire caption-based triage approach is invalidated and must be reported as
such — that is a genuinely useful finding, not a failure of your work.

### Stage 4 — Shortlist (human decision)

Rows added to `provenance/sources.csv` (in git). You may **propose** a shortlist
by threshold, but do not auto-promote videos into `sources.csv` without the
human confirming. Write the proposal into the run log instead.

### Stage 5 — RIGHTS GATE (hard block)

**Nothing proceeds past here** unless `provenance/sources.csv` for that
`source_id` has:
- `license_status` NOT in {`permission-pending`, `all-rights-reserved`}, AND
- `allows_transcription` = `yes`

**Implement this as an actual function that raises**, not a comment:

```python
BLOCKED = {"permission-pending", "all-rights-reserved", ""}

def assert_cleared(source_id: str) -> dict:
    """Raise unless this source's rights are documented and permissive."""
    row = _lookup(source_id)          # from provenance/sources.csv
    if row is None:
        raise PermissionError(f"{source_id} not in sources.csv — not cleared")
    if row.get("license_status", "").strip().lower() in BLOCKED:
        raise PermissionError(
            f"{source_id} license_status={row.get('license_status')!r} — blocked")
    if row.get("allows_transcription", "").strip().lower() != "yes":
        raise PermissionError(f"{source_id} does not allow transcription")
    return row
```

Call it at the top of Stage 6 and Stage 7. **Do not add a bypass flag.**

Context: the supervising professor has offered licensing covering YouTube
material for this project, but its exact scope (research-use vs redistribution)
is **not yet confirmed in writing**. Until it is, treat everything as
research-use-only and plan for transcript-only release.

### Stage 6 — Download

**Not built. Build it.**
**Pre:** `assert_cleared(source_id)` passes.
**Action:** `yt-dlp -x --audio-format wav`, then `ffmpeg` to 16 kHz mono PCM16.
**Out:** `data/tierB/raw/{video_id}.wav`
**Post:** file exists, non-zero size, and `soundfile.info()` reports
`samplerate == 16000` and `channels == 1`.

### Stage 7 — Cut

**Not built. Build it.**
**Pre:** rights cleared; raw wav exists.

**Clip spec — this matters, get it right:**
- **Target 10–15 seconds total per clip.** Standard ASR training segments run
  2–60s with the optimal band at 10–15s.
- **Do not use ±10s around a switch point** — that yields 20s+ clips, and
  Whisper pads everything to 30s internally, so longer is wasted compute.
  Aim for roughly ±5s of context around the switch region.
- **Add ~500 ms hard padding** at each edge. Without it, segments clip the
  leading and trailing phonemes.
- **Merge overlapping windows.** If three switch points fall within 15 seconds,
  emit ONE clip spanning them, not three near-identical overlapping clips.
  Duplicate audio inflates the corpus hour count and is a defect a reviewer
  will catch.
- Caption timestamps drift by roughly 0.3–1s and mark caption-block boundaries,
  not word boundaries. **Never use them as final segment boundaries** — they
  locate a region, the annotator adjusts the exact edge later.

**Out:** `data/tierB/work/{video_id}/seg_NNNN.wav`
**Post:** every clip is 16 kHz mono; every duration is within [2.0, 30.0]s;
no two clips from one video overlap by more than 25% of their length.

### Stage 8 — Draft

**Not built. Build it.**
**Action:** `mlx-whisper` locally (free, offline, keeps audio on-device).
**No `language=` argument.**
**Out:** `data/drafts/{video_id}/seg_NNNN.txt`
**Post:** one draft per clip; report how many came back empty.

### Stage 9 — Push to Label Studio

**Not built. Build it.**
Label Studio's ASR template accepts pre-annotations, so the annotator corrects
Whisper's draft rather than typing from silence. Task shape:

```python
{
  "data": {"audio": "<path or URL>"},
  "predictions": [{
    "model_version": "whisper-large-v3-mlx",
    "result": [{
      "from_name": "transcription", "to_name": "audio",
      "type": "textarea", "value": {"text": ["<draft text>"]}
    }]
  }]
}
```

**Post:** task count in Label Studio equals clip count.

### Stage 10 — Correct & export

Human work in the browser, then export to `corpus/transcripts/{video_id}.jsonl`
(in git). Annotation runs **two independent annotators on a sample**, blind to
each other, with Cohen's κ measured and disagreements adjudicated. Not your
concern this run.

---

## 6. Demo run log — REQUIRED OUTPUT

Write `docs/RUN_LOG.md`, appending one section per stage, **as you go** (not at
the end — if you crash, the partial log is the diagnostic).

The reader cannot see your machine. Include actual data samples, not summaries.

### Format — follow exactly

```markdown
# Run log — <ISO timestamp>

Machine: <mac|gpu>   Python: <version>   Mode: DEMO

---

## Stage 0 — Environment audit
**Status:** PASS | FAIL

**Checked:**
- git remote: <actual output>
- git status: <clean | N modified files>
- python: <version>
- config.paths: <PASS — pasted output | FAIL — pasted traceback>
- yt-dlp: <version | MISSING>
- mlx-whisper: <ok | MISSING>
- pre-commit hook: <present | absent>

**Files found:**
<paste the find output>

**Notes:** <anything unexpected>

---

## Stage N — <name>
**Status:** PASS | FAIL | SKIPPED (reason)

**Precondition check:** <what you verified, and the result>

**Command run:**
```
<the literal command or function call>
```

**Consumed:** <input path> (<N records>)
**Produced:** <output path> (<N records>, <size>)

**Sample output — first 2 records, verbatim:**
```json
<paste actual records, do not paraphrase or clean them up>
```

**Postcondition check:** <what you asserted, pass/fail>

**Errors:** <verbatim traceback, or "none">

**Observations:** <anything surprising — encoding, empty fields, odd values>
```

### Rules for the log

1. **Paste real data, not descriptions.** "Retrieved 47 videos" is useless.
   Paste two actual records. Arabic text especially — encoding bugs are
   invisible in a summary.
2. **Paste tracebacks verbatim and in full.** Do not summarize an error.
3. **Never fake a PASS.** If a stage half-worked, mark it FAIL and explain.
4. **Log surprises even when the stage passes.** Empty fields, unexpected
   nulls, weird durations, Arabic rendering oddly — all of it.
5. Append after each stage. Do not buffer.

---

## 7. Demo mode

This run is a **smoke test**, not production. Constraints:

- **One channel only.** Whichever is in `candidate_channels.csv`, or if empty,
  pick any Saudi Arabic podcast/tech channel you can find and **record clearly
  in the log that you chose it and why**.
- **Cap at 5 videos** for Stages 2-3. Do not triage a whole channel.
- **Stages 6-9: build the code, but do NOT execute on real content** unless
  Stage 5's rights gate genuinely passes for a source. If nothing is cleared,
  that is the **correct** outcome — write the code, run it against a
  synthetic fixture, and log `SKIPPED — no cleared sources, gate working as
  designed`.
- Add `--demo` / `--limit N` flags rather than hardcoding caps.
- **Commit nothing** until the human reviews the log.

For fixture-testing Stages 6-9 without real content, generate a synthetic wav:

```python
import numpy as np, soundfile as sf
sr = 16000
tone = 0.1 * np.sin(2*np.pi*220*np.arange(sr*30)/sr).astype("float32")
sf.write("/tmp/fixture_30s.wav", tone, sr, subtype="PCM_16")
```

This exercises segmentation and format checks without touching anyone's
copyright.

---

## 8. What to hand back

Three things, which the human will forward:

1. **`docs/RUN_LOG.md`** — the full log
2. **Any new/modified source files** — say which
3. **A short summary:** what passed, what failed, what you'd need to proceed

**Do not push to GitHub.** Leave changes staged or unstaged for review.

---

## 9. If you get stuck

Do not improvise around a blocker. Specifically:

- **Do not** disable the pre-commit hook
- **Do not** add a bypass to the rights gate
- **Do not** hardcode absolute paths to work around `config.paths`
- **Do not** pass `language="ar"` to make Whisper "work better"
- **Do not** invent a channel ID, video ID, or license status

Write the blocker in the log with the verbatim error and stop. A clean, honest
failure report is a successful run of this task.
