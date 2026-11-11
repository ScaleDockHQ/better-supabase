# Example findings

Every bug, improvement and feature found while covering the block catalog in
`apps/examples/nextjs`, from the plan "Example SaaS coverage". Read this before
you change the example, and add a line when you find something.

## Rules

- One item per finding: an id (`EX-nnn`), the page that found it, the kind
  (bug, improvement, feature) and a state.
- A state is `open`, `fixed` with the commit or PR, an ADR number, `measured away`
  with the number, or `deferred` with the reason.
- A bug that blocks a page is fixed in the same PR, with a library test and a
  changeset. Anything larger becomes its own to-do in the plan.
- Each PR description lists the findings it opened and closed.
- The format follows [`block-gaps.md`](block-gaps.md): one table per area.

## Library

| Id     | Found on  | Kind        | State | Item                                                                                                                           |
| ------ | --------- | ----------- | ----- | ------------------------------------------------------------------------------------------------------------------------------ |
| EX-001 | Customers | improvement | open  | Only customers uses the server-side list (`defineListQuery`); every other table loads a capped list and filters in the browser |
| EX-002 | Customers | feature     | open  | No generator renders a list query and its route per table                                                                      |

## SQL and database

| Id     | Found on | Kind        | State          | Item                                                                                                                                         |
| ------ | -------- | ----------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| EX-010 | Risks    | bug         | open           | `risks` loads `db.risks.list({ limit: 200 })` and filters in the browser, so a tenant with more rows never sees the rest                     |
| EX-011 | Seed     | bug         | open           | The 1,000,000-row seed does not finish because of row triggers (ADR 0427); the tiers in `seed-scale.ts` run inside `importing()` to avoid it |
| EX-012 | Doctor   | improvement | open           | No doctor check that a list query's sorts, facets and search have an index                                                                   |
| EX-013 | Search   | improvement | open (phase 1) | `search` is on for two subjects, so the command search finds customers only                                                                  |

## Next.js helpers

| Id     | Found on   | Kind        | State                 | Item                                                                                                                               |
| ------ | ---------- | ----------- | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| EX-020 | All pages  | improvement | open (route manifest) | Six pages export `instant = true` and `tests/instant.spec.ts` has three cases; the route manifest generates a case per route       |
| EX-021 | All pages  | improvement | open (budgets spec)   | No per-page database budget (`maxCalls`, `maxWaves`) and no cold versus warm timing in the example                                 |
| EX-022 | Navigation | improvement | fixed (this PR)       | 80 flat navigation items in three groups; they are now grouped into twelve product areas, and the area with the current page opens |

## React helpers

| Id     | Found on    | Kind        | State           | Item                                                                                                                                       |
| ------ | ----------- | ----------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| EX-030 | Inbox, help | improvement | open (phase 4)  | Conversation lists are hand-rolled `overflow-y-auto` containers; the chat primitives (`MessageScroller`, `Message`, `Bubble`) replace them |
| EX-031 | Customers   | improvement | fixed (this PR) | The customers table filtered and searched in the browser over the first page; it reads the list query from the URL and fetches pages       |

## Design system

| Id     | Found on   | Kind        | State           | Item                                                                                                                                                                                                                                                 |
| ------ | ---------- | ----------- | --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| EX-040 | All pages  | improvement | fixed (this PR) | The example built `cn` from `clsx` and `tailwind-merge`; `shadcn migrate cn` moved it to the `cn` package and the example drops both                                                                                                                 |
| EX-041 | Components | bug         | fixed (this PR) | `calendar.tsx` and `highlighter.tsx` from the shadcn registry fail the strict compiler options (`exactOptionalPropertyTypes`); they carry a `@ts-nocheck` with the reason, and the lint config ignores `highlighter.tsx` like the other copied files |
| EX-042 | Components | improvement | open            | `shadcn add` rewrites seven installed files (`button`, `card`, `dialog`, `input`, `input-group`, `separator`, `textarea`); only the `cn` import changed, so the diff is formatting noise                                                             |

## Tooling

| Id     | Found on   | Kind        | State           | Item                                                                                                                                                |
| ------ | ---------- | ----------- | --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| EX-050 | shadcn MCP | improvement | open            | The shadcn MCP cannot see the ReUI registry from the repository root; names are confirmed with the CLI in `apps/examples/nextjs`                    |
| EX-051 | Portless   | improvement | open            | `portless run` prefixes the branch name, so a worktree serves `https://<branch>.example.localhost` and not `https://example.localhost`              |
| EX-052 | next-intl  | improvement | open            | Extraction adds new messages to `nl.po` with an empty `msgstr`; a person fills them in by hand, and nothing fails when one stays empty              |
| EX-053 | Coverage   | feature     | fixed (this PR) | No map from catalog blocks and presets to screens; `pnpm check:example-coverage` now fails for a block or preset without an entry or a missing page |
