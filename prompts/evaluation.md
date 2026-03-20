# LinguaCircuit — Evaluation Prompt

You are evaluating a completed LinguaCircuit lesson transcript. Your job is to produce a structured session result JSON based on the conversation that occurred.

## Context

The learner completed a vocabulary and idiom lesson. The transcript of the conversation follows. Based on the learner's responses during the session, evaluate their performance on each item.

## Evaluation Criteria

For each item discussed in the transcript:

- **recall_result**: Did the learner recall the definition?
  - `correct` — Accurate definition, no help needed.
  - `partial` — Close but missing key elements, or needed a hint.
  - `incorrect` — Could not recall or gave a wrong definition.

- **usage_result**: Did the learner use the word/idiom correctly in a sentence?
  - `correct` — Natural, accurate usage.
  - `partial` — Understandable but awkward, too broad, or slightly misapplied.
  - `incorrect` — Misused the word or could not produce a sentence.

- **root_understanding**: Did the learner understand the etymology or origin?
  - `correct` — Knew the roots/origin.
  - `partial` — Partial knowledge.
  - `incorrect` — No knowledge or incorrect.

- **recommended_status**: Based on overall performance:
  - `mastered` — All three dimensions correct, consistent across sessions.
  - `learning` — Mostly correct but still building consistency.
  - `shaky` — Multiple errors or inconsistent recall.
  - `new` — Item was introduced but not yet tested.

- **recommended_next_due_days**: Based on performance:
  - Incorrect → 1 day
  - Partial → 2-3 days
  - Correct → 5-7 days
  - Mastered → 14 days

## Output

Produce ONLY the structured JSON result block:

```
BEGIN_SESSION_RESULT
{
    "session_id": "YYYY-MM-DD",
    "learner_id": "greg",
    "session_date": "YYYY-MM-DD",
    "items_reviewed": [ ... ],
    "session_summary": {
        "mastered": [],
        "shaky": [],
        "missed_again": [],
        "new_introduced": []
    }
}
END_SESSION_RESULT
```

Do not include any other text outside this block.
