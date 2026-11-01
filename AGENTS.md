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

- 0001: the library profile of the repo standard.
- 0002: the deviations and lint backlogs, each with what ends it (CI shape, Ask AI tools,
  the support-storage rehearsal, `tracedFetch`).
- 0003: the CLI runs on citty (package split superseded by 0007).
- 0004: maintainer skills in `.agents/skills` are committed.
- 0005: the public API uses Temporal.
- 0006: the fixture schema diffs with pg-delta.
- 0007: the CLI ships inside `better-supabase`, dependencies inlined.
- 0008: the server and adapters run on `@supabase/middleware`.
- 0009: `stripe` is a lazy optional peer; OpenFeature is typed structurally.
- 0010: AI blocks stay SDK-neutral; SDK adapters own no tables.
- 0011: authorization is a versioned `AuthorizationProvider`.
- 0012: kits are blocks, imported from `better-supabase/blocks/<name>`.
- 0013: SDK adapters that need Node are Node-only entries.
- 0014: `better-supabase/nestjs` loads `@nestjs/common` with `createRequire`.
- 0015: blocks extend through `fields`, `hooks`, middleware and `extendBlock`.
- 0016: `@supabase/postgrest-typegen` is a peer range; the pin stays exact.
- 0017: one `ApiModel` renders every OpenAPI, Overlay, Arazzo and AsyncAPI version.
- 0018: a subject binding can name the adopted table it lives in.
- 0019: security definer writes refuse read-only support sessions.
- 0020: subject types are declared once in `config.subjects`.
- 0021: rows are ordered by base-62 fractional rank keys.
- 0022: Yjs documents are an update log and a snapshot in Postgres.
- 0023: the bookings block installs `btree_gist`.
- 0024: money is `bigint` minor units; payments and tax are versioned providers.
- 0025: the drive is two modules on attachments.
- 0026: delegated tokens are narrowed in the access functions (`OPERATIONS`).
- 0027: the fixture migrations are one pg-delta baseline.
- 0028: record stages run on tenant-editable pipelines.
- 0029: every block is one `defineBlock` manifest wired by `createBlocks`.
- 0030: block client state lives in headless controllers.
- 0031: presets install blocks; UI ships as recipes over the app's shadcn components.
- 0032: the fixture runs on the CLI's stack engine with ports per branch.
- 0033: signing keys live in Vault; signing runs in TypeScript with WebCrypto.
- 0034: retention policies and legal holds; a hash-chained, partitionable audit log.
- 0035: the Flags SDK adapter is structural; brands are custom flag contexts.
- 0036: every SDK integration is an optional peer with a tested range.
- 0037: every amount is `Money`; block SQL returns int8 as text, decoded strictly.
- 0038: outbox, usage history, webhook deliveries and notification delivery events partition by month on opt-in.
- 0039: the Create page names PermDock as one optional auth choice.
- 0040: `appTables` renders the app's own tables; a Create design rides on the URL as `&design=`.
- 0041: Create deploys a preset through a Supabase OAuth app; tokens live in a sealed cookie.
- 0042: app table columns take a format, options and bounds; tables take composite keys and an id type.
- 0043: an app table becomes a subject through `appTables.<name>.subject`.
- 0044: app table rollups and lookups render as a `security_invoker` view, from structured keys only.
- 0045: the CLI runs from one command tree, with one JSON envelope, agent mode and the `bsb` short name.
- 0046: tenant rules are filter trees with `{ kind, config }` action references, evaluated in TS and SQL.
- 0047: the CLI contract is published for other CLIs: codes, envelope, help document, consent.
- 0048: app tables emit outbox events from a trigger; rules and workflows consume them through sinks.
- 0049: `better-supabase mcp` serves the CLI on stdio; write tools need a consent token.
- 0050: doctor lints unapplied migrations for locking statements (BS229 to BS235).
- 0051: app table columns restrict access to `read` or `server` with Postgres column grants.
- 0052: billing webhooks keep subscriptions, guarded by `event_at`.
- 0053: usage meters can count distinct values or compute a value on a schedule.
- 0054: a Vercel Marketplace block and a Vercel Queues jobs backend, without `@vercel/*` dependencies.
- 0055: the Create page connects a PermDock Cloud account through OAuth with PKCE.
- 0056: audit resolves tenants through a path or function and names the acting member.
- 0057: Create runs in the cloud app at `app.bettersupabase.com`; marketing redirects `/create` there.
- 0058: a design too large for a URL reaches `init` and `add --preset` as a JSON design file.
- 0059: `db diff` diffs inside the running stack when the shadow database can't start; `dev stack prune` frees segments.
- 0060: block entities rename per block (`blocks.<name>.entities`); keys are typed and entities register as subjects.
- 0061: `gen` writes block schemas, name constants, nuqs parsers and factories; their libraries stay optional peers.
- 0062: one messaging core; channels first, then comments and the inbox move onto it (breaking).
- 0063: the activity feed moves out of comments into its own `timeline` block.
- 0064: blocks compose through sections and flows; library logic, generated bindings and recipe UI.
- 0065: balances live in one double-entry `ledger`; inventory stock, leave balances and invoice payments move onto it (breaking).
- 0066: `assets` stores coordinates as numbers; PostGIS geography columns and area lookups are the `postgis` option.
- 0067: votes are reactions of kind `vote`; `scores` computes versioned scores from tenant-editable models (breaking).
- 0068: calendar free/busy runs in SQL; appointment schedules are bookings resources with a host.
- 0069: document suggestions wait outside the update log until an editor accepts them; named versions are version labels.
- 0070: guests reach granted records through `ctx.scope.guest`, never as members; providers answer through `portalSubjects`.
- 0071: drive labels are tags; file approvals target one attachment, and both follow the drive grants.
- 0072: a record merge moves every module's rows through handlers marked `better-supabase:subject-merge`.
- 0073: admission passes carry a signed token; the database keeps the nonce and decides every scan.
- 0074: billable time prices entries from a rate card; billed entries lock until the invoice is voided.
- 0075: record presence, record mentions and saved items build on the subject registry.
- 0076: one moderation item per subject; reviews and comments moderate through `moderation` (breaking).
- 0077: `enrollments` tracks subjects through programs of steps; onboarding checklists run on it (breaking).
- 0078: member mailboxes sync into engagements through a versioned `MailProvider` over `fetch`.
- 0079: segments materialize rules filter trees; assignment queues pick owners by turn, weight and territory.
- 0080: balances live only on the ledger; rent and pledges post once per period, keyed by owner and period start.
- 0081: enrichment stores provider profiles per record and fills only empty columns, through a versioned provider over `fetch`.
- 0082: shipments go through a versioned `ShipmentCarrier`; tracking arrives by a signed, idempotent webhook ingest.
- 0083: forecast snapshots copy the deals behind each number; field history is a trigger per tracked table.
- 0084: the public status page is one security definer function anon may call, returning only public fields.
- 0085: `courses` enrolls learners through `enrollments` (`course:<id>`); quizzes are graded by `forms` in SQL.
- 0086: recurring bookings place each occurrence through `place_booking`; class credits are a ledger refunded on early cancel.
- 0087: encrypted fields use per-owner Vault keys and decrypt through scoped definers; reads there can be audited.
- 0090: confirmed bookings become meeting engagements through a trigger on the bookings table.
- 0091: sequences run on enrollments and send email steps through a `mailer` port from mail-sync.
- 0092: posts keep boards and posts; votes, replies and moderation stay in their blocks.
- 0093: blocks install as named instances behind one data contract; plugins, sections and preset codes go (supersedes 0064).
- 0094: supported adapters (Next.js, Hono, Expo, SvelteKit, TanStack Start, React Router) get the full test matrix; the rest are community adapters with a smoke test.
- 0095: one token verification per request across cache scopes, through a session memo keyed by the token.
- 0096: authorization libraries pass a version cache to `createServer`; `subscribeAuthzVersions` evicts users on a Realtime broadcast, and `SessionProvider` refreshes on the user's `authz:<uid>` topic.
- 0097: `gen.contentMapper` serves the schema types through a TypeScript 7.1 content mapper; the `ts71` catalog pins the beta for tests only.
- 0098: blocks detect the app's tables per table (`ownTables`) and run over them; every block table is adoptable except the `workflow-sdk` world; `ownership: "adopt"` is removed (breaking).
- 0099: tenant isolation renders as one restrictive `bsb_tenant_scope` policy per tenant table; an app's permissive policy can't widen it.
- 0100: One project pipeline for the config, the CLI, Create and the cloud; `checkProject` returns one `Issue` type.
- 0101: Adopt one rung at a time: `init`, helpers for every table, table features, blocks over your tables.
- 0102: Tables are user-owned SQL; per-table features are `@bsb` tags in the table comment; block SQL defaults to `supabase/schemas` with the `900_better_supabase` prefix.
- 0103: Block modules emit typed `Policy` values; the tenant scope and actor guard compose on them.
- 0104: Per-command tenant scope to public, default privileges, anonymous excluded, rls-guard on.
- 0105: The catalog is verified offline and by a generated role by command by table access matrix.
- 0106: The CLI plans migrations with pg-delta's library plan: renames, hazards and data loss.
- 0107: `designDataApi` stays in `create/lite`.
- 0108: `db diff` plans with pg-delta's library on the stack's postgres role; renames and data loss are gated.
- 0109: Hooks run an affected lint and typecheck, tests run in CI as shards, Next.js builds prerender a few pages outside Vercel production, worktrees set themselves up.
- 0110: Flags keep revisions in Postgres, roll out on schedules and draw weighted splits from a second bucket.
- 0111: Workflow SDK start keys are claimed in `workflow_run_keys`; ended runs purge in SQL (`retention`, `db prune-workflows`).
- 0112: Vercel Sandbox runs chat sandboxes through an optional-peer adapter; credentials reach the VM only at its firewall.
- 0113: eve tools run as the user through `forContext` with delegated scopes; approvals block approvals and queue schedules drive them.
- 0114: Authorization libraries get a typed, additive contract: `claims` and `contract` subpaths, request intent and source, typed `versions`, approval ids, `blockTables`.
- 0115: A page reads its user data in one `bsb.bootstrap` call, private or remote, from a generated `bootstrap_<rpc>` wrapper.
- 0116: One JWKS per process on `globalThis`; one verified-token memo per server; clients on `createContextClient` and `createAdminClient`.
- 0117: Sessions refresh through `@supabase/ssr` on every request; a coalescing fetch makes one Auth call per refresh token.
- 0118: Calendar alarms are event data in `calendar_event_alarms`; reminders fire on any subject's rule, `at` column or own time, planned by the `reminders.schedule` timer.
- 0119: Tenant approval policies tighten config floors with conditions and a confirm or authorize mode; manager approvers; approvals consumed once against a fingerprint.
- 0120: Quotes publish immutable `quote_versions` and revise in place; document discounts, VAT-inclusive prices and deposits count per tax rate into `quote_tax_lines`.
- 0121: Enrollment steps carry an assignee and a due date, rendered into open `enrollment_steps` rows with `due_at`.
- 0122: ai-chat runs without a tenant (`tenant: false`), shares chats through `ai_chat_participants`, and `messages` keys a linear list by uuid with native parts (amends 0010).
- 0123: `transition()` takes `{ reason, actor }`; history keeps the actor's name, email, IP and user agent, or `history: "app"` leaves it to the app. Memory gets a `record` scope, expiry, confidence and soft deletes.
- 0124: Knowledge collections with a visibility, a priority and user or team grants; system collections and documents have no tenant and every tenant reads them.
- 0125: `inbox_drafts` keeps one open reply draft per staff member and conversation; the service role suggests AI drafts the team sends or discards.
- 0126: `workflow_node_kinds` registers the app's own node kinds (`defineNodeKind`, run as steps); definitions take a `purpose` and one default lifecycle workflow per subject type.
- 0127: Stock is `numeric` with a unit scale and posts base units; lots, serials, bins, average cost, document allocations, orders from lines or a quote, and shipment lines.
- 0128: Templates gain brand starters and schedules on reminders' rules; a machine reads its edges from a workflow version; timelines add transitions and messages.
- 0129: Native apps refresh on the authorization version and reconnect PowerSync; bootstrap reports the live version next to the token's.
- 0130: One naming convention for blocks: entity keys, tables, `<area>.<verb>` permission keys, `<entity>.<past tense>` events, hint codes, functions and docs titles (partly supersedes 0093).
- 0131: Inbox contacts, sequence enrollments, AI file versions and postmortem actions move onto `contacts`, `enrollments`, `versions` and `tasks`.
- 0132: Quality management is five cross-cutting blocks (`acknowledgements`, `cases`, `inspections`, `risks`, `qualifications`) linked through `relations` kinds.
- 0155: Payroll runs collect hours and leave in SQL, lock behind an exported file and render through a versioned `PayrollExportFormat`.
- 0158: Route stops are ordered in TypeScript behind a versioned `RouteOptimizer`, with a nearest-neighbour fallback that never fails.
- 0157: The `psa`, `ats` and `intranet` presets reuse existing blocks; HRIS stays `people` and help desk stays `helpdesk`.
- 0133: Drive gets commenter and upload-only roles, link passwords and download control with previews on their own path, versioned text and preview ports, and controlled documents.
- 0134: Record teams (`subjects.<type>.team`, `subject_members`) grant per-record actions in `can_subject`; emergency access and read logging build on them.
- 0135: Care plans, observations, medications, consents and funding are domain-neutral blocks keyed on any subject, with FHIR R4 mappers and ports for national formats.
- 0136: Double-entry books live in the `accounting` block beside the operational `ledger`: account roles, journals, numbered entries in fiscal periods that close, FX, tax codes and reports.
- 0139: Manufacturing versions bills of materials, runs production orders over `move_stock` with `consumption` and `production` reasons, and keeps lot genealogy in `stock_lot_links`.
- 0138: Shifts are their own block; every assignment, request approval and swap runs one SQL check for overlap, approved leave, qualifications and rest.
- 0140: Drive keeps extracted text in `drive_node_texts`, searched through the `drive_node_search` view and filled from the outbox; `quota` checks `within_quota` on upload.
- 0141: Imports write through `import_upsert_batch` onto an external record map with content hashes; an import mode skips or tags events and audit and guards side effects.
- 0142: Legal entities live inside one organization as an opt-in `legal_entity_id` with a settings fallback; contacts stay shared.
- 0143: A `tax` block owns tax codes, rate history, `compute_document_tax` (margin, credit restriction), invoice tax lines, returns and the EU sales list (breaking).
- 0144: `accounting` grows into a general ledger (levels, locks, opening balances, open items, payment batches); `better-supabase/audit-files` exchanges SAF-T and XAF.
- 0145: Document templates read a typed variable contract, look up per legal entity and language, and use tenant-editable text blocks.
- 0146: Controlled document types can set a `numberFormat` and count from their own numbering entity.
- 0148: Purchase bills are invoices with `direction = 'purchase'`; receipts are rows, requisitions run on approvals, a three-way match gates payment, contacts credit limits gate orders and sales invoices.
- 0149: Postmortem `actionItems` and the `action_items` column go in 0.47; an `incidents` upgrade step copies them into tasks first.
- 0150: The remaining block overlaps are decided pair by pair (all stay separate, three follow-ups) and seven blocks move to the docs group that matches their job.
- 0151: Party payments keep their rest as ledger credit; dunning levels raise overdue invoices; `better-supabase/e-invoicing` writes UBL for Peppol without a bundled validator.
- 0152: The task and activity foreign key columns become `task_id` and `activity_id`, renamed by upgrade steps.
- 0153: Banking imports camt.053 and MT940 statements idempotently, suggests and matches invoices in SQL through `record_invoice_payment`, books rule matches in the bank journal; bank feeds are a versioned `BankFeed` port over `fetch`.
- 0154: Meetings are one block over subjects, reactions, documents and tasks; votes settle decisions and action items are tasks.
- 0156: Field definitions name registered subject types; packs install them by pack and key, and values can belong to a legal entity.
- 0157: Numbers are scoped per legal entity, an import keeps its historical numbers and the sync reports what does not match the format.
- 0159: E-invoice formats and channels and chart-of-accounts formats are versioned ports; nothing is bundled.
- 0160: Preventive maintenance plans by time or meter open dispatch work orders with their parts; readings and calibrations are records.
- 0161: Attachments take per-organization document types with typed metadata, a source and external id index, and metadata-first import records.
  ||||||| parent of 50dca684f (feat(powersync): sync progress notes, observations and doses offline)
- 0162: Care blocks sync offline: streams by organization and `read` role, upload routes that replay through block functions, clinical conflicts surface in `connector.rejected`.
- 0163: Digital asset management is renditions made through the drive preview port and usage rights with territory, channel and expiry on drive files.
- 0164: `lims` keeps samples, methods with specification limits and results; an out of specification result opens a `cases` nonconformity and blocks release, and instruments are assets with qualifications.
- 0165: Drive retention sweeps bin files by label, and a changes feed serves sync clients.
- 0166: Purchase bill lines and expense lines carry `dimensions`; a report books one expense line per dimension set, so project costs split.
- 0167: Appraisals run review cycles over enrollments, forms, goals and approvals, with calibration and sign-off.
- 0168: A WOPI host on the check-out lock lets office editors open and save drive files.
- 0169: Warehouse makes pick waves and lists from stock allocations, picking tasks and cycle count plans that hold large variances for review.
- 0170: `rfqs` sends requests for quotation to suppliers, compares their quotes and awards one into a draft purchase order.
- 0171: Tills run shifts with a float, cash movements and an end-of-day count that books its variance, then deposit and reconcile in banking.
- 0172: Payroll runs count only the time entries of weeks with an approved timesheet.
  ||||||| 550ced2a5
- 0172: Payroll runs count only the time entries of weeks with an approved timesheet.
- 0173: Clinical decision support raises dose range, duplicate therapy and interaction alerts from built-in rules and a versioned `ClinicalDecisionSupport` port.
- 0174: Payroll runs count only the time entries of weeks with an approved timesheet.
- 0175: Sent e-invoices keep the channel's reference in `invoice_deliveries`; `sendEInvoice` records it through the invoices client (amends 0159).
- 0176: The tills example creates each till with a cash account, mapped from or added to the accounting chart.

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
