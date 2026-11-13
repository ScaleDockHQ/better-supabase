# 0710: Raise the next-build baselines for the error message provider

- Status: accepted
- Date: 2026-11-13

## Context

ADR 0709 replaces the example's `use-error-message.ts` with
`ErrorMessagesProvider` and `useErrorMessage` from `better-supabase/react`.
The translated kind sentences now live in one client component that the
`(app)` layout and the four auth layouts that load the `errors` namespace
render, and every consumer imports the hook from the react entry instead of a
file of the app. `tests/next-build` fails when a route grows past its
baseline, and the update script only lowers a baseline (ADR 0684).

## Decision

Raise the baselines by the difference between two fresh `next build`s on the
same machine, one of `main` and one of this branch, and keep every other
number. The 110 KB table of hint messages is not in the figures: the provider
loads `better-supabase/blocks/messages` after hydration with a dynamic import,
and a build with a static import measured about 740 first-load entries over
their baselines.

| Baseline                               | Routes                    | Change                                                             |
| -------------------------------------- | ------------------------- | ------------------------------------------------------------------ |
| First load (`baseline.json`)           | every route under `(app)` | median +1,028 B gzip, +1,707 B raw: the provider and its sentences |
| First load                             | `/invite/[token]`         | +19,365 B gzip: the page now reads the react entry's shared chunk  |
| Server chunks (`server-baseline.json`) | 279 route entries         | median +274 B gzip, at most +486 B                                 |

## Alternatives considered

Keeping the hook in the app avoids the growth but leaves every app writing
the same file (EX-1236). Importing the hint messages statically saves the
dynamic import and adds about 30 KB brotli to every route.

## Consequences

The invite page pays for the react entry once; a later split of the entry's
shared chunk would take it back. The next lane that moves a route onto the
provider adds nothing.
