# 0363: Run workerSafe generators on a worker pool

- Status: accepted
- Date: 2026-11-08
- Amends: 0330

## Context

ADR 0330 defined `workerSafe` and the `structuredClone` check a pool needs, and
left the pool undone because the generators still ran on the main thread. Part 7
of the plan asks that `gen` run generators declared `workerSafe` on worker
threads, with the output of a single thread.

## Decision

- A `Generator` may carry `module: { specifier, export }`. The six built-in
  generators declare theirs (`better-supabase/generators/zod` and so on). A
  worker imports the module, calls the export with the generator's `options`,
  checks that the result has the same `name` and `version`, and runs `generate`.
  A `workerSafe` generator without a `module` runs on the main thread, as does a
  closure from the config file.
- `src/cli/generators/pool.ts` starts up to four workers (cores less one), gives
  each the input once through `workerData`, hands out jobs as they become idle,
  and returns the outcomes in job order. A worker that throws in `generate` is an
  outcome; a worker that fails to start or exits early is a `PoolError`, and
  `runGenerators` then generates on the main thread. The worker is its own build
  entry, `cli/generator-worker`, and `node:worker_threads` is imported lazily, so
  the CLI's start-up path and the runtime entries are unchanged.
- `runGenerators` looks up the cache for every generator first, sends the
  uncached eligible ones to the pool (when there are two or more), runs the
  others on the main thread, and then merges the files in config order, with the
  same path and capability checks as before. The first failing generator in
  config order is the error `gen` reports, whichever finished first.
- The pool engages for a schema of 1500 tables or more. `testGeneratorPlugin`
  builds the generator again from its `module` and compares the files.

## Measured

The six built-in generators, no cache, Node 24, on the fixture schema repeated
(from source, so a worker also compiles TypeScript; a built worker starts
faster):

| Tables | Main thread | Four workers |
| ------ | ----------- | ------------ |
| 380    | 33-49 ms    | 56-85 ms     |
| 1900   | 134-238 ms  | 116-132 ms   |

The generators are cheap, so starting threads costs more than they save until
the schema is far larger than any app's today. Hence the threshold, and no
config key for it: a knob would only invite turning on a slower path.

## Not done

A user-facing switch (`gen.workers`), and a measure of a generator that is slow
on its own (a third-party one that formats with a slow tool). Both wait for a
case where the pool pays.

## Consequences

Output does not depend on the pool: a test compares the files from workers and
from the main thread, with completion order reversed. A third-party generator
opts in by adding `module`, and `testGeneratorPlugin` proves it rebuilds.
