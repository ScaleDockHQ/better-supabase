# 0901: Declare a retention class and legal hold per entity

- Status: accepted
- Date: 2026-11-14

## Context

Retention and legal hold exist in `data-lifecycle`, `drive` and `audit` only
(EX-1311). `data-lifecycle` already keys policies by a retention kind.

## Decision

`EntitySurface.retention` names a retention kind (`audit`, `outbox`, `trash` or
the app's own) and `EntitySurface.legalHold` is `true` when a hold on that kind
stops the entity's purge. `subjectAccessPlan` carries both per step, so an
erasure sees which rows a hold protects. `field_history`,
`data_subject_request` use `audit`; `consent` declares `legalHold`.

## Alternatives considered

A per-entity interval: it would fork the policy that `retention` already stores
per tenant and plan.

## Consequences

One policy applies to every entity of a class. Entities of other blocks adopt
the field as lane I and the block owners reach them.
