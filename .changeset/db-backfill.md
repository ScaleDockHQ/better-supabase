---
"better-supabase": minor
---

`better-supabase db backfill <table.column>` fills the null values of a column that a migration added to a table that already holds rows. `--from projects.organization_id via project_id` copies each value from the table a foreign key points at, and `--value "'EUR'"` writes one literal. It updates `--batch-size` rows per statement (default 1000) and locks only those rows, prints a line per batch, supports `--dry-run` and the `--json` envelope, and touches only null rows, so a second run fills nothing. Read more under [db backfill](https://bettersupabase.com/docs/cli/db#backfill).

`doctor` adds BS236, which reports a check added `not valid` that no row fails any more, and the new `doctor --fix` flag runs `alter table ... validate constraint` for it. Against a database that is not local, an agent asks for consent first. JSON findings that `--fix` can resolve carry the SQL in a new optional `fix` field.

The migration lock lints now follow expand and contract. BS230 flags a `references` or `check` written inline in `add column`, BS231 flags `add column ... not null` without a default, and BS233 no longer asks for `lock_timeout` before a statement that only runs `validate constraint`.
