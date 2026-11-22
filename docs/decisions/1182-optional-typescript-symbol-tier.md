# 1182: An optional TypeScript 7.1 symbol tier

- Status: accepted
- Date: 2026-11-22

## Context

`oxc-parser` (ADR 1181) reads one file. Some edits depend on what a name
refers to in another file: renaming an export and every import of it, finding
the receiver type of a call that doctor flags as a round trip, or following a
config value that is imported from another file. TypeScript 7.1 ships
`typescript/sync`, a language service API over its native process.

## Decision

`src/cli/typescript-symbols` opens that API from the TypeScript the app has
installed (`createRequire` at the project root), after reading its version. It
needs 7.1 or newer. It returns `references` (every use of the identifier at an
offset, across files) and `declaration`. It is typed structurally and loaded
through variable specifiers, so the published code never imports `typescript`.

Without the tier, `openSymbolTier` returns a reason and never throws. Every
codemod then runs per file with the `oxc-parser` path and lists the places a
symbol leaves its file as review lines.

`typescript` becomes an optional peer with the floor `>=5.0.0`: the tier checks
the version itself, so an app on TypeScript 5 or 6 sees no peer warning. The
tier is tested against the 7.1 install in `tests/types/ts-7.1` and sits in
"Pre-release pins" until 7.1 is stable.

## Alternatives considered

- Require TypeScript 7.1 in the peer range: warns every app on an older
  TypeScript for a feature that only some edits use.
- Bundle `typescript`: it is a native binary and the output would depend on its
  version.
- Resolve symbols with `oxc-parser` alone: it cannot follow an import to its
  declaration through re-exports and path aliases.

## Consequences

The tier is the base for cross-file renames and receiver-type rules, which ADR
1183 wires in. Starting the TypeScript process costs
startup time, so the CLI opens it only for an edit that asks.
