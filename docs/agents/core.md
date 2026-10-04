# Core

Corrections for `packages/better-supabase/src/core` and the plugins.

## Column names and casing

Table metadata stores names in the configured casing: on a `casing: 'camel'`
table, `table.primaryKey`, `table.columns` and the keys of a row are
camelCase. PostgREST only knows the database names. Every name that goes into
a query (an order term, a filter, a select list, an `on_conflict` target)
passes through `builder.column(table, name)` first, as `withTieBreaker` and the
default order in `src/core/repository.ts` do. A raw `table.primaryKey` in an
`OrderTerm` sends `order=customerId.asc`, which PostgREST rejects.

The tests that catch this need a camel table whose primary key is not `id`
(`customer_tags` in the fixtures); a table keyed on `id` hides the bug because
the name is the same in both casings.

## Per-request work

`connect()` and the repositories run on every request. Work that depends only
on the schema or the plugin list (column maps, default orders, plugin hook
arrays) is computed once per table and cached in a `WeakMap` keyed on the
table or the plugin list, not rebuilt inside a method.

## Plugin order and hook copies

`rules()` must see the query as the caller wrote it, so `orderPlugins` ranks
it before every `pre` plugin by name; a new `pre` plugin that rewrites
queries never needs to know about it. Mutation hooks and `mutation`
listeners get a copy of the returned rows (`cloneRows` in
`src/core/repository.ts`), which keeps invariant 5 without trusting each
hook. Copy plain objects and arrays only: Temporal values are immutable and
`structuredClone` drops their prototype.

## Cross-tenant contexts

A request context is data that adapters, jobs and callers build, so a plain
key such as `{ allTenants: true }` in it could come from a payload or claims.
Skipping the tenant scope for a whole connection goes through
`allTenantsContext(context)` in `src/core/plugin.ts`, which sets a module
symbol that JSON can't produce and `$with` copies. `tenant()` and tenant
buckets check it with `spansAllTenants`; per-call opt-outs stay
`{ allTenants: true }` in the call options.

## Kit extension points

Every kit uses the same four extension points, so a new kit adds entries
instead of a new mechanism:

- **Events.** Add the type to `KitEventMap` (`src/core/kit-events.ts`) and
  call `emitKitEvent` after the work succeeds or is refused. The data never
  holds secrets (invitation tokens, webhook secrets), and handlers only
  observe.
- **Policies.** A decision the app can make is a `Policy` run through
  `decide()` (`src/core/policy.ts`), which fails closed. Never call the
  callback directly; a throw must deny, not escape.
- **SQL hooks.** List the hook in the module's `names.hooks` and render it
  with `ctx.hook(name, args)`; `ctx.emit(...)` writes the outbox event and
  renders nothing without the outbox.
- **Swappable parts.** An interface the app can replace carries
  `apiVersion: 1`, a conformance kit in `src/testing/conformance.ts`, an
  entry in `tests/core/extensibility.test-d.ts` and a row on the interfaces
  page.
