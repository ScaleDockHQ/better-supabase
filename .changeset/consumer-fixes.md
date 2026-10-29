---
"better-supabase": minor
---

Fixes from an app built on better-supabase: tenant scope exemptions, PowerSync streams on edition 3, multi-limit rate limits, formatter-stable generated code, and block controllers that share a data engine. The [0.44 to 0.45 guide](https://bettersupabase.com/docs/migration/0.44-to-0.45) lists what to check.

Import paths, old to new:

| Before                                                | Now                                                 |
| ----------------------------------------------------- | --------------------------------------------------- |
| `createRateLimit` from `better-supabase/blocks/queue` | `createRateLimit` from `better-supabase/rate-limit` |
| `rateLimited` from `better-supabase/blocks/queue`     | `rateLimited` from `better-supabase/rate-limit`     |

The old exports stay as deprecated aliases.

- Tenant scope: `database.sql.tenantScope.exemptRoles` lets roles such as `supabase_auth_admin` through the restrictive `bsb_tenant_scope` policies. Doctor reports a `security invoker` access token hook behind the scope as BS421.
- Roles: with the provider or custom access model, `membership_roles` takes roles outside `blocks.permissions.roles`, `on_accept.roles` checks only `can_assign`, and a direct write of `memberships.role` swaps the previous primary role and keeps the others.
- PowerSync: `better-supabase powersync streams` writes Sync Streams edition 3, skips disabled memberships, syncs every team in the user's organizations and adds a `membership_roles` stream with `roles.many`. The publication migration starts with `create publication ... for table` and later adds only new tables.
- Attachments: `object_path` is a plain column a trigger fills, so logical replication sends it. A `topic` option (default `attachments`) broadcasts `changed` to `<topic>:<tenant>`; `attachmentsTopic()` names it and `createAttachmentListController` lists a record's files again when they change. Run `better-supabase upgrade` and generate a migration.
- Notifications: preferences sync and change offline through `notificationPreferencesRoute`, `send()` returns `eventId`, and `list()` items carry `recipientId`. `AUTHZ_EVENT` and `authzUserTopic` are exported from the client entries.
- Rate limits: oRPC and Hono `rateLimit` take several `hits`, and oRPC throws a declared `TOO_MANY_REQUESTS`. `createMcpAuth` reads context from a `Request` or `Headers` and takes a `clientId`.
- CLI: `add` renders new modules with `sql.schema` and `sql.api`, so doctor reports no BS304 right after it. `db seed` no longer loads the chat SDK. Provider function names can contain `{resource}`.
- Gen: `records/` and `hooks.ts` come out the way oxfmt prints them. `createdAt` and `updatedAt` are optional on `Insert` for tables the updated-at extension stamps. `gen.hooks.select` wraps every generated select in the app's own function.
- Testing: `TestUser`, `asUser`, `withRollback` and the seed helpers keep the definition's block map, so `db.$blocks` is typed.
- Block controllers: `createBlockQuery`, `createBlockMutation` and the framework hooks take `{ engine, instance }`, and `blockControllerEngine(queryClient)` from `better-supabase/query` shares cache entries with `blockQueries`.
- Errors: `BlockHint<B>`, `isBlockHint` and `blockHint` from `better-supabase/blocks` type each block's hint codes.
