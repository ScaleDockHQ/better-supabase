---
"better-supabase": minor
---

Add the `forms` block (`better-supabase/blocks/forms`). A form has numbered versions of steps and fields with `showIf` conditions, and each version stores a JSON Schema 2020-12 that `pg_jsonschema` checks on every submission. Submissions can be saved as drafts, linked to a record, or turned into one by a handler per form key. With `share-links`, a `respond` link opens the form to anyone who holds it, rate limited per caller with `rate-limit`, and `before_public_form_submission` receives a bot-check token. `useQuestionnaire` from `better-supabase/blocks/forms/react` drives a multi-step form from a version, and `validateAnswers` checks answers in the browser with the same schema.
