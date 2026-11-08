# 0330: Run generators as plugins at apiVersion 2, with a public kit

- Status: accepted; supersedes the generator part of 0292's "Not done"
- Date: 2026-11-07

## Context

Part 12 of the plan asks that every built-in generator use only the contract a
third party gets. The v1 `Generator` received the resolved config, an
`importPath` closure and an absolute `output`, and marked its validators file
with a `validators: true` flag that `gen` found by scanning the files. None of
that survives `structuredClone`, so a generator could not be cached on its
input or moved to a worker, and the helpers the built-ins share
(`generators/shared.ts`) were private.

## Decision

- **`apiVersion: 2`** is the only contract. A generator declares `name`,
  `version`, optional `options`, `pure`, `workerSafe`, `provides` and
  `generate`. `resolveConfig` refuses anything else with a message that names
  the change from v1 (`generatorProblem`); there is no dual support (invariant
  10).
- **Plain-data input.** `GeneratorInput` holds `meta`, `introspection`,
  `extras`, `model`, `config` (a `GeneratorConfigView` of output paths, casing
  and `json` overrides) and `imports.runtime`. `importPath` and `output` leave
  the input; `relativeImport` in the kit replaces the closure for the
  project-relative paths a generator already holds.
- **Capabilities.** `provides: ["validators"]` replaces the `validators` flag
  on `GeneratedFile`. The first file of the providing generator is the one `gen`
  imports into the schema. Two generators that provide a capability are an
  error; the zod, valibot and standard-schema generators take `validators: false`
  to write a file without providing it.
- **Cache.** `src/cli/generators/run.ts` runs the generators and caches a `pure`
  generator's files on `(name, version, options, CLI version, hash of the
  input)`. The input hash covers every read, which is stricter than a read set,
  because the input is complete data. A generator without `pure` runs every
  pass and is never cached.
- **Public kit.** `better-supabase/generators` exports `defineGenerator`,
  `relativeImport` and the helpers the built-ins share. The built-ins import
  the kit only; `tests/generators/kit.test.ts` is the boundary rule.
- **`testGeneratorPlugin`** replaces `testGenerator`. It adds checks that a
  `structuredClone` of the input gives the same files (worker safety) and that
  the files survive the JSON round trip the cache makes.

## Not done

A worker pool. `workerSafe` and the clone check are the contract a pool needs,
but the generators still run on the main thread, because the pipeline's stage
split (Part 7) did not land and a worker entry in the CLI build needs it. The
read-set key of the plan is replaced by the input hash described above.

## Alternatives considered

- **Keep v1 beside v2.** Invariant 10 and Part 9 rule out dual support.
- **A read-tracking proxy on the input.** The hash of the whole input costs one
  `JSON.stringify` per pass and cannot miss a read; a proxy would add precision
  nobody has needed yet.

## Consequences

A second `gen` over an unchanged schema skips every pure generator. Third-party
generators are built the same way as the built-in ones, and `gen` tells an
author of a v1 generator exactly what to change. A change to a kit helper is a
breaking change to a public export.
