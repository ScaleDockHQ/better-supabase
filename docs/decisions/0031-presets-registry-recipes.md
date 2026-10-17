# 0031: Install blocks through presets, ship glue through a shadcn registry, and show UI as recipes

- Status: accepted
- Date: 2026-10-15

## Context

Starting an app on better-supabase means choosing blocks one by one: there
are no presets, `init` never asks about blocks, the docs recipes are
copy-paste pages, and adopting is config-heavy (the centrakit config is 397
lines for 21 modules). shadcn solved the same onboarding problem for UI:
`/create` builds a versioned preset code, `init --preset` and `apply`
install it, and a registry of items (`files[].target`, `dependencies`,
`registryDependencies`, `envVars`) copies code into the app by name. Its
components are copied code the app owns.

Visible components would make us maintain markup, styling and
accessibility for every framework and both platforms, while apps already
build their UI from shadcn components.

## Decision

- **Presets.** `better-supabase/preset` (WinterTC-safe) encodes a block
  selection and its conventions as a version character plus base62 over a
  BigInt. `PRESET_BLOCKS` and `PRESET_FIELDS` are append-only, a removed
  block keeps its slot as a tombstone, and an older code decodes with
  defaults reported as `derived`. `resolvePreset` returns the full block
  set with `requires`, the soft integrations, conflicts and a reason per
  block, from a generated catalog that never imports the SQL renderers, so
  the website and the CLI share one resolver. Named presets (`minimal`,
  `saas`, `crm`, `projects`, `commerce`, `scheduling`, `ai`) replace the
  docs app recipes. `defineConfig({ preset, blocks })` expands the preset
  first and explicit config wins. The CLI gains `init --preset`,
  `apply --preset [--only] [--adopt]`, `add <block...>`, `adopt`,
  `preset decode|info` and `blocks list|view|search`.
- **A registry for glue only.** `packages/registry` builds shadcn registry
  items into `https://bettersupabase.com/r/{name}.json` under the
  `@better-supabase` namespace: `registry:lib` for the wiring and server
  actions, `registry:hook` for app-level hooks that compose our bindings,
  `registry:file` for route handlers and Expo config, and `registry:item`
  for a preset's glue bundle. It never contains `registry:ui`,
  `registry:component`, `registry:block` with markup or `registry:page`,
  and no config or SQL: an item that needs a block prints
  `better-supabase add <block>`. Framework and platform variants are
  separate items. A test validates every item against the shadcn JSON
  schema, vendored at a pinned commit in `SPEC_PINS` (invariant 8).
- **UI recipes instead of components.** Each UI pattern (notification
  bell, comment thread, org switcher, plan picker, ...) is a recipe page:
  the shadcn components to add, the glue to install, and the web and
  native code side by side with the same hook call (ADR 0030). The
  snippets are extracted by region markers from the example apps, so they
  are typechecked and tested. Each recipe is also a consumer skill section
  and part of `/llms.txt`.
- **Website.** The main navigation becomes Docs, Blocks, Recipes, Create
  and Changelog. `/blocks`, `/recipes` and `/create` read generated data
  (the catalog and the recipe index), so they can't drift from the code.

What ships in the package stays ours to upgrade (SQL, block clients,
controllers and bindings); wiring the app is expected to edit is copied
from the registry; anything visible is a recipe the app owns.

## Alternatives considered

- **Ship styled components.** Every framework, platform and design system
  would need its own set, and apps would fight our markup. Recipes over
  the app's own shadcn components avoid both.
- **A registry that also installs config and SQL.** A registry install
  can't run migrations or resolve block dependencies; mixing them would
  give two install paths with different results. Our CLI owns config and
  SQL, and the registry owns copied code.
- **Presets as JSON files instead of codes.** A short code fits a URL and a
  command line, and named presets cover the readable case.
- **Our own registry format.** The shadcn CLI and its MCP server already
  read the format, so apps and agents get our glue with tools they have.

## Consequences

A new SaaS starts from one command or a `/create` link, and the CLI and
the website resolve the same selection. Adding a preset field or block is
append-only forever, and every released preset version needs a fixture
that must keep decoding. The registry build and the recipe extraction
become dependencies of the marketing build. Revisit the glue-only rule if
a shadcn-style React Native library with a working registry makes native
recipes too long to copy. The decisions this left open settled on
2026-10-16: the default tenant name stays "organization" (renamed with
`sql.naming.tenant`), and the `everything` preset is public.
