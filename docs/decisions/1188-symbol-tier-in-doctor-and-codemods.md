# 1188: Use the symbol tier in doctor and the codemods

- Status: accepted
- Date: 2026-11-22

## Context

ADR 1186 moved the config edits and part of the codemods and doctor source
checks onto the parse tree (ADR 1320 records how far). A parse tree reads one
file, so three cases stayed by hand or
by name: the N+1 and round-trip rules matched a receiver by its name (`db`,
`userService`), a renamed export that an app re-exports left its importers
broken, and a config value imported from another file could not be edited.
ADR 1187 added an optional TypeScript 7.1 tier for exactly these questions and
left the wiring open.

## Decision

Each case asks the tier and has a fallback that says why it did not.

- **Receiver types.** BS609, BS634 and BS635 call `typeOf` on the receiver of a
  read (`src/cli/doctor/receiver-types.ts`) and drop it when TypeScript types it
  as a plain collection or primitive (`Map`, `Set`, arrays, `string`). Any other
  type, and a receiver the checker cannot resolve, keeps the finding, so the
  tier can only remove false positives. `doctor` opens the tier only when one of
  these rules runs and closes it after the run. When the tier is off, a run that
  reports one of the rules adds one info finding that names the reason.
- **Cross-file renames.** `codemod naming` finds `export { old } from
  "better-supabase"` in the app (`codemod-reexports.ts`), asks `references` for
  every use of the name, and renames the importers in the files it scans. A
  location outside the scanned files (the declaration inside better-supabase) is
  not edited. Without the tier the re-export gets a review line that says its
  importers were not changed.
- **Imported config values.** `ConfigDocument` lists the imported names the
  config uses as a value or a spread, with the config path each sits at.
  `followImports` resolves each through `declaration` and opens the declaring
  file as a document rooted at that value. `codemod config` removes a `columns`
  entry from that file when the config does not hold it. Without the tier, or
  when a name does not resolve, a review line names the imported values.

The tier is opened by the commands that use it (`doctor`, `codemod naming` and
`codemod config`) and passed down as `ProjectSymbols`: the open tier and its
root, or `{ skipped: reason }`. No rule or codemod opens it on its own.

## Alternatives considered

- Resolve imports in the codemods by path: cannot follow path aliases,
  re-exports or a barrel, which is the case that breaks.
- Treat an unresolved receiver as not a client: would hide real findings
  whenever the project does not type-check, so the tier only removes a finding
  on a positive answer.
- Open the tier for every command: it starts a native process, which costs
  startup time for commands that never ask.

## Consequences

An app on TypeScript 7.1 or later gets fewer false N+1 findings and complete
renames. Everyone else keeps the name-based behavior and sees why a check was
not made. The tier reports paths in the case the disk's TypeScript host uses, so
callers match them against scanned files by their real path. Only BS609, BS634
and BS635 use receiver types, `followImports` applies to `codemod config`
`columns` entries only, and `prune` and the other config codemods edit the
config file alone. Imports a codemod adds are still merged by hand
(`codemod-account-calls.ts` and others). ADR 1320 lists these as open work.
