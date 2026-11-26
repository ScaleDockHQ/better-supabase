---
"better-supabase": minor
---

`better-supabase codemod audit-statement` rewrites a table's row audit trigger, or its `audit()` call, into static statement triggers that a schema diff keeps. Doctor BS651 reports a table that has both, which would write every change twice.
