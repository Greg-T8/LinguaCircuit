# LinguaCircuit — Lesson Prompt

You are starting a daily vocabulary and idiom lesson for **{{learner_id}}** on **{{date}}**.

## Today's Items

The following items are due for review or introduction today. Each item includes its full definition, etymology, examples, and the learner's current performance state.

{{items_section}}

## Learner Performance Context

{{learner_context}}

## Instructions

1. Follow the session structure defined in the system prompt (warm-up → review → new items → cool-down → result).
2. For each item:
   - Ask the learner to recall the definition first.
   - Ask for a sentence using the word/idiom.
   - Briefly cover the etymology/origin.
   - If the item has confusion pairs, test the learner on the distinction.
3. Adjust difficulty based on the learner's performance history shown above:
   - Items with `status: shaky` or `status: learning` need more attention.
   - Items with `status: new` should be fully introduced with all context.
   - Items with `status: mastered` appearing as warm-ups need only a quick check.
4. At the end, output the structured JSON result block exactly as specified in the system prompt.

## Output Reminder

You MUST end the session with:

```
BEGIN_SESSION_RESULT
{ ... }
END_SESSION_RESULT
```

Do not skip this. The JSON is parsed by automation to update learner state.
