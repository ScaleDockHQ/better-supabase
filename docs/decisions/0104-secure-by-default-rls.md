# 0104: RLS that is safe by default

- Status: accepted
- Date: 2026-10-25

## Context

The audit found these gaps: app-table writes skip `actor_may_write()` (fixed in 0.20.x); the
tenant scope is `to authenticated`, so a `to anon` or `to public` policy reads across tenants;
the restrictive policy is `for all`, so a block's select branch satisfies an app's update or
delete; nothing revokes `PUBLIC` or sets default privileges; `none` scope admits anonymous users.

## Decision

- The restrictive tenant scope is one policy per command, `to public`, so it narrows anon and
  every other role. Branches stay per command (ADR 0099 amended).
- Every schema the app exposes gets `alter default privileges ... revoke all on tables, functions,
  sequences from public, anon, authenticated`, and `revokeTable` also revokes from `PUBLIC`.
- `rls-guard` is on by default and also catches `disable row level security`.
- App tables exclude anonymous users (`is_anonymous` claim) unless the table asks for them, and
  `none` scope no longer admits `anon`.
- Authorization templates are checked at config load and in `gen` with a tokenizer.
- The service-role check reads the role PostgREST set, not the `request.jwt.claims` setting.

## Alternatives considered

- Leave defaults and rely on doctor: doctor warns after the fact, and a missed warning is a leak.

## Consequences

Breaking for apps that relied on the open defaults. Each hardening step has a changeset and a
migration note.
