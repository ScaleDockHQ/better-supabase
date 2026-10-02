---
"better-supabase": minor
"@better-supabase/cli": minor
---

Security fixes in the SQL kit. Rerun `better-supabase sql add` for the modules you installed to apply them:

- `create_invitation` no longer lets an admin invite someone as `owner`; only an owner or the service role can. The service-role check reads `auth.jwt() ->> 'role'` instead of the deprecated `auth.role()`, and `invitations.role` gets the same check constraint as `memberships.role`.
- `accept_invitation` requires the signed-in user's address in `auth.users` to be confirmed, not only an `email` claim. An unconfirmed user gets the hint `INVITATION_EMAIL_UNCONFIRMED`.
- `anon` can no longer call `has_org_role`, and the pgTAP kit's `tests.create_user` is granted to `authenticated` and `service_role` only.
- The tenant module adds `member_org_ids(roles)`, a set-returning helper. Write policies as `org_id in (select better_supabase.member_org_ids())`, which Postgres evaluates once per statement instead of once per row.
- Deduplicated jobs get a partial index on `dedupe_key` in each queue table, so `enqueue_job` no longer scans the queue while it holds the advisory lock.
- `triggerSql` puts the realtime trigger function in the `better_supabase` schema, which the Data API does not expose, instead of `public`.

`better-supabase gen` names a composite foreign key that repeats a column on both sides, such as `(customer_id, organization_id)` referencing `(id, organization_id)`, after the remaining column: the relation is `customer`, as it would be for a plain `customer_id` key. Schemas with such keys get new relation names; set `tables.<name>.relations` to keep the old ones.
