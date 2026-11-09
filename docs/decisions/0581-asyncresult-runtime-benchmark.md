# 0581: Time AsyncResult against a promise chain in the type bench

## Status

Accepted

## Context

Every repository method returns an `AsyncResult`, a class over a promise whose `then`, `map` and `andThen` each add a promise hop. The type bench gated compile time only, so a change to the class could slow every call without a failing check.

## Decision

`tests/types/perf/bench.ts` has a `runtime` case. It runs 20,000 chains of two `map` steps, an `andThen` and `orThrow`, takes the best of five rounds, and does the same with a bare promise chain. The baseline stores both times in microseconds and their ratio. The check fails when the `AsyncResult` time passes twice the baseline scaled by the TypeScript 6 calibration (with 5 microseconds of slack), or when the ratio grows past one and a half times the baseline plus 0.5.

## Consequences

A slower `AsyncResult` fails the benchmark. The first baseline is 0.09 microseconds for the promise chain and 0.32 for `AsyncResult` (3.4 times). The case adds about two seconds to the bench.
