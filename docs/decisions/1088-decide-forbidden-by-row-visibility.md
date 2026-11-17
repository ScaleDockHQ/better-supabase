# 1088: Decide forbidden or not found by row visibility

- Status: accepted
- Date: 2026-11-17

## Context

A refused invoice action answers `INVOICE_FORBIDDEN` when the caller can read
the invoice and `INVOICE_NOT_FOUND` otherwise, so a refusal never reveals a
row the caller can't see. "Can read" meant the block's `read` key. An app
whose readers see invoices through a key with row conditions, such as
"invoices that are not drafts", can't map that key to `read`: the SQL scope
helpers check role and scope only, so an authorization provider refuses a
conditioned key there, and the app maps `read` to an unconditioned key that
fewer members hold. Members who see the invoice through the app's own select
policy then got `INVOICE_NOT_FOUND` for an action they were not
allowed to take.

## Decision

The prelude defines `better_supabase.row_visible(rel, column, value)`. It
evaluates the table's select policies for the calling API role (the `role`
setting, else the token's role): the permissive policies or-ed, the
restrictive ones and-ed, the role's select grant required, and every row for
a role that bypasses row security. The invoice refusals call it after the
read key, so a caller who sees the row through any policy gets
`INVOICE_FORBIDDEN`. Only the refusal path calls it; the success path runs
the same single check as before. The function is not granted to the API
roles; block functions call it as their owner.

## Alternatives considered

- Several read keys, or a conditioned read key. A list of keys still can't
  hold a conditioned one, and evaluating row conditions in SQL would put the
  authorization provider's condition language into every block.
- Running the check as the caller. A security definer function can't
  `set role`, so the policies are read from `pg_policy` and run in the
  function instead.
- Leaving it to the app, which would map `INVOICE_NOT_FOUND` back by reading
  the row itself. Every adopter would repeat it, and SQL callers would still
  get the wrong answer.

## Consequences

The refusal follows what the caller can see, whatever grants it. Sub-queries
inside a policy run with the function owner's rights, so a policy that relies
on row security of another table can count a row as visible that the caller
would not see; such a caller learns only that the id exists. Policy
expressions that read `current_user` see the owner. Any error answers false,
so the refusal falls back to `INVOICE_NOT_FOUND`. Other blocks can call
`row_visible` for the same decision.
