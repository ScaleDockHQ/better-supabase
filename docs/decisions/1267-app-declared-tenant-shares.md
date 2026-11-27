# 1267: App-declared tenant shares

- Status: accepted
- Date: 2026-11-26

## Context

`bsb.kept` and `bsb.remote` with `share: "tenant"` share one cache entry between
callers who hold the same grant in a tenant. The read still runs under the
caller's RLS (ADR 1221). Which tables and functions qualify was decided only by
the authorization provider's `tables` and `sharedFunctions`. An app table the
provider does not know about had no way to join that list.

`bsb.shared` (ADR 1255) is a different read. It checks the permission outside
the cache and then runs the app's function, which chooses its own client. It
does not pass the read through RLS, so it does not replace a shared fill.

## Decision

The config key `shares` takes `tables` and `functions` in the same shape as the
provider's. `resolveShares` merges the two. The provider's entry wins when the
app repeats it, and that repeat is a restated default (BS427). An entry that
names the same table or function with different settings is not written: gen
keeps the provider's entry and doctor reports BS652. Gen, doctor and the
testing kit read the merged lists. The runtime still reads only the generated
meta.

## Alternatives

- Keep the lists on the provider only. Every app table would need a provider
  release.
- Treat a disagreement as the app winning. Two places would then silently
  override each other.

## Consequences

An app declares `shares.tables` with `share: "tenant"` for a read that RLS
still checks. A function listed only in `shares.functions` is accepted when
its tables are shared per tenant by either list. `SHARE_REFUSED` names both
places.
