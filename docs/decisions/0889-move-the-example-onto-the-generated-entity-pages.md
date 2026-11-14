# 0889: Move the example onto the generated entity pages

- Status: accepted
- Date: 2026-11-14

## Context

Lanes M1 to M3 (ADR 0859, 0869, 0879) generate the list query, its route and
indexes, the scale test, columns, the detail frame, forms, seed rows, a nav item
and a route manifest from `defineEntityPage`. The Next.js example declared one
page (periods) and read none of the output: it kept five list helpers, a nav
file, a coverage map and its seed rows by hand (EX-1294, EX-1264, EX-1267,
EX-1268). Lane M4 moves it over.

The generator only resolves a block entity that declares a list surface
(`entityLists` in the preset catalog), and its route calls the block's `page` and
`facets` without a per-call tenant. That rules out three pages the lane named:
`customers` is an app table, `inbox` conversations declare no list surface, and
`incidents` takes `organizationId` per call (ADR 0939), which the generated route
does not pass.

## Decision

The example declares these pages in `gen.entityPages`: `periods.period`,
`risks.risk`, `commissions.commission`, `referrals.referral` and
`dispatch.work_order` (named `work-orders`).

- Nav: the `risks`, `commissions`, `referrals`, `periods` and `dispatch` items
  in `nav-items.ts` read `href` and `area` from `<name>Nav`.
- Risks: the register reads its URL state through the generated `risksList`
  (`parse`, `toSearchParams` and the declared sorts), and offers the block's three
  sorts in the sort select (EX-1001). Its rows need the band from the matrices, so
  its own `/api/risks/register` route stays beside the generated `/api/risks/list`.
- Seed: `dispatch.work_order` is the one page whose block exports an input schema
  that asks for a free text, so it sets `seed`. `pnpm db:seed:pages`
  (`scripts/seed-entity-pages.ts`) creates the rows through the block's SQL create
  function and skips titles the organization already holds. `risks.risk` also has
  an input schema, but its `category` takes one of the block's configured values,
  which a generated demo value cannot know.
- Coverage: `check:example-coverage` reads the generated `entityRoutes` and fails
  when a declared page's route is missing under its block in
  `coverage/block-coverage.ts` or has no `page.tsx`. Node cannot import the
  manifest (its imports carry no extension), so `scripts/entity-routes.ts` reads
  the entries as text.
- Translations: `check:empty-translations` (in `pnpm verify`) fails on an empty
  `msgstr` in any locale for a message whose `msgctxt` is a manifest message key
  or starts with the page name as namespace (`risks.<hash>`). The extractor keys
  messages by hash, so a manifest key such as `risks.title` matches only a literal
  key; the namespace rule is what catches an extracted message.
- `oxlint.config.ts` ignores `lib/supabase/pages/**` like the other `gen` output
  (the generated forms carry numbers over four digits with no separator).

## Alternatives considered

- Make the generated route pass `organizationId` for blocks that need it. The
  catalog does not say which blocks do, so it needs a manifest flag and a new
  output version; left for a library change.
- Generate the coverage map. The map is per block and covers blocks with no page,
  so the page descriptor cannot own it; checking it against the manifest keeps one
  source for the page routes.
- Fail on any empty `msgstr` in the example. `main` carries empty Dutch
  strings in namespaces no page declares, so that check would fail before it
  protects a page.

## Consequences

Five pages are declared and three of them (risks, nav, coverage) are read by the
app. The five list helpers stay: their pages are array lists, block lists with
their own UI or app tables, and each needs its page declared, a block list
surface or a UI move first. The rows that name them move to lane M5.
