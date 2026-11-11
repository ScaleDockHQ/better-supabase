# Example findings

Every bug, improvement and feature found while covering the block catalog in
`apps/examples/nextjs`, from the plan "Example SaaS coverage". Read this before
you change the example, and add a line when you find something.

## Rules

- One item per finding: an id (`EX-nnn`), the page that found it, the kind
  (bug, improvement, feature) and a state.
- A state is `open`, `fixed` with the PR, an ADR number, `measured away` with the
  number, or `deferred` with the reason.
- A bug that blocks a page is fixed in the same PR, with a library test and a
  changeset. Anything larger becomes its own to-do in the plan.
- Each PR description lists the findings it opened and closed.
- The format follows [`block-gaps.md`](block-gaps.md): one table per area.

## Library

| Id     | Found on  | Kind        | State                      | Item                                                                                                                                                                                                                                                     |
| ------ | --------- | ----------- | -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| EX-001 | Customers | improvement | open                       | Only customers reads through the server-side list (`defineListQuery`, now on the list kit); every other table still loads a capped list and filters in the browser                                                                                       |
| EX-002 | Customers | feature     | open                       | No generator renders a list query, its route and its columns per table                                                                                                                                                                                   |
| EX-003 | Customers | improvement | open                       | `defineListQuery` has a `filters` config that takes a ReUI filter tree, but customers declares only `facets`; the kit maps chips to facets, and a tree needs a second adapter                                                                            |
| EX-004 | Customers | bug         | fixed (this PR, changeset) | `useRecordListState` dropped facets: nuqs keeps `status=active` under its own key, but the hook passed that flat state to `toSearchParams`, which reads `facets`, so `searchParams` and `query` never held a facet and the list route returned every row |

## SQL and database

| Id     | Found on  | Kind        | State           | Item                                                                                                                                                                                                                                                                       |
| ------ | --------- | ----------- | --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| EX-010 | Risks     | bug         | open            | `risks` loads `db.risks.list({ limit: 200 })` and filters in the browser, so a tenant with more rows never sees the rest                                                                                                                                                   |
| EX-011 | Seed      | bug         | fixed (this PR) | The 1,000,000-row seed did not finish because of row triggers (ADR 0427). The tier seeder writes under a fixed import run, so `importing()` is true and the audit log keeps no row per insert; tier M loads in 5.6 s on the native stack                                   |
| EX-012 | Doctor    | improvement | open            | No doctor check that a list query's sorts, facets and search have an index                                                                                                                                                                                                 |
| EX-013 | Search    | improvement | open (phase 1)  | `search` is on for two subjects, so the command search finds customers only                                                                                                                                                                                                |
| EX-014 | Customers | improvement | open            | No `scale_list_<entity>.test.sql` yet for the customers list; the first list file lands with the first scale run in phase 11                                                                                                                                               |
| EX-015 | Customers | improvement | open            | At tier L (1,100,000 customers, dev server) a search by name takes 323 to 387 ms and the `newest` sort 513 ms, while the default page and a status filter take 15 to 19 ms: `search: ["name"]` is an unindexed `ilike` and there is no `(tenant_id, created_at, id)` index |
| EX-016 | Customers | improvement | open            | Facet counts at tier L are capped (`667+`, `333+`) by `facetCountMode: "capped"`, so the chips show lower bounds; fine for a filter, wrong for a dashboard number                                                                                                          |

## Next.js helpers

| Id     | Found on   | Kind        | State                           | Item                                                                                                                                                                                                                                                                                                                       |
| ------ | ---------- | ----------- | ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| EX-020 | All pages  | improvement | fixed (this PR), 109 pages open | Four of 111 pages export `instant = true`. The route manifest, a generated `expectInstant` case per instant page and a `check-app-architecture` rule now hold the contract; the 109 pages without it sit in `scripts/app-architecture-allow.json`                                                                          |
| EX-021 | All pages  | improvement | fixed (this PR), numbers open   | No per-page database budget or cold versus warm timing. `budgets.spec.ts`, `cold-warm.spec.ts` and `pnpm example:perf-report` exist; the budgets are ceilings per archetype until a seeded production build measures them                                                                                                  |
| EX-022 | Navigation | improvement | fixed (this PR)                 | 80 flat navigation items in three groups; they are twelve product areas now, and the area with the current page opens                                                                                                                                                                                                      |
| EX-023 | Navigation | bug         | fixed (this PR)                 | A collapsed area hides its links, which broke the specs that click a menu link; `navLink` in `tests/support/example-session.ts` opens the area first                                                                                                                                                                       |
| EX-024 | All pages  | improvement | deferred                        | `instantInsights.validationLevel` stays at `warning` until every page passes; raise it when the allow list is empty                                                                                                                                                                                                        |
| EX-025 | Customers  | bug         | open                            | `/customers` shows its error page when a note has an embedding: `getSimilarNotes` calls `db.$search` through `bsbShell`, and `db.$search is not a function` there. The seed holds three embedded notes; the check here ran with their embeddings set to null on the local stack. Not caused by this PR and not fixed in it |

## React helpers

| Id     | Found on        | Kind        | State              | Item                                                                                                                                                                                                                                    |
| ------ | --------------- | ----------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| EX-030 | Inbox, help     | improvement | open (phase 4)     | Conversation lists are hand-rolled `overflow-y-auto` containers; `MessageScroller`, `Message` and `Bubble` replace them                                                                                                                 |
| EX-031 | Customers       | improvement | fixed (this PR)    | The customers table filtered and searched the first page in the browser; it reads the list query from the URL and asks the list route for every other state                                                                             |
| EX-032 | Customer detail | improvement | deferred (phase 6) | The record sections (comments, attachments, relations, versions, timeline) still take `customerId`; contacts and deals need them generic over a subject                                                                                 |
| EX-033 | Customers       | improvement | open               | The grid sorts through a toolbar select because the lists have named sorts; header sorting needs a `freeSort` list                                                                                                                      |
| EX-034 | Customers       | improvement | open               | ReUI `Filters` drops an unfinished rule when the query is controlled from the URL, so the kit keeps the chips in local state and syncs on a URL change                                                                                  |
| EX-035 | Customer detail | improvement | deferred (phase 6) | The detail frame has a head, a main column, an aside and `AfterNavigation`, but no tabs (overview, activity, related, files): the first detail that needs them (contacts or deals) adds them, because knip fails on an unused component |

## Design system

| Id     | Found on   | Kind        | State           | Item                                                                                                                                                                                                                    |
| ------ | ---------- | ----------- | --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| EX-040 | All pages  | improvement | fixed (this PR) | The example built `cn` from `clsx` and `tailwind-merge`; `shadcn migrate cn` moved it to the `cn` package and the example drops both (the marketing app keeps them in the catalog)                                      |
| EX-041 | Components | bug         | fixed (this PR) | `calendar.tsx` and `highlighter.tsx` from the shadcn registry fail `exactOptionalPropertyTypes`; each carries a `@ts-nocheck` with the reason and the lint config ignores `highlighter.tsx` like the other copied files |
| EX-042 | Components | improvement | open            | `shadcn add` rewrites seven installed files (`button`, `card`, `dialog`, `input`, `input-group`, `separator`, `textarea`); only the `cn` import and the quote style changed                                             |
| EX-043 | Components | improvement | measured away   | The 21 installed parts are imported by no page yet, so no route's first load changes; the first change shows when phase 1 imports `Command`. No `next build` ran in this PR                                             |

## Tooling

| Id     | Found on   | Kind        | State           | Item                                                                                                                                                                                                                              |
| ------ | ---------- | ----------- | --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| EX-050 | shadcn MCP | improvement | open            | The shadcn MCP cannot see the ReUI registry from the repository root; names are confirmed with the CLI in `apps/examples/nextjs`                                                                                                  |
| EX-051 | Portless   | improvement | open            | `portless run` prefixes the branch name, so a worktree serves `https://<branch>.example.localhost`, not `https://example.localhost`                                                                                               |
| EX-052 | next-intl  | improvement | open            | Extraction adds new messages to `nl.po` with an empty `msgstr`, and nothing fails while one stays empty                                                                                                                           |
| EX-053 | Coverage   | feature     | fixed (this PR) | No map from catalog blocks and presets to screens; `pnpm check:example-coverage` fails for a block or preset without an entry or a listed route without a page. 123 blocks are on a screen, 10 have no UI and 52 wait for a phase |
| EX-054 | Seed       | bug         | fixed (this PR) | `supabase db query` prepares one statement, so a batch of begin, import session, insert and commit fails; the seeder talks to Postgres through `pg`                                                                               |
| EX-055 | Seed       | bug         | fixed (this PR) | Fixed row ids made a second tier collide with the rows of the first (a note pointed at a customer of another tenant); `--clean` removes the earlier tier first                                                                    |
| EX-056 | Worktree   | improvement | open            | A new worktree needs the git-ignored `supabase/signing_keys.json` and the env files before the stack and the app start; check whether `scripts/worktree-setup.ts` should copy them                                                |
