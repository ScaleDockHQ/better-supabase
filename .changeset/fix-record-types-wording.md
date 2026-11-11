---
"better-supabase": patch
---

Say `config.recordTypes` in error messages, generated comments, JSDoc and docs where they said `config.subjects`, the key `recordTypes` replaced in 0.54. `scripts/check-naming.ts` now fails on a former config key in a comment, a string or a docs page. Run `better-supabase gen` to refresh the comment in `generated.ts`.
