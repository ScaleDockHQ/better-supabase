# 1252: Interrupts end a private cache render

- Status: accepted
- Date: 2026-11-26

## Context

The tenant scope helpers (`bsb.auth`, `bsb.tenant`) refuse a request by calling
`interrupt(error)` from `better-supabase/next`, which throws Next.js's
`notFound()`, `forbidden()` or `unauthorized()`. The reads they guard run inside
`"use cache: private"`. Whether Next.js 16.4.6 ends the render with the
interrupt from inside that scope, on a render and on a prefetch, was not
confirmed.

## Decision

The helpers throw. The fixture at
`apps/examples/nextjs/src/app/[locale]/(public)/status/probe/[kind]` throws each
interrupt from a `"use cache: private"` function behind a `<Suspense>` boundary,
and `apps/examples/nextjs/tests/interrupts.spec.ts` runs it against a production
build:

| Interrupt        | Render                                  | Prefetch then navigation      |
| ---------------- | --------------------------------------- | ----------------------------- |
| `notFound()`     | `NEXT_HTTP_ERROR_FALLBACK;404`, noindex | fallback shown, no page error |
| `forbidden()`    | `NEXT_HTTP_ERROR_FALLBACK;403`, noindex | fallback shown, no page error |
| `unauthorized()` | `NEXT_HTTP_ERROR_FALLBACK;401`, noindex | fallback shown, no page error |

`createNextConfig` already sets `experimental.authInterrupts`, which `forbidden`
and `unauthorized` need; without it both fall back to `notFound()`. The
guarded content never reaches the page. The HTTP status is 200 when the
interrupt happens behind a `<Suspense>` boundary, because the response has
already started; the page carries the fallback and `noindex`.

The typed refusal with one `bsb.refuse(scope)` call in the page, which the plan
named as the fallback, is not needed.

## Consequences

Scope helpers refuse by throwing, and pages need no refusal call. An app that
wants a real 403 status places the guarded read outside a `<Suspense>` boundary.
