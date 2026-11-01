# 0192: Berlin Group XS2A is a `BankFeed` adapter over fetch

- Status: accepted
- Date: 2026-11-01

## Context

ADR 0153 defined the `BankFeed` port. Most European banks expose NextGenPSD2 XS2A.

## Decision

`berlinGroupFeed` in `better-supabase/blocks/banking` lists accounts and reads booked transactions with the consent id, follows `_links.next` on the bank's origin only and maps errors to `Result` errors. Pin `berlinGroupXs2a` is 1.3.12. Consent creation and strong customer authentication are not run.

## Alternatives considered

Per-bank adapters (rejected: the framework is the shared part). An aggregator SDK (rejected: nothing bundled).

## Consequences

Banks with custom message signing or dialect differences pass `headers` or use their own feed.
