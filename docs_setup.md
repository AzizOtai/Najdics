# Workspace Setup — Cross-Platform

**One repo, three machines, one cloud archive. No special cases.**

Covers: MacBook Pro (Apple Silicon), desktop (RTX 3050), iPad/iPhone, Google Drive.

---

## The three rules

**1. Git and Drive never overlap.**
Never put a git repository inside a Google Drive synced folder. The Drive client
will race the `.git` directory, corrupt the index, and produce failures that look
like git bugs. This is the single most common way this kind of setup breaks.

**2. Three storage classes, three different homes.**

| Class | Examples | Lives in | Why |
|---|---|---|---|
| **Code + docs + small metadata** | scripts, guidelines, transcripts, CSVs | **Git / GitHub** | Versioned, diffable, syncs everywhere free |
| **Bulk binary** | audio, model checkpoints | **Local disk + Drive mirror** | Too large for git, doesn't diff |
| **PII** | consent forms, participant names/contacts | **Restricted Drive folder, encrypted** | Never in git, never in a shared folder, ever |

**3. No absolute paths in code, ever.**
Machines differ. One environment variable, `NAJDICS_DATA_ROOT`, resolves it.
Anything hardcoding `/Users/...` or `C:\...` is a bug.

---

## Why WSL2 on the desktop

Your desktop is Windows with an RTX 3050. Install **WSL2 with Ubuntu**. CUDA
passes through to the GPU, and from that point both machines are Unix: the same
bash scripts, the same paths, the same Python environment setup, the same
everything.

The alternative — maintaining PowerShell and bash versions of every script — is a
tax you pay on every single change for the life of the project. Pay the one-hour
WSL setup cost instead.

```powershell
# In an Administrator PowerShell, on the desktop:
wsl --install -d Ubuntu
# reboot, then set a username/password when Ubuntu first launches
```

CUDA in WSL2 needs the **Windows** NVIDIA driver only — do not install a Linux
NVIDIA driver inside WSL, it will conflict. Verify after setup with `nvidia-smi`
inside Ubuntu.

**One caveat:** WSL2's filesystem bridge is slow. Keep the repo and data inside
the Linux filesystem (`~/najdics`), **not** on `/mnt/c/`. Reading thousands of
audio files across the bridge is dramatically slower.

---

## Directory layout

Identical on both machines.

```
~/najdics/                      ← GIT REPO. Never inside Drive.
├── .env                        ← machine-specific, gitignored
├── .env.example                ← committed template
├── config/paths.py             ← resolves all paths
├── docs/                       progress.md, decisions.md, prior-work.md
├── guidelines/                 ANNOTATION.md, borrowings.md, examples.md
├── metadata/                   speakers.csv, sources.csv  (small, IN git)
├── corpus/transcripts/         *.jsonl  (small, IN git — the actual value)
├── tools/  eval/  scripts/  paper/  cad/
└── data → symlink to ~/najdics-data

~/najdics-data/                 ← BULK. Not git, not synced live.
├── tierA/raw/                  48kHz session masters
├── tierA/work/                 16kHz mono segments
├── tierB/raw/  tierB/work/
├── drafts/                     Whisper pre-transcriptions
└── checkpoints/                LoRA adapters (desktop only)

Google Drive/NajdiCS/
├── 00-audio-archive/           ← rclone mirror of ~/najdics-data
├── 10-papers/                  ← reading. Syncs to iPad.
├── 30-exports/                 ← PDFs of the four program documents
└── 90-RESTRICTED-PII/          ← consent forms. Sharing OFF. See below.
```

**Transcripts live in git, audio does not.** That split matters: the transcripts
and annotations are the intellectual work and they're small, textual, and benefit
enormously from version history. Audio is large, opaque to diff, and never
changes after recording.

---

## Storage maths — you probably fit

Easy to over-plan for. The actual numbers:

| Content | Rate | 25 hours |
|---|---|---|
| 48kHz 16-bit mono masters | ~345 MB/hr | ~8.6 GB |
| 16kHz mono working copies | ~115 MB/hr | ~2.9 GB |
| **Total corpus audio** | | **~12 GB** |
| LoRA checkpoints (small, ×3 runs) | ~50 MB each | negligible |

That is on the edge of Google Drive's free 15GB. Two options: use a university
Google Workspace account if you have one (usually far more storage), or archive
only the 16kHz working copies to Drive and keep 48kHz masters on local disk plus
one external drive.

**Do not** treat Drive as your only copy of the raw audio. Recording sessions are
irreplaceable — participants will not come back.

---

## Setup, both machines

```bash
# 1. Repo (do this on GitHub first: create empty private repo "najdics")
cd ~ && git clone git@github.com:YOURNAME/najdics.git
cd najdics

# 2. Bulk data directory, OUTSIDE the repo
mkdir -p ~/najdics-data/{tierA/{raw,work},tierB/{raw,work},drafts,checkpoints}
ln -s ~/najdics-data ~/najdics/data

# 3. Environment
cp .env.example .env
# edit .env: set NAJDICS_DATA_ROOT and MACHINE_ROLE

# 4. Python
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

`requirements.txt` differs by machine role — see `requirements-mac.txt`
(mlx-whisper, annotation tooling) and `requirements-gpu.txt` (torch+CUDA, peft,
bitsandbytes). Install the base file plus the one for your role.

---

## Machine roles

Set `MACHINE_ROLE` in `.env`. Code branches on it rather than on OS detection.

| Machine | Role | Does |
|---|---|---|
| MacBook Pro | `mac` | Annotation (ELAN), `mlx-whisper` pre-transcription, writing, daily driver |
| Desktop (WSL2) | `gpu` | LoRA fine-tuning, bulk audio processing, benchmark runs |
| iPad | — | Reading papers, reviewing progress. **Not** an annotation machine — ELAN has no iPadOS version |
| iPhone | — | Second recorder every session; Drive app for the progress log |

---

## Sync: rclone, not the Drive desktop app

Use **rclone** rather than Google Drive's desktop client for the audio archive.
Reasons: it is scriptable, it runs identically on macOS and WSL, it does not run
a background daemon that can touch files mid-write, and you control exactly when
a sync happens.

```bash
# install
brew install rclone            # macOS
sudo apt install rclone        # WSL2

# configure once per machine
rclone config
#   n) new remote → name: gdrive → storage: drive → follow the OAuth prompts
```

You may still install the Drive desktop app for `10-papers/` and `30-exports/` —
those are read-mostly and convenient to have synced to the iPad. Just keep it
pointed away from the repo and away from `00-audio-archive/`.

---

## The PII rule

`90-RESTRICTED-PII/` holds signed consent forms, which contain real names and
signatures. Rules, non-negotiable:

- **Never** in the git repo. Not even gitignored — one `git add -f` and it is in
  the history permanently.

- **Never** in a folder with link-sharing enabled. Check the sharing setting
  explicitly; do not assume.

- Store as a password-protected archive, or in Drive with sharing off.
- In the corpus, participants appear only as `speaker_id` and `consent_id`. The
  mapping from `consent_id` to a real person lives **only** in this folder.

That indirection is what lets you publish the corpus without publishing anyone's
identity, and what lets you honour a withdrawal request by deleting one row.

---

## Daily rhythm

```bash
# start of session, either machine
cd ~/najdics && git pull

# ... work ...

# end of session
git add -A && git commit -m "phase 2: transcribed tierA_003, 22 min" && git push
./scripts/sync-up.sh            # push new audio to Drive
```

`git pull` first, every time. It is the whole discipline — two machines editing
`guidelines/ANNOTATION.md` without pulling produces a merge conflict in the one
document you least want to merge by hand.

---

## What goes in git, what does not

**In git:** everything textual. Transcripts, annotations, guidelines, metadata
CSVs, code, docs, DXF files, the paper.

**Not in git:** audio (any format), model checkpoints, `.venv/`, `.env`,
anything under `data/`, and absolutely anything with a participant's name in it.

The `.gitignore` in `scripts/` enforces this. Do not weaken it — the reason
audio is excluded is not only size, it is that a public repo with participant
audio committed to its history is a consent violation you cannot undo.
