# 0012: Rename kits to blocks and import every feature module from `better-supabase/blocks`

- Status: accepted
- Date: 2026-10-09

## Context

Through 0.5 the feature modules (organizations, jobs, notifications,
billing and the rest) were called kits. The word meant three things at once:
the SQL kit (the modules `sql add` writes), the TypeScript side of a feature,
and the conformance kits in `better-supabase/testing`. The feature subpaths
sat at the top level next to primitives such as `list`, `storage` and
`realtime`, so the exports map gave no hint which entries own tables.

## Decision

A feature module is a block. Its SQL lives in one or more SQL modules, and
its TypeScript side imports from `better-supabase/blocks/<name>` (with
`/react` where it has hooks). The config keeps the modules to sync and their
settings in one place, `sql.modules`. Public names follow: `Kit` names that
describe a feature become `Block` names (`BlockRequireOptions`,
`BlockActionOptions`), and names that describe a SQL module become `Module`
names. The conformance kits in `better-supabase/testing` keep their name;
they are test kits, not features. Primitives every app uses (`list`,
`storage`, `realtime`, `streams`, `credentials`) stay at the top level.

The rename ships in 0.6 with the 0.5 to 0.6 migration guide.

## Alternatives considered

- Keep "kit" and document the three meanings. Agents and readers kept
  mixing them up, and the docs needed a disambiguation on every page.
- "Modules". It collides with the SQL modules a block is made of.
- Leave the subpaths at the top level and rename only the docs. The exports
  map would still not show which entries install tables.

## Consequences

`better-supabase/blocks/*` lists every feature that owns tables, and the
"A block" row in `AGENTS.md` applies to each. Every app on 0.5 changes its
imports and config once, following the migration guide.
`better-supabase codemod 0.6` renames the `Kit` and `Org` exports and lists
imports from the moved subpaths for review; it does not move imports or
rewrite config. Docs, skills and examples use "block" only; `pnpm verify`
does not check the word, so reviews have to.
