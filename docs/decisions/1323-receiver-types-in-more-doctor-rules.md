# 1323: More doctor source rules check receiver types

- Status: accepted
- Date: 2026-11-23

## Context

BS609, BS634 and BS635 asked TypeScript for a receiver's type. BS210, BS219,
BS227 and BS351 also match on a receiver name (`db.x.count()`,
`q.contains(...)`) and reported a `Map` or a `Set` that has the same method.

## Decision

`RECEIVER_RULES` in `src/cli/doctor/receiver-types.ts` lists BS210, BS219,
BS227, BS351, BS609, BS634 and BS635. A finding is dropped when
`receiverIsNotClient` finds a type that is provably not a client. Without the
tier the rules keep matching names, and the run adds one info finding.

## Alternatives considered

- Every name-matching rule: the SQL and dotenv rules have no receiver.

## Consequences

Doctor opens the tier for one more set of rules, only when one of them runs.
