# 0070: Let guests in through `ctx.scope.guest`, never as members

- Status: accepted
- Date: 2026-10-22

## Context

Apps built on the tenant blocks want to show a client or contractor the
records they work on: an invoice to pay, a project to comment on, a booking
to check. The only way in was membership, which gives a role in the whole
organization, or a share link, which is anonymous and read-only. A customer
portal needs a signed-in person who sees their own party's invoices and
bookings and nothing else. Invariant 15 rules out depending on an
authorization library for this, and providers that already model external
users need a way to answer instead.

## Decision

The scope port (`src/sql/scope.ts`) gets two checks:
`ctx.scope.guest(tenant, type, id, action)` for a record granted to the
caller, with `action` one of `read`, `comment` and `upload`, and
`ctx.scope.guestParty(tenant, type, id)` for a record that belongs to the
party the caller acts for. Both read two shared contract functions,
`better_supabase.portal_subjects(action)` and `portal_parties()`, as a
row-value `in (select ...)` so Postgres hashes the set once per statement.
They render `false` unless the sets exist, so a layout without guests keeps
its policies byte for byte (`guestOr` drops the `false` checks).

The sets come from two sources, unioned:

- the `guests` module (`src/sql/modules/guests.ts`, client
  `better-supabase/blocks/guests`): guests invited by email, accepted with a
  hashed one-time token whose email must match, with per-record grants;
- an `AuthorizationProvider` under the `provider` model, through the optional
  templates `portalSubjects` (placeholder `{action}`) and `portalParties`.

Without the module, `access` renders the provider's sets alone. The
templates are optional, so `apiVersion` stays 1. The functions are named
`portal_*` rather than `guest_*` so renaming the `guest` entity
(`blocks.guests.entities`) leaves the contract alone.

`guests` declares `before: "comments"`, so its functions exist before the
comments, attachments, invoices and bookings policies that reference them.
Comments and attachments let a guest read with `read` and write with
`comment` or `upload`; invoices let in a granted invoice and the invoices
addressed to the guest's party; bookings let in a granted booking. A guest is
never a member: `can()` stays false for them.

## Alternatives considered

- Make guests members with a restricted role: every module that lists members
  or checks `can()` would see them, and a role grants the whole tenant.
- Extend share links with a signed-in mode: links are per record and
  anonymous by design; a portal needs one identity across many records.
- Ship an external-user model in an authorization library: ruled out by
  invariant 15. Providers can still answer through the templates.

## Consequences

Modules that want guests add one `guestOr` call per policy; the scope port
keeps literal access calls out of modules. Every guest check costs one
hashed subplan per statement when guests are installed and nothing
otherwise. Channels and other messaging modules are not covered yet and
would add the same call. We would revisit this if guests need permissions
beyond the three actions, which would call for a per-module action list in
the grant.
