# 1250: get is the read verb

- Status: accepted
- Date: 2026-11-25

## Context

The public API had one `get*` export in 4,016 values, against 8 `load*` and 14
`read*` functions, and the CLI had 21 `load*` and 51 `read*` functions. The same
meaning had three spellings, and generated code (`load<Name>SearchParams`,
`tableLoaders`, `loadFunctions`) followed the old spelling. The naming page
already says reads are `get` and hooks are `use`.

## Decision

Reads are `get*` and hooks are `use*` everywhere. `loadConfig`, `loadProject`,
`loadSnapshot`, `loadEnv`, `loadJsonPath`, `loadBindings`, `loadMyWork`,
`loadTimeline` and the public `read*` functions become `get*`. The record
binding member `load` becomes `get`, so `bsb.record(...).load` is
`bsb.record(...).get`. `tableLoaders` and `loadFunctions` on the schema meta
become `tableGetters` and `getFunctions`, and the nuqs loader is
`get<Name>SearchParams`. Each public rename is a `function` row in
`api/naming.json`, so `better-supabase codemod naming` renames them in apps.

Four groups keep their name, listed with a reason under `verbs` in
`naming.json`: factories around `fetch` (`fetchTransport`,
`fetchSmartConfiguration`, `fetchRouteOptimizer`), parsers that compute from an
argument (`readValue`, `readLine`), concept names (`readSetTables`,
`readPolicy`, `readOnly*`), and `readStdin`. Private helpers that collide with
an existing `get*` in the same file keep their name too; the example app's
private `load<Name>` helpers sit under the `verbs` list until generated queries
replace them.

`scripts/check-naming.ts` fails on an exported `load*`, `fetch*` or `read*`
function outside the list, and fails when a listed name stops existing, so the
list only shrinks.

The CLI flag spellings (`--dir`, `dev stack ls`, `--format`) are not changed
here; they need the moved table and a migration row each and go in their own
change.

## Alternatives considered

- Keep `load` for async reads. It leaves two verbs for one meaning and the
  codemod could not tell them apart.
- Text replace. It hits unrelated words, so the renames were done per symbol
  with the TypeScript rename refactor, and the collisions were left alone.

## Consequences

Callers rename with the codemod. The example's `getX` wrappers around private
`loadX` helpers stay until PR 5 removes `Loaded` and `settle`.
