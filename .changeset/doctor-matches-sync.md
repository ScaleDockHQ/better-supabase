---
"better-supabase": patch
---

Doctor's BS304 now renders the SQL module files with the same layout as `sql sync` (grants from policies, session policies, audited tables and the vector schema), so the two no longer disagree about stale files. BS313 skips projects that set `sql.modules["rate-limit"].options.preRequest` to `false`.
