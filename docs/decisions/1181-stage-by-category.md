# 1181: Name hold, start and expired stages by key or category

- Status: accepted
- Date: 2026-11-22

## Context

`hold.stage`, `claims.startStage` and `claims.expiredStage` took a stage key. Pipelines are editable per tenant and per team, so a key that one pipeline has and another lacks made a hold raise `TASK_HOLD_STAGE_MISSING`, and a claim or expiry skip the move without a sign.

## Decision

Each of the three options accepts a key or `{ category }`, where the category is any category the pipeline defines, custom ones included. The module resolves it through the pipelines helpers `stageByKey` and `stageByCategory`, in `claim_task`, the expiry job, `hold_task` and the guard trigger that releases a hold stage. A malformed value fails at config time with "must be a stage key or { category }". A new live doctor rule, BS245, lists each live pipeline of the `task` subject type that has no live stage for an option that is set, so a missing stage is visible instead of silent. The rule needs a database and reads the pipelines tables through `blockTables`.

## Alternatives considered

Raising on claim when the start stage is missing was rejected: it would stop work for a tenant over a cosmetic move. Creating the missing stage was rejected: pipelines belong to the tenant.

## Consequences

Config that used keys keeps working. A category resolves to the lowest-ranked live stage of that category.
