# 003: Composable blocks, presets, a shadcn-compatible registry and Create

Status: phases 0 to 4 done, and phase 5 apart from `adopt`: `init --preset`, `apply --preset [--only]`, `add <block...>` (framework glue under `add --framework`), `preset decode|info` and `blocks list|view|search` shipped, and `/create` shows the `init` and `apply` commands. Phase 4 ended with the comments and organizations controllers, so the Expo example shares the notifications, organizations and comments hooks with the Next.js example. Next: `adopt` and `apply --adopt` with the validation-crm port. Written 2026-10-14 against `main` at `3d9920b`, with `feat/pipelines-foundation` (parties, pipelines, engagements) still open. That branch merges first; see "Order and conflicts". Revised 2026-10-15:

- better-supabase ships no visible UI components. It ships helpers and glue, plus recipes that build the UI from shadcn components.
- The client helpers are shared between React and React Native.
- `sql.modules` is renamed to `blocks`.
- The project is greenfield with no external users, so every change here is made in place: no deprecated aliases, no compatibility shims, no codemods and no migration guides (see "Breaking changes").
- The config key is a top-level `blocks` (decided 2026-10-15).

The goal of better-supabase is mix and match: run everything with the default config, change behaviour by changing the config, and build a new SaaS by picking blocks, tweaking them and extending later. This plan has five workstreams:

1. **Decouple the blocks**, so each one stands alone and the core stops knowing about individual blocks.
2. **Presets**: a named or encoded selection of blocks and conventions that `init` and `apply` install in one step.
3. **A shadcn-compatible registry for glue only**: hooks, wiring, routes and server actions. No UI components.
4. **Cross-platform client helpers**: one headless controller per block, with thin bindings for React (web and native) and the other frameworks.
5. **The website**: Blocks, Recipes and Create in the main navigation, modelled on ui.shadcn.com.

Each workstream lists its phases, the files it touches and what "done" means. An executor with no context from the analysis session can run it.

## Background: the analysis behind this plan

Verified against the code on 2026-10-14.

- **Block-to-block imports are not the problem.** There are 37 edges and no cycles, and no block depends on more than 2 others. `jobs` is the de facto shared kernel, with 15 blocks importing it.
- **Central registries know every block.**
  - `src/blocks/create-blocks.ts` hard-codes sibling wiring: the options `aiTaskNotification`, `reminderNotification` and `metricEvents`; the `files`/`notify`/`notifyDelivery` slots; the `aiFiles` special case; `build("notifications")` with a duck-typed `send`; and `sinks: {search, metrics}`.
  - `src/core/block-events.ts:683-914` is one closed `BlockEventMap` with 239 events, with payload types in core. Every new block edits it.
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
  - Module `options` is `Record<string, unknown>` (`src/config/blocks.ts:43`).
  - The config key says "modules" while everything else, the docs, the subpaths and ADR 0012, says "blocks".
- **Extension points differ per block.**
  - `fields`: 2 blocks.
  - `extraColumns`: 3 blocks.
  - `hooks` as an option: 19 of 67 blocks.
  - `commerce`, `entitlements`, `outbox` and `webhooks` don't use `blockCall`.
  - Concept names (`create_organization`) cannot be renamed.
- **Client helpers are React-only.**
  - Block hooks such as `blocks/notifications/react/index.ts` keep their state in `useState`/`useEffect`, so Vue, Svelte and Solid get nothing, and React Native gets them only by accident.
  - `blocks/search/react/index.ts:144` uses `window.addEventListener`, which breaks on native.
  - 14 blocks have a `/react` entry.
- **Onboarding.**
  - There are no presets, and recipes are copy-paste docs.
  - `init` never asks about blocks.
  - `sql add` prints a snippet in array form instead of editing the config.
  - There is no global `api` default.
  - Adopting is null-heavy: the centrakit config is 397 lines for 21 modules.
  - The production ports adopt no blocks.

## What we take from shadcn

Read from the shadcn-ui/ui source: `packages/shadcn/src/commands/{init,apply,preset,eject}.ts`, `packages/registry/src/preset/preset.ts`, `apps/v4/content/docs/registry/*`, and the changelog entries `2025-12-shadcn-create` and `2026-02-blocks`.

| shadcn concept                                                                                                             | What it is there                                                                                                    | Our counterpart                                                                                                                                                 |
| -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/create`                                                                                                                  | Pick base library, style, colours, icons, fonts and radius; live preview; result is a preset.                       | `/create`: pick a framework, conventions and blocks; live preview of the generated config, migrations and wiring.                                               |
| Preset code                                                                                                                | Versioned base62 bit field (`PRESET_FIELDS`, append-only, version prefix char). The URL is `/create?preset=<code>`. | The same scheme with an append-only block list, encoded as a BigInt (more than 53 bits).                                                                        |
| `init --preset`, `apply --preset --only`                                                                                   | New project from a preset; apply a preset to an existing project, in part if wanted.                                | `better-supabase init --preset`, and `apply --preset --only blocks,conventions` as the adopt path.                                                              |
| `preset decode` / `info`                                                                                                   | Show what a code contains.                                                                                          | The same commands.                                                                                                                                              |
| Styles rewrite component code                                                                                              | Code adapts to the chosen setup.                                                                                    | **Conventions** (casing, id type, tenant name, scope) rewrite table, function and method names.                                                                 |
| Registry items with `files[].target` (`~/`, `@lib/`, `@hooks/`), `dependencies`, `registryDependencies`, `envVars`, `docs` | Universal items, installed by name.                                                                                 | Our glue ships as `registry:lib`, `registry:hook` and `registry:file` items. There are no `registry:ui` items.                                                  |
| Namespaces (`@acme/item`) and the registry index                                                                           | Decentralized registries.                                                                                           | `@better-supabase` in the index; `https://bettersupabase.com/r/{name}.json`.                                                                                    |
| `/blocks`                                                                                                                  | Pages with preview and code, installed by name.                                                                     | `/blocks`: one page per block with config, migrations, wiring and install commands.                                                                             |
| Components as copied code                                                                                                  | The UI lives in your project.                                                                                       | **Recipes.** The app builds its UI from its own shadcn components plus our headless helpers, following a recipe. We never ship or maintain a visible component. |

### What ships, what is copied, and what is a recipe

| Layer                                                                                                              | Delivered as                                                                                                                   | Who maintains it                   |
| ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------- |
| SQL modules, block clients, codecs, events                                                                         | npm package `better-supabase`, configured through `blocks`                                                                     | us, upgraded through `sql upgrade` |
| Headless client controllers and their React (web and native), Vue, Svelte and Solid bindings                       | npm package subpaths (W4)                                                                                                      | us                                 |
| Glue: `lib/blocks.ts` wiring, route handlers (outbox relay, Stripe webhook, cron), server actions, native adapters | shadcn registry items, copied into the app                                                                                     | the app, after install             |
| UI                                                                                                                 | recipes: docs pages, plus agent skills, that compose shadcn components (web) or a shadcn-style native library with our helpers | the app                            |

The rule is that anything with security or upgrade consequences stays in the package, wiring the app is expected to edit is copied, and anything visible is a recipe.

## Workstream 1: decouple the blocks

This is the prerequisite for presets. A preset only works if blocks combine freely.

### 1a. Fixes with no conflicts (can start now)

- `entitlements-source.ts`: declare `billing` and `organizations` in `integrates` and resolve the table, column and key through `ctx.of(...)`. Add a test with renamed billing columns.
- Replace the 7 hard-coded `"better_supabase"` literals in blocks (`catalog.ts:571`, `time-tracking/metrics.ts:32`, `drive.ts:684`, `orders/metrics.ts:28`, `outbox.ts:338`, `webhooks/secrets.ts:28`, `webhooks/incoming.ts:69`) with the block's `schema` option.
- Route `better_supabase.member_organization_ids()` and `has_organization_role` in `api-keys`, `flags`, `entitlements-checks` and `organizations` through `ctx.of("tenant").fn(...)`.
- A global `sql.api` (and `sql.schema`) default that modules inherit.
- `sql add` edits the config file, using an AST edit that keeps the object form. It falls back to the printed snippet when the config is not a literal object.

Done when `pnpm verify` is green, the golden SQL is unchanged except where it was renamed on purpose, and there is one changeset per fix.

### 1b. Rename `sql.modules` to `blocks` (with the manifests, after the pipelines merge)

The config key becomes a top-level `blocks`, not `sql.blocks`. After W1c a block's config covers both its SQL options and the options its client needs, so it no longer belongs under `sql`. `sql` keeps the SQL-wide settings: `schema`, `api`, `scope`, `naming` and the migration paths.

```ts
export default defineConfig({
  preset: "saas",
  sql: { api: "api" },
  blocks: {
    comments: { mode: "managed", options: { notify: true } },
    tags: {},
  },
});
```

The foundation modules (`tenant`, `access`, `updated-at`, `ensure-rls`, ...) become blocks in a `foundation` category, so there is one key and one word.

Doing the rename:

1. `sql.modules` is removed. An unknown top-level or `sql` key is already a config validation error.
2. The docs (about 240 references), CLI messages, code comments such as `sql.modules.notifications.options.topic`, the JSON schema (`schemas/config-v1.json`) and the validation projects move to `blocks` in the same release.
3. `SqlModule` stays the internal name of the SQL half of a block.

### 1c. `defineBlock` manifests

ADR 0029, "One manifest per block". Each block exports one manifest, for example `src/blocks/comments/manifest.ts`:

```ts
export const comments = defineBlock({
  name: "comments",
  sql: "comments", // the SqlModule key(s)
  options: commentsOptionsSchema, // Standard Schema, typed `blocks.comments.options`
  events: commentsEvents, // this block's own event map
  consumes: { notifier: optional<Notifier>() },
  provides: {},
  create: (ctx) => createComments(ctx),
  client: "comments", // headless controller (W4), when the block has one
  category: "collaboration",
  recipes: ["comment-thread"], // UI recipe slugs (W5)
});
```

- `createBlocks` wires on `provides` and `consumes`, never on names. `aiTaskNotification` and `reminderNotification` move to the ai-tasks and reminders manifests. `notifications` provides `notifier`; `search` and `metrics` provide sinks.
- **Events per block.** `BlockEventMap` becomes the inferred union of the manifests passed to `defineBlocks(...)`, which keeps invariant 2 (no `declare module`). App events become possible through `defineEvents({...})`.
- **No hidden instances.** `drive` consumes `attachments` and `workflow-builder` consumes `workflows`.

### 1d. One config for SQL and TS

- `gen` emits `blocks.generated.ts` with the resolved per-block config. `defineBlocks(generated, {...})` reads it, so settings such as `requireScan` live in one place.
- `blocks.<name>.options` is typed from each manifest's options schema, and `schemas/config-v1.json` is generated from it. Check `pnpm typecheck:perf` after this change.

### 1e. One contract for every block, enforced by a conformance test

`tests/blocks/conformance.test.ts` iterates the manifests and checks:

- the creator is `create<Name>(options)` and takes `BlockOptions`;
- it accepts `hooks`;
- every managed table has `fields` and `extraColumns`;
- every call goes through `blockCall`;
- it has its own event map;
- it creates no sibling clients;
- its client controller imports no DOM or React Native globals (W4).

Start with an allowlist of current exceptions and shrink it to zero. Also normalize the outliers: `createBuilder` becomes `createWorkflowBuilder` and `createPushDevices` becomes `createPush`, with no aliases.

### 1f. Scope and naming as conventions

This step goes deepest and comes last.

- **Scope.** `scope: "tenant" | "user" | "none"` per block, with a default in `sql.scope`. `access` and `tenant` sit behind a port (`ctx.scope.can(...)`, `ctx.scope.ids(...)`), so all literal `better_supabase.can(` sites go through `ctx`. The preset resolver refuses a combination that cannot work.
- **Naming.** `sql.naming.tenant: "organization" | "workspace" | "team" | string` renames the tenant concept in tables, functions, columns and, through `gen`, TS method names. A `functions` rename map sits next to `tables` and `columns`. This is our counterpart of shadcn's styles.

## Workstream 2: presets

### 2a. The preset model (`better-supabase/preset`, WinterTC-safe)

- **Encoding.**
  - `PRESET_BLOCKS` is an append-only list of block names. A removed block keeps its slot as a tombstone.
  - `PRESET_FIELDS` is an append-only list of convention fields, each with `{ key, values, bits }`:
    - `framework`: `next`, `vite`, `tanstack-start`, `expo`, `sveltekit`, `nuxt`, `hono`, `astro`, `react-router`, ...
    - `platforms`: `web`, `native` or both
    - `casing`
    - `idType`
    - `scope`
    - `tenantName`
    - `access`
    - `api`
    - `integrations`
  - `encodePreset` / `decodePreset` produce a version char plus base62 of a BigInt. Decoding an older version fills new fields with defaults and reports them as `derived`.
- **Resolving.** `resolvePreset(preset)` returns:
  - the full block set, including `requires`;
  - the active soft integrations;
  - conflicts;
  - an explanation per block ("added because comments requires tenant").

  It reads a generated catalog (`src/preset/catalog.generated.ts`, from `SQL_MODULES` and the manifests by `scripts/build-catalog.ts`) and never imports the SQL renderers, so it runs in the browser.

- **Named presets** (`src/preset/presets.ts`):

  | Preset       | Blocks                                                                                                                           |
  | ------------ | -------------------------------------------------------------------------------------------------------------------------------- |
  | `minimal`    | profiles                                                                                                                         |
  | `saas`       | organizations, invitations, teams, profiles, billing, entitlements, notifications, audit, api-keys, settings, onboarding, outbox |
  | `crm`        | `saas` + parties, pipelines, engagements, tags, comments, custom-fields, saved-views, search                                     |
  | `projects`   | `saas` + tags, comments, attachments, state-machine, rank, reminders, time-tracking                                              |
  | `commerce`   | `saas` + catalog, inventory, orders, promotions                                                                                  |
  | `scheduling` | `saas` + calendar, bookings, reminders                                                                                           |
  | `ai`         | `saas` + ai-chat, ai-files, knowledge, memory, agents, ai-tasks                                                                  |
  | `everything` | all blocks, for demos and tests                                                                                                  |

  The app recipes in `apps/docs/content/docs/recipes` (CRM, commerce, drive, scheduling, project management) become these presets. `tests/validation-recipes` imports them instead of copying.

- **Config.** `defineConfig({ preset: "saas", blocks: { ... } })` expands the preset first, and explicit config wins. A code works there too, so `preset info` can show the drift from the starting point.

### 2b. CLI

| Command                                                       | What it does                                                                                                                                                                                   |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `init --preset <name\|code\|url>`                             | Writes the config, migrations, the glue items from the registry for the chosen framework and platforms, and env, then runs `gen`. Without `--preset` it asks interactively.                    |
| `apply --preset <code> [--only blocks,conventions] [--adopt]` | For an existing project: merges the preset, shows a diff and writes the migrations. With `--adopt` it introspects existing tables and proposes adopt mappings.                                 |
| `add <block...>`                                              | Edits `blocks`, resolves dependencies, writes migrations, adds the manifest to the wiring, and installs the block's glue items. The current `add` (framework glue) moves to `add --framework`. |
| `adopt <block> --from <schema.table>`                         | Writes a proposed `tables`/`columns` mapping plus a doctor report.                                                                                                                             |
| `preset decode <code>` / `preset info`                        | Shows the content of a code, or the project's current preset and its drift.                                                                                                                    |
| `blocks list` / `view <name>` / `search <q>`                  | Reads the catalog.                                                                                                                                                                             |

### 2c. Tests

- Encode/decode round-trips, plus a fixture per released preset version that must decode forever.
- `resolvePreset` against the catalog.
- Every named preset renders, migrates and passes pgTAP in a new `tests/validation-presets`.
- `validation-crm` adopts blocks through `apply --adopt`, so the adopt path is tested on a real app.

## Workstream 3: a registry that shadcn can read, for glue only

### 3a. Registry source and build

- `packages/registry/` is a private workspace with `registry.json` (shadcn schema, `"name": "better-supabase"`) and `items/<name>/...`.
- **Item types:**
  - `registry:lib` for the wiring (`lib/blocks.ts`) and server actions;
  - `registry:hook` for app-level hooks that compose our bindings (for example a `useCurrentOrganization` that the app is expected to edit);
  - `registry:file` with `target: "~/..."` for route handlers and Expo config;
  - `registry:item` for a preset's glue bundle.
- **What items never contain.** No `registry:ui`, `registry:component`, `registry:block` with markup, or `registry:page` items: the UI is a recipe. No config or SQL files either: a registry install that needs a block prints `better-supabase add <block>`, or our CLI runs both steps.
- **Every item has:**
  - `dependencies: ["better-supabase@^<version>"]`;
  - `registryDependencies` on other `@better-supabase/*` items only;
  - `envVars` for development values only;
  - `docs` linking the block page;
  - `meta: { block, platforms, frameworks }`.
- **Framework and platform variants.** These are separate items (`outbox-relay-next`, `outbox-relay-hono`, `push-native`), chosen by the preset fields.
- **Build.** `pnpm registry:build` runs `shadcn build` into `apps/marketing/public/r/{name}.json`. A test validates every item against the shadcn JSON schema (vendored at a pinned commit and added to `SPEC_PINS`, invariant 8) and checks every `meta.block` against the catalog.

### 3b. Distribution

- Users add `"@better-supabase": "https://bettersupabase.com/r/{name}.json"` to `components.json`, or need nothing once we are listed in the shadcn registry index.
- `init` adds the namespace when `components.json` exists.
- The shadcn MCP server then sees our glue items. Note this in `apps/docs/content/docs/for-ai-agents.mdx`.

## Workstream 4: cross-platform client helpers

The web and React Native apps should share everything except the markup. ADR 0030, "Headless block controllers".

### 4a. One controller per block

`src/blocks/<name>/client.ts` is a framework-agnostic controller in plain TS:

```ts
export function createNotificationsController(
  options,
): NotificationsController {
  // state, actions (markRead, archive), realtime through the topic port,
  // optimistic updates, pagination
  return { getSnapshot, subscribe, actions, dispose };
}
```

- It follows the external-store contract (`subscribe` / `getSnapshot`), so every binding is a thin wrapper.
- It imports no React, no DOM and no React Native. Platform needs go through small injected ports: realtime topic (already `watchTopic` in `src/blocks/react-topic.ts`, moved out of React), storage, keyboard shortcuts, file pick and upload, push token, deep links and clipboard.
- Default ports live in `better-supabase/client` (web) and `better-supabase/client/native` (Expo), which already exist for auth.

### 4b. Bindings

| Binding                | Entry                                              | Notes                                                                                                                            |
| ---------------------- | -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| React (web and native) | `better-supabase/blocks/<name>/react`              | `useSyncExternalStore` over the controller. The same hook runs in React DOM and React Native, and the `react-server` stub stays. |
| React Native extras    | `better-supabase/blocks/<name>/react/native`       | Only where a port needs a native default, such as push or file pick. Most blocks need none.                                      |
| Vue, Svelte, Solid     | `better-supabase/blocks/<name>/{vue,svelte,solid}` | Generated wrappers over the controller (`shallowRef`, a readable store, `from`), following `src/vue`, `src/svelte`, `src/solid`. |

### 4c. Migration of the current hooks

- Move the state logic of the 14 existing `/react` entries into controllers: ai-chat, announcements, bookings, calendar, forms, inbox, notifications, onboarding, reactions, saved-views, search, undo, workflows and workflow-builder.
- Hook signatures change wherever the controller allows a cleaner API. The examples and recipes change in the same commit.
- `search` moves its `window` keydown listener behind the keyboard port.
- Then add controllers for the blocks that have none but need client state: comments, tags, organizations (switching), invitations, api-keys, approvals and settings.

### 4d. Tests

- Each controller is unit-tested once, with fake ports.
- Each binding gets one shared conformance suite (`src/testing/kits/controller-binding.ts`) run against React, Vue, Svelte and Solid.
- A static check, like the WinterTC check, fails when a controller or a `/react` entry references `window`, `document` or `react-native`.
- The Expo example (`apps/examples/expo-powersync`) uses the same hooks as the Next.js example for at least notifications, organizations and comments.

## Workstream 5: website (Blocks, Recipes and Create)

The main navigation in `apps/marketing/lib/site.ts` becomes `Docs · Blocks · Recipes · Create · Changelog`. Enterprise moves to the footer. All pages read generated data (the catalog from W2a and the recipe index), so they never drift from the code.

### `/blocks`, modelled on ui.shadcn.com/blocks

- **Overview**: category tabs (Foundation, Collaboration, CRM & sales, Work, Billing & commerce, Scheduling, AI, Content, Operations, Platform), a search filter, and a card per block with title, description, platforms, recipe count and requirement badges.
- **Detail** (`app/blocks/[name]/page.tsx`, statically generated): tabs for Config, Migrations (rendered at build time), Server, Client (controller and bindings per framework), Events and Recipes; "Requires / works with" links; supported modes; and the commands `npx better-supabase add <block>` and `npx shadcn add @better-supabase/<glue>`.

### `/recipes`: UI recipes instead of components

The page lists one recipe per UI pattern, grouped by block. Examples: notification bell, notification list, comment thread, org switcher, members table, invite dialog, plan picker, usage meter, feature gate, API keys table, audit log table, onboarding checklist, tag input, command search and settings layout.

Each recipe page shows:

1. **What you build**, with a screenshot of the example app.
2. **shadcn components to add**: `npx shadcn add card dropdown-menu badge`, and for native the equivalent from a shadcn-style React Native library. Check its registry support before naming it in the docs.
3. **Glue to install**: `npx shadcn add @better-supabase/<glue>`, if any.
4. **The code**, for Web (React and shadcn) and Native (React Native) side by side, with the same hook call in both.
5. **Variations**, such as the same recipe with the Vue or Svelte binding.

The snippets are not written by hand. They are extracted by region markers from the example apps (`apps/examples/nextjs`, `apps/examples/expo-powersync`), so every snippet is typechecked and covered by the examples' tests.

Each recipe is also published as a consumer skill section and in `/llms.txt`, so agents build the UI from it. The existing docs app recipes become presets and appear on `/create`, which frees the word "recipes" for UI.

### `/create`, modelled on ui.shadcn.com/create

- **Left panel**: preset; framework and platforms (web, native or both); conventions (casing, id type, scope, tenant name, access model, API schema); blocks per category. Dependencies switch on automatically and are marked "required by comments"; soft integrations show as "works with"; conflicts are disabled with the reason.
- **Right panel tabs**: `better-supabase.config.ts`; migrations; `lib/blocks.ts`; the glue items and the recipes that apply; a dependency graph (inline SVG from the resolver output).
- **Result**:
  - the URL stays in sync as `/create?preset=<code>`;
  - a copy button for `npx better-supabase init --preset <code>`, or `apply --preset <code>` for an existing project;
  - a download of the config file.
- It uses `better-supabase/preset` directly, so the website and the CLI share one resolver.
- **Before the CLI commands ship**, the copy button shows the generated config plus `npx better-supabase sql add <blocks>`, both of which work today (PRODUCT.md: never claim what CI does not test).

### Website data and tests

- `scripts/build-catalog.ts` and the recipe index run as Turbo dependencies of the marketing `build`.
- A Vitest test checks that every catalog block has a `/blocks` page and every recipe slug in a manifest has a recipe page with extracted snippets.
- A Playwright smoke test ticks `comments` on `/create`, expects `tenant` and `access` to switch on, and expects the URL code to decode to the same selection.
- New docs sections `presets/` and `registry/`. `blocks/index.mdx` links to `/blocks` and keeps its drift-checked table.

## Order and conflicts

`feat/pipelines-foundation` touches `src/sql/registry.ts`, `src/sql/modules/*`, `src/core`, `src/events` and `apps/docs/content/docs/blocks`. It does not touch `apps/marketing`, `src/cli` or the `/react` entries.

| Phase | Content                                                                                                                                                | Can start                 | Depends on |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------- | ---------- |
| 0     | W1a fixes; ADR 0029 (manifests, block contract, `blocks` config key); ADR 0030 (headless controllers); ADR 0031 (presets, glue-only registry, recipes) | now                       | none       |
| 1     | W5 skeleton: navigation and `/blocks` from a first catalog script over `SQL_MODULES`; W4a/4c controllers for the existing `/react` entries             | now                       | none       |
| 2     | W1b `blocks` config key; W1c manifests and the generic `createBlocks`; W1e conformance as a warning                                                    | after the pipelines merge | 0          |
| 3     | W2a preset model and catalog; W5 `/create` (with the `sql add` fallback)                                                                               | after 2                   | 2          |
| 4     | W3 glue registry; W5 `/recipes` with extracted snippets; W4b Vue, Svelte and Solid bindings; the Expo example                                          | parallel to 3             | 1          |
| 5     | W2b CLI (`init --preset`, `apply`, `add`, `adopt`, `preset`, `blocks`); `/create` switches to the preset command                                       | after 3                   | 3, 4       |
| 6     | W1d one config (generated block config, typed options)                                                                                                 | after 2                   | 2          |
| 7     | W1f scope and naming conventions; a validation port that really adopts                                                                                 | last                      | 2, 5       |

Run `pnpm verify` before every push, with one changeset per user-visible change. Run `pnpm size` for every new entry, and update the exports map, `tsdown.config.ts`, the size baseline, the export snapshot and the docs per invariant 9.

## Breaking changes

better-supabase is greenfield: there are no external users to migrate. Every phase changes the API in place and updates the repository's own callers (examples, validation projects, docs, skills, tests) in the same PR.

- **Removed outright, with no replacement shim:**
  - `sql.modules`;
  - the sibling-specific `createBlocks` options (`aiTaskNotification`, `reminderNotification`, `metricEvents`, `metricTime`);
  - the closed `BlockEventMap` export;
  - the old creator names (`createBuilder`, `createPushDevices`);
  - the framework-glue form of `add`.
- **Not built:** codemods, deprecation notices, doctor findings for old keys, or a migration guide for these changes.
- **SQL.**
  - Module SQL can change freely.
  - The fixture's pg-delta baseline (ADR 0027) is regenerated, not migrated.
  - `sql upgrade` steps are only needed once there are released installs to upgrade.
- **Versions.** Changesets are `minor` bumps for `better-supabase`, which is pre-1.0, and say what changed.

## Open decisions

1. **Preset code format.** The plan uses base62 over a BigInt, which is short and matches shadcn. Named presets cover the readable case.
2. **Default tenant name.** "organization" is the proposed default because it is the most common term; nothing ties us to it.
3. **The native UI library the recipes name.** This needs a check of which shadcn-style React Native library has a working registry before the recipes reference it. Until then, the native recipes use plain React Native primitives.
4. **Whether `everything` is a public preset.** It installs about 90 modules.
