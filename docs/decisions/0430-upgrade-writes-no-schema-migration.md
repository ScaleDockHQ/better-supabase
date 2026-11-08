# 0430: Upgrade writes no schema migration, and app triggers replace block triggers

- Status: accepted
- Date: 2026-11-08
- Amends: 0250, 0262

## Context

Under pg-delta, `upgrade` wrote a clock-stamped `block_upgrade` migration next
to the module files. The module files and the schema diff already own every
statement a diff can express, so the migration owned the same DDL twice. The
auto-derived `sameTenant` triggers also ignored a guard the app already wrote,
such as Lienlink's `jobs_organization_fixed`.

## Decision

Under pg-delta the migration holds only the forward steps and entity renames a
diff can't express. It is named `_better_supabase_reviewed_upgrade_<hash>.sql`,
starts with `-- destructive: reviewed`, and is written only when there are
steps. Migra keeps `_better_supabase_block_upgrade_<hash>.sql`, and the
migrations workflow keeps one module migration. `sameTenant.auto` skips a key
column that an app trigger (any trigger not named `bsb_*`) reads or writes
through `new.<column>` or `old.<column>`. `codemod` drops any edit to a file a
block wrote.

## Consequences

Scripts that matched `block_upgrade` under pg-delta match `reviewed_upgrade`.
An app trigger that touches the column but doesn't check the tenant also turns
the generated check off, so the app names the guard it wants.
