# 1109: Let a same-tenant trigger satisfy BS217

- Status: accepted
- Date: 2026-11-22

## Context

BS217 asks for a composite foreign key so a child row cannot point at another tenant's parent. CentraKit enforces the same rule with a generated same-tenant trigger or an app trigger, and the rule still reported both.

## Decision

A same-tenant trigger, generated or an app trigger that BS398 accepts, satisfies BS217. Where the parent has a unique on `(id, tenant)` an info finding recommends the composite key, because a key also covers rows a trigger skips. The validation-centrakit expected groups no longer list BS116 or BS217.

## Alternatives considered

Keeping the finding for triggers was rejected: it forced a baseline entry for a protected table. Dropping BS217 for tables with a trigger and no unique was rejected because the info finding costs nothing.

## Consequences

Fewer false baseline entries. A trigger that BS398 accepts but that is later disabled is caught by BS398, not BS217.
