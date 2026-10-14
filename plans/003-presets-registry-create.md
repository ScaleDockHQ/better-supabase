# 003: Composable blocks, presets, a shadcn-compatible registry and Create

Status: TODO. Written 2026-10-14 against `main` at `3d9920b`, with `feat/pipelines-foundation` (parties, pipelines, engagements) still open. That branch merges first; see "Order and conflicts".

The goal of better-supabase is mix and match: run everything with the default config, change behaviour by changing the config, and build a new SaaS by picking blocks, tweaking them and extending later. This plan has four workstreams:

1. **Decouple the blocks** so each one stands alone and the core stops knowing about individual blocks.
2. **Presets**: a named or encoded selection of blocks and conventions that `init` and `apply` install in one step.
3. **A registry that shadcn can read**, so the code an app should own (UI, wiring, routes) installs with `npx shadcn add @better-supabase/<item>` or with our own CLI.
4. **The website**: Components, Blocks and Create in the main navigation, modelled on ui.shadcn.com.

Each workstream lists its phases, the files it touches and what "done" means. An executor with no context from the analysis session can run it.

## Background: the analysis behind this plan

Verified against the code on 2026-10-14.

- **Block-to-block imports are not the problem.** There are 37 edges and no cycles, and no block depends on more than 2 others. `jobs` is the de facto shared kernel, with 15 blocks importing it.
- **Central registries know every block.**
  - `src/blocks/create-blocks.ts` hard-codes sibling wiring: the options `aiTaskNotification`, `reminderNotification` and `metricEvents`; the `files`/`notify`/`notifyDelivery` slots; the `aiFiles` special case; `build("notifications")` with a duck-typed `send`; and `sinks: {search, metrics}`.
  - `src/core/block-events.ts:683-914` is one closed `BlockEventMap` with 239 events, with payload types in core. Every new block edits it, and the pipelines branch does again.
- **Hidden instances.** `drive` builds its own `attachments` client and `workflow-builder` its own `workflows` client, so `createBlocks` hooks never reach them.
- **Tenancy is wired in everywhere.**
  - `access` is a hard requirement of 60 of the 92 SQL modules and `tenant` of 58.
  - Managed tables declare `organization_id not null`.
  - `better_supabase.can(`, `tenant_ids_with(` and `member_organization_ids()` are literal in about 60 SQL sites.
  - There is no user-scoped or single-tenant mode.
- **Leaks.**
  - `src/sql/modules/entitlements-source.ts:70-90` calls `moduleContext("billing" | "organizations")` without declaring them, and hard-codes `stripe_customer_id`, `organization_id` and `better_supabase.organizations`.
  - `"better_supabase"` is re-hard-coded in 7 block files despite `DEFAULT_BLOCK_SCHEMA`.
- **Two configurations per block.**
  - `sql.modules.<name>` and the TS block options are kept in sync by hand. `drive.ts:37-41` says "Must match `sql.modules.attachments.options.requireScan`".
  - Module `options` is `Record<string, unknown>` (`src/config/modules.ts:43`), so it has no autocomplete and errors only show at render time.
- **Extension points differ per block.**
  - `fields`: 2 blocks.
  - `extraColumns`: 3 blocks.
  - `hooks` as an option: 19 of 67 blocks.
  - `commerce`, `entitlements`, `outbox` and `webhooks` don't use `blockCall`.
  - Concept names (`create_organization`, `switch_organization`) cannot be renamed.
- **Onboarding.**
  - There are no presets, and recipes are copy-paste docs.
  - `init` never asks about blocks.
  - `sql add` prints a snippet in array form instead of editing the config, and the snippet clobbers a config in object form.
  - There is no global `api` default: the Next.js example repeats `api: "api"` about 30 times.
  - Adopting is null-heavy: the centrakit config is 397 lines for 21 modules.
  - The production ports (`validation-crm`, `validation-request-context`) adopt no blocks.

## What we take from shadcn

Read from the shadcn-ui/ui source: `packages/shadcn/src/commands/{init,apply,preset,eject}.ts`, `packages/registry/src/preset/preset.ts`, `apps/v4/content/docs/registry/*`, and the changelog entries `2025-12-shadcn-create` and `2026-02-blocks`.

| shadcn concept | What it is there | Our counterpart |
| --- | --- | --- |
| `/create` | Pick base library, style, colours, icons, fonts and radius; live preview; result is a preset. | `/create`: pick a framework, conventions (casing, tenancy, naming, API schema) and blocks; live preview of the generated config, migrations and wiring. |
| Preset code | Versioned base62 bit field (`PRESET_FIELDS`, append-only, version prefix char). The URL is `/create?preset=<code>`. | The same scheme with an append-only block list, encoded as a BigInt because there are more than 53 bits (see W2). |
| `init --preset <name\|code\|url>` | New project from a preset. | `better-supabase init --preset saas` / `--preset <code>`. |
| `apply --preset <code> --only theme,font` | Apply a preset to an existing project, partly if wanted. | `better-supabase apply --preset <code> --only blocks,conventions`. This is the adopt path for existing projects. |
| `preset decode` / `info` | Show what a code contains. | `better-supabase preset decode <code>` and `preset info`. |
| "Styles" (Vega, Nova, ...) rewrite component code | More than theming: code adapts to the chosen setup. | **Conventions**: casing, id type, tenant concept name (organization, workspace or team) and scope (tenant, user or none) rewrite table and function names and TS method names. |
| Registry items `registry:block`, `ui`, `component`, `hook`, `lib`, `page`, `file`, `item` | Universal items with `files[].target` (`~/` = project root, `@ui/`, `@lib/`, ...), plus `dependencies`, `registryDependencies`, `envVars`, `docs`, `categories` and `meta`. | Our UI, wiring, routes and pages ship as registry items. They depend on the npm package `better-supabase` and on shadcn primitives (`button`, `card`, ...). |
| Namespaces `@acme/item` and `components.json` `registries` | Decentralized registries, with auth headers and a public index. | `@better-supabase` in the shadcn registry index; `https://bettersupabase.com/r/{name}.json`. |
| `/blocks` | Pages with preview and code, installed by name (`add login-01`). | `/blocks`: one page per block with its config, migrations, wiring, UI and install commands. |
| MCP server | Agents browse and install registry items. | It works for free once we are a registry; we also keep our docs MCP. |
| "You own the code" | Components are copied into your project. | **A hybrid, and the most important design decision below.** |

### The hybrid: what is copied and what stays a package

Database logic does not belong in copy-paste: RLS, security-definer functions, triggers and the upgrade path through `sql upgrade` must stay versioned and upgradeable. UI and app wiring do belong to the app.

- **Stays in the npm package, configured through the config:** SQL modules, TS block clients, codecs, events.
- **Copied through the registry; the app owns it:**
  - React UI components on top of shadcn primitives (`NotificationBell`, `CommentThread`, `OrgSwitcher`, ...);
  - the wiring file (`lib/blocks.ts`);
  - route handlers (outbox relay, Stripe webhook, cron);
  - page templates (settings, members, billing, API keys).

So shadcn compatibility applies to the copied layer. Our own CLI handles the config and SQL, and uses the same registry for the copied part.

## Workstream 1: decouple the blocks

This is the prerequisite for presets. A preset only works if blocks really combine freely.

### 1a. Fixes with no conflicts (can start now)

- `entitlements-source.ts`: declare `billing` and `organizations` in `integrates`, and resolve the table, column and key through `ctx.of(...)`. Add a test with renamed billing columns.
- Replace the 7 hard-coded `"better_supabase"` literals in blocks (`catalog.ts:571`, `time-tracking/metrics.ts:32`, `drive.ts:684`, `orders/metrics.ts:28`, `outbox.ts:338`, `webhooks/secrets.ts:28`, `webhooks/incoming.ts:69`) with the block's `schema` option.
- Route `better_supabase.member_organization_ids()` and `has_organization_role` in `api-keys`, `flags`, `entitlements-checks` and `organizations` through `ctx.of("tenant").fn(...)`.
- A global default: `sql.api` (and `sql.schema`) in `src/config/types/database.ts`, which modules inherit unless they set their own.
- `sql add` edits the config file, using an AST edit that keeps the object form. Fall back to the printed snippet when the config is not a literal object.

Done when `pnpm verify` is green, the golden SQL is unchanged except where it was renamed on purpose, and there is one changeset per fix.

### 1b. `defineBlock` manifests (after the pipelines merge)

ADR 0029, "One manifest per block". Each block exports one manifest, for example `src/blocks/comments/manifest.ts`:

```ts
export const comments = defineBlock({
  name: "comments",
  sql: "comments", // the SqlModule key(s)
  options: commentsOptionsSchema, // Standard Schema, typed module options
  events: commentsEvents, // this block's own event map
  consumes: { notifier: optional<Notifier>() },
  provides: {},
  create: (ctx) => createComments(ctx),
  category: "collaboration",
  ui: ["comment-thread", "comment-composer"], // registry item names
});
```

- `createBlocks` wires on `provides` and `consumes`, never on names. `aiTaskNotification` and `reminderNotification` move to the ai-tasks and reminders manifests as options. The `notifications` manifest `provides: { notifier }`. `search` and `metrics` provide `sinks` through a generic `provides.sink`.
- **Events per block.** `BlockEventMap` becomes the inferred union of the manifests passed to `defineBlocks(...)`, which keeps invariant 2 (no `declare module`). App events become possible: `defineEvents({...})` is passed the same way. The payload types move out of `core/block-events.ts` into each block.
- **No hidden instances.** `drive` consumes `attachments` and `workflow-builder` consumes `workflows`, both through `consumes`.

### 1c. One config for SQL and TS

- `gen` emits `blocks.generated.ts`, which holds the resolved per-module config (schema, api, options that the TS side needs). `defineBlocks(generated, {...})` reads it, so `requireScan` and similar options live in one place.
- Module options are typed from each manifest's options schema. `ModulesConfig` becomes a mapped type over the registry. The JSON schema (`schemas/config-v1.json`) is generated from it. Check `pnpm typecheck:perf` after this change.

### 1d. One contract for every block, enforced by a conformance test

`tests/blocks/conformance.test.ts` iterates the manifests and checks:
- the creator is `create<Name>(options)` and takes `BlockOptions`;
- it accepts `hooks`;
- every managed table has `fields` and `extraColumns`;
- every call goes through `blockCall`;
- it has its own event map;
- it creates no sibling clients.

Start with a warning list (an allowlist of current exceptions) and shrink it to zero. Also normalize the outliers: `createBuilder` becomes `createWorkflowBuilder` and `createPushDevices` becomes `createPush`, each keeping a deprecated alias.

### 1e. Scope and naming as conventions

This step goes deepest and comes last.

- **Scope.** A per-module `scope: "tenant" | "user" | "none"`, with a project default in `sql.scope`. `access` and `tenant` sit behind a port (`ctx.scope.can(...)`, `ctx.scope.ids(...)`), so all literal `better_supabase.can(` sites go through `ctx`. Modules that need a tenant declare it in `scopes: ["tenant"]`, and the preset resolver refuses a combination that cannot work.
- **Naming.**
  - `sql.naming.tenant: "organization" | "workspace" | "team" | string` renames the tenant concept in table and function names (`create_workspace`), in columns (`workspace_id`) and, through `gen`, in TS method names, with aliases.
  - A `functions` rename map is added next to `tables` and `columns` for one-off renames.

This is the counterpart of shadcn's styles.

## Workstream 2: presets

### 2a. The preset model (`better-supabase/preset`, WinterTC-safe)

A new entry `src/preset/` holds:

- `PRESET_BLOCKS`: an append-only, ordered list of block names. Never reorder it and never remove an entry; a removed block keeps its slot as a tombstone.
- `PRESET_FIELDS`: append-only convention fields, each with `{ key, values, bits }`:
  - `framework`: `next`, `vite`, `tanstack-start`, `sveltekit`, `nuxt`, `hono`, `astro`, `react-router`, ...
  - `casing`: `snake` or `camel`
  - `idType`
  - `scope`: `tenant`, `user` or `none`
  - `tenantName`: `organization`, `workspace` or `team`
  - `access`: `roles`, `catalog` or `provider`
  - `api`: `public` or `api`
  - `integrations`: realtime, storage, edge
- `encodePreset(preset)` / `decodePreset(code)` produce a version char plus base62 of a BigInt (fields, then a block bit set). Version `a` is the first. Decoding an older version fills new fields with defaults and reports them as `derived`, as shadcn does.
- `resolvePreset(preset)` returns the full block set including `requires`, the soft integrations that are active, the conflicts (scope), and an explanation per block ("added because comments requires tenant").
  - It reads a generated **catalog** (`src/preset/catalog.generated.ts`) built from `SQL_MODULES` and the manifests by `scripts/build-catalog.ts`. That catalog holds name, title, category, requires, integrates, scopes, modes, options schema summary, events and UI items.
  - The resolver never imports the SQL renderers, so it runs in the browser (bundle budget in `tests/bundle`).
- **Named presets** (`src/preset/presets.ts`):

| Preset | Blocks |
| --- | --- |
| `minimal` | profiles |
| `saas` | organizations, invitations, teams, profiles, billing, entitlements, notifications, audit, api-keys, settings, onboarding, outbox |
| `crm` | saas + parties, pipelines, engagements, tags, comments, custom-fields, saved-views, search |
| `projects` | saas + tags, comments, attachments, state-machine, rank, reminders, time-tracking |
| `commerce` | saas + catalog, inventory, orders, promotions |
| `scheduling` | saas + calendar, bookings, reminders |
| `ai` | saas + ai-chat, ai-files, knowledge, memory, agents, ai-tasks |
| `everything` | all blocks whose scope matches, used for the demo and the tests |

  The recipes in `apps/docs/content/docs/recipes` become these presets, and `tests/validation-recipes` imports them instead of copying.
- **Config form.** `defineConfig({ preset: "saas", sql: { modules: { comments: {...} } } })`. The preset expands first and explicit config wins. `defineConfig({ preset: "a3Fx9..." })` also works, so a project keeps the preset it started from and `preset info` can show the drift.

### 2b. CLI

| Command | What it does |
| --- | --- |
| `init --preset <name\|code\|url>` | Writes the config with the preset, the migrations (managed mode), `blocks.ts` wiring and env, then runs `gen`. Without `--preset` it asks interactively: framework, then a preset or picked blocks, then conventions. |
| `apply --preset <code> [--only blocks,conventions] [--adopt]` | For an existing project. It merges the preset into the config, shows a diff and writes the migrations. With `--adopt` it introspects existing tables and proposes `mode: "adopt"` mappings (see `adopt`). |
| `add <block...>` | The single-block form of `apply`. It edits the config, resolves dependencies, writes migrations, adds the manifest to `blocks.ts`, and offers the UI items (`--ui`, which calls the registry install). The existing `add` (framework glue) moves under `add --framework` with a deprecation notice. |
| `adopt <module> --from <schema.table>` | Introspects the table and writes a proposed `tables`/`columns` mapping, with `null` for missing optional columns, plus a doctor report. |
| `preset decode <code>` / `preset info` | Shows the content of a code, or the project's current preset and its drift. |
| `blocks list` / `blocks view <name>` / `blocks search <q>` | Reads the catalog. This replaces `sql list` for block discovery; `sql list` stays. |

### 2c. Tests

- Encode/decode round-trips, plus a version-compatibility fixture per released version that must decode forever.
- `resolvePreset` against the catalog.
- Every named preset renders, migrates and passes pgTAP in a new `tests/validation-presets`. It replaces the hand copies in `validation-recipes`.
- A port in `validation-crm` actually adopts blocks through `apply --adopt`, so the adopt path is tested on a real app.

## Workstream 3: a registry that shadcn can read

### 3a. Registry source and build

- `packages/registry/` is a new private workspace that holds the copied code: `registry.json` (shadcn schema, `"name": "better-supabase"`, `"homepage": "https://bettersupabase.com"`) and `items/<name>/...`.
- **Item types:**
  - `registry:ui` and `registry:component` for the UI components;
  - `registry:block` for multi-file features (UI plus hook plus route);
  - `registry:page` for page templates, with `target` set for each framework;
  - `registry:lib` for `lib/blocks.ts` wiring;
  - `registry:file` with `target: "~/..."` for route handlers;
  - `registry:item` for a preset bundle.
- Every item has:
  - `dependencies: ["better-supabase@^<version>"]`;
  - `registryDependencies` on shadcn primitives (`button`, `card`, `dropdown-menu`, `avatar`, `table`, `dialog`, `sonner`) and on other `@better-supabase/*` items;
  - `envVars` for development values only;
  - `docs` that point to the block page;
  - `categories` matching the block category;
  - `meta: { block: "<sql module>", preset: [...] }`.
- **Framework variants.** Items are framework-neutral React by default. Next.js-specific route and page files are separate items (`members-page-next`, `members-page-tanstack`), selected by the framework field of the preset.
- `pnpm registry:build` runs `shadcn build` and writes `apps/marketing/public/r/{name}.json`. A test validates every item against the shadcn JSON schema (vendored at a pinned commit, invariant 8: add it to `SPEC_PINS`) and checks that every `meta.block` exists in the catalog.
- Config and SQL are never registry files. A registry install that needs a block prints the line `better-supabase add <block>`, or our CLI runs both steps.

### 3b. First set of components

Build these on the existing `*/react` hooks:

| Block | Components |
| --- | --- |
| organizations | `org-switcher`, `create-org-dialog`, `org-settings-form` |
| invitations / teams | `members-table`, `invite-dialog`, `team-picker` |
| notifications | `notification-bell`, `notification-list`, `notification-preferences` |
| comments / reactions | `comment-thread`, `comment-composer`, `reaction-bar` |
| billing / entitlements | `plan-picker`, `billing-portal-button`, `usage-meter`, `feature-gate` |
| api-keys | `api-keys-table`, `create-api-key-dialog` |
| audit | `audit-log-table` |
| onboarding | `onboarding-checklist` |
| tags | `tag-input` |
| search | `command-search` |
| profiles | `profile-form`, `avatar-upload` |
| page templates | `settings-layout`, `members-page`, `billing-page`, `api-keys-page` |

Each component gets a demo (`items/<name>/demo.tsx`) that runs against fixture data, so the website can preview it without a database.

### 3c. Distribution

- `components.json` users add `"@better-supabase": "https://bettersupabase.com/r/{name}.json"`, or nothing once we are listed in the shadcn registry index (submit after 3b; see `registry-index.mdx` in shadcn).
- Our `init` writes `components.json` when it is missing (it calls `shadcn init` with the user's preset when shadcn is present) and adds the namespace.
- The shadcn MCP server then sees our items. Note this in `apps/docs/content/docs/for-ai-agents.mdx`.

## Workstream 4: website (Components, Blocks, Create)

The main navigation in `apps/marketing/lib/site.ts` becomes `Docs · Components · Blocks · Create · Changelog`. Enterprise moves to the footer. All three pages read generated data (the catalog from W2a and the registry from W3a), so they never drift from the code.

### `/blocks`, modelled on ui.shadcn.com/blocks

- **Overview** (`app/blocks/page.tsx`):
  - category tabs: Foundation, Collaboration, CRM & sales, Work, Billing & commerce, Scheduling, AI, Content, Operations, Platform;
  - a search filter;
  - a card per block: title, one line of description, the number of UI items, and its requirements as badges.
- **Detail** (`app/blocks/[name]/page.tsx`, statically generated from the catalog):
  - a preview of the block's UI (the demo components, or a screenshot from the example app when the block has no UI yet);
  - tabs: **Config**, **Migrations** (file list and the first lines of SQL, rendered at build time with `better-supabase/sql`), **Server** (the wiring), **React** (hooks and components), **Events**;
  - "Requires / works with" as links;
  - supported modes (managed, adopt, custom);
  - install commands `npx better-supabase add <block>` and `npx shadcn add @better-supabase/<ui>`;
  - a link to the docs page.

### `/components`, modelled on ui.shadcn.com/docs/components

- **Overview** (`app/components/page.tsx`): a grid of all registry UI items, grouped by block.
- **Detail** (`app/components/[name]/page.tsx`):
  - a live preview (the demo running against fixture data) with a Preview/Code toggle;
  - install with the shadcn CLI or with ours;
  - the props table, generated from the TS types at build time;
  - the block it needs, linking to `/blocks/<name>`.

### `/create`, modelled on ui.shadcn.com/create

- **Layout** (`app/create/page.tsx`, a client component). A left panel with the choices, a right panel with the live result.
- **Left panel:**
  1. preset (`minimal`, `saas`, `crm`, ... or custom);
  2. framework;
  3. conventions: casing, id type, scope, tenant name, access model, API schema;
  4. blocks per category as checkboxes. Dependencies switch on automatically, marked "required by comments" so they cannot be unticked alone. Soft integrations are shown as "works with". A conflicting choice is disabled with the reason.
- **Right panel tabs:**
  - `better-supabase.config.ts` (generated);
  - migrations (file list per module);
  - `lib/blocks.ts`;
  - UI items that will be installed;
  - a dependency graph (inline SVG built from the resolver output).
- **Result.**
  - The URL stays in sync as `/create?preset=<code>`, so it can be shared.
  - A copy button for `npx better-supabase init --preset <code>`, and for existing projects `npx better-supabase apply --preset <code>`.
  - A download of the config file.
- It uses `better-supabase/preset` (`encodePreset`, `decodePreset`, `resolvePreset`) directly, so the website and the CLI share one resolver.

**Shipping before the CLI preset commands exist.** `/create` can go live as soon as W2a lands. Until `init --preset` is released, the copy button shows the generated config plus `npx better-supabase sql add <blocks>`, both of which work today. After the release it switches to the preset command. This keeps the PRODUCT.md rule never to claim what CI does not test.

### Website data and tests

- `scripts/build-catalog.ts` writes `apps/marketing/lib/catalog.generated.json`, and `pnpm registry:build` writes `public/r/*.json`. Both run as Turbo dependencies of the marketing `build`.
- Tests:
  - a Vitest test checks that every catalog block has a `/blocks` page and every registry UI item a `/components` page;
  - a Playwright smoke test in the marketing tests: tick `comments` on `/create`, expect `tenant` and `access` to switch on, and expect the URL code to decode to the same selection.
- Docs:
  - `apps/docs/content/docs/blocks/index.mdx` links to `/blocks` and keeps its "Requires / Works with" table (still checked by `docs-drift.test.ts`);
  - a new docs section `presets/` covers the model, the named presets, `init`/`apply`/`preset` and versioning;
  - a new docs section `registry/` covers shadcn compatibility, the namespace and the hybrid rule.

## Order and conflicts

`feat/pipelines-foundation` touches `src/sql/registry.ts`, `src/sql/modules/*`, `src/core`, `src/events` and `apps/docs/content/docs/blocks`. It does not touch `apps/marketing` or `src/cli`.

| Phase | Content | Can start | Depends on |
| --- | --- | --- | --- |
| 0 | W1a fixes; ADR 0029 (manifests and block contract); ADR 0030 (presets and registry, including the hybrid rule) | now | none |
| 1 | W4 skeleton: navigation and the `/blocks` overview and detail pages, built on a first catalog script that reads `SQL_MODULES` only | now | none (marketing only) |
| 2 | W1b manifests and the generic `createBlocks`; W1d conformance test as a warning | after the pipelines merge | 0 |
| 3 | W2a preset model and catalog; W4 `/create` (with the `sql add` fallback) | after 2 | 2 |
| 4 | W3a/W3b registry and first components; W4 `/components`; listing in the shadcn index | parallel to 3 | 1 |
| 5 | W2b CLI: `init --preset`, `apply`, `add`, `preset`, `blocks`; `/create` switches to the preset command | after 3 | 3, 4 |
| 6 | W1c one config (generated block config, typed options) | after 2 | 2 |
| 7 | W1e scope and naming conventions; the adopt command and a validation port that really adopts | last | 2, 5 |

Run `pnpm verify` before every push, one changeset per user-visible change, and `pnpm size` for the new `better-supabase/preset` entry. Update the exports map, `tsdown.config.ts`, the size baseline, the export snapshot and the docs per invariant 9.

## Open decisions

1. **Preset code: base62 BigInt or readable?** The plan uses a base62 code, which is short and matches shadcn. Named presets cover the readable case.
2. **Registry location.** The plan uses one registry at `bettersupabase.com/r`. A per-framework `{style}` path (`/r/{style}/{name}.json`) is only worth it once pages have framework variants. Until then, use separate item names.
3. **Default naming.** Is "organization" the default tenant name? The plan keeps it, because changing it breaks every installed app.
4. **Whether `everything` is a public preset.** It is useful for demos and tests, but it installs about 90 modules.
