---
"better-supabase": patch
---

Read the SQL and dotenv doctor rules (hooks, dispatch regression, error codes, the import guard, BS221, BS226, BS389 and the env rules) as tokens, so a comment or a quoted string that names a function or a pooler URL no longer produces a finding. Codes and findings stay the same for real code. The table-modules codemod puts a new import after a leading `"use client"`, and the same-tenant and table-tags codemods remove an entry from the file that declares an imported config value.
