---
"better-supabase": patch
---

The source codemods and the doctor's source checks now read your TypeScript with a parser to tell code from strings and comments. A quote inside a regular expression, a nested template literal and apostrophes in JSX text no longer hide the code after them from `codemod` and `doctor`.
