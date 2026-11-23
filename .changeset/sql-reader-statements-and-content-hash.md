---
"better-supabase": minor
---

Read SQL with one reader and compare statements by their canonical text (ADR 1300 and 1301).

Breaking for callers of `better-supabase/sql`: the statement splitter is gone from the entry. The CLI reads statements from the parser's scanner, which needs no valid grammar and keeps the same lines.

| Removed from `better-supabase/sql` | Use instead                                                                                       |
| ---------------------------------- | ------------------------------------------------------------------------------------------------- |
| `splitStatements`                  | Split in your own code, or read the file with the `better-supabase` CLI (`doctor`, `gen`, `sync`) |
| `SqlStatement` (type)              | `{ text: string; line: number }`                                                                  |

`sync` and the codemods compare statements by the parser's deparse, so spacing, comments, keyword case and redundant quoting no longer make a statement new. The migration file hash is versioned: new files end in `_v2-<8 hex digits>.sql`. A migration an earlier release wrote, with the old hash, is still recognized as the same file and is never renamed, so upgrading writes no new migration. A statement set that does not parse keeps the old name form.
