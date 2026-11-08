# 0261: Remove refused config entries with a codemod, and report them in doctor

- Status: accepted
- Date: 2026-11-07
- Amends: 0258

## Context

ADR 0258 makes the render refuse a `null` entry for a column its view lacks and a
tenant entry that repeats `sql.tenantColumn`. An existing config that holds such
entries fails at render time, and the message names one entry at a time.

## Decision

`viewColumns` collects the redundant nulls (`ViewColumns.redundant`); `viewColumnsOf`
throws the first one, and `redundantNulls(layout)` returns them all. The
`config` codemod (`src/cli/codemod-config.ts`) removes them and the repeated
tenant entries from the config source by brace matching on `blocks.<name>.columns.<table>`,
so a name in a string or a comment stays. Doctor BS379 reports the same entries
as errors and names the codemod. Both read the view columns from the same places
as the render: `ownLayout` in the codemod, the snapshot in doctor.

## Alternatives considered

A codemod that also removed `null` entries for tables the app owns would change
what the block adds to those tables (ADR 0258), so it stays out. A static scan of
the config can't know a view's columns, so the codemod loads the layout.

## Consequences

An app upgrades with `better-supabase codemod config` and no hand edits. The
CentraKit dry run is the same shape as the validation fixtures; its tables are
tables, so it holds no refused nulls.
