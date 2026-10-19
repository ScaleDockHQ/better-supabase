# Decisions

Architecture decision records for this repository. Each one says what we
decided, why, and what it costs. Copy `0000-template.md` to the next number to
add one, and link it from the code or config it explains.

| ADR                                                   | Decision                                                                                                                       |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| [0001](0001-library-profile.md)                       | The repo follows the library profile of the repo standard                                                                      |
| [0002](0002-deviations.md)                            | Where the repo departs from the standard, and the lint backlogs                                                                |
| [0003](0003-cli-package.md)                           | The CLI runs on citty; MCP keeps its own protocol layer (package split superseded)                                             |
| [0004](0004-commit-maintainer-skills.md)              | Maintainer skills in `.agents/skills` and `skills-lock.json` are committed                                                     |
| [0005](0005-temporal.md)                              | Time values in the public API are `Temporal`; the polyfill is an optional peer                                                 |
| [0006](0006-pgdelta-and-native-stack.md)              | The fixture schema diffs with pg-delta; the native stack part is superseded by 0032                                            |
| [0007](0007-cli-in-library.md)                        | The CLI ships inside `better-supabase` with its dependencies inlined                                                           |
| [0008](0008-middleware-entries.md)                    | The server and the adapters run on `@supabase/middleware` entries and bridges                                                  |
| [0009](0009-stripe-peer-and-openfeature.md)           | Stripe is a lazily loaded optional peer; OpenFeature is typed structurally                                                     |
| [0010](0010-neutral-blocks-and-sdk-adapters.md)       | AI blocks stay SDK-neutral; SDK adapters own no tables; tokens sit behind a `credential_ref`                                   |
| [0011](0011-authorization-providers.md)               | Authorization is a neutral, versioned `AuthorizationProvider`; libraries ship adapters                                         |
| [0012](0012-kits-renamed-to-blocks.md)                | Kits are blocks; feature modules import from `better-supabase/blocks/<name>`                                                   |
| [0013](0013-node-only-sdk-adapters.md)                | SDK adapters whose SDK needs Node (`workflow-sdk/world`, `eve`) are Node-only entries                                          |
| [0014](0014-nestjs-create-require.md)                 | `better-supabase/nestjs` loads `@nestjs/common` with a synchronous `createRequire`                                             |
| [0015](0015-block-extension-model.md)                 | Blocks extend through `fields`, `hooks`, transport middleware and `extendBlock`                                                |
| [0016](0016-typegen-peer-range.md)                    | `@supabase/postgrest-typegen` is a peer range; the default catalog stays exact                                                 |
| [0017](0017-spec-documents.md)                        | One `ApiModel` renders every spec version and serves the routes; 3.3 is an opt-in preview                                      |
| [0018](0018-subject-bound-blocks.md)                  | A subject binding can name the adopted table its rows live in                                                                  |
| [0019](0019-read-only-actors.md)                      | Security definer writes refuse a read-only support or impersonation session                                                    |
| [0020](0020-subject-registry.md)                      | Subject types are declared once in `config.subjects`; modules fall back to the registry                                        |
| [0021](0021-rank-keys.md)                             | Rows are ordered by base-62 fractional rank keys; `move()` changes the group as the caller                                     |
| [0022](0022-documents-yjs.md)                         | Yjs documents are an update log in Postgres; `yjs` is an optional peer of the provider                                         |
| [0023](0023-bookings-btree-gist.md)                   | The bookings block installs `btree_gist` for its exclusion constraint against double bookings                                  |
| [0024](0024-money-and-commerce-providers.md)          | Money is bigint minor units; payments and tax are versioned providers with Stripe adapters                                     |
| [0025](0025-drive-on-attachments.md)                  | The drive is two modules on attachments; `before` renders a module ahead of the subject checks                                 |
| [0026](0026-delegation-cap-and-operations.md)         | Delegated tokens are narrowed inside the access functions; every checked action is a row in `OPERATIONS`                       |
| [0027](0027-fixture-pgdelta-baseline.md)              | The fixture's migrations are one pg-delta baseline, and its schema uses the per-schema layout                                  |
| [0028](0028-pipelines.md)                             | Record stages run on tenant-editable pipelines with fixed outcomes, separate from status                                       |
| [0029](0029-block-manifests.md)                       | One `defineBlock` manifest per block, wired by provides and consumes; `blocks` replaces `sql.modules`                          |
| [0030](0030-headless-block-controllers.md)            | Block client state lives in headless controllers with React, Vue, Svelte and Solid bindings                                    |
| [0031](0031-presets-registry-recipes.md)              | Presets install blocks, a shadcn registry ships glue only, and UI is a recipe                                                  |
| [0032](0032-fixture-on-the-stack-engine.md)           | The fixture runs on the CLI's stack engine with per-checkout ports and the native runtime in CI                                |
| [0033](0033-signing-keys-in-vault.md)                 | Signing keys live in Vault; signing runs in TypeScript with WebCrypto                                                          |
| [0034](0034-retention-holds-and-audit-chain.md)       | Retention policies and legal holds in data-lifecycle; a hash-chained, partitionable audit log                                  |
| [0035](0035-flags-sdk-adapter-and-custom-contexts.md) | The Flags SDK adapter is typed structurally; brand-like targeting uses custom flag contexts                                    |
| [0036](0036-optional-peers-for-every-integration.md)  | Every SDK integration is an optional peer with a tested range                                                                  |
| [0037](0037-money-on-the-wire.md)                     | Every amount with a currency is `Money`; block SQL functions return int8 as text, decoded strictly                             |
| [0038](0038-monthly-partitions-for-event-tables.md)   | Partition the outbox, usage history, webhook deliveries and notification delivery events by month on opt-in                    |
| [0039](0039-name-permdock-on-create.md)               | The Create page names PermDock as one optional auth choice                                                                     |
| [0040](0040-app-tables.md)                            | `appTables` renders the app's own tables with scope, RLS and pgTAP; a Create design rides on the URL as `&design=`             |
| [0041](0041-create-deploys-through-supabase-oauth.md) | Create deploys a preset to the visitor's own project through a Supabase OAuth app; tokens live in a sealed cookie              |
| [0042](0042-column-formats-and-table-keys.md)         | App table columns take a format, options, bounds, a comment and identity; tables take composite keys, an id type and a comment |
| [0043](0043-app-tables-are-subjects.md)               | An app table becomes a subject through `appTables.<name>.subject`                                                              |
| [0044](0044-rollups-and-lookups-as-views.md)          | App table rollups and lookups render as a `security_invoker` view                                                              |
| [0045](0045-cli-command-tree-and-agent-mode.md)       | The CLI runs from one command tree with real subcommands, one JSON envelope and agent mode; `bsb` is its short name            |
