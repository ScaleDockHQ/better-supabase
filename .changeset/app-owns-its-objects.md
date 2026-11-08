---
"better-supabase": minor
---

`upgrade` writes module and data files only. Under pg-delta, the forward steps a schema diff can't express (renames, backfills, expression changes) go into `<stamp>_better_supabase_reviewed_upgrade_<hash>.sql`, marked `-- destructive: reviewed`; the migra workflow keeps `<stamp>_better_supabase_block_upgrade_<hash>.sql`. `blocks.memberships.options.sameTenant.auto` emits no trigger for a column that an app trigger already reads or writes through `new.<column>`, and `codemod` never rewrites a block file, even when a path names it. If you reference the old migration name in scripts, use the new one.
