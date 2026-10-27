# 0110: Keep flag revisions in Postgres and draw splits from a second bucket

- Status: accepted
- Date: 2026-10-27

## Context

The flags block stored one definition per flag and overwrote it on every
save. Hosted flag services keep a change history, roll a percentage up on a
schedule, split a rollout between variants and share targeting segments
across flags. Apps on better-supabase asked for the same, and the Flags SDK's
Flags Explorer wants a discovery route outside Next.js and overrides on the
OpenFeature path. The block evaluates in SQL (`evaluate_flag`) and in
TypeScript, so every rule has to give the same answer in both.

## Decision

`save_flag(key, definition, message)` writes the definition and a row in
`flag_revisions` with the acting user and the message; `restore_flag` saves
an earlier revision again as a new one. `rollout_schedule` is a list of
`{ at, percentage }` steps that `flag_rollout_percentage` reads at evaluation
time, so no job has to run when a step starts. `rollout_variant` becomes
`rollout_variants`, a weighted split. The rollout percentage uses the
existing bucket of the flag key and target; the split uses a second bucket
over the cumulative weights, so raising the percentage never moves a target
to another variant. `flag_segments` holds named rule sets that a rule names
in `segments`. The `from: 3` upgrade step moves a stored variant into a split
of weight 100.

On the Flags SDK side, `flagsDiscoveryHandler` serves discovery from any
fetch handler, and `explorerOverrides` reads the overrides cookie with a
`decrypt` the app passes in, because `flags` is an optional peer that the
runtime entry must not import.

## Alternatives considered

- A doctor check for definitions that drifted from the declared flags. Flags
  Explorer already shows drift hints from `getProviderData`, and `flagDrift`
  covers tests, so a check would only repeat them without a running app.
- A scheduler that rewrites `rollout_percentage` at each step. It needs a
  cron and loses the plan once a step ran; reading the schedule at
  evaluation time keeps the history in one row.
- One bucket for percentage and split. Growing the rollout would then move
  targets between variants.
- Lazily importing `flags` to decrypt the cookie. It adds a lazy load to a
  runtime entry for one call the app can pass.

## Consequences

Every save costs one more insert, and `flag_revisions` grows with each
change and is never pruned by the block. `rolloutVariant` is a breaking rename, which
the 0.32 codemod lists for review. Rules gain `segments`, so the TypeScript
and SQL evaluators must stay in step; the integration test checks both.
