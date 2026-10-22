# 0067: Votes are reactions, and scores come from tenant-editable models

- Status: accepted
- Date: 2026-10-22

## Context

Apps ask for two related things. Ideas boards, forums and changelogs want up
and down votes with a score per record. CRMs and customer success tools want
a number per record that says how promising a lead is or how healthy an
account is, recomputed when the record changes, with the reasons visible.

Votes look like reactions: one per actor and subject, under the subject's
read rules, counted per subject. A separate votes block would duplicate the
subject checks, the realtime topic and the custom-mode table. Lead scoring
and health scoring look like two features, but both are "add points for
conditions and weighted numbers, then name the range", and the rules block
already has a filter tree over a synced field catalog that SQL evaluates.

## Decision

Reactions gain `kind` (`emoji` or `vote`) and `value`. A vote is a row with
`kind = 'vote'` and `value` 1 or -1, one per actor and subject, and a trigger
keeps `reaction_scores` (score, up, down) per subject so lists can sort by
score in SQL. The module goes to version 2; its upgrade fills `kind` and
`value` for existing rows. `reaction.added` and `reaction.removed` fire for
votes too, with `kind` and `value` in the payload. That is the breaking
part: consumers that meant emoji filter on `kind`.

A new `scores` block keeps score models per organization: a subject type,
rules (a rules filter tree worth points), metrics (a number field or the
vote score, times a weight, with a cap) and bands. Saving changed rules,
metrics or bands raises the model's version and stores the definition.
`compute_score` takes the record's fields from the caller, as `rule_run`
does, evaluates the rules with `rule_matches`, and writes a new current
score with its breakdown only when the score, band or model version changed,
emitting `score.changed`. Older scores stay as history. Lead scoring and
health scoring are models, not code.

## Consequences

- Scoring runs only in SQL. There is no TypeScript evaluator, because the
  caller can't see the vote scores and a second evaluator would have to stay
  equal to the SQL one. Apps compute from a Server Action or an outbox sink.
- The module never reads the app's tables; the caller passes the fields, so
  a stale caller writes a stale score until the next compute.
- Recomputing an unchanged record is a no-op, so apps can compute on every
  change without growing the history.
- Custom-mode reactions tables need the two columns and `kind` in their
  unique key; the 0.13 to 0.14 guide says so.
