# 1086: Declare the block overview pages for scale files and coverage

- Status: accepted
- Date: 2026-11-16

## Context

`gen` writes the indexes, the `scale_list_<entity>.test.sql` plan check and the `pageCoverage`
entry only for a page declared in `gen.entityPages` (ADRs 0859 and 0895). The example's
overviews on `BlockOverview` read a block's `page` and `facets` on the server (ADR 1077) but were
never declared, so they had no scale file and the coverage map kept their routes by hand (EX-607,
EX-1265, EX-1267).

## Decision

- `apps/examples/nextjs/overview-pages.ts` declares one `defineEntityPage` per overview that reads
  a block list: contacts, companies, forecasts, quotes, sequences, commission plans and
  statements, referral codes, RFQs, tills and till sessions, the four warehouse lists, lims
  samples and methods, and the maintenance plans, meters and calibrations. The config spreads the
  array into `gen.entityPages.pages`, which keeps `better-supabase.config.ts` under the line cap.
- The pages still render their own `BlockOverview`. A declaration here adds the generated list
  query, `/api/<name>/list`, the indexes, the scale file and the coverage entry; it declares no
  `area`, so no nav item or page is generated and the menu is unchanged.
- No page declares `seed`: the demo rows already come from `example.sql` and the finance demo,
  and the blocks' state machines reject generated rows for most of these entities. The scale
  files read whatever the stack holds, so `pnpm db:seed:scale --tier l` measures the volume.
- `block-coverage.ts` reads these routes through `declared(block, ...extras)` for contacts,
  forecasts, quotes, sequences, maintenance, lims, warehouse, RFQs and tills.
- A page named `rfqs` or `tills` shares its name with the screen's message namespace, so
  `check:empty-translations` now counts that screen's messages. It found 17 empty Dutch messages,
  which are translated.
- Three of these pages (lims samples, referral codes, RFQs) declare a facet that a block's own
  index already covers, so `gen` wrote an identical second index and doctor reported BS200
  duplicate indexes. `gen` now compares the btree column lists in the snapshot, ignores its own
  `*_page_idx` indexes, and skips a facet index the table already has (changeset, library test). Sort indexes are always
  written because the snapshot has no sort direction.
- The account health page (`/crm/success`) is not declared: it reads scores in memory through
  `loadedPager`, not through a block list, so there is no list function to plan.

## Alternatives considered

- Convert each overview to a generated page: the pages have dialogs, tabs and money cells the
  generator does not write, so the look would change.
- Add seed rows for the volume: the scale file plans each sort and facet on the index, which does
  not depend on the row count; the volume comes from `db:seed:scale`.

## Consequences

EX-607, EX-1265 and EX-1267 are fixed. Twenty scale files exist for the overviews, and they pass
on the local seed (72 assertions). The generated routes grow the Next.js server baselines by the
numbers CI reports. The next entity added to a tabbed page needs one more entry in
`overview-pages.ts`.
