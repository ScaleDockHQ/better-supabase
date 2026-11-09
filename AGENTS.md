# better-supabase agent guide

This guide is for agents and humans changing this repository. Apps that use
better-supabase get the consumer skills in `packages/better-supabase/skills`
instead. `CLAUDE.md` is the one line `@AGENTS.md`; put everything here or in
a rule.

`better-supabase` is an ESM package with subpath exports, plugins and blocks
(`better-supabase/blocks/*`). Its CLI ships in the same package, from
`src/cli`, with its dependencies inlined at build time. Docs live in
`apps/docs` (Fumadocs), examples in `apps/examples/*`, cross-package tests in
`tests/*`.

## Commands

- `pnpm install` (pnpm 12, Node 24), then `pnpm verify`: the gate before
  every push (format, lint, prose, typecheck, Knip, boundaries, tests,
  doctor, audit), cached per task in Turbo.
- `pnpm fix` (`ultracite fix`), `pnpm lint`, `pnpm typecheck`, `pnpm test`.
- `pnpm supabase:start`, `pnpm supabase:reset`, `pnpm supabase:test`, then
  `pnpm test:integration` against the running stack.
- `pnpm db:gen` regenerates the typed clients; `pnpm dev:portless` serves the
  apps on HTTPS `.localhost` URLs.

Every other script, with what it checks, is in
[`docs/agents/commands.md`](docs/agents/commands.md).

## Layout

```
packages/better-supabase/  the library and its CLI, skills/, schemas/, api/exports.json
packages/next-config/      createNextConfig() and the security headers
packages/typescript-config/ tsconfig presets
apps/docs/, apps/marketing/ bettersupabase.com/docs and bettersupabase.com
apps/examples/*            one app per adapter (examples/monorepo/*: one package each)
tests/*                    bundle size, type matrix and benchmark, validation projects
supabase/                  the local stack: schemas/, migrations/, tests/ (pgTAP)
scripts/                   repo checks and release scripts (Node type stripping)
docs/agents/, docs/decisions/ agent corrections by topic, and the ADRs
.agents/rules/, .agents/skills/ rules (linked from .cursor and .claude) and maintainer skills
```

The root `oxlint.config.ts` and `oxfmt.config.ts` extend Ultracite and hold
every lint and format rule; each workspace config extends the root one.

## Invariants

The full text is in `.agents/rules/architecture.mdc`.

1. The core depends only on `@standard-schema/spec` and the Supabase packages.
2. Generated code never uses `declare module`; it calls inferring functions.
3. Rows keep the configured casing; `$client` and `queryRaw` use database names.
4. Repository methods return a `Result` with plain `DbError`s; only `.orThrow()` throws.
5. Event handlers and sinks can never change a result.
6. Runtime entries import no Node built-ins (`NODE_ENTRIES` lists the exceptions).
7. Auth never calls the Auth server for a valid token; refresh happens only in the proxy.
8. Every followed spec version is pinned in `SPEC_PINS`.
9. Every public API has a docs page and an example.
10. Plugins and extension interfaces are versioned (`apiVersion: 1`).
11. `@supabase/postgrest-typegen` is an optional peer that only the CLI loads.
12. Imports stay at the top; lazy loads are listed in `.agents/rules/lazy-imports.mdc`.
13. Splinter lints are fetched at a pinned commit and hash, never vendored.
14. Never bypass `minimumReleaseAge`.
15. better-supabase never depends on an authorization library; only the Create page names PermDock, as one optional choice.

## Conventions

- Exhaustive `switch` over unions ends in a `never` check.
- Tests sit in the workspace's `tests/` folder and mirror the `src/` path.
- A type assertion carries a `SAFETY:` comment; `as unknown as T` is rejected
  outside tests. Prefer a type guard or a schema parse.
- Only erasable syntax, and `isolatedDeclarations` in packages: exported
  functions have explicit return types.
- TypeScript 7 (`tsc` is the native one) everywhere except `tests/types/ts-6`.
- Docs pages, prose and comments follow `.agents/rules/writing.mdc` and
  `.agents/rules/docs-content.mdc`.

## Agent workflow

One branch and one PR per chat or plan, Conventional Commits, and
`pnpm verify` before every push (`.agents/rules/git-workflow.mdc`). Read the
`docs/agents` page for the area first, and add a correction there when an
agent needs it twice.

## When you change X, also update Y

| Change                  | Also update                                                                                                   |
| ----------------------- | ------------------------------------------------------------------------------------------------------------- |
| A subpath               | exports map, `tsdown.config.ts`, size baseline, export snapshot, README table                                 |
| A public export         | `api/exports.json` (`vitest run tests/exports.test.ts -u`), review the diff                                   |
| An env key              | the app's `env.ts`, all three Vercel environments, `turbo.json`, `.env.example`                               |
| A CLI command or flag   | its docs page under `cli/`, the help snapshot, the changeset                                                  |
| A dependency bump       | the catalog pin, "Pre-release pins", the changeset or commit note, an ADR                                     |
| A `typescript` bump     | `oxlint-tsgolint` in the same commit                                                                          |
| A Next.js bump          | run `next dev` once in each Next.js app                                                                       |
| A file move             | Knip entries, the `tests/` mirror path, the folder's `meta.json` for a docs page                              |
| A rename                | the docs Naming page (`docs:drift` checks `lib/supabase/*` names), the changeset's old-to-new table           |
| A perf-sensitive change | the bundle (with the CLI startup entry), type and benchmark baselines, before and after numbers in the commit |
| A user-visible change   | a changeset (`pnpm changeset`)                                                                                |

The rows for each area are in `.agents/rules/also-update-library.mdc`,
`also-update-blocks.mdc` and `also-update-repo.mdc`.

## Hard rules

- `pnpm verify` passes before every push. Fix the code, not the test.
- Never commit secrets. Server-only keys never get a `NEXT_PUBLIC_` prefix,
  and `.env.example` lists keys without values.
- Never edit generated files by hand (`database.types.ts`, the examples'
  `src/lib/supabase/*`, `api/exports.json`).
- Never change a pushed migration. Edit `supabase/schemas` and generate a new one.
- Never turn a lint rule off without a comment that gives the reason and the finding count.
- Pin exact versions in the catalog, and never bypass `minimumReleaseAge`.

## Deviations

One ADR per decision in `docs/decisions` (copy `0000-template.md`).

- 0001: Follow the library profile of the repo standard
- 0002: Deviations from the repo standard and the lint backlogs
- 0003: Ship the CLI as @better-supabase/cli on citty
- 0004: Commit the maintainer skills in `.agents/skills`
- 0005: Use Temporal for time values in the public API
- 0006: Diff the fixture schema with pg-delta; the native stack stays opt-in
- 0007: Ship the CLI inside better-supabase
- 0008: Build the server and the adapters on @supabase/middleware entries
- 0009: Load Stripe lazily as an optional peer and type OpenFeature structurally
- 0010: Keep AI blocks SDK-neutral and bridge each SDK in an adapter subpath
- 0011: Define a neutral authorization provider and let libraries ship adapters
- 0012: Rename kits to blocks and import every feature module from `better-supabase/blocks`
- 0013: Ship SDK adapters whose SDK needs Node as Node-only entries
- 0014: Load `@nestjs/common` with a synchronous `createRequire`
- 0015: Extend blocks through fields, hooks and `extendBlock`
- 0016: Declare postgrest-typegen as a peer range
- 0017: Render every spec document from one API model
- 0018: Subject bindings carry their own adopted tables
- 0019: Read-only actors are refused inside security definer writes
- 0020: Declare subject types once in config.subjects
- 0021: Order rows with base-62 fractional rank keys
- 0022: Store Yjs documents as an update log, with yjs as an optional peer
- 0023: The bookings block requires the btree_gist extension
- 0024: Keep money in bigint minor units behind versioned commerce providers
- 0025: Build the drive on attachments, in two modules that render around the subject checks
- 0026: Narrow delegated tokens inside the access functions, and name every checked action in one operations table
- 0027: Squash the fixture migrations into a pg-delta baseline, and use the per-schema layout
- 0028: Run record stages on tenant-editable pipelines, separate from status
- 0029: Describe every block with one manifest, wired by what it provides and consumes
- 0030: Keep block client state in headless controllers with thin framework bindings
- 0031: Install blocks through presets, ship glue through a shadcn registry, and show UI as recipes
- 0032: Run the fixture on the Supabase CLI's stack engine
- 0033: Keep signing keys in Vault and sign in TypeScript
- 0034: Retention policies, legal holds and a hash-chained audit log in Postgres
- 0035: A structural Flags SDK adapter, and custom contexts instead of brands
- 0036: Declare every SDK integration as an optional peer
- 0037: Send every amount as Money and every int8 as text
- 0038: Partition the event tables by month when an app opts in
- 0039: Name PermDock as one optional auth choice on the Create page
- 0040: Render the app's own tables from `appTables`, and carry a Create design in the URL
- 0041: Deploy a Create preset through a Supabase OAuth app
- 0042: App table columns take a format, options and bounds; tables take composite keys and an id type
- 0043: An app table becomes a subject through `appTables.<name>.subject`
- 0044: Rollups and lookups render as a `security_invoker` view
- 0045: Run the CLI from one command tree, with agent mode
- 0046: Store tenant rules as filter trees with action references
- 0047: Publish the CLI contract other CLIs follow
- 0048: App tables emit outbox events from a database trigger
- 0049: Serve the CLI as a stdio MCP server, with consent for writes
- 0050: Lint unapplied migrations for locking statements in doctor
- 0051: App table columns restrict access with Postgres column grants
- 0052: Billing can store subscriptions from webhooks
- 0053: Usage meters have a kind: counter, distinct or computed
- 0054: A Vercel Marketplace block and a Vercel Queues jobs backend
- 0055: Connect PermDock Cloud on the Create page
- 0056: Audit resolves tenants itself and names the acting member
- 0057: Run Create in the cloud app
- 0058: Hand designs too large for a URL to init as a design file
- 0059: Diff inside the running stack when the shadow database can't start
- 0060: Name block entities per block, with typed config keys and automatic subjects
- 0061: Generate typed helpers for blocks and keep their libraries optional peers
- 0062: Build one messaging core and move comments and the inbox onto it
- 0063: Split the activity feed out of comments into its own block
- 0064: Compose blocks through sections, flows and three layers
- 0065: Keep balances in one double-entry ledger
- 0066: Store asset coordinates as numbers, with PostGIS as an option
- 0067: Votes are reactions, and scores come from tenant-editable models
- 0068: Compute calendar availability in SQL and build appointment schedules on bookings
- 0069: Keep document suggestions outside the update log until an editor accepts them
- 0070: Let guests in through `ctx.scope.guest`, never as members
- 0071: Drive labels are tags, and file approvals target one attachment
- 0072: Merge subject records through marked handler functions
- 0073: Admission passes carry a signed token; the database keeps the nonce
- 0074: Billable time prices entries from a rate card; billed entries lock
- 0075: Put record presence, record mentions and saved items on the subject registry
- 0076: One moderation item per subject, shared by reviews and comments
- 0077: Enrollments in programs of steps, with onboarding on top
- 0078: Sync member mailboxes into engagements through a versioned mail provider
- 0079: Materialize segments from rules filter trees and route records through assignment queues
- 0080: Post recurring charges on the ledger, once per period
- 0081: Store enrichment results per record and provider, and fill only empty columns
- 0082: Ship through a versioned ShipmentCarrier and ingest tracking by webhook
- 0083: Snapshot the forecast with its deals, and record field changes with a trigger per tracked table
- 0084: The public status page is one security definer function anon may call
- 0085: Courses run on enrollments, with quizzes graded by forms
- 0086: Book series one occurrence at a time, and pay for classes from a credit ledger
- 0087: Encrypt fields with per-owner Vault keys and audit reads where they decrypt
- 0090: Log confirmed bookings as engagements with a trigger on the bookings table
- 0091: Sequences run on enrollments and send through a mailer port
- 0092: Posts keep only boards and posts; votes, replies and moderation stay in their blocks
- 0093: Install blocks as named instances behind one data contract
- 0094: Split the framework adapters into supported and community tiers
- 0095: Share one token verification across cache scopes through a session memo
- 0096: Give authorization libraries a version cache slot and a Realtime evictor
- 0097: Serve the schema types through a TypeScript 7.1 content mapper
- 0098: Detect the app's tables per table instead of an adopt mode
- 0099: Render tenant isolation as one restrictive policy per tenant table
- 0100: One project pipeline for the config, the CLI, Create and the cloud
- 0101: Adopt better-supabase one rung at a time
- 0102: Tables are user-owned SQL; features are `@bsb` tags
- 0103: Block modules emit typed policies
- 0104: RLS that is safe by default
- 0105: Verify RLS against the catalog and generate an access matrix
- 0106: Plan migrations with pg-delta's library plan
- 0107: `designDataApi` stays in `create/lite`
- 0108: `db diff` plans with pg-delta's library on the stack's postgres role
- 0109: Keep hooks, CI and Next.js builds fast
- 0110: Keep flag revisions in Postgres and draw splits from a second bucket
- 0111: Claim Workflow SDK start keys in a table and purge ended runs in SQL
- 0112: Run chat sandboxes on Vercel Sandbox through an optional-peer adapter
- 0113: Run eve tools as the user, approve them in the approvals block and schedule them on the queue
- 0114: Give authorization libraries a typed, additive contract
- 0115: Read a page's user data in one bootstrap call, in a private or remote cache scope
- 0116: Fetch one JWKS per process; keep one verified-token memo; build clients with createContextClient and createAdminClient
- 0117: Refresh sessions through `@supabase/ssr` on every request, with one Auth call per refresh token
- 0118: Store calendar alarms as event data; schedule reminders on any subject from a block timer
- 0119: Tenant approval policies tighten config floors; approvals are consumed once
- 0120: Publish quote versions and count document totals per tax rate
- 0121: Enrollment steps carry an assignee and a due date, rendered into rows
- 0122: Let ai-chat run without a tenant, share chats with participants and store native parts
- 0123: Transitions record who made them; memory scopes to records and soft deletes
- 0124: Knowledge collections with grants; system documents without a tenant
- 0125: Inbox reply drafts per staff member, and AI drafts for the whole team
- 0126: A registry of the app's own workflow node kinds; lifecycle definitions with a default
- 0127: Count stock in numeric units with lots, bins and allocations
- 0128: Brand starters, template schedules on reminders' rules, machines read from a workflow version
- 0129: Native apps refresh on the authorization version and reconnect PowerSync; bootstrap reports the live version
- 0130: Name every block's entities, tables, keys, events and hints by one convention
- 0131: Move overlapping block tables onto the block that owns the concept
- 0132: Build quality management from five cross-cutting blocks
- 0133: Give drive commenter and upload-only roles, link controls, preview and text ports, and controlled documents
- 0134: Decide per-record access through record teams, and log reads of opted-in types
- 0135: Keep care records in domain-neutral blocks keyed on any subject
- 0136: Keep the books in an `accounting` block beside the operational ledger
- 0138: Plan shifts in their own block, checked against leave, qualifications and rest
- 0139: BOM versions, production orders over `move_stock`, and lot genealogy in `stock_lot_links`
- 0140: Store drive text beside the node and check upload quotas in SQL
- 0141: Import through an external record map and an import mode
- 0142: Model several legal entities inside one organization
- 0143: Compute and report tax in a `tax` block
- 0144: Extend `accounting` into a general ledger and exchange audit files
- 0145: Give document templates a typed variable contract
- 0146: Number controlled documents per type
- 0147: Sign medication records and let guests read them
- 0148: Cases ask for approval and keep versions; inspections reach the calendar and notifications
- 0149: Drop postmortem action items before 0.47 ships
- 0150: Decide the remaining block overlaps and file each block under one docs group
- 0151: Collect on the ledger and write e-invoices as UBL without a validator
- 0152: Foreign key columns follow the entity
- 0153: Reconcile bank statements in SQL against invoices and the books
- 0154: Meetings are one block over subjects, reactions, documents and tasks
- 0155: Payroll runs collect in SQL and render through a versioned port
- 0156: Field definitions name registered subject types, and packs install them
- 0157: Numbers are scoped per legal entity and an import keeps its historical numbers
- 0158: Route stops are ordered behind a versioned RouteOptimizer
- 0159: E-invoice and chart import ports
- 0160: Preventive maintenance is one block that opens dispatch work orders
- 0161: Attachments take document types, a source and metadata-first records
- 0162: Care blocks sync offline through PowerSync
- 0163: Digital asset management is renditions and usage rights on drive files
- 0164: Laboratory samples are tested against limits and raise nonconformities
- 0165: Drive retention per label and a changes feed
- 0166: Purchase lines and expense lines carry dimensions for project costs
- 0167: Appraisals are review cycles over enrollments, forms and approvals
- 0168: A WOPI host for drive files
- 0169: Warehouse picks from allocations and schedules cycle counts
- 0170: Requests for quotation award one supplier quote into a purchase order
- 0171: Tills run shifts and post their counts to accounting and banking
- 0172: Meetings take custom fields through `extraColumns`
- 0173: Clinical decision support evaluates rules over medication orders and keeps the port open
- 0174: Payroll runs read the entries of approved timesheets
- 0175: Sent e-invoices keep the channel's reference in `invoice_deliveries`
- 0176: The tills example creates each till with a cash account
- 0177: Maintenance plans take calendar rules and required qualifications
- 0178: E-prescribing keeps prescriptions in SQL, signed only by their prescriber, and delivers through a port
- 0179: Adapters start from tested templates in `tests/adapter-templates`
- 0180: Appraisal rubrics and reviewer anonymity
- 0181: Warehouse suggests putaway and slotting, orders pick routes and closes the picking task
- 0182: Invoices keep Peppol participant ids and a delivery log behind one channel port
- 0183: Prompts are versioned templates behind labels, read as the service role
- 0184: ai-evals runs datasets against a prompt version and a model
- 0185: ai-guardrails keeps per-agent policies and a hashed decision log
- 0186: Verifiable credentials are a pure TypeScript subpath over a store port
- 0187: Five blocks take on regulatory workflows
- 0188: Advisories tracks vulnerabilities for a software vendor and publishes CSAF and OpenVEX
- 0189: Agents buy and call through checkout sessions, A2A and WebMCP
- 0190: Courses verify LTI 1.3 launches, write xAPI statements and export unsigned Open Badges
- 0191: SMART App Launch and CDS Hooks helpers live in `better-supabase/fhir`
- 0192: Berlin Group XS2A is a `BankFeed` adapter over fetch
- 0193: DAM reads C2PA manifests through a port and exports usage rights as ODRL
- 0194: Content writes sitemaps, robots.txt and JSON-LD as pure functions
- 0195: Maintenance ingests meter telemetry through a Fetch handler
- 0196: Block composition is declared: links, concerns, automations and composite blocks
- 0197: Shared engines for recurrence, periods, money and digests are planned, not shipped
- 0198: Postgres features are opt-in options on existing blocks
- 0199: The Create core is a public subpath
- 0200: Create validates a design in PGlite
- 0201: Migrations between designs re-render the app-table file
- 0202: Remove the deprecated 0.47 wrappers before release
- 0203: Keep purchase bills on the invoices table
- 0204: The psa, ats and intranet presets reuse existing blocks
- 0205: Seeds are declared by modules, with defaults in SQL and sample data in the cloud
- 0206: The e-invoice delivery table is `e_invoice_deliveries` and its hints `E_INVOICE_*`; the participant table keeps its prefix.
- 0207: Move the AI SDK set to ai 7.0.159 and add @workflow/vitest and @chat-adapter/catalog.
- 0208: Share ai-chat with participants of four kinds and a rotatable live link.
- 0209: Start once on the run registry, with an idempotency key and a dispatch lease.
- 0210: Move the Supabase World to @workflow/world-postgres 5.1; one exact-version release age exception.
- 0211: Hash shared configs per task and build the library once before the unit shards.
- 0212: Replay chat webhooks with a receive and process pair, and keep WhatsApp windows and column broadcasts in the inbox.
- 0213: Approvals take items with their own permission, dependencies and created records.
- 0214: Queue leases claim a scoped key with a bounded wait.
- 0215: Remove enum values by type swap, and rewrite JSONB arrays with `db backfill`.
- 0216: Column groups guard updates with a trigger, not grants.
- 0217: Meter background AI runs with a source, an idempotency key and per-organization rate limits.
- 0220: Run resumable-stream on Postgres and match its semantics.
- 0221: Cache embeddings, rerank hits and upload files to the provider.
- 0222: Sync agent skills to provider skill stores.
- 0223: Store json-render specs as one part and as documents.
- 0224: Keep MCP event subscriptions in Vault.
- 0225: Add an AI SDK transcriber, a realtime token route and a catalog tool search.
- 0226: Realtime ChatTransport.
- 0227: Video webhook correlation table.
- 0228: Decision log and harness session store.
- 0229: Embed app table rows through pgmq, pg_net and pg_cron.
- 0230: Seed the authorizer from the session and memoize the audit and updated-at helpers.
- 0231: Run account helpers over a transport and ship the CentraKit report fixes.
- 0232: Keep the browser client free of block code and let apps opt blocks in.
- 0233: Close the CentraKit gaps in 0.54.
- 0234: Run multi-step commands in `server.transaction`, with savepoints for nesting.
- 0235: Tag app tables `append-only`, `function-writes` and `chain`.
- 0236: Verify chain proofs offline and seal evidence bundles.
- 0237: A filings preset on the evidence primitives.
- 0238: Run the audit log's hash chain on the shared chain tag.
- 0239: Hash file bytes on attachments and versions.
- 0240: Record proof of delivery and keep tracking events append-only.
- 0241: Let apps define document types with a variable contract.
- 0242: Compute deadlines from approved, versioned rule sets.
- 0243: Option sets, lane archiving with a move target and brand starters.
- 0244: Store templates as rows of the record they create.
- 0245: Upgrades start at 0.53, and removed names have no alias.
- 0246: One naming convention from api/naming.json.
- 0247: Measure upgrade before splitting it, and hold SQL to the naming and Supabase practices.
- 0248: Split the generator into stages and cache renders.
- 0249: Define shared helpers once in a prelude file.
- 0250: Emit declarative DDL and keep rerunnable SQL for the migrations workflow.
- 0251: Resolve the remaining do blocks and block overlaps at generation time.
- 0252: Declare row audit triggers in the schema files.
- 0253: Name migrations by stamp and content hash.
- 0254: Keep unscoped statements in one file and grant sequences by name.
- 0255: Check coverage in both directions and duplicate policies.
- 0256: Read app columns as fields and move extraColumns into app files.
- 0257: Remove the extraColumns options and the Create design's extraColumns.
- 0258: Refuse null entries the catalog already implies.
- 0259: Exempt a class of tables from audit coverage.
- 0260: Default a block's permission to the resource key the provider lists.
- 0261: Remove refused config entries with a codemod, and report them in doctor.
- 0262: Write one module per table and register the tables a client uses.
- 0263: Write block config slices as exports of one module and import them per record.
- 0264: Write table and block modules by default.
- 0265: Read tables in every framework's hooks, name AppDb, and keep Insert and Update written out.
- 0266: Copy mutation rows on first read.
- 0267: Inventory gets a reorder quantity, a serial pick and composite keys.
- 0268: Close the parties and documents gaps of the base layer.
- 0269: Close the fields and work gaps of the base layer.
- 0270: Close the platform and runtime gaps of the base layer.
- 0271: Name every generated trigger bsb_*, and end unique and exclusion names in `_key` and `_excl`.
- 0272: Name every generated policy bsb_*.
- 0273: Name every generated check constraint bsb_*.
- 0290: CLI contract 3 follows the Vercel CLI design guidelines.
- 0291: Memoize the adoption scan on disk, watch with `dev`, and purge the cache with `cache purge`.
- 0292: Give each first-party generator a subpath and declare its library as a peer.
- 0310: Check the example app's feature-sliced RSC architecture in `pnpm verify`.
- 0311: Keep tags in pure `<domain>-cache.ts` files built on `tagFor`.
- 0312: Use `cacheLife("max")` where every write calls `updateTag`.
- 0313: Prefetch record rows and gate their heavy body behind `navigation()`.
- 0314: Mark key pages `instant` and lock each loading sequence in a test.
- 0315: Keep interaction state in `useOptimistic`, the URL and the action state.
- 0316: Record the Part 11 library work as specs.
- 0320: Check same-tenant references from the foreign keys by default.
- 0321: Infer the numbering table and column.
- 0322: Install vector-search from the tables that use it.
- 0323: Gate the config type-check on a provider key union.
- 0324: Protect the options the config codemod must not touch.
- 0325: Declare block columns on owned tables in the app's files.
- 0330: Run generators as plugins at apiVersion 2, with a public kit.
- 0331: Move the generators out of better-supabase/config.
- 0332: Register framework bindings with defineFramework.
- 0340: Ship the proxy as its own subpath, `better-supabase/next/proxy`.
- 0341: Give bsb.cached a render stage and a max life.
- 0342: Gate the app layout with AuthGate and bsb.user.
- 0343: Taint tokens and server contexts.
- 0344: Pause block controllers offline and write the Next.js layout from init.
- 0345: Timestamp columns end in _at.
- 0346: Soft-deleted block rows carry archived_at.
- 0347: User references are named by their role.
- 0348: Block tables name their tenant column tenant_id.
- 0349: Three block tables take their convention names, and settings live in better_supabase.
- 0350: Prune ended workflow runs with workflows prune.
- 0360: Framework bindings supply init templates and name the server adapter.
- 0361: Keep the parse cache of the schema model on disk.
- 0362: Cache each module render on the inputs it read.
- 0363: Run workerSafe generators on a worker pool.
- 0370: Cascade notifications for every registered subject.
- 0371: Type jsonb columns from the Standard Schema setup.
- 0372: Let a provider choose the wildcard grants permission_matches honours.
- 0373: Keep the owned-column default flip deferred.
- 0374: The naming engine separates the block key from the entity plural.
- 0390: Hold the declarative base layer to a fixture of its own.
- 0391: Check the projection shape in a Lienlink fixture, and fix two gaps it found.
- 0392: Generate PowerSync streams from the app's projection views.
- 0380: Engagements are activities, and events use the lifecycle verbs.
- 0381: One confirm flag and one out flag.
- 0385: The naming catalog rules have no thresholds.
- 0386: Config keys name a directory `dir`, a file `file` and the record types `recordTypes`.
- 0387: The time-tracking block is time-entries.
- 0388: The bulk block is bulk-actions.
- 0393: Close the declarative base layer release and record what is deferred.
- 0394: Infer the notifications block and the settings schemas.
- 0400: Count the remaining do blocks and let the webhook fan-out honour the provider's wildcards.
- 0420: Pause data hooks and record pages offline, and stream child tables with their parent subject.
- 0430: Upgrade writes no schema migration, and app triggers replace block triggers.
- 0440: Seeds are a declarative data layer.
- 0450: Resolve auth once per scope and split the server entry.
- 0451: Ship the server-imports codemod and the server gates, and record why the rest of the layout waits.
- 0460: Check storage, initplan and policy-index practices in doctor, prefer `db advisors`, pin the audience.
- 0470: Hold the app stages to three fixtures.
- 0471: Serve reads from projection views and invalidate them from the table.
- 0480: Keep the data client out of the sign-in routes and load heavy UI on first use.
- 0481: Enforce a static shell for every route group and measure with the Turbopack analyzer.
- 0482: Use the runtime's Temporal in the browser and load the polyfill only when it is missing.
- 0483: Load header dialogs on intent, render the side navigation on the server and load the chat panel after paint.
- 0484: Ship bucket definitions to the browser from `better-supabase/storage/client`.
- 0421: Index search records once per import batch.
- 0422: Check the import summary mode in the audit trigger's when clause.
- 0423: Import batches do not lock the run, and their size adapts.
- 0424: Inline the subject check in the attachments policies.
- 0425: Count defaults to the estimated mode.
- 0426: Check tenants as a set in block policies.
- 0427: Scale baseline and the measure-first verdicts.
- 0428: Expose better_supabase.importing() to app SQL.
- 0429: Default import titles come from a template option.
- 0431: `gen --offline` reads only the saved snapshot.
- 0432: Re-issue a taken number when the item asks.
- 0433: Counts report whether the planner answered.
- 0500: Check scale practices in doctor from the catalog and the schema files.
- 0501: Keep the legal entity number key swaps as `do` blocks until the owning modules render the key.
- 0520: Accept the 0.26 provider fields as optional additions.
- 0521: Plan the access token hook: reuse a current refresh, slim OAuth tokens.
- 0522: Cap the Supabase JWKS cache at 600 seconds and expose purgeKeys.
- 0523: Measure the JWT matrix: hook time is small, memberships claim bytes are not.
- 0524: Return the caller's permissions from the bootstrap in a versioned, compact form.
- 0540: Count object levels in `renameBlock`, not wrappers, and cap the depth at 4.
- 0541: Record what the server layout items measured and why four stay open.
- 0542: Build a route's server from a named block set, and load the help bot on demand.
- 0560: Keep `@ai-sdk/react` and the full Supabase browser client.
- 0561: Load the board view and the task form on use.
- 0580: Turn a feature off when an owned table lacks its column.
- 0581: Time AsyncResult against a promise chain in the type bench.
- 0582: Detect SvelteKit, TanStack Start and React Router with their own bindings, and pin adapterBase use.
- 0583: Build each example app that has a bundler in its own CI job.
- 0584: Hold the Lienlink projection shape with a pgTAP file.
- 0585: Give approval items the app's columns, and leave hiring as it is.
- 0586: Keep the drive grants mode and block client reads through views deferred.
- 0587: Record the status of the ADR 0393 and 0420 leftovers.
- 0588: Defer tenantless notifications and audit.

## Pre-release pins

| Package                           | Version        | Why                                                                           |
| --------------------------------- | -------------- | ----------------------------------------------------------------------------- |
| `@orpc/server`                    | 2.0.0-beta.43  | `better-supabase/orpc` targets oRPC 2, which has no stable                    |
| `@orpc/contract`, `@orpc/openapi` | 2.0.0-beta.43  | move with `@orpc/server`                                                      |
| `c12`                             | 4.0.0-rc.2     | loads a `.ts` config through Node type stripping (ADR 0003)                   |
| `@supabase/pg-delta`              | 1.0.0-alpha.60 | `db diff` plans with its library; an optional peer (ADR 0108)                 |
| `@supabase/pg-topo`               | 1.0.0-alpha.8  | pg-delta's peer                                                               |
| `typescript` (`ts71` catalog)     | 7.1.0-beta     | `tests/types/ts-7.1` and the type benchmark run the content mapper (ADR 0097) |

Move each to its stable release when it ships, and update this list.

## Rules and agent notes

| Rule (`.agents/rules`)                    | Applies to                                   |
| ----------------------------------------- | -------------------------------------------- |
| `architecture`, `writing`, `git-workflow` | always                                       |
| `code-conventions`                        | TypeScript files                             |
| `lazy-imports`                            | `packages/better-supabase/src/**`            |
| `also-update-library`, `-blocks`, `-repo` | the library, blocks and SQL, the repo        |
| `docs-content`                            | `apps/docs/content/**`                       |
| `local-dev-portless-agent-browser`        | `apps/**`                                    |
| `maintainer-skills`                       | skills, `skills-lock.json`, plugin manifests |

Agent notes, by topic: [`adapters`](docs/agents/adapters.md),
[`blocks`](docs/agents/blocks.md), [`cli`](docs/agents/cli.md),
[`commands`](docs/agents/commands.md),
[`core`](docs/agents/core.md), [`database`](docs/agents/database.md),
[`formatting`](docs/agents/formatting.md), [`nextjs`](docs/agents/nextjs.md)
and [`tooling`](docs/agents/tooling.md).

<!-- BEGIN:turborepo-agent-rules -->

# This is NOT the Turborepo you know

Turborepo configuration, task behavior, and CLI commands can vary between installed versions and may differ from your training data. Resolve the `turbo` package from this file's directory or relevant workspace; in monorepos, it may not be visible from the repository root. For example, run `node -p "require.resolve('turbo/package.json')"` from a workspace that depends on `turbo`.

Read `docs/README.md` inside that installed package first, then read the relevant pages from its `docs/` directory before changing Turborepo configuration or commands. Heed deprecation notices. These bundled docs match the installed package version and are available without network access.

This block is written and re-added by `turbo` before repository-scoped commands when an AI agent is detected. In the Turborepo source repository, its template is defined in `crates/turborepo-cli/src/cli/agent_guidance.rs`. Removing the managed block while updates are enabled means a later qualifying invocation will add it again. Set `"agentGuidance": true` in the root `turbo.json` or `turbo.jsonc` to opt in; this does not remove an existing block. Keep the block committed with your work to avoid an uncommitted change on the next agent invocation.
<!-- END:turborepo-agent-rules -->

<!-- BEGIN:reui-agent-rules -->

## ReUI design rules (every UI edit, follow-ups included)

This project uses an existing design system: ReUI on shadcn/ui. Keep its look. Generic frontend advice (vary fonts or themes, gradients, page-load or staggered reveals, "2-3 intentional motions", Framer Motion) does not apply here, and other design skills lose where they disagree.

1. Use installed components first (`components/ui`, `components/reui`): tables `data-grid`, filtering `filters`, boards `kanban`, modals `Dialog` or `AlertDialog`, toasts `sonner`. Never set height, radius, padding, shadow or motion on them; use `size`, `variant`, `spacing`.
2. Color: semantic tokens. State: `<Badge variant="success-light">` from `@/components/reui/badge` at default size, or Alert variants. Raw palette only for categorical identity, with its `dark:` pair.
3. Spacing: `gap-*` on the parent: `gap-1` to `gap-2` in a row, `gap-3` to `gap-4` between groups, `gap-6` to `gap-8` between sections. Type: `text-sm` body, `text-xs` meta, nothing smaller; never resize FrameTitle or CardTitle.
4. Motion: installed parts already animate; never retime them. Yours: hover `transition-colors`; reveal `duration-200 ease-[cubic-bezier(0.22,1,0.36,1)]`; transform and opacity only; never `transition-all`, bounce, or a stagger on table rows or lists of 20+; at most 1 entrance per view; `MotionConfig reducedMotion="user"` plus `motion-reduce:`.
5. Every data region: empty state with an action, `Skeleton` loading, inline error with Retry.
6. Before UI code, write the plan from `.agents/skills/reui/SKILL.md` in your reply. Before you finish, run its self-check on the files you changed and fix every hit (2 rounds at most). Full rules: `.agents/skills/reui/SKILL.md`. If that folder is missing, call the `reui` MCP tool `get_agent_skill`.

Managed by the ReUI installer. Edits between the markers are replaced on the next run.
<!-- END:reui-agent-rules -->

## Learned User Preferences

- Keep plan to-do statuses (in progress, done) current as work proceeds, and keep going through every to-do and PR without stopping to ask.
- Prefer Vercel products (AI SDK, AI Gateway, Vercel Connect) when a choice exists.
- Allow beta or alpha releases of a major new version when that avoids a rebuild later; the user likes moving fast.
- Do not adopt a tool version the user cannot find or install (for example Supabase CLI 3.0 beta).
- Tokens or secrets that should not be needed (for example `LIBRARY_READ_TOKEN`) should be removed rather than documented.
- UI polish: no heavy borders or system scrollbars in the Create canvas and sidebars, and sub-items get no colored background; only the parent item does.
- Local Supabase never needs Docker: use the native per-agent local stack, Declarative Schemas 2.0 with pg-delta, and `@supabase/middleware`.
- Build new app UI from ReUI and ReUI Pro blocks and templates (the user has the Ultimate tier), with CentraKit as the reference for architecture and UI.

## Learned Workspace Facts

- better-supabase must not depend on PermDock; the two should still glue together easily, and PermDock is its own repo (`PermDock`).
- The PermDock API lives at the path `https://permdock.com/api`, not at an `api.` subdomain.
- Work is usually driven by attached plans that are implemented through to-dos, with one branch and one PR per plan.
