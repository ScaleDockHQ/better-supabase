# 1256: App-wide actions, client defaults and declared tags

- Status: accepted
- Date: 2026-11-26

## Context

CentraKit wraps `bsb.action` in `tenantAction` (299 lines, 517 actions) because
its outcome carries a translated `message`, `fieldErrors` and a `code`, it has
guards every action shares, and it returns `better-result` values. Its 390
client call sites repeat the same toast in `startTransition`.

## Decision

`createNext({ actions })` takes three optional functions.

- `envelope(outcome)` returns fields merged into every outcome, success or
  error, after the action's own `result`. `createNext` infers their type, and
  each action returns `ActionResult<O> & Ex`. The plan named this option
  `result`; it is `envelope` because it adds fields instead of replacing the
  outcome, which the per-action `result` already does.
- `guard(tenant, ctx)` runs before the action's own `guard` and refuses the
  call with an error.
- `from(value)` turns a value the library does not know (a `better-result`
  `Result`) into `{ ok, data }` or `{ ok: false, error }`; `undefined` leaves
  the value to the default handling.

`ActionDefaultsProvider` in `better-supabase/react` gives `useAction`,
`useOptimisticAction` and `useActionForm` app-wide `onSuccess` and `onError`
callbacks. They receive the whole outcome, so the envelope's fields are there,
and run only for a call that has no callback of its own. The provider takes
functions, so it renders in a Client Component.

`defineTags(["customers"])` returns one tag function per table. A reader and an
action name the same entry through it. The plan had `gen` emit these. They are
a runtime function of the table names because `gen` output changes every
generated file and snapshot, and `tableTags` already defines the tag format.

## Consequences

The envelope is typed on `bsb.action` and `bsb.blockAction`. `withContext`
actions return the plain `ActionResult` type but carry the fields at runtime.
