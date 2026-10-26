# 0099: Render tenant isolation as one restrictive policy per tenant table

- Status: accepted
- Date: 2026-10-24

## Context

Apps mix their own declarative schemas with the files better-supabase
writes, and they add their own policies to block tables and to `tables`
(app tables). Postgres combines permissive policies with `or`. Every block
policy was permissive, with the tenant check inside it, so one app policy
such as `using (true)` on `better_supabase.invoices` opened every
organization's invoices to every signed-in user. Nothing in the generated
SQL or in doctor stopped it.

Turning the block policies restrictive doesn't work either. A table often has
several permissive policies that reach rows outside the caller's
memberships on purpose: an invitee reads their invitation, a user reads
their own employee record or notification, a guest reads a granted
invoice through `portal_subjects` (ADR 0070), platform staff read audit
events. A restrictive policy that only checks membership would deny them.

## Decision

A render pass, `applyTenantScope` in `src/sql/tenant-scope.ts`, runs on
every module in tenant scope before the actor write guards. For each table
whose spec names a `lifecycle.tenant` column, where the module grants a
privilege to `authenticated` or writes a permissive policy for it, it
appends one policy:

```sql
create policy bsb_tenant_scope on "better_supabase"."invoices" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
```

The base is `ctx.scope.members()`, so it follows the naming conventions and
the provider access model. The other branches are the `using` expressions
of the block's own permissive policies on the table (those that read,
update or delete) and their `with check` expressions (those that insert
or update; an update without one checks its `using`). The restrictive
policy therefore never denies what the block grants, and it narrows only
what other permissive policies add. Permission and access rules stay in
the permissive policies, unchanged.

App tables in tenant scope (`src/sql/modules/app-tables.ts`) get the same
policy with membership alone, since their four permissive policies are
membership checks. Their generated pgTAP file adds a `using (true)` policy
for the test and asserts that a stranger still reads and inserts nothing;
`supabase/tests/database/tenant_scope.test.sql` does the same for block
tables.

## Alternatives considered

- Making each block policy restrictive: it would deny the deliberate
  branches above, or need a second permissive policy per table to grant
  them, which doubles the policies and moves every module's access rules.
- One restrictive policy per command: four policies per table instead of
  one, with no stricter result, since `for all` applies `using` and
  `with check` to the right commands.
- A doctor rule that flags app policies on block tables: it warns after the
  fact and can't tell a widening policy from a narrowing one by its text.

## Consequences

An app's permissive policy on a block or app table can widen access within
the caller's organizations, and to rows the block already opens to them,
but never beyond. The fixture gains 261 policies, one per client-reachable
tenant table. Service-only tables, and tables outside tenant scope, get
none. The service role bypasses RLS and is unaffected; support sessions
carry the impersonated user's `sub`, so membership holds and the read-only
guard of ADR 0019 is unchanged.

The branches are copies, so a row that fails membership can evaluate a
block expression twice. Rows with a null tenant are hidden unless a block
policy opens them. The scope is `for all`, so a branch granted for one
command also lets an app policy use it for another (a row a user may read
through a block policy, an app policy may then let them update). Doctor
BS107, the schema scan for grants and the splinter multiple permissive
lint count only permissive policies, so their findings don't change.
Revisit this if a module needs a tenant table whose access must not follow
`lifecycle.tenant`.

## Update: templates are tokenized

Authorization templates are read by `tokenizeTemplate` (`src/core/sql-template-tokens.ts`)
instead of regular expressions, and `fillTemplate` refuses an unsafe template
before it fills a placeholder. Strings, quoted identifiers and comments are
read whole, so the checks for `;`, comments, dollar quotes and unqualified
calls look at code only.
