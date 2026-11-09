# 0593: same_tenant null rows are opt-in

- Status: accepted
- Date: 2026-11-09

## Context

ADR 0590 kept `same_tenant` on by default and let a referenced row with a null
tenant pass, so a global role was a member of every tenant. That pass was
hard-coded in `better_supabase.same_tenant()`. A table that should not be
shared had no way to refuse a null tenant, and a table that should be shared
was not named in the config.

## Decision

The default refuses a reference to a row whose tenant is null. An entry opts
in with `shared: true`, on the entry or on `references`. The function reads
that flag from its arguments, so a trigger that does not pass `shared` keeps
the strict check. `codemod naming` skips a `columns.<table>.tenant` name only
on that table. `sql.tenantColumn` stays global. `renameSqlColumns` renames a
column only when it is qualified by the block table or its alias, or it sits
in that table's insert list or update `set` clause, or in a `'{...}'` argument
of `better_supabase.audit` for that table. A `$$` body is left as it is.

## Alternatives considered

Keep the null-tenant pass as the default: every tenant table that points at a
shared catalog also accepts a row that has no tenant, including one written
by mistake.

A global `sameTenant.shared` list of tables: the flag belongs on the reference
that opts in, next to `where` and `tenant`.

## Consequences

A global role needs `shared: true` or the member insert fails with
`TENANT_MISMATCH`. The PGlite test in
`tests/sql/modules/tenant-same-behavior.test.ts` pins both the refusal and the
opt-in. ADR 0590 records the cost of the check and points here for the null
row.
