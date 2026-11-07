# 0360: Framework bindings supply init templates and name the server adapter

- Status: accepted
- Date: 2026-11-08
- Amends: 0332

## Context

ADR 0332 left `serverSubpath` and `templates` on `FrameworkBinding` as
contract fields that nothing read, so a registered framework could declare
files and a server adapter and `init` ignored both.

## Decision

- `frameworkFiles(binding, context)` calls `templates` with the source
  directory, the generated module, the `.ts` extension flag and `serverImport`,
  the `better-supabase/<serverSubpath>` specifier (or `undefined`).
- `init` writes the files of the framework it detects, through the same
  create-once plan as the integration templates, so an existing file stays the
  app's.
- `init` prints `Server adapter for <name>: <specifier>.` when the binding has
  one.
- `frameworkFiles` and `serverImportOf` are exported from
  `better-supabase/plugins`.

## Not done

The adapter tables (`INTEGRATION_INFO`, `TEMPLATES`) still list the built-in
integrations themselves, and the capability registry does not read bindings.
Both stay separate lists until the built-in adapters move into bindings.

## Consequences

A third-party framework gets its `init` files and a server adapter hint from
its binding alone. The built-in bindings declare neither field, so their
output does not change.
