# 0633: Correct the provider contract and bound stale JWKS

- Status: accepted
- Date: 2026-11-10
- Amends: 0114, 0520, 0522, 0595

## Context

ADR 0114 keeps the authorization provider contract additive under
`apiVersion: 1`. Two names from that version, `functions.canApprove` and
`approvals.distinctApprover`, were removed while the version stayed 1, and
the strict config schema then rejected a provider that still set them.

ADR 0520 says an older better-supabase ignores the new fields, and that
doctor checks the placeholders of `approverFor` and `managedUsers`. The
schema is strict, so an older release rejects unknown fields. Doctor checked
no template placeholders. Only the testing kit did, and no module reads
`approverFor` or `managedUsers` yet.

ADR 0595 serves a cached JWKS past `cacheSeconds` and keeps it when a
refresh fails, with no maximum age. ADR 0522 caps a Supabase key set at 600
seconds because a revoked signing key keeps verifying until the set is
fetched again.

## Decision

`apiVersion` stays 1. The schema accepts `functions.canApprove` and
`approvals.distinctApprover` and ignores them. Doctor BS409 notes that, and
`isApprover` decides. A provider that wants a field removed waits for
`apiVersion: 2`.

`templatePlaceholderProblems` checks every template the provider sets,
including ones no module renders. The testing kit and doctor BS409 both use
it. An older release still rejects fields it does not know, so a provider
gates new fields by the better-supabase version it targets.

`sharedJwks` takes `maxStaleSeconds`, defaulting to `cacheSeconds`. Past
`cacheSeconds` a caller still gets the cached key set while a refresh runs
in the background. Past `cacheSeconds` plus `maxStaleSeconds` the call waits
for the fetch and returns `JWKS_FETCH_FAILED` when the fetch fails. For a
Supabase Auth key set the two windows together stay within 600 seconds.

## Alternatives considered

- `looseObject` on the provider schema, so unknown fields pass. Rejected: a
  typo in a template name would load and then fail at render.
- Serving a stale key set until the next successful fetch, with no age
  limit. Rejected: an unreachable issuer would keep a revoked key verifying.
- Waiting on the issuer as soon as `cacheSeconds` ends. Rejected: that drops
  the stale-while-revalidate behavior ADR 0595 added.

## Consequences

A provider written for the removed names loads on this release. Doctor
reports a placeholder a template does not take before SQL render throws.
A Supabase key set is never served for longer than 600 seconds, and a failed
refresh past the stale window is an error instead of a silent success.
