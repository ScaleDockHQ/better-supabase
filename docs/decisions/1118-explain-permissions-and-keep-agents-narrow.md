# 1118: Explain permissions and keep agents narrow

- Status: accepted
- Date: 2026-11-21

## Context

An agent refused by the access model should be able to say why, and the plan assumed a missing escalation check.

## Decision

`better_supabase.explain_permission(tenant, member, permission)` reads the verdict from `member_can` and reports a reason, the roles, the matching keys and the override. A caller explains their own access; the `members.read` key explains others. `db.permissions.explain` and `explainPermissionTool` call it. The escalation check the plan called missing already exists in `set_permission_override` and `can_assign`; this change adds tests instead. The docs present `forContext({ permissions })` (ADR 0026) as the way to give an agent less.

## Alternatives considered

A table of denial logs was rejected: the live answer can't go stale.

## Consequences

One more function in the permissions module, granted to `authenticated`.
