---
"better-supabase": patch
---

The `data-lifecycle` module (version 5) exports and purges more module tables, leaves credentials and audit snapshots out of exports, and the organization purger revokes credential refs before the purge. Run `better-supabase sql sync` to get the new version.

- Platform role assignments, outbox events, webhook secrets (purged, never exported), inbox tables, flag overrides and SCIM users per user, waitlist redemptions, AI provider keys, connector servers and grants, and workflow credentials join exports and purges.
- Exports leave out every `credential_ref` column, and audit events lose `old_record`, `new_record` and the impersonation columns.
- `createOrganizationPurger({ credentials })` revokes the `credential_ref` of each row the purge deletes through the `CredentialProvider` (connector grants for their user), only when the ref carries the organization. The rest come back in `purge.credentials.unrevoked` with a reason (`foreign`, `no_provider` or `not_revocable`), and a failed revoke stops the purge before it deletes anything.
- The purger now checks that the deletion is due (`organization_credential_refs`) before it cancels billing or clears Storage.
