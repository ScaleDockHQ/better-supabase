# 0252: Declare row audit triggers in the schema files

- Status: accepted
- Date: 2026-11-07
- Amends: 0251

## Context

A block table that the audit block covers (`blocks.audit.options.blockTables`)
got its row trigger from a `do` block that called `better_supabase.audit(...)`.
A schema diff can't see the trigger that block creates at run time, and a
module installed before `audit` could not call the function at all, so its
registration went to the data file and a schema diff dropped nothing and
created nothing for it.

## Decision

`rowAuditData` in `src/sql/row-audit.ts` writes the trigger that `audit()` would
create as one static statement in the module's schema file:
`create constraint trigger bsb_audit after insert or update or delete on <table>
deferrable initially deferred for each row execute function
better_supabase.audit_row_change('<settings>')`. The settings are the trigger's
argument (`ignore`, `redact`, `target_type`, `event_prefix`), and the row's key
columns fall back to its primary key when the trigger runs, as they do for a
trigger without `key_columns`. `blockTables: "all"` writes the plain
`bsb_audit` trigger for the tables that have no entity.

Install order no longer matters under a declarative diff, because pg-delta
orders the trigger after the function. Only the migrations workflow
(`layout.rerunnable`) keeps the data-file call for a module installed before
`audit`, since it applies statements in file order. `blockTables: "none"` and a
missing `audit` block write nothing, and the audit module's own tables stay
unaudited.

`auditRegistrations` reads `create constraint trigger bsb_audit ... deferrable`
the way it reads a plain trigger, so the audit pgTAP file asserts each
generated trigger and doctor accepts one an app file declares.

## Alternatives considered

Keeping the `do` block would leave 241 triggers invisible to the diff. Reading
primary keys from the module body to fill `key_columns` would repeat what the
trigger already reads from the catalog.

## Consequences

The repository's `supabase/` folder is regenerated with one migration that
swaps each `bsb_audit` trigger for the static one. Installed apps run
`better-supabase upgrade` and then the Supabase CLI sync. `supabase db schema
declarative sync --strict-coverage` reports no changes and the 172 pgTAP files
pass.
