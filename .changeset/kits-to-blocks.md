---
"better-supabase": minor
---

Kits are now blocks, and every feature module lives under `better-supabase/blocks/<name>`. This is a breaking change with no aliases; the [0.5 to 0.6 guide](https://bettersupabase.com/docs/migration/0.5-to-0.6) lists every rename.

- Subpaths: `better-supabase/orgs` is `better-supabase/blocks/organizations`, and `better-supabase/jobs`, `/notifications` and `/webhooks` move to `better-supabase/blocks/jobs`, `/blocks/notifications` and `/blocks/webhooks`. `createOutbox` and `outboxCloudEvent` move to `better-supabase/blocks/outbox`. `hasEntitlement`, `EntitlementKey`, `entitlementMembers` and `ENTITLEMENTS_UPDATED` move to `better-supabase/blocks/entitlements` (out of `server`, `next`, `ssr`, `react` and `jobs`), and `useNotifications` moves from `better-supabase/react` to `better-supabase/blocks/notifications/react`.
- Config: the `kits` key is `blocks`, and `sql.kit` is `sql.modules`.
- Names: `Kit*` types and functions are `Block*` (`BlocksConfig`, `BlockEvent`, `onBlockEvent`, `forwardBlockEvents`, `renderBlocks`). `org` is spelled out: `createOrganizations`, `Organizations`, `organizationLogoBucket`, and the `organization.*` event types replace `org.*`.
- SQL: `member_org_ids`, `has_org_role` and `org_member_role` are `member_organization_ids`, `has_organization_role` and `organization_member_role`, the organization functions take an `organization` parameter, `better_supabase.kit_modules` is `better_supabase.block_modules`, and module files carry `-- @bs-block` markers. Run `better-supabase sql sync`, the schema diff and `better-supabase sql data` to move a database over.

`list`, `storage`, `realtime` and `events` keep their subpaths, and their docs pages move to `/docs/platform`.
