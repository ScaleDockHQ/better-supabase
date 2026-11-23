# 1186: Config edits go through a document on oxc-parser

- Status: accepted
- Date: 2026-11-22

## Context

The config codemods, `config --prune`, `add`, `remove` and `adopt` edited
`better-supabase.config.ts` with scanners that track brackets and quotes in
text (`code-ranges.ts`, `sql/config-edit.ts`, the regular expressions in
`codemod-prune.ts`). They could not follow an array index, took a comment that
held `export default {` for the config, wrote a syntax error for a shorthand
property and dropped a failed edit without saying so. ADR 1171 made
`oxc-parser` a direct dependency of the CLI so a parser can replace them.

## Decision

`src/cli/config-document` parses the config with `oxc-parser` and edits it as
text splices with `magic-string`. `oxc-walker` supplies the scope tracker that
finds the imports and constants an edit left unused. `magic-string` and
`oxc-walker` are devDependencies the CLI build inlines (`deps.onlyBundle`), so
apps never install them.

`ConfigDocument` finds the config object through the `defineConfig` import
binding (a variable, `satisfies`, `as const`, an alias and the function form
all work), looks up a path with array indexes and a block name in the `blocks`
list, follows a shorthand, an identifier or a spread to its declaration, and
edits there. It detects line endings, indentation and quotes, keeps a comment
with its entry, and removes the declarations an edit left unused. Every edit
returns `done`, `absent` or `review`; a shape it cannot follow returns a review
line and leaves the text alone. The text is parsed again after each edit, so a
splice that writes a syntax error throws before it reaches a file.

The prune, blocks-list, record-types and config-key codemods use it first.
`sql/config-edit.ts` and `sql/remove-edit.ts` now edit the config and the
`lib/blocks.ts` wiring through it. `code-ranges.ts` is deleted: the source
codemods and the doctor scans take their code ranges from `codeRanges()` in
`config-document/ranges.ts`, which reads the parse tree, so a regular
expression, a template literal or JSX text no longer hides code. The prune,
blocks-list, record-types and config-key codemods rewrite through the document
or `rewriteSource`. Of the doctor source checks, only `source-scan.ts` and
`n-plus-one.ts` read the tree when this ADR was accepted; the other source rules
and the naming codemod's environment, hint and event renames still matched text.
ADR 1207 moves part of them and lists the rest.

## Alternatives considered

- Babel or TypeScript's own parser: heavier, and TypeScript's API starts a
  native binary that apps on TypeScript 5 or 6 do not have.
- Keep the scanners and fix each bug: every bug came from the same missing
  syntax tree, so the next shape would break them again.

## Consequences

Codemods fail loudly on a file that does not parse, with the path, line and
column. `oxc-parser` is a native binding, so an install without optional
dependencies cannot run these codemods. `gen` and the runtime never load it.
