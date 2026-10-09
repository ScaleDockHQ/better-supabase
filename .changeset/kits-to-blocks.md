---
"better-supabase": minor
---

Kits are now blocks, and every feature module lives under `better-supabase/blocks/<name>`. There are no aliases; the [0.5 to 0.6 guide](https://bettersupabase.com/docs/migration/0.5-to-0.6) lists every rename.

- **Breaking:** subpaths move. `better-supabase/orgs` is `better-supabase/blocks/organizations`, and `better-supabase/jobs`, `/notifications` and `/webhooks` are `better-supabase/blocks/jobs`, `/blocks/notifications` and `/blocks/webhooks`. `createOutbox` and `outboxCloudEvent` move to `better-supabase/blocks/outbox`, and `purgeAuditLog` to `better-supabase/blocks/audit`. `hasEntitlement`, `EntitlementKey`, `entitlementMembers` and `ENTITLEMENTS_UPDATED` move to `better-supabase/blocks/entitlements` (out of `server`, `next`, `ssr`, `react` and `jobs`), and `useNotifications` moves from `better-supabase/react` to `better-supabase/blocks/notifications/react`.
- **Breaking:** `sql.kit` and the `kits` key merge into `sql.modules`, an object keyed by module name whose values are the module settings (a list of names still works).
- **Breaking:** `Kit*` names for features are `Block*` (`BlockEvent`, `onBlockEvent`, `forwardBlockEvents`), and `Kit*` names for SQL modules are `Module*` (`ModulesConfig`, `ModuleConfig`, `renderModules`, `modulePermissionKeys`). `org` is spelled out: `createOrganizations`, `Organizations`, `organizationLogoBucket`, and the `organization.*` event types replace `org.*`.
- **Breaking:** in SQL, `member_org_ids`, `has_org_role` and `org_member_role` are `member_organization_ids`, `has_organization_role` and `organization_member_role`, the organization functions take an `organization` parameter, `better_supabase.kit_modules` is `better_supabase.modules`, and module files carry `-- @bs-module` and `-- @bs-module-data` markers. Run `better-supabase sql sync`, the schema diff and `better-supabase sql data` to move a database over.

`list`, `storage`, `realtime` and `events` keep their subpaths. The list, storage and realtime pages move to `/docs/platform`, and the events page to [`/docs/standards/events`](https://bettersupabase.com/docs/standards/events).
