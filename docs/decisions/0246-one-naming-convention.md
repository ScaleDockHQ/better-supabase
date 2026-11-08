# 0246: One naming convention from api/naming.json

- Status: accepted
- Date: 2026-11-06

## Context

ADR 0130 fixed the block convention and the Naming page fixed the glossary,
and both were applied unevenly: `Settings`, `Config` and `Options` name the
same kind of type, `Failure` and `Error` both name errors, environment
variables use `BSB_` and `BETTER_SUPABASE_`, and one subpath has a `/`
where the others have a `-`. Nothing checked any of it.

## Decision

`packages/better-supabase/api/naming.json` holds the rules (words, the
environment prefix with the platform's own names, banned type suffixes, the
subpath shape) and the rename table (`from`, `to`, `kind`, `since`).
`scripts/check-naming.ts` runs in `pnpm verify`. It fails when a renamed name
returns anywhere in the library, tests, apps, skills or scripts, when code reads
an environment variable outside the prefix, when an exported type ends in a
banned suffix, when a doctor code is lower case or a subpath breaks the shape.

Violations the repo has not renamed yet are an explicit allowlist in the same
file, and the check fails when an allowlisted name stops violating, so the list
only shrinks. `codemod naming` applies the table to code, subpaths and
environment names, and writes one hand migration of `alter ... rename`
statements (`-- destructive: reviewed`) for renamed tables, columns and
policies of installed blocks, so no data moves. Doctor BS260 reports a source
file that still uses an old name.

Renamed in this step: `buildJsonSchema` is `toJsonSchema`, `buildApiModel` is
`defineApiModel`, `createRuleSink` is `automationSink`,
`workItemRecurrenceSink` is `taskRecurrenceSink`, `SessionEntryConfig` and
`GuardEntryConfig` are `*Options`, seven `*Failure` types are `*Error`,
`AgentPassthroughSettings` is `AgentPassthroughOptions`, the four `BSB_*` and
hook secret variables carry `BETTER_SUPABASE_`, and `ai-sdk/workflow/react` is
`ai-sdk/workflow-react`.

## Alternatives considered

Renaming everything at once breaks the generated SQL goldens and every
installed app in one step. A lint rule per convention has no rename table to
drive the codemod.

## Consequences

`Args`, `Settings` and `Failure` types are renamed except 15 whose `Options`
or `Error` name another type already holds: `ActionArgs`, `BlockActionArgs`,
`CliArgs`, `CursorPageArgs`, `DoctorArgs`, `HookArgs`, `ListArgs`,
`ReactRouterArgs`, `RequestArgs`, `RpcArgs`, `SearchArgs`, `TableArgs`,
`AuthFailure`, `Args` and `Settings`. They stay in the allowlist until each
gets a name from its noun. `defineSupabase` is `createSupabase` and the Svelte
`getBetterSupabase` is `betterSupabase`.

Still open, and owned by the later stages: the config keys (`tenant`,
`recordTypes`, `adapters`, `dir`, `file`, `entry`, `key: false`), the generated
file names (they move with the Part 6 layout), hint codes, event verbs, the CLI
flags (they move with the Part 8 grammar), the remaining subpaths and block
names, and the SQL object names with their rename migrations and the pgTAP
catalog test. The SQL renames need the TypeScript clients that still use
`WorkItem`, `Engagement` and `Rule` renamed first (ADR 0245).
