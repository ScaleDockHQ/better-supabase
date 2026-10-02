# 0005: Use Temporal for time values in the public API

- Status: accepted
- Date: 2026-10-02

## Context

The repo standard (1.3) asks libraries to use `Temporal` instead of `Date` for
instants, durations and wall-clock values. The library runs on every WinterTC
runtime, and the core may depend on nothing beyond `@standard-schema/spec` and
the Supabase packages (AGENTS.md invariant 1). Node 24, the minimum supported
Node, and Safari have no native `Temporal`; Node 26, Chrome and Firefox do.
TypeScript 6 and 7 ship the `esnext.temporal` lib; TypeScript 5.9 does not, and
`temporal-polyfill` provides no types of its own (`global.d.ts` is empty).

## Decision

Every time value in the public API is a `Temporal` value. The
`codecs.timestamptz` option takes `'instant'` instead of `'date'`: `timestamptz`
columns decode to `Temporal.Instant` and `timestamp` columns to
`Temporal.PlainDateTime`, because a `timestamp` has no offset and any instant
would invent one. The codec columns are selected with a `::text` cast so
Postgres sends microseconds, which `Temporal.Instant.from` keeps and `Date`
dropped. The `now` options return a `Temporal.Instant`, and jobs, the inbox,
webhooks, storage sweeps and CloudEvents use `Temporal.Instant` and
`Temporal.Duration`. Auth keeps `now: () => number`, since JWT `exp` and `iat`
are epoch seconds and the math stays in milliseconds.

`temporal-polyfill` is an optional peer (`catalog:peers`, `>=1`). The library
never imports it: `src/core/temporal.ts` reads `globalThis.Temporal`, and a call
that needs it while it is missing returns a `DbError` with kind `unexpected`
(500) and a message that names `temporal-polyfill/global`. A new `DbError` kind
would have broken every consumer's exhaustive `switch` over kinds, so the
existing catch-all kind is used. Apps on Node 24 or Safari import
`temporal-polyfill/global` once; it installs only when there is no native
`Temporal`.

The published declarations reference `esnext.temporal`, so consumers get the
types without changing `lib`. `src/core/temporal.ts` carries
`/// <reference lib="esnext.temporal" />`, and because the tsdown declaration
bundler drops reference directives, the `temporal-lib-reference` plugin in
`packages/better-supabase/tsdown.config.ts` prepends it to every `.d.ts` chunk
that names `Temporal.`. The shared tsconfig preset adds `ESNext.Temporal` to
`lib` for the repo's own code.

TypeScript 5.9 leaves the compatibility matrix: `tests/types/ts-5.9` and the
`ts59` catalog are removed. `tests/types/shared/consumer.ts` names
`Temporal.Instant` without the lib, which fails on 5.9 with TS2503 and passes on
6 and 7 through the published reference.

## Consequences

Timestamps keep microsecond precision, and there is no confusion between local
and UTC `Date` getters. It is a breaking change for every caller of the APIs
above and for apps on TypeScript 5.9. Tests need an equality tester, because
Vitest's `toEqual` sees no enumerable keys on Temporal objects and treats any
two of them as equal (`packages/better-supabase/tests/setup/temporal.ts`).
Revisit the polyfill note and the plugin when Node 24 leaves support and when
tsdown keeps reference directives.
