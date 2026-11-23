# 1211: The doctor source rules read the syntax tree

- Status: accepted
- Date: 2026-11-23

## Context

ADR 1207 moved the cookie and cache rules to the tree. About thirty other
source rules still ran regular expressions over `file.text`, so a comment or a
string that named a call produced a finding.

## Decision

The TypeScript source rules (claims, client barrels, wiring, lite, workflow
builder, edge functions, modules, naming renames, BS210, BS219 to BS227, BS260,
BS351, BS381, BS5xx and BS6xx) read the tree through `src/cli/doctor/tree.ts`
and `module-calls.ts`. Codes, findings and lines stay the same for real code.
Each rule has a case for a comment and a string.

These rules still read text, because their input is not TypeScript: `hooks`,
`dispatch-regression`, `error-codes`, `plain-secrets` and `import-guard` (SQL),
`env` BS501, BS502, BS503, BS506 and BS509 and `vercel-env` (dotenv), the
`scale` purge check, and the `:6543` URL line scan in BS226.

Behavior that changed: BS260 reports only imported function and type names,
BS511 and BS621 count dynamic imports, BS508 and BS510 match identifiers, and
the shim check ignores comments.

## Consequences

A rule added later reads the tree unless its input is SQL or dotenv.
