---
"better-supabase": minor
---

Lists and resources page by cursor by default. `defineListQuery` and the default list of `defineResource` and `defineApi` read the same number of rows however deep the page is, and rows inserted between requests don't shift it. Set `pagination: "offset"` to keep page numbers and totals; the 0.9 codemod adds it to calls that set no pagination in files that read page numbers, and lists the other calls for review. A table or view without a primary key stays on offset.

| 0.8 (offset default)                       | 0.9 (cursor default)                  |
| ------------------------------------------ | ------------------------------------- |
| `?page=3&size=50`                          | `?after=<nextCursor>&size=50`         |
| `page.page.number`, `.total`, `.pages`     | `page.hasMore`, `page.nextCursor`     |
| `ListPage<R, F, C>` is an `OffsetPage`     | `ListPage<R, F, C>` is a `CursorPage` |
| `list.args(query)` returns `page`, `count` | `list.args(query)` returns `after`    |
| OpenAPI and MCP list `page`                | OpenAPI and MCP list `after`          |

The World's `world.analytics` lists return `(created_at, id)` keyset cursors instead of offsets. Pass back the cursor the previous page returned; an offset number from 0.8 fails with "not an analytics cursor".

Time tracking rates are `Money` (ADR 0037). An entry's `rate` is an hourly amount in minor units with its currency, and the timesheet totals return `amounts`, one `Money` per currency, instead of `amount`. The client returns `CURRENCY_INVALID` before any database call for an unknown code, and `time_entry.*` events carry `rate` as text with `rateCurrency`.

| 0.8                              | 0.9                                                 |
| -------------------------------- | --------------------------------------------------- |
| `time.start(org, { rate: 120 })` | `time.start(org, { rate: money(12_000n, "EUR") })`  |
| `entry.rate` is `120`            | `entry.rate` is `money(12_000n, "EUR")`             |
| `sheet.totals.amount` is `480`   | `sheet.totals.amounts` is `[money(48_000n, "EUR")]` |

The module upgrade turns `rate` into a `bigint` with `round(rate * 100)`, adds `rate_currency`, and drops the `numeric` signatures of `start_timer` and `log_time`. Set `rate_currency` on existing rows after the upgrade; the 0.8 to 0.9 guide has the statements.

Tagging a record needs `tags.apply` or `tags.manage`. In 0.8 any signed-in user could tag or untag a record. The `role_permissions` defaults give `tags.apply` to members; apps with their own roles grant it to the roles that tag.

| 0.8                                          | 0.9                                                        |
| -------------------------------------------- | ---------------------------------------------------------- |
| `tag()` and `untag()` check the subject only | they also need `tags.apply` or `tags.manage` on the tenant |

Audit, webhooks and notifications write a batch in one call. `audit.recordMany(events)`, `webhooks.publishMany(events)` and `notifications.sendMany(items)` take up to 1000 items each, run the single-item checks per item, and return one `Result` per item in order, so a bad item never drops the others. The audit, webhook and notification sinks use them, one call per batch. `auditSink` takes the batch function:

| 0.8                                      | 0.9                                                              |
| ---------------------------------------- | ---------------------------------------------------------------- |
| `auditSink(record, options)`             | `auditSink(recordMany, options)`                                 |
| `record: (event) => AsyncResult<string>` | `recordMany: (events) => AsyncResult<readonly Result<string>[]>` |

The outbox, usage, notifications and webhooks modules take `partitioned: true`, as the audit module does. It partitions a new events, `usage_history`, `notification_delivery_events` or deliveries table by month on its time column, with a primary key of `(id, created_at)`, and retention drops whole months. It applies to new tables only; the default stays unpartitioned (ADR 0038).

Direct Postgres (`better-supabase/postgres`) honors `count: "planned"` and `count: "estimated"` the way PostgREST does: `planned` reads the row estimate from `explain`, and `estimated` counts exactly up to `estimatedCountThreshold` (default 1000) and uses the estimate above it. Counts are cast to `bigint`.

| 0.8                                          | 0.9                                                            |
| -------------------------------------------- | -------------------------------------------------------------- |
| `planned` and `estimated` ran an exact count | `planned` reads `explain`; `estimated` switches at 1000 rows   |
| `idleInTransactionTimeout` unset             | defaults to 15000 ms; `0` turns it off                         |
| an idle connection error crashed the process | it arrives as an `error` event, or the logger without handlers |

`createPostgres` takes `events` and `logger` for those errors. The World's pool has limits now: `maxConnections` (10), `connectionTimeout` (30 s), `idleTimeout` (10 s), `statementTimeout` (30 s) and `idleInTransactionTimeout` (15 s), also read from `WORKFLOW_POSTGRES_MAX_CONNECTIONS`, `WORKFLOW_POSTGRES_CONNECTION_TIMEOUT_MS`, `WORKFLOW_POSTGRES_IDLE_TIMEOUT_MS`, `WORKFLOW_POSTGRES_STATEMENT_TIMEOUT_MS` and `WORKFLOW_POSTGRES_IDLE_IN_TRANSACTION_TIMEOUT_MS`.

Realtime trigger functions include the schema, so tables with the same name in two schemas no longer replace each other's function. The trigger keeps its name. Drop the old functions in the migration; grants on them don't carry over.

| 0.8                              | 0.9                                       |
| -------------------------------- | ----------------------------------------- |
| `bs_broadcast_<topic>_<table>()` | `bs_broadcast_<topic>_<schema>_<table>()` |

The key payload of `broadcast_topic()` reads only the primary key and the placeholder columns and looks the key up once per statement.

Doctor has five new rules:

| Code  | Severity | Finds                                                                                           |
| ----- | -------- | ----------------------------------------------------------------------------------------------- |
| BS117 | warning  | a policy without a `to` role, so it applies to `public`                                         |
| BS224 | warning  | `anon` or `authenticated` without `statement_timeout` or `idle_in_transaction_session_timeout`  |
| BS225 | info     | `pg_stat_statements` not installed                                                              |
| BS226 | warning  | postgres.js without `prepare: false`, or Prisma without `pgbouncer=true`, next to a `:6543` URL |
| BS227 | info     | `pagination: "offset"` in a list or resource config, or `count: "exact"` on a list              |

BS216 accepts a `where col is not null` partial index as the foreign key's index. BS335 now also
checks the outbox, usage history, webhook deliveries and notification delivery events tables, not
only the audit log.

`calendar_attendees.role` is checked against the RFC 5545 roles, `notification_events.priority` against the configured priorities, and `reminders.offset_minutes` is limited to a year either way. Each check is added `not valid` and then validated, so existing bad rows leave it unvalidated with a warning instead of failing the migration. `comments.list` takes `cursorId` with `cursor`, so comments with the same timestamp no longer repeat or skip between pages. The audit list ignores `offset` when it gets a cursor.

Line totals on quotes, invoices and deals are recounted once per parent per statement instead of once per line. Trigger functions and `broadcast_changes()` are no longer executable by `anon` or `authenticated`, and the storefront helpers are revoked from `public` and granted to the roles that call them. `bs_reserved_slugs_read` names its roles, and `scope.platform()` checks the platform permission once per statement. The reminders, calendar, bookings, imports, bulk, share-links, tags, memory and workflow-builder modules index the columns their policies and lookups filter on. Search writes embeddings in one statement, the pgmq backend archives a batch in one call, and `metrics_rollup` locks per tenant.
