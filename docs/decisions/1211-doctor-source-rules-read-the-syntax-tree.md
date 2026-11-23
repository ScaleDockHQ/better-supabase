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

[ADR 1220](1220-remaining-doctor-text-rules-read-tokens.md) moved the SQL and
dotenv rules and the BS226 and purge scans that this ADR first left on text.
What still reads text is listed there.

Behavior that changed: BS260 reports only imported function and type names,
BS511 and BS621 count dynamic imports, BS508 and BS510 match identifiers, and
the shim check ignores comments.

## Consequences

A rule added later reads the tree unless its input is SQL or dotenv.
