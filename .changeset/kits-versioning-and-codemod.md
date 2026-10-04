---
"better-supabase": minor
---

SQL kit modules have versions and an upgrade path, and a codemod rewrites renamed APIs.

- `better-supabase sql upgrade` reads each module's `@bs-kit` version (a file without one is version 1), writes the forward steps into `supabase/migrations/<timestamp>_better_supabase_kit_upgrade.sql` and rewrites the module files. `--check` exits 1 when a module is behind or a file is stale.
- Deprecated kit functions keep a wrapper under the old name until they are removed. `upgradePlan()`, `kitDeprecations()` and `moduleVersion()` are exported from `better-supabase/sql`.
- `track_updated_at()` and `audit()` warn about an existing trigger that does the same work, and drop it with `replace_trigger => true`.
- Doctor reports deprecated or removed kit symbols in schema files and policies (BS309), a kit trigger next to an equivalent one (BS310), and a module behind its version on disk or in `better_supabase.kit_modules` (BS311). BS304 skips files BS311 reports.
- `better-supabase codemod <version>` rewrites imports, members, JSX props and call options for renamed APIs (`0.4`, and `0.5` for `createMcp`'s `scopes`), skipping strings and comments, and lists the lines it leaves for review. `--dry-run` prints the diff.
