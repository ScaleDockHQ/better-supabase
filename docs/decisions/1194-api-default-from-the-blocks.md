# 1194: Set sql.api from the blocks and compare api entries by form

- Status: accepted
- Date: 2026-11-22

## Context

CentraKit writes `api: "api"` on most blocks. `database.sql.api` is the default
for that key, but the config kept 40 entries that repeat it, and doctor reported
only an entry that was byte-equal to `sql.api`. A block written as
`{ schema: "api" }` is the same thing, and it was never reported. Setting
`sql.api` by hand is not a pure win: a block with no `api` entry would start
writing wrappers under the new default.

## Decision

- `apiMatches` in `config/api-default.ts` decides whether a block's `api` equals
  `sql.api`: the same schema as a string, or as an object with no `functions`
  list. `resolveConfig` uses it for `restatedDefaults`, so BS427 and
  `codemod config --prune` report `{ schema: "api" }` too.
- An object with a `functions` list is never equal here. The render probe
  decides whether the list names every function, because that needs the module
  SQL.
- `ResolvedConfig.blockApis` keeps each instance's `api` entry as written.
  `suggestSqlApi` picks the schema that more than half of the blocks name
  without a list (and at least two blocks), when the config sets no
  `sql.api`.
- `codemod config --prune` writes `database.sql.api`, removes the matching
  entries and adds `api: false` to each block with no entry. It keeps the edit
  only when the files render the same as before, and leaves a review line when
  it cannot edit a block in place (a name in the blocks list that is a bare
  string, for example).

## Alternatives considered

- A doctor finding for the suggestion: BS427 reports entries the render does not
  need, and the suggestion is a choice between two spellings, so it stays in the
  codemod.
- Suggest the most common schema at any share: it would add more `api: false`
  entries than it removes.

## Consequences

An app with three of four blocks on `api` loses three entries and gains one
`api: false`. An app whose blocks disagree is left alone. The render proof
covers a block the config file does not list (a dependency a preset adds): the
edit is refused when that block would gain wrappers.
