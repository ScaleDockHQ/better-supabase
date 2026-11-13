---
"better-supabase": minor
---

Block errors name their fields and carry default messages. `invalid_input` errors have an optional `fields: [{ path, code, message }]` (build one with `invalidInput(message, fields)`, or raise `{"fields": [...]}` in the `DETAIL` of an `22xxx` error in SQL), and `toProblem` sends them as a `fields` member. The new `better-supabase/blocks/messages` entry exports `BLOCK_HINT_MESSAGES` (one English message per hint code, keyed by the code, which is also the next-intl key) with `hintMessage`, `blockErrorMessage` and `fieldMessages`. `createBlocks` takes `locale` and `hintMessages` and rewords errors raised in SQL through them. `better-supabase/react` exports `ErrorMessagesProvider` and `useErrorMessage`. The tags block returns a `TAG_NAME_REQUIRED` field error for an empty name, and a few clients raise hint codes that `BlockHints` now lists.

| Before                                                      | After                                                                           |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------- |
| A hand-written `useErrorMessage` hook per app               | `useErrorMessage` from `better-supabase/react`, with an `ErrorMessagesProvider` |
| A sentence per error kind and no text for a hint code       | `blockErrorMessage(error) ?? yourKindMessage(error)`                            |
| `dbError("invalid_input", message, { hint })` with no field | `invalidInput(message, [{ path, code, message }])`                              |
| `{ kind: "invalid_input" }` carries no input names          | `error.fields` lists the inputs, when the block names them                      |
