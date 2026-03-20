# LinguaCircuit — Architecture

## Overview

LinguaCircuit is a spaced-repetition vocabulary and idiom learning system that uses
**GitHub as a stateful backend** and **ChatGPT as an interactive tutor**. All
scheduling, state management, and automation live in this repository; ChatGPT
reads lesson packets and writes session results via pull requests.

---

## Daily Cycle

```
┌──────────────┐   5 AM CT (cron)     ┌──────────────────┐
│  GitHub       │─────────────────────▶│ daily-lesson-prep │
│  Actions      │                      │ workflow          │
└──────────────┘                      └────────┬─────────┘
                                               │
                             1. Get-DueItems.ps1 → due-queue JSON
                             2. Invoke-LessonPrep.ps1 → lesson packet (.md)
                             3. Commit + push to main
                                               │
                                               ▼
┌──────────────┐   6 AM CT (manual)   ┌──────────────────┐
│  ChatGPT      │◀────────────────────│ Lesson packet     │
│  (tutor)      │  reads via GitHub   │ in repo           │
└──────┬───────┘  App integration     └──────────────────┘
       │
       │  Interactive lesson session
       │
       ▼
┌──────────────────┐                  ┌──────────────────┐
│ Session result    │   PR opened by   │ process-session-  │
│ JSON + transcript │──ChatGPT/user──▶│ result workflow    │
└──────────────────┘                  └────────┬─────────┘
                                               │
                           1. Update-LearnerState.ps1 → updated item-state
                           2. Save session history
                           3. Commit + push
                                               │
                                               ▼
                                      ┌──────────────────┐
                                      │ validate-state    │
                                      │ workflow (on push) │
                                      └──────────────────┘
```

---

## Repository Structure

```
LinguaCircuit/
├── .github/workflows/
│   ├── daily-lesson-prep.yml      # Cron: build due queue + lesson packet
│   ├── process-session-result.yml # PR merge: update learner state
│   └── validate-state.yml         # Push/PR: validate JSON against schemas
├── data/
│   ├── items/
│   │   ├── vocabulary/*.json      # Word definitions (20 seed items)
│   │   └── idioms/*.json          # Idiom definitions (10 seed items)
│   ├── learner-state/
│   │   └── greg/
│   │       ├── profile.json       # Daily targets, preferences
│   │       ├── item-state/*.json  # Per-item recall tracking (30 seeds)
│   │       └── session-history/   # Archived session results
│   └── derived/
│       └── due-queues/            # Generated lesson packets
├── schemas/
│   ├── item.schema.json           # Vocabulary + idiom definition schema
│   ├── learner-state.schema.json  # Per-item state tracking schema
│   └── lesson-result.schema.json  # ChatGPT output contract
├── scripts/powershell/
│   ├── Get-DueItems.ps1           # Filter + prioritize due items
│   ├── Invoke-LessonPrep.ps1     # Assemble markdown lesson packet
│   └── Update-LearnerState.ps1   # Process session results, update state
├── prompts/
│   ├── system.md                  # Coach persona + rules
│   ├── lesson.md                  # Lesson template with placeholders
│   └── evaluation.md             # Standalone evaluation prompt
└── docs/
    └── architecture.md            # This file
```

---

## Data Model

### Item Definition (`schemas/item.schema.json`)

Unified schema with an `item_type` discriminator:

| Field               | Vocabulary | Idiom | Description                              |
|---------------------|:----------:|:-----:|------------------------------------------|
| `item_id`           | ✓          | ✓     | `vocab-*` or `idiom-*`                   |
| `item_type`         | ✓          | ✓     | `vocabulary` or `idiom`                  |
| `term`              | ✓          | ✓     | The word or phrase                        |
| `definition`        | ✓          | ✓     | Primary meaning                           |
| `examples`          | ✓          | ✓     | Usage sentences                           |
| `confusions`        | ✓          | ✓     | Commonly confused terms                   |
| `difficulty`        | ✓          | ✓     | 1–5 scale                                |
| `tags`              | ✓          | ✓     | Categorization labels                     |
| `part_of_speech`    | ✓          |       | Noun, verb, adjective, etc.              |
| `etymology`         | ✓          |       | Origin summary + root morphemes          |
| `literal_gloss`     |            | ✓     | Word-by-word literal meaning             |
| `figurative_meaning`|            | ✓     | Actual intended meaning                  |
| `register`          |            | ✓     | formal / informal / neutral              |
| `common_contexts`   |            | ✓     | Typical usage situations                 |

### Learner State (`schemas/learner-state.schema.json`)

Per-item tracking with three recall dimensions:

- **`definition`** — Can the learner define the term? (0–2)
- **`sentence_usage`** — Can they use it correctly in a sentence? (0–2)
- **`root_understanding`** — Do they grasp etymology/origin? (0–2)

Status progression: `new` → `learning` → `mastered` (with `shaky` regression).

### Session Result (`schemas/lesson-result.schema.json`)

The contract ChatGPT must follow. Each reviewed item includes:

- `recall_result`, `usage_result`, `root_understanding` — each `correct | partial | incorrect`
- `recommended_status` and `recommended_next_due_days`
- `notes` for qualitative feedback

---

## Scheduling Algorithm (MVP)

Rule-based interval assignment based on worst recall dimension:

| Worst Result  | Base Interval |
|---------------|---------------|
| `incorrect`   | 1 day         |
| `partial`     | 2 days        |
| `correct`     | 5 days        |

Mastered items (all dimensions correct, `correct_count ≥ 2`) get up to **14 days**.

An ease factor (1.3–3.0) multiplies the base interval. Ease adjusts by:

- All correct → +0.1
- Any partial → −0.1
- Any incorrect → −0.2

> SM-2 / FSRS algorithms are planned for a future iteration.

---

## Prompt Architecture

Three prompt files work together:

1. **`system.md`** — Defines the coach persona, teaching methodology (forced recall,
   contextual usage, etymology, confusion pairs), session structure, and the
   `BEGIN_SESSION_RESULT` / `END_SESSION_RESULT` output contract.

2. **`lesson.md`** — Template with `{{learner_id}}`, `{{date}}`, `{{items_section}}`,
   and `{{learner_context}}` placeholders. Filled by `Invoke-LessonPrep.ps1`.

3. **`evaluation.md`** — Standalone prompt for reprocessing a transcript into
   structured session-result JSON.

---

## GitHub Actions Workflows

### `daily-lesson-prep.yml`

- **Trigger:** Cron at 10:00 and 11:00 UTC, with runtime gating to 5 AM
   Central Time (`America/Chicago`)
- **Steps:** Checkout → `Get-DueItems.ps1` → `Invoke-LessonPrep.ps1` → commit + push

### `process-session-result.yml`

- **Trigger:** PR merged with changes in `data/learner-state/greg/session-history/`
- **Steps:** Checkout → find new session files → `Update-LearnerState.ps1` → commit + push

### `validate-state.yml`

- **Trigger:** Push to main or PR with changes in `data/` or `schemas/`
- **Steps:** Checkout → Python `jsonschema` validation of all items, states, and history

---

## ChatGPT Integration

ChatGPT connects to this repo via the **GitHub App integration** (no API keys needed).
The workflow is:

1. GitHub Actions commits the lesson packet to `data/derived/due-queues/`.
2. At 6 AM Central Time, a ChatGPT scheduled task reminds the user to start.
3. ChatGPT reads the lesson packet from the repo.
4. After the session, ChatGPT (or the user) opens a PR with the session-result JSON
   in `data/learner-state/greg/session-history/`.
5. Merging the PR triggers the `process-session-result` workflow.

---

## Adding New Items

1. Create a JSON file in `data/items/vocabulary/` or `data/items/idioms/`.
2. Validate against `schemas/item.schema.json`.
3. Create a matching item-state seed in `data/learner-state/greg/item-state/`
   with `status: "new"` and a `next_due` date.
4. Commit and push — the validate workflow will verify the files.
