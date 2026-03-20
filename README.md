# LinguaCircuit

A spaced-repetition vocabulary and idiom learning system that uses **GitHub as a
stateful backend** and **ChatGPT as an interactive tutor**.

GitHub Actions prepares a daily lesson packet at 5 AM Central Time. At 6 AM,
ChatGPT
reads the packet, runs an interactive session, and writes the results back via
pull request. Merging the PR triggers automated state updates — no external
database required.

---

## How It Works

1. **5 AM CT** — A cron workflow runs `Get-DueItems.ps1` and `Invoke-LessonPrep.ps1`
   to build a prioritized due queue and markdown lesson packet.
2. **6 AM CT** — ChatGPT (via GitHub App integration) reads the lesson packet and
   starts an interactive review session.
3. **After the session** — ChatGPT opens a PR containing a structured session-result
   JSON file in `data/learner-state/greg/session-history/`.
4. **On merge** — The `process-session-result` workflow runs `Update-LearnerState.ps1`
   to update recall scores, ease factors, and next-due dates.
5. **On every push** — The `validate-state` workflow checks all JSON files against
   their schemas.

---

## Repository Structure

```
LinguaCircuit/
├── .github/workflows/
│   ├── daily-lesson-prep.yml        # 5 AM CT cron — build due queue + lesson packet
│   ├── process-session-result.yml   # PR merge — update learner state
│   └── validate-state.yml           # Push/PR — validate JSON against schemas
├── data/
│   ├── items/
│   │   ├── vocabulary/              # Word definition files (20 seed items)
│   │   └── idioms/                  # Idiom definition files (10 seed items)
│   ├── learner-state/greg/
│   │   ├── profile.json             # Daily targets and preferences
│   │   ├── item-state/              # Per-item recall tracking
│   │   └── session-history/         # Archived session results
│   └── derived/due-queues/          # Generated lesson packets (auto-committed)
├── schemas/
│   ├── item.schema.json             # Vocabulary + idiom definition schema
│   ├── learner-state.schema.json    # Per-item state tracking schema
│   └── lesson-result.schema.json    # ChatGPT session output contract
├── scripts/powershell/
│   ├── Get-DueItems.ps1             # Filter and prioritize due items
│   ├── Invoke-LessonPrep.ps1       # Assemble markdown lesson packet
│   └── Update-LearnerState.ps1     # Process session results, update state
├── prompts/
│   ├── system.md                    # Coach persona and output rules
│   ├── lesson.md                    # Lesson template with placeholders
│   └── evaluation.md               # Standalone evaluation prompt
└── docs/
    └── architecture.md              # Full system design documentation
```

---

## Prerequisites

- **PowerShell 7+** — scripts use `pwsh` syntax.
- **Python 3.12+** — used by the validation workflow (`jsonschema` package).
- **GitHub Actions** — workflows run on `ubuntu-latest` with `pwsh` shell.
- **ChatGPT with GitHub App integration** — reads/writes repo content.

---

## Getting Started

### 1. Clone the repo

```bash
git clone https://github.com/<owner>/LinguaCircuit.git
cd LinguaCircuit
```

### 2. Run a local lesson prep (optional)

```powershell
./scripts/powershell/Get-DueItems.ps1 -RepoRoot . -LearnerId greg
./scripts/powershell/Invoke-LessonPrep.ps1 -RepoRoot . -LearnerId greg
```

The lesson packet will appear in `data/derived/due-queues/`.

### 3. Enable GitHub Actions

Push to `main` and ensure Actions are enabled in the repo settings. The
`daily-lesson-prep` workflow evaluates runs at 10:00 and 11:00 UTC, then
executes only at 5 AM Central Time (America/Chicago).

### 4. Connect ChatGPT

1. Install the GitHub App integration in ChatGPT.
2. Grant it access to this repository.
3. Create a scheduled task in ChatGPT at 6 AM with the system prompt from
   `prompts/system.md`.

---

## Adding New Items

1. Create a JSON file in `data/items/vocabulary/` or `data/items/idioms/`
   following the schema in `schemas/item.schema.json`.
2. Create a matching item-state seed in `data/learner-state/greg/item-state/`
   with `"status": "new"` and a `next_due` date.
3. Push to `main` — the validation workflow will verify the files.

---

## Scheduling Algorithm

Rule-based interval assignment (MVP) based on the worst recall dimension:

| Worst Result | Base Interval |
|-------------|---------------|
| Incorrect   | 1 day         |
| Partial     | 2 days        |
| Correct     | 5 days        |
| Mastered    | up to 14 days |

An ease factor (1.3–3.0) multiplies the base interval and adjusts after each
session. SM-2 / FSRS algorithms are planned for a future iteration.

---

## Documentation

See [docs/architecture.md](docs/architecture.md) for the full system design,
data model details, prompt architecture, and workflow specifications.

---

## Author

Greg Tate
