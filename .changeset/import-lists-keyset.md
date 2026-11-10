---
"better-supabase": minor
---

`list_import_issues` and `list_import_diff` take a fifth argument, `after`, and return `next_cursor`. Pass the `next_cursor` of one page as `after` to read the next page by keyset. `row_offset` still works while `after` is null. The issues `total` is null on a keyset page, and is counted with a bound of 10,000 on an offset page.

Migration guide:

| Before                                     | After                                                           |
| ------------------------------------------ | --------------------------------------------------------------- |
| `list_import_issues(run, entity, 50, 100)` | Still works. Add `after => page.next_cursor` to page by keyset. |
| `rpc("list_import_issues", { ... })`       | Pass `after` as a fifth named argument when you want a cursor.  |
| Reading `total` on every page              | Read it on the first page, it is null on a keyset page.         |

Run `supabase db diff` to drop the old four-argument functions and to replace the `import_run_issues_run_idx` index.
