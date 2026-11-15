# 1036: Seed the customers and inbox pages

- Status: accepted
- Date: 2026-11-15

## Context

ADR 1035 left two `app.*` pages of the example without a generated seed.
`app.customers` is `public.customers`, the fixture table of the pgTAP suite, and
`app.inbox` rows are conversations that `record_inbound` creates, one of them
backdated by an `UPDATE` afterwards. The library reset that CI and pgTAP use runs
no page seeds, so anything a test depends on has to stay in `seed.sql`.

## Decision

The descriptor stays at `apiVersion: 1` and gets no new key. The `after`
statement of a seed target (ADR 1035) already runs a declared SQL statement per
row, after the create call has committed, so it carries the backdating.

- `seed.sql` keeps the three customers with fixed ids, the Help inbox and its
  conversation: the pgTAP suite and the invitation links name them.
- `app.customers` seeds four more demo customers by name, through a plain insert,
  skipped when a customer of that name exists.
- `app.inbox` seeds the email, Slack and WhatsApp conversations through
  `record_inbound`. A row's `age_days` is not passed to the function; the target's
  `after` statement moves the conversation and its messages back by that many days.
  The three hand-written calls and both `UPDATE`s leave `example.sql`; the inboxes,
  the failed webhook event, the templates and the draft stay there, since they are
  not conversations.
- The runner lists the customers and inbox targets first: the deals look their
  contact up among the people a conversation records, and the orderings that pull
  the deals forward would otherwise run them before the inbox.

## Consequences

- `pnpm supabase:reset` seeds every `app.*` page; a second `pnpm db:seed:pages`
  adds no rows. The library reset is unchanged.
- No library code changed, so there is no changeset.
