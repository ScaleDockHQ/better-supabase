# 0314: Mark key pages `instant` and lock each loading sequence in a test

- Status: accepted
- Date: 2026-11-07
- Amends: 0310, 0313

## Context

The three specs in `tests/instant.spec.ts` assert the navigation lock through
the library's `expectInstant`. They do not say which content is visible before
uncached work resolves, and no page told Next.js to validate its navigation.

## Decision

- The customers list, a customer record page and the login page export
  `instant = true`, so `next dev` surfaces any code that would block their
  navigation.
- `tests/loading-sequences.spec.ts` calls `instant()` from `@next/playwright`
  directly and checks, under the lock, what is visible and what is absent, then
  what streams in after it: the customers heading before the rows, a customer's
  back link before its version history and timeline (gated by ADR 0313), and the
  sign-up link from the static sign-in form. It uses `getByRole` and `getByText`
  locators, which only match visible text, with `toHaveCount(0)` for absence.

## Consequences

The spec needs a `next build`, the testing API and the seeded local stack, so
CI runs it where the integration job runs; it was written and type-checked but
not run on the machine that made it, because the native Supabase stack belongs
to another worker. Other pages join by adding `export const instant = true` and
a test.
