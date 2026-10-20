# 0051: App table columns restrict access with Postgres column grants

- Status: accepted
- Date: 2026-10-19

## Context

No-code databases let a builder hide a field from some users or make it
read-only: an internal note, a cost price, a score the server computes. App
tables had row policies only, so every column a signed-in user could reach
was readable and writable. An app had to move such a column into a second
table, or trust its client code to leave it alone.

## Decision

An app table column takes `access?: "read" | "server"`. Without it, nothing
changes. With it on any column, `sql sync` revokes the table grants from
`authenticated` and grants `select` on the readable columns, and `insert` and
`update` on the writable ones, by name; `delete` stays a table grant on a
scoped table. `read` columns are readable and not writable, `server` columns
are neither. The service role keeps every grant.

Everything that reads the table follows the grants. The `<table>_view` lists
the readable columns instead of `t.*`. `gen` marks a `server` column
`selectable: false` in the table meta, so the query compiler leaves it out of
a default select, and makes it optional in the row type. `appTables.set`
never offers a restricted column.

`appTables` refuses configs that would need a hidden column. A required
column with `access` needs a default, since signed-in users can't fill it on
insert. A `server` column can't feed the subject title, search, URL or rank
group, a rollup or lookup, `events.include` or `subject.versions.columns`,
and a table with `versions: true` must list its versioned columns. These
checks cover `server` only: a `read` column is still readable, so it is safe
in every read use. A table in `expose` can't set `access`, because `expose`
already owns its grants.

The pgTAP file checks `has_column_privilege` for every column, and that a read
of a `server` column and an update of a restricted one throw `42501`.

## Alternatives considered

A view that leaves the columns out, with the table itself revoked, hides the
data too, but every write would need `instead of` triggers or a second path,
and PostgREST embedding works on tables. Policies can't hide a column: row
level security filters rows, not fields. A trigger that rejects writes to a
column handles `read` but not `server`. Encrypting the column with Vault keeps
it secret even from the database owner, which is more than this needs and
makes it unsearchable.

## Consequences

Access is enforced by Postgres, so it holds for the typed client, raw
PostgREST calls and SQL run as `authenticated`. A query that names a hidden
column fails at plan time, even with `where false`. The typed client names its
columns, so it keeps working; a raw PostgREST call with `select=*` on the
table can fail and has to name its columns or read the `<table>_view`.
Tightening access is breaking in the design diff, because client reads or
writes of the column start to fail. Grants are per role, not per user, so a
column one member can see and another can't still needs a separate table or
an authorization provider.
