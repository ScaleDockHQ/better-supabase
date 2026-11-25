# 1234: Read record flags from the permissions the app already holds

- Status: accepted
- Date: 2026-11-25

## Context

`bsb.record(type).load()`, `.timeline()` and `recordListServer` compute their
`can` flags with `my_permissions({ tenant, keys })`, even when the token or the
shell bootstrap (ADR 0524, ADR 1233) already holds the caller's keys. Each
private cache scope repeats the call. The warm render of `/customers/[id]` in
the Next.js example made six of them (11 calls, 3 waves) after the shell
bootstrap.

## Decision

`NextOptions.heldPermissions` returns the caller's full keys in the active
tenant without a database call, or `null`. The record loaders use it first and
call `my_permissions` only when it returns `null` or `undefined`. The example
passes `getPermissions`, which reads the token claim, then the shell entry.

## Alternatives considered

- Pass the keys through each `bsb.record(type, options)` call: 47 call sites
  in the example.
- Read the claim inside the library: it needs the app's permission catalog,
  which the library does not hold.

## Consequences

The six calls per render are gone (fetch log: 0 `my_permissions` across the
harness run). The returned set must be complete: a set that omits a key the
record type checks denies it. The count in the response header goes up on
`/customers/[id]` because the sections now start before the header is written;
the database round trips per render drop.
