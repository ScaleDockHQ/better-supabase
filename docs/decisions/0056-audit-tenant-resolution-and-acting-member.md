# 0056: Audit resolves tenants itself and names the acting member

- Status: accepted
- Date: 2026-10-20

## Context

`audit()` found a row's tenant only through a column on that row. Tables that
reach their tenant through a parent, and writes by a service role on behalf
of a member, left audit rows without a tenant or an actor.

## Decision

`audit()` takes `tenant_path` (a join path to the tenant) or `tenant_function`
(a SQL function that returns it), and splits its triggers so `ignore` columns
become a `WHEN` clause instead of a runtime check. `admin({}, { as })` sends
`x-bs-actor`, which the audit trigger and `track_actor` read, so a server write
names the member it acts for. The doctor's BS315 takes exemptions with a
reason, scoped to the configured schemas, and BS343 flags partitions without
RLS.

## Consequences

An exemption without a reason is a finding. A tenant function runs inside the
trigger, so it must be `stable` and cheap. The header is advisory for the
database: only the trusted server sets it.
