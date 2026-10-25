---
"better-supabase": patch
---

`codemod 0.15` lists the lines of your own SQL that name a `bs_` object the upgrade migration renames to `bsb_`: your pgTAP tests (`sql.testsDir`), the schema files no block wrote, and your newest migration. Each line shows under "Check these by hand" with its file and line. The codemod never rewrites SQL, since a migration you pushed must not change.
