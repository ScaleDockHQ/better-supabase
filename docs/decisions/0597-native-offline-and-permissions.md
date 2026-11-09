# 0597: Native offline boundary and a permissions snapshot

- Status: accepted
- Date: 2026-11-09
- Amends: 0344, 0420

## Context

ADRs 0344 and 0420 pause data hooks through `OfflineContext`, and the Next.js
adapter was the only thing that set it. React Native and Vite had the context
and no boundary. A PowerSync reconnect invalidated every `["bsb"]` read,
including rows SQLite was about to refresh itself. The compact bootstrap form
had no on-device cache keyed by `authz_ver`.

## Decision

`OfflineBoundary` in `better-supabase/react/native` takes a NetInfo-shaped
object and sets `OfflineContext`. `nativePermissions` stores the compact
payload in a string store (MMKV) under user, tenant and `authz_ver`, and is
meant to run from `SessionProvider`'s `onAuthzChange`. A PowerSync reconnect
invalidates only tables whose reads ran on the server fallback.

## Alternatives considered

- Importing NetInfo: it would be a required dependency of the native entry.
- Invalidating every key on reconnect: local lists refetch even when SQLite
  already has the rows.

## Consequences

Apps pass their own NetInfo module. A read that never fell back to the server
is left to PowerSync's table change events. A new `authz_ver` misses the
stored snapshot.
