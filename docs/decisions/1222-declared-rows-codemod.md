# 1222: Move config items to rows with a codemod

- Status: accepted
- Date: 2026-11-22

## Context

Apps that already declare option set items, pipeline stages or approval floors in
the config need a way to move them into `supabase/rows` (ADR 1221) without
retyping them, and without leaving the same data in two places.

## Decision

`better-supabase codemod declared-rows` reads the resolved config, so a helper
such as `taskStages(...)` is already expanded, and writes
`supabase/rows/option-sets.sql`, `pipelines.sql` and `approvals.sql` as upserts
into `better_supabase.declared_defaults`. It then removes the moved keys (`items`
and `brands` of an option set binding, `stages` and `brands` of a pipeline
binding, `options.policies` of approvals) from the config file with the config
document editor. It never overwrites a rows file, leaves numbering formats
alone because most are baked into triggers, and prints a review line for an
import the config no longer uses and for running `db rows`.

## Alternatives considered

Rewriting the config in place without rows files: the data would still be code.
Removing unused imports itself: it cannot tell whether another file uses them.

## Consequences

The move is one command and one review. A config that stays as it is keeps
working, because declared rows are optional (ADR 1220).
