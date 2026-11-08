# 0341: Give bsb.cached a render stage and a max life

- Status: accepted
- Date: 2026-11-07
- Amends: 0312, 0316

## Context

Apps held a read back from the App Shell by awaiting `navigation()` by hand and
named the long profile with a second `cacheLife("max")` call after
`bsb.cached()`. Next.js takes the smallest `stale` of several calls, so that
call could only shorten an entry (ADR 0312).

## Decision

`CachedOptions` gains `stage` and `life: "max"`. `stage` awaits the gate in
`awaitStage` (`src/next/entry.ts`) before `scopeOf` resolves the context, for
`cached()` and `bootstrap()`. The gate is read from `next/cache` as a namespace
member, so a Next.js build without it loads the library and the option does
nothing. A gate that throws (inside a `"use cache"` scope) is caught and logged
once in development, since `bsb.cached()` normally runs inside that scope.
`"max"` is `MAX_LIFE` in `src/next/cache.ts`; `capToToken` still applies.

## Consequences

`stage` only takes effect when the call runs in the component body, before the
cache scope; inside a `"use cache: private"` function it is skipped. The docs say
so.
