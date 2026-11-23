# 1209: The symbol tier follows imports in the config codemods

- Status: accepted
- Date: 2026-11-23

## Context

ADR 1188 let `codemod config` follow a config value imported from another file.
The other config codemods (`prune`, `declared-rows`, `adopt-names`,
`extra-columns`) edited only the config file, so an entry in an imported value
stayed. Import merging was written by hand in `codemod-account-calls.ts`.

## Decision

- `followImports` results are shared through `openImports`, `ownerOf` and
  `changedFiles` in `src/cli/config-document/follow.ts`. The four codemods
  remove from the file that owns the value and return it as a planned file. A
  review line says the render check covers only the config file.
- Without the tier (below TypeScript 7.1) each codemod works on the config file
  and lists the imported values, as before.
- `addNamedImports` in `src/cli/import-edits.ts` is the one import merging
  implementation. The TypeScript 7.1 `getImportEditsForSymbols` was tried: it
  needs symbols from a program that already contains the module, it places the
  import at the top of the file, and per-file codemods get no tier. The oxc
  helper gives the same output with or without the tier.
- `codemod-same-tenant.ts` and `codemod-table-tags.ts` do not follow imports:
  they address array indexes, and stream A owns their SQL reading.
  `codemod-table-modules.ts` and `codemod-server-imports.ts` keep their own
  import logic because their semantics differ.

## Consequences

Edits in a followed file are not render-checked, so the review line asks for
`gen --check`. The tier stays optional.
