# 1207: Codemods and doctor source rules read the syntax tree, and never skip a file in silence

- Status: accepted
- Date: 2026-11-23

## Context

ADR 1186 put the config edits on `oxc-parser`, and its text said the codemods
and the doctor source checks followed. An audit found otherwise: `renameEnvNames`
and `renameQuotedNames` replaced text inside comments and strings, and most
doctor source rules (`wiring.ts`, `hooks.ts`, `env.ts` and others) still match
`file.text` with regular expressions. A codemod that could not parse a file
returned it unchanged with no review line, so a broken file looked the same as
a file with nothing to change.

## Decision

- `renameNames` in `codemod-naming.ts` renames environment variables, hint codes
  and event names through the tree. An environment variable changes where code
  names it (`process.env.NAME`, a key, a binding). A hint code, an event name or
  an environment variable in a string changes only when the whole string is the
  name. Comments never change, and a string that holds a renamed environment
  variable among other words gets a review line. `.env*` files and `turbo.json`
  have no tree and keep a whole-word text rename (`renameEnvFileNames`).
  `Codemod.source` now receives the file path so it can tell them apart.
- `applyCodemod` adds one review line when a script does not parse and no stage
  changed or reported it. `tests/cli/codemod-no-silent-noop.test.ts` runs every
  registered codemod on an unparseable file and fails when one returns it with no
  change and no review line. A codemod without a source stage must be listed in
  that test with the reason, so a new codemod cannot skip the check.
- The session cookie rule (BS412) and the cache rules (BS608, BS610, BS611,
  BS640) read imports, calls, properties and function directives from the tree.
  A comment, a string or a type annotation no longer counts, and findings, codes
  and lines are unchanged for real code.

## Alternatives considered

- Keep regular expressions and strip comments and strings first: that was the
  `withoutComments` approach, and it fails on a regex literal or a nested
  template.
- Move every rule in one change: each rule's tests pin its findings, so moving
  them one family at a time keeps each diff reviewable.

## Consequences

Still on text, and open work: the doctor rules in `wiring.ts`, `hooks.ts`,
`env.ts`, `client-barrels.ts`, `claims.ts`, `dispatch-regression.ts` and the
other files that match `file.text`; the TypeScript import merging in
`codemod-account-calls.ts` and the other source codemods; receiver types beyond
BS609, BS634 and BS635; and `followImports` for `prune` and the other config
codemods (ADR 1188). The SQL regexes in the column, tag and tenant codemods
belong to the schema reader.
