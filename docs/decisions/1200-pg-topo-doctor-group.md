# 1200: pg-topo is a doctor group that needs no database

- Status: accepted
- Date: 2026-11-22

## Context

pg-delta orders declarative files with pg-topo, and a file that does not parse,
a statement that uses an object nothing creates, or a cycle shows up only when
`db diff` fails in the shadow database, which needs a running stack. pg-topo is
a direct dependency since ADR 1171, and its analysis is pure.

## Decision

Doctor runs `analyzeAndSort` over the files under the declarative schemas
folder in every project, with no database (`src/cli/doctor/pg-topo.ts`). Five
rules map its diagnostics: BS720 (parse error), BS721 (unresolved dependency),
BS722 (duplicate producer), BS723 (cycle) and BS724 (invalid annotation).
pg-topo is advisory, so BS721 skips what the platform or an extension supplies
(roles, extensions, languages, the platform's schemas, constraints that belong
to a missing table, and unqualified functions, which pg-topo reads as
`public.<name>`). The message tells the reader to add a `-- pg-topo:provides`,
`depends_on` or `requires` annotation when dynamic SQL is the cause. The module
loads on first use with a skip when it is missing (invariant 12).

## Consequences

A broken schema file fails `doctor` offline, before the stack starts. A false
positive has a documented escape (the annotation), and the rules are warnings
except for a file that cannot parse and an annotation that cannot be read.
